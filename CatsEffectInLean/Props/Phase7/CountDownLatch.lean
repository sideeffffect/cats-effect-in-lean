import CatsEffectInLean.Std.CountDownLatch
import CatsEffectInLean.Model.SchedP
import CatsEffectInLean.Model.WellFormed

/-!
# `std.CountDownLatch`: properties (Phase 7, track L)

Mirror: `Std/CountDownLatch.lean`. `CDL` = `std/shared/src/main/scala/cats/effect/std/CountDownLatch.scala`
at `v3.7.1`.

## Promise

Scaladoc (`CDL:23-27`, `:33-36`, `:39-41`):

> Concurrency abstraction that supports fiber blocking until n latches are released. Note that
> this has 'one-shot' semantics - once the counter reaches 0 then `release` and `await` will
> forever be no-ops.
>
> `release`: Release a latch, decrementing the remaining count and releasing any fibers that
> are blocked if the count reaches 0.
>
> `await`: Semantically block until the count reaches 0.

Read in context: an `await` returns only after `n` `release` calls (never earlier); after the
`n`-th `release`, every waiting `await` returns (no lost wakeup), also when other waiters were
canceled; a `release` after the count reached 0 does nothing (it completes, it does not fail or
block).

## Test program (harness)

`prog n` with user programs `ws` (one per awaiter fiber) and `us` (one per releaser fiber), and
a list `cancels` of awaiter indices. All closures of the harness are library-side (odd ids,
namespace `hns`, not public): they are the test, not user code.

1. Allocate the harness cells: `Ref` 0 = `started` (number of `release` calls that began),
   `Ref` 1 = `completed` (number that returned), `Ref` 2 = the awaiter status list (all `0`).
2. `CountDownLatch[IO](n)` (the mirror; `n < 1` throws `IllegalArgumentException`).
3. Start awaiter `j` for each `ws[j]`:
   `ws[j].attempt *> IO.uncancelable(poll => mark(j, 1) *> poll(l.await).onCancel(mark(j, 3)) *> mark(j, 2))`.
   Status `1` = entered `await`, `2` = `await` returned, `3` = canceled while in `poll`.
4. Start releaser `i` for each `us[i]`:
   `us[i].attempt *> IO.uncancelable(_ => started.update(_ + 1) *> l.release *> completed.update(_ + 1))`.
5. Cancel the awaiters in `cancels` (`fib.cancel`, in order; an index out of range is skipped),
   then join every awaiter and every releaser, and return `()`.

The user programs get no handle: not the latch, not a harness cell, not a fiber. The library
`cdlLib` lists the mirror closures of v3.7.1 (variant 0) only. They can raise,
suspend, wait forever, start fibers, cancel themselves, and use their own `Ref`s, `Deferred`s and
latches. `WellFormed` (decision 27) with `H0 = []` makes the harness cells private by
construction (a user `writeRef` needs a held `Ref`; a program that names a mirror closure that
captured the latch cell needs that cell).

Schedules: every `PChoice` list (preemption at every run-loop iteration, decisions 29, 36) and
every fuel. The cancels of step 5 can land at any point of the other fibers. The preemptive
scheduler has no outside cancel (decision 22); cancels come from the program (step 5) and from
the user programs (self-cancel).

## Statements

1. `cdlAwaitNotEarly`: in every reachable state, if an awaiter has status 2, then
   `started ≥ n`. Wrong function: a latch that opens one `release` early.
2. `cdlNoLostWakeup`: if the run is blocked (no task ready, no timer, the root not done) and
   `started ≥ n`, then no awaiter has status 1. Covers canceled awaiters (`cancels`) and
   self-canceled ones. Wrong function: a latch that never completes `signal`.
3. `cdlReleaseTotal`: if the run is blocked or the root is done, then `completed = started`:
   every `release` returned, also the ones after the count reached 0. Wrong function: a
   `release` that raises after `Done`.

No hypothesis except `WellFormed`. `n` is any natural number (for `n = 0` the harness root fails
with `IllegalArgumentException` before any fiber starts, so the statements hold trivially).
-/

namespace CatsEffectInLean.Props.Phase7.CountDownLatch

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.CountDownLatch (CLam)

/-- The namespace of the harness closures (track L: 70..79). -/
def hns : Nat := 74

/-- The harness lambdas. `l` is the latch value; `fa`/`fr` are the awaiter/releaser fibers so far
(`listV` of `fiber`); `cs` the cancel indices left (`listV` of `nat`). -/
inductive HLam where
  /-- The thunk that allocates `Ref` 0, 1 (`nat 0`) and 2 (`k` zeros). -/
  | newCells (k : Nat)
  /-- `_ => CountDownLatch[IO](n).flatMap(afterLatch)`. -/
  | afterCells (n v : Nat) (cs : Val)
  /-- `l => start awaiter 0 …`. -/
  | afterLatch (cs : Val)
  /-- `f => …`: awaiter `i` started as fiber `f`. -/
  | gotA (l : Val) (i : Nat) (fa cs : Val)
  /-- `f => …`: releaser `i` started as fiber `f`. -/
  | gotR (l : Val) (i : Nat) (fa fr cs : Val)
  /-- `_ => …` after a `cancel`. -/
  | afterCancel (fa fr cs : Val)
  /-- `_ => …` after a `join`. -/
  | afterJoin (rest : Val)
  /-- `_ => IO.uncancelable(awBody l j)` after `ws[j].attempt`. -/
  | awUnc (l : Val) (j : Nat)
  /-- `poll => mark(j, 1) *> …`. -/
  | awBody (l : Val) (j : Nat)
  /-- `_ => poll(l.await).onCancel(mark(j, 3)) *> mark(j, 2)`. -/
  | awEnter (l : Val) (j m p : Nat)
  /-- `_ => mark(j, 2)`. -/
  | awPass (j : Nat)
  /-- The thunk of `status.update(_.updated(j, s))` (`Ref` 2). -/
  | mark (j s : Nat)
  /-- `_ => IO.uncancelable(relBody l)` after `us[i].attempt`. -/
  | relUnc (l : Val)
  /-- `_ => started.update(_ + 1) *> l.release *> completed.update(_ + 1)`. -/
  | relBody (l : Val)
  /-- `_ => l.release *> completed.update(_ + 1)`. -/
  | relThen (l : Val)
  /-- `_ => completed.update(_ + 1)`. -/
  | relDone
  /-- The thunk of `Ref c` `update(_ + 1)`. -/
  | incr (c : Nat)
  deriving DecidableEq, Repr

def HLam.toVal : HLam → Val
  | .newCells k => cloVal hns 0 [.nat k]
  | .afterCells n v cs => cloVal hns 1 [.nat n, .nat v, cs]
  | .afterLatch cs => cloVal hns 2 [cs]
  | .gotA l i fa cs => cloVal hns 3 [l, .nat i, fa, cs]
  | .gotR l i fa fr cs => cloVal hns 4 [l, .nat i, fa, fr, cs]
  | .afterCancel fa fr cs => cloVal hns 5 [fa, fr, cs]
  | .afterJoin rest => cloVal hns 6 [rest]
  | .awUnc l j => cloVal hns 7 [l, .nat j]
  | .awBody l j => cloVal hns 8 [l, .nat j]
  | .awEnter l j m p => cloVal hns 9 [l, .nat j, .poll m p]
  | .awPass j => cloVal hns 10 [.nat j]
  | .mark j s => cloVal hns 11 [.nat j, .nat s]
  | .relUnc l => cloVal hns 12 [l]
  | .relBody l => cloVal hns 13 [l]
  | .relThen l => cloVal hns 14 [l]
  | .relDone => cloVal hns 15 []
  | .incr c => cloVal hns 16 [.nat c]

def HLam.ofFields : Nat → List Val → Option HLam
  | 0, [.nat k] => some (.newCells k)
  | 1, [.nat n, .nat v, cs] => some (.afterCells n v cs)
  | 2, [cs] => some (.afterLatch cs)
  | 3, [l, .nat i, fa, cs] => some (.gotA l i fa cs)
  | 4, [l, .nat i, fa, fr, cs] => some (.gotR l i fa fr cs)
  | 5, [fa, fr, cs] => some (.afterCancel fa fr cs)
  | 6, [rest] => some (.afterJoin rest)
  | 7, [l, .nat j] => some (.awUnc l j)
  | 8, [l, .nat j] => some (.awBody l j)
  | 9, [l, .nat j, .poll m p] => some (.awEnter l j m p)
  | 10, [.nat j] => some (.awPass j)
  | 11, [.nat j, .nat s] => some (.mark j s)
  | 12, [l] => some (.relUnc l)
  | 13, [l] => some (.relBody l)
  | 14, [l] => some (.relThen l)
  | 15, [] => some .relDone
  | 16, [.nat c] => some (.incr c)
  | _, _ => none

/-- Library-side closure (odd id). Not public: user code never holds it. -/
def HLam.fn (l : HLam) : Fn := libFn l.toVal

def HLam.ofId? (id : Nat) : Option HLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == hns then HLam.ofFields tag fs else none
    | none => none
  else none

/-! ## Harness programs -/

/-- `l.await` of a latch value (the mirror's `await`). -/
def awaitOf (l : Val) : IO :=
  match CatsEffectInLean.Std.CountDownLatch.latchOf? l with
  | some (r, _) => CatsEffectInLean.Std.CountDownLatch.awaitIO r
  | none => .error CatsEffectInLean.Std.CountDownLatch.illErr

/-- `l.release` of a latch value. -/
def releaseOf (l : Val) : IO :=
  match CatsEffectInLean.Std.CountDownLatch.latchOf? l with
  | some (r, v) => CatsEffectInLean.Std.CountDownLatch.releaseIO r v
  | none => .error CatsEffectInLean.Std.CountDownLatch.illErr

/-- Awaiter `j`: `ws[j].attempt *> IO.uncancelable(awBody l j)`. -/
def awaiterIO (ws : List IO) (l : Val) (j : Nat) : IO :=
  .flatMap (.attempt (ws.getD j (.pure .unit))) (HLam.awUnc l j).fn

/-- Releaser `i`: `us[i].attempt *> IO.uncancelable(relBody l)`. -/
def releaserIO (us : List IO) (l : Val) (i : Nat) : IO :=
  .flatMap (.attempt (us.getD i (.pure .unit))) (HLam.relUnc l).fn

/-- Join the fibers `fs` in order (`fib.join` reads `_join` now), then `()`. -/
def joinAll (w : View) : List Val → IO
  | .fiber t :: rest => .flatMap (IO.joinOf t (w.outcome t)) (HLam.afterJoin (listV rest)).fn
  | _ :: rest => joinAll w rest
  | [] => .pure .unit

/-- Cancel the awaiters with the indices `cs` (in order; out of range: skipped), then join all. -/
def cancelThenJoin (w : View) (fa fr : List Val) : List Val → IO
  | .nat c :: rest =>
    match fa[c]? with
    | some (.fiber t) =>
      .flatMap (IO.cancelOf t (w.outcome t)) (HLam.afterCancel (listV fa) (listV fr) (listV rest)).fn
    | _ => cancelThenJoin w fa fr rest
  | _ :: rest => cancelThenJoin w fa fr rest
  | [] => joinAll w (fa ++ fr)

/-- Start releaser `i` (or go on to the cancels). -/
def startR (us : List IO) (w : View) (l : Val) (i : Nat) (fa fr cs : List Val) : IO :=
  if i < us.length then
    .flatMap (.start (releaserIO us l i)) (HLam.gotR l i (listV fa) (listV fr) (listV cs)).fn
  else cancelThenJoin w fa fr cs

/-- Start awaiter `i` (or go on to the releasers). -/
def startA (ws us : List IO) (w : View) (l : Val) (i : Nat) (fa cs : List Val) : IO :=
  if i < ws.length then
    .flatMap (.start (awaiterIO ws l i)) (HLam.gotA l i (listV fa) (listV cs)).fn
  else startR us w l 0 fa [] cs

/-- The list in a value (`[]` for another shape). -/
def lst (x : Val) : List Val := (unlistV x).getD []

/-- The awaiter status list (`Ref` 2). -/
def statusesOf (refs : List Val) : List Val := lst (refs.getD 2 .unit)

/-- Run a harness closure. -/
def HLam.call (ws us : List IO) (h : HLam) (arg : Val) (w : View) : UserResult :=
  let bad : UserResult := { out := .throw CatsEffectInLean.Std.CountDownLatch.illErr }
  match h, arg with
  | .newCells k, _ =>
    { effects := [.allocRef (.nat 0), .allocRef (.nat 0), .allocRef (listV (List.replicate k (.nat 0)))],
      out := .ret .unit }
  | .afterCells n v cs, _ =>
    match CatsEffectInLean.Std.CountDownLatch.apply? n v with
    | some io => { out := .prog (.flatMap io (HLam.afterLatch cs).fn) }
    | none => { out := .throw CatsEffectInLean.Std.CountDownLatch.iaeErr }
  | .afterLatch cs, l => { out := .prog (startA ws us w l 0 [] (lst cs)) }
  | .gotA l i fa cs, .fiber f => { out := .prog (startA ws us w l (i + 1) (lst fa ++ [.fiber f]) (lst cs)) }
  | .gotR l i fa fr cs, .fiber f => { out := .prog (startR us w l (i + 1) (lst fa) (lst fr ++ [.fiber f]) (lst cs)) }
  | .afterCancel fa fr cs, _ => { out := .prog (cancelThenJoin w (lst fa) (lst fr) (lst cs)) }
  | .afterJoin rest, _ => { out := .prog (joinAll w (lst rest)) }
  | .awUnc l j, _ => { out := .prog (.uncancelable (HLam.awBody l j).fn) }
  | .awBody l j, .poll m p => { out := .prog (.flatMap (.delay (HLam.mark j 1).fn) (HLam.awEnter l j m p).fn) }
  | .awEnter l j m p, _ =>
    { out := .prog (.flatMap (.onCancel (IO.applyPoll (awaitOf l) m p) (.delay (HLam.mark j 3).fn))
        (HLam.awPass j).fn) }
  | .awPass j, _ => { out := .prog (.delay (HLam.mark j 2).fn) }
  | .mark j s, _ => { effects := [.writeRef 2 (listV ((statusesOf w.refs).set j (.nat s)))], out := .ret .unit }
  | .relUnc l, _ => { out := .prog (.uncancelable (HLam.relBody l).fn) }
  | .relBody l, _ => { out := .prog (.flatMap (.delay (HLam.incr 0).fn) (HLam.relThen l).fn) }
  | .relThen l, _ => { out := .prog (.flatMap (releaseOf l) HLam.relDone.fn) }
  | .relDone, _ => { out := .prog (.delay (HLam.incr 1).fn) }
  | .incr c, _ =>
    match w.refs.getD c .unit with
    | .nat x => { effects := [.writeRef c (.nat (x + 1))], out := .ret .unit }
    | _ => bad
  | _, _ => bad

/-- The test program: `prog n v ws cancels` (`v = 0`: Cats Effect v3.7.1). -/
def prog (n : Nat) (ws : List IO) (cancels : List Nat) (v : Nat := 0) : IO :=
  .flatMap (.delay (HLam.newCells ws.length).fn) (HLam.afterCells n v (listV (cancels.map .nat))).fn

/-! ## Environment and run -/

/-- The variant of a mirror closure (`0` = Cats Effect v3.7.1). -/
def clamVariant : CLam → Nat
  | .refK v | .mkLatch v | .obj _ v | .relBody _ v | .relModify _ v => v
  | _ => 0

/-- The library of the statements: the mirror closures of Cats Effect v3.7.1 (variant 0). User
code may name them; `WellFormed` requires their captured handles to be available, so a program
that does not hold a latch's state cell cannot name the closures that use it. The variants
(wrong functions) and the harness closures are not public. -/
def isLibV0 (id : Nat) : Bool :=
  match CLam.ofId? id with
  | some l => clamVariant l == 0
  | none => false

/-- The `WellFormed` library (decision 58: references are followed structurally). -/
@[reducible] def cdlLib : Lib := Lib.idFree isLibV0

/-- Dispatch: mirror closures, harness closures, then user code `u`. -/
def dispatch (ws us : List IO) (u : UserEnv) (id : Nat) (arg : Val) (w : View) : UserResult :=
  match CLam.ofId? id with
  | some l => CatsEffectInLean.Std.CountDownLatch.call l arg w
  | none =>
    match HLam.ofId? id with
    | some h => h.call ws us arg w
    | none => u.callV id arg w

/-- The user environment of the statements. -/
def env (ws us : List IO) (u : UserEnv) : UserEnv where
  call id arg refs := dispatch ws us u id arg { refs }
  callV := dispatch ws us u

/-- The final state: `fuel` micro-steps of the preemptive scheduler with choices `cs`, default
`Config`, `IOFiber` mask model. -/
def run (ws us : List IO) (u : UserEnv) (n : Nat) (cancels : List Nat) (fuel : Nat)
    (cs : List PChoice) (v : Nat := 0) : Sched CounterMask :=
  runSchedStateP {} counterMaskModel (env ws us u) fuel cs (Sched.init counterMaskModel (prog n ws cancels v))

/-! ## Observations (harness cells only) -/

/-- A natural number in a cell (`0` for another shape). -/
def natAt (refs : List Val) (c : Nat) : Nat :=
  match refs.getD c .unit with
  | .nat x => x
  | _ => 0

/-- `started` (`Ref` 0). -/
def started {M : Type} (s : Sched M) : Nat := natAt s.liveHeap.refs 0

/-- `completed` (`Ref` 1). -/
def completed {M : Type} (s : Sched M) : Nat := natAt s.liveHeap.refs 1

/-- The status of awaiter `j` (`Ref` 2). -/
def status {M : Type} (s : Sched M) (j : Nat) : Nat :=
  match (statusesOf s.liveHeap.refs)[j]? with
  | some (.nat x) => x
  | _ => 0

/-- The user programs are well-formed (decision 27). -/
def AllWF (ws us : List IO) (u : UserEnv) : Prop :=
  ∀ p ∈ ws ++ us, WellFormed cdlLib [] (env ws us u) p

/-! ## Statements -/

/-- Statement 1: an `await` returns only after `n` `release` calls began. -/
def cdlAwaitNotEarly : Prop :=
  ∀ (u : UserEnv) (n : Nat) (ws us : List IO) (cancels : List Nat), AllWF ws us u →
    ∀ (fuel : Nat) (cs : List PChoice) (j : Nat),
      status (run ws us u n cancels fuel cs) j = 2 → n ≤ started (run ws us u n cancels fuel cs)

/-- Statement 2: no lost wakeup. A blocked run after `n` `release` calls has no awaiter in
`await`. -/
def cdlNoLostWakeup : Prop :=
  ∀ (u : UserEnv) (n : Nat) (ws us : List IO) (cancels : List Nat), AllWF ws us u →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run ws us u n cancels fuel cs).halt = some .blocked →
      n ≤ started (run ws us u n cancels fuel cs) →
      ∀ j, status (run ws us u n cancels fuel cs) j ≠ 1

/-- Statement 3: every `release` returns (also after the count reached 0). -/
def cdlReleaseTotal : Prop :=
  ∀ (u : UserEnv) (n : Nat) (ws us : List IO) (cancels : List Nat), AllWF ws us u →
    ∀ (fuel : Nat) (cs : List PChoice),
      ((run ws us u n cancels fuel cs).halt = some .blocked ∨
        ∃ oc, (run ws us u n cancels fuel cs).halt = some (.done oc)) →
      completed (run ws us u n cancels fuel cs) = started (run ws us u n cancels fuel cs)

end CatsEffectInLean.Props.Phase7.CountDownLatch

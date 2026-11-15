import CatsEffectInLean.Std.CyclicBarrier
import CatsEffectInLean.Model.SchedP
import CatsEffectInLean.Model.WellFormed

/-!
# `std.CyclicBarrier`: properties (Phase 7, track L)

Mirror: `Std/CyclicBarrier.lean`. `CB` = `std/shared/src/main/scala/cats/effect/std/CyclicBarrier.scala`
at `v3.7.1`.

## Promise

Scaladoc (`CB:24-34`, `:37-40`):

> A synchronization abstraction that allows a set of fibers to wait until they all reach a
> certain point. A cyclic barrier is initialized with a positive integer capacity n and a fiber
> waits by calling `await`, at which point it is semantically blocked until a total of n fibers
> are blocked on the same cyclic barrier. At this point all the fibers are unblocked and the
> cyclic barrier is reset, allowing it to be used again.
>
> `await`: Possibly semantically block until the cyclic barrier is full.

The code comment at `CB:77-78` adds the cancel rule: "reincrement count if this await gets
canceled, but only if the barrier hasn't reset in the meantime". Read in context: the barrier
trips only when `capacity` fibers wait on it (never earlier); each trip releases one generation;
after a trip, the waiting fibers of that generation all return (no lost wakeup); a canceled
`await` is removed from the count, so it neither trips the barrier early nor makes it hang, and a
cancel never changes the count of a later generation.

## Test program (harness)

`prog cap as bs cancels` with user programs `as` (group A awaiters), `bs` (group B awaiters) and
a list `cancels` of group A indices. All harness closures are library-side (odd ids, namespace
`hns`, not public).

1. Allocate `Ref` 0 = the status list (one `0` per awaiter; index `j` for `as[j]`, index
   `as.length + j` for `bs[j]`).
2. `CyclicBarrier[IO](cap)` (the mirror; `cap < 1` throws `IllegalArgumentException`).
3. Start awaiter `j` of group A for each `as[j]`:
   `as[j].attempt *> IO.uncancelable(poll => mark(j, 1) *> poll(b.await).onCancel(mark(j, 3)) *> mark(j, 2))`.
   Status `1` = entered `await`, `2` = `await` returned, `3` = canceled while in `poll`.
4. Cancel the group A awaiters in `cancels` (`fib.cancel`, in order; it waits for the
   finalizers; an index out of range is skipped).
5. Start the group B awaiters (the same body), then join every awaiter and return `()`.

The user programs get no handle (not the barrier, not the status cell, not a fiber); they can
raise, suspend, wait forever, start fibers, cancel themselves, and use their own state.
`WellFormed` with `H0 = []` makes the status cell private (decision 54). Schedules: every
`PChoice` list and every fuel (decisions 29, 36).

Counts (all from the status list): `entered` = status ≥ 1, `passed` = status 2, `waiting` =
status 1, `canceledIn` = status 3.

## Statements

1. `cbNoEarlyTrip` (no program cancel: `cancels = []`): in every reachable state,
   `passed ≤ cap * (entered / cap)`. Each trip needs `cap` fibers in `await`. Wrong function:
   a barrier that trips at `cap - 1`.
2. `cbExactGenerations` (`cancels = []`): if the run is blocked, `passed` is a multiple of `cap`
   and `waiting < cap`: every full generation was released, and fewer than `cap` fibers wait.
   Wrong function: a barrier that never completes `unblock`.
3. `cbCancelNoHang` (any `cancels`): if the run is blocked, `waiting < cap`. A canceled `await`
   is removed from its own generation only. Wrong functions: no epoch check (a cancel that loses
   the race with a trip re-increments the next generation, which then needs `cap + 1`).
4. `cbCancelRemoved` (any `cancels`, hypothesis `as.length < cap`): in every reachable state,
   `passed ≤ cap * ((entered - canceledIn) / cap)`. With fewer than `cap` group A awaiters, the
   barrier cannot trip before group B starts, and group B starts after every cancel returned; so
   every awaiter with status 3 left the count. Wrong function: a cleanup that does not
   re-increment (the canceled awaiter still counts, and the barrier trips early).

5. `cbAwaitCompletes` (decision 63, item 3: the companion success claim): for `cap ≥ 1`, if the
   root is done, it is `Succeeded(())` (review batch 13, H4), and `waiting = 0`: every `await`
   that began returned or was canceled; none ended with an error. Wrong functions: an `await`
   or `apply` that raises.
6. `cbNoDeadlock` (review batch 13, H4): for `cap ≥ 1`, `cap * g` group A awaiters with user
   programs `IO.pure(())`, no group B and no cancels, the run is never blocked. Wrong functions:
   an `apply` or `await` that never returns.

Decision 63 battery (`Proofs/Phase7/LatchBattery.lean`): every wrong `await` (raises, hangs,
drops, doubles; variants of `Std/CyclicBarrier.lean`) breaks one of the five statements.
`cbXV v` below is statement X with mirror variant `v` (`cbX = cbXV 0`).

Why the hypothesis of statement 4: with `as.length ≥ cap` a cancel can lose the race with a trip
(the awaiter was released, but `poll` sees the cancel first); then it has status 3 and still
counted for the trip, so the bound would be false for every correct barrier. That race is
covered by statement 3. The hypothesis restricts the test program, not Cats Effect.
-/

namespace CatsEffectInLean.Props.Phase7.CyclicBarrier

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.CyclicBarrier (BLam)

/-- The namespace of the harness closures (track L: 70..79). -/
def hns : Nat := 75

/-- The harness lambdas. `b` is the barrier value; `fa`/`fb` the fibers of group A/B so far
(`listV` of `fiber`); `cs` the cancel indices left (`listV` of `nat`). -/
inductive HLam where
  /-- The thunk that allocates `Ref` 0 (`k` zeros). -/
  | newCells (k : Nat)
  /-- `_ => CyclicBarrier[IO](cap).flatMap(afterBarrier)`. -/
  | afterCells (cap v : Nat) (cs : Val)
  /-- `b => start awaiter 0 …`. -/
  | afterBarrier (cs : Val)
  /-- `f => …`: group A awaiter `i` started as fiber `f`. -/
  | gotA (b : Val) (i : Nat) (fa cs : Val)
  /-- `_ => …` after a `cancel`. -/
  | afterCancel (b fa cs : Val)
  /-- `f => …`: group B awaiter `i` started as fiber `f`. -/
  | gotB (b : Val) (i : Nat) (fa fb : Val)
  /-- `_ => …` after a `join`. -/
  | afterJoin (rest : Val)
  /-- `_ => IO.uncancelable(awBody b j)` after the user program. -/
  | awUnc (b : Val) (j : Nat)
  /-- `poll => mark(j, 1) *> …`. -/
  | awBody (b : Val) (j : Nat)
  /-- `_ => poll(b.await).onCancel(mark(j, 3)) *> mark(j, 2)`. -/
  | awEnter (b : Val) (j m p : Nat)
  /-- `_ => mark(j, 2)`. -/
  | awPass (j : Nat)
  /-- The thunk of `status.update(_.updated(j, s))` (`Ref` 0). -/
  | mark (j s : Nat)
  deriving DecidableEq, Repr

def HLam.toVal : HLam → Val
  | .newCells k => cloVal hns 0 [.nat k]
  | .afterCells cap v cs => cloVal hns 1 [.nat cap, .nat v, cs]
  | .afterBarrier cs => cloVal hns 2 [cs]
  | .gotA b i fa cs => cloVal hns 3 [b, .nat i, fa, cs]
  | .afterCancel b fa cs => cloVal hns 4 [b, fa, cs]
  | .gotB b i fa fb => cloVal hns 5 [b, .nat i, fa, fb]
  | .afterJoin rest => cloVal hns 6 [rest]
  | .awUnc b j => cloVal hns 7 [b, .nat j]
  | .awBody b j => cloVal hns 8 [b, .nat j]
  | .awEnter b j m p => cloVal hns 9 [b, .nat j, .poll m p]
  | .awPass j => cloVal hns 10 [.nat j]
  | .mark j s => cloVal hns 11 [.nat j, .nat s]

def HLam.ofFields : Nat → List Val → Option HLam
  | 0, [.nat k] => some (.newCells k)
  | 1, [.nat cap, .nat v, cs] => some (.afterCells cap v cs)
  | 2, [cs] => some (.afterBarrier cs)
  | 3, [b, .nat i, fa, cs] => some (.gotA b i fa cs)
  | 4, [b, fa, cs] => some (.afterCancel b fa cs)
  | 5, [b, .nat i, fa, fb] => some (.gotB b i fa fb)
  | 6, [rest] => some (.afterJoin rest)
  | 7, [b, .nat j] => some (.awUnc b j)
  | 8, [b, .nat j] => some (.awBody b j)
  | 9, [b, .nat j, .poll m p] => some (.awEnter b j m p)
  | 10, [.nat j] => some (.awPass j)
  | 11, [.nat j, .nat s] => some (.mark j s)
  | _, _ => none

/-- Library-side closure (odd id). Not public. -/
def HLam.fn (h : HLam) : Fn := libFn h.toVal

def HLam.ofId? (id : Nat) : Option HLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == hns then HLam.ofFields tag fs else none
    | none => none
  else none

/-! ## Harness programs -/

/-- `b.await` of a barrier value (the mirror's `await`). -/
def awaitOf (b : Val) : IO :=
  match CatsEffectInLean.Std.CyclicBarrier.barrierOf? b with
  | some (r, cap, v) => CatsEffectInLean.Std.CyclicBarrier.awaitIO r cap v
  | none => .error CatsEffectInLean.Std.CyclicBarrier.illErr

/-- The user program of awaiter `j` (group A first, then group B). -/
def userOf (as bs : List IO) (j : Nat) : IO :=
  if j < as.length then as.getD j (.pure .unit) else bs.getD (j - as.length) (.pure .unit)

/-- Awaiter `j`: `userOf j .attempt *> IO.uncancelable(awBody b j)`. -/
def awaiterIO (as bs : List IO) (b : Val) (j : Nat) : IO :=
  .flatMap (.attempt (userOf as bs j)) (HLam.awUnc b j).fn

/-- Join the fibers `fs` in order, then `()`. -/
def joinAll (w : View) : List Val → IO
  | .fiber t :: rest => .flatMap (IO.joinOf t (w.outcome t)) (HLam.afterJoin (listV rest)).fn
  | _ :: rest => joinAll w rest
  | [] => .pure .unit

/-- Start group B awaiter `i` (or join all). -/
def startB (as bs : List IO) (w : View) (b : Val) (i : Nat) (fa fb : List Val) : IO :=
  if i < bs.length then
    .flatMap (.start (awaiterIO as bs b (as.length + i))) (HLam.gotB b i (listV fa) (listV fb)).fn
  else joinAll w (fa ++ fb)

/-- Cancel the group A awaiters with the indices `cs` (in order; out of range: skipped), then
start group B. -/
def cancelThenB (as bs : List IO) (w : View) (b : Val) (fa : List Val) : List Val → IO
  | .nat c :: rest =>
    match fa[c]? with
    | some (.fiber t) => .flatMap (IO.cancelOf t (w.outcome t)) (HLam.afterCancel b (listV fa) (listV rest)).fn
    | _ => cancelThenB as bs w b fa rest
  | _ :: rest => cancelThenB as bs w b fa rest
  | [] => startB as bs w b 0 fa []

/-- Start group A awaiter `i` (or go on to the cancels). -/
def startA (as bs : List IO) (w : View) (b : Val) (i : Nat) (fa cs : List Val) : IO :=
  if i < as.length then
    .flatMap (.start (awaiterIO as bs b i)) (HLam.gotA b i (listV fa) (listV cs)).fn
  else cancelThenB as bs w b fa cs

/-- The list in a value (`[]` for another shape). -/
def lst (x : Val) : List Val := (unlistV x).getD []

/-- The status list (`Ref` 0). -/
def statusesOf (refs : List Val) : List Val := lst (refs.getD 0 .unit)

/-- Run a harness closure. -/
def HLam.call (as bs : List IO) (h : HLam) (arg : Val) (w : View) : UserResult :=
  let bad : UserResult := { out := .throw CatsEffectInLean.Std.CyclicBarrier.illErr }
  match h, arg with
  | .newCells k, _ => { effects := [.allocRef (listV (List.replicate k (.nat 0)))], out := .ret .unit }
  | .afterCells cap v cs, _ =>
    match CatsEffectInLean.Std.CyclicBarrier.apply? cap v with
    | some io => { out := .prog (.flatMap io (HLam.afterBarrier cs).fn) }
    | none => { out := .throw CatsEffectInLean.Std.CyclicBarrier.iaeErr }
  | .afterBarrier cs, b => { out := .prog (startA as bs w b 0 [] (lst cs)) }
  | .gotA b i fa cs, .fiber f => { out := .prog (startA as bs w b (i + 1) (lst fa ++ [.fiber f]) (lst cs)) }
  | .afterCancel b fa cs, _ => { out := .prog (cancelThenB as bs w b (lst fa) (lst cs)) }
  | .gotB b i fa fb, .fiber f => { out := .prog (startB as bs w b (i + 1) (lst fa) (lst fb ++ [.fiber f])) }
  | .afterJoin rest, _ => { out := .prog (joinAll w (lst rest)) }
  | .awUnc b j, _ => { out := .prog (.uncancelable (HLam.awBody b j).fn) }
  | .awBody b j, .poll m p => { out := .prog (.flatMap (.delay (HLam.mark j 1).fn) (HLam.awEnter b j m p).fn) }
  | .awEnter b j m p, _ =>
    { out := .prog (.flatMap (.onCancel (IO.applyPoll (awaitOf b) m p) (.delay (HLam.mark j 3).fn))
        (HLam.awPass j).fn) }
  | .awPass j, _ => { out := .prog (.delay (HLam.mark j 2).fn) }
  | .mark j s, _ => { effects := [.writeRef 0 (listV ((statusesOf w.refs).set j (.nat s)))], out := .ret .unit }
  | _, _ => bad

/-- The test program (`v = 0`: Cats Effect v3.7.1). -/
def prog (cap : Nat) (as bs : List IO) (cancels : List Nat) (v : Nat := 0) : IO :=
  .flatMap (.delay (HLam.newCells (as.length + bs.length)).fn)
    (HLam.afterCells cap v (listV (cancels.map .nat))).fn

/-! ## Environment and run -/

/-- The variant of a mirror closure (`0` = Cats Effect v3.7.1). -/
def blamVariant : BLam → Nat
  | .mkBarrier _ v | .obj _ _ v | .gateK _ _ v | .fmfBody _ _ _ v | .modifyThunk _ _ _ _ _ v
  | .cleanupThunk _ _ v => v
  -- not Cats Effect code (battery variant 6 only): never public
  | .neverK => 1
  | _ => 0

/-- The library of the statements: the mirror closures of Cats Effect v3.7.1 (variant 0). User
code may name them; their captured handles must be available. The variants and the harness
closures are not public. -/
def isLibV0 (id : Nat) : Bool :=
  match BLam.ofId? id with
  | some l => blamVariant l == 0
  | none => false

/-- The `WellFormed` library (decision 58). -/
@[reducible] def cbLib : Lib := Lib.idFree isLibV0

/-- Dispatch: mirror closures, harness closures, then user code `u`. -/
def dispatch (as bs : List IO) (u : UserEnv) (id : Nat) (arg : Val) (w : View) : UserResult :=
  match BLam.ofId? id with
  | some l => CatsEffectInLean.Std.CyclicBarrier.call l arg w
  | none =>
    match HLam.ofId? id with
    | some h => h.call as bs arg w
    | none => u.callV id arg w

/-- The user environment of the statements. -/
def env (as bs : List IO) (u : UserEnv) : UserEnv where
  call id arg refs := dispatch as bs u id arg { refs }
  callV := dispatch as bs u

/-- The final state: `fuel` micro-steps of the preemptive scheduler with choices `cs`. -/
def run (as bs : List IO) (u : UserEnv) (cap : Nat) (cancels : List Nat) (fuel : Nat)
    (cs : List PChoice) (v : Nat := 0) : Sched CounterMask :=
  runSchedStateP {} counterMaskModel (env as bs u) fuel cs (Sched.init counterMaskModel (prog cap as bs cancels v))

/-! ## Observations (the status cell only) -/

/-- The statuses. -/
def statuses {M : Type} (s : Sched M) : List Nat :=
  (statusesOf s.liveHeap.refs).map fun x => match x with | .nat k => k | _ => 0

/-- Number of awaiters with status `k`. -/
def countSt {M : Type} (s : Sched M) (k : Nat) : Nat := ((statuses s).filter (· == k)).length

/-- Awaiters that entered `await` (status ≥ 1). -/
def entered {M : Type} (s : Sched M) : Nat := ((statuses s).filter (1 ≤ ·)).length

/-- Awaiters whose `await` returned. -/
def passed {M : Type} (s : Sched M) : Nat := countSt s 2

/-- Awaiters in `await` (entered, not returned, not canceled). -/
def waiting {M : Type} (s : Sched M) : Nat := countSt s 1

/-- Awaiters canceled in `poll(b.await)`. -/
def canceledIn {M : Type} (s : Sched M) : Nat := countSt s 3

/-- The user programs are well-formed (decision 27). -/
def AllWF (as bs : List IO) (u : UserEnv) : Prop :=
  ∀ p ∈ as ++ bs, WellFormed cbLib [] (env as bs u) p

/-! ## Statements -/

/-- Statement 1: without program cancels, every trip needs `cap` fibers in `await`. -/
def cbNoEarlyTrip : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO), AllWF as bs u →
    ∀ (fuel : Nat) (cs : List PChoice),
      passed (run as bs u cap [] fuel cs) ≤ cap * (entered (run as bs u cap [] fuel cs) / cap)

/-- Statement 2: without program cancels, a blocked run released only full generations, and
fewer than `cap` fibers wait. -/
def cbExactGenerations : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO), AllWF as bs u →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run as bs u cap [] fuel cs).halt = some .blocked →
      passed (run as bs u cap [] fuel cs) % cap = 0 ∧ waiting (run as bs u cap [] fuel cs) < cap

/-- Statement 3: with program cancels, a blocked run has fewer than `cap` fibers in `await`. -/
def cbCancelNoHang : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO) (cancels : List Nat), AllWF as bs u →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run as bs u cap cancels fuel cs).halt = some .blocked → waiting (run as bs u cap cancels fuel cs) < cap

/-- Statement 4: a canceled `await` leaves the count (cancels before any trip is possible). -/
def cbCancelRemoved : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO) (cancels : List Nat), AllWF as bs u → as.length < cap →
    ∀ (fuel : Nat) (cs : List PChoice),
      passed (run as bs u cap cancels fuel cs) ≤
        cap * ((entered (run as bs u cap cancels fuel cs) - canceledIn (run as bs u cap cancels fuel cs)) / cap)

/-- Statement 5 (decision 63, item 3; review 13 H4): for `cap ≥ 1`, a done root is
`Succeeded(())`, and no `await` is left open. -/
def cbAwaitCompletes : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO) (cancels : List Nat), AllWF as bs u → 1 ≤ cap →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run as bs u cap cancels fuel cs).halt = some (.done oc) →
      oc = .succeeded .unit ∧ waiting (run as bs u cap cancels fuel cs) = 0

/-- Statement 6 (review 13 H4): for `cap ≥ 1` and `cap * g` awaiters with user programs
`IO.pure(())`, no run is blocked. -/
def cbNoDeadlock : Prop :=
  ∀ (u : UserEnv) (cap g : Nat), AllWF (List.replicate (cap * g) (.pure .unit)) [] u → 1 ≤ cap →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run (List.replicate (cap * g) (.pure .unit)) [] u cap [] fuel cs).halt ≠ some .blocked

/-! ## The statements with a mirror variant (decision 63 battery; `v = 0` gives the statements) -/

def cbNoEarlyTripV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO), AllWF as bs u →
    ∀ (fuel : Nat) (cs : List PChoice),
      passed (run as bs u cap [] fuel cs v) ≤ cap * (entered (run as bs u cap [] fuel cs v) / cap)

def cbExactGenerationsV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO), AllWF as bs u →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run as bs u cap [] fuel cs v).halt = some .blocked →
      passed (run as bs u cap [] fuel cs v) % cap = 0 ∧ waiting (run as bs u cap [] fuel cs v) < cap

def cbAwaitCompletesV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (cap : Nat) (as bs : List IO) (cancels : List Nat), AllWF as bs u → 1 ≤ cap →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run as bs u cap cancels fuel cs v).halt = some (.done oc) →
      oc = .succeeded .unit ∧ waiting (run as bs u cap cancels fuel cs v) = 0

def cbNoDeadlockV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (cap g : Nat), AllWF (List.replicate (cap * g) (.pure .unit)) [] u → 1 ≤ cap →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run (List.replicate (cap * g) (.pure .unit)) [] u cap [] fuel cs v).halt ≠ some .blocked

end CatsEffectInLean.Props.Phase7.CyclicBarrier

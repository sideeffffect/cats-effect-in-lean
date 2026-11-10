import CatsEffectInLean.Model.Memoize
import CatsEffectInLean.Model.SchedP
import CatsEffectInLean.Model.WellFormed

/-!
# `IO#memoize`: properties (Phase 6, track M)

Mirror: `Model/Memoize.lean` (`IO#memoize` = kernel `GenConcurrent#memoize` with `IOAsync`;
no `IO` twin). `K/` = `kernel/shared/src/main/scala/cats/effect/kernel/` at `v3.7.1`.

## Promise

Scaladoc of `GenConcurrent#memoize` (`K/GenConcurrent.scala:33-42`):

> Caches the result of `fa`. The returned inner effect, hence referred to as `get`, when
> sequenced, will evaluate `fa` and cache the result. If `get` is sequenced multiple times `fa`
> will only be evaluated once. If all `get`s are canceled prior to `fa` completing, it will be
> canceled and evaluated again the next time `get` is sequenced.

Read in context: every `get` gives the cached result; `fa` runs once while no `get` is
canceled; a `get` never waits for an evaluation that is already finished. The test suite says
the same (`tests/shared/src/test/scala/cats/effect/MemoizeSuite.scala:106-117`: `memoize` then
`flatten` is `fa`, also for a self-canceling `fa`).

## Test program (decision 50: only program fibers)

`twoGets v` = `fa.memoize.flatMap(get => get.start.flatMap(a => get.start.flatMap(b =>
a.join.flatMap(oa => b.join.map(ob => (oa, ob))))))`: two fibers run `get` at the same time,
the root waits for both. `countedTwoGets` first makes a counter `c = Ref(0)` and memoizes
`c.update(_ + 1) *> fa` instead of `fa`. The test-program lambdas are library-side closures
(odd ids, namespace `tns`): they are the harness, not user code, so `WellFormed` does not
restrict them, and user code cannot reach the counter.

## Statements

All `fa` that are `WellFormed` with the library closures (decision 27), all user code `u`, all
fuel values and all `PChoice` lists (`EqvP` schedules: preemption at any run-loop iteration,
decisions 29 and 36). The state cell of the memo is `Ref` 0 in `twoGets` (the first cell that
the program makes); the counter is `Ref` 0 and the memo cell `Ref` 1 in `countedTwoGets`.

1. `memoizeNoStuckGet`: if the run is blocked (no task ready, no timer, the root not done),
   the memo is not `Finished`. With a finished evaluation, every `get` has its result, so a
   blocked run means an evaluation that did not finish. Refuted (CE-0030).
2. `memoizeGetsAgree`: if the root completes with `(oa, ob)`, then `oa = ob`: two concurrent
   `get`s observe the same outcome. Open.
3. `memoizeAtMostOnce`: in `countedTwoGets` (no cancel from the program), the counter is at
   most 1 in every reachable state: `fa` starts at most once. Open.

Wrong-function tests (`Proofs/Phase6/MemoizeStuck.lean`, `test/Phase6/MemoizeSmoke.lean`): a
`memoize` that runs `fa` for each `get` gives counter 2 (statement 3) and different outcomes
for a counting `fa` (statement 2).
-/

namespace CatsEffectInLean.Props.Phase6.Memoize

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Memoize

/-- The namespace of the test-program closures (track M: 30..39). -/
def tns : Nat := 32

/-- The lambdas of the test programs. -/
inductive TLam where
  /-- `get => get.start.flatMap(a => …)`. -/
  | afterMemo
  /-- `a => get.start.flatMap(b => …)`. -/
  | afterA (get : Val)
  /-- `b => a.join.flatMap(oa => …)`: `a.join` reads `_join` now. -/
  | afterB (a : Nat)
  /-- `oa => b.join.map(ob => (oa, ob))` (`b` in the closure). -/
  | thenJoin (b : Nat)
  /-- `ob => (oa, ob)`. -/
  | pairWith (oa : Val)
  /-- The thunk of `Ref.unsafe(0)` (the counter). -/
  | newCounter
  /-- `c => (c.update(_ + 1) *> fa).memoize.flatMap(afterMemo)`. -/
  | afterCounter (variant : Nat)
  /-- The thunk of `c.update(_ + 1)`. -/
  | incr (c : Nat)
  /-- `_ => fa` of that `*>`. -/
  | constFa
  deriving DecidableEq, Repr

def TLam.toVal : TLam → Val
  | .afterMemo => cloVal tns 0 []
  | .afterA get => cloVal tns 1 [get]
  | .afterB a => cloVal tns 2 [.fiber a]
  | .thenJoin b => cloVal tns 3 [.fiber b]
  | .pairWith oa => cloVal tns 4 [oa]
  | .newCounter => cloVal tns 5 []
  | .afterCounter variant => cloVal tns 6 [.nat variant]
  | .incr c => cloVal tns 7 [.ref c]
  | .constFa => cloVal tns 8 []

def TLam.ofFields : Nat → List Val → Option TLam
  | 0, [] => some .afterMemo
  | 1, [get] => some (.afterA get)
  | 2, [.fiber a] => some (.afterB a)
  | 3, [.fiber b] => some (.thenJoin b)
  | 4, [oa] => some (.pairWith oa)
  | 5, [] => some .newCounter
  | 6, [.nat variant] => some (.afterCounter variant)
  | 7, [.ref c] => some (.incr c)
  | 8, [] => some .constFa
  | _, _ => none

/-- Library-side closure (odd id). -/
def TLam.fn (l : TLam) : Fn := libFn l.toVal

def TLam.ofId? (id : Nat) : Option TLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == tns then TLam.ofFields tag fs else none
    | none => none
  else none

/-- The source builder: code `0` is `fa`; code `ref c` is `c.update(_ + 1) *> fa`. -/
def srcIO (fa : IO) : Val → IO
  | .nat 0 => fa
  | .ref c => .flatMap (.delay (TLam.incr c).fn) TLam.constFa.fn
  | _ => .error { code := 999999, kind := .fatal }

/-- Run a test-program closure. -/
def TLam.call (fa : IO) (l : TLam) (arg : Val) (v : View) : UserResult :=
  let bad : UserResult := { out := .throw { code := 999999, kind := .fatal } }
  match l, arg with
  | .afterMemo, get =>
    match getOfVal? get with
    | some g => { out := .prog (.flatMap (.start g) (TLam.afterA get).fn) }
    | none => bad
  | .afterA get, .fiber a =>
    match getOfVal? get with
    | some g => { out := .prog (.flatMap (.start g) (TLam.afterB a).fn) }
    | none => bad
  | .afterB a, .fiber b => { out := .prog (.flatMap (IO.joinOf a (v.outcome a)) (TLam.thenJoin b).fn) }
  | .thenJoin b, oa => { out := .prog (.map (IO.joinOf b (v.outcome b)) (TLam.pairWith oa).fn) }
  | .pairWith oa, ob => { out := .ret (.pair oa ob) }
  | .newCounter, _ => { effects := [.allocRef (.nat 0)], out := .ret (.ref v.refs.length) }
  | .afterCounter variant, .ref c =>
    { out := .prog (.flatMap (memoizeIO (.ref c) variant) TLam.afterMemo.fn) }
  | .incr c, _ =>
    match v.refs.getD c .unit with
    | .nat n => { effects := [.writeRef c (.nat (n + 1))], out := .ret .unit }
    | _ => bad
  | .constFa, _ => { out := .prog fa }
  | _, _ => bad

/-- The `Bracket` leaf closures that `IO#guaranteeCase` uses (`reportError`, `raiseK`, `asK`). -/
def bracketLeaf? (id : Nat) : Option Bracket.BLam :=
  match Bracket.BLam.ofId? id with
  | some l@(.reportK) | some l@(.reportEc _) | some l@(.reportThunk _) | some l@(.raiseK _)
  | some l@(.asK _) => some l
  | _ => none

/-- The `never` closures (`Timeout.neverIO`). -/
def timeoutOf? (id : Nat) : Option Timeout.TLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == Timeout.ns then Timeout.TLam.ofFields tag fs else none
    | none => none
  else none

/-- Library closures (`WellFormed`): the mirror, its leaf closures and the test programs. -/
def isLib (id : Nat) : Bool := CatsEffectInLean.Model.Memoize.isLib id || (TLam.ofId? id).isSome

private def noUser : Nat → Val → View → UserResult := fun _ _ _ =>
  { out := .throw { code := 999999, kind := .fatal } }

/-- Dispatch: mirror closures, leaf closures, test-program closures, then user code `u`. -/
def dispatch (fa : IO) (u : UserEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match MLam.ofId? id with
  | some l => CatsEffectInLean.Model.Memoize.call (srcIO fa) l arg v
  | none =>
    match bracketLeaf? id with
    | some l => Bracket.call noUser (fun _ => .pure .unit) l arg v
    | none =>
      match timeoutOf? id with
      | some l => Timeout.call (srcIO fa) l arg v
      | none =>
        match TLam.ofId? id with
        | some l => l.call fa arg v
        | none => u.callV id arg v

/-- The user environment of the statements. -/
def env (fa : IO) (u : UserEnv) : UserEnv where
  call id arg refs := dispatch fa u id arg { refs }
  callV := dispatch fa u

/-- `twoGets v`: `fa.memoize` (variant `v`; 0 = Cats Effect v3.7.1), then two `get` fibers. -/
def twoGets (variant : Nat := 0) : IO := .flatMap (memoizeIO (.nat 0) variant) TLam.afterMemo.fn

/-- `Ref(0).flatMap(c => (c.update(_ + 1) *> fa).memoize.flatMap(…))`. -/
def countedTwoGets (variant : Nat := 0) : IO :=
  .flatMap (.delay TLam.newCounter.fn) (TLam.afterCounter variant).fn

/-- The final state: `fuel` micro-steps of the preemptive scheduler with choices `cs`, default
`Config`, `IOFiber` mask model. -/
def run (fa : IO) (u : UserEnv) (fuel : Nat) (cs : List PChoice) (io : IO) : Sched CounterMask :=
  runSchedStateP {} counterMaskModel (env fa u) fuel cs (Sched.init counterMaskModel io)

/-- The memo in cell `r` is `Finished`. -/
def memoFinished {M : Type} (s : Sched M) (r : Nat) : Bool :=
  match St.ofVal (s.liveHeap.refs.getD r .unit) with
  | .finished _ => true
  | _ => false

/-- The counter (cell 0) of `countedTwoGets`. -/
def counter {M : Type} (s : Sched M) : Nat :=
  match s.liveHeap.refs.getD 0 .unit with
  | .nat n => n
  | _ => 0

/-- Statement 1 (refuted, CE-0030): a blocked run never has a finished memo. -/
def memoizeNoStuckGet : Prop :=
  ∀ (u : UserEnv) (fa : IO), WellFormed isLib [] (env fa u) fa →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run fa u fuel cs (twoGets 0)).halt = some .blocked →
      memoFinished (run fa u fuel cs (twoGets 0)) 0 = false

/-- Statement 2 (open): two concurrent `get`s observe the same outcome. -/
def memoizeGetsAgree : Prop :=
  ∀ (u : UserEnv) (fa : IO), WellFormed isLib [] (env fa u) fa →
    ∀ (fuel : Nat) (cs : List PChoice) (oa ob : Val),
      (run fa u fuel cs (twoGets 0)).halt = some (.done (.succeeded (.pair oa ob))) → oa = ob

/-- Statement 3 (open): without a cancel from the program, `fa` starts at most once. -/
def memoizeAtMostOnce : Prop :=
  ∀ (u : UserEnv) (fa : IO), WellFormed isLib [] (env fa u) fa →
    ∀ (fuel : Nat) (cs : List PChoice), counter (run fa u fuel cs (countedTwoGets 0)) ≤ 1

end CatsEffectInLean.Props.Phase6.Memoize

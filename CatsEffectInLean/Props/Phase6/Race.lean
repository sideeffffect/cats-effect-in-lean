import CatsEffectInLean.Model.Race
import CatsEffectInLean.Model.Leak
import CatsEffectInLean.Model.Outcomes
import CatsEffectInLean.Model.WellFormed
import CatsEffectInLean.Model.IOInstance

/-!
# `race`, `raceOutcome`, `both`, `bothOutcome`, `timeout`: no leaked fiber (Phase 6, track R)

`IO.scala` = `core/shared/src/main/scala/cats/effect/IO.scala`, `K/` =
`kernel/shared/src/main/scala/cats/effect/kernel/` at `v3.7.1`. Mirrors:
`Model/Race.lean` (the four kernel defaults with `IOAsync`), `Model/Timeout.lean`
(`IO#timeout`), on the `IOFiber` mirror (`RacePair`, `_cancel`, `_join`). Leak observation:
`Model/Leak.lean` (`liveRaceChildren`).

## Promise

* `K/GenSpawn.scala:358-360` (`raceOutcome`): "The loser of the race is canceled before
  returning."
* `K/GenSpawn.scala:380-385` (`race`), rules 1 and 2: "The loser is canceled before returning."
* `K/GenSpawn.scala:430-432` (`bothOutcome`) and rule 7 of `both` (`K/GenSpawn.scala:459-460`):
  "If the race is canceled before one or both participants complete, then whichever ones are
  incomplete are canceled."
* `IO.scala:801-802` (`timeout`): "The resulting effect will always wait for the source effect to
  complete (and to complete its finalizers)".
* `GenSpawn` cancel is backpressured: `f.cancel` returns after the fiber's finalizers ran
  (`IOFiber.scala:142-175`, `_cancel` joins). So "canceled before returning" means "terminated
  before returning".

The undisputed invariant (source (b) of `AGENTS.md`): no fiber that the combinator starts is
still alive when the combinator's result is delivered. The cut is the root completion
(decision 33): the root is the combinator itself, or (decision 50) a parent that starts the
combinator in a fiber, cancels it and joins it.

## Statements

* Inputs: all programs `fa`, `fb` (the two sides; for `timeout`, the source `fa` and every
  duration `d`), all user code `u` (every closure id that is not a mirror closure), all fuel
  values and all `PChoice` lists of the preemptive scheduler (`EqvP` schedules, decisions 29
  and 36). The only hypotheses: `fa` and `fb` are `WellFormed` with the library closures of the
  mirrors (decision 27: Scala can write them; no forged handle).
* The sides are given to the mirror closures by their codes `.nat 0` and `.nat 1` (`srcIO`).
* Claim: if the root completes (`Sched.rootDone`), the racing fiber has no live race child
  (`liveRaceChildren s r = []`, `r = 0` for the direct form, `r = 1` for the parent form).
* No claim for runs that end otherwise (out of fuel, blocked, model abort).

## Wrong-function test

A `race` that never cancels the loser (`Model/RaceSmoke.lean`, `raceNoCancel`) falsifies the
statement on `race(pure 1, never)`: the root completes with fiber 2 live. Checked by
`decide +kernel` (`RaceSmoke.noCancel_leaks`).
-/

namespace CatsEffectInLean.Props.Phase6.Race

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the closures of the test programs below (user code, even ids). -/
def ns : Nat := 11

/-- Code of side `fa` / `fb`. -/
def src0 : Val := .nat 0
def src1 : Val := .nat 1

/-- The source builder: code `0` is `fa`, code `1` is `fb`. -/
def srcIO (fa fb : IO) : Val → IO
  | .nat 0 => fa
  | .nat 1 => fb
  | _ => .error { code := 999999, kind := .fatal }

/-- The parent of decision 50: `comb.start.flatMap(f => f.cancel *> f.join)`. -/
inductive PLam where
  /-- `f => f.cancel.flatMap(_ => f.join)`. -/
  | afterStart
  /-- `_ => f.join`. -/
  | afterCancel (f : Nat)
  deriving DecidableEq, Repr

def PLam.toVal : PLam → Val
  | .afterStart => cloVal ns 0 []
  | .afterCancel f => cloVal ns 1 [.fiber f]

def PLam.ofFields : Nat → List Val → Option PLam
  | 0, [] => some .afterStart
  | 1, [.fiber f] => some (.afterCancel f)
  | _, _ => none

/-- User closure (even id). -/
def PLam.fn (l : PLam) : Fn := userFn l.toVal

/-- Run a parent closure. -/
def PLam.call (l : PLam) (arg : Val) (v : View) : UserResult :=
  match l, arg with
  -- `f.cancel` reads `_cancel` now; `*> f.join`: `f.join` reads `_join` one iteration later
  | .afterStart, .fiber f => { out := .prog (.flatMap (IO.cancelOf f (v.outcome f)) (PLam.afterCancel f).fn) }
  | .afterCancel f, _ => { out := .prog (IO.joinOf f (v.outcome f)) }
  | _, _ => { out := .throw { code := 999999, kind := .fatal } }

/-- The mirror closure of an id (race or timeout), if it is one. -/
def timeoutOf? (id : Nat) : Option Timeout.TLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == Timeout.ns then Timeout.TLam.ofFields tag fs else none
    | none => none
  else none

/-- The parent closure of an id, if it is one. -/
def parentOf? (id : Nat) : Option PLam :=
  if isLibId id then none
  else
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then PLam.ofFields tag fs else none
    | none => none

/-- Library closures (`WellFormed`): the race and timeout mirrors. -/
def isLib (id : Nat) : Bool := (Race.ofId? id).isSome || (timeoutOf? id).isSome

/-- Dispatch: mirror closures, then the parent closures, then user code `u`. -/
def dispatch (fa fb : IO) (u : UserEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match Race.ofId? id with
  | some l => Race.call (srcIO fa fb) l arg v
  | none =>
    match timeoutOf? id with
    | some t => Timeout.call (srcIO fa fb) t arg v
    | none =>
      match parentOf? id with
      | some p => p.call arg v
      | none => u.callV id arg v

/-- The user environment of the statements. -/
def env (fa fb : IO) (u : UserEnv) : UserEnv where
  call id arg refs := dispatch fa fb u id arg { refs }
  callV := dispatch fa fb u

/-- The final state of a run of `io`: `fuel` micro-steps of the preemptive scheduler with
choices `cs`, default `Config`, `IOFiber` mask model. -/
def run (fa fb : IO) (u : UserEnv) (fuel : Nat) (cs : List PChoice) (io : IO) : Sched CounterMask :=
  runSchedStateP {} counterMaskModel (env fa fb u) fuel cs (Sched.init counterMaskModel io)

/-- The parent program of decision 50 around `io`. -/
def parentIO (io : IO) : IO := .flatMap (.start io) PLam.afterStart.fn

/-- No leak for root program `io` with racing fiber `r`. -/
def NoLeak (fa fb : IO) (u : UserEnv) (io : IO) (r : Nat) : Prop :=
  ∀ (fuel : Nat) (cs : List PChoice),
    (run fa fb u fuel cs io).rootDone = true → liveRaceChildren (run fa fb u fuel cs io) r = []

/-- `fa.race(fb)`, `fa.raceOutcome(fb)`, `fa.both(fb)`, `fa.bothOutcome(fb)` as the root: when
the root completes, no child of its `racePair` is alive. All four kernel defaults (`k`), all
sides, all user code, all schedules. -/
def combNoLeak : Prop :=
  ∀ (k : Race.Kind) (u : UserEnv) (fa fb : IO),
    WellFormed isLib [] (env fa fb u) fa → WellFormed isLib [] (env fa fb u) fb →
    NoLeak fa fb u (Race.combIO k src0 src1) 0

/-- Decision 50: a parent starts the combinator in fiber 1, cancels it and joins it. When the
root completes, fiber 1 has no live race child. -/
def combCanceledNoLeak : Prop :=
  ∀ (k : Race.Kind) (u : UserEnv) (fa fb : IO),
    WellFormed isLib [] (env fa fb u) fa → WellFormed isLib [] (env fa fb u) fb →
    NoLeak fa fb u (parentIO (Race.combIO k src0 src1)) 1

/-- `fa.timeout(d)` as the root, and (decision 50) in a fiber that a parent cancels: when the
root completes, the timeout's `racePair` has no live child (the source and the sleep). -/
def timeoutNoLeak : Prop :=
  ∀ (d : Nat) (u : UserEnv) (fa : IO),
    WellFormed isLib [] (env fa fa u) fa →
    NoLeak fa fa u (Timeout.timeoutIO src0 d) 0 ∧
    NoLeak fa fa u (parentIO (Timeout.timeoutIO src0 d)) 1

/-- The outcome of fiber `i` in state `s`. -/
def fiberOutcome {M : Type} (s : Sched M) (i : Nat) : Option Outcome :=
  (s.liveFibers[i]?).bind (·.outcome)

/-- `raceOutcome` returns the winner's outcome (`K/GenSpawn.scala:358-360`, `:372-375`): when
the root `fa.raceOutcome(fb)` completes with `Succeeded(Left(oc))`, fiber 1 (the fiber of `fa`)
ended with `oc`; with `Succeeded(Right(oc))`, fiber 2 (the fiber of `fb`) ended with `oc`. -/
def raceOutcomeIsWinnerOutcome : Prop :=
  ∀ (u : UserEnv) (fa fb : IO),
    WellFormed isLib [] (env fa fb u) fa → WellFormed isLib [] (env fa fb u) fb →
    ∀ (fuel : Nat) (cs : List PChoice) (v : Val),
      let s := run fa fb u fuel cs (Race.raceOutcomeIO src0 src1)
      s.halt = some (.done (.succeeded v)) →
      (∃ oc, v = .left oc ∧ (fiberOutcome s 1).map Outcome.toVal = some oc) ∨
      (∃ oc, v = .right oc ∧ (fiberOutcome s 2).map Outcome.toVal = some oc)

/-! ## A closed `GenSpawn` law for `IO`

`laws/shared/src/main/scala/cats/effect/laws/GenSpawnLaws.scala:146-147`:
`F.uncancelable(_ => F.race(F.never[Unit], F.canceled)).void <-> F.never[Unit]`.

The law has no input: no `fa`, no user code. Its lambda `_ => F.race(...)` is part of the law
text, so the environment is fixed (`lawEnv`): the race and timeout mirror closures and this
lambda. `F.race` = `asyncForIO.race` (`Model/Race.lean`), `F.never` = `Timeout.neverIO`,
`F.canceled` = `Canceled`, `.void` = `map(_ => ())` (`IO.scala:961-962`, `IOI.void`),
`F.uncancelable` = `Uncancelable`. `<->` = `EqvP` (default `Config`, `counterMaskModel`). -/

/-- The law lambda `_ => F.race(F.never[Unit], F.canceled)` (user closure, even id). -/
def raceBodyFn : Fn := userFn (cloVal ns 2 [])

/-- `lawEnv`: `F.never` is side `0`, `F.canceled` is side `1`. -/
def lawEnv : UserEnv :=
  let u : UserEnv :=
    { call := fun _ _ _ => { out := .throw { code := 999999, kind := .fatal } }
      callV := fun id _ _ =>
        if raceBodyFn = .user id then { out := .prog (Race.raceIO src0 src1) }
        else { out := .throw { code := 999999, kind := .fatal } } }
  env Timeout.neverIO .canceled u

/-- Left side of `uncancelableRaceNotInherited`. -/
def raceNotInheritedLhs : IO := IOI.void (.uncancelable raceBodyFn)

/-- `GenSpawnLaws.uncancelableRaceNotInherited` at `IO`. -/
def uncancelableRaceNotInherited : Prop :=
  EqvP {} counterMaskModel lawEnv raceNotInheritedLhs Timeout.neverIO

end CatsEffectInLean.Props.Phase6.Race

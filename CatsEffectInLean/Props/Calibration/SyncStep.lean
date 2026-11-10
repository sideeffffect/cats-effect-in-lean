import CatsEffectInLean.Model.SyncStep
import CatsEffectInLean.Model.WellFormed

/-!
# `syncStepIdentity` for `IO` with `G = SyncIO` (CE-0001)

The law `AsyncLaws.syncStepIdentity`
(`laws/shared/src/main/scala/cats/effect/laws/AsyncLaws.scala:84-88` at `v3.7.1`):

```scala
F.syncStep(fa, limit).flatMap { case Left(fa) => fa; case Right(a) => F.pure(a) } <-> fa
```

The Scaladoc of `IO#syncStep` (`core/shared/src/main/scala/cats/effect/IO.scala:1154-1160`)
says that the `SyncIO` "runs the original `IO` to its completion, the `limit` number of stages,
or until the first stage that cannot be expressed with `SyncIO`". So the `Left` value is the
rest of the original `IO`, and "step, then run the rest" must act as "run the original".

The law suite checks the law only with `G = F = IO` (root cancel scope `Cancelable`). The
public method `IO#syncStep(limit)` uses `G = SyncIO` (`IO.scala:1161-1162`). This file states
the law for that method.

## Statement

* `fa`, `limit`, the user code `env` and the initial `Ref` cells `refs`: all values, with two
  hypotheses.
  * The type invariant `WellFormed` (`CatsEffectInLean/Model/WellFormed.lean`, decisions 27
    and 37): `fa` and `env` are a program that Scala can write. User code treats `Poll` values
    as opaque, so it cannot tell `IdPoll` from the poll of the run loop. The `Ref` cells `refs`
    exist before `fa` starts, so all of `fa` can hold them (`H0 = refHandles refs`), and their
    values hold no other handles (`initialRefsOK`). Plain `IO`: no library closures.
  * The domain `NonFatalOnly` (decision 38): `fa` and the user code raise and throw only
    non-fatal errors (`UnsafeNonFatal`, `core/shared/src/main/scala/cats/effect/unsafe/UnsafeNonFatal.scala:37-41`).
    A fatal error is not an ordinary input: the run loops of `IO` and `SyncIO` treat
    `raiseError(fatal)` differently (`IOFiber.scala:265-269` calls `onFatalFailure`;
    `SyncIO.scala:257-259` has no check). That is a separate defect, CE-0004
    (`bugs/CE-0004.yaml`). In 2019 a maintainer wrote that `IO(throw e) <-> IO.raiseError(e)`
    "only holds if `e` is non-fatal" (typelevel/cats-effect#549). With fatal errors in the
    domain, the statement is false also for a `syncStep` that keeps the masks (review batch 2,
    entry 5), so it would not isolate CE-0001.
* "stepped" = `fa.syncStep(limit).unsafeRunSync()`, then the selected `IO`
  (`SyncStepObs.steppedObs`); "direct" = `fa` (`SyncStepObs.directObs`). Both `IO` runs are the
  root fiber of the single-fiber driver (`IOFiber` mirror, `counterMaskModel`, default
  config), under a schedule `steps bs`: only `step` choices; `bs` picks the `observe` flag of
  each step. No external cancel (decision 26): the law compares two programs that run alone
  (decision 22), and with an external cancel a correct `syncStep` also fails the statement
  (a cancel before `run()` stops `fa`, but the `SyncIO` prefix of the stepped side already
  ran; `review/2026-11-10-review-batch-1.md`, entry 5). Cancelation from the program itself
  (`IO.canceled`) stays.
* The single-fiber driver is enough here (decision 23): `syncStep` is a single-fiber method,
  and the witness starts no fiber. Limit: a child that `fa` starts never runs, so for a
  program with `start` the driver can show `suspended` where the real runtime goes on.
* `<->`: same observations over all schedules, both ways. An observation is
  (summary, `Ref` cells, emitted values), with each `Poll` value replaced by one fixed `Poll`
  (`eraseObs`). Scala can tell two `Poll` objects apart only by object identity, which no law
  observes; the run loop and `syncStep` give the body different `Poll` objects by design. For
  each run of one side that makes a claim (not out of fuel, not a model abort), some run of the
  other side gives the same observation. The stepped side also has a `SyncIO` fuel; out of fuel
  there is "no claim".

Choice (documented in `wiki/cats-effect/syncio-and-syncstep-model.md`): the shared outcome
equivalence `Eqv` (planned in `Model/Enum.lean`) is not in this worktree, so the statement
uses the run observations directly.
-/

namespace CatsEffectInLean.Props.Calibration

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs

/-- The handles of the `Ref` cells `refs` (ids `0 .. refs.length - 1`). -/
def refHandles (refs : List Val) : List Handle := (List.range refs.length).map Handle.ref

/-- The values in the initial `Ref` cells hold only handles of these cells (Scala: before the
program starts there are no fibers, `Deferred`s, polls or callbacks of it). -/
def initialRefsOK (refs : List Val) : Bool :=
  refs.all fun x => x.handles.all fun h => (refHandles refs).contains h

/-- A schedule of the single-fiber driver with no external cancel: one `step` choice per
`observe` flag. -/
def steps (bs : List Bool) : List SoloChoice := bs.map .step

/-- Does a program raise only non-fatal errors? Each `IO.raiseError(e)` node (`Error`) has a
non-fatal `e` (`Err.isNonFatal` = `UnsafeNonFatal`). -/
def progNonFatal : IO → Bool
  | .error e => e.isNonFatal
  | .map p _ | .flatMap p _ | .handleErrorWith p _ | .attempt p | .start p | .evalOn p _
  | .unmaskRunLoop p _ _ => progNonFatal p
  | .onCancel p q | .racePair p q => progNonFatal p && progNonFatal q
  | _ => true

/-- The domain of CE-0001 (decision 38): the start program and all programs and throws of user
code have only non-fatal errors. -/
def NonFatalOnly (env : UserEnv) (fa : IO) : Prop :=
  progNonFatal fa = true ∧
  ∀ (id : Nat) (arg : Val) (v : View),
    match (env.callV id arg v).out with
    | .throw e => e.isNonFatal = true
    | .prog p => progNonFatal p = true
    | .ret _ => True

/-- The renaming that maps every `Poll` to one fixed `Poll`. -/
def erasePoll : WF.PollRen := fun _ _ => (0, 0)

/-- An observation with each `Poll` value replaced by one fixed `Poll`. -/
def eraseObs (o : Obs) : Obs :=
  let s := match o.1 with
    | .done oc => .done (WF.rnOutcome erasePoll oc)
    | s => s
  (s, o.2.1.map (WF.rnVal erasePoll), o.2.2.map (WF.rnVal erasePoll))

/-- The two directions of `<->` for one program, with `stepped` the observation function of the
stepped side (`steppedObs` for v3.7.1; the fixed twin uses its own). -/
def StepIdentityFor (stepped : Nat → List SoloChoice → Obs) (env : UserEnv) (fa : IO)
    (refs : List Val) : Prop :=
  (∀ bs : List Bool, isClaim (directObs env fa refs (steps bs)).1 = true →
    ∃ (fuel : Nat) (bs' : List Bool),
      eraseObs (stepped fuel (steps bs')) = eraseObs (directObs env fa refs (steps bs))) ∧
  (∀ (fuel : Nat) (bs : List Bool),
    isClaim (stepped fuel (steps bs)).1 = true →
    ∃ bs' : List Bool, eraseObs (directObs env fa refs (steps bs')) =
      eraseObs (stepped fuel (steps bs)))

/-- `AsyncLaws.syncStepIdentity` (`AsyncLaws.scala:84-88`) for `IO#syncStep` with
`G = SyncIO`, for non-fatal errors: the stepped program and `fa` have the same observations
(up to `Poll` identity) over all schedules without an external cancel. -/
def syncStepIdentitySyncIO : Prop :=
  ∀ (env : UserEnv) (fa : IO) (limit : Int) (refs : List Val),
    initialRefsOK refs = true →
    WellFormed (fun _ => false) (refHandles refs) env fa →
    NonFatalOnly env fa →
    StepIdentityFor (steppedObs env fa limit refs) env fa refs

end CatsEffectInLean.Props.Calibration

import CatsEffectInLean.Props.Calibration.SyncStep

/-!
# `IO` and `SyncIO` on `raiseError(e).handleErrorWith(_ => pure(1))` (CE-0004)

The two run loops handle the `Error` node differently at `v3.7.1`:

* `IO` (`core/shared/src/main/scala/cats/effect/IOFiber.scala:263-269`, mirrored at
  `Model/Step.lean`, `Error` branch): `if (!UnsafeNonFatal(ex)) onFatalFailure(ex)`. A fatal
  error shuts down all runtimes and is rethrown (`IOFiber.scala:1597-1646`); no handler sees it.
  Added by PR #3811 (issue #3767, 2023).
* `SyncIO` (`core/shared/src/main/scala/cats/effect/SyncIO.scala:257-259`, mirrored at
  `Model/SyncIO.lean`, `runLoop`, `.error`): `runLoop(failed(cur.t, 0))`, with no check. A
  fatal error is an ordinary error, and `handleErrorWith` catches it.

`IO#syncStep(limit)` (`IO.scala:1161-1162`) runs the start of an `IO` in the `SyncIO` run loop.
So `IO.raiseError(e).handleErrorWith(_ => IO.pure(1))` gives one result when it runs directly
and another one when it runs through `syncStep` (`AsyncLaws.syncStepIdentity`,
`laws/shared/src/main/scala/cats/effect/laws/AsyncLaws.scala:84-88`). The same split shows in
`SyncIO#to[IO]` (`SyncIO.scala:190-208`): it translates `SyncIO.Error(t)` to `IO.raiseError(t)`,
so `sio.unsafeRunSync()` and `sio.to[IO]` disagree (`reproducers/CE-0004/Repro.scala`).

## Statement

`raiseErrorTwin`: for every error `e` (fatal or not), the program
`IO.raiseError(e).handleErrorWith(_ => IO.pure(1))` with `limit = Int.MaxValue` and no `Ref`
cells satisfies `StepIdentityFor` (`Props/Calibration/SyncStep.lean`: same observations over
all step-only schedules, both ways). The program has no `uncancelable` and no `onCancel`, so
CE-0001 cannot occur in it. The user code is fixed (the handler `_ => IO.pure(1)`, user id 0);
it is a well-formed program (`WellFormedIO`).

`raiseErrorTwinNonFatal`: the same for non-fatal `e` only (the ordinary inputs, `AGENTS.md`
section 6).
-/

namespace CatsEffectInLean.Props.Calibration

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs

/-- User code: id 0 is the handler `_ => IO.pure(1)`. Other ids return `()`. -/
def handlerEnv : UserEnv where
  call id _ _ := if id = 0 then { out := .prog (.pure (.nat 1)) } else { out := .ret .unit }

/-- `IO.raiseError(e).handleErrorWith(_ => IO.pure(1))`: `Error(e)` (`IO.scala:1652`) and
`HandleErrorWith` (`IO.scala:549-550`). -/
def raiseHandled (e : Err) : IO := .handleErrorWith (.error e) (.user 0)

/-- `Int.MaxValue`. -/
def maxIntLimit : Int := 2147483647

/-- CE-0004: for every error `e`, `IO.raiseError(e).handleErrorWith(_ => IO.pure(1))` gives the
same observations directly (`IO` run loop) and through `syncStep(Int.MaxValue)` (`SyncIO` run
loop). -/
def raiseErrorTwin : Prop :=
  ∀ e : Err, StepIdentityFor (steppedObs handlerEnv (raiseHandled e) maxIntLimit [])
    handlerEnv (raiseHandled e) []

/-- `raiseErrorTwin` for non-fatal errors only. -/
def raiseErrorTwinNonFatal : Prop :=
  ∀ e : Err, e.isNonFatal = true →
    StepIdentityFor (steppedObs handlerEnv (raiseHandled e) maxIntLimit [])
      handlerEnv (raiseHandled e) []

end CatsEffectInLean.Props.Calibration

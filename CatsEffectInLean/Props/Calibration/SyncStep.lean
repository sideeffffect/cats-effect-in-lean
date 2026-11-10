import CatsEffectInLean.Model.SyncStep

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

* `fa`, `limit`, the user code `env` and the initial `Ref` cells `refs`: all values, no
  hypotheses. (The witness of the refutation uses only public constructors, so it also
  refutes each restriction to public programs.)
* "stepped" = `fa.syncStep(limit).unsafeRunSync()`, then the selected `IO`
  (`SyncStepObs.steppedObs`); "direct" = `fa` (`SyncStepObs.directObs`). Both `IO` runs are the
  root fiber of the single-fiber driver (`IOFiber` mirror, `counterMaskModel`, default
  config), under a schedule `cs : List SoloChoice`. A schedule picks the `observe` flag of
  each step and the points where another fiber cancels the root (external cancel).
* `<->`: same observations over all schedules, both ways. An observation is
  (summary, `Ref` cells, emitted values). For each run of one side that makes a claim (not
  out of fuel, not a model abort), some run of the other side gives the same observation.
  The stepped side also has a `SyncIO` fuel; out of fuel there is "no claim".

Choice (documented in `wiki/cats-effect/syncio-and-syncstep-model.md`): the shared outcome
equivalence `Eqv` (planned in `Model/Enum.lean`) is not in this worktree, so the statement
uses the run observations directly.
-/

namespace CatsEffectInLean.Props.Calibration

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs

/-- `AsyncLaws.syncStepIdentity` (`AsyncLaws.scala:84-88`) for `IO#syncStep` with
`G = SyncIO`: the stepped program and `fa` have the same observations over all schedules. -/
def syncStepIdentitySyncIO : Prop :=
  ∀ (env : UserEnv) (fa : IO) (limit : Int) (refs : List Val),
    (∀ cs : List SoloChoice, isClaim (directObs env fa refs cs).1 = true →
      ∃ (fuel : Nat) (cs' : List SoloChoice),
        steppedObs env fa limit refs fuel cs' = directObs env fa refs cs) ∧
    (∀ (fuel : Nat) (cs : List SoloChoice), isClaim (steppedObs env fa limit refs fuel cs).1 = true →
      ∃ cs' : List SoloChoice, directObs env fa refs cs' = steppedObs env fa limit refs fuel cs)

end CatsEffectInLean.Props.Calibration

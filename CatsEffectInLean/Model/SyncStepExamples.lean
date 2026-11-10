import CatsEffectInLean.Model.SyncStep

/-!
# Hand examples for `SyncIO` and `IO#syncStep`

Each example mirrors a `syncStep` test of the Cats Effect suite
(`tests/shared/src/test/scala/cats/effect/IOSuite.scala:2577-2700` at `v3.7.1`) or one branch
of `SyncStep.interpret` (`core/shared/src/main/scala/cats/effect/IO.scala:2348-2402`). All are
checked by `decide +kernel`.
-/

namespace CatsEffectInLean.Model.SyncStepExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs

/-- `UserError(1)`. -/
def e1 : Err := { code := 1 }

/-- The user code of the examples. -/
def env : UserEnv where
  call
    -- `IO(i += 1)` on `Ref` cell 0
    | 10, _, refs =>
      match refs with
      | .nat n :: _ => { effects := [.writeRef 0 (.nat (n + 1))], out := .ret .unit }
      | _ => { out := .ret .unit }
    -- `_ => IO.cede`
    | 11, _, _ => { out := .prog .cede }
    -- `_ => ()` (the function of `void`)
    | 12, _, _ => { out := .ret .unit }
    -- `_ => IO { second = true }`
    | 13, _, _ => { out := .prog (.delay (.user 14)) }
    -- `second = true` (`Ref` cell 1)
    | 14, _, _ => { effects := [.writeRef 1 (.bool true)], out := .ret .unit }
    -- `first = true` (`Ref` cell 0)
    | 15, _, _ => { effects := [.writeRef 0 (.bool true)], out := .ret .unit }
    -- `n => n * 2`
    | 16, .nat n, _ => { out := .ret (.nat (n * 2)) }
    -- `_ => IO.pure(2)`
    | 17, _, _ => { out := .prog (.pure (.nat 2)) }
    | _, _, _ => { out := .ret .unit }

/-- The rest and the `Ref` cells after the `SyncIO` part, or `none` for a model stop. -/
def rest (fuel : Nat) (fa : IO) (limit : Int) (refs : List Val) : Option (IO × List Val) :=
  match SyncStep.steppedRest counterMaskModel env fuel fa limit refs with
  | .ok (p, h) => some (p, h.refs)
  | .error _ => none

/-- `n` steps of the single-fiber driver. -/
def go (n : Nat) : List SoloChoice := List.replicate n (.step true)

/-- 1. A program with no async boundary runs to completion: `Right(a)` gives `IO.pure(a)`.
`IO.pure(5).map(n => n * 2)` (`IOSuite.scala:2577-2605`, shorter). -/
example : rest 20 (.map (.pure (.nat 5)) (.user 16)) 1024 [] = some (.pure (.nat 10), []) := by
  decide +kernel

/-- 2. `IO.raiseError(e)` fails in `SyncIO` (`IOSuite.scala:2607-2617`); the selected `IO` is
`IO.raiseError(e)`. -/
example : rest 20 (.error e1) 1024 [] = some (.error e1, []) := by decide +kernel

/-- 3. "evaluate up to limit and no further" (`IOSuite.scala:2664-2681`):
`IO { first = true } *> IO { second = true }` with `syncStep(2)`: `first`, not `second`, `Left`. -/
example : rest 20 (.flatMap (.delay (.user 15)) (.user 13)) 2 [.bool false, .bool false]
    = some (.delay (.user 14), [.bool true, .bool false]) := by
  decide +kernel

/-- 4. "should not execute effects twice for map (#2858)" (`IOSuite.scala:2683-2692`):
`(IO(i += 1) *> IO.cede).void`; the rest is `IO.cede.map(_ => ())` and the run gives `i = 1`. -/
example : rest 20 (.map (.flatMap (.delay (.user 10)) (.user 11)) (.user 12)) 1024 [.nat 0]
    = some (.map .cede (.user 12), [.nat 1]) := by
  decide +kernel

example : steppedObs env (.map (.flatMap (.delay (.user 10)) (.user 11)) (.user 12)) 1024 [.nat 0]
    20 (go 20) = (.done (.succeeded .unit), [.nat 1], []) := by
  decide +kernel

/-- 5. `IO.OnCancel` with `G = SyncIO`: the finalizer is dropped (`IO.scala:2396-2397`).
`IO.cede.onCancel(fin)` gives `Left(IO.cede)`. -/
example : rest 20 (.onCancel .cede (.delay (.user 14))) 1024 [] = some (.cede, []) := by
  decide +kernel

/-- 6. `IO.Uncancelable` with `G = SyncIO`: the body runs with `IdPoll` and the mask is dropped
(`IO.scala:2390-2394`). `IO.uncancelable(_ => IO.cede)` gives `Left(IO.cede)`. -/
example : rest 20 (.uncancelable (.user 11)) 1024 [] = some (.cede, []) := by decide +kernel

/-- 7. `limit <= 0` gives `Left(io)` at once (`IO.scala:2350-2351`). -/
example : rest 20 (.pure (.nat 1)) 0 [] = some (.pure (.nat 1), []) := by decide +kernel

/-- 8. `stepsUntilDefer <= 0` gives `G.defer(interpret(io, limit, MaxSteps))`
(`IO.scala:2352-2353`): the same result after one more `SyncIO` stage. -/
example :
    (match SyncStep.interpret counterMaskModel env 5 (.pure (.nat 1)) 7 0
        (SyncStep.prefixExec counterMaskModel []) with
      | .ok s x =>
        match SyncIO.unsafeRunSync (SyncStep.senv counterMaskModel env) 10 s x with
        | .value v _ => some v
        | _ => none
      | _ => none) = some (.right (.pair (.val (.nat 1)) (.int 7))) := by
  decide +kernel

/-- 9. A throw inside `HandleErrorWith` is caught by the `SyncIO` handler:
`IO.raiseError(e).handleErrorWith(_ => IO.pure(2))` gives `Right(2)`. -/
example : rest 20 (.handleErrorWith (.error e1) (.user 17)) 1024 [] = some (.pure (.nat 2), []) := by
  decide +kernel

/-- 10. `attempt` of an error gives `Right(Left(e))` (`IO.scala:2374-2380`). -/
example : rest 20 (.attempt (.error e1)) 1024 [] = some (.pure (.left (.err e1)), []) := by
  decide +kernel

end CatsEffectInLean.Model.SyncStepExamples

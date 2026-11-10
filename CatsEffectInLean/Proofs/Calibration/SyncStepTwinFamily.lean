import CatsEffectInLean.Model.SyncStepFixed
import CatsEffectInLean.Proofs.Calibration.StepCheck

/-!
# The bounded domain of the CE-0001 fixed-twin check (decision 39)

Ten small non-fatal programs with `uncancelable`, `poll`, `onCancel`, `canceled`, an async
boundary (`IO.cede`), a poll that escapes its region, a nested region, an error that crosses a
rebuilt region and a throwing body. In Scala (`emit(n)` is `IO(out += n)`):

| # | program | direct outcome |
|---|---|---|
| 1 | `IO.uncancelable(_ => IO.canceled *> emit(1))` | `Succeeded`, `[1]` |
| 2 | `IO.uncancelable(p => IO.cede *> p(IO.canceled) *> emit(1))` | `Canceled`, `[]` |
| 3 | `IO.uncancelable(p => p(IO.canceled) *> emit(1))` | `Canceled`, `[]` |
| 4 | `IO.canceled.onCancel(emit(3))` | `Canceled`, `[3]` |
| 5 | `IO.uncancelable(o => IO.uncancelable(_ => IO.cede *> o(IO.canceled) *> emit(1)))` | `Succeeded`, `[1]` |
| 6 | `IO.uncancelable(p => IO.cede *> p(IO.cede) *> IO.canceled *> emit(1))` | `Succeeded`, `[1]` |
| 7 | `IO.uncancelable(p => IO.pure(p)).flatMap(p => IO.cede *> p(IO.canceled) *> emit(1))` | `Canceled`, `[]` |
| 8 | `IO.uncancelable(p => p(IO.cede *> IO.canceled) *> emit(1))` | `Canceled`, `[]` |
| 9 | `IO.uncancelable(_ => IO.cede *> IO.raiseError(e)).handleErrorWith(_ => emit(2))` | `Succeeded`, `[2]` |
| 10 | `IO.uncancelable(_ => throw e).handleErrorWith(_ => emit(2))` | `Succeeded`, `[2]` |

`e` is a non-fatal error. Each program uses only handles that it received, and applies a poll
only with `poll(io)` (`applyPollT`), so it is a Scala program (decision 27); `WellFormed` is not
proven here.

User code is a table `T k c a` of closures with tag `k`, one captured value `c` and argument
`a` (`Codec` closure ids, namespace `famNs`).
-/

namespace CatsEffectInLean.Proofs.Calibration.SyncStepTwin

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.SyncStepObs
open CatsEffectInLean.Model.SyncStepFixed
open CatsEffectInLean.Props.Calibration
open CatsEffectInLean.Proofs.Calibration.StepCheck

/-- The namespace of the user closures of the family. -/
def famNs : Nat := 8

/-- User closure `k` with captured value `c`. -/
def F (k : Nat) (c : Val := .unit) : Fn := userFn (cloVal famNs k [c])

/-- `emit(n)`: `IO.delay` of a thunk that emits `n`. -/
def E (n : Nat) : IO := .delay (F n)

/-- The non-fatal error of programs 9 and 10. -/
def eN : Err := { code := 1 }

/-- A result that is a program. -/
def pr (p : IO) : UserResult := { out := .prog p }

/-- A closure got an argument of the wrong shape (never in these programs). -/
def ill : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- The user closures: `T k c a` is closure `k` with captured `c`, called on `a`. -/
def T (k : Nat) (c a : Val) : UserResult :=
  match k with
  | 1 => { effects := [.emit (.nat 1)], out := .ret .unit }
  | 2 => { effects := [.emit (.nat 2)], out := .ret .unit }
  | 3 => { effects := [.emit (.nat 3)], out := .ret .unit }
  -- `_ => emit(1)`, `_ => IO.canceled`, `_ => IO.canceled *> emit(1)`
  | 10 => pr (E 1)
  | 11 => pr .canceled
  | 12 => pr (.flatMap .canceled (F 10))
  -- 2: `p => IO.cede *> k21(p)`; `k21(p) = _ => p(IO.canceled) *> emit(1)`
  | 20 => pr (.flatMap .cede (F 21 a))
  | 21 => pr (.flatMap (applyPollT c .canceled) (F 10))
  -- 3: `p => p(IO.canceled) *> emit(1)`
  | 22 => pr (.flatMap (applyPollT a .canceled) (F 10))
  -- 5: `o => IO.uncancelable(k51(o))`; `k51(o) = _ => IO.cede *> k21(o)`
  | 50 => pr (.uncancelable (F 51 a))
  | 51 => pr (.flatMap .cede (F 21 c))
  -- 6: `p => IO.cede *> k61(p)`; `k61(p) = _ => p(IO.cede) *> (IO.canceled *> emit(1))`
  | 60 => pr (.flatMap .cede (F 61 a))
  | 61 => pr (.flatMap (applyPollT c .cede) (F 12))
  -- 7: `p => IO.pure(p)`, then `p => IO.cede *> k21(p)`
  | 70 => pr (.pure a)
  | 71 => pr (.flatMap .cede (F 21 a))
  -- 8: `p => p(IO.cede *> IO.canceled) *> emit(1)`
  | 80 => pr (.flatMap (applyPollT a (.flatMap .cede (F 11))) (F 10))
  -- 9: `_ => IO.cede *> IO.raiseError(e)`; handler `_ => emit(2)`
  | 90 => pr (.flatMap .cede (F 91))
  | 91 => pr (.error eN)
  | 92 => pr (E 2)
  -- 10: `_ => throw e`
  | 100 => { out := .throw eN }
  | _ => ill

/-- The user environment of the family, with the closures of the fixed twin (`fixEnv`). The
v3.7.1 model never builds a twin closure, so it sees only `T`. -/
def famEnv : UserEnv :=
  fixEnv
    { call := fun id arg _ =>
        match (cloOfId id).bind ofCloVal with
        | some (k, tag, [c]) => if id % 2 == 0 && k == famNs then T tag c arg else ill
        | _ => ill
      callV := fun id arg _ =>
        match (cloOfId id).bind ofCloVal with
        | some (k, tag, [c]) => if id % 2 == 0 && k == famNs then T tag c arg else ill
        | _ => ill }

/-- The ten programs. -/
def prog : Nat → IO
  | 1 => .uncancelable (F 12)
  | 2 => .uncancelable (F 20)
  | 3 => .uncancelable (F 22)
  | 4 => .onCancel .canceled (E 3)
  | 5 => .uncancelable (F 50)
  | 6 => .uncancelable (F 60)
  | 7 => .flatMap (.uncancelable (F 70)) (F 71)
  | 8 => .uncancelable (F 80)
  | 9 => .handleErrorWith (.uncancelable (F 90)) (F 92)
  | 10 => .handleErrorWith (.uncancelable (F 100)) (F 92)
  | _ => .pure .unit

/-- `Int.MaxValue`. -/
def lim : Int := 2147483647

/-- The `SyncIO` part of v3.7.1. -/
def R371 (n fuel : Nat) : Except Summary (IO × Heap) :=
  SyncStep.steppedRest counterMaskModel famEnv fuel (prog n) lim []

/-- The `SyncIO` part of the fixed twin. -/
def Rfix (n fuel : Nat) : Except Summary (IO × Heap) :=
  steppedRestFixed counterMaskModel famEnv fuel (prog n) lim []

end CatsEffectInLean.Proofs.Calibration.SyncStepTwin

import CatsEffectInLean.Model.Bracket
import CatsEffectInLean.Model.EnumP

/-!
# Examples of the `guarantee`/`bracket` mirror (Phase 6, track G)

A small user environment `env` for `Model/Bracket.lean`. The smoke tests that use it are in
`Proofs/Phase6/BracketSmoke.lean` (exact `EqvP` outcome sets, `decide +kernel`). Program codes
of `progOf` are also the external sources (`ioOf`).

User code (`Codec.userFn`, namespace `uns`), so that closures can capture values:

| tag | Scala | call |
|---|---|---|
| 0 `prog p` | `_ => p` (for a fixed program code `p`, `progOf`) | returns `progOf p` |
| 1 `emitThunk v` | `IO.delay(emit v)` thunk | emits `v`, returns `unit` |
| 2 `relEmit t` | `(a, oc) => IO.delay(emit (t, oc))` | returns `Delay(emitThunk (t, oc))` |
| 3 `throwE c` | `_ => throw E(c)` | throws error `c` |
| 4 `emitThen v p` | `_ => { emit v; p }` (an impure function) | emits `v`, returns `progOf p` |
| 5 `markA v` | `x => { emit v; IO.pure(x) }` | emits `v`, returns `Pure(x)` |
| 6 `relMark` | `_ => IO.delay(emit 88) *> IO.unit` | returns that program |

External sources (`ioOf`, `Src.ext`): the same codes as `progOf`.
-/

namespace CatsEffectInLean.Model.BracketExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket

/-- The namespace of the user closures of these examples. -/
def uns : Nat := 9

/-- A user closure id. -/
def uid (tag : Nat) (fs : List Val) : Nat := 2 * valToNat (cloVal uns tag fs)

/-- `IO.delay(emit v)`. -/
def emitIO (v : Val) : IO := .delay (.user (uid 1 [v]))

/-- Program codes for `prog` and `ioOf`. -/
def progOf : Val → IO
  | .nat 0 => .pure .unit                                   -- `IO.unit`
  | .nat 1 => .canceled                                     -- `IO.canceled`
  | .nat 2 => .error { code := 2 }                          -- `IO.raiseError(E2)`
  | .nat 3 => emitIO (.nat 3)                               -- `IO.delay(emit 3)`
  | .nat 4 => .error { code := 4 }                          -- `IO.raiseError(E4)`
  | .nat 5 => .flatMap (emitIO (.nat 5)) (.user (uid 0 [.nat 1]))  -- `emit 5 >> IO.canceled`
  | .nat 6 => .pure (.nat 6)                                -- `IO.pure(6)`
  | .nat 7 => .flatMap (emitIO (.nat 7)) (.user (uid 0 [.nat 6]))  -- `emit 7 >> IO.pure(6)`
  | .nat 8 => .flatMap (.start (emitIO (.nat 8))) (.user (uid 0 [.nat 3]))  -- `IO.delay(emit 8).start >> emit 3`
  | .nat 9 => .flatMap .cede (.user (uid 0 [.nat 6]))         -- `IO.cede >> IO.pure(6)`
  | .nat 10 => .flatMap (emitIO (.nat 88)) (.user (uid 0 [.nat 0]))  -- `IO.delay(emit 88) *> IO.unit`
  | .pair (.nat 50) a0 => .flatMap (progOf a0) (.user (uid 5 [.nat 77]))  -- `a0.flatMap(markA 77)`
  | .pair (.nat 51) c => .flatMap (emitIO (.nat 77)) (.user (uid 0 [c]))  -- `IO.delay(emit 77) *> c`
  | _ => .error { code := 999 }

/-- The user code. -/
def user (id : Nat) (arg : Val) (_v : View) : UserResult :=
  match cloOfId id with
  | some c =>
    match ofCloVal c with
    | some (9, 0, [p]) => { out := .prog (progOf p) }
    | some (9, 1, [v]) => { effects := [.emit v], out := .ret .unit }
    | some (9, 2, [t]) => { out := .prog (.delay (.user (uid 1 [.pair t arg]))) }
    | some (9, 3, [.nat c]) => { out := .throw { code := c } }
    | some (9, 4, [v, p]) => { effects := [.emit v], out := .prog (progOf p) }
    | some (9, 5, [v]) => { effects := [.emit v], out := .prog (.pure arg) }
    | some (9, 6, []) => { out := .prog (.flatMap (emitIO (.nat 88)) (.user (uid 0 [.nat 0]))) }
    | _ => { out := .throw { code := 998 } }
  | none => { out := .throw { code := 997 } }

/-- Dispatch: library closures of the mirror, then user code. The mirror calls `uc` only on
user functions (`callFin`), so `user` is enough there. -/
def dispatch (id : Nat) (arg : Val) (v : View) : UserResult :=
  match BLam.ofId? id with
  | some l => call user progOf l arg v
  | none => user id arg v

/-- The environment of the examples. -/
def env : UserEnv where
  call id arg refs := dispatch id arg { refs }
  callV := dispatch

/-- The exact observation set of a program. -/
def obs (io : IO) : Option (List Obs) := outcomesPList {} counterMaskModel env 400 io

end CatsEffectInLean.Model.BracketExamples

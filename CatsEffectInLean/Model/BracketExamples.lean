import CatsEffectInLean.Model.Bracket
import CatsEffectInLean.Model.EnumP

/-!
# Examples of the `guarantee`/`bracket` mirror (Phase 6, track G)

Smoke tests of `Model/Bracket.lean` with a small user environment `BEx.env`. Each check is an
exact outcome set under the preemptive scheduler (`outcomesPList`, `EqvP` sets), evaluated by
`decide +kernel`.

User code (`Codec.userFn`, namespace `uns`), so that closures can capture values:

| tag | Scala | call |
|---|---|---|
| 0 `prog p` | `_ => p` (for a fixed program code `p`, `progOf`) | returns `progOf p` |
| 1 `emitThunk v` | `IO.delay(emit v)` thunk | emits `v`, returns `unit` |
| 2 `relEmit t` | `(a, oc) => IO.delay(emit (t, oc))` | returns `Delay(emitThunk (t, oc))` |
| 3 `throwE c` | `_ => throw E(c)` | throws error `c` |
| 4 `emitThen v p` | `_ => { emit v; p }` (an impure function) | emits `v`, returns `progOf p` |

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

/-! ## guarantee -/

#eval obs (guaranteeIO (.ext (.nat 0)) (.ext (.nat 3)))
#eval obs (guaranteeIO (.ext (.nat 2)) (.ext (.nat 3)))
#eval obs (guaranteeIO (.ext (.nat 1)) (.ext (.nat 3)))
#eval obs (guaranteeIO (.ext (.nat 2)) (.ext (.nat 4)))
#eval obs (guaranteeCaseIO (.ext (.nat 2)) (uid 0 [.nat 4]))
#eval obs (defaultGuaranteeCaseIO (.ext (.nat 2)) (uid 0 [.nat 4]))

/-! ## bracketFull twin -/

-- acquire `_ => IO.canceled` (masked self-cancel), use `_ => throw E5`, release emits (t, oc)
#eval obs (bracketFullIO (uid 0 [.nat 1]) (uid 3 [.nat 5]) (uid 2 [.nat 9]))
#eval obs (defaultBracketFullIO (uid 0 [.nat 1]) (uid 3 [.nat 5]) (uid 2 [.nat 9]))
-- use `_ => { emit 8; IO.unit }`
#eval obs (bracketFullIO (uid 0 [.nat 1]) (uid 4 [.nat 8, .nat 0]) (uid 2 [.nat 9]))
#eval obs (defaultBracketFullIO (uid 0 [.nat 1]) (uid 4 [.nat 8, .nat 0]) (uid 2 [.nat 9]))
-- pure use `_ => emit 7 >> IO.pure 6`
#eval obs (bracketFullIO (uid 0 [.nat 1]) (uid 0 [.nat 7]) (uid 2 [.nat 9]))
#eval obs (defaultBracketFullIO (uid 0 [.nat 1]) (uid 0 [.nat 7]) (uid 2 [.nat 9]))
-- ordinary: acquire `IO.pure 6`, use `emit 7 >> pure 6`
#eval obs (bracketFullIO (uid 0 [.nat 6]) (uid 0 [.nat 7]) (uid 2 [.nat 9]))
#eval obs (bracketIO (.ext (.nat 6)) (uid 0 [.nat 5]) (uid 0 [.nat 3]))

end CatsEffectInLean.Model.BracketExamples

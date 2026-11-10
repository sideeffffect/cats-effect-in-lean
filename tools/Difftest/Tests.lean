import Difftest.Env

/-!
# Checks of the difftest decoder and translation

`#guard` checks run when this module builds (`lake build Difftest`). They are tests of the
harness, not proofs about Cats Effect.
-/

namespace Difftest.Tests

open Difftest
open CatsEffectInLean.Model
open Lean (Json)

deriving instance BEq for Except

/-- Decode a program from JSON text. -/
def dec (s : String) : Except String Prog := do decodeProg (← Json.parse s)

/-- Decode a case from JSON text. -/
def decCase (s : String) : Except String TestCase := do decodeCase (← Json.parse s)

def isErr {α : Type} : Except String α → Bool
  | .error _ => true
  | .ok _ => false

/-! ## Closure ids round-trip -/

def sampleClos : List Clo :=
  [ { node := 0, lam := .delayThunk, vals := [] },
    { node := 17, lam := .neverSel, vals := [.poll 3 1, .cont 9] },
    { node := 5, lam := .gcFinEmit,
      vals := [.ocSucceeded (.pair (.nat 9000000000000000) (.left (.bool true))), .unit,
               .ocErrored (userErr 4), .err { code := 7, kind := .fatal }, .int (-12), .int 5,
               .none, .some (.right .ocCanceled), .fiber 2, .ref 0, .deferred 3, .ec 0,
               .trace, .runtime] } ]

#guard sampleClos.all fun c => Clo.decode? c.encode == some c
#guard Lam.all.all fun l => Lam.ofNat? l.toNat == some l
#guard Lam.all.length = Lam.all.eraseDups.length

/-! ## Decoder rejects what the Scala decoder rejects -/

#guard isErr (dec r#"{"op":"pure","v":{"t":"var","x":"y"}}"#)               -- unbound
#guard isErr (dec r#"{"op":"pure","v":{"t":"fiber","id":0}}"#)              -- handle literal
#guard isErr (dec r#"{"op":"pure","v":{"t":"nat","v":1},"extra":1}"#)       -- unknown key
#guard isErr (dec r#"{"op":"nope"}"#)                                       -- unknown op
#guard isErr (dec r#"{"op":"poll","poll":"p","e":{"op":"cede"}}"#)          -- unbound poll
#guard isErr (dec r#"{"op":"uncancelable","poll":"p","body":{"op":"pure","v":{"t":"var","x":"p"}}}"#)
#guard isErr (dec r#"{"op":"delay","fn":10}"#)                              -- unknown user fn
#guard isErr (dec r#"{"op":"seq","ps":[]}"#)
#guard isErr (dec r#"{"op":"sleep","ms":1.5}"#)
#guard isErr (dec r#"{"op":"sleep","ms":-1}"#)
#guard isErr (dec r#"{"op":"async","cbs":[{"when":"sync","ok":{"t":"unit"},"err":1}]}"#)
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"cede"}}"#)
#guard isErr (decCase r#"{"v":0,"id":"x","mode":"replay","seed":1,"prog":{"op":"cede"}}"#)
#guard isErr (decCase r#"{"v":0,"id":"x","mode":"testcontrol","choices":[],"seed":1,"prog":{"op":"cede"}}"#)

-- Shadowing and de Bruijn indices: `split` binds `b` at 0 and `a` at 1.
#guard dec r#"{"op":"split","on":{"t":"pair","a":{"t":"nat","v":1},"b":{"t":"unit"}},"a":"x","b":"y","k":{"op":"pure","v":{"t":"var","x":"x"}}}"#
  == .ok (.split (.lit (.pair (.nat 1) .unit)) (.pure (.var 1)))
#guard dec r#"{"op":"bind","x":"x","e":{"op":"cede"},"k":{"op":"bind","x":"x","e":{"op":"cede"},"k":{"op":"pure","v":{"t":"var","x":"x"}}}}"#
  == .ok (.bind .cede (.bind .cede (.pure (.var 0))))
-- `seq [p]` is `p`; `seq` is left-nested.
#guard dec r#"{"op":"seq","ps":[{"op":"cede"}]}"# == .ok .cede
#guard dec r#"{"op":"seq","ps":[{"op":"cede"},{"op":"never"},{"op":"canceled"}]}"#
  == .ok (.seq (.seq .cede .never) .canceled)
-- `1e3` is a natural number; `delay` without `arg` gets `unit`.
#guard dec r#"{"op":"sleep","ms":1e3}"# == .ok (.sleep 1000)
#guard dec r#"{"op":"delay","fn":2}"# == .ok (.delay 2 (.lit .unit))

/-! ## Translation gives the Scala `IO` terms -/

/-- Run closure `f` of program `p`. -/
def callFn (p : Prog) (f : Fn) (arg : Val) (refs : List Val := []) : DResult :=
  match f with
  | .user id => denv p id arg refs
  | .rt _ => DResult.harness

def outOf (r : DResult) : UserOut := r.base.out

-- `bind x (pure 1) (pure x)`: `IO.pure(1).flatMap(x => IO.pure(x))`.
def pBind : Prog := .bind (.pure (.lit (.nat 1))) (.pure (.var 0))
#guard rootTerm pBind == .ok (.flatMap (.pure (.nat 1)) (clo 0 .bindK []))
#guard outOf (callFn pBind (clo 0 .bindK []) (.nat 5)) == .prog (.pure (.nat 5))

-- `delay inc 1`: the thunk emits `call` and returns 2. `delay raise 3` throws `UserError(3)`.
def pDelay : Prog := .delay 2 (.lit (.nat 1))
#guard rootTerm pDelay == .ok (.delay (clo 0 .delayThunk []))
#guard (callFn pDelay (clo 0 .delayThunk []) .unit).trace == [.call 2 (.nat 1)]
#guard outOf (callFn pDelay (clo 0 .delayThunk []) .unit) == .ret (.nat 2)
#guard outOf (callFn (.delay 3 (.lit (.nat 3))) (clo 0 .delayThunk []) .unit) == .throw (userErr 3)

-- `handleErrorWith`: a `UserError(7)` binds `nat 7`; any other error is raised again.
def pHew : Prog := .handleErrorWith (.raise 7) (.pure (.var 0))
#guard rootTerm pHew == .ok (.handleErrorWith (.error (userErr 7)) (clo 0 .hewK []))
#guard outOf (callFn pHew (clo 0 .hewK []) (.err (userErr 7))) == .prog (.pure (.nat 7))
#guard outOf (callFn pHew (clo 0 .hewK []) (.err typeErr)) == .prog (.error typeErr)

-- `guaranteeCase e x fin` (`IO.scala:523-530`).
def pGc : Prog := .guaranteeCase (.pure (.lit (.nat 1))) (.pure (.var 0)) 4
#guard rootTerm pGc == .ok (.uncancelable (clo 0 .gcBody []))
#guard outOf (callFn pGc (clo 0 .gcBody []) (.poll 1 0)) == .prog
  (.flatMap
    (.handleErrorWith
      (.onCancel (.unmaskRunLoop (.pure (.nat 1)) 1 0)
        (.flatMap (.pure .ocCanceled) (clo 0 .gcFinK [])))
      (clo 0 .gcOnError []))
    (clo 0 .gcTap []))
#guard outOf (callFn pGc (clo 0 .gcTap []) (.nat 1)) == .prog
  (.map (.flatMap (.map (.pure (.nat 1)) (clo 0 .succFn [])) (clo 0 .gcFinK []))
    (clo 0 .constVal [.nat 1]))
#guard outOf (callFn pGc (clo 0 .gcOnError []) (.err (userErr 2))) == .prog
  (.flatMap
    (.handleErrorWith (.flatMap (.pure (.ocErrored (userErr 2))) (clo 0 .gcFinK []))
      (clo 0 .reportK []))
    (clo 0 .constRaise [.err (userErr 2)]))
#guard (callFn pGc (clo 0 .gcFinEmit [.ocCanceled]) .unit).trace == [.finGuaranteeCase 4 .ocCanceled]
#guard outOf (callFn pGc (clo 0 .gcFinThen [.ocCanceled]) .unit) ==
  .prog (.map (.pure .ocCanceled) (clo 0 .voidFn []))

-- `onCancel e fin`: `OnCancel(I(e), Delay(emit).flatMap(_ => I(fin).void))`.
def pOc : Prog := .onCancel .never .cede 2
#guard rootTerm pOc == .ok (.onCancel (neverTerm 1)
  (.flatMap (.delay (clo 0 .ocFinEmit [])) (clo 0 .ocFinThen [])))
#guard outOf (callFn pOc (clo 0 .ocFinThen []) .unit) ==
  .prog (.map (.map .cede (clo 2 .asUnit [])) (clo 0 .voidFn []))

-- `IO.never`: `IOCont(body)`; body → `uncancelable`; → `pure(Some(unit)).flatMap(sel)`;
-- `sel(Some _)` → `onCancel(poll(get), unit)`.
#guard outOf (callFn .never (clo 0 .neverBody []) (.cont 3)) ==
  .prog (.uncancelable (clo 0 .neverUnc [.cont 3]))
#guard outOf (callFn .never (clo 0 .neverUnc [.cont 3]) (.poll 1 0)) ==
  .prog (.flatMap (.pure (.some .unit)) (clo 0 .neverSel [.poll 1 0, .cont 3]))
#guard outOf (callFn .never (clo 0 .neverSel [.poll 1 0, .cont 3]) (.some .unit)) ==
  .prog (.onCancel (.unmaskRunLoop (.contGet 3) 1 0) (.pure .unit))

-- `async` with one sync and one later callback and a finalizer.
def pAsync : Prog :=
  .asyncFin [{ when := .sync, res := .ok (.nat 1) }, { when := .later, res := .err 5 }] .cede 9
#guard rootTerm pAsync == .ok (.flatMap .readEC (clo 0 .asyncEc []))
#guard outOf (callFn pAsync (clo 0 .asyncEc []) (.ec 0)) == .prog (.ioCont (clo 0 .asyncBody [.ec 0]))
#guard (callFn pAsync (clo 0 .asyncReg [.cont 2, .ec 0]) .unit).base ==
  { effects := [.invokeCb 2 (.right (.nat 1)), .deferCb 2 (.left (.err (userErr 5)))],
    out := .ret (.some .unit) }
#guard (callFn pAsync (clo 0 .asyncReg [.cont 2, .ec 0]) .unit).trace == [.asyncReg 2, .cb 2 0]
#guard outOf (callFn pAsync (clo 0 .asyncSel [.poll 1 0, .cont 2, .ec 0]) (.some .unit)) ==
  .prog (.onCancel (.unmaskRunLoop (.contGet 2) 1 0)
    (.flatMap (.delay (clo 0 .asyncFinEmit [])) (clo 0 .asyncFinThen [])))

-- `refModify r incOld` on `Ref` 0 = 4: writes 5, returns 4, emits `call`.
def pMod : Prog := .refModify (.var 0) 5
#guard (callFn pMod (clo 0 .refModifyThunk [.ref 0]) .unit [.nat 4]).base ==
  { effects := [.writeRef 0 (.nat 5)], out := .ret (.nat 4) }

-- `racePair`: `Left((oc, fb))` → `ocVal(oc).map(o => left(pair(o, fiber fb)))`.
def pRace : Prog := .racePair .cede .never
#guard outOf (callFn pRace (clo 0 .rpK []) (.left (.pair (.ocSucceeded .unit) (.fiber 2)))) ==
  .prog (.map (.map (.pure .unit) (clo 0 .succFn [])) (clo 0 .rpLeft [.fiber 2]))

-- Unsupported ops are reported, not guessed.
#guard rootTerm (.bind .deferredNew (.pure (.var 0))) == .error (.unsupported "deferredNew")
#guard rootTerm (.join (.lit .unit)) == .error .typeError

end Difftest.Tests

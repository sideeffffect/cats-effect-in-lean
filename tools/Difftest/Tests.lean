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
#guard isErr (decCase r#"{"v":3,"id":"x","mode":"replay","prog":{"op":"cede"}}"#)
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
  | .user id => denv p id arg { refs }
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
-- `run(e)` is built with the outer term: `gcBody` captures the snapshot of the root view.
def snap0 : Val := snapVal rootView
#guard rootTerm pGc == .ok (.uncancelable (clo 0 .gcBody [snap0]))
#guard outOf (callFn pGc (clo 0 .gcBody [snap0]) (.poll 1 0)) == .prog
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
  (.flatMap (.delay (clo 0 .ocFinEmit [])) (clo 0 .ocFinThen [snap0])))
#guard outOf (callFn pOc (clo 0 .ocFinThen [snap0]) .unit) ==
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
-- The registration emits its events between the callback calls, in Scala order, and returns
-- `some snap` (the snapshot for `run(fin)`).
#guard (callFn pAsync (clo 0 .asyncReg [.cont 2, .ec 0]) .unit).base ==
  { effects := [.emit (TraceEv.asyncReg 2).toVal, .emit (TraceEv.cb 2 0).toVal,
                .invokeCb 2 (.right (.nat 1)), .emit (TraceEv.cbLater 2 1).toVal,
                .deferCb 2 (.left (.err (userErr 5)))],
    out := .ret (.some (snapVal {})) }
#guard outOf (callFn pAsync (clo 0 .asyncSel [.poll 1 0, .cont 2, .ec 0]) (.some snap0)) ==
  .prog (.onCancel (.unmaskRunLoop (.contGet 2) 1 0)
    (.flatMap (.delay (clo 0 .asyncFinEmit [])) (clo 0 .asyncFinThen [snap0])))

-- `refModify r incOld` on `Ref` 0 = 4: writes 5, returns 4, emits `call`.
def pMod : Prog := .refModify (.var 0) 5
#guard (callFn pMod (clo 0 .refModifyThunk [.ref 0]) .unit [.nat 4]).base ==
  { effects := [.writeRef 0 (.nat 5)], out := .ret (.nat 4) }

-- `racePair`: `Left((oc, fb))` → `ocVal(oc).map(o => left(pair(o, fiber fb)))`.
def pRace : Prog := .racePair .cede .never
#guard outOf (callFn pRace (clo 0 .rpK []) (.left (.pair (.ocSucceeded .unit) (.fiber 2)))) ==
  .prog (.map (.map (.pure .unit) (clo 0 .succFn [])) (clo 0 .rpLeft [.fiber 2]))

-- `join`/`cancel` read the fiber outcome of the view when the term is built (`IO.joinOf`,
-- `IO.cancelOf`); `deferred.get` reads the cell (`IO.deferredGetOf`).
/-- An `REnv` for terms without resource nodes. -/
def R0 : CatsEffectInLean.Model.Resource.REnv := renvOf .cede

def vDone : View := { outcomes := [none, some (.succeeded (.nat 3))], deferreds := [some (.nat 7), none] }
#guard tr R0 (.join (.lit (.fiber 1))) 0 [] rootView == .ok (.flatMap (.ioCont (.rt (.join 1))) (clo 0 .ocValK []))
#guard tr R0 (.join (.lit (.fiber 1))) 0 [] vDone == .ok (.flatMap (.pure (.ocSucceeded (.nat 3))) (clo 0 .ocValK []))
#guard tr R0 (.cancel (.lit (.fiber 1))) 0 [] rootView == .ok (.map (.uncancelable (.rt (.cancel 1))) (clo 0 .asUnit []))
#guard tr R0 (.cancel (.lit (.fiber 1))) 0 [] vDone == .ok (.map (.pure .unit) (clo 0 .asUnit []))
#guard tr R0 (.deferredGet (.lit (.deferred 0))) 0 [] vDone == .ok (.pure (.nat 7))
#guard tr R0 (.deferredGet (.lit (.deferred 1))) 0 [] vDone ==
  .ok (.flatMap (.delay (.rt (.deferredDefer 1))) (.rt (.deferredFlatten 1)))
-- The snapshot keeps what the view shows when the outer term is built.
#guard snapView (snapVal vDone) == { vDone with refs := [] }
-- `refNew v`: `Map(Delay(Ref.unsafe(v)), handle)`; the thunk allocates cell `refs.length`.
#guard rootTerm (.refNew (.lit (.nat 4))) ==
  .ok (.map (.delay (clo 0 .refNewThunk [])) (clo 0 .refHandle []))
#guard (callFn (.refNew (.lit (.nat 4))) (clo 0 .refNewThunk []) .unit [.nat 0]).base ==
  { effects := [.allocRef (.nat 4)], out := .ret (.ref 1) }
#guard rootTerm (.bind .deferredNew (.pure (.var 0))) ==
  .ok (.flatMap (.map (.delay (clo 1 .deferredNewThunk [])) (clo 1 .deferredHandle [])) (clo 0 .bindK []))
-- Trace events survive `emit`.
#guard [TraceEv.call 2 (.pair .unit (.fiber 1)), .finOnCancel 1, .finAsync 2,
        .finGuaranteeCase 3 .ocCanceled, .set 0 (.nat 1), .complete 1 (.nat 2) false,
        .asyncReg 4, .cb 4 1, .handle 3, .cbLater 4 2, .failure (userErr 6)].all
  fun e => TraceEv.ofVal? e.toVal == some e

-- Every op of format v0 runs on the model (no unsupported op left).
#guard unsupportedOps (.seq (.sleep 1) (.racePair .cede .cede)) == []
#guard rootTerm (.join (.lit .unit)) == .error .typeError

/-! ## Format v1 -/

#guard !isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"syncStep","limit":3,"e":{"op":"cede"}}}"#)
#guard isErr (decCase r#"{"v":0,"id":"x","mode":"replay","prog":{"op":"syncStep","limit":3,"e":{"op":"cede"}}}"#)
#guard isErr (decCase r#"{"v":0,"id":"x","mode":"replay","prog":{"op":"queueNew"}}"#)
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"seq","ps":[{"op":"syncStep","limit":3,"e":{"op":"cede"}}]}}"#)
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"syncStep","limit":2147483648,"e":{"op":"cede"}}}"#)
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"rPure","v":{"t":"unit"}}}"#)
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"allocatedCase","res":{"op":"cede"}}}"#)
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"pure","v":{"t":"queue","id":0}}}"#)
#guard (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"allocatedCase","res":{"op":"rFlatMap","res":{"op":"rMake","acq":{"op":"pure","v":{"t":"nat","v":1}},"x":"a","rel":{"op":"pure","v":{"t":"var","x":"a"}}},"x":"b","k":{"op":"rPure","v":{"t":"var","x":"b"}}}}}"#).map (·.prog) ==
  .ok (.allocatedCase (.rFlatMap (.rMake (.pure (.lit (.nat 1))) (.pure (.var 0))) (.rPure (.var 0))))

-- A difftest closure id is even and in namespace 3 (never a `Resource` or queue/timeout id).
#guard sampleClos.all fun c => match c.fn with
  | .user id => id % 2 == 0 && cloOfId? id == some c
  | _ => false
-- The `IdPoll` of `syncStep` (mask id 0) is the identity; a real poll is `UnmaskRunLoop`.
#guard pollTerm .cede 0 0 == .cede
#guard pollTerm .cede 1 0 == .unmaskRunLoop .cede 1 0
-- `timeoutTo` is not mirrored; a resource node that reads state is outside the restriction.
#guard unsupportedOps (.timeoutTo .cede .cede 1) == ["timeoutTo"]
#guard unsupportedOps (.allocatedCase (.rEval (.join (.lit (.fiber 1))))) == ["resource-reads-state"]
#guard unsupportedOps (.allocatedCase (.rEval (.bind .cede (.join (.lit (.fiber 1)))))) == []
-- The queue: `Map(newIO, handle)`; the handle emits `queueH` with the buffer cell.
#guard rootTerm .queueNew == .ok (.map CatsEffectInLean.Std.Queue.newIO (clo 0 .queueHandle []))
#guard (callFn .queueNew (clo 0 .queueHandle []) (.ref 2)).trace == [.queueH 2]
-- `allocatedCase (rPure 3)`: `loop` gives `pure((3, F.unit release))`, then `_._1`.
#guard rootTerm (.allocatedCase (.rPure (.lit (.nat 3)))) ==
  .ok (.map (.pure (.pair (.nat 3) (CatsEffectInLean.Model.Resource.RelFn.unit.toVal))) (clo 0 .allocFst []))
#guard [TraceEv.refH 3, .queueH 4].all fun e => TraceEv.ofVal? e.toVal == some e

-- Format v2 (track R): `race`, `raceOutcome`, `both`, `bothOutcome`. A v2 op in a v0/v1 case is a
-- decode error; the term is the `Race` mirror plus the interpreter's `map`/`flatMap`.
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"race","a":{"op":"cede"},"b":{"op":"cede"}}}"#)
#guard isErr (decCase r#"{"v":1,"id":"x","mode":"replay","prog":{"op":"seq","ps":[{"op":"cede"},{"op":"both","a":{"op":"cede"},"b":{"op":"cede"}}]}}"#)
#guard (decCase r#"{"v":2,"id":"x","mode":"replay","prog":{"op":"bothOutcome","a":{"op":"cede"},"b":{"op":"never"}}}"#).map (·.prog) ==
  .ok (.bothOutcome .cede .never)
#guard isErr (decCase r#"{"v":2,"id":"x","mode":"replay","prog":{"op":"race","a":{"op":"cede"}}}"#)
#guard rootTerm (.race .cede .never) ==
  .ok (.map (CatsEffectInLean.Model.Race.raceIO (combSrcs 0 [] rootView).1 (combSrcs 0 [] rootView).2) (clo 0 .raceK []))
#guard some (srcIO (.both .cede .never) (combSrcs 0 [] rootView).2) == (tr (renvOf (.both .cede .never)) .never 2 [] rootView).toOption
#guard unsupportedOps (.raceOutcome .cede .cede) == []
-- A race closure id is odd and in namespace `Race.ns` (never a difftest closure).
#guard match (CatsEffectInLean.Model.Race.RLam.sel .both 1 0).fn with
  | .user id => id % 2 == 1 && cloOfId? id == none && (libClo? id).isSome
  | _ => false

end Difftest.Tests

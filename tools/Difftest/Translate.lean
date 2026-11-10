import Difftest.Closure
import CatsEffectInLean.Model.Syntax

/-!
# Translation: difftest program → `Model.IO` + user environment

`tr p node env` builds the `IO` term that `Interp.run(p, env)` builds in Scala
(`difftest/src/main/scala/cats/effect/difftest/Interp.scala`), with the same constructor
nesting. The spec table is in `wiki/methodology/difftest-program-format.md`. Citations of the
form `IO.scala:N` are `core/shared/src/main/scala/cats/effect/IO.scala` at `v3.7.1`.

Every Scala lambda becomes a closure `Fn.user (Clo.encode ⟨node, lam, vals⟩)`
(`Difftest/Closure.lean`). `denv p` gives the meaning of all closures of program `p`;
`userEnv p` is the `Model.UserEnv` for the step function.

## Eager and lazy construction

Scala builds some sub-terms eagerly (when the outer term is built), and the model rebuilds them
inside a closure when the closure runs. For the ops that this file supports, building a term has
no side effect and reads no mutable state, so both give the same term. The one difference:
a `TypeError` during construction. Where Scala builds eagerly (`onCancel.fin`,
`guaranteeCase.e`), `tr` also builds the sub-term eagerly to raise the error at the same point.

## Ops the model cannot express yet

`tr` returns `TrErr.unsupported op` for `join`, `cancel`, `refNew`, `deferredNew`,
`deferredGet`, `deferredComplete`. See `unsupportedReason` and the wiki ("Lean side").
-/

namespace Difftest

open CatsEffectInLean.Model

/-! ## Trace events (`Interp.scala` `h.emit`) -/

/-- A trace event. `asyncReg`/`cb` hold the `ContState` id as a stand-in for the Scala async
id; the runner renumbers them by first `asyncReg`, which gives the Scala numbering
(`Harness.newAsync` counts registrations). `handle` is internal (not printed): it marks
the point where Scala's `h.fiberHandle` gives a fiber its handle, so the runner can
renumber model fiber ids into Scala handles. -/
inductive TraceEv where
  | call (fn : Nat) (arg : Val)
  | finOnCancel (tag : Nat)
  | finAsync (tag : Nat)
  | finGuaranteeCase (tag : Nat) (oc : Val)
  | set (ref : Nat) (v : Val)
  | complete (deferred : Nat) (v : Val) (ok : Bool)
  | asyncReg (async : Nat)
  | cb (async : Nat) (i : Nat)
  | handle (fiber : Nat)
  deriving DecidableEq, Repr

/-- The result of one closure call: the model result, plus what the model cannot hold yet:
trace events and `reportFailure` calls (in order). -/
structure DResult where
  base : UserResult
  trace : List TraceEv := []
  failures : List Err := []
  deriving Repr

/-- A harness error result. -/
def DResult.harness : DResult := { base := { out := .throw harnessErr } }

/-! ## User function table (`UserFns.scala`) -/

/-- `UserFns(fn, v)` (`difftest/.../UserFns.scala:24-35`). -/
def userFn (fn : Nat) (v : Val) : Except Err Val :=
  match fn, v with
  | 0, x => .ok x
  | 1, _ => .ok .unit
  | 2, .nat n => .ok (.nat (n + 1))
  | 3, .nat c => .error (userErr c)
  | 4, x => .ok (.pair x x)
  | 5, .nat n => .ok (.pair (.nat (n + 1)) (.nat n))
  | 6, .bool b => .ok (.bool (!b))
  | 7, .nat n => .ok (.bool (n == 0))
  | 8, .pair a _ => .ok a
  | 9, .pair _ b => .ok b
  | _, _ => .error typeErr

/-- `call(fn, v)` (`Interp.scala` `call`): emit `call`, then apply. -/
def callUser (fn : Nat) (v : Val) : DResult :=
  { base := { out := match userFn fn v with | .ok r => .ret r | .error e => .throw e },
    trace := [.call fn v] }

/-! ## Translation -/

/-- Why a translation stops. -/
inductive TrErr where
  /-- Scala throws `TypeError` while it builds the term. -/
  | typeError
  /-- The model cannot express this op yet. -/
  | unsupported (op : String)
  deriving DecidableEq, Repr

/-- What the model lacks for each unsupported op. -/
def unsupportedReason : String → String
  | "join" | "cancel" =>
    "fib.join/fib.cancel read the IOFiber fields _join/_cancel when the term is built " ++
    "(IOFiber.scala:142-205); user code sees only Ref cells"
  | "refNew" => "Ref.unsafe allocates a Ref cell; UserEffect has no allocation"
  | "deferredNew" | "deferredGet" | "deferredComplete" =>
    "IODeferred cells are not visible to user code and have no mirror yet (Phase 2 step 9)"
  | _ => "unknown"

/-- `⟦a⟧`. -/
def atomVal (env : List Val) : Atom → Except TrErr Val
  | .lit v => .ok v
  | .var i => match env[i]? with
    | some v => .ok v
    | none => .error .typeError

/-- `refOf` (`Interp.scala`): the ref id of an atom. -/
def refId (env : List Val) (a : Atom) : Except TrErr Nat := do
  match ← atomVal env a with
  | .ref i => pure i
  | _ => throw .typeError

/-- `ocVal(oc)` as an `IO` term (`Interp.scala` `ocVal`). `oc` is an outcome value. -/
def ocValTerm (node : Nat) : Val → IO
  | .ocSucceeded v => .map (.pure v) (clo node .succFn [])
  | .ocErrored e => .pure (.ocErrored e)
  | _ => .pure .ocCanceled

/-- `finalizer(oc)` of `guaranteeCase` (`Interp.scala`):
`ocVal(oc).flatMap(o => IO.delay(emit) *> I(fin)[x := o].void)`. -/
def gcFinalizer (node : Nat) (env : List Val) (oc : Val) : IO :=
  .flatMap (ocValTerm node oc) (clo node .gcFinK env)

/-- `io.reportError` (`IO.scala:967-971`): `io.handleErrorWith(t => …)`. -/
def reportErrorTerm (node : Nat) (io : IO) : IO :=
  .handleErrorWith io (clo node .reportK [])

/-- `IO.never` (`IO.scala:1560`, `IO.scala:2198`, `kernel/.../Async.scala:168`):
`IO.async(_ => IO.pure(Some(IO.unit)))`, which is `IOCont(body)` (`IO.scala:1418-1431`). -/
def neverTerm (node : Nat) : IO := .ioCont (clo node .neverBody [])

/-- `I(p)` with `p` at pre-order number `node`, in environment `env`. -/
def tr : Prog → (node : Nat) → (env : List Val) → Except TrErr IO
  | .pure a, _, env => do pure (.pure (← atomVal env a))
  | .raise c, _, _ => pure (.error (userErr c))
  | .delay _ _, node, env => pure (.delay (clo node .delayThunk env))
  | .bind e _, node, env => do pure (.flatMap (← tr e (node + 1) env) (clo node .bindK env))
  | .seq e _, node, env => do pure (.flatMap (← tr e (node + 1) env) (clo node .seqK env))
  | .map e _, node, env => do pure (.map (← tr e (node + 1) env) (clo node .mapFn env))
  | .handleErrorWith e _, node, env => do
    pure (.handleErrorWith (← tr e (node + 1) env) (clo node .hewK env))
  | .attempt e, node, env => do
    pure (.map (.attempt (← tr e (node + 1) env)) (clo node .attemptMap env))
  | .uncancelable _, node, env => pure (.uncancelable (clo node .uncBody env))
  | .poll q e, node, env =>
    -- `env(q) match { case Bound.P(poll) => poll(run(e, env)); case _ => raiseError }`;
    -- `poll(ioa) = UnmaskRunLoop(ioa, id, self)` (`IOFiber.scala:564-567`).
    match env[q]? with
    | some (.poll m f) => do pure (.unmaskRunLoop (← tr e (node + 1) env) m f)
    | _ => pure (.error typeErr)
  | .onCancel e fin _, node, env => do
    -- `run(e).onCancel(IO.delay(emit) *> run(fin).void)`; `*>` = `flatMap(_ => that)`
    -- (`IO.scala:138-139`, `IO.scala:903-904`); `onCancel` = `OnCancel` (`IO.scala:590-591`).
    let ie ← tr e (node + 1) env
    let _ ← tr fin (node + 1 + e.size) env
    pure (.onCancel ie (.flatMap (.delay (clo node .ocFinEmit env)) (clo node .ocFinThen env)))
  | .guaranteeCase e _ _, node, env => do
    -- `IO.guaranteeCase` = `IO.uncancelable { poll => … }` (`IO.scala:523-530`).
    let _ ← tr e (node + 1) env
    pure (.uncancelable (clo node .gcBody env))
  | .canceled, node, _ => pure (.map .canceled (clo node .asUnit []))
  | .cede, node, _ => pure (.map .cede (clo node .asUnit []))
  | .never, node, _ => pure (neverTerm node)
  | .start e, node, env => do pure (.map (.start (← tr e (node + 1) env)) (clo node .fiberHandle []))
  | .join f, _, env => do
    let .fiber _ ← atomVal env f | throw .typeError
    throw (.unsupported "join")
  | .cancel f, _, env => do
    let .fiber _ ← atomVal env f | throw .typeError
    throw (.unsupported "cancel")
  | .racePair a b, node, env => do
    let ia ← tr a (node + 1) env
    let ib ← tr b (node + 1 + a.size) env
    pure (.flatMap (.racePair ia ib) (clo node .rpK []))
  | .sleep ms, node, _ =>
    -- `IO.sleep(fd)` = `Sleep(fd)` (`IO.scala:1692-1696`), then `.as(VUnit)`.
    pure (.map (.sleep ms) (clo node .asUnit []))
  | .refNew v, _, env => do
    let _ ← atomVal env v
    throw (.unsupported "refNew")
  | .refGet r, node, env => do
    let _ ← refId env r
    pure (.delay (clo node .refGetThunk env))
  | .refSet r v, node, env => do
    let _ ← refId env r
    let _ ← atomVal env v
    pure (.flatMap (.delay (clo node .refSetThunk env)) (clo node .refSetThen env))
  | .refModify r _, node, env => do
    let _ ← refId env r
    pure (.delay (clo node .refModifyThunk env))
  | .deferredNew, _, _ => throw (.unsupported "deferredNew")
  | .deferredGet d, _, env => do
    let .deferred _ ← atomVal env d | throw .typeError
    throw (.unsupported "deferredGet")
  | .deferredComplete d v, _, env => do
    let .deferred _ ← atomVal env d | throw .typeError
    let _ ← atomVal env v
    throw (.unsupported "deferredComplete")
  | .async _ _, node, env | .asyncFin _ _ _, node, env =>
    -- `IO.executionContext.flatMap { ec => IO.async[Val] { cb => IO.delay { … } } }`.
    pure (.flatMap .readEC (clo node .asyncEc env))
  | .case on lk rk, node, env => do
    match ← atomVal env on with
    | .left v => tr lk (node + 1) (v :: env)
    | .right v => tr rk (node + 1 + lk.size) (v :: env)
    | _ => pure (.error typeErr)
  | .split on k, node, env => do
    match ← atomVal env on with
    | .pair x y => tr k (node + 1) (y :: x :: env)
    | _ => pure (.error typeErr)

end Difftest

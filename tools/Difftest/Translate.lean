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

## State read at construction

`tr` takes the `View` of the moment when Scala builds the term: `fib.join`/`fib.cancel` read the
fiber outcome (`IO.joinOf`/`IO.cancelOf`), `deferred.get` reads the cell (`IO.deferredGetOf`).
Where Scala builds a sub-term eagerly and the model builds it later in a closure, the closure
captures a snapshot (`snapVal`).

## Ops the model cannot express yet

`racePair` and `sleep` (no `RacePair`/`Sleep` mirror in the step function). See
`unsupportedReason` and the wiki ("Lean side").
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
  /-- Internal (not printed): callback `i` of the `async` with `ContState` `async` is a `later`
  callback. Its task (`Task.cb`) gets the label `cb<id>.<i>`. -/
  | cbLater (async : Nat) (i : Nat)
  /-- `ec.reportFailure(t)` from user code (`reportError`, `IO.scala:967-971`). Printed in the
  `failures` list, not in the trace. -/
  | failure (e : Err)
  deriving DecidableEq, Repr

/-- A trace event as a model value, for `UserEffect.emit`. Tag first. -/
def TraceEv.toVal : TraceEv → Val
  | .call fn arg => .pair (.nat 0) (.pair (.nat fn) arg)
  | .finOnCancel tag => .pair (.nat 1) (.nat tag)
  | .finAsync tag => .pair (.nat 2) (.nat tag)
  | .finGuaranteeCase tag oc => .pair (.nat 3) (.pair (.nat tag) oc)
  | .set ref v => .pair (.nat 4) (.pair (.nat ref) v)
  | .complete d v ok => .pair (.nat 5) (.pair (.nat d) (.pair v (.bool ok)))
  | .asyncReg a => .pair (.nat 6) (.nat a)
  | .cb a i => .pair (.nat 7) (.pair (.nat a) (.nat i))
  | .handle f => .pair (.nat 8) (.nat f)
  | .cbLater a i => .pair (.nat 9) (.pair (.nat a) (.nat i))
  | .failure e => .pair (.nat 10) (.err e)

/-- The inverse of `TraceEv.toVal`. -/
def TraceEv.ofVal? : Val → Option TraceEv
  | .pair (.nat 0) (.pair (.nat fn) arg) => some (.call fn arg)
  | .pair (.nat 1) (.nat tag) => some (.finOnCancel tag)
  | .pair (.nat 2) (.nat tag) => some (.finAsync tag)
  | .pair (.nat 3) (.pair (.nat tag) oc) => some (.finGuaranteeCase tag oc)
  | .pair (.nat 4) (.pair (.nat ref) v) => some (.set ref v)
  | .pair (.nat 5) (.pair (.nat d) (.pair v (.bool ok))) => some (.complete d v ok)
  | .pair (.nat 6) (.nat a) => some (.asyncReg a)
  | .pair (.nat 7) (.pair (.nat a) (.nat i)) => some (.cb a i)
  | .pair (.nat 8) (.nat f) => some (.handle f)
  | .pair (.nat 9) (.pair (.nat a) (.nat i)) => some (.cbLater a i)
  | .pair (.nat 10) (.err e) => some (.failure e)
  | _ => none

/-! ## Construction-time snapshot

Scala builds some sub-terms when the outer term is built (`onCancel` finalizer, the `this` of
`guaranteeCase`, the `async` finalizer at registration). Building reads mutable state in two
places: `fib.join`/`fib.cancel` read `_join`/`_cancel` (`IOFiber.scala:197-207`) and
`deferred.get` reads `cell` (`IODeferred.scala:71`). The model builds these sub-terms later,
inside a closure. So the closure captures a snapshot of that state (fiber outcomes and
`Deferred` cells) as a `Val`, taken when Scala builds the term. -/

/-- An outcome value back as an `Outcome`. -/
def outcomeOfVal? : Val → Option Outcome
  | .ocSucceeded v => some (.succeeded v)
  | .ocErrored e => some (.errored e)
  | .ocCanceled => some .canceled
  | _ => none

/-- A list of optional values as one `Val` (right-nested pairs, `unit` at the end). -/
def optListVal : List (Option Val) → Val
  | [] => .unit
  | x :: xs => .pair (match x with | some v => .some v | none => .none) (optListVal xs)

/-- The inverse of `optListVal`. -/
def optListOfVal : Val → List (Option Val)
  | .pair (.some v) rest => some v :: optListOfVal rest
  | .pair _ rest => none :: optListOfVal rest
  | _ => []

/-- The snapshot of a view: fiber outcomes and `Deferred` cells. `Ref` cells are not read
when a term is built (`Ref.get` is `F.delay(ar.get)`, `SyncRef.scala:30`). -/
def snapVal (v : View) : Val :=
  .pair (optListVal (v.outcomes.map (·.map Outcome.toVal))) (optListVal v.deferreds)

/-- The view of a snapshot (no `Ref` cells). -/
def snapView : Val → View
  | .pair os ds =>
    { outcomes := (optListOfVal os).map (·.bind outcomeOfVal?), deferreds := optListOfVal ds }
  | _ => {}

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
  | "racePair" => "the step function does not mirror RacePair (IOFiber.scala:908-950) yet"
  | "sleep" => "the step function does not mirror Sleep and timers (IOFiber.scala:952-981) yet"
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

/-- `I(p)` with `p` at pre-order number `node`, in environment `env`. `vw` is the state that
Scala reads when it builds the term (see "State read at construction"). -/
def tr : Prog → (node : Nat) → (env : List Val) → (vw : View) → Except TrErr IO
  | .pure a, _, env, _ => do pure (.pure (← atomVal env a))
  | .raise c, _, _, _ => pure (.error (userErr c))
  | .delay _ _, node, env, _ => pure (.delay (clo node .delayThunk env))
  | .bind e _, node, env, vw => do pure (.flatMap (← tr e (node + 1) env vw) (clo node .bindK env))
  | .seq e _, node, env, vw => do pure (.flatMap (← tr e (node + 1) env vw) (clo node .seqK env))
  | .map e _, node, env, vw => do pure (.map (← tr e (node + 1) env vw) (clo node .mapFn env))
  | .handleErrorWith e _, node, env, vw => do
    pure (.handleErrorWith (← tr e (node + 1) env vw) (clo node .hewK env))
  | .attempt e, node, env, vw => do
    pure (.map (.attempt (← tr e (node + 1) env vw)) (clo node .attemptMap env))
  | .uncancelable _, node, env, _ => pure (.uncancelable (clo node .uncBody env))
  | .poll q e, node, env, vw =>
    -- `env(q) match { case Bound.P(poll) => poll(run(e, env)); case _ => raiseError }`;
    -- `poll(ioa) = UnmaskRunLoop(ioa, id, self)` (`IOFiber.scala:564-567`).
    match env[q]? with
    | some (.poll m f) => do pure (.unmaskRunLoop (← tr e (node + 1) env vw) m f)
    | _ => pure (.error typeErr)
  | .onCancel e fin _, node, env, vw => do
    -- `run(e).onCancel(IO.delay(emit) *> run(fin).void)`; `*>` = `flatMap(_ => that)`
    -- (`IO.scala:138-139`, `IO.scala:903-904`); `onCancel` = `OnCancel` (`IO.scala:590-591`).
    -- `run(fin)` is built now: `ocFinThen` captures the snapshot.
    let ie ← tr e (node + 1) env vw
    let _ ← tr fin (node + 1 + e.size) env vw
    pure (.onCancel ie (.flatMap (.delay (clo node .ocFinEmit env))
      (clo node .ocFinThen (snapVal vw :: env))))
  | .guaranteeCase e _ _, node, env, vw => do
    -- `IO.guaranteeCase` = `IO.uncancelable { poll => … }` (`IO.scala:523-530`). `run(e)` is
    -- built now: `gcBody` captures the snapshot.
    let _ ← tr e (node + 1) env vw
    pure (.uncancelable (clo node .gcBody (snapVal vw :: env)))
  | .canceled, node, _, _ => pure (.map .canceled (clo node .asUnit []))
  | .cede, node, _, _ => pure (.map .cede (clo node .asUnit []))
  | .never, node, _, _ => pure (neverTerm node)
  | .start e, node, env, vw => do
    pure (.map (.start (← tr e (node + 1) env vw)) (clo node .fiberHandle []))
  | .join f, node, env, vw => do
    -- `fiberOf(⟦f⟧).join.flatMap(ocVal)`; `join` reads `_join` now (`IOFiber.scala:203-207`).
    let .fiber t ← atomVal env f | throw .typeError
    pure (.flatMap (IO.joinOf t (vw.outcome t)) (clo node .ocValK []))
  | .cancel f, node, env, vw => do
    -- `fiberOf(⟦f⟧).cancel.as(VUnit)`; `cancel` reads `_cancel` now (`IOFiber.scala:197-201`);
    -- `as` = `map(_ => b)` (`IO.scala:182-183`).
    let .fiber t ← atomVal env f | throw .typeError
    pure (.map (IO.cancelOf t (vw.outcome t)) (clo node .asUnit []))
  | .racePair a b, node, env, vw => do
    let ia ← tr a (node + 1) env vw
    let ib ← tr b (node + 1 + a.size) env vw
    pure (.flatMap (.racePair ia ib) (clo node .rpK []))
  | .sleep ms, node, _, _ =>
    -- `IO.sleep(fd)` = `Sleep(fd)` (`IO.scala:1692-1696`), then `.as(VUnit)`.
    pure (.map (.sleep ms) (clo node .asUnit []))
  | .refNew v, node, env, _ => do
    -- `IO.ref(v).map(r => VRef(h.newRef(r)))`; `IO.ref(a) = IO(Ref.unsafe(a))` (`IO.scala:1822`);
    -- `IO(a) = delay(a)` (`IO.scala:1275`).
    let _ ← atomVal env v
    pure (.map (.delay (clo node .refNewThunk env)) (clo node .refHandle []))
  | .refGet r, node, env, _ => do
    let _ ← refId env r
    pure (.delay (clo node .refGetThunk env))
  | .refSet r v, node, env, _ => do
    let _ ← refId env r
    let _ ← atomVal env v
    pure (.flatMap (.delay (clo node .refSetThunk env)) (clo node .refSetThen env))
  | .refModify r _, node, env, _ => do
    let _ ← refId env r
    pure (.delay (clo node .refModifyThunk env))
  | .deferredNew, node, _, _ =>
    -- `IO.deferred[Val].map(d => VDeferred(h.newDeferred(d)))`;
    -- `IO.deferred = IO(new IODeferred[A])` (`IO.scala:1824`).
    pure (.map (.delay (clo node .deferredNewThunk [])) (clo node .deferredHandle []))
  | .deferredGet d, _, env, vw => do
    -- `deferredOf(⟦d⟧).get` reads `cell` now (`IODeferred.scala:71`).
    let .deferred i ← atomVal env d | throw .typeError
    pure (IO.deferredGetOf i (vw.deferred i))
  | .deferredComplete d v, node, env, _ => do
    -- `dfd.complete(v).flatMap(ok => IO.delay { emit complete; VBool(ok) })`;
    -- `complete(a) = IO { … }` (`IODeferred.scala:62-69`).
    let .deferred i ← atomVal env d | throw .typeError
    let x ← atomVal env v
    pure (.flatMap (.delay (.rt (.deferredComplete i x))) (clo node .dcThen env))
  | .async _ _, node, env, _ | .asyncFin _ _ _, node, env, _ =>
    -- `IO.executionContext.flatMap { ec => IO.async[Val] { cb => IO.delay { … } } }`.
    pure (.flatMap .readEC (clo node .asyncEc env))
  | .case on lk rk, node, env, vw => do
    match ← atomVal env on with
    | .left v => tr lk (node + 1) (v :: env) vw
    | .right v => tr rk (node + 1 + lk.size) (v :: env) vw
    | _ => pure (.error typeErr)
  | .split on k, node, env, vw => do
    match ← atomVal env on with
    | .pair x y => tr k (node + 1) (y :: x :: env) vw
    | _ => pure (.error typeErr)

end Difftest

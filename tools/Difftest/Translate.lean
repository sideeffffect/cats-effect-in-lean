import Difftest.Closure
import CatsEffectInLean.Model.Syntax
import CatsEffectInLean.Model.Resource
import CatsEffectInLean.Model.Timeout
import CatsEffectInLean.Model.Race
import CatsEffectInLean.Model.Bracket
import CatsEffectInLean.Std.Queue

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

None (`unsupportedReason`). `racePair` and `sleep` run on the `RacePair` and `Sleep` mirrors
of the step function. Format v1: `timeoutTo` with a user fallback runs on
`Timeout.timeoutToIO` (since 2026-11-10; before, it was `unsupported`).

## Format v1: library mirrors

* `timeout e ms` is `Timeout.timeoutIO src ms` (`Model/Timeout.lean`). The source `I(e)` is
  the code `src` of a `timeoutSrc` closure value (node, snapshot, environment); `srcIO`
  (`Difftest/Env.lean`) builds it. `timeoutTo e ms fb` is `Timeout.timeoutToIO src c ms`; the
  fallback `I(fb)` is the code `c` of a `timeoutFb` closure value.
* The queue ops are the `Std/Queue.lean` terms (`newIO`, `offerIO`, `takeIO`, `tryTakeIO`),
  plus the `Map` of the interpreter (`.as(VUnit)`, the `Option` selection, the handle).
* `allocatedCase res` is `Resource.allocatedCase R res` (`Model/Resource.lean`), then
  `.map(_._1)`. `R : Resource.REnv` gives the meaning of the resource codes (`renvOf`): `bind`,
  `acquire` and `release` translate the sub-program of the node in the code. These functions
  take no `View`, so a program inside a resource node must not read state when it is built
  (`Prog.resViewFree`; otherwise the case is `unsupported`).
* `IdPoll`. `SyncStep.interpret` calls an `uncancelable` body with `idPollVal = poll 0 0`
  (`Model/SyncStep.lean`), and `IdPoll(fa) = fa` (`IO.scala:2391-2393`). Real `poll` ids
  start at 1. So `poll` with mask id 0 is the identity here (`pollTerm`).
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
  /-- Internal (not printed): `h.newRef` gives the `Ref` with model cell id `ref` its handle
  (format v1: queue cells share the model cell ids, so the glue renumbers). -/
  | refH (ref : Nat)
  /-- Internal (not printed): `h.newQueue` gives the queue with buffer cell `buf` its handle. -/
  | queueH (buf : Nat)
  /-- Format v2: a `guarantee` (`op = 0`), `bracket` (1), `bracketCase` (2) or `bracketFull` (3)
  finalizer starts; `oc` for the last two. -/
  | finV2 (op : Nat) (tag : Nat) (oc : Option Val)
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
  | .refH r => .pair (.nat 11) (.nat r)
  | .queueH b => .pair (.nat 12) (.nat b)
  | .finV2 op tag oc => .pair (.nat 13) (.pair (.nat op) (.pair (.nat tag)
      (match oc with | some o => .some o | none => .none)))

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
  | .pair (.nat 11) (.nat r) => some (.refH r)
  | .pair (.nat 12) (.nat b) => some (.queueH b)
  | .pair (.nat 13) (.pair (.nat op) (.pair (.nat tag) .none)) => some (.finV2 op tag none)
  | .pair (.nat 13) (.pair (.nat op) (.pair (.nat tag) (.some o))) => some (.finV2 op tag (some o))
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

/-- What the model lacks for each unsupported op. Every op of formats v0 and v1 runs on the
model. -/
def unsupportedReason : String → String
  | _ => "unknown"

/-- `⟦a⟧`. -/
def atomVal (env : List Val) : Atom → Except TrErr Val
  | .lit v => .ok v
  | .var i => match env[i]? with
    | some v => .ok v
    | none => .error .typeError

/-- `queueOf` (`Interp.scala`): the queue of an atom. A queue is the model cell id of its
buffer (`Std.Queue`), a `Val.ref`. -/
def queueId (env : List Val) (a : Atom) : Except TrErr Nat := do
  match ← atomVal env a with
  | .ref i => pure i
  | _ => throw .typeError

/-- `poll(io)` with the poll value `(m, f)`: `UnmaskRunLoop(io, m, f)` (`IOFiber.scala:564-567`),
or `io` for the `IdPoll` of `syncStep` (mask id 0, `IO.scala:2391-2393`). -/
def pollTerm (io : IO) (m f : Nat) : IO := if m == 0 then io else .unmaskRunLoop io m f

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

/-- A translation error as a thrown error. -/
def TrErr.toErr : TrErr → Err
  | .typeError => typeErr
  | .unsupported _ => harnessErr

/-- The two source codes of a v2 combinator at `node` (`raceSrcA`, `raceSrcB`, with the
snapshot); `Env.srcIO` rebuilds `I(a)` and `I(b)` from them. -/
def combSrcs (node : Nat) (env : List Val) (vw : View) : Val × Val :=
  (.nat (Clo.encode { node, lam := .raceSrcA, vals := snapVal vw :: env }),
   .nat (Clo.encode { node, lam := .raceSrcB, vals := snapVal vw :: env }))

mutual
/-- `I(p)` with `p` at pre-order number `node`, in environment `env`. `vw` is the state that
Scala reads when it builds the term (see "State read at construction"). `R` gives the meaning
of the resource codes (`renvOf`). -/
def tr (R : Resource.REnv) : Prog → (node : Nat) → (env : List Val) → (vw : View) → Except TrErr IO
  | .pure a, _, env, _ => do pure (.pure (← atomVal env a))
  | .raise c, _, _, _ => pure (.error (userErr c))
  | .delay _ _, node, env, _ => pure (.delay (clo node .delayThunk env))
  | .bind e _, node, env, vw => do pure (.flatMap (← tr R e (node + 1) env vw) (clo node .bindK env))
  | .seq e _, node, env, vw => do pure (.flatMap (← tr R e (node + 1) env vw) (clo node .seqK env))
  | .map e _, node, env, vw => do pure (.map (← tr R e (node + 1) env vw) (clo node .mapFn env))
  | .handleErrorWith e _, node, env, vw => do
    pure (.handleErrorWith (← tr R e (node + 1) env vw) (clo node .hewK env))
  | .attempt e, node, env, vw => do
    pure (.map (.attempt (← tr R e (node + 1) env vw)) (clo node .attemptMap env))
  | .uncancelable _, node, env, _ => pure (.uncancelable (clo node .uncBody env))
  | .poll q e, node, env, vw =>
    -- `env(q) match { case Bound.P(poll) => poll(run(e, env)); case _ => raiseError }`;
    -- `poll(ioa) = UnmaskRunLoop(ioa, id, self)` (`IOFiber.scala:564-567`).
    match env[q]? with
    | some (.poll m f) => do pure (pollTerm (← tr R e (node + 1) env vw) m f)
    | _ => pure (.error typeErr)
  | .onCancel e fin _, node, env, vw => do
    -- `run(e).onCancel(IO.delay(emit) *> run(fin).void)`; `*>` = `flatMap(_ => that)`
    -- (`IO.scala:138-139`, `IO.scala:903-904`); `onCancel` = `OnCancel` (`IO.scala:590-591`).
    -- `run(fin)` is built now: `ocFinThen` captures the snapshot.
    let ie ← tr R e (node + 1) env vw
    let _ ← tr R fin (node + 1 + e.size) env vw
    pure (.onCancel ie (.flatMap (.delay (clo node .ocFinEmit env))
      (clo node .ocFinThen (snapVal vw :: env))))
  | .guaranteeCase e _ _, node, env, vw => do
    -- `IO.guaranteeCase` = `IO.uncancelable { poll => … }` (`IO.scala:523-530`). `run(e)` is
    -- built now: `gcBody` captures the snapshot.
    let _ ← tr R e (node + 1) env vw
    pure (.uncancelable (clo node .gcBody (snapVal vw :: env)))
  | .canceled, node, _, _ => pure (.map .canceled (clo node .asUnit []))
  | .cede, node, _, _ => pure (.map .cede (clo node .asUnit []))
  | .never, node, _, _ => pure (neverTerm node)
  | .start e, node, env, vw => do
    pure (.map (.start (← tr R e (node + 1) env vw)) (clo node .fiberHandle []))
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
    let ia ← tr R a (node + 1) env vw
    let ib ← tr R b (node + 1 + a.size) env vw
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
    | .left v => tr R lk (node + 1) (v :: env) vw
    | .right v => tr R rk (node + 1 + lk.size) (v :: env) vw
    | _ => pure (.error typeErr)
  | .split on k, node, env, vw => do
    match ← atomVal env on with
    | .pair x y => tr R k (node + 1) (y :: x :: env) vw
    | _ => pure (.error typeErr)
  -- format v1
  | .syncStep _ _, _, _, _ => throw .typeError -- below the root: the decoder prevents this
  | .timeout e ms, node, env, vw => do
    -- `I(e).timeout(ms.millis)` (`IO.scala:818-823`, `IO.scala:850-860`) = `Timeout.timeoutIO`.
    -- Scala builds `I(e)` now; the model builds it in the `body` closure from `src`, with the
    -- snapshot.
    let _ ← tr R e (node + 1) env vw
    pure (Timeout.timeoutIO (.nat (Clo.encode { node, lam := .timeoutSrc, vals := snapVal vw :: env })) ms)
  | .timeoutTo e fb ms, node, env, vw => do
    -- `I(e).timeoutTo(ms.millis, I(fb))` (`IO.scala:850-860`) = `Timeout.timeoutToIO`. Scala
    -- builds `I(e)`, then `I(fb)`, now; the model builds them in closures from the codes, with
    -- the snapshot.
    let _ ← tr R e (node + 1) env vw
    let _ ← tr R fb (node + 1 + e.size) env vw
    let code (lam : Lam) : Val := .nat (Clo.encode { node, lam, vals := snapVal vw :: env })
    pure (Timeout.timeoutToIO (code .timeoutSrc) (code .timeoutFb) ms)
  | .queueNew, node, _, _ =>
    -- `Queue.unbounded[IO, Val].map(q => VQueue(h.newQueue(q)))` (`Queue.scala:160-167`)
    pure (.map CatsEffectInLean.Std.Queue.newIO (clo node .queueHandle []))
  | .queueOffer q v, node, env, _ => do
    -- `queueOf(⟦q⟧).offer(⟦v⟧).as(VUnit)`
    let b ← queueId env q
    let x ← atomVal env v
    pure (.map (CatsEffectInLean.Std.Queue.offerIO b x) (clo node .asUnit []))
  | .queueTake q, _, env, _ => do
    -- `queueOf(⟦q⟧).take`
    pure (CatsEffectInLean.Std.Queue.takeIO (← queueId env q))
  | .queueTryTake q, node, env, _ => do
    -- `queueOf(⟦q⟧).tryTake.map { case Some(v) => VRight(v); case None => VLeft(VUnit) }`
    pure (.map (CatsEffectInLean.Std.Queue.tryTakeIO (← queueId env q)) (clo node .optEither []))
  | .allocatedCase r, node, env, _ => do
    -- `I_R(r).allocatedCase.map(_._1)`; `allocatedCase` runs `loop` now (`Resource.scala:464-531`)
    let res ← trRes R r (node + 1) env
    match Resource.allocatedCase R res with
    | .ok io => pure (.map io (clo node .allocFst []))
    | .error _ => throw .typeError
  | .rPure _, _, _, _ | .rEval _, _, _, _ | .rMake _ _, _, _, _ | .rFlatMap _ _, _, _, _ =>
    throw .typeError -- a resource node at an `IO` position: the decoder prevents this
  -- format v2: `I(a).<op>(I(b))` (`IO.scala:638`, `:641`, `:243`, `:228`) = the kernel default
  -- with `IOAsync` (`Model/Race.lean`). Scala builds `I(a)` then `I(b)` now; the model builds them
  -- in the `body` closure from the source codes `raceSrcA`/`raceSrcB`, with the snapshot.
  | .race a b, node, env, vw => do
    let _ ← tr R a (node + 1) env vw
    let _ ← tr R b (node + 1 + a.size) env vw
    let (sa, sb) := combSrcs node env vw
    -- `.map { case Left(v) => VLeft(v); case Right(v) => VRight(v) }`
    pure (.map (Race.raceIO sa sb) (clo node .raceK []))
  | .raceOutcome a b, node, env, vw => do
    let _ ← tr R a (node + 1) env vw
    let _ ← tr R b (node + 1 + a.size) env vw
    let (sa, sb) := combSrcs node env vw
    -- `.flatMap { case Left(oc) => ocVal(oc).map(VLeft(_)); case Right(oc) => ... }`
    pure (.flatMap (Race.raceOutcomeIO sa sb) (clo node .roK []))
  | .both a b, node, env, vw => do
    let _ ← tr R a (node + 1) env vw
    let _ ← tr R b (node + 1 + a.size) env vw
    let (sa, sb) := combSrcs node env vw
    -- `.map { case (x, y) => VPair(x, y) }`
    pure (.map (Race.bothIO sa sb) (clo node .pairK []))
  | .bothOutcome a b, node, env, vw => do
    let _ ← tr R a (node + 1) env vw
    let _ ← tr R b (node + 1 + a.size) env vw
    let (sa, sb) := combSrcs node env vw
    -- `.flatMap { case (oa, ob) => ocVal(oa).flatMap(x => ocVal(ob).map(y => VPair(x, y))) }`
    pure (.flatMap (Race.bothOutcomeIO sa sb) (clo node .boK []))
  -- format v2: the mirror `Model/Bracket.lean`
  | .guarantee e fin _, node, env, vw => do
    -- `run(e).guarantee(IO.delay(emit) *> run(fin).void)` (`IO.scala:496-501`): both built now;
    -- the source codes capture the snapshot (`Env.bracketSrcIO` rebuilds them)
    let _ ← tr R e (node + 1) env vw
    let _ ← tr R fin (node + 1 + e.size) env vw
    let sv := snapVal vw :: env
    pure (Bracket.guaranteeIO (.ext (.nat (Clo.encode { node, lam := .gSrcE, vals := sv })))
      (.ext (.nat (Clo.encode { node, lam := .gSrcFin, vals := sv }))))
  | .bracket acq _ _ _, node, env, vw => do
    -- `run(acq).bracket(use)(release)` (`IO.scala:338-339`); `run(acq)` is built now
    let _ ← tr R acq (node + 1) env vw
    pure (Bracket.bracketIO (.ext (.nat (Clo.encode { node, lam := .brAcqSrc, vals := snapVal vw :: env })))
      (cloId node .brUse env) (cloId node .brRel env))
  | .bracketCase acq _ _ _, node, env, vw => do
    -- `run(acq).bracketCase(use)(release)` (`IO.scala:370-371`)
    let _ ← tr R acq (node + 1) env vw
    pure (Bracket.bracketCaseIO (.ext (.nat (Clo.encode { node, lam := .brAcqSrc, vals := snapVal vw :: env })))
      (cloId node .brUse env) (cloId node .brcRel env))
  | .bracketFull _ _ _ _, node, env, _ =>
    -- `IO.bracketFull(acquire)(use)(release)` (`IO.scala:1826-1830`)
    pure (Bracket.bracketFullIO (cloId node .bfAcq env) (cloId node .brUse env) (cloId node .brcRel env))


/-- `I_R(r)`: the `Resource` term of a resource node (`Interp.scala` `res`). The `IO` programs
inside are built with an empty view (the resource restriction, `Prog.resViewFree`). -/
def trRes (R : Resource.REnv) : Prog → (node : Nat) → (env : List Val) → Except TrErr Resource.Res
  -- `Resource.pure(⟦a⟧)` (`Resource.scala:977-978`)
  | .rPure a, _, env => do pure (Resource.Res.pureOf (← atomVal env a))
  -- `Resource.eval(I(e))` (`Resource.scala:992-993`)
  | .rEval e, node, env => do pure (Resource.Res.evalOf (← tr R e (node + 1) env {}))
  -- `Resource.make(I(acq))(a => I(rel)[x := a].void)` (`Resource.scala:900-902`); `I(acq)` is
  -- built now, `I(rel)` when the release function runs
  | .rMake acq _, node, env => do
    let _ ← tr R acq (node + 1) env {}
    pure (Resource.Res.make (Clo.encode { node, lam := .resAcquire, vals := env })
      (Clo.encode { node, lam := .resRelease, vals := env }))
  -- `I_R(r).flatMap(v => I_R(k)[x := v])` (`Resource.scala:388-389`)
  | .rFlatMap r _, node, env => do
    pure (Resource.Res.flatMap (← trRes R r (node + 1) env) (Clo.encode { node, lam := .resBind, vals := env }))
  | _, _, _ => throw .typeError
end

/-! ## The meaning of the resource codes -/

/-- A user environment for `REnv.user`: the translation never makes `AllocFn.user` or
`RelFn.user`, so it is never called. -/
def harnessUser : UserEnv where
  call _ _ _ := { out := .throw harnessErr }

/-- `REnv` with lookup `look` (pre-order node number → node of the root program). `fuel`
bounds the nesting of `allocatedCase` inside resource nodes. -/
def renvF (look : Nat → Option Prog) : Nat → Resource.REnv
  | 0 =>
    { user := harnessUser, bind := fun _ _ => .error harnessErr, acquire := fun _ => .error harnessErr,
      release := fun _ _ => .error harnessErr }
  | n + 1 =>
    let R := renvF look n
    { user := harnessUser
      -- `v => I_R(k)[x := v]` of `rFlatMap`
      bind := fun k v =>
        match Clo.decode? k with
        | some { node, lam := .resBind, vals } =>
          match look node with
          | some (.rFlatMap r kk) =>
            match trRes R kk (node + 1 + r.size) (v :: vals) with
            | .ok res => .ok res
            | .error e => .error e.toErr
          | _ => .error harnessErr
        | _ => .error harnessErr
      -- `I(acq)` of `rMake`
      acquire := fun k =>
        match Clo.decode? k with
        | some { node, lam := .resAcquire, vals } =>
          match look node with
          | some (.rMake acq _) =>
            match tr R acq (node + 1) vals {} with
            | .ok io => io
            | .error e => .error e.toErr
          | _ => .error harnessErr
        | _ => .error harnessErr
      -- `a => I(rel)[x := a].void` of `rMake`; `void` = `map(_ => ())` (`IO.scala:961-962`)
      release := fun k a =>
        match Clo.decode? k with
        | some { node, lam := .resRelease, vals } =>
          match look node with
          | some (.rMake acq rel) =>
            match tr R rel (node + 1 + acq.size) (a :: vals) {} with
            | .ok io => .ok (.map io (clo node .voidFn []))
            | .error e => .error e.toErr
          | _ => .error harnessErr
        | _ => .error harnessErr }

/-- The `REnv` of root program `p`. -/
def renvOf (p : Prog) : Resource.REnv := renvF p.at? (p.size + 1)

end Difftest

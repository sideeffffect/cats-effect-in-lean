import Difftest.Translate

/-!
# The user environment of a difftest program

`denv p id arg vw` runs closure `id` (`Clo.decode?`) of program `p` with the view `vw` (the
`Ref` cells, fiber outcomes and `Deferred` cells that user code sees). It mirrors the Scala
lambda named in `Lam`. `userEnv p` is the `Model.UserEnv`: trace events and `reportFailure`
calls become `UserEffect.emit` effects (`TraceEv.toVal`), before the other effects
(`DResult.toUser`). The `async` registration puts its events in `effects` itself, in Scala
order.
-/

namespace Difftest

open CatsEffectInLean.Model

/-- A translation result as a closure result (a program, or a thrown error). -/
def ofTr : Except TrErr IO → DResult
  | .ok io => { base := { out := .prog io } }
  | .error .typeError => { base := { out := .throw typeErr } }
  | .error (.unsupported _) => DResult.harness

/-- Return a value. -/
def ret (v : Val) (trace : List TraceEv := []) : DResult := { base := { out := .ret v }, trace }

/-- Return a program. -/
def prog (io : IO) : DResult := { base := { out := .prog io } }

/-- The model result: trace events and failures become `emit` effects, first. -/
def DResult.toUser (r : DResult) : UserResult :=
  { r.base with effects := r.trace.map (.emit ∘ TraceEv.toVal)
      ++ r.failures.map (.emit ∘ TraceEv.toVal ∘ .failure) ++ r.base.effects }

/-- Run closure `c` (made by node `n` of the program) on `arg` with view `vw`. -/
def runClo (c : Clo) (n : Prog) (arg : Val) (vw : View) : DResult :=
  let refs := vw.refs
  let node := c.node
  let env := c.vals
  match c.lam, n with
  | .delayThunk, .delay fn a =>
    match atomVal env a with
    | .ok v => callUser fn v
    | .error e => ofTr (.error e)
  | .bindK, .bind e k => ofTr (tr k (node + 1 + e.size) (arg :: env) vw)
  | .seqK, .seq e k => ofTr (tr k (node + 1 + e.size) env vw)
  | .mapFn, .map _ fn => callUser fn arg
  | .hewK, .handleErrorWith e k =>
    match arg with
    | .err t => match userCode? t with
      | some c => ofTr (tr k (node + 1 + e.size) (.nat c :: env) vw)
      | none => prog (.error t)
    | _ => DResult.harness
  | .attemptMap, .attempt _ =>
    match arg with
    | .right v => ret (.right v)
    | .left (.err t) => match userCode? t with
      | some c => ret (.left (.nat c))
      | none => { base := { out := .throw t } }
    | _ => DResult.harness
  | .uncBody, .uncancelable body => ofTr (tr body (node + 1) (arg :: env) vw)
  | .ocFinEmit, .onCancel _ _ tag => ret .unit [.finOnCancel tag]
  | .ocFinThen, .onCancel e fin _ =>
    -- `run(fin)` was built with the `onCancel` term: use the captured snapshot
    match env with
    | snap :: env0 =>
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$> tr fin (node + 1 + e.size) env0 (snapView snap))
    | [] => DResult.harness
  | .voidFn, _ => ret .unit
  | .asUnit, _ => ret .unit
  | .gcBody, .guaranteeCase e _ _ =>
    -- `IO.scala:524-530`:
    -- `val finalized = poll(this).onCancel(finalizer(Outcome.canceled))`
    -- `finalized.onError(onError).flatTap(a => finalizer(Outcome.succeeded(IO.pure(a))))`
    -- `onError(pf) = handleErrorWith(t => pf.applyOrElse(t, …) *> IO.raiseError(t))`
    -- (`IO.scala:605-606`); `flatTap(f) = flatMap(a => f(a).as(a))` (`IO.scala:474`).
    -- `run(e)` was built with the `guaranteeCase` term: use the captured snapshot
    match arg, env with
    | .poll m f, snap :: env =>
      ofTr ((fun ie =>
        let finalized := IO.onCancel (.unmaskRunLoop ie m f) (gcFinalizer node env .ocCanceled)
        IO.flatMap (.handleErrorWith finalized (clo node .gcOnError env))
          (clo node .gcTap env)) <$> tr e (node + 1) env (snapView snap))
    | _, _ => DResult.harness
  | .gcOnError, .guaranteeCase _ _ _ =>
    -- `pf = { case e => finalizer(Outcome.errored(e)).reportError }` (`IO.scala:526-528`),
    -- then `*> IO.raiseError(t)`.
    match arg with
    | .err t =>
      prog (.flatMap (reportErrorTerm node (gcFinalizer node env (.ocErrored t)))
        (clo node .constRaise [.err t]))
    | _ => DResult.harness
  | .constRaise, _ =>
    match env with
    | [.err t] => prog (.error t)
    | _ => DResult.harness
  | .reportK, _ =>
    -- `t => IO.executionContext.flatMap(ec => IO(ec.reportFailure(t)))` (`IO.scala:969-971`).
    match arg with
    | .err t => prog (.flatMap .readEC (clo node .reportEc [.err t]))
    | _ => DResult.harness
  | .reportEc, _ => prog (.delay (clo node .reportThunk env))
  | .reportThunk, _ =>
    match env with
    | [.err t] => { base := { out := .ret .unit }, failures := [t] }
    | _ => DResult.harness
  | .gcTap, .guaranteeCase _ _ _ =>
    prog (.map (gcFinalizer node env (.ocSucceeded arg)) (clo node .constVal [arg]))
  | .constVal, _ =>
    match env with
    | [a] => ret a
    | _ => DResult.harness
  | .succFn, _ => ret (.ocSucceeded arg)
  | .gcFinK, .guaranteeCase _ _ _ =>
    prog (.flatMap (.delay (clo node .gcFinEmit (arg :: env))) (clo node .gcFinThen (arg :: env)))
  | .gcFinEmit, .guaranteeCase _ _ tag =>
    match env with
    | o :: _ => ret .unit [.finGuaranteeCase tag o]
    | [] => DResult.harness
  | .gcFinThen, .guaranteeCase e fin _ =>
    -- Scala builds `run(fin)` in `o => IO.delay(emit) *> run(fin).void`, one run-loop iteration
    -- before this closure runs (`FlatMap` over `Delay`, `IOFiber.scala:420-437`); nothing else
    -- runs in between, so the current view is the same.
    ofTr ((fun io => IO.map io (clo node .voidFn [])) <$> tr fin (node + 1 + e.size) env vw)
  | .fiberHandle, _ =>
    match arg with
    | .fiber i => ret (.fiber i) [.handle i]
    | _ => DResult.harness
  | .ocValK, _ => prog (ocValTerm node arg)
  | .rpK, .racePair _ _ =>
    match arg with
    | .left (.pair oc fb) => prog (.map (ocValTerm node oc) (clo node .rpLeft [fb]))
    | .right (.pair fa oc) => prog (.map (ocValTerm node oc) (clo node .rpRight [fa]))
    | _ => DResult.harness
  | .rpLeft, _ =>
    match env with
    | [.fiber i] => ret (.left (.pair arg (.fiber i))) [.handle i]
    | _ => DResult.harness
  | .rpRight, _ =>
    match env with
    | [.fiber i] => ret (.right (.pair (.fiber i) arg)) [.handle i]
    | _ => DResult.harness
  | .refGetThunk, .refGet r =>
    match refId env r with
    | .ok i => match refs[i]? with
      | some v => ret v
      | none => DResult.harness
    | .error e => ofTr (.error e)
  | .refSetThunk, .refSet r v =>
    match refId env r, atomVal env v with
    | .ok i, .ok x => { base := { effects := [.writeRef i x], out := .ret .unit } }
    | _, _ => ofTr (.error .typeError)
  | .refSetThen, .refSet _ _ => prog (.delay (clo node .refSetEmit env))
  | .refSetEmit, .refSet r v =>
    match refId env r, atomVal env v with
    | .ok i, .ok x => ret .unit [.set i x]
    | _, _ => ofTr (.error .typeError)
  | .refModifyThunk, .refModify r fn =>
    -- `modify(f) = F.delay(spin)`, `spin`: `c = ar.get; (u, b) = f(c); CAS` (`SyncRef.scala:85-94`).
    -- One model step is atomic, so the CAS always succeeds.
    match refId env r with
    | .ok i => match refs[i]? with
      | some c =>
        let r := callUser fn c
        match r.base.out with
        | .ret (.pair u b) => { r with base := { effects := [.writeRef i u], out := .ret b } }
        | .ret _ => { r with base := { out := .throw typeErr } }
        | _ => r
      | none => DResult.harness
    | .error e => ofTr (.error e)
  | .asyncEc, _ => prog (.ioCont (clo node .asyncBody (arg :: env)))
  | .asyncBody, _ =>
    -- `G.uncancelable { poll => … }` with `G = asyncForIO`: `IO.uncancelable` (`IO.scala:2095-2096`).
    prog (.uncancelable (clo node .asyncUnc (arg :: env)))
  | .asyncUnc, _ =>
    -- `lift(k(resume)) flatMap { … }`; `lift = FunctionK.id` (`IOFiber.scala:658`);
    -- `k(cb) = IO.delay { … }` (the registration).
    prog (.flatMap (.delay (clo node .asyncReg env)) (clo node .asyncSel (arg :: env)))
  | .asyncReg, n@(.async cbs _) | .asyncReg, n@(.asyncFin cbs _ _) =>
    -- `IO.delay { id = newAsync; emit asyncReg; for each callback: sync ↦ emit cb; cb(r),
    -- later ↦ ec.execute(task); fin.map(f => IO.delay(emit fin) *> run(f, env).void) }`.
    -- `cbLater` is internal: it gives the label of the task. `Some(io)` cannot be a `Val`:
    -- `some snap` marks it, with the snapshot for `run(f, env)` (built here in Scala).
    match env with
    | .cont s :: _ =>
      let hasFin := match n with | .asyncFin .. => true | _ => false
      let ev (e : TraceEv) : UserEffect := .emit e.toVal
      let effects := cbs.zipIdx.foldl (init := [ev (.asyncReg s)])
        fun effs (c, i) => match c.when with
          | .sync => effs ++ [ev (.cb s i), .invokeCb s c.res.toVal]
          | .later => effs ++ [ev (.cbLater s i), .deferCb s c.res.toVal]
      { base := { effects, out := .ret (if hasFin then .some (snapVal vw) else .none) } }
    | _ => DResult.harness
  | .asyncSel, n =>
    match env with
    | .poll m f :: .cont s :: _ :: env0 =>
      match arg, n with
      | .some snap, .asyncFin _ _ _ =>
        -- `G.onCancel(poll(get), lift(fin))` = `OnCancel(UnmaskRunLoop(Get(s), m, f), fin)`;
        -- `fin = IO.delay(emit fin) *> I(f).void`.
        prog (.onCancel (.unmaskRunLoop (.contGet s) m f)
          (.flatMap (.delay (clo node .asyncFinEmit env0)) (clo node .asyncFinThen (snap :: env0))))
      | .none, _ => prog (.contGet s)
      | _, _ => DResult.harness
    | _ => DResult.harness
  | .asyncFinEmit, .asyncFin _ _ tag => ret .unit [.finAsync tag]
  | .asyncFinThen, .asyncFin _ fin _ =>
    match env with
    | snap :: env0 =>
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$> tr fin (node + 1) env0 (snapView snap))
    | [] => DResult.harness
  | .neverBody, _ => prog (.uncancelable (clo node .neverUnc [arg]))
  | .neverUnc, _ =>
    -- `k = _ => pure(Some(unit))`: `IO.pure(Some(IO.unit))`; `some unit` marks `Some(IO.unit)`.
    prog (.flatMap (.pure (.some .unit)) (clo node .neverSel (arg :: env)))
  | .neverSel, _ =>
    match env, arg with
    | [.poll m f, .cont s], .some _ => prog (.onCancel (.unmaskRunLoop (.contGet s) m f) (.pure .unit))
    | [_, .cont s], .none => prog (.contGet s)
    | _, _ => DResult.harness
  | .refNewThunk, .refNew a =>
    -- `Ref.unsafe(v)` = `new SyncRef(v)` (`Ref.scala:314`): a new cell; its id is the number
    -- of cells before it (`UserEffect.allocRef`)
    match atomVal env a with
    | .ok v => { base := { effects := [.allocRef v], out := .ret (.ref refs.length) } }
    | .error e => ofTr (.error e)
  -- `h.newRef(r)` counts `Ref`s in creation order: the same number as the cell id, because the
  -- thunk and this function run in one run-loop iteration (`Map` over `Delay`, `IOFiber.scala:349-368`)
  | .refHandle, _ => ret arg
  | .deferredNewThunk, _ =>
    { base := { effects := [.allocDeferred], out := .ret (.deferred vw.deferreds.length) } }
  | .deferredHandle, _ => ret arg
  | .dcThen, .deferredComplete _ _ => prog (.delay (clo node .dcEmit (arg :: env)))
  | .dcEmit, .deferredComplete d v =>
    match env with
    | .bool ok :: env0 =>
      match atomVal env0 d, atomVal env0 v with
      | .ok (.deferred i), .ok x => ret (.bool ok) [.complete i x ok]
      | _, _ => ofTr (.error .typeError)
    | _ => DResult.harness
  | _, _ => DResult.harness

/-- The closures of program `p`, with trace and failure lists. -/
def denv (p : Prog) (id : Nat) (arg : Val) (vw : View) : DResult :=
  match Clo.decode? id with
  | none => DResult.harness
  | some c => match p.at? c.node with
    | none => DResult.harness
    | some n => runClo c n arg vw

/-- The `Model.UserEnv` of program `p` (see module doc). -/
def userEnv (p : Prog) : UserEnv where
  call id arg refs := (denv p id arg { refs }).toUser
  callV id arg vw := (denv p id arg vw).toUser

/-- The view of the root term: only the root fiber, not completed. -/
def rootView : View := { outcomes := [none] }

/-- The root term `I(p)` (`Interp.apply`: `run(p, Map.empty)`). -/
def rootTerm (p : Prog) : Except TrErr IO := tr p 0 [] rootView

/-- Ops in `p` that the model cannot express yet (no repeats, in first-use order). -/
def unsupportedOps (p : Prog) : List String :=
  (p.ops.filter fun o => unsupportedReason o != "unknown").eraseDups

end Difftest

namespace Difftest

open CatsEffectInLean.Model

mutual
/-- Number of `IO` constructors in a term, including `IO` terms inside runtime closures. -/
def ioSize : IO → Nat
  | .map a f | .flatMap a f | .handleErrorWith a f => 1 + ioSize a + fnSize f
  | .delay f | .uncancelable f | .ioCont f | .local f | .blocking _ f => 1 + fnSize f
  | .attempt a | .start a | .unmaskRunLoop a _ _ | .evalOn a _ => 1 + ioSize a
  | .onCancel a b | .racePair a b => 1 + ioSize a + ioSize b
  | _ => 1
/-- `IO` constructors inside a `Fn` (0 for user code). -/
def fnSize : Fn → Nat
  | .user _ => 0
  | .rt k => rtSize k
/-- `IO` constructors inside a runtime closure. -/
def rtSize : RtFn → Nat
  | .racePairBody a b | .racePairUnc a b _ | .racePairRegister a b _ => ioSize a + ioSize b
  | _ => 0
end

end Difftest

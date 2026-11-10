import Difftest.Translate

/-!
# The user environment of a difftest program

`denv p id arg vw` runs closure `id` (`cloOfId?`) of program `p` with the view `vw` (the
`Ref` cells, fiber outcomes and `Deferred` cells that user code sees). It mirrors the Scala
lambda named in `Lam`. `userEnv p` is the `Model.UserEnv`: trace events and `reportFailure`
calls become `UserEffect.emit` effects (`TraceEv.toVal`), before the other effects
(`DResult.toUser`). The `async` registration puts its events in `effects` itself, in Scala
order.

Format v1: `userEnv p` also runs the closures of the library mirrors (`dispatch`): queue
(`Std.Queue.call`, `Codec.cloVal` namespace 1), timeout (`Timeout.call`, namespace 2, with the
source builder `srcIO`) and `Resource` (`Resource.cloCall`, odd ids). A difftest closure id is
never one of them (`Difftest/Closure.lean`). An id that decodes as both a `Resource` closure and
a queue or timeout closure is a harness error (never seen; a check, not an assumption).
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

/-- Run closure `c` (made by node `n` of the program) on `arg` with view `vw`. `R`: the meaning
of the resource codes of the program (`renvOf`). -/
def runClo (U : ResourceUse.UEnv) (c : Clo) (n : Prog) (arg : Val) (vw : View) : DResult :=
  let R := U.rx
  let refs := vw.refs
  let node := c.node
  let env := c.vals
  match c.lam, n with
  | .delayThunk, .delay fn a =>
    match atomVal env a with
    | .ok v => callUser fn v
    | .error e => ofTr (.error e)
  | .bindK, .bind e k => ofTr (tr R k (node + 1 + e.size) (arg :: env) vw)
  | .seqK, .seq e k => ofTr (tr R k (node + 1 + e.size) env vw)
  | .mapFn, .map _ fn => callUser fn arg
  | .hewK, .handleErrorWith e k =>
    match arg with
    | .err t => match userCode? t with
      | some c => ofTr (tr R k (node + 1 + e.size) (.nat c :: env) vw)
      | none => prog (.error t)
    | _ => DResult.harness
  | .attemptMap, .attempt _ =>
    match arg with
    | .right v => ret (.right v)
    | .left (.err t) => match userCode? t with
      | some c => ret (.left (.nat c))
      | none => { base := { out := .throw t } }
    | _ => DResult.harness
  | .uncBody, .uncancelable body => ofTr (tr R body (node + 1) (arg :: env) vw)
  | .ocFinEmit, .onCancel _ _ tag => ret .unit [.finOnCancel tag]
  | .ocFinThen, .onCancel e fin _ =>
    -- `run(fin)` was built with the `onCancel` term: use the captured snapshot
    match env with
    | snap :: env0 =>
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$> tr R fin (node + 1 + e.size) env0 (snapView snap))
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
        let finalized := IO.onCancel (pollTerm ie m f) (gcFinalizer node env .ocCanceled)
        IO.flatMap (.handleErrorWith finalized (clo node .gcOnError env))
          (clo node .gcTap env)) <$> tr R e (node + 1) env (snapView snap))
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
    -- `o => IO.delay(emit) *> run(fin).void`: `*>` takes `that` by value (`IO.scala:138-139`),
    -- so Scala builds `run(fin)` now, in this closure. `gcFinThen` captures the snapshot.
    prog (.flatMap (.delay (clo node .gcFinEmit (arg :: env)))
      (clo node .gcFinThen (snapVal vw :: arg :: env)))
  | .gcFinEmit, .guaranteeCase _ _ tag =>
    match env with
    | o :: _ => ret .unit [.finGuaranteeCase tag o]
    | [] => DResult.harness
  | .gcFinThen, .guaranteeCase e fin _ =>
    -- `run(fin)` was built in `gcFinK`: use the captured snapshot. (Before 2026-11-10 this used
    -- the current view. An auto-yield between the two closures let another fiber complete, so
    -- `fib.cancel` read a different `_cancel`: found with small `runtime` thresholds.)
    match env with
    | snap :: env0 =>
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$> tr R fin (node + 1 + e.size) env0 (snapView snap))
    | [] => DResult.harness
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
  -- format v2 (track R)
  | .raceK, .race _ _ =>
    match arg with
    | .left v => ret (.left v)
    | .right v => ret (.right v)
    | _ => DResult.harness
  | .roK, .raceOutcome _ _ =>
    match arg with
    | .left oc => prog (.map (ocValTerm node oc) (clo node .mkLeft []))
    | .right oc => prog (.map (ocValTerm node oc) (clo node .mkRight []))
    | _ => DResult.harness
  | .mkLeft, _ => ret (.left arg)
  | .mkRight, _ => ret (.right arg)
  | .pairK, .both _ _ =>
    match arg with
    | .pair x y => ret (.pair x y)
    | _ => DResult.harness
  | .boK, .bothOutcome _ _ =>
    match arg with
    | .pair oa ob => prog (.flatMap (ocValTerm node oa) (clo node .boK2 [ob]))
    | _ => DResult.harness
  | .boK2, .bothOutcome _ _ =>
    match env with
    | [ob] => prog (.map (ocValTerm node ob) (clo node .boK3 [arg]))
    | _ => DResult.harness
  | .boK3, .bothOutcome _ _ =>
    match env with
    | [x] => ret (.pair x arg)
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
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$> tr R fin (node + 1) env0 (snapView snap))
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
  -- `h.newRef(r)` counts `Ref`s in creation order. Format v1: queue cells share the model cell
  -- ids, so the `refH` event gives the handle; the glue renumbers.
  | .refHandle, _ =>
    match arg with
    | .ref i => ret arg [.refH i]
    | _ => DResult.harness
  | .deferredNewThunk, _ =>
    { base := { effects := [.allocDeferred], out := .ret (.deferred vw.deferreds.length) } }
  -- `h.newDeferred(d)` counts `Deferred`s in creation order (the `memoize` mirror makes cells too)
  | .deferredHandle, _ =>
    match arg with
    | .deferred i => ret arg [.deferredH i]
    | _ => DResult.harness
  | .dcThen, .deferredComplete _ _ => prog (.delay (clo node .dcEmit (arg :: env)))
  | .dcEmit, .deferredComplete d v =>
    match env with
    | .bool ok :: env0 =>
      match atomVal env0 d, atomVal env0 v with
      | .ok (.deferred i), .ok x => ret (.bool ok) [.complete i x ok]
      | _, _ => ofTr (.error .typeError)
    | _ => DResult.harness
  -- format v1
  -- `q => VQueue(h.newQueue(q))`: the queue is the cell id of its buffer (`Std.Queue.newIO`)
  | .queueHandle, _ =>
    match arg with
    | .ref b => ret arg [.queueH b]
    | _ => DResult.harness
  -- `{ case Some(v) => VRight(v); case None => VLeft(VUnit) }`
  | .optEither, _ =>
    match arg with
    | .some v => ret (.right v)
    | .none => ret (.left .unit)
    | _ => DResult.harness
  -- `_._1` of `(B, ExitCase => F[Unit])`
  | .allocFst, _ =>
    match arg with
    | .pair b _ => ret b
    | _ => DResult.harness
  -- format v2 (`Model/Bracket.lean` runs the library lambdas; these are the program lambdas)
  | .gFinEmit, .guarantee _ _ tag => ret .unit [.finV2 0 tag none]
  | .gFinThen, .guarantee e fin _ =>
    match env with
    | snap :: env0 =>
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$> tr R fin (node + 1 + e.size) env0 (snapView snap))
    | [] => DResult.harness
  -- `x => run(use, env + x)`
  | .brUse, .bracket acq use _ _ | .brUse, .bracketCase acq use _ _ | .brUse, .bracketFull acq use _ _ =>
    ofTr (tr R use (node + 1 + acq.size) (arg :: env) vw)
  -- `poll => run(acq, env + poll)`
  | .bfAcq, .bracketFull acq _ _ _ => ofTr (tr R acq (node + 1) (arg :: env) vw)
  -- `a => IO.delay(emit fin) *> run(rel, env + x).void`: `run(rel)` is built now (snapshot)
  | .brRel, .bracket acq use rel _ =>
    match tr R rel (node + 1 + acq.size + use.size) (arg :: env) vw with
    | .error e => ofTr (.error e)
    | .ok _ =>
      prog (.flatMap (.delay (clo node .brFinEmit [])) (clo node .brRelThen (snapVal vw :: arg :: env)))
  | .brFinEmit, .bracket _ _ _ tag => ret .unit [.finV2 1 tag none]
  | .brRelThen, .bracket acq use rel _ =>
    match env with
    | snap :: env0 =>
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$>
        tr R rel (node + 1 + acq.size + use.size) env0 (snapView snap))
    | [] => DResult.harness
  -- `(a, oc) => ocVal(oc).flatMap(o => …)`
  | .brcRel, .bracketCase .. | .brcRel, .bracketFull .. =>
    match arg with
    | .pair a oc => prog (.flatMap (ocValTerm node oc) (clo node .brcFinK (a :: env)))
    | _ => DResult.harness
  -- `o => IO.delay(emit fin) *> run(rel, env + x + y).void`: `run(rel)` is built now (snapshot)
  | .brcFinK, .bracketCase acq use rel _ | .brcFinK, .bracketFull acq use rel _ =>
    match tr R rel (node + 1 + acq.size + use.size) (arg :: env) vw with
    | .error e => ofTr (.error e)
    | .ok _ =>
      prog (.flatMap (.delay (clo node .brcFinEmit [arg])) (clo node .brcFinThen (snapVal vw :: arg :: env)))
  | .brcFinEmit, .bracketCase _ _ _ tag => match env with
    | [o] => ret .unit [.finV2 2 tag (some o)]
    | _ => DResult.harness
  | .brcFinEmit, .bracketFull _ _ _ tag => match env with
    | [o] => ret .unit [.finV2 3 tag (some o)]
    | _ => DResult.harness
  | .brcFinThen, .bracketCase acq use rel _ | .brcFinThen, .bracketFull acq use rel _ =>
    match env with
    | snap :: env0 =>
      ofTr ((fun io => IO.map io (clo node .voidFn [])) <$>
        tr R rel (node + 1 + acq.size + use.size) env0 (snapView snap))
    | [] => DResult.harness
  -- format v2 (track M): `get => VMemo(h.newMemo(get))`
  | .memoHandle, _ =>
    match Memoize.Eff.ofVal? arg with
    | some (.get r _ _) => ret arg [.memoH r]
    | _ => DResult.harness
  -- format v2 (track Res; `Model/ResourceUse.lean` runs the library lambdas)
  -- `x => I(k)` of `rUse`
  | .ruUse, .rUse r k => ofTr (tr R k (node + 1 + r.size) (arg :: env) vw)
  -- `{ case (x, rel) => I(k).flatMap(b => rel.as(b)) }` of `rAllocated`
  | .raK, .rAllocated r k =>
    match arg with
    | .pair a rel => ofTr ((fun io => IO.flatMap io (clo node .raRelAs [rel])) <$> tr R k (node + 1 + r.size) (a :: env) vw)
    | _ => DResult.harness
  -- `b => rel.as(b)`; `as(b)` = `map(_ => b)` (`IO.scala:182-183`); `rel` is a `USrc` code
  | .raRelAs, _ =>
    match env with
    | [rel] => prog (.map (ResourceUse.srcU U rel) (clo node .constVal [arg]))
    | _ => DResult.harness
  | _, _ => DResult.harness

/-- The difftest closures of program `p`, with trace and failure lists. -/
def denv (p : Prog) (id : Nat) (arg : Val) (vw : View) : DResult :=
  match cloOfId? id with
  | none => DResult.harness
  | some c => match p.at? c.node with
    | none => DResult.harness
    | some n => runClo (uenvOf p) c n arg vw

/-- The source builder of `Timeout.call`: `src` is the code of a `timeoutSrc` closure value
(the result is `I(e)` of that `timeout` or `timeoutTo` node) or of a `timeoutFb` closure value
(the result is `I(fb)` of that `timeoutTo` node), built with the snapshot. -/
def srcIO (p : Prog) (srcV : Val) : IO :=
  let build (e : Prog) (n : Nat) (env : List Val) (snap : Val) : IO :=
    match tr (renvOf p) e n env (snapView snap) with
    | .ok io => io
    | .error e => .error e.toErr
  match (match srcV with | .nat src => Clo.decode? src | _ => none) with
  | some { node, lam := .timeoutSrc, vals := snap :: env } =>
    match p.at? node with
    | some (.timeout e _) | some (.timeoutTo e _ _) => build e (node + 1) env snap
    | _ => .error harnessErr
  | some { node, lam := .timeoutFb, vals := snap :: env } =>
    match p.at? node with
    | some (.timeoutTo e fb _) => build fb (node + 1 + e.size) env snap
    | _ => .error harnessErr
  -- format v2: `I(a)` / `I(b)` of a combinator node (`Translate.combSrcs`)
  | some { node, lam := .raceSrcA, vals := snap :: env } =>
    match (p.at? node).bind Prog.combArgs? with
    | some (a, _) =>
      match tr (renvOf p) a (node + 1) env (snapView snap) with
      | .ok io => io
      | .error e => .error e.toErr
    | none => .error harnessErr
  -- format v2 (track M): `I(e)` of a `memoize` node
  | some { node, lam := .memoSrc, vals := snap :: env } =>
    match p.at? node with
    | some (.memoize e) => build e (node + 1) env snap
    | _ => .error harnessErr
  | some { node, lam := .raceSrcB, vals := snap :: env } =>
    match (p.at? node).bind Prog.combArgs? with
    | some (a, b) =>
      match tr (renvOf p) b (node + 1 + a.size) env (snapView snap) with
      | .ok io => io
      | .error e => .error e.toErr
    | none => .error harnessErr
  -- track Res: a source code of the `Resource` mirror (`ResourceUse.USrc`)
  | _ => if (ResourceUse.USrc.ofVal srcV).isSome then ResourceUse.srcU (uenvOf p) srcV else .error harnessErr

/-- The external sources of `Bracket.call` (format v2): `I(e)` and the finalizer of
`guarantee`, `I(acq)` of `bracket`/`bracketCase`, each built with the snapshot of the op. -/
def bracketSrcIO (p : Prog) (srcV : Val) : IO :=
  match (match srcV with | .nat src => Clo.decode? src | _ => none) with
  | some { node, lam, vals := snap :: env } =>
    let R := renvOf p
    let res : Except TrErr IO :=
      match lam, p.at? node with
      | .gSrcE, some (.guarantee e _ _) => tr R e (node + 1) env (snapView snap)
      -- `IO.delay(emit fin) *> run(fin).void`; `*>` = `flatMap(_ => that)` (`IO.scala:138-139`)
      | .gSrcFin, some (.guarantee _ _ _) =>
        .ok (.flatMap (.delay (clo node .gFinEmit [])) (clo node .gFinThen (snap :: env)))
      | .brAcqSrc, some (.bracket acq _ _ _) | .brAcqSrc, some (.bracketCase acq _ _ _) =>
        tr R acq (node + 1) env (snapView snap)
      | _, _ => .error (.unsupported "bracket-src")
    match res with
    | .ok io => io
    | .error e => .error e.toErr
  -- track Res: a source code of the `Resource` mirror (`ResourceUse.USrc`)
  | _ => if (ResourceUse.USrc.ofVal srcV).isSome then ResourceUse.srcU (uenvOf p) srcV else .error harnessErr

/-- A library closure of the mirrors. -/
inductive LibClo where
  | queue (l : CatsEffectInLean.Std.Queue.QLam)
  | timeout (l : Timeout.TLam)
  | resource (c : Resource.Clo)
  | race (l : Race.RLam)
  | bracket (l : Bracket.BLam)
  | memoize (l : Memoize.MLam)
  | ures (l : ResourceUse.ULam)

/-- The library closure of an id that is not a difftest closure id, if exactly one mirror
decodes it. -/
def libClo? (id : Nat) : Option LibClo :=
  if id % 2 == 1 then
    match CatsEffectInLean.Model.Codec.cloOfId id with
    | some v =>
      let res : Option LibClo := (Resource.Clo.ofVal v).map .resource
      let lib : Option LibClo :=
        match CatsEffectInLean.Model.Codec.ofCloVal v with
        | some (k, tag, fs) =>
          if k == CatsEffectInLean.Std.Queue.ns then
            (CatsEffectInLean.Std.Queue.QLam.ofFields tag fs).map .queue
          else if k == Timeout.ns then (Timeout.TLam.ofFields tag fs).map .timeout
          else if k == Race.ns then (Race.RLam.ofFields tag fs).map .race
          else if k == Bracket.ns then (Bracket.BLam.ofFields tag fs).map .bracket
          else if k == Memoize.ns then (Memoize.MLam.ofFields tag fs).map .memoize
          else if k == ResourceUse.ns then (ResourceUse.ULam.ofFields tag fs).map .ures
          else none
        | none => none
      match res, lib with
      | some c, none => some c
      | none, some c => some c
      | _, _ => none
    | none => none
  else none

/-- The difftest closures of program `p` as model results (the user functions that the
`Bracket` mirror calls). -/
def dispatchDt (p : Prog) (id : Nat) (arg : Val) (vw : View) : UserResult :=
  match cloOfId? id with
  | some c =>
    match p.at? c.node with
    | some n => (runClo (uenvOf p) c n arg vw).toUser
    | none => DResult.harness.toUser
  | none => DResult.harness.toUser

/-- The difftest closures and the `ResourceUse` lambdas of program `p` (the functions that the
`Bracket` mirror calls: `IO.bracketFull` of `Resource#fold`, track Res). -/
def dispatchRes (p : Prog) (id : Nat) (arg : Val) (vw : View) : UserResult :=
  match ResourceUse.ULam.ofId? id with
  | some l => ResourceUse.callU (uenvOf p) (dispatchDt p) l arg vw
  | none => dispatchDt p id arg vw

/-- All closures of program `p`: difftest closures (with trace and failures) and library
closures (module doc). -/
def dispatch (p : Prog) (id : Nat) (arg : Val) (vw : View) : UserResult :=
  match cloOfId? id with
  | some _ => dispatchDt p id arg vw
  | none =>
    match libClo? id with
    | some (.queue l) => CatsEffectInLean.Std.Queue.call l arg vw
    | some (.timeout l) => Timeout.call (srcIO p) l arg vw
    | some (.resource c) => Resource.cloCall (renvOf p) c arg vw
    | some (.race l) => Race.call (srcIO p) l arg vw
    -- `Bracket` calls its user functions: difftest closures, or `ResourceUse` lambdas (track Res)
    | some (.bracket l) => Bracket.call (dispatchRes p) (bracketSrcIO p) l arg vw
    | some (.ures l) => ResourceUse.callU (uenvOf p) (dispatchDt p) l arg vw
    | some (.memoize l) => Memoize.call (srcIO p) l arg vw
    | none => DResult.harness.toUser

/-- The `Model.UserEnv` of program `p` (see module doc). -/
def userEnv (p : Prog) : UserEnv where
  call id arg refs := dispatch p id arg { refs }
  callV id arg vw := dispatch p id arg vw

/-- The view of the root term: only the root fiber, not completed. -/
def rootView : View := { outcomes := [none] }

/-- The root term `I(p)` (`Interp.apply`: `run(p, Map.empty)`). For a root `syncStep e`, the
term `I(e)` (node 1) that `syncStep` steps. -/
def rootTerm (p : Prog) : Except TrErr IO :=
  match p with
  | .syncStep e _ => tr (renvOf p) e 1 [] rootView
  | _ => tr (renvOf p) p 0 [] rootView

/-- Ops in `p` that the model cannot express yet (no repeats, in first-use order), and the
resource restriction (`Prog.resViewFree`). -/
def unsupportedOps (p : Prog) : List String :=
  (p.ops.filter fun o => unsupportedReason o != "unknown").eraseDups ++
    (if p.resViewFree then [] else ["resource-reads-state"])

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

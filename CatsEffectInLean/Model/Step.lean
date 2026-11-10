import CatsEffectInLean.Model.State

/-!
# One iteration of `IOFiber.runLoop` (one fiber, sequential core)

Phase 2 step 5. A mirror of `IOFiber.runLoop` and its helpers for one fiber:
`succeeded`, `failed`, `done`, `prepareFiberForCancelation`, `shouldFinalize`, the
continuations (`CancelationLoopK`, `RunTerminusK`, ...), and the resume dispatch of `run()`.

`FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala` at tag `v3.7.1`.

Design (`wiki/lean/kernel-evaluation.md`, design rules):

* `step` does one run-loop iteration (one call of `runLoop`, `FIB:211-1073`). It is not
  recursive. The driver in `CatsEffectInLean/Model/Run.lean` is structural on the schedule.
* `succeeded` and `failed` (`FIB:1209-1331`) are recursive in Scala. Here they are mutually
  structural on the `conts` stack: each recursive call in Scala pops one byte first.
* Each Scala `try` around user code is `tryUser`; each call without `try` is `callUser`.
* `onFatalFailure` (`FIB:1597`) throws. It is `Flow.fatal`, never an `Outcome`.
* Tags that need other fibers, the scheduler or async callbacks are not done yet. They give
  `Abort.unsupportedTag`. They never succeed silently.

The cancelation and auto-yield counters of `runLoop` (`FIB:213-240`) are `Loop` fields. The
read barrier (`FIB:228`) and the `observe` flag of a step make a pending external cancel
visible (`Loop.pendingCancel`).
-/

namespace CatsEffectInLean.Model

/-- The runtime settings that the run loop reads.

`cancelationCheckThreshold` and `autoYieldThreshold` are `IORuntimeConfig` fields
(`core/shared/src/main/scala/cats/effect/unsafe/IORuntimeConfig.scala:22-24`). Defaults 512 and
`2 * 512` (`core/jvm/src/main/scala/cats/effect/unsafe/IORuntimeConfigCompanionPlatform.scala:26-32`).
`TestControl` uses the default config. `maxStackDepth` is the constant `MaxStackDepth = 512`
(`core/jvm/src/main/java/cats/effect/IOFiberConstants.java:26`); it is a field here only so
that examples can use a small value. `reportUnhandledFiberErrors` defaults to `true`
(`IORuntimeConfig.scala:178`). -/
structure Config where
  /-- `runtime.cancelationCheckThreshold` (`FIB:229`). Must be `> 0`. -/
  cancelationCheckThreshold : Nat := 512
  /-- `runtime.autoYieldThreshold` (`FIB:1399`). A multiple of the cancelation threshold. -/
  autoYieldThreshold : Nat := 1024
  /-- `MaxStackDepth` (`IOFiberConstants.java:26`), used in `succeeded` (`FIB:1226`). -/
  maxStackDepth : Nat := 512
  /-- `runtime.config.reportUnhandledFiberErrors` (`FIB:1099`). -/
  reportUnhandledFiberErrors : Bool := true
  deriving DecidableEq, Repr

/-- An observable side effect of the runtime itself (not of user code). -/
inductive TraceEv where
  /-- `currentCtx.reportFailure(e)`: an error in a finalizer (`FIB:1488`), or an `Errored`
  outcome with no callback (`FIB:1099-1101`). -/
  | reportFailure (e : Err)
  /-- `callbacks(oc)` called this outcome callback (`FIB:1099`). -/
  | outcomeCb (cb : OutcomeCb) (oc : Outcome)
  /-- The canceller's `IO.async_` callback was called with `Right(())` (`FIB:1155`,
  `FIB:1476`). `state` names the canceller's `ContState`. -/
  | cancelerCb (state : Nat)
  deriving DecidableEq, Repr

/-- The part of the world that one fiber step reads and writes, other than the fiber. -/
structure Heap where
  /-- `Ref` cells (index = id). User code reads a snapshot and writes with `writeRef`.
  A write to an id that is not in the list has no effect, so examples allocate first. -/
  refs : List Val := []
  /-- The virtual clock (`RealTime`/`Monotonic`, `FIB:294-306`). -/
  clock : Nat := 0
  /-- Runtime events, newest first. -/
  trace : List TraceEv := []
  deriving DecidableEq, Repr

/-- Why the model stops without a Cats Effect result. Never a Cats Effect outcome. -/
inductive Abort where
  /-- A tag that the single-fiber step does not implement yet (Phase 2 step 8). -/
  | unsupportedTag (tag : Int)
  /-- A resume tag that the single-fiber step does not implement yet (`blockingR`). -/
  | unsupportedResume (tag : ResumeTag)
  /-- A runtime closure (`Fn.rt`) must run. They come only from unsupported tags. -/
  | unsupportedFn
  /-- User code called an `IOCont` callback (`invokeCb`/`deferCb`). -/
  | unsupportedEffect
  /-- User code returned a value where the run loop needs a program, or the reverse. The
  generator makes only well-typed programs, so this is a generator or example bug. -/
  | illTyped
  /-- `conts` is empty. `execR` pushes `RunTerminusK` (`FIB:1392`), so this is unreachable. -/
  | emptyConts
  /-- `objectState` does not hold what the continuation pops. Unreachable from `execR`. -/
  | badObjectState
  /-- `resumeIO` is `null` where `run()` reads it. -/
  | noResumeIO
  deriving DecidableEq, Repr

/-- What the run loop does next, as computed by one branch, `succeeded` or `failed`. -/
inductive Flow where
  /-- `runLoop(cur, ...)`: continue with `cur` (can be `IO.endFiber`). -/
  | io (cur : IO)
  /-- `onFatalFailure(e)` (`FIB:1597`): the runtime shuts down and the error is rethrown. -/
  | fatal (e : Err)
  /-- An exception left `runLoop` with no `try` around it (only `Local`, `FIB:1061`). Under
  `TestControl` the `TestContext` reports it (`kernel-testkit/.../TestContext.scala:161-162`)
  and the fiber never completes. -/
  | uncaught (e : Err)
  /-- The model stops (see `Abort`). -/
  | abort (a : Abort)
  deriving DecidableEq, Repr

/-- The fiber and the heap: what `succeeded`, `failed` and the branches change. -/
structure Exec (M : Type) where
  fib : Fiber M
  heap : Heap
  deriving DecidableEq, Repr

namespace Exec
variable {M : Type}
/-- Set `conts`. -/
@[inline] def setConts (x : Exec M) (c : List ContK) : Exec M := { x with fib := { x.fib with conts := c } }
/-- Push one continuation byte (`ByteStack.push`). -/
@[inline] def pushCont (x : Exec M) (k : ContK) : Exec M := x.setConts (k :: x.fib.conts)
/-- Set `objectState`. -/
@[inline] def setObj (x : Exec M) (o : List ObjEntry) : Exec M :=
  { x with fib := { x.fib with objectState := o } }
/-- Push onto `objectState`. -/
@[inline] def pushObj (x : Exec M) (o : ObjEntry) : Exec M := x.setObj (o :: x.fib.objectState)
/-- Set the mask state. -/
@[inline] def setMask (x : Exec M) (m : M) : Exec M := { x with fib := { x.fib with mask := m } }
/-- Set the heap. -/
@[inline] def setHeap (x : Exec M) (h : Heap) : Exec M := { x with heap := h }
/-- Add a runtime event. -/
@[inline] def log (x : Exec M) (e : TraceEv) : Exec M :=
  { x with heap := { x.heap with trace := e :: x.heap.trace } }
end Exec

/-! ## User code -/

/-- Apply the effects of one user call, in order. Callback effects need `IOCont`. -/
def applyEffects : List UserEffect → List Val → Except Abort (List Val)
  | [], refs => .ok refs
  | .writeRef r v :: es, refs => applyEffects es (refs.set r v)
  | .invokeCb _ _ :: _, _ => .error .unsupportedEffect
  | .deferCb _ _ :: _, _ => .error .unsupportedEffect

/-- Call a function with no `try` around it: effects first, then the output. -/
def callUser (env : UserEnv) (f : Fn) (arg : Val) (h : Heap) : Except Abort (UserOut × Heap) :=
  match f with
  | .rt _ => .error .unsupportedFn
  | .user id =>
    let r := env.call id arg h.refs
    match applyEffects r.effects h.refs with
    | .ok refs => .ok (r.out, { h with refs := refs })
    | .error a => .error a

/-- The result of user code inside the run loop's `try` / `catch`. -/
inductive TryRes where
  /-- The call returned (`out` is `ret` or `prog`, never `throw`). -/
  | ok (out : UserOut) (h : Heap)
  /-- `case t if UnsafeNonFatal(t) => ...` caught `e`. -/
  | caught (e : Err) (h : Heap)
  /-- `case t: Throwable => onFatalFailure(t)`. -/
  | fatal (e : Err) (h : Heap)
  /-- The model stops. -/
  | abort (a : Abort)

/-- `try f(arg) catch { case t if UnsafeNonFatal(t) => ...; case t: Throwable =>
onFatalFailure(t) }`, the pattern at `FIB:280-286` and its copies. -/
def tryUser (env : UserEnv) (f : Fn) (arg : Val) (h : Heap) : TryRes :=
  match callUser env f arg h with
  | .error a => .abort a
  | .ok (.throw e, h') => if e.isNonFatal then .caught e h' else .fatal e h'
  | .ok (out, h') => .ok out h'

/-- `try f(thunk()) catch ...`: two calls inside one `try` (`FIB:359`, `FIB:429`). If the
thunk throws, `f` does not run. -/
def tryUser2 (env : UserEnv) (thunk f : Fn) (h : Heap) : TryRes :=
  match tryUser env thunk .unit h with
  | .ok (.ret r) h' => tryUser env f r h'
  | .ok _ _ => .abort .illTyped
  | other => other

/-! ## Helpers of the run loop -/

section Helpers
variable {M : Type} (cfg : Config) (mm : MaskModel M)

/-- `done(oc)` (`FIB:1092-1126`). `_join`/`_cancel` (`FIB:1094-1095`) follow from `outcome`.
`currentCtx = null` (`FIB:1121`) is not modelled (no read after `done`). -/
def done (x : Exec M) (oc : Outcome) : Exec M :=
  -- FIB:1097 `outcome = oc`
  let fib := { x.fib with outcome := some oc }
  -- FIB:1099 `callbacks(oc)`: calls every callback in stack order (`CallbackStack.scala:61-85`)
  let x := { x with fib := fib }
  let x := x.fib.callbacks.foldl (fun x p => x.log (.outcomeCb p.2 oc)) x
  -- FIB:1099-1104 report an `Errored` outcome that nobody receives
  let x :=
    if x.fib.callbacks.isEmpty && cfg.reportUnhandledFiberErrors then
      match oc with
      | .errored e => x.log (.reportFailure e)
      | _ => x
    else x
  -- FIB:1110 `masks = 0`; FIB:1112-1114; FIB:1118-1120 clear the stacks
  { x with fib := { x.fib with
      mask := mm.reset x.fib.mask, resumeTag := .doneR, resumeIO := none, suspended := false,
      conts := [], objectState := [], finalizers := [] } }

/-- `prepareFiberForCancelation(cb)` (`FIB:1132-1164`). `cb = none` is Scala `null`. -/
def prepareFiberForCancelation (x : Exec M) (cb : Option Nat) : Exec M × IO :=
  match x.fib.finalizers with
  -- FIB:1133 `!finalizers.isEmpty()`
  | fin :: rest =>
    -- FIB:1134-1146: only the first time
    let fib :=
      if !x.fib.finalizing then
        { x.fib with finalizing := true, conts := [.cancelationLoopK],
                     objectState := [.cancelCb cb], mask := mm.finalizeMask x.fib.mask }
      else x.fib
    -- FIB:1149 `finalizers.pop()`
    ({ x with fib := { fib with finalizers := rest } }, fin)
  | [] =>
    -- FIB:1154-1156 unblock the canceller
    let x := match cb with
      | some s => x.log (.cancelerCb s)
      | none => x
    -- FIB:1159-1162
    (done cfg mm x .canceled, .endFiber)

/-- `shouldFinalize()` (`FIB:1172-1173`) with `isUnmasked()` (`FIB:1175-1176`). -/
def shouldFinalize (fib : Fiber M) : Bool :=
  fib.canceled && mm.isUnmasked fib.mask

/-- `cancelationLoopSuccessK()` (`FIB:1465-1485`). -/
def cancelationLoopSuccessK (x : Exec M) : Exec M × Flow :=
  match x.fib.finalizers with
  | fin :: rest =>
    -- FIB:1466-1469 next finalizer
    ({ x with fib := { x.fib with conts := .cancelationLoopK :: x.fib.conts,
                                  finalizers := rest } }, .io fin)
  | [] =>
    -- FIB:1474-1477 unblock the canceller
    match x.fib.objectState with
    | .cancelCb cb :: os =>
      let x := x.setObj os
      let x := match cb with
        | some s => x.log (.cancelerCb s)
        | none => x
      -- FIB:1480-1483
      (done cfg mm x .canceled, .io .endFiber)
    | _ => (x, .abort .badObjectState)

/-- `cancelationLoopFailureK(t)` (`FIB:1487-1490`): report, then go on. -/
def cancelationLoopFailureK (x : Exec M) (t : Err) : Exec M × Flow :=
  cancelationLoopSuccessK cfg mm (x.log (.reportFailure t))

/-- `runTerminusSuccessK(result)` (`FIB:1492-1495`). -/
def runTerminusSuccessK (x : Exec M) (result : Val) : Exec M × Flow :=
  (done cfg mm x (.succeeded result), .io .endFiber)

/-- `runTerminusFailureK(t)` (`FIB:1497-1500`). -/
def runTerminusFailureK (x : Exec M) (t : Err) : Exec M × Flow :=
  (done cfg mm x (.errored t), .io .endFiber)

end Helpers

/-! ## `succeeded` and `failed` (`FIB:1209-1331`)

Structural on `conts`: the list argument is the stack without the byte that this call pops.
`Exec.fib.conts` is set to the rest before each branch. -/

section Unwind
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

mutual

/-- `succeeded(result, depth)` (`FIB:1209-1268`). -/
def succeeded (x : Exec M) (result : Val) (depth : Nat) : List ContK → Exec M × Flow
  | [] => (x, .abort .emptyConts)
  | k :: rest =>
    -- FIB:1211 `ByteStack.pop(conts)`
    let x := x.setConts rest
    match k with
    | .mapK =>
      -- FIB:1212-1232
      match x.fib.objectState with
      | .fn f :: os =>
        let x := x.setObj os
        match tryUser env f result x.heap with
        | .ok (.ret t) h =>
          let x := x.setHeap h
          -- FIB:1226-1228: hand back to the run loop at depth > MaxStackDepth
          if depth > cfg.maxStackDepth then (x, .io (.pure t))
          else succeeded x t (depth + 1) rest
        | .caught e h =>
          let x := x.setHeap h
          if depth > cfg.maxStackDepth then (x, .io (.error e))
          else failed x e (depth + 1) rest
        | .ok _ h => (x.setHeap h, .abort .illTyped)
        | .fatal e h => (x.setHeap h, .fatal e)
        | .abort a => (x, .abort a)
      | _ => (x, .abort .badObjectState)
    | .flatMapK =>
      -- FIB:1234-1243
      match x.fib.objectState with
      | .fn f :: os =>
        let x := x.setObj os
        match tryUser env f result x.heap with
        | .ok (.prog p) h => (x.setHeap h, .io p)
        | .caught e h => failed (x.setHeap h) e (depth + 1) rest
        | .ok _ h => (x.setHeap h, .abort .illTyped)
        | .fatal e h => (x.setHeap h, .fatal e)
        | .abort a => (x, .abort a)
      | _ => (x, .abort .badObjectState)
    -- FIB:1245
    | .cancelationLoopK => cancelationLoopSuccessK cfg mm x
    -- FIB:1246
    | .runTerminusK => runTerminusSuccessK cfg mm x result
    -- FIB:1247 `evalOnSuccessK`: only reachable after a foreign `EvalOn` (unsupported)
    | .evalOnK => (x, .abort (.unsupportedTag 20))
    | .handleErrorWithK =>
      -- FIB:1249-1252: drop the handler, same depth
      match x.fib.objectState with
      | _ :: os => succeeded (x.setObj os) result depth rest
      | [] => (x, .abort .badObjectState)
    -- FIB:1254-1256 `onCancelSuccessK`
    | .onCancelK =>
      succeeded { x with fib := { x.fib with finalizers := x.fib.finalizers.tail } }
        result (depth + 1) rest
    -- FIB:1258-1260 `uncancelableSuccessK`
    | .uncancelableK => succeeded (x.setMask (mm.exit x.fib.mask)) result (depth + 1) rest
    -- FIB:1262-1264 `unmaskSuccessK`
    | .unmaskK => succeeded (x.setMask (mm.remask x.fib.mask)) result (depth + 1) rest
    -- FIB:1266-1267 `attemptK`, same depth
    | .attemptK => succeeded x (.right result) depth rest
  termination_by structural c => c

/-- `failed(error, depth)` (`FIB:1270-1331`). `Tracing.augmentThrowable` (`FIB:1271`) only
changes the stack trace; not modelled. There is no depth check in `failed`. -/
def failed (x : Exec M) (error : Err) (depth : Nat) : List ContK → Exec M × Flow
  | [] => (x, .abort .emptyConts)
  | k :: rest =>
    -- FIB:1295 `ByteStack.pop(conts)`
    let x := x.setConts rest
    match k with
    -- FIB:1298-1300: drop `map` and `flatMap` functions, same depth
    | .mapK | .flatMapK =>
      match x.fib.objectState with
      | _ :: os => failed (x.setObj os) error depth rest
      | [] => (x, .abort .badObjectState)
    -- FIB:1302
    | .cancelationLoopK => cancelationLoopFailureK cfg mm x error
    -- FIB:1303
    | .runTerminusK => runTerminusFailureK cfg mm x error
    -- FIB:1304 `evalOnFailureK`: only reachable after a foreign `EvalOn` (unsupported)
    | .evalOnK => (x, .abort (.unsupportedTag 20))
    | .handleErrorWithK =>
      -- FIB:1306-1315
      match x.fib.objectState with
      | .fn f :: os =>
        let x := x.setObj os
        match tryUser env f (.err error) x.heap with
        | .ok (.prog p) h => (x.setHeap h, .io p)
        | .caught e h => failed (x.setHeap h) e (depth + 1) rest
        | .ok _ h => (x.setHeap h, .abort .illTyped)
        | .fatal e h => (x.setHeap h, .fatal e)
        | .abort a => (x, .abort a)
      | _ => (x, .abort .badObjectState)
    -- FIB:1317-1319 `onCancelFailureK`
    | .onCancelK =>
      failed { x with fib := { x.fib with finalizers := x.fib.finalizers.tail } }
        error (depth + 1) rest
    -- FIB:1321-1323 `uncancelableFailureK`
    | .uncancelableK => failed (x.setMask (mm.exit x.fib.mask)) error (depth + 1) rest
    -- FIB:1325-1327 `unmaskFailureK`
    | .unmaskK => failed (x.setMask (mm.remask x.fib.mask)) error (depth + 1) rest
    -- FIB:1329 `attemptK`
    | .attemptK => succeeded x (.left (.err error)) depth rest
  termination_by structural c => c

end

/-- `succeeded(result, depth)` on the current `conts`. -/
def succeededK (x : Exec M) (result : Val) (depth : Nat) : Exec M × Flow :=
  succeeded cfg mm env x result depth x.fib.conts

/-- `failed(error, depth)` on the current `conts`. -/
def failedK (x : Exec M) (error : Err) (depth : Nat) : Exec M × Flow :=
  failed cfg mm env x error depth x.fib.conts

/-- The `Error` check `if (!UnsafeNonFatal(ex)) onFatalFailure(ex)` then `failed(ex, 0)`
(`FIB:265-269`, `FIB:343-347`, `FIB:414-418`). -/
def raised (x : Exec M) (ex : Err) : Exec M × Flow :=
  if !ex.isNonFatal then (x, .fatal ex) else failedK cfg mm env x ex 0

/-- A user call result in a value position: `if (error == null) succeeded(r, 0) else
failed(error, 0)` (`FIB:288-290`, `FIB:333`, `FIB:367`). -/
def afterValue (x : Exec M) : TryRes → Exec M × Flow
  | .ok (.ret r) h => succeededK cfg mm env (x.setHeap h) r 0
  | .caught e h => failedK cfg mm env (x.setHeap h) e 0
  | .ok _ h => (x.setHeap h, .abort .illTyped)
  | .fatal e h => (x.setHeap h, .fatal e)
  | .abort a => (x, .abort a)

/-- A user call result in a program position: `try f(v) catch { case NonFatal(t) =>
failed(t, 0) }` (`FIB:398-405`, `FIB:428-435`). -/
def afterProg (x : Exec M) : TryRes → Exec M × Flow
  | .ok (.prog p) h => (x.setHeap h, .io p)
  | .caught e h => failedK cfg mm env (x.setHeap h) e 0
  | .ok _ h => (x.setHeap h, .abort .illTyped)
  | .fatal e h => (x.setHeap h, .fatal e)
  | .abort a => (x, .abort a)

/-- The value of a "leaf" tag that `Map`, `FlatMap` and `Attempt` read in their fast
paths: `RealTime` (`FIB:371`), `Monotonic` (`FIB:375`), `ReadEC` (`FIB:379`).
The clock is in the virtual-time unit; `nowMicros().micros` and `monotonicNanos().nanos`
give the same `FiniteDuration` under `TestControl`. -/
def leafValue (x : Exec M) : IO → Option Val
  | .realTime => some (.nat x.heap.clock)
  | .monotonic => some (.nat x.heap.clock)
  | .readEC => some (.ec x.fib.currentCtx)
  | _ => none

end Unwind

/-! ## The run loop -/

/-- The arguments and fiber state of one `runLoop` call (`FIB:211-214`). -/
structure Loop (M : Type) where
  /-- The fiber and the heap. -/
  exec : Exec M
  /-- `_cur0`. -/
  cur : IO
  /-- `cancelationIterations`. A `Nat`: the Scala `Int` is only tested by `<= 0`, and
  `max 0` commutes with each subtraction, so truncated subtraction gives the same tests. -/
  cancelIters : Nat
  /-- `autoCedeIterations` (same remark). -/
  autoCedeIters : Nat
  /-- Not an `IOFiber` field. An external `cancel` wrote `canceled = true` (`FIB:143`, a
  plain `var`), but this thread does not see the write yet. The read barrier (`FIB:228`),
  `run()` (`FIB:115`) and a step with `observe = true` make it visible. -/
  pendingCancel : Bool := false
  deriving DecidableEq, Repr

/-- Make a pending external cancel visible (a read barrier). -/
def Loop.flush {M : Type} (l : Loop M) : Loop M :=
  if l.pendingCancel then
    { l with exec := { l.exec with fib := { l.exec.fib with canceled := true } },
             pendingCancel := false }
  else l

/-- The result of one run-loop iteration or of one `run()` entry. -/
inductive StepResult (M : Type) where
  /-- The run loop goes on with this state. -/
  | continue (l : Loop M)
  /-- Auto-yield (`FIB:233-238`): `resumeTag = AutoCedeR`, `resumeIO = cur`, and the fiber
  is rescheduled. The scheduler decides when it runs again. `Cede` will also give this. -/
  | yielded (x : Exec M)
  /-- `runLoop` returned at `EndFiber` (`FIB:220-222`) but the fiber has no outcome: it
  waits for an async callback. No implemented branch gives this yet. -/
  | suspended (x : Exec M)
  /-- The fiber completed with this outcome (`done`, `FIB:1092`). -/
  | done (oc : Outcome) (x : Exec M)
  /-- `onFatalFailure(e)` (`FIB:1597`). -/
  | fatal (e : Err) (x : Exec M)
  /-- An exception left the run loop (`Local`, `FIB:1061`). -/
  | uncaught (e : Err) (x : Exec M)
  /-- The model stops (see `Abort`). -/
  | aborted (a : Abort) (x : Exec M)
  deriving DecidableEq, Repr

section Run
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Turn a computed `Flow` into the next run-loop call `runLoop(next, nc, na)`. -/
def toStep (l : Loop M) (r : Exec M × Flow) (nc na : Nat) : StepResult M :=
  match r.2 with
  | .io cur => .continue { l with exec := r.1, cur := cur, cancelIters := nc, autoCedeIters := na }
  | .fatal e => .fatal e r.1
  | .uncaught e => .uncaught e r.1
  | .abort a => .aborted a r.1

/-- The dispatch on `cur0.tag` (`FIB:258-1071`), after the `shouldFinalize` check.
`nc`, `na` are `nextCancelation`, `nextAutoCede`. -/
def dispatch (l : Loop M) (nc na : Nat) : StepResult M :=
  let x := l.exec
  let ret (r : Exec M × Flow) (c : Nat) : StepResult M := toStep l r c na
  match l.cur with
  -- FIB:259-261 `Pure`
  | .pure v => ret (succeededK cfg mm env x v 0) nc
  -- FIB:263-269 `Error`
  | .error ex => ret (raised cfg mm env x ex) nc
  -- FIB:271-292 `Delay`: the thunk is inside `try`
  | .delay thunk => ret (afterValue cfg mm env x (tryUser env thunk .unit x.heap)) nc
  -- FIB:295-299 `RealTime`
  | .realTime => ret (succeededK cfg mm env x (.nat x.heap.clock) 0) nc
  -- FIB:302-306 `Monotonic`
  | .monotonic => ret (succeededK cfg mm env x (.nat x.heap.clock) 0) nc
  -- FIB:309-310 `ReadEC`
  | .readEC => ret (succeededK cfg mm env x (.ec x.fib.currentCtx) 0) nc
  -- FIB:312-386 `Map`
  | .map ioe f =>
    match ioe with
    -- FIB:337-339 over `Pure`: `next(v)` with `f` inside `try`
    | .pure v => ret (afterValue cfg mm env x (tryUser env f v x.heap)) (nc - 1)
    -- FIB:341-347 over `Error`: `f` is never called
    | .error ex => ret (raised cfg mm env x ex) (nc - 1)
    -- FIB:349-368 over `Delay`: `f(thunk())` in one `try`
    | .delay thunk => ret (afterValue cfg mm env x (tryUser2 env thunk f x.heap)) (nc - 1)
    -- FIB:370-380 over `RealTime`, `Monotonic`, `ReadEC`
    | .realTime | .monotonic | .readEC =>
      match leafValue x ioe with
      | some v => ret (afterValue cfg mm env x (tryUser env f v x.heap)) (nc - 1)
      | none => ret (x, .abort .illTyped) nc
    -- FIB:382-385 general case
    | _ => ret ((x.pushObj (.fn f)).pushCont .mapK, .io ioe) nc
  -- FIB:388-455 `FlatMap`
  | .flatMap ioe f =>
    match ioe with
    -- FIB:408-410 over `Pure`
    | .pure v => ret (afterProg cfg mm env x (tryUser env f v x.heap)) (nc - 1)
    -- FIB:412-418 over `Error`
    | .error ex => ret (raised cfg mm env x ex) (nc - 1)
    -- FIB:420-437 over `Delay`: `f(thunk())` in one `try`
    | .delay thunk => ret (afterProg cfg mm env x (tryUser2 env thunk f x.heap)) (nc - 1)
    -- FIB:439-449 over `RealTime`, `Monotonic`, `ReadEC`
    | .realTime | .monotonic | .readEC =>
      match leafValue x ioe with
      | some v => ret (afterProg cfg mm env x (tryUser env f v x.heap)) (nc - 1)
      | none => ret (x, .abort .illTyped) nc
    -- FIB:451-454 general case
    | _ => ret ((x.pushObj (.fn f)).pushCont .flatMapK, .io ioe) nc
  -- FIB:457-517 `Attempt`
  | .attempt ioa =>
    match ioa with
    -- FIB:463-465
    | .pure v => ret (succeededK cfg mm env x (.right v) 0) (nc - 1)
    -- FIB:467-475: fatal check, then `Left(t)` (no `failed`)
    | .error t =>
      if !t.isNonFatal then ret (x, .fatal t) (nc - 1)
      else ret (succeededK cfg mm env x (.left (.err t)) 0) (nc - 1)
    -- FIB:477-500: the thunk inside `try`; an error becomes `Left`
    | .delay thunk =>
      match tryUser env thunk .unit x.heap with
      | .ok (.ret r) h => ret (succeededK cfg mm env (x.setHeap h) (.right r) 0) (nc - 1)
      | .caught e h => ret (succeededK cfg mm env (x.setHeap h) (.left (.err e)) 0) (nc - 1)
      | .ok _ h => ret (x.setHeap h, .abort .illTyped) (nc - 1)
      | .fatal e h => ret (x.setHeap h, .fatal e) (nc - 1)
      | .abort a => ret (x, .abort a) (nc - 1)
    -- FIB:502-512
    | .realTime | .monotonic | .readEC =>
      match leafValue x ioa with
      | some v => ret (succeededK cfg mm env x (.right v) 0) (nc - 1)
      | none => ret (x, .abort .illTyped) nc
    -- FIB:514-516 general case
    | _ => ret (x.pushCont .attemptK, .io ioa) nc
  -- FIB:519-529 `HandleErrorWith`
  | .handleErrorWith ioa f => ret ((x.pushObj (.fn f)).pushCont .handleErrorWithK, .io ioa) nc
  -- FIB:532-540 `Canceled`
  | .canceled =>
    let x := { x with fib := { x.fib with canceled := true } }
    if mm.isUnmasked x.fib.mask then
      -- FIB:535-537 run finalizers now
      let (x, fin) := prepareFiberForCancelation cfg mm x none
      ret (x, .io fin) nc
    else
      -- FIB:539
      ret (succeededK cfg mm env x .unit 0) nc
  -- FIB:542-553 `OnCancel`: the finalizer is wrapped in `EvalOn(fin, currentCtx)`
  | .onCancel ioa fin =>
    let x := { x with fib := { x.fib with
      finalizers := .evalOn fin x.fib.currentCtx :: x.fib.finalizers } }
    ret (x.pushCont .onCancelK, .io ioa) nc
  -- FIB:555-583 `Uncancelable`: mask first, then the body inside `try`, then `UncancelableK`
  | .uncancelable body =>
    let (m, id) := mm.enter x.fib.mask
    let x := x.setMask m
    match tryUser env body (.poll id x.fib.id) x.heap with
    | .ok (.prog p) h => ret ((x.setHeap h).pushCont .uncancelableK, .io p) nc
    -- FIB:572-573 `IO.raiseError(t)`
    | .caught e h => ret ((x.setHeap h).pushCont .uncancelableK, .io (.error e)) nc
    | .ok _ h => ret (x.setHeap h, .abort .illTyped) nc
    | .fatal e h => ret (x.setHeap h, .fatal e) nc
    | .abort a => ret (x, .abort a) nc
  -- FIB:585-602 `UnmaskRunLoop`: "the outer block wins"
  | .unmaskRunLoop ioa id self =>
    if mm.pollMatches x.fib.mask id && self == x.fib.id then
      ret ((x.setMask (mm.unmask x.fib.mask)).pushCont .unmaskK, .io ioa) nc
    else
      ret (x, .io ioa) nc
  -- FIB:604-769 `IOCont`, FIB:771-886 `Get`: need the `ContState` race (step 8)
  | .ioCont _ => ret (x, .abort (.unsupportedTag 14)) nc
  | .contGet _ => ret (x, .abort (.unsupportedTag 15)) nc
  -- `Cede`, `Start`, `RacePair`, `Sleep` (FIB:888-981): need the scheduler (step 8)
  | .cede => ret (x, .abort (.unsupportedTag 16)) nc
  | .start _ => ret (x, .abort (.unsupportedTag 17)) nc
  | .racePair _ _ => ret (x, .abort (.unsupportedTag 18)) nc
  | .sleep _ => ret (x, .abort (.unsupportedTag 19)) nc
  -- FIB:983-1011 `EvalOn`
  | .evalOn ioa ec =>
    -- FIB:987-988 fast path when `cur.ec eq currentCtx`
    if ec == x.fib.currentCtx then ret (x, .io ioa) nc
    -- FIB:989-1010 a foreign `ExecutionContext`: needs the scheduler (step 8)
    else ret (x, .abort (.unsupportedTag 20)) nc
  -- FIB:1013-1056 `Blocking`: needs the blocking pool (step 8)
  | .blocking _ _ => ret (x, .abort (.unsupportedTag 21)) nc
  -- FIB:1058-1063 `Local`: `cur.f(localState)` has NO `try`
  | .local f =>
    match callUser env f x.fib.localState x.heap with
    | .ok (.ret (.pair s v), h) =>
      let x := { x.setHeap h with fib := { x.fib with localState := s } }
      ret (succeededK cfg mm env x v 0) nc
    | .ok (.throw e, h) => ret (x.setHeap h, .uncaught e) nc
    | .ok (_, h) => ret (x.setHeap h, .abort .illTyped) nc
    | .error a => ret (x, .abort a) nc
  -- FIB:1065-1066 `IOTrace`
  | .ioTrace => ret (succeededK cfg mm env x .trace 0) nc
  -- FIB:1069-1070 `ReadRT`
  | .readRT => ret (succeededK cfg mm env x .runtime 0) nc
  -- `EndFiber` is handled by `step` before the dispatch (FIB:220-222)
  | .endFiber => ret (x, .io .endFiber) nc

/-- `runLoop(_cur0, cancelationIterations, autoCedeIterations)`, one iteration
(`FIB:211-1073`). `observe = true` makes a pending external cancel visible before the
iteration (the JVM may show the write at any time; the read barrier forces it). -/
def step (observe : Bool) (l : Loop M) : StepResult M :=
  match l.cur with
  -- FIB:220-222 `if (_cur0 eq IO.EndFiber) return`
  | .endFiber =>
    match l.exec.fib.outcome with
    | some oc => .done oc l.exec
    | none => .suspended (l.flush).exec
  | cur =>
    let l := if observe then l.flush else l
    -- FIB:224-225
    let nextCancelation := l.cancelIters - 1
    let nextAutoCede := l.autoCedeIters
    -- FIB:226-240
    if nextCancelation ≤ 0 then
      -- FIB:228 `readBarrier()`
      let l := l.flush
      -- FIB:229
      let nextCancelation := cfg.cancelationCheckThreshold
      -- FIB:231
      let nextAutoCede := nextAutoCede - nextCancelation
      if nextAutoCede ≤ 0 then
        -- FIB:234-238 auto-yield
        .yielded { l.exec with fib := { l.exec.fib with
          resumeTag := .autoCedeR, resumeIO := some cur } }
      else
        -- FIB:242-245
        if shouldFinalize mm l.exec.fib then
          let (x, fin) := prepareFiberForCancelation cfg mm l.exec none
          .continue { l with exec := x, cur := fin, cancelIters := nextCancelation,
                             autoCedeIters := nextAutoCede }
        else dispatch cfg mm env l nextCancelation nextAutoCede
    else
      -- FIB:242-245
      if shouldFinalize mm l.exec.fib then
        let (x, fin) := prepareFiberForCancelation cfg mm l.exec none
        .continue { l with exec := x, cur := fin, cancelIters := nextCancelation,
                           autoCedeIters := nextAutoCede }
      else dispatch cfg mm env l nextCancelation nextAutoCede

/-- A new `runLoop` call with full counters (`FIB:1399`, `FIB:1405`, ...). -/
def freshLoop (r : Exec M × Flow) : StepResult M :=
  toStep { exec := r.1, cur := .endFiber, cancelIters := 0, autoCedeIters := 0 } r
    cfg.cancelationCheckThreshold cfg.autoYieldThreshold

/-- `run()` (`FIB:113-131`): the entry when the scheduler runs the fiber. The read barrier
(`FIB:115`) is implicit: an off-loop fiber has no pending cancel (`Exec` holds `canceled`). -/
def resume (x : Exec M) : StepResult M :=
  match x.fib.resumeTag with
  -- FIB:1386-1401 `execR`
  | .execR =>
    if x.fib.canceled then
      -- FIB:1388-1389: canceled before the first run; no finalizer was registered
      .done .canceled (done cfg mm x .canceled)
    else
      match x.fib.resumeIO with
      | some io =>
        -- FIB:1391-1399
        let x := { x with fib := { x.fib with
          conts := [.runTerminusK], objectState := [], finalizers := [], resumeIO := none } }
        freshLoop cfg (x, .io io)
      | none => .aborted .noResumeIO x
  -- FIB:1403-1406
  | .asyncContinueSuccessfulR =>
    match x.fib.objectState with
    | .val a :: os => freshLoop cfg (succeededK cfg mm env (x.setObj os) a 0)
    | _ => .aborted .badObjectState x
  -- FIB:1408-1411
  | .asyncContinueFailedR =>
    match x.fib.objectState with
    | .err t :: os => freshLoop cfg (failedK cfg mm env (x.setObj os) t 0)
    | _ => .aborted .badObjectState x
  -- FIB:1413-1416
  | .asyncContinueCanceledR =>
    let (x, fin) := prepareFiberForCancelation cfg mm x none
    freshLoop cfg (x, .io fin)
  -- FIB:1418-1422
  | .asyncContinueCanceledWithFinalizerR =>
    match x.fib.objectState with
    | .cancelCb cb :: os =>
      let (x, fin) := prepareFiberForCancelation cfg mm (x.setObj os) cb
      freshLoop cfg (x, .io fin)
    | _ => .aborted .badObjectState x
  -- FIB:1424-1451 `blockingR`: needs the blocking pool
  | .blockingR => .aborted (.unsupportedResume .blockingR) x
  -- FIB:1453-1455 `cedeR`
  | .cedeR => freshLoop cfg (succeededK cfg mm env x .unit 0)
  -- FIB:1457-1461 `autoCedeR`
  | .autoCedeR =>
    match x.fib.resumeIO with
    | some io => freshLoop cfg ({ x with fib := { x.fib with resumeIO := none } }, .io io)
    | none => .aborted .noResumeIO x
  -- FIB:130 `DoneR`: nothing
  | .doneR =>
    match x.fib.outcome with
    | some oc => .done oc x
    | none => .suspended x

end Run

/-! ## External cancel (`IOFiber.cancel`, `FIB:142-175`, `FIB:197-201`) -/

/-- Where the fiber is when another fiber runs `fiber.cancel`. -/
inductive Where (M : Type) where
  /-- Inside its run loop on another thread. -/
  | running (l : Loop M)
  /-- Off the run loop: in a ready queue (`suspended = false`) or suspended on an async
  boundary (`suspended = true`), or done. -/
  | off (x : Exec M)
  deriving DecidableEq, Repr

/-- The effect of the `_cancel` body (`FIB:142-175`) on the target fiber, when the canceller
reads `_cancel` before `done` swapped it for `IO.unit` (`FIB:1095`). `canceller` names the
`ContState` of the canceller's `IO.async_` (`FIB:155`).

Local part only. Not modelled here (needs the scheduler, step 8): `cancel` is itself
`uncancelable`; the canceller then waits (`IO.async_` or `join.void`) until the target
calls `cancelerCb` or completes. -/
def cancelFiber {M : Type} (mm : MaskModel M) (canceller : Nat) : Where M → Where M
  | .running l =>
    if l.exec.fib.outcome.isSome then .running l -- FIB:1095 `_cancel = IO.unit`
    else
      -- FIB:143 `canceled = true` (a plain write, seen later: `pendingCancel`).
      -- FIB:148 `resume()` fails (the target owns its run loop): FIB:173 `join.void`.
      .running { l with pendingCancel := true }
  | .off x =>
    if x.fib.outcome.isSome then .off x -- FIB:1095 `_cancel = IO.unit`
    else
      -- FIB:143
      let x := { x with fib := { x.fib with canceled := true } }
      -- FIB:148 `if (resume())`: `suspended.getAndSet(false)`
      if x.fib.suspended then
        let x := { x with fib := { x.fib with suspended := false } }
        if mm.isUnmasked x.fib.mask then
          -- FIB:155-161: take over and run the finalizers on the target
          .off { x with fib := { x.fib with
            resumeTag := .asyncContinueCanceledWithFinalizerR,
            objectState := .cancelCb (some canceller) :: x.fib.objectState } }
        else
          -- FIB:167-168 `suspend()`; then `join.void`
          .off { x with fib := { x.fib with suspended := true } }
      else
        -- FIB:173 `join.void`: the fiber is queued and sees `canceled` in `run()`
        .off x

end CatsEffectInLean.Model

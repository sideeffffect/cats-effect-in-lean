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
* Phase 2 step 8 (part): `IOCont`, `Get`, `Cede` and `Start` are mirrored, with the runtime
  closures of `_cancel` and `_join` (`RtFn`, `rtCall`) and the `IOCont` callback
  (`contCallback`). These read and write other fibers through `Exec.fibers`. The multi-fiber
  scheduler is `CatsEffectInLean/Model/Sched.lean`.
* Phase 2 step 9 (part): `IODeferred` (`get`, `complete`, `clear`) as runtime closures
  (`RtFn.deferred*`) over `Heap.deferreds`.
* `RacePair`, `Sleep`, a foreign `EvalOn` and `Blocking` give `Abort.unsupportedTag`. They
  never succeed silently.

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

/-- Why the model stops without a Cats Effect result. Never a Cats Effect outcome. -/
inductive Abort where
  /-- A tag that the single-fiber step does not implement yet (Phase 2 step 8). -/
  | unsupportedTag (tag : Int)
  /-- A resume tag that the single-fiber step does not implement yet (`blockingR`). -/
  | unsupportedResume (tag : ResumeTag)
  /-- A runtime closure (`Fn.rt`) must run. They come only from unsupported tags. -/
  | unsupportedFn
  /-- Not used any more: user code can call `IOCont` callbacks since Phase 2 step 8. Kept so
  that older examples still name it. -/
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
  /-- A `ContState` id that does not exist, or a `Get` that finds the state "waiting"
  (`FIB:849-863` says this cannot happen; Scala would throw a `MatchError`). -/
  | badContState
  /-- A fiber id that does not exist. -/
  | badHandle
  /-- The `IOCont` callback must spin until `get` gives up the run loop (`FIB:701-709`). With
  one thread nothing gives it up, so this is a hang of the scripted runtime. -/
  | cbSpin
  /-- The task scheduler found a broken invariant (for example a ready index out of range). -/
  | badSched
  deriving DecidableEq, Repr

/-- One task in the ready list of the `ExecutionContext` (in replay mode: the scripted
`ExecutionContext` of `difftest/src/main/scala/cats/effect/difftest/Runner.scala`). -/
inductive Task where
  /-- `ec.execute(fiber)`: the task is one `IOFiber.run()` (`FIB:113-131`). `scheduleFiber`
  and `rescheduleFiber` both end in `ec.execute` for an `ExecutionContext` that is not a
  `WorkStealingThreadPool` (`FIB:1333-1376`). -/
  | fiber (id : Nat)
  /-- A task that calls the `IOCont` callback of cell `state` with `result`
  (`UserEffect.deferCb`; in the difftest a `CbTask`). -/
  | cb (state : Nat) (result : Val)
  deriving DecidableEq, Repr

/-- The part of the world that one fiber step reads and writes, other than the fibers. -/
structure Heap where
  /-- `Ref` cells (index = id). User code reads a snapshot and writes with `writeRef`.
  A write to an id that is not in the list has no effect, so examples allocate first. -/
  refs : List Val := []
  /-- The virtual clock (`RealTime`/`Monotonic`, `FIB:294-306`). -/
  clock : Nat := 0
  /-- Runtime events, newest first. -/
  trace : List TraceEv := []
  /-- `ContState` cells (index = id; one per executed `IOCont`, `FIB:642`). -/
  conts : List ContState := []
  /-- The ready list of the `ExecutionContext`, in enqueue order (`ec.execute` appends). -/
  ready : List Task := []
  /-- The next fresh `CallbackStack` handle (handle 0 is the constructor callback). -/
  handles : Nat := 1
  /-- Values that user code emitted (`UserEffect.emit`), newest first. -/
  out : List Val := []
  /-- A broken invariant found where the step cannot return an `Abort` (inside `done` and
  the `IOCont` callback). The first one wins. The scheduler stops when it is set. -/
  broken : Option Abort := none
  /-- `IODeferred` cells (index = `Deferred` id; `UserEffect.allocDeferred`). -/
  deferreds : List DeferredCell := []
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
  /-- `runLoop` returns because the fiber put itself in the ready list (`Cede`,
  `FIB:886-888`). -/
  | yield
  deriving DecidableEq, Repr

/-- The fiber and the world: what `succeeded`, `failed` and the branches change.

`fib` is the fiber in focus (the one that runs). `fibers` is the table of all fibers (index =
fiber id); the slot of `fib` in it can be old while `fib` runs. `getFib` and `setFib` read and
write any fiber and use `fib` for its own id. -/
structure Exec (M : Type) where
  fib : Fiber M
  heap : Heap
  fibers : List (Fiber M) := []
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
/-- Fiber `t` (the focused fiber for its own id). -/
def getFib (x : Exec M) (t : Nat) : Option (Fiber M) :=
  if t == x.fib.id then some x.fib else x.fibers[t]?
/-- Write fiber `t`. -/
def setFib (x : Exec M) (t : Nat) (f : Fiber M) : Exec M :=
  if t == x.fib.id then { x with fib := f } else { x with fibers := x.fibers.set t f }
/-- `ec.execute(task)`: append a task to the ready list. -/
def enqueue (x : Exec M) (t : Task) : Exec M :=
  { x with heap := { x.heap with ready := x.heap.ready ++ [t] } }
/-- Write `ContState` cell `s`. -/
def setContState (x : Exec M) (s : Nat) (st : ContState) : Exec M :=
  { x with heap := { x.heap with conts := x.heap.conts.set s st } }
/-- Record a broken invariant (the first one wins). -/
def markBroken (x : Exec M) (a : Abort) : Exec M :=
  match x.heap.broken with
  | some _ => x
  | none => { x with heap := { x.heap with broken := some a } }
/-- What user code can read (`View`). -/
def view (x : Exec M) : View :=
  { refs := x.heap.refs, outcomes := (x.fibers.set x.fib.id x.fib).map (·.outcome),
    deferreds := x.heap.deferreds.map (·.value) }
/-- Write `IODeferred` cell `d`. -/
def setDeferred (x : Exec M) (d : Nat) (c : DeferredCell) : Exec M :=
  { x with heap := { x.heap with deferreds := x.heap.deferreds.set d c } }
/-- A fresh `CallbackStack` handle. -/
def freshHandle (x : Exec M) : Nat × Exec M :=
  (x.heap.handles, { x with heap := { x.heap with handles := x.heap.handles + 1 } })
end Exec

/-! ## User code, runtime closures and the `IOCont` callback -/

section Closures
variable {M : Type} (mm : MaskModel M)

/-- `shouldFinalize()` (`FIB:1172-1173`) with `isUnmasked()` (`FIB:1175-1176`). -/
def shouldFinalize (fib : Fiber M) : Bool :=
  fib.canceled && mm.isUnmasked fib.mask

/-- The callback `cb` of the `IOCont` with cell `s`, called with `result` (`FIB:644-755`).
`result` is `Val.left (Val.err t)` or `Val.right a` (`Val.ofExcept`).

`stateLoop` (`FIB:737-752`): an "initial" cell gets the result (the callback came first); a
"waiting" cell gets the result and then `loop()` takes the run loop of the suspended fiber
and schedules it (`FIB:664-716`); a cell with a result ignores the call (`FIB:733-734`).
The CAS loops succeed at once: one model step is atomic. -/
def contCallback (s : Nat) (result : Val) (x : Exec M) : Exec M :=
  match x.heap.conts[s]? with
  | none => x.markBroken .badContState
  | some st =>
    match st.value with
    -- FIB:739: neither "initial" nor "waiting": a second call is a no-op
    | .result _ => x
    -- FIB:740: CAS(null, result); `cb` came first, so it stops here (FIB:731)
    | .initial => x.setContState s { st with value := .result result }
    | .waiting =>
      -- FIB:740 CAS(waiting, result), then FIB:748 `loop()`
      let x := x.setContState s { st with value := .result result }
      match x.getFib st.fiber with
      | none => x.markBroken .badHandle
      | some f =>
        -- FIB:667 `resume()`: `suspended.getAndSet(false)`
        if f.suspended then
          let f := { f with suspended := false }
          -- FIB:670
          if f.finalizing == st.wasFinalizing then
            -- FIB:671-673 `state.handle.deregister()`: fiber monitor only
            -- FIB:675-693
            if !shouldFinalize mm f then
              match result with
              | .left (.err t) =>
                (x.setFib f.id { f with resumeTag := .asyncContinueFailedR,
                                         objectState := .err t :: f.objectState }).enqueue
                  (.fiber f.id)
              | .right a =>
                (x.setFib f.id { f with resumeTag := .asyncContinueSuccessfulR,
                                         objectState := .val a :: f.objectState }).enqueue
                  (.fiber f.id)
              | _ => (x.setFib f.id f).markBroken .illTyped
            else
              -- FIB:691: canceled; we won `resume`, so we run the finalizers
              (x.setFib f.id { f with resumeTag := .asyncContinueCanceledR }).enqueue (.fiber f.id)
          else
            -- FIB:699 `suspend()`
            x.setFib f.id { f with suspended := true }
        else if f.finalizing == st.wasFinalizing && !shouldFinalize mm f && f.outcome.isNone then
          -- FIB:701-709: spin until `get` gives up the run loop
          x.markBroken .cbSpin
        else
          -- FIB:711-715: canceled, completed or finalizing: let `cancel` or `get` win
          x

/-- Run a runtime closure (`Fn.rt`) on `arg`. Each case mirrors one Scala lambda; the
citations are on the `RtFn` constructors (`CatsEffectInLean/Model/Syntax.lean`). Runtime
closures never throw. -/
def rtCall (k : RtFn) (arg : Val) (x : Exec M) : Except Abort (UserOut × Exec M) :=
  match k with
  | .contGetFin s =>
    -- FIB:781-784 `state.compareAndSet(state.waiting, null)`
    match x.heap.conts[s]? with
    | some st =>
      if st.value == .waiting then .ok (.ret .unit, x.setContState s { st with value := .initial })
      else .ok (.ret .unit, x)
    | none => .error .badContState
  -- FIB:804-807: fiber monitor only
  | .monitorDeregister _ => .ok (.ret .unit, x)
  | .cancel t =>
    match x.getFib t with
    | none => .error .badHandle
    | some f =>
      -- FIB:143 `canceled = true`
      let f := { f with canceled := true }
      -- FIB:148 `if (resume())`
      if f.suspended then
        let f := { f with suspended := false }
        if mm.isUnmasked f.mask then
          -- FIB:155-161 `IO.async_[Unit] { fin => ... }` = `IOCont(body)` (`IO.scala:1473-1481`)
          .ok (.prog (.ioCont (.rt (.cancelAsync t))), x.setFib t f)
        else
          -- FIB:167-168 `suspend(); join.void`; `void` = `map(_ => ())` (`IO.scala:961-962`)
          let f := { f with suspended := true }
          .ok (.prog (.map (IO.joinOf t f.outcome) (.rt .voidK)), x.setFib t f)
      else
        -- FIB:173 `join.void`
        .ok (.prog (.map (IO.joinOf t f.outcome) (.rt .voidK)), x.setFib t f)
  | .cancelAsync t =>
    match arg with
    -- IO.scala:1476 `G.uncancelable(_ => ...)`
    | .cont s => .ok (.prog (.uncancelable (.rt (.cancelAsyncUnc t s))), x)
    | _ => .error .illTyped
  -- IO.scala:1476 `lift(IO.delay(k(resume))).flatMap(_ => get)`
  | .cancelAsyncUnc t s =>
    .ok (.prog (.flatMap (.delay (.rt (.cancelAsyncK t s))) (.rt (.getK s))), x)
  | .cancelAsyncK t s =>
    match x.getFib t with
    | none => .error .badHandle
    | some f =>
      -- FIB:157-160 `ec = currentCtx; resumeTag = AsyncContinueCanceledWithFinalizerR;
      -- objectState.push(fin); scheduleFiber(ec, this)`
      let f := { f with resumeTag := .asyncContinueCanceledWithFinalizerR,
                        objectState := .cancelCb (some s) :: f.objectState }
      .ok (.ret .unit, (x.setFib t f).enqueue (.fiber t))
  | .getK s => .ok (.prog (.contGet s), x)
  | .voidK => .ok (.ret .unit, x)
  | .join t =>
    match arg with
    -- IO.scala:1357 `G.uncancelable { poll => ... }`
    | .cont s => .ok (.prog (.uncancelable (.rt (.joinUnc t s))), x)
    | _ => .error .illTyped
  | .joinUnc t s =>
    match arg with
    -- IO.scala:1358 `lift(k(resume)) flatMap { ... }`; `k(cb) = IO { ... }` (FIB:180)
    | .poll m p =>
      .ok (.prog (.flatMap (.delay (.rt (.joinReg t s))) (.rt (.joinSel t s m p))), x)
    | _ => .error .illTyped
  | .joinReg t s =>
    match x.getFib t with
    | none => .error .badHandle
    | some f =>
      match f.outcome with
      | none =>
        -- FIB:182 `callbacks.push(oc => cb(Right(oc)))`; FIB:185 double-check (one thread:
        -- `outcome` is still `null`); FIB:189 `Left(Some(IO { clearHandle }))`
        let h := x.heap.handles
        let x := x.setFib t { f with callbacks := (h, .join s) :: f.callbacks }
        .ok (.ret (.left (.some (.nat h))), { x with heap := { x.heap with handles := h + 1 } })
      -- FIB:191-192 `Right(outcome)`
      | some oc => .ok (.ret (.right oc.toVal), x)
  | .joinSel t s m p =>
    match arg with
    -- IO.scala:1359
    | .right a => .ok (.prog (.pure a), x)
    -- IO.scala:1360 `G.onCancel(poll(get), lift(fin))`; `poll(get)` = `UnmaskRunLoop`
    -- (FIB:564-567)
    | .left (.some (.nat h)) =>
      .ok (.prog (.onCancel (.unmaskRunLoop (.contGet s) m p) (.delay (.rt (.joinClear t h)))), x)
    -- IO.scala:1361
    | .left .none => .ok (.prog (.contGet s), x)
    | _ => .error .illTyped
  | .joinClear t h =>
    match x.getFib t with
    | none => .error .badHandle
    -- FIB:189 `callbacks.clearHandle(handle)`
    | some f => .ok (.ret .unit, x.setFib t { f with callbacks := f.callbacks.filter (·.1 != h) })
  -- IODeferred (`core/shared/src/main/scala/cats/effect/IODeferred.scala`, `ID` below)
  | .deferredDefer d =>
    match x.heap.deferreds[d]? with
    | none => .error .badHandle
    -- ID:52-56 `if (back eq initial) await else back`
    | some c => .ok (.ret (match c.value with | some a => .some a | none => .none), x)
  | .deferredFlatten d =>
    match arg with
    -- `await` = `IO.asyncCheckAttempt { ... }` = `IOCont(body)` (IO.scala:1353-1368)
    | .none => .ok (.prog (.ioCont (.rt (.deferredAwait d))), x)
    | .some a => .ok (.prog (.pure a), x)
    | _ => .error .illTyped
  | .deferredAwait d =>
    match arg with
    -- IO.scala:1357 `G.uncancelable { poll => ... }`
    | .cont s => .ok (.prog (.uncancelable (.rt (.deferredUnc d s))), x)
    | _ => .error .illTyped
  | .deferredUnc d s =>
    match arg with
    -- IO.scala:1358 `lift(k(resume)) flatMap { ... }`; `k(cb) = IO { ... }` (ID:25)
    | .poll m p => .ok (.prog (.flatMap (.delay (.rt (.deferredReg d s))) (.rt (.deferredSel d s m p))), x)
    | _ => .error .illTyped
  | .deferredReg d s =>
    match x.heap.deferreds[d]? with
    | none => .error .badHandle
    | some c =>
      -- ID:26 `val handle = callbacks.push(cb)`
      let (h, x) := x.freshHandle
      let c := { c with callbacks := (h, s) :: c.callbacks }
      -- ID:39-40 `val back = cell.get()`
      match c.value with
      -- ID:41 `Left(Some(IO(clear())))`
      | none => .ok (.ret (.left (.some (.nat h))), x.setDeferred d c)
      | some a =>
        -- ID:43-44 `clear()`: `clearHandle` nulls the callback and returns `false` (JVM
        -- `CallbackStack.clearHandle`), so `clearCounter` goes up. `pack` only frees cleared
        -- nodes; the model removes the node at once. Then `Right(value)`.
        let c := { c with callbacks := c.callbacks.filter (·.1 != h), clearCounter := c.clearCounter + 1 }
        .ok (.ret (.right a), x.setDeferred d c)
  | .deferredSel d s m p =>
    match arg with
    -- IO.scala:1359
    | .right a => .ok (.prog (.pure a), x)
    -- IO.scala:1360 `G.onCancel(poll(get), lift(fin))`
    | .left (.some (.nat h)) =>
      .ok (.prog (.onCancel (.unmaskRunLoop (.contGet s) m p) (.delay (.rt (.deferredClear d h)))), x)
    -- IO.scala:1361
    | .left .none => .ok (.prog (.contGet s), x)
    | _ => .error .illTyped
  | .deferredClear d h =>
    match x.heap.deferreds[d]? with
    | none => .error .badHandle
    -- ID:28-37 `clear()` (see `deferredReg`)
    | some c =>
      .ok (.ret .unit, x.setDeferred d { c with callbacks := c.callbacks.filter (·.1 != h),
                                                clearCounter := c.clearCounter + 1 })
  | .deferredComplete d v =>
    match x.heap.deferreds[d]? with
    | none => .error .badHandle
    | some c =>
      match c.value with
      -- ID:63 `cell.compareAndSet(initial, IO.pure(a))` fails: ID:67 `false`
      | some _ => .ok (.ret (.bool false), x)
      | none =>
        -- ID:63-65: the cell holds `IO.pure(a)`; `callbacks(Right(a))` calls the callbacks from
        -- the head (newest first; the constructor callback is `null`, ID:59) and clears the
        -- stack (`CallbackStack.apply`); each callback is the `resume` of a waiting `await`
        let x := x.setDeferred d { c with value := some v, callbacks := [] }
        let x := c.callbacks.foldl (fun x p => contCallback mm p.2 (.right v) x) x
        .ok (.ret (.bool true), x)
  | .racePairRegister _ _ | .sleepRegister _ => .error .unsupportedFn

/-- Apply the effects of one user call, in order. -/
def applyEffects : List UserEffect → Exec M → Exec M
  | [], x => x
  | .writeRef r v :: es, x =>
    applyEffects es { x with heap := { x.heap with refs := x.heap.refs.set r v } }
  | .allocRef v :: es, x =>
    applyEffects es { x with heap := { x.heap with refs := x.heap.refs ++ [v] } }
  | .allocDeferred :: es, x =>
    applyEffects es { x with heap := { x.heap with deferreds := x.heap.deferreds ++ [{}] } }
  | .emit v :: es, x =>
    applyEffects es { x with heap := { x.heap with out := v :: x.heap.out } }
  | .invokeCb s r :: es, x => applyEffects es (contCallback mm s r x)
  | .deferCb s r :: es, x => applyEffects es (x.enqueue (.cb s r))

/-- Call a function with no `try` around it: effects first, then the output. User code sees
`Exec.view`. -/
def callUser (env : UserEnv) (f : Fn) (arg : Val) (x : Exec M) :
    Except Abort (UserOut × Exec M) :=
  match f with
  | .rt k => rtCall mm k arg x
  | .user id =>
    let r := env.callV id arg x.view
    .ok (r.out, applyEffects mm r.effects x)

/-- The result of user code inside the run loop's `try` / `catch`. -/
inductive TryRes (M : Type) where
  /-- The call returned (`out` is `ret` or `prog`, never `throw`). -/
  | ok (out : UserOut) (x : Exec M)
  /-- `case t if UnsafeNonFatal(t) => ...` caught `e`. -/
  | caught (e : Err) (x : Exec M)
  /-- `case t: Throwable => onFatalFailure(t)`. -/
  | fatal (e : Err) (x : Exec M)
  /-- The model stops. -/
  | abort (a : Abort)

/-- `try f(arg) catch { case t if UnsafeNonFatal(t) => ...; case t: Throwable =>
onFatalFailure(t) }`, the pattern at `FIB:280-286` and its copies. -/
def tryUser (env : UserEnv) (f : Fn) (arg : Val) (x : Exec M) : TryRes M :=
  match callUser mm env f arg x with
  | .error a => .abort a
  | .ok (.throw e, x') => if e.isNonFatal then .caught e x' else .fatal e x'
  | .ok (out, x') => .ok out x'

/-- `try f(thunk()) catch ...`: two calls inside one `try` (`FIB:359`, `FIB:429`). If the
thunk throws, `f` does not run. -/
def tryUser2 (env : UserEnv) (thunk f : Fn) (x : Exec M) : TryRes M :=
  match tryUser mm env thunk .unit x with
  | .ok (.ret r) x' => tryUser mm env f r x'
  | .ok _ _ => .abort .illTyped
  | other => other

end Closures

/-! ## Helpers of the run loop -/

section Helpers
variable {M : Type} (cfg : Config) (mm : MaskModel M)

/-- Call one outcome callback (`FIB:1099`). A `join` callback is `oc => cb(Right(oc))`
(`FIB:182`). -/
def runOutcomeCb (oc : Outcome) (x : Exec M) : OutcomeCb → Exec M
  | .root | .ext => x
  | .join s => contCallback mm s (.right oc.toVal) x
  | .raceLeft _ _ | .raceRight _ _ => x.markBroken .unsupportedFn

/-- `done(oc)` (`FIB:1092-1126`). `_join`/`_cancel` (`FIB:1094-1095`) follow from `outcome`.
`currentCtx = null` (`FIB:1121`) is not modelled (no read after `done`). -/
def done (x : Exec M) (oc : Outcome) : Exec M :=
  -- FIB:1097 `outcome = oc`
  let fib := { x.fib with outcome := some oc }
  -- FIB:1099 `callbacks(oc)`: `CallbackStack.apply` calls the constructor callback (handle 0)
  -- first, then the pushed callbacks from the head (newest first), and clears the stack
  -- (`core/jvm-native/src/main/scala/cats/effect/CallbackStack.scala`, `apply`)
  let cbs := fib.callbacks.filter (·.1 == 0) ++ fib.callbacks.filter (·.1 != 0)
  let x := { x with fib := { fib with callbacks := [] } }
  let x := cbs.foldl (fun x p => runOutcomeCb mm oc (x.log (.outcomeCb p.2 oc)) p.2) x
  -- FIB:1099-1104 report an `Errored` outcome that nobody receives
  let x :=
    if cbs.isEmpty && cfg.reportUnhandledFiberErrors then
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
    -- FIB:1154-1156 unblock the canceller: `cb(RightUnit)`
    let x := match cb with
      | some s => contCallback mm s (.right .unit) (x.log (.cancelerCb s))
      | none => x
    -- FIB:1159-1162
    (done cfg mm x .canceled, .endFiber)

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
        | some s => contCallback mm s (.right .unit) (x.log (.cancelerCb s))
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
        match tryUser mm env f result x with
        | .ok (.ret t) x =>
          -- FIB:1226-1228: hand back to the run loop at depth > MaxStackDepth
          if depth > cfg.maxStackDepth then (x, .io (.pure t))
          else succeeded x t (depth + 1) rest
        | .caught e x =>
          if depth > cfg.maxStackDepth then (x, .io (.error e))
          else failed x e (depth + 1) rest
        | .ok _ x => (x, .abort .illTyped)
        | .fatal e x => (x, .fatal e)
        | .abort a => (x, .abort a)
      | _ => (x, .abort .badObjectState)
    | .flatMapK =>
      -- FIB:1234-1243
      match x.fib.objectState with
      | .fn f :: os =>
        let x := x.setObj os
        match tryUser mm env f result x with
        | .ok (.prog p) x => (x, .io p)
        | .caught e x => failed x e (depth + 1) rest
        | .ok _ x => (x, .abort .illTyped)
        | .fatal e x => (x, .fatal e)
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
        match tryUser mm env f (.err error) x with
        | .ok (.prog p) x => (x, .io p)
        | .caught e x => failed x e (depth + 1) rest
        | .ok _ x => (x, .abort .illTyped)
        | .fatal e x => (x, .fatal e)
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
def afterValue (x : Exec M) : TryRes M → Exec M × Flow
  | .ok (.ret r) x' => succeededK cfg mm env x' r 0
  | .caught e x' => failedK cfg mm env x' e 0
  | .ok _ x' => (x', .abort .illTyped)
  | .fatal e x' => (x', .fatal e)
  | .abort a => (x, .abort a)

/-- A user call result in a program position: `try f(v) catch { case NonFatal(t) =>
failed(t, 0) }` (`FIB:398-405`, `FIB:428-435`). -/
def afterProg (x : Exec M) : TryRes M → Exec M × Flow
  | .ok (.prog p) x' => (x', .io p)
  | .caught e x' => failedK cfg mm env x' e 0
  | .ok _ x' => (x', .abort .illTyped)
  | .fatal e x' => (x', .fatal e)
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

/-- The `Get` branch (`FIB:771-883`). When the fiber suspends, the run loop returns: the
result is `Flow.io IO.endFiber` and the fiber has no outcome. -/
def contGet (x : Exec M) (s : Nat) : Exec M × Flow :=
  match x.heap.conts[s]? with
  | none => (x, .abort .badContState)
  | some st =>
    -- FIB:781-786: `fin = IO { state.compareAndSet(state.waiting, null) }`; push it; `OnCancelK`
    let x := { x with fib := { x.fib with
      finalizers := .delay (.rt (.contGetFin s)) :: x.fib.finalizers } }
    let x := x.pushCont .onCancelK
    match st.value with
    | .initial =>
      -- FIB:788 CAS(null, waiting) succeeds; FIB:800 `state.wasFinalizing = finalizing`
      let x := x.setContState s { st with value := .waiting, wasFinalizing := x.fib.finalizing }
      -- FIB:802-810: stack tracing is on by default; one more finalizer and `OnCancelK`
      let x := { x with fib := { x.fib with
        finalizers := .delay (.rt (.monitorDeregister s)) :: x.fib.finalizers } }
      let x := x.pushCont .onCancelK
      -- FIB:819 `suspended.getAndSet(true)`
      let x := { x with fib := { x.fib with suspended := true } }
      -- FIB:825
      if shouldFinalize mm x.fib then
        -- FIB:834 `resume()`: no other thread took the run loop, so it succeeds;
        -- FIB:835-837 `shouldFinalize()` is still true
        let x := { x with fib := { x.fib with suspended := false } }
        let (x, fin) := prepareFiberForCancelation cfg mm x none
        (x, .io fin)
      else
        -- the run loop returns; `cb` resumes the fiber later
        (x, .io .endFiber)
    -- FIB:849-863: "impossible"; Scala would throw a `MatchError`
    | .waiting => (x, .abort .badContState)
    | .result r =>
      -- FIB:865-882
      if !shouldFinalize mm x.fib then
        match r with
        | .left (.err t) => failedK cfg mm env x t 0
        | .right a => succeededK cfg mm env x a 0
        | _ => (x, .abort .illTyped)
      else if x.fib.outcome.isNone then
        let (x, fin) := prepareFiberForCancelation cfg mm x none
        (x, .io fin)
      else (x, .io .endFiber)

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
  /-- Auto-yield (`FIB:233-238`) or `Cede` (`FIB:886-888`): the fiber set its resume tag and
  put itself at the end of the ready list (`Heap.ready`). The scheduler decides when it runs
  again. -/
  | yielded (x : Exec M)
  /-- `runLoop` returned at `EndFiber` (`FIB:220-222`) but the fiber has no outcome: it
  waits for an async callback (`Get`), or another fiber took its run loop. -/
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
  | .yield => .yielded r.1

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
  | .delay thunk => ret (afterValue cfg mm env x (tryUser mm env thunk .unit x)) nc
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
    | .pure v => ret (afterValue cfg mm env x (tryUser mm env f v x)) (nc - 1)
    -- FIB:341-347 over `Error`: `f` is never called
    | .error ex => ret (raised cfg mm env x ex) (nc - 1)
    -- FIB:349-368 over `Delay`: `f(thunk())` in one `try`
    | .delay thunk => ret (afterValue cfg mm env x (tryUser2 mm env thunk f x)) (nc - 1)
    -- FIB:370-380 over `RealTime`, `Monotonic`, `ReadEC`
    | .realTime | .monotonic | .readEC =>
      match leafValue x ioe with
      | some v => ret (afterValue cfg mm env x (tryUser mm env f v x)) (nc - 1)
      | none => ret (x, .abort .illTyped) nc
    -- FIB:382-385 general case
    | _ => ret ((x.pushObj (.fn f)).pushCont .mapK, .io ioe) nc
  -- FIB:388-455 `FlatMap`
  | .flatMap ioe f =>
    match ioe with
    -- FIB:408-410 over `Pure`
    | .pure v => ret (afterProg cfg mm env x (tryUser mm env f v x)) (nc - 1)
    -- FIB:412-418 over `Error`
    | .error ex => ret (raised cfg mm env x ex) (nc - 1)
    -- FIB:420-437 over `Delay`: `f(thunk())` in one `try`
    | .delay thunk => ret (afterProg cfg mm env x (tryUser2 mm env thunk f x)) (nc - 1)
    -- FIB:439-449 over `RealTime`, `Monotonic`, `ReadEC`
    | .realTime | .monotonic | .readEC =>
      match leafValue x ioe with
      | some v => ret (afterProg cfg mm env x (tryUser mm env f v x)) (nc - 1)
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
      match tryUser mm env thunk .unit x with
      | .ok (.ret r) x => ret (succeededK cfg mm env x (.right r) 0) (nc - 1)
      | .caught e x => ret (succeededK cfg mm env x (.left (.err e)) 0) (nc - 1)
      | .ok _ x => ret (x, .abort .illTyped) (nc - 1)
      | .fatal e x => ret (x, .fatal e) (nc - 1)
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
    match tryUser mm env body (.poll id x.fib.id) x with
    | .ok (.prog p) x => ret (x.pushCont .uncancelableK, .io p) nc
    -- FIB:572-573 `IO.raiseError(t)`
    | .caught e x => ret (x.pushCont .uncancelableK, .io (.error e)) nc
    | .ok _ x => ret (x, .abort .illTyped) nc
    | .fatal e x => ret (x, .fatal e) nc
    | .abort a => ret (x, .abort a) nc
  -- FIB:585-602 `UnmaskRunLoop`: "the outer block wins"
  | .unmaskRunLoop ioa id self =>
    if mm.pollMatches x.fib.mask id && self == x.fib.id then
      ret ((x.setMask (mm.unmask x.fib.mask)).pushCont .unmaskK, .io ioa) nc
    else
      ret (x, .io ioa) nc
  -- FIB:604-769 `IOCont`
  | .ioCont body =>
    -- FIB:642 `val state = new ContState(finalizing)`
    let s := x.heap.conts.length
    let x := { x with heap := { x.heap with
      conts := x.heap.conts ++ [{ fiber := x.fib.id, wasFinalizing := x.fib.finalizing }] } }
    -- FIB:759-767 `try body[IO].apply(cb, get, FunctionK.id)`; `cb` and `get` are `Val.cont s`
    match tryUser mm env body (.cont s) x with
    | .ok (.prog p) x => ret (x, .io p) nc
    -- FIB:763-764 `IO.raiseError(t)`
    | .caught e x => ret (x, .io (.error e)) nc
    | .ok _ x => ret (x, .abort .illTyped) nc
    | .fatal e x => ret (x, .fatal e) nc
    | .abort a => ret (x, .abort a) nc
  -- FIB:771-883 `Get`
  | .contGet s => ret (contGet cfg mm env x s) nc
  -- FIB:885-888 `Cede`: `resumeTag = CedeR; rescheduleFiber(currentCtx, this)`, then return
  | .cede =>
    let x := { x with fib := { x.fib with resumeTag := .cedeR } }
    ret (x.enqueue (.fiber x.fib.id), .yield) nc
  -- FIB:890-906 `Start`
  | .start ioa =>
    -- FIB:893-900 `new IOFiber(localState, null, cur.ioa, ec, runtime)` (no callback)
    let id := x.fibers.length
    let child := Fiber.new mm id x.fib.localState x.fib.currentCtx ioa none
    let x := { x with fibers := x.fibers ++ [child] }
    -- FIB:904 `scheduleFiber(ec, fiber)`, FIB:906 `succeeded(fiber, 0)`
    ret (succeededK cfg mm env (x.enqueue (.fiber id)) (.fiber id) 0) nc
  -- `RacePair`, `Sleep` (FIB:908-981): not mirrored yet
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
    match callUser mm env f x.fib.localState x with
    | .ok (.ret (.pair s v), x) =>
      let x := { x with fib := { x.fib with localState := s } }
      ret (succeededK cfg mm env x v 0) nc
    | .ok (.throw e, x) => ret (x, .uncaught e) nc
    | .ok (_, x) => ret (x, .abort .illTyped) nc
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
        -- FIB:236-237 `rescheduleFiber(currentCtx, this)`
        .yielded ({ l.exec with fib := { l.exec.fib with
          resumeTag := .autoCedeR, resumeIO := some cur } }.enqueue (.fiber l.exec.fib.id))
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

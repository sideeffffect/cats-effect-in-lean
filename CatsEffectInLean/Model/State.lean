import CatsEffectInLean.Model.Fiber

/-!
# Global state and scheduler choices (skeleton)

The replay scheduler that runs is `CatsEffectInLean/Model/Sched.lean` (`Sched`, `RChoice`).
This file keeps the planned shape for the refinement mode (`Choice.step`, `fire`, `tick`).

Phase 2 step 6 data only (no step function yet): the fiber soup, `Ref` and `Deferred`
cells, `ContState` cells, the virtual clock, the ready queue in enqueue order, and the
`Choice` type.

The ready queue order matters for schedule replay: the difftest replays chosen indices into
the ready list of a scripted `ExecutionContext` (`wiki/cats-effect/testcontrol.md`). `Start`
enqueues the child and the parent keeps running (`FIB:890-906`); `RacePair` enqueues A, then
B (`FIB:937-938`). `FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala` at `v3.7.1`.
-/

namespace CatsEffectInLean.Model

/-- One `IODeferred` cell (`core/shared/src/main/scala/cats/effect/IODeferred.scala:21-60`).
Shape only; Phase 2 step 9 mirrors the methods. -/
structure DeferredCell where
  /-- `cell: AtomicReference[IO[A]]` (`IODeferred.scala:58`): `none` for `initial`,
  `some a` for `IO.pure(a)` (`IODeferred.scala:63`). -/
  value : Option Val := none
  /-- `callbacks: CallbackStack[Right[Nothing, A]]` (`IODeferred.scala:59`) as
  (handle, `ContState` id) pairs. -/
  callbacks : List (Nat × Nat) := []
  /-- `clearCounter: AtomicInteger` (`IODeferred.scala:60`). -/
  clearCounter : Nat := 0
  deriving DecidableEq, Repr

/-- A pending external event: a callback call that user code deferred
(`UserEffect.deferCb`), or a timer of `Sleep` (`FIB:960-977`). -/
inductive Event where
  /-- Call the `IOCont` callback of cell `state` with `result` (another thread calls `cb`). -/
  | callCb (state : Nat) (result : Val)
  /-- A timer: at virtual time `wakeAt`, call the callback of cell `state` with `Right(())`
  (`scheduler.sleep(delay, () => cb(RightUnit))`, `FIB:972`). -/
  | timer (wakeAt : Nat) (state : Nat)
  deriving DecidableEq, Repr

/-- The global state, generic in the mask model `M`. Tables are lists; the index is the id. -/
structure State (M : Type) where
  /-- All fibers ever made; index = fiber id. -/
  fibers : List (Fiber M) := []
  /-- `Ref` cells; index = `Ref` id. -/
  refs : List Val := []
  /-- `IODeferred` cells; index = `Deferred` id. -/
  deferreds : List DeferredCell := []
  /-- `ContState` cells; index = cell id (one per executed `IOCont`, `FIB:642`). -/
  conts : List ContState := []
  /-- Virtual time (`TestControl`; `RealTime` and `Monotonic` read it, `FIB:294-306`). -/
  clock : Nat := 0
  /-- Fiber ids of runnable tasks, in enqueue order (`scheduleFiber`/`rescheduleFiber`,
  `FIB:1333-1364`). -/
  ready : List Nat := []
  /-- The fiber whose task runs now (`none` between tasks). -/
  running : Option Nat := none
  /-- Pending external events, in creation order. -/
  events : List Event := []
  /-- `onFatalFailure` was called with this error (`FIB:1597`): the runtime is shut down.
  This is a separate result, never a fiber `Outcome`. -/
  fatal : Option Err := none
  deriving DecidableEq, Repr

/-- One scheduler choice. It extends the `Choice` of the liveness spike
(`spikes/liveness/Liveness.lean`: a fiber and an `observe` flag) with task-level picks,
external cancel, external events and time.

* Replay mode (`wiki/cats-effect/testcontrol.md`) uses `pick`, `fire` and `tick` with
  `step true`.
* Refinement mode also uses `observe = false` and `cancel` at any step. -/
inductive Choice where
  /-- Start the task `ready[idx]` (a task boundary). -/
  | pick (idx : Nat)
  /-- Do one run-loop iteration of the running fiber. `observe` says whether a pending
  cancel from another thread is visible now (the `readBarrier`, `FIB:224-229`). -/
  | step (observe : Bool)
  /-- External cancel of fiber `fiber` (Phase 0 decision 2: external cancel is a schedule
  choice). -/
  | cancel (fiber : Nat)
  /-- Fire the pending event `events[idx]`. -/
  | fire (idx : Nat)
  /-- Advance the virtual clock to the earliest timer (`TestControl.tick`). -/
  | tick
  deriving DecidableEq, Repr

/-- A finite schedule (for replay and witnesses). -/
abbrev Schedule := List Choice

/-- The initial state for one root program `io`: one fiber with id 0 on `ExecutionContext`
0, the `root` callback, in the ready queue. -/
def State.init {M : Type} (mm : MaskModel M) (io : IO) : State M where
  fibers := [Fiber.new mm 0 .unit 0 io (some .root)]
  ready := [0]

end CatsEffectInLean.Model

import CatsEffectInLean.Model.Step

/-!
# Single-fiber driver (Phase 2 steps 6 and 10, one fiber only)

Runs one fiber with `step` and `resume` (`CatsEffectInLean/Model/Step.lean`) under a finite
schedule. The run is structural on the schedule list. A schedule that ends before the fiber
finishes gives "out of fuel", which is never a Cats Effect outcome.

The scheduler decides when a yielded fiber runs again: a `step` choice on a parked fiber
calls `run()` (`resume`). External cancel is a schedule choice (Phase 0 decision 2).
The multi-fiber scheduler is `CatsEffectInLean/Model/Sched.lean`. Here a `Cede` or a
`Start` works, but the single fiber is the only one that runs.
-/

namespace CatsEffectInLean.Model

/-- The state of the one fiber. -/
inductive Solo (M : Type) where
  /-- Inside `runLoop`. -/
  | running (l : Loop M)
  /-- Off the run loop and runnable (a new fiber, or after an auto-yield). The next `step`
  calls `run()`. -/
  | parked (x : Exec M)
  /-- Off the run loop and waiting for an async callback (`suspended = true`). -/
  | suspended (x : Exec M)
  /-- Completed with an outcome (`done`). -/
  | done (oc : Outcome) (x : Exec M)
  /-- `onFatalFailure` (`FIB:1597`). -/
  | fatal (e : Err) (x : Exec M)
  /-- An exception left the run loop (`Local`). The fiber never completes. -/
  | uncaught (e : Err) (x : Exec M)
  /-- The model stopped (`Abort`). -/
  | aborted (a : Abort) (x : Exec M)
  deriving DecidableEq, Repr

/-- One choice of the single-fiber schedule. -/
inductive SoloChoice where
  /-- One run-loop iteration, or `run()` of a parked fiber. `observe` as in `step`. -/
  | step (observe : Bool)
  /-- Another fiber calls `cancel` on this fiber; its `IO.async_` uses `ContState`
  `canceller`. -/
  | cancel (canceller : Nat)
  deriving DecidableEq, Repr

/-- The summary of a run. `outOfFuel` is not a Cats Effect result. -/
inductive Summary where
  | done (oc : Outcome)
  | fatal (e : Err)
  | uncaught (e : Err)
  | aborted (a : Abort)
  /-- The fiber waits for an async callback that never comes (a deadlock if nothing else
  runs). Only the single-fiber driver gives it. -/
  | suspended
  /-- The schedule ended while the fiber can still run. -/
  | outOfFuel
  /-- Multi-fiber scheduler (`CatsEffectInLean/Model/Sched.lean`): no task is ready and the
  root fiber has no outcome (the difftest outcome `blocked`). -/
  | blocked
  /-- Multi-fiber scheduler: the task limit was reached (the difftest outcome `fuel`,
  `maxSteps`). Like `outOfFuel`, this is not a Cats Effect result. -/
  | taskLimit
  deriving DecidableEq, Repr

section
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Turn a `StepResult` into the next `Solo` state. A yield parks the fiber; the
scheduler picks it again later. -/
def Solo.ofStep : StepResult M → Solo M
  | .continue l => .running l
  | .yielded x => .parked x
  | .suspended x => .suspended x
  | .done oc x => .done oc x
  | .fatal e x => .fatal e x
  | .uncaught e x => .uncaught e x
  | .aborted a x => .aborted a x

/-- Do one schedule choice. Choices that cannot act are stutters. -/
def Solo.next : SoloChoice → Solo M → Solo M
  | .step obs, .running l => Solo.ofStep (step cfg mm env obs l)
  | .step _, .parked x => Solo.ofStep (resume cfg mm env x)
  | .cancel c, .running l =>
    match cancelFiber mm c (.running l) with
    | .running l' => .running l'
    | .off x => .parked x
  | .cancel c, .parked x =>
    match cancelFiber mm c (.off x) with
    | .off x' => .parked x'
    | .running l => .running l
  | .cancel c, .suspended x =>
    match cancelFiber mm c (.off x) with
    | .off x' => if x'.fib.suspended then .suspended x' else .parked x'
    | .running l => .running l
  | _, s => s

/-- Run a schedule. Structural on the list. -/
def Solo.exec : List SoloChoice → Solo M → Solo M
  | [], s => s
  | c :: cs, s => Solo.exec cs (Solo.next cfg mm env c s)

/-- The heap of any state. -/
def Solo.heap : Solo M → Heap
  | .running l => l.exec.heap
  | .parked x | .suspended x | .done _ x | .fatal _ x | .uncaught _ x | .aborted _ x => x.heap

/-- The fiber of any state. -/
def Solo.fiber : Solo M → Fiber M
  | .running l => l.exec.fib
  | .parked x | .suspended x | .done _ x | .fatal _ x | .uncaught _ x | .aborted _ x => x.fib

/-- The summary of a state at the end of a schedule. -/
def Solo.summary : Solo M → Summary
  | .running _ | .parked _ => .outOfFuel
  | .suspended _ => .suspended
  | .done oc _ => .done oc
  | .fatal e _ => .fatal e
  | .uncaught e _ => .uncaught e
  | .aborted a _ => .aborted a

/-- The root fiber of `io` (fiber id 0, `ExecutionContext` 0, the `root` callback), not yet
started, with the `Ref` cells `refs`. -/
def Solo.init (io : IO) (refs : List Val := []) : Solo M :=
  let root := Fiber.new mm 0 .unit 0 io (some .root)
  .parked { fib := root, heap := { refs := refs }, fibers := [root] }

/-- Run `io` for `fuel` choices `step true` (no external cancel). -/
def runSolo (fuel : Nat) (io : IO) (refs : List Val := []) : Solo M :=
  Solo.exec cfg mm env (List.replicate fuel (.step true)) (Solo.init mm io refs)

end

end CatsEffectInLean.Model

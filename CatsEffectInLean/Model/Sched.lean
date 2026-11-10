import CatsEffectInLean.Model.Run

/-!
# Multi-fiber scheduler: task-level schedule replay

Phase 2 steps 6 and 8 (part). The global state is the fiber soup (`Sched.fibers`), the shared
heap (`Heap`: `Ref` cells, `ContState` cells, the ready list), and the task that runs now.

The scheduler mirrors the scripted `ExecutionContext` of the difftest replay mode
(`difftest/src/main/scala/cats/effect/difftest/Runner.scala`, `ScriptedEC` and `replay`), so
that a replay choice list gives the same task order in Lean and in Scala:

* The ready list holds tasks in `ec.execute` order. `IOFiber` enqueues with `scheduleFiber` /
  `rescheduleFiber`, which call `ec.execute(fiber)` for this `ExecutionContext`
  (`FIB:1333-1376`). The model enqueues at the same points: the root at start
  (`IO.scala:1146`), a child in `Start` (`FIB:904`), the fiber itself in `Cede` (`FIB:888`) and
  at auto-yield (`FIB:237`), a resumed fiber in the `IOCont` callback (`FIB:693`), the target
  in the `_cancel` takeover (`FIB:160`), and user callback tasks (`UserEffect.deferCb`).
* One task is one `IOFiber.run()` (`FIB:113-131`): it runs run-loop iterations until the run
  loop returns (end, suspension, `Cede`, auto-yield after `autoYieldThreshold` iterations),
  or one callback task. A replay index counts tasks, so the indices align with Scala.
* A choice `pick n` runs ready task `n mod size`. A choice `cancel t` makes a new fiber that
  runs `fiber(t).cancel` and runs it at once as one task. When the choices run out, the
  scheduler picks index 0 (FIFO).
* The run stops when the root fiber (id 0) has an outcome (checked between tasks), when no task
  is ready ("blocked"), or when the task limit is reached.

Timers (`Sleep`, `FIB:954-981`): `Heap.timers` mirrors the timer list of the virtual-time
`Scheduler` of `Runner.replay`. Time moves only when nothing is ready: then all timers with the
earliest due time move to the ready list in creation order (`Task.timer`), and the clock jumps
to that time. In Scala this happens in the same loop turn as the next pick; here it is a
micro-step of its own (`LogEntry.advance`) that does not count as a task and uses no choice.
Nothing runs between the two, so the task order and the schedule log are the same.

`FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala` at `v3.7.1`.

Differences from the Scala runner (by design):

* `cancel t` names a model fiber id. The Scala runner names a fiber handle (handles count only
  `start`/`racePair` results; root = 0). A translation must map handles to ids.
* The model fuel counts micro-steps (one task start or one run-loop iteration). Out of fuel is
  never a Cats Effect result.
-/

namespace CatsEffectInLean.Model

/-- One replay choice (`difftest/src/main/scala/cats/effect/difftest/Ast.scala`, `Choice`). -/
inductive RChoice where
  /-- `Choice.Pick(i)`: run ready task `i mod size`. -/
  | pick (n : Nat)
  /-- `Choice.CancelFiber(h)`: run `fiber(t).cancel` in a new fiber now. `t` is a fiber id. -/
  | cancel (fiber : Nat)
  deriving DecidableEq, Repr

/-- One entry of the schedule log (the `schedule` array of the difftest output). -/
inductive LogEntry where
  /-- Ready task number `idx` ran. -/
  | pick (idx : Nat) (task : Task)
  /-- External cancel of fiber `target` by the new fiber `canceller`. -/
  | cancel (target : Nat) (canceller : Nat)
  /-- External cancel of a fiber that does not exist: no step (`"skipped":true`). -/
  | cancelSkipped (target : Nat)
  /-- Time moved to `time`; the timers `woken` (ids, creation order) went to the ready list
  (the `{"advance":ms,"woken":[…]}` entry of `Runner.replay`). -/
  | advance (time : Nat) (woken : List Nat)
  deriving DecidableEq, Repr

/-- The global state of the scheduler. -/
structure Sched (M : Type) where
  /-- The shared heap. While a task runs, the live heap is in `cur`. -/
  heap : Heap
  /-- All fibers (index = fiber id). While a task runs, the live table is in `cur`. -/
  fibers : List (Fiber M)
  /-- The run loop of the task that runs now, or `none` between tasks. -/
  cur : Option (Loop M) := none
  /-- Number of tasks run (`steps` of the difftest output). -/
  tasks : Nat := 0
  /-- The schedule log, newest first. -/
  log : List LogEntry := []
  /-- Why the run stopped, or `none` if it can go on. -/
  halt : Option Summary := none
  deriving DecidableEq, Repr

namespace Sched
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- The initial state for root program `io`: `unsafeRunFiber` makes fiber 0 with a callback on
`ExecutionContext` 0 and enqueues it (`IO.scala:1117-1148`). -/
def init (io : IO) (refs : List Val := []) : Sched M :=
  let root := Fiber.new mm 0 .unit 0 io (some .root)
  { heap := { refs := refs, ready := [.fiber 0] }, fibers := [root] }

/-- The live heap. -/
def liveHeap (s : Sched M) : Heap :=
  match s.cur with
  | some l => l.exec.heap
  | none => s.heap

/-- The live fiber table. -/
def liveFibers (s : Sched M) : List (Fiber M) :=
  match s.cur with
  | some l => l.exec.fibers.set l.exec.fib.id l.exec.fib
  | none => s.fibers

/-- The task ends: write the fiber and the world back. -/
def finish (s : Sched M) (x : Exec M) : Sched M :=
  { s with heap := x.heap, fibers := x.fibers.set x.fib.id x.fib, cur := none }

/-- Stop with `h` (the first reason wins). -/
def stop (s : Sched M) (h : Summary) : Sched M :=
  match s.halt with
  | some _ => s
  | none => { s with halt := some h }

/-- Go on after one run-loop iteration or one `run()` entry. -/
def after (s : Sched M) : StepResult M → Sched M
  | .continue l => { s with cur := some l }
  -- the run loop returned: the task ends
  | .yielded x | .suspended x | .done _ x => s.finish x
  | .fatal e x => (s.finish x).stop (.fatal e)
  | .uncaught e x => (s.finish x).stop (.uncaught e)
  | .aborted a x => (s.finish x).stop (.aborted a)

/-- Stop if a step recorded a broken invariant (`Heap.broken`). -/
def checkBroken (s : Sched M) : Sched M :=
  match s.liveHeap.broken with
  | some a => s.stop (.aborted a)
  | none => s

/-- Run task `t` (already removed from the ready list). -/
def runTask (s : Sched M) : Task → Sched M
  | .fiber i =>
    match s.fibers[i]? with
    -- `IOFiber.run()` (FIB:113-131)
    | some f => (s.after (resume cfg mm env { fib := f, heap := s.heap, fibers := s.fibers })).checkBroken
    | none => s.stop (.aborted .badHandle)
  | .cb st r =>
    -- a callback task: `cb(result)` on another thread (FIB:644-755)
    match s.heap.conts[st]? with
    | some c =>
      match s.fibers[c.fiber]? with
      | some f =>
        (s.finish (contCallback mm st r { fib := f, heap := s.heap, fibers := s.fibers })).checkBroken
      | none => s.stop (.aborted .badHandle)
    | none => s.stop (.aborted .badContState)
  | .timer _ st =>
    -- a timer task: `() => cb(RightUnit)` (FIB:972) on the scheduler thread
    match s.heap.conts[st]? with
    | some c =>
      match s.fibers[c.fiber]? with
      | some f =>
        (s.finish (contCallback mm st (.right .unit) { fib := f, heap := s.heap, fibers := s.fibers })).checkBroken
      | none => s.stop (.aborted .badHandle)
    | none => s.stop (.aborted .badContState)

/-- Move time to the earliest due time; the timers due then go to the ready list in creation
order (`Runner.replay`: `timers.map(_._1).min`, `filter`, `now = t`, `ec.execute`). -/
def advance (s : Sched M) : Sched M :=
  match s.heap.timers.map (·.due) |>.min? with
  | none => s
  | some t =>
    let due := s.heap.timers.filter (·.due == t)
    let rest := s.heap.timers.filter (·.due != t)
    { s with heap := { s.heap with timers := rest, clock := t,
                                   ready := s.heap.ready ++ due.map (fun tm => .timer tm.id tm.state) },
             log := .advance t (due.map (·.id)) :: s.log }

/-- One micro-step: one run-loop iteration of the running task, or (between tasks) the start
of the next task. Mirrors the `while` loop of `Runner.replay`. `maxTasks` is `maxSteps`. -/
def tick (maxTasks : Nat) (cs : List RChoice) (s : Sched M) : Sched M × List RChoice :=
  match s.cur with
  | some l =>
    -- one iteration; replay runs one thread, so no cancel write is pending (`observe`)
    ((s.after (step cfg mm env true l)).checkBroken, cs)
  | none =>
    -- `while result.isEmpty && stop.isEmpty`: the root callback ran
    match (s.fibers[0]?).bind (·.outcome) with
    | some oc => (s.stop (.done oc), cs)
    | none =>
      match cs with
      | .cancel t :: rest =>
        if maxTasks ≤ s.tasks then (s.stop .taskLimit, cs)
        else
          match s.fibers[t]? with
          | none => ({ s with log := .cancelSkipped t :: s.log }, rest)
          | some tf =>
            -- `f.cancel.unsafeRunFiber(...)`: `f.cancel` reads `_cancel` now (FIB:197-201);
            -- a new fiber with a callback (`IO.scala:1124-1146`); the runner takes it out of
            -- the ready list and runs it at once
            let cid := s.fibers.length
            let cf := Fiber.new mm cid .unit 0 (IO.cancelOf t tf.outcome) (some .ext)
            let fibers := s.fibers ++ [cf]
            let s := { s with fibers, tasks := s.tasks + 1, log := .cancel t cid :: s.log }
            ((s.after (resume cfg mm env { fib := cf, heap := s.heap, fibers })).checkBroken, rest)
      | _ =>
        if maxTasks ≤ s.tasks then (s.stop .taskLimit, cs)
        else
          match s.heap.ready with
          | [] =>
            -- `ec.ready.isEmpty && timers.isEmpty`: blocked; else time moves (no task, no choice)
            if s.heap.timers.isEmpty then (s.stop .blocked, cs) else (s.advance, cs)
          | rd =>
            -- `Choice.Pick(i)`, or index 0 (FIFO) when the choices ran out
            let (n, rest) := match cs with
              | .pick n :: r => (n, r)
              | _ => (0, [])
            let idx := n % rd.length
            match rd[idx]? with
            | none => (s.stop (.aborted .badSched), rest)
            | some t =>
              let s := { s with heap := { s.heap with ready := rd.eraseIdx idx },
                                tasks := s.tasks + 1, log := .pick idx t :: s.log }
              (s.runTask cfg mm env t, rest)

/-- The summary of a state. A state that can still go on is `outOfFuel`. -/
def summary (s : Sched M) : Summary := s.halt.getD .outOfFuel

end Sched

section
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Run at most `fuel` micro-steps with replay choices `cs`. Structural on `fuel`. -/
def runSchedState (maxTasks : Nat) : (fuel : Nat) → List RChoice → Sched M → Sched M
  | 0, _, s => s
  | fuel + 1, cs, s =>
    match s.halt with
    | some _ => s
    | none =>
      let (s', cs') := s.tick cfg mm env maxTasks cs
      runSchedState maxTasks fuel cs' s'

/-- Run root program `io` with replay choices `cs` and give the summary. The default task
limit is the difftest default `maxSteps = 10000`. -/
def runSched (fuel : Nat) (cs : List RChoice) (io : IO) (refs : List Val := [])
    (maxTasks : Nat := 10000) : Summary :=
  (runSchedState cfg mm env maxTasks fuel cs (Sched.init mm io refs)).summary

end

end CatsEffectInLean.Model

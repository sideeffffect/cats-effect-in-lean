import CatsEffectInLean.Model.Sched

/-!
# Preemptive scheduler: a preemption choice at any run-loop iteration (decisions 29, 36)

An additive variant of the replay scheduler (`CatsEffectInLean/Model/Sched.lean`). It reuses
`Sched.tick` unchanged and adds one more choice, `PChoice.preempt`. The replay scheduler, the
difftest replay mode and `runSchedState` do not change.

## Why

On the JVM, the default `IORuntime` runs fibers on a work-stealing pool with many worker
threads. Two fibers run in parallel, so the steps of one fiber can come between any two
run-loop iterations of the other. The auto-yield (`IOFiber.scala:224-240`: after
`autoYieldThreshold` iterations, `resumeTag = AutoCedeR; resumeIO = _cur0;
rescheduleFiber(ec, this)`) is only a fairness device. Its position (every 1024 iterations, a
runtime setting) is not a Cats Effect promise (decision 29). The replay scheduler models one
thread, where other fibers run only at task boundaries; so it sees iteration counts through
the auto-yield position (`wiki/semantics/outcome-equivalence.md`).

`PChoice.preempt` ends the running task between two iterations and puts the fiber at the end
of the ready list, in the same way as an auto-yield at that point (`Sched.preemptRun`). Then
any ready task can run before the fiber goes on. This gives every interleaving of fibers at
run-loop-iteration granularity, which the multi-threaded runtime allows.

## Choices

The choice list is read at every micro-step (one run-loop iteration, or a task start between
tasks). Each micro-step uses one choice; after the end of the list, the default is `pick 0`.

* `pick n` while a task runs: go on (one iteration). Between tasks: run ready task
  `n mod size` (as `RChoice.pick n`, `Sched.tick`).
* `preempt` while a task runs and the next term is not `EndFiber`: end the task and enqueue the
  fiber (`Sched.preemptRun`). At `EndFiber` (the task ends anyway, maybe suspended on an async
  callback) and between tasks: nothing happens.

The preemptive scheduler has no outside cancel (decision 22) and no task limit (fuel bounds the
run). It keeps no schedule log and no task count (`Sched.norm`): the observation (`Obs`) does
not see them, and without them the state space of a terminating program is finite.
-/

namespace CatsEffectInLean.Model

/-- One choice of the preemptive scheduler. -/
inductive PChoice where
  /-- Between tasks: run ready task `n mod size`. While a task runs: go on. -/
  | pick (n : Nat)
  /-- While a task runs: end the task between two iterations and enqueue the fiber. -/
  | preempt
  deriving DecidableEq, Repr

namespace Sched
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Forget the schedule log and the task count (not observed). -/
def norm (s : Sched M) : Sched M := { s with tasks := 0, log := [] }

/-- Preempt the running task between two iterations. The same effect as the auto-yield of
`IOFiber.scala:233-238` at this point: `resumeTag = AutoCedeR; resumeIO = _cur0;
rescheduleFiber(currentCtx, this); return`. A thread switch is a memory barrier, so a pending
outside cancel becomes visible (`Loop.flush`). No effect at `EndFiber` or between tasks. -/
def preemptRun (s : Sched M) : Sched M :=
  match s.cur with
  | some l =>
    match l.cur with
    | .endFiber => s
    | cur =>
      let l := l.flush
      s.finish ({ l.exec with fib := { l.exec.fib with
        resumeTag := .autoCedeR, resumeIO := some cur } }.enqueue (.fiber l.exec.fib.id))
  | none => s

/-- One micro-step of the preemptive scheduler with choice `c`. `pick n` is `Sched.tick` with
the replay choice `pick (n mod max 1 size)` (the same ready task) and no task limit. -/
def tickP (s : Sched M) : PChoice → Sched M
  | .preempt => s.preemptRun
  | .pick n =>
    (s.tick cfg mm env (s.tasks + 1) [.pick (n % max 1 s.heap.ready.length)]).1.norm

end Sched

section
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Run at most `fuel` micro-steps of the preemptive scheduler with choices `cs` (one choice
per micro-step; `pick 0` after the end of the list). Structural on `fuel`. -/
def runSchedStateP : (fuel : Nat) → List PChoice → Sched M → Sched M
  | 0, _, s => s
  | fuel + 1, cs, s =>
    match s.halt with
    | some _ => s
    | none => runSchedStateP fuel cs.tail (s.tickP cfg mm env (cs.headD (.pick 0)))

/-- The successor states of `s`: one for `preempt` and one for each ready task (at least one:
`pick 0`). Every choice gives one of them (`tickP_mem_succsP`). -/
def succsP (s : Sched M) : List (Sched M) :=
  s.tickP cfg mm env .preempt ::
    (List.range (max 1 s.heap.ready.length)).map (fun i => s.tickP cfg mm env (.pick i))

theorem tickP_mem_succsP (s : Sched M) (c : PChoice) : s.tickP cfg mm env c ∈ succsP cfg mm env s := by
  cases c with
  | preempt => exact List.mem_cons_self
  | pick n =>
    refine List.mem_cons_of_mem _ (List.mem_map.mpr ⟨n % max 1 s.heap.ready.length, ?_, ?_⟩)
    · exact List.mem_range.mpr (Nat.mod_lt _ (by omega))
    · simp only [Sched.tickP, Nat.mod_mod]

theorem runSchedStateP_succ (fuel : Nat) (c : PChoice) (cs : List PChoice) (s : Sched M)
    (h : s.halt = none) :
    runSchedStateP cfg mm env (fuel + 1) (c :: cs) s =
      runSchedStateP cfg mm env fuel cs (s.tickP cfg mm env c) := by
  simp [runSchedStateP, h]

end

end CatsEffectInLean.Model

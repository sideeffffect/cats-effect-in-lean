import CatsEffectInLean.Model.Sched

/-!
# Outcome sets and the law equivalence `Eqv` (Phase 2 step 10, Phase 4 step 2)

The meaning of `lhs <-> rhs` in a law, for `IO` programs of the model.

## Observation

One run of the replay scheduler (`runSchedState`, `CatsEffectInLean/Model/Sched.lean`) ends in a
`Sched` state. Its observation (`Obs`) is:

* `summary`: why the run stopped. This is the root outcome (`Summary.done oc`: succeeded with a
  value, errored, or canceled), or `blocked` (deadlock), `fatal`, `uncaught`, `aborted`.
* `out`: the values that user code emitted (`UserEffect.emit`), newest first. This is the trace
  of the test program: the finalizers that ran, in which order, and the effects of user code.
* `refs`: the final contents of the `Ref` cells. A continuation of the program could read them.
* `reports`: the errors that the runtime reported to the `ExecutionContext`
  (`TraceEv.reportFailure`): an error in a finalizer (`IOFiber.scala:1488`), or an `Errored`
  outcome of a fiber that has no callback (`IOFiber.scala:1099-1101`).

Not observed: the task count, the schedule log, fiber ids, `ContState` ids, handles, and the
outcome callbacks (`TraceEv.outcomeCb`, `TraceEv.cancelerCb`). These are internal names and
counters. Two equal programs can allocate them in a different way.

A run that stops with `outOfFuel` or `taskLimit` gives no observation. These are not Cats Effect
results (`wiki/lean/kernel-evaluation.md`, design rule "Out of fuel").

## Schedules

`outcomes` quantifies over all fuel values and all choice lists of `pick` choices: every
interleaving of the ready tasks of the program. It does not use `RChoice.cancel` (a cancel
by the test harness from outside the program). Reasons:

1. A law `lhs <-> rhs` compares two programs that run alone. The Cats Effect test suite checks
   it with an `Eq[IO[A]]` that runs each side alone under `TestContext` and compares the
   `Outcome` (`eqIOA` and `unsafeRun`,
   `testkit/shared/src/main/scala/cats/effect/testkit/TestInstances.scala:160-161`,
   `TestInstances.scala:199-219`). There is no outside canceller. `Eqv` is stronger: it
   compares sets over all schedules, and it also compares the traces.
2. In replay mode an outside cancel lands only between tasks. A running fiber makes a task
   boundary only at `cede`, at an async suspension, or at auto-yield (every 1024 run-loop
   iterations). So with outside cancels, two programs that differ only in the number of
   run-loop iterations (for example `uncancelable(poll => poll(fa))` and `fa`, two iterations)
   can be told apart by an auto-yield at a different place. No law promises equal iteration
   counts.

Cancelation is still observed: self-cancelation (`canceled`), the cancel of one fiber by
another fiber of the program, the finalizers, and their trace. `outcomesExt` and `EqvExt`
(below) also allow outside cancels at every task boundary.

User code is a parameter (`env`). It can build any `IO` term. So it can also call `cancel` on a
fiber id that the program did not receive from `start` (for example the root, id 0). Scala user
code cannot do this. Statements about `outcomes` hold for these programs too.
-/

namespace CatsEffectInLean.Model

/-- The observation of one finished run. See the module doc. -/
structure Obs where
  /-- Why the run stopped: the root outcome, or `blocked`, `fatal`, `uncaught`, `aborted`. -/
  summary : Summary
  /-- `Heap.out`: values that user code emitted, newest first. -/
  out : List Val
  /-- `Heap.refs`: the final `Ref` cells. -/
  refs : List Val
  /-- The errors in `TraceEv.reportFailure` events, newest first. -/
  reports : List Err
  deriving DecidableEq, Repr

/-- `false` for the summaries that are not Cats Effect results (`outOfFuel`, `taskLimit`). -/
def Summary.isResult : Summary → Bool
  | .outOfFuel | .taskLimit => false
  | _ => true

/-- The errors that the runtime reported, newest first. -/
def reportsOf (tr : List TraceEv) : List Err :=
  tr.filterMap fun
    | .reportFailure e => some e
    | _ => none

/-- The observation of a scheduler state: `none` if the run can go on, or if it stopped with
`outOfFuel` or `taskLimit`. -/
def Sched.obs {M : Type} (s : Sched M) : Option Obs :=
  match s.halt with
  | some h =>
    if h.isResult then
      some { summary := h, out := s.liveHeap.out, refs := s.liveHeap.refs,
             reports := reportsOf s.liveHeap.trace }
    else none
  | none => none

/-- `true` for a `pick` choice. -/
def RChoice.isPick : RChoice → Bool
  | .pick _ => true
  | .cancel _ => false

section
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Run root program `io` for `fuel` micro-steps with replay choices `cs` and give the
observation. The task limit is `fuel`: a task start is one micro-step, so the task limit never
stops the run first. -/
def runObs (fuel : Nat) (cs : List RChoice) (io : IO) : Option Obs :=
  (runSchedState cfg mm env fuel fuel cs (Sched.init mm io)).obs

/-- The outcome set of `io` over all schedules: `o` is in it if some fuel and some list of
`pick` choices give observation `o`. Unbounded: no limit on the fuel or on the list length. -/
def outcomes (io : IO) (o : Obs) : Prop :=
  ∃ (fuel : Nat) (cs : List RChoice), (∀ c ∈ cs, c.isPick = true) ∧ runObs cfg mm env fuel cs io = some o

/-- The same with outside cancels: any choice list, also `RChoice.cancel`. -/
def outcomesExt (io : IO) (o : Obs) : Prop :=
  ∃ (fuel : Nat) (cs : List RChoice), runObs cfg mm env fuel cs io = some o

/-- The law equivalence `<->` for `IO`: the two programs have the same outcome set. -/
def Eqv (p q : IO) : Prop :=
  ∀ o, outcomes cfg mm env p o ↔ outcomes cfg mm env q o

/-- `Eqv` with outside cancels (`outcomesExt`). -/
def EqvExt (p q : IO) : Prop :=
  ∀ o, outcomesExt cfg mm env p o ↔ outcomesExt cfg mm env q o

theorem Eqv.refl (p : IO) : Eqv cfg mm env p p := fun _ => Iff.rfl

theorem Eqv.symm {p q : IO} (h : Eqv cfg mm env p q) : Eqv cfg mm env q p :=
  fun o => (h o).symm

theorem Eqv.trans {p q r : IO} (h₁ : Eqv cfg mm env p q) (h₂ : Eqv cfg mm env q r) :
    Eqv cfg mm env p r :=
  fun o => (h₁ o).trans (h₂ o)

/-- A pick-only schedule is also an `outcomesExt` schedule. -/
theorem outcomes_sub_ext {io : IO} {o : Obs} (h : outcomes cfg mm env io o) :
    outcomesExt cfg mm env io o :=
  let ⟨fuel, cs, _, h⟩ := h
  ⟨fuel, cs, h⟩

end

end CatsEffectInLean.Model

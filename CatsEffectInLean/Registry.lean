import CatsEffectInLean.Props.IO.MonadCancelLaws
import CatsEffectInLean.Proofs.IO.MonadCancelLaws
import CatsEffectInLean.Props.Calibration.SyncStep
import CatsEffectInLean.Proofs.Calibration.SyncStep
import CatsEffectInLean.Props.Calibration.ResourceEval
import CatsEffectInLean.Proofs.Calibration.ResourceEval
import CatsEffectInLean.Props.Calibration.QueueTimeout
import CatsEffectInLean.Proofs.Calibration.QueueTimeout

/-!
# Property registry

One `Entry` for each registered property. The audit (`lake exe audit`, see
`tools/Audit/Core.lean` and `wiki/methodology/registry-and-audit.md`) checks
each entry mechanically:

- `prop` is a definition of type `Prop` in a `CatsEffectInLean.Props.*` module;
- for `proven`, the type of `thm` is exactly `prop` (the constant, not its unfolding);
- for `refuted`, the type of `thm` is exactly `¬ prop`, and `bug` names an existing file;
- `prop` and `thm` use only the axioms `propext`, `Classical.choice`, `Quot.sound`;
- each row in `rows` is an id in `inventory/inventory.csv`, and each `modelled`
  row there names an entry that lists it;
- a `modelled` row names at least one `proven` or `refuted` entry (decision 28). An
  `open` entry lists its rows, but they stay `todo`.

Write names with double backticks (``` ``CatsEffectInLean.Props.foo ```).
Lean then rejects a name that does not exist when this file compiles.
Import the `Props` and `Proofs` modules that the entries name.
-/

namespace CatsEffectInLean

/-- Settlement status of a registered property. -/
inductive Status where
  /-- Stated, not yet proven or refuted. `thm` must be `none`. -/
  | «open»
  /-- `thm : prop`. -/
  | proven
  /-- `thm : ¬ prop`, with a bug record. -/
  | refuted
  deriving Repr, DecidableEq, Inhabited

/-- One registered property. -/
structure Entry where
  /-- Unique id, for example `kernel.MonadCancel.uncancelable.pollIsIdentity`. -/
  id : String
  /-- Inventory row ids (column `id` of `inventory/inventory.csv`) that this entry covers. -/
  rows : List String
  /-- Name of the property definition (`def foo : Prop := ...`). -/
  prop : Lean.Name
  status : Status
  /-- Name of the theorem. Required for `proven` and `refuted`; `none` for `open`. -/
  thm : Option Lean.Name := none
  /-- Path of the bug record (`bugs/<id>.yaml`) from the repository root. Required for `refuted`. -/
  bug : Option String := none
  /-- Free text, for example why an `open` entry is hard. -/
  note : String := ""
  deriving Repr, Inhabited

/-- The registry. One entry per (law, instance) (decision 16). -/
def registry : List Entry := [
  { id := "laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO"
    rows := ["laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap"]
    prop := ``Props.IO.MonadCancelLaws.canceledAssociatesLeftOverFlatMap
    status := .proven
    thm := ``Proofs.IO.MonadCancelLaws.canceledAssociatesLeftOverFlatMap_proven
    note := "IO, EqvP (all schedules, preemption at any run-loop iteration); fa never runs \
      (both sides: Canceled, empty trace; state families of 13 and 8 states)" },
  { id := "laws.MonadCancelLaws.forceRCanceledShortCircuits.IO"
    rows := ["laws.MonadCancelLaws.forceRCanceledShortCircuits"]
    prop := ``Props.IO.MonadCancelLaws.forceRCanceledShortCircuits
    status := .proven
    thm := ``Proofs.IO.MonadCancelLaws.forceRCanceledShortCircuits_proven
    note := "IO, EqvP; forceR = handleError(_ => ()).productR (IO.scala:452-454); fa never runs \
      (state family of 19 states)" },
  { id := "laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO"
    rows := ["laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary"]
    prop := ``Props.IO.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary
    status := .«open»
    note := "Believed true: the NB comment (L/MonadCancelLaws.scala:47-60) is about the monad laws, \
      not this law. Bounded smoke tests (11 fa, picks and outside cancels) agree. Proof needs a \
      simulation: the two states differ only in the order of OnCancelK and UncancelableK, which \
      the succeeded/failed chain pops with no run-loop iteration in between." },
  { id := "laws.MonadCancelLaws.uncancelablePollIsIdentity.IO"
    rows := ["laws.MonadCancelLaws.uncancelablePollIsIdentity"]
    prop := ``Props.IO.MonadCancelLaws.uncancelablePollIsIdentity
    status := .«open»
    note := "Open, statement now with EqvP (decision 36). The replay-Eqv difference for \
      fa = start(emit 9) >> emit 1 >> n flatMaps >> emit 2 (n = 509 at default thresholds) is gone: \
      the right side reaches trace [1, 9, 2] with one preemption (EnumPExamples.default_rhs_preempt); \
      with thresholds 2/4 the exact EqvP sets agree for n = 0..9 (kernel: n = 0..3). A proof for all \
      fa needs a simulation between the runs (extra Uncancelable/UnmaskRunLoop pair); not done." },
  { id := "core.IO.syncStep.syncStepIdentitySyncIO"
    rows := ["core.IO.syncStep#2", "core.IO.IOAsync.syncStep", "core.SyncStep.MaxSteps",
      "core.SyncStep.interpret#2", "core.SyncIO.unsafeRunSync"]
    prop := ``Props.Calibration.syncStepIdentitySyncIO
    status := .refuted
    thm := some ``Proofs.Calibration.syncStepIdentitySyncIO_refuted
    bug := some "bugs/CE-0001.yaml"
    note := "AsyncLaws.syncStepIdentity for IO#syncStep with G = SyncIO, single-fiber driver, \
      step-only schedules (no external cancel, decision 26), WellFormed fa/env; counterexample = \
      case 4 of reproducers/CE-0001 (IO.uncancelable(_ => IO.canceled *> flag.set(true))). \
      Rows: only those the witness exercises; the SyncIO run-loop rows went back to todo." },
  { id := "kernel.Resource.eval.preservesUncancelable"
    rows := ["kernel.Resource.eval", "kernel.Resource.allocatedCase", "kernel.Resource.pure"]
    prop := ``Props.Calibration.resourceEvalPreservesUncancelable
    status := .refuted
    thm := some ``Proofs.Calibration.resourceEvalPreservesUncancelable_refuted
    bug := some "bugs/CE-0002.yaml"
    note := "Scaladoc Resource.scala:986-987 'Preserves interruptibility of fa': for \
      fa = IO.uncancelable(_ => g), Resource.eval(fa).allocatedCase <-> \
      IO.uncancelable(_ => Resource.eval(fa).allocatedCase) (EqvP: all schedules with a \
      preemption at any run-loop iteration, F = IO). Counterexample g = IO.canceled: exact \
      outcome sets {Canceled} vs {Succeeded} = case C of reproducers/CE-0002. Fixed twin \
      (PR #4630, allocatedCaseFixed) satisfies the equation for a family of g, also with \
      child fibers (decision 39)." },
  { id := "std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement"
    rows := ["std.Queue.unbounded", "std.Queue.UnboundedAsyncQueue.unsafeOffer",
      "std.Queue.UnboundedAsyncQueue.offer", "std.Queue.UnboundedAsyncQueue.take",
      "std.Queue.UnboundedAsyncQueue.tryTake", "std.UnsafeUnbounded.put",
      "std.UnsafeUnbounded.take", "std.UnsafeUnbounded.Cell.apply",
      "core.IO.timeout", "core.IO.timeoutTo", "core.IO.racePair",
      "core.IOFiber.runLoop.RacePair", "core.IO.asyncCheckAttempt"]
    prop := ``Props.Calibration.QueueTimeout.takeTimeoutNoLostElement
    status := .refuted
    thm := some ``Proofs.Calibration.QueueTimeout.takeTimeoutNoLostElement_refuted
    bug := some "bugs/CE-0003.yaml"
    note := "No lost element for program A of reproducers/CE-0003 (offer xs; take.timeout(d) in a \
      started fiber; cancel it; join; drain), all xs, d, s and pick schedules. Counterexample: \
      xs = [42], d = 1000, s = 1, FIFO schedule: the take racer completes Succeeded(42) after \
      the consumer is canceled; the racePair finalizer drops the outcome." }
]

end CatsEffectInLean

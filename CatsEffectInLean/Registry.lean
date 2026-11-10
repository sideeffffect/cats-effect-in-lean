import CatsEffectInLean.Props.IO.MonadCancelLaws
import CatsEffectInLean.Proofs.IO.MonadCancelLaws
import CatsEffectInLean.Props.Calibration.SyncStep
import CatsEffectInLean.Proofs.Calibration.SyncStep
import CatsEffectInLean.Props.Calibration.ResourceEval
import CatsEffectInLean.Proofs.Calibration.ResourceEval
import CatsEffectInLean.Props.Calibration.QueueTimeout
import CatsEffectInLean.Proofs.Calibration.QueueTimeout
import CatsEffectInLean.Props.Calibration.FatalRaise
import CatsEffectInLean.Proofs.Calibration.FatalRaise
import CatsEffectInLean.Props.Phase6.Bracket
import CatsEffectInLean.Proofs.Phase6.BracketFullTwin

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
      step-only schedules (no external cancel, decision 26), WellFormed fa/env with opaque polls \
      (decision 37), non-fatal errors only (NonFatalOnly, decision 38; fatal errors are CE-0004), \
      observations up to Poll identity (eraseObs); counterexample = \
      case 4 of reproducers/CE-0001 (IO.uncancelable(_ => IO.canceled *> flag.set(true))). \
      Rows: only those the witness exercises; the SyncIO run-loop rows went back to todo. \
      Fixed twin (decision 39): Model/SyncStepFixed.lean mirrors upstream PR #4700; it satisfies \
      the statement on 10 bounded programs (Proofs.Calibration.SyncStepTwin.fixed_twin), v3.7.1 \
      fails 5 of them (v371_fails)." },
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
      "core.IO.timeout", "core.IO.racePair",
      "core.IOFiber.runLoop.RacePair", "core.IO.asyncCheckAttempt"]
    prop := ``Props.Calibration.QueueTimeout.takeTimeoutNoLostElement
    status := .refuted
    thm := some ``Proofs.Calibration.QueueTimeout.takeTimeoutNoLostElement_refuted
    bug := some "bugs/CE-0003.yaml"
    note := "No lost element for program A of reproducers/CE-0003 (offer xs; take.timeout(d) in a \
      started fiber; cancel it; join; drain), all xs, d, s and pick schedules. Counterexample: \
      xs = [42], d = 1000, s = 1, FIFO schedule: the take racer completes Succeeded(42) after \
      the consumer is canceled; the racePair finalizer drops the outcome. Row core.IO.timeoutTo \
      is not listed: the model mirrors timeoutTo only with the TimeoutException fallback of \
      IO#timeout (review batch 2), so the row stays todo." },
  { id := "core.SyncIO.runLoop.Error.fatalTwin"
    rows := ["core.IOFiber.runLoop.Error", "core.SyncIO.runLoop.Error"]
    prop := ``Props.Calibration.raiseErrorTwin
    status := .refuted
    thm := some ``Proofs.Calibration.FatalRaise.raiseErrorTwin_refuted
    bug := some "bugs/CE-0004.yaml"
    note := "For every error e, IO.raiseError(e).handleErrorWith(_ => IO.pure(1)) (limit \
      Int.MaxValue) has the same observations directly (IO run loop) and through syncStep \
      (SyncIO run loop), over all step-only schedules. Counterexample: fatal e. Direct: fatal \
      (IOFiber.scala:265-269 onFatalFailure); stepped: Succeeded(1) (SyncIO.scala:257-259 has \
      no check). Fixed twin (SyncIOEnv.fixFatalRaise) holds on the bounded domain (fixed_twin); \
      v3.7.1 holds on its non-fatal members (v371_nonFatal)." },
  { id := "core.SyncIO.runLoop.Error.fatalTwin.nonFatal"
    rows := ["core.IOFiber.runLoop.Error", "core.SyncIO.runLoop.Error"]
    prop := ``Props.Calibration.raiseErrorTwinNonFatal
    status := .«open»
    note := "Ordinary inputs of CE-0004 (AGENTS.md section 6). Proven only for the bounded \
      domain e in {nonFatal 0, interrupted 0} (Proofs.Calibration.FatalRaise.v371_nonFatal). \
      A proof for all codes needs a lemma that runs do not depend on the error code (decide \
      cannot check a free code)." },
  -- Phase 6, track G (guarantee, bracket*)
  { id := "core.IO.bracketFull.kernelDefaultTwin"
    rows := ["core.IO.bracketFull", "core.IO.IOAsync.bracketFull", "kernel.MonadCancel.bracketFull"]
    prop := ``Props.Phase6.Bracket.bracketFullIsKernelDefault
    status := .refuted
    thm := some ``Proofs.Phase6.bracketFullIsKernelDefault_refuted
    bug := some "bugs/CE-0005.yaml"
    note := "Twin: IO.bracketFull (IO.scala:1826-1830) <-> kernel MonadCancel#bracketFull body \
      (K/MonadCancel.scala:447-456) with the IO operations, EqvP, all user functions. \
      Counterexample: acquire = IO.canceled, use throws E5: IO {Errored(E5)} (use(a) is called \
      inside IO.defer before poll unmasks) vs kernel {Canceled}. Reproducer cases A/B (parent \
      cancel). Fixed twin poll(IO.defer(use(a))) agrees with the kernel body on 8 programs \
      (Proofs/Phase6/BracketFullFixed.lean)." },
  { id := "core.IO.bracketFull.kernelDefaultTwin.pureUse"
    rows := ["core.IO.bracketFull", "core.IO.IOAsync.bracketFull", "kernel.MonadCancel.bracketFull"]
    prop := ``Props.Phase6.Bracket.bracketFullIsKernelDefaultPureUse
    status := .«open»
    note := "Ordinary inputs of CE-0005: use is pure (no effect, no throw when called). \
      Smoke-tested (Proofs/Phase6/BracketSmoke.lean, twin_pure_*). A proof for all programs needs \
      a simulation between the two runs: same states up to the closure ids of the two bodies and \
      one extra run-loop iteration, preserved by Sched.tickP over all of Step.lean." },
  { id := "laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO"
    rows := ["laws.MonadCancelLaws.guaranteeIsGuaranteeCase", "core.IO.guarantee", "core.IO.guaranteeCase",
      "core.IO.IOAsync.guarantee", "core.IO.IOAsync.guaranteeCase"]
    prop := ``Props.Phase6.Bracket.guaranteeIsGuaranteeCase
    status := .«open»
    note := "Law L/MonadCancelLaws.scala:28-29 at IO: IO#guarantee (IO.scala:496-501) vs \
      IO#guaranteeCase(_ => fin) (IO.scala:523-530), EqvP, all fa, fin. Believed true: same \
      structure, both report finalizer errors in the error case. Smoke-tested on 14 pairs \
      (law_*); a guarantee that never runs fin breaks it (law_wrongFunction). Open: needs a \
      simulation proof over Step/SchedP for arbitrary fa (closure ids differ, extra user call)." },
  { id := "core.IO.bracket.releaseOnce"
    rows := ["core.IO.bracket", "core.IO.bracketCase", "core.IO.bracketFull", "kernel.MonadCancel.bracket"]
    prop := ``Props.Phase6.Bracket.bracketReleaseOnce
    status := .«open»
    note := "Invariant (decision 50): bracket in a child fiber that the parent cancels at any \
      point and joins; release runs exactly once iff acquire completed, every use outcome, all \
      schedules. Smoke-tested (rel_*; rel_wrongFunction). Open: a universal proof needs an \
      invariant on scheduler states (the onCancel release is on the finalizer stack iff the \
      acquire marker was emitted and the release marker not)." },
  { id := "core.IO.guarantee.finalizerOnce"
    rows := ["core.IO.guarantee", "kernel.MonadCancel.guarantee"]
    prop := ``Props.Phase6.Bracket.guaranteeFinalizerOnce
    status := .«open»
    note := "Invariant: guarantee in a child fiber that the parent cancels and joins; the \
      finalizer runs at most once, and it runs if fa started. Smoke-tested (fin_*). Open: same \
      missing state invariant as core.IO.bracket.releaseOnce." }
]

end CatsEffectInLean

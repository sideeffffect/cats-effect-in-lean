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
import CatsEffectInLean.Props.Phase6.Race
import CatsEffectInLean.Props.Phase6.Bracket
import CatsEffectInLean.Proofs.Phase6.BracketFullTwin
import CatsEffectInLean.Props.Phase6.Memoize
import CatsEffectInLean.Proofs.Phase6.MemoizeStuck
import CatsEffectInLean.Props.Phase6.Resource
import CatsEffectInLean.Proofs.Phase6.ResourceBoth
import CatsEffectInLean.Props.Phase6.ParTraverse
import CatsEffectInLean.Props.Phase7.CountDownLatch
import CatsEffectInLean.Props.Phase7.CyclicBarrier

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
      is not listed: this property uses only IO#timeout (TimeoutException fallback). Since \
      Phase 6 track D, Model/Timeout.lean mirrors timeoutTo with any fallback (timeoutToIO), \
      but no settled entry names core.IO.timeoutTo yet, so the row stays todo." },
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
  -- Phase 6, track R (race, both, raceOutcome, bothOutcome, timeout; Props/Phase6/Race.lean)
  { id := "core.IO.race.combNoLeak"
    rows := ["core.IO.race", "core.IO.race#2", "core.IO.raceOutcome", "core.IO.both", "core.IO.both#2",
      "core.IO.bothOutcome", "core.IO.bothOutcome#2", "kernel.GenSpawn.race",
      "kernel.GenSpawn.raceOutcome", "kernel.GenSpawn.both", "kernel.GenSpawn.bothOutcome"]
    prop := ``Props.Phase6.Race.combNoLeak
    status := .«open»
    note := "No leaked fiber: for the four kernel defaults (IO dispatches to them, no own body), \
      all WellFormed sides, all user code and all PChoice schedules, when the root (the \
      combinator) completes, its racePair has no live child (Model/Leak.lean). Smoke: \
      lake exe leaksmoke (140,400 random runs, 0 violations; wrong function 'race without \
      cancel' leaks), spikes/race-leak/LeakSmoke.scala on CE 3.7.1 (7,038 completed runs, 0 \
      violations). Open: needs an invariant over Step/SchedP that a racing fiber passes its \
      combinator only after both children are done; exact search does not scale (>10^4 states). Track P (2026-11-10): not settled. Proven so far: F1/F1b/F2 frame lemmas for all runs \
      (Proofs/Lemmas/Frame.lean: owner_stable, result_stable). Gap: runtime grammar S, slot-0 \
      discipline F3, outcome stability F4 with the takeover/join protocols P1/P2, handle secrecy H, \
      and the control invariant C(r) of the racing fiber (raw/cats-effect/2026-11-10-race-invariant-track-p-notes.md). Decision 58 (review 9 R1 survey, track G): the side codes are odd references src0/src1, not \
      data numbers; user code cannot re-run fa/fb by name (RaceWitness.forged_race_sources). A \
      re-run broke no claim before (more user code; the claims are about the root's racePair)." },
  { id := "core.IO.race.combCanceledNoLeak"
    rows := ["core.IO.race", "core.IO.race#2", "core.IO.raceOutcome", "core.IO.both", "core.IO.both#2",
      "core.IO.bothOutcome", "core.IO.bothOutcome#2", "kernel.GenSpawn.race",
      "kernel.GenSpawn.raceOutcome", "kernel.GenSpawn.both", "kernel.GenSpawn.bothOutcome"]
    prop := ``Props.Phase6.Race.combCanceledNoLeak
    status := .«open»
    note := "Decision 50 form of combNoLeak: a parent starts the combinator, cancels it and joins \
      it; at root completion fiber 1 has no live race child. Same smoke evidence; open for the \
      same reason. Track P (2026-11-10): not settled. Proven so far: F1/F1b/F2 frame lemmas for all runs \
      (Proofs/Lemmas/Frame.lean: owner_stable, result_stable). Gap: runtime grammar S, slot-0 \
      discipline F3, outcome stability F4 with the takeover/join protocols P1/P2, handle secrecy H, \
      and the control invariant C(r) of the racing fiber (raw/cats-effect/2026-11-10-race-invariant-track-p-notes.md). Decision 58 (review 9 R1 survey, track G): the side codes are odd references src0/src1, not \
      data numbers; user code cannot re-run fa/fb by name (RaceWitness.forged_race_sources). A \
      re-run broke no claim before (more user code; the claims are about the root's racePair)." },
  { id := "core.IO.timeout.noLeak"
    rows := ["core.IO.timeout"]
    prop := ``Props.Phase6.Race.timeoutNoLeak
    status := .«open»
    note := "fa.timeout(d), direct and canceled by a parent (decision 50): at root completion the \
      timeout's racePair (source and sleep) has no live child. Smoke as combNoLeak; open. Track P (2026-11-10): not settled. Proven so far: F1/F1b/F2 frame lemmas for all runs \
      (Proofs/Lemmas/Frame.lean: owner_stable, result_stable). Gap: runtime grammar S, slot-0 \
      discipline F3, outcome stability F4 with the takeover/join protocols P1/P2, handle secrecy H, \
      and the control invariant C(r) of the racing fiber (raw/cats-effect/2026-11-10-race-invariant-track-p-notes.md). Decision 58 (review 9 R1 survey, track G): the side codes are odd references src0/src1, not \
      data numbers; user code cannot re-run fa/fb by name (RaceWitness.forged_race_sources). A \
      re-run broke no claim before (more user code; the claims are about the root's racePair)." },
  { id := "core.IO.raceOutcome.isWinnerOutcome"
    rows := ["core.IO.raceOutcome", "kernel.GenSpawn.raceOutcome"]
    prop := ``Props.Phase6.Race.raceOutcomeIsWinnerOutcome
    status := .«open»
    note := "raceOutcome returns Left(oc) only if fiber 1 (fa) ended with oc, Right(oc) only if \
      fiber 2 (fb) did. Smoke: leaksmoke (0 violations). Open: same invariant argument (needs H, \
      F4 and the first-write rule of the race ContState). Track P (2026-11-10): not settled. Proven so far: F1/F1b/F2 frame lemmas for all runs \
      (Proofs/Lemmas/Frame.lean: owner_stable, result_stable). Gap: runtime grammar S, slot-0 \
      discipline F3, outcome stability F4 with the takeover/join protocols P1/P2, handle secrecy H, \
      and the control invariant C(r) of the racing fiber (raw/cats-effect/2026-11-10-race-invariant-track-p-notes.md). Decision 58 (review 9 R1 survey, track G): the side codes are odd references src0/src1, not \
      data numbers; user code cannot re-run fa/fb by name (RaceWitness.forged_race_sources). A \
      re-run broke no claim before (more user code; the claims are about the root's racePair)." },
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
      one extra run-loop iteration, preserved by Sched.tickP over all of Step.lean. \
      Satisfiable (decision 53): Proofs.Phase6.BracketWitness.bracketFullIsKernelDefaultPureUse_satisfiable." },
  { id := "laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO"
    rows := ["laws.MonadCancelLaws.guaranteeIsGuaranteeCase", "core.IO.guarantee", "core.IO.guaranteeCase",
      "core.IO.IOAsync.guarantee", "core.IO.IOAsync.guaranteeCase"]
    prop := ``Props.Phase6.Bracket.guaranteeIsGuaranteeCase
    status := .«open»
    note := "Law L/MonadCancelLaws.scala:28-29 at IO: IO#guarantee (IO.scala:496-501) vs \
      IO#guaranteeCase(_ => fin) (IO.scala:523-530), EqvP, all fa, fin. Believed true: same \
      structure, both report finalizer errors in the error case. Smoke-tested on 14 pairs \
      (law_*); a guarantee that never runs fin breaks it (law_wrongFunction). Open: needs a \
      simulation proof over Step/SchedP for arbitrary fa (closure ids differ, extra user call). \
      Satisfiable (decision 53): Proofs.Phase6.BracketWitness.guaranteeIsGuaranteeCase_satisfiable." },
  { id := "core.IO.bracket.releaseOnce"
    rows := ["core.IO.bracket", "core.IO.bracketCase", "core.IO.bracketFull", "kernel.MonadCancel.bracket"]
    prop := ``Props.Phase6.Bracket.bracketReleaseOnce
    status := .«open»
    note := "Invariant (decision 50): bracket in a child fiber that the parent cancels at any \
      point and joins; release runs exactly once iff acquire completed, every use outcome, all \
      schedules. Restated after review batch 4 (decisions 53, 54): the first form had a marker \
      hypothesis (MarkersOnly) that never held with the others, so it was vacuous. Now the test \
      program is a harness (henv, HLam) with counter cells that only the harness holds; user \
      code u and acquire a0 are arbitrary WellFormed code; hypotheses: use, rel even and \
      WellFormed a0. This fixes the statement, it does not weaken it: it quantifies over the \
      same user code and schedules, and a broken bracket breaks it. Satisfiable: \
      Proofs.Phase6.BracketWitness.bracketReleaseOnce_satisfiable (acquire done, release run, \
      child canceled). Smoke by #guard with the hypotheses checked \
      (test/Phase6/BracketSmokeParent.lean: 18 inputs; a bracket without release breaks it). \
      Open: a universal proof needs an invariant on scheduler states (the onCancel release is on \
      the finalizer stack iff counter 0 > counter 1). Decision 58: closure references are Val.fn; WellFormed holds user code to the available \
      handles (WF.avail), so the batch 6 leaf forgery and the batch 8 F1 source forgery are \
      rejected (Proofs/Phase6/PrivacyExamples.lean). Construction: the counters are the first \
      cells of the run, never given to user code; events capture them." },
  { id := "core.IO.guarantee.finalizerOnce"
    rows := ["core.IO.guarantee"]
    prop := ``Props.Phase6.Bracket.guaranteeFinalizerOnce
    status := .«open»
    note := "Invariant: IO#guarantee in a child fiber that the parent cancels and joins; the \
      finalizer runs at most once, and it runs if fa started. Restated after review batch 4 \
      like core.IO.bracket.releaseOnce (harness markers, decisions 53, 54); row \
      kernel.MonadCancel.guarantee removed (not mirrored here). Satisfiable: \
      Proofs.Phase6.BracketWitness.guaranteeFinalizerOnce_satisfiable. Smoke by #guard with the \
      hypotheses checked (12 inputs; a guarantee without finalizer breaks it). Open: same \
      missing state invariant as core.IO.bracket.releaseOnce. Decision 58: closure references are Val.fn; WellFormed holds user code to the available \
      handles (WF.avail), so the batch 6 leaf forgery and the batch 8 F1 source forgery are \
      rejected (Proofs/Phase6/PrivacyExamples.lean). Construction: the counters are the first \
      cells of the run, never given to user code; events capture them." },
  -- Phase 6, track M (memoize)
  { id := "core.IO.memoize.noStuckGet"
    rows := ["core.IO.memoize", "kernel.GenConcurrent.memoize"]
    prop := ``Props.Phase6.Memoize.memoizeNoStuckGet
    status := .refuted
    thm := some ``Proofs.Phase6.memoizeNoStuckGet_refuted
    bug := some "bugs/CE-0030.yaml"
    note := "IO#memoize = kernel GenConcurrent#memoize with IOAsync (no IO twin). Two get fibers, \
      all WellFormed fa, all PChoice schedules: a blocked run never has a Finished memo. \
      Counterexample: fa = IO.canceled, one preemption of the second get between state.get and \
      state.flatModifyFull; flatModifyFull returns canceled *> never without poll (masked), so \
      the get waits forever (K/GenConcurrent.scala:91-92). Fixed twin poll(fromEither(..).flatten) \
      completes on all one-preemption schedules < 120 for 7 fa (canceled, pure, raiseError, \
      emit >> canceled, start(emit) >> canceled, cede >> canceled with a 2-preemption grid, \
      uncancelable(_ => canceled)); v3.7.1 is stuck exactly for the self-canceling fa \
      (Proofs/Phase6/MemoizeFixed.lean). Hypothesis satisfiable: MemoizeStuck.fa_wf; observed \
      memo cell not forgeable (Proofs/Phase6/MemoizeSat.lean, decision 54). Decision 58 (review 9 R1 survey, track G): fa's code is the odd reference faSrc, not the \
      number 0, and the test closures (constFa) are not public, so user code cannot name fa \
      (MemoizeSat.forged_source, forged_constFa). It can still run fa again through its own \
      cell k: srcIO fa (.ref k) is k.update(_ + 1) *> fa, and the Memoize/Timeout closures with \
      a source field are public (review 10, D1). Scala can do the same by recursion (def fa = \
      IO.ref(0).flatMap(r => (r.update(_ + 1) *> fa).timeout(..))), so this is ordinary user \
      code, not a forgery. No claim breaks: the counter of atMostOnce is cell 0, allocated \
      first, never given to user code, so a user cell k is never cell 0; noStuckGet and \
      getsAgree are about the tested memo cell and the two get fibers." },
  { id := "core.IO.memoize.getsAgree"
    rows := ["core.IO.memoize", "kernel.GenConcurrent.memoize"]
    prop := ``Props.Phase6.Memoize.memoizeGetsAgree
    status := .«open»
    note := "Two concurrent gets observe the same outcome when the root completes (all \
      WellFormed fa, all PChoice schedules). Smoke: 9 fa x 400 random schedules, 0 violations; a \
      memoize without cache breaks it (test/Phase6/MemoizeSmoke.lean). Satisfiability witness \
      (decision 53): MemoizeSat.getsAgree_sat (fa = IO.cede: a get subscribes during the \
      evaluation, root completes with a pair). Open: a proof for all fa \
      needs a state invariant over SchedP (memo cell, deferred cell, go fiber outcome). Decision 58 (review 9 R1 survey, track G): fa's code is the odd reference faSrc, not the \
      number 0, and the test closures (constFa) are not public, so user code cannot name fa \
      (MemoizeSat.forged_source, forged_constFa). It can still run fa again through its own \
      cell k: srcIO fa (.ref k) is k.update(_ + 1) *> fa, and the Memoize/Timeout closures with \
      a source field are public (review 10, D1). Scala can do the same by recursion (def fa = \
      IO.ref(0).flatMap(r => (r.update(_ + 1) *> fa).timeout(..))), so this is ordinary user \
      code, not a forgery. No claim breaks: the counter of atMostOnce is cell 0, allocated \
      first, never given to user code, so a user cell k is never cell 0; noStuckGet and \
      getsAgree are about the tested memo cell and the two get fibers." },
  { id := "core.IO.memoize.atMostOnce"
    rows := ["core.IO.memoize", "kernel.GenConcurrent.memoize"]
    prop := ``Props.Phase6.Memoize.memoizeAtMostOnce
    status := .«open»
    note := "Without a cancel from the program, fa starts at most once (counter <= 1 in every \
      reachable state of countedTwoGets). Smoke: 9 fa x 400 random schedules, max 1; a memoize \
      without cache gives 2 (test/Phase6/MemoizeSmoke.lean). Satisfiability witness: \
      MemoizeSat.atMostOnce_sat (counter 1, a get during the evaluation). Counter and memo cell \
      not forgeable (MemoizeSat.forged_*). Open: same missing invariant as \
      core.IO.memoize.getsAgree (at most one Evaluating transition while no get is canceled). Decision 58 (review 9 R1 survey, track G): fa's code is the odd reference faSrc, not the \
      number 0, and the test closures (constFa) are not public, so user code cannot name fa \
      (MemoizeSat.forged_source, forged_constFa). It can still run fa again through its own \
      cell k: srcIO fa (.ref k) is k.update(_ + 1) *> fa, and the Memoize/Timeout closures with \
      a source field are public (review 10, D1). Scala can do the same by recursion (def fa = \
      IO.ref(0).flatMap(r => (r.update(_ + 1) *> fa).timeout(..))), so this is ordinary user \
      code, not a forgery. No claim breaks: the counter of atMostOnce is cell 0, allocated \
      first, never given to user code, so a user cell k is never cell 0; noStuckGet and \
      getsAgree are about the tested memo cell and the two get fibers." },
  -- Phase 6, track Res (Resource use/allocated/both)
  { id := "kernel.Resource.both.releaseOnce"
    rows := ["kernel.Resource.both", "kernel.Resource.use", "kernel.Resource.fold"]
    prop := ``Props.Phase6.Resource.bothReleasesBoth
    status := .refuted
    thm := some ``Proofs.Phase6.bothReleasesBoth_refuted
    bug := some "bugs/CE-0020.yaml"
    note := "Invariant: Resource.both(A, B).use(f) (Resource.scala:286-314, use = fold with \
      IO.bracketFull), sides are marked make in a harness with a log cell (the token, Ref 0, \
      allocated first); every run that ends: each release tag is logged as often as its acquire \
      tag. Decision 58: closure references are Val.fn; WellFormed libH holds user code to the \
      available handles (WF.avail: held, or own user closures); events and resource codes hold \
      the token; Private = the Phase 5 REnv clauses for non-harness entries (review batch 8 S2); \
      no user-code restriction beyond WellFormed (S1 gone); REnv table entries are Val.fn \
      references, harness entries odd (review batch 9 R1, regression example forge). \
      Counterexample: A's release raises; F.both in the makeCase release cancels the fiber of B's \
      finalizer chain before it starts (one schedule, decide +kernel); all hypotheses proven \
      (also the satisfiability witness). Fixed twin (attempt both chains) satisfies the \
      conclusion on the same input for 120 schedules (Proofs/Phase6/ResourceBothFixed.lean, \
      TwinChecks, kernel) and 600 + 1,500 schedules (smoke); v3.7.1 violates it there. \
      Reproducer: REPRODUCED on 3.7.1, series/3.x, series/3.7.x (fixed copy misses no release)." },
  { id := "kernel.Resource.use.releaseOnce"
    rows := ["kernel.Resource.use", "kernel.Resource.fold", "kernel.Resource.make"]
    prop := ``Props.Phase6.Resource.useReleaseOnce
    status := .«open»
    note := "Invariant (decision 50): make(acq)(rel).use(f) in the harness, directly or under the \
      harness parent that cancels and joins; release tag logged exactly as often as the acquire \
      tag. Decision 58 harness (Val.fn, WF.avail; Private = REnv clauses, S2; table entries are \
      references, review batch 9 R1). Wrong-function: use without release breaks it \
      (Proofs/Phase6/ResourceWrongFunction.lean, noReleaseUse_breaks). \
      Satisfiability witnesses with and without the parent (Proofs/Phase6/ResourceWitness.lean, \
      use_sat). Smoke: hypotheses evaluated, 3 releases x 4 bodies x parent/no parent x 900 \
      schedules (test/Phase6/ResourceSmoke.lean). Open: needs the bracket state invariant of \
      core.IO.bracket.releaseOnce (fold puts make under IO.bracketFull)." },
  { id := "kernel.Resource.flatMap.releaseOrder"
    rows := ["kernel.Resource.flatMap", "kernel.Resource.use", "kernel.Resource.fold"]
    prop := ``Props.Phase6.Resource.flatMapReleaseOrder
    status := .«open»
    note := "Invariant: make(A).flatMap(_ => make(B)).use(f) in the harness: each release tag iff its \
      acquire tag, and RB is logged before RA (LIFO; fold nests bracketFull). Decision 58 harness \
      (table entries are references, harness entries odd, review batch 9 R1). \
      Wrong-function: FIFO release order breaks it (ResourceWrongFunction.fifo_breaks). Satisfiability witnesses with \
      and without the parent (ResourceWitness.lean, flat_sat). Smoke: hypotheses evaluated, 24 \
      configurations x 900 schedules. Open: same missing state invariant, for two nested brackets." },
  { id := "kernel.Resource.eval.preservesCancelable"
    rows := ["kernel.Resource.eval", "kernel.Resource.allocatedCase"]
    prop := ``Props.Phase6.Resource.resourceEvalPreservesCancelable
    status := .«open»
    note := "Decision 41, the cancelable direction of CE-0002: if masking fa changes fa (EqvP), \
      masking Resource.eval(fa).allocatedCase changes it too. Smoke-tested with exact EqvP sets \
      for 4 programs fa; the over-masking Eval (wrong function) breaks it for IO.canceled \
      (test/Phase6/ResourceSmoke.lean, part 3). Believed true: a masked root never ends \
      Canceled, and alloc keeps every Canceled run of fa. Open: needs that invariant over \
      Step/SchedP." },
  -- Phase 6, batch 6.3 (parTraverseN; Props/Phase6/ParTraverse.lean)
  { id := "core.IO.parTraverseN.resultOrder"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNOrder
    status := .«open»
    note := "If parTraverseN(n)(as)(f) succeeds, the result holds one entry per input in input order \
      (f tagged by the harness as a => f(a).map(b => (a, b)); no lost, duplicated or \
      reordered entry). All user code. All n >= 1, all input lengths, all schedules, all HashSet orders (the supervision Set is a \
      HashSet from 5 elements; any permutation, review 7; difftest by refinement over every \
      child order, review 8). Satisfiable: \
      Proofs.Phase6.ParTraverseWitness.parTraverseNOrder_satisfiable. Smoke: lake exe ptsmoke \
      (a reversed result breaks it). Root: orderRoot (the public harness \
      closure TL.start builds the traversal; TL.tag is not public). Review 7 defect D and \
      review 8 F2 (f that captured the per-input result Deferred, named in a PT field or \
      under .some in a Timeout.fold source) are closed by decision 58: function fields are \
      Val.fn references and WellFormed follows them (WF.avail). Kernel examples: \
      Proofs.Phase6.ParTraversePrivacy; ptsmoke: both forgeries are rejected and break the \
      claim when run. Plausible. Open." },
  { id := "core.IO.parTraverseN.pureSucceeds"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNPureSucceeds
    status := .«open»
    note := "For f(a) = IO.pure(g(a)), every run that stops ends Succeeded(as.map(g)): no deadlock, \
      no error, input order. All n >= 1, all input lengths, all schedules, all HashSet orders (the supervision Set is a \
      HashSet from 5 elements; any permutation, review 7). Satisfiable \
      (parTraverseNPureSucceeds_satisfiable). Smoke: ptsmoke (a dropped result breaks it). \
      Open: needs a liveness and value invariant." },
  { id := "core.IO.parTraverseN.errorAborts"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNErrorAborts
    status := .«open»
    note := "If f(a0) raises e, a0 is among the first n inputs and every other f(a) never completes, \
      every run that stops ends Errored(e) (Scaladoc K/GC:137-139: errors abort the \
      sequence). The sharpest case of errorAbortsGen. All n >= 1, all input lengths, all schedules, all HashSet orders (the supervision Set is a \
      HashSet from 5 elements; any permutation, review 7). Satisfiable \
      (parTraverseNErrorAborts_satisfiable). Smoke: ptsmoke (no cancelAll in the error branch \
      breaks it). Open." },
  { id := "core.IO.parTraverseN.cancelAborts"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNCancelAborts
    status := .«open»
    note := "The same for a self-cancel f(a0) = IO.canceled: every run that stops ends Canceled. All n >= 1, all input lengths, all schedules, all HashSet orders (the supervision Set is a \
      HashSet from 5 elements; any permutation, review 7). \
      Satisfiable (parTraverseNCancelAborts_satisfiable). Smoke: ptsmoke. Open." },
  { id := "core.IO.parTraverseN.succeedsGen"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNSucceedsGen
    status := .«open»
    note := "f(a) = IO.cede k(a) times, then IO.pure(v(a)) (behaviour table, no user code): every run \
      that stops ends Succeeded with the values in input order. All n >= 1, all input lengths, all schedules, all HashSet orders (the supervision Set is a \
      HashSet from 5 elements; any permutation, review 7). \
      Satisfiable (parTraverseNSucceedsGen_satisfiable: 5 inputs, HashSet order reverse). \
      Smoke: ptsmoke (random tables). Open." },
  { id := "core.IO.parTraverseN.errorAbortsGen"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNErrorAbortsGen
    status := .«open»
    note := "Behaviour table with cedes, then pure, raiseError (non-fatal) or never, no cancel: if \
      some input raises and fewer than n inputs before it never complete (so it gets a \
      permit), every run that stops ends Errored(e) with an e that an input raises. Covers \
      siblings that complete, an action that suspends first, an error in an action that \
      starts later, two errors at once (review 7). All n >= 1, all input lengths, all schedules, all HashSet orders (the supervision Set is a \
      HashSet from 5 elements; any permutation, review 7). Satisfiable \
      (parTraverseNErrorAbortsGen_satisfiable). Smoke: ptsmoke (random tables; no cancelAll \
      breaks it). Open." },
  { id := "core.IO.parTraverseN.cancelAbortsGen"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNCancelAbortsGen
    status := .«open»
    note := "The same with IO.canceled in place of the error and no error: every run that stops ends \
      Canceled. All n >= 1, all input lengths, all schedules, all HashSet orders (the supervision Set is a \
      HashSet from 5 elements; any permutation, review 7). Satisfiable (parTraverseNCancelAbortsGen_satisfiable). Smoke: \
      ptsmoke. Open." },
  { id := "core.IO.parTraverseN.atMostN"
    rows := ["core.IO.parTraverseN", "kernel.GenConcurrent.parTraverseN", "kernel.MiniSemaphore.apply", "kernel.MiniSemaphore.acquire", "kernel.MiniSemaphore.release"]
    prop := ``Props.Phase6.ParTraverse.parTraverseNAtMostN
    status := .«open»
    note := "At most n actions run at once (Scaladoc K/GC:132-133): the harness (counter Ref 0) counts \
      the running g(a) inside uncancelable(poll => enter *> poll(g(a)).attempt.onCancel(exit) \
      ...); in every run that stops the highest count is <= n. All user code (WellFormed \
      limLib only; no harness-privacy hypothesis: the HarnessPrivacy module is removed, review 8 \
      S1, decision 58), n >= 1, all inputs, \
      schedules and HashSet orders. Review 8 F3 (user code writes the semaphore state Ref \
      through a Timeout.fold source) is closed by decision 58 (ParTraversePrivacy; ptsmoke: \
      rejected, and it breaks the claim when run). Satisfiable \
      (Limit.parTraverseNAtMostN_satisfiable: n = 1 reached). Wrong function: 1000 permits \
      reaches 2 > 1 (Limit.wideRun_breaks, kernel-checked; ptsmoke). Open." },
  { id := "std.CountDownLatch.awaitNotEarly"
    rows := ["std.CountDownLatch.apply", "std.CountDownLatch.State.initial", "std.CountDownLatch.release", "std.CountDownLatch.await", "std.CountDownLatch.ConcurrentCountDownLatch.release", "std.CountDownLatch.ConcurrentCountDownLatch.await"]
    prop := ``Props.Phase7.CountDownLatch.cdlAwaitNotEarly
    status := .«open»
    note := "Phase 7, track L. An await returns only after n release calls began (Scaladoc \
      CountDownLatch.scala:23-27, :39-41). Harness: awaiters ws[j].attempt *> uncancelable(poll => \
      mark 1 *> poll(l.await).onCancel(mark 3) *> mark 2), releasers us[i].attempt *> \
      uncancelable(started += 1 *> l.release *> completed += 1), the root cancels awaiters in \
      cancels, joins all. All user code (WellFormed cdlLib, variant-0 mirror closures only), all n, \
      all PChoice schedules and fuel (every reachable state). Satisfiable (LatchWitness.CDL.\
      awaitNotEarly_sat). Wrong function: variant 1 opens one release early (awaitNotEarly_wrong, \
      cdlAwaitNotEarly_v1_false; smoke 160 of 1500 runs). Smoke: 0 violations in 1500 runs. Open." },
  { id := "std.CountDownLatch.noLostWakeup"
    rows := ["std.CountDownLatch.apply", "std.CountDownLatch.State.initial", "std.CountDownLatch.release", "std.CountDownLatch.await", "std.CountDownLatch.ConcurrentCountDownLatch.release", "std.CountDownLatch.ConcurrentCountDownLatch.await"]
    prop := ``Props.Phase7.CountDownLatch.cdlNoLostWakeup
    status := .«open»
    note := "Phase 7, track L. A blocked run after n release calls has no awaiter left in await, \
      also with canceled and self-canceled awaiters (Scaladoc :33-36). Same harness and \
      quantifiers. Satisfiable (noLostWakeup_sat: blocked by a releaser that never ends). Wrong \
      function: variant 2 never completes signal (noLostWakeup_wrong; smoke 238). Smoke: 0. Open." },
  { id := "std.CountDownLatch.releaseTotal"
    rows := ["std.CountDownLatch.apply", "std.CountDownLatch.State.initial", "std.CountDownLatch.release", "std.CountDownLatch.await", "std.CountDownLatch.ConcurrentCountDownLatch.release", "std.CountDownLatch.ConcurrentCountDownLatch.await"]
    prop := ``Props.Phase7.CountDownLatch.cdlReleaseTotal
    status := .«open»
    note := "Phase 7, track L. In a blocked or done run every release returned (completed = \
      started), also releases after the count reached 0 (one-shot: no-ops, Scaladoc :24-26). \
      Satisfiable (releaseTotal_sat: n = 1, two releases). Wrong function: variant 3 raises \
      after Done (releaseTotal_wrong; smoke 225). Smoke: 0. Open." },
  { id := "std.CyclicBarrier.noEarlyTrip"
    rows := ["std.CyclicBarrier.apply", "std.CyclicBarrier.await"]
    prop := ``Props.Phase7.CyclicBarrier.cbNoEarlyTrip
    status := .«open»
    note := "Phase 7, track L. Without program cancels, passed <= cap * (entered / cap) in every \
      reachable state: each trip needs cap fibers in await (Scaladoc CyclicBarrier.scala:24-34). \
      Harness: group A, cancels, group B awaiters, each us.attempt *> uncancelable(poll => mark 1 \
      *> poll(b.await).onCancel(mark 3) *> mark 2). All user code (WellFormed cbLib), all cap, \
      schedules, fuel. Satisfiable (CB.noEarlyTrip_sat). Wrong function: variant 1 trips at cap - 1 \
      (noEarlyTrip_wrong; smoke 606 of 1500). Smoke: 0. Open." },
  { id := "std.CyclicBarrier.exactGenerations"
    rows := ["std.CyclicBarrier.apply", "std.CyclicBarrier.await"]
    prop := ``Props.Phase7.CyclicBarrier.cbExactGenerations
    status := .«open»
    note := "Phase 7, track L. Without program cancels, a blocked run released only full \
      generations (passed % cap = 0) and fewer than cap fibers wait: no lost wakeup. Satisfiable \
      (exactGenerations_sat). Wrong function: variant 4 never completes unblock \
      (exactGenerations_wrong; smoke 589). Smoke: 0. Open." },
  { id := "std.CyclicBarrier.cancelNoHang"
    rows := ["std.CyclicBarrier.apply", "std.CyclicBarrier.await"]
    prop := ``Props.Phase7.CyclicBarrier.cbCancelNoHang
    status := .«open»
    note := "Phase 7, track L. With program cancels at any point, a blocked run has fewer than cap \
      fibers in await: a canceled await leaves only its own generation (code comment \
      CyclicBarrier.scala:77-78). Satisfiable (cancelNoHang_sat). Wrong function: variant 3 drops \
      the epoch check; the race (A0 canceled while suspended, A1 trips before A0's cleanup task) \
      makes the next generation need cap + 1 (cancelNoHang_wrong, cbCancelNoHang_v3_false; v3.7.1 \
      passes the same schedule, cancelNoHang_v0_race). Smoke: 0. Open." },
  { id := "std.CyclicBarrier.cancelRemoved"
    rows := ["std.CyclicBarrier.apply", "std.CyclicBarrier.await"]
    prop := ``Props.Phase7.CyclicBarrier.cbCancelRemoved
    status := .«open»
    note := "Phase 7, track L. With as.length < cap (no trip before group B starts, after every \
      cancel returned), passed <= cap * ((entered - canceledIn) / cap) in every state: a canceled \
      await does not count for a trip. The hypothesis restricts the test program (a cancel that \
      loses the race with a trip is covered by cancelNoHang). Satisfiable (cancelRemoved_sat). \
      Wrong function: variant 2 does not re-increment (cancelRemoved_wrong). Smoke: 0. Open." }
]

end CatsEffectInLean

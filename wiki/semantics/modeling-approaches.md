# Modeling approaches for CE3 in Lean

> Sources: Marlow, Peyton Jones, Moran, Reppy 2001; GHC Control.Exception docs; Walker & Runciman 2015 (dejafu); Xia et al. 2019 (ITrees); Chappe et al. 2022 (CTrees); HITrees 2025; Lean reference (IO, Tasks, Std.Do); Loom (verse-lab); Porcupine; research notes 2026-11-10
> Raw: [Marlow 2001](../../raw/effect-semantics/2001-06-marlow-asynchronous-exceptions-in-haskell.md); [GHC masking](../../raw/effect-semantics/ghc-control-exception-async-masking.md); [dejafu paper](../../raw/effect-semantics/2015-09-dejafu-concurrency-testing-library-haskell.md); [dejafu README](../../raw/effect-semantics/dejafu-readme.md); [ITrees](../../raw/effect-semantics/2019-05-31-interaction-trees-coq-xia-et-al.md); [CTrees](../../raw/effect-semantics/2022-11-13-choice-trees-ctrees-coq-chappe-et-al.md); [HITrees](../../raw/effect-semantics/2025-10-16-hitrees-higher-order-interaction-trees-lean.md); [lean-itrees](../../raw/effect-semantics/lean-itrees-boogie-org-readme.md); [ISTA Coinductive](../../raw/effect-semantics/ista-plv-coinductive-lean-itrees-readme.md); [Lean IO model](../../raw/effect-semantics/lean-reference-io-logical-model.md); [Lean tasks](../../raw/effect-semantics/lean-reference-tasks-and-threads.md); [Std.Do / mvcgen](../../raw/effect-semantics/lean-reference-mvcgen-std-do.md); [Loom](../../raw/effect-semantics/loom-verse-lab-readme.md); [Porcupine](../../raw/effect-semantics/porcupine-linearizability-checker-readme.md); [Modeling notes](../../raw/effect-semantics/2026-11-10-findings-effect-semantics-modeling-notes.md)

## Overview

Recommendation (confidence 0.8): a **small-step operational semantics with an explicit scheduler**, executable in Lean, mirroring `IOFiber`, in the style of Marlow et al. 2001. State the CE3 laws and std-structure invariants as properties over it. Find bugs by bounded schedule enumeration and difftest against real CE3. Not decided yet — confirm with the user before formalization starts.

## Approaches compared

| Approach | Pros | Cons |
|---|---|---|
| 1. Small-step operational semantics + scheduler (recommended) | Executable (`#eval`, `decide`); enumerate all schedules up to a bound (dejafu-style); maps 1:1 to IOFiber and Marlow 2001; easy difftest | Equational laws need bisimulation / outcome-set equivalence |
| 2. Denotational via ITrees/CTrees | Compositional, rich equational theory | Lean ITree libs immature (boogie-org: no universe polymorphism, no `interp`; ISTA Coinductive: early); `start`/`uncancelable`/`poll` are higher-order effects (HITrees tricks); weak for bug finding |
| 3. Law-based / axiomatic | Direct use of CE3 laws | Needs a model to be about; combine with 1 |
| 4. Differential testing only | Cheap, finds model bugs | Proves nothing; still needs 1 |

## Sketch of approach 1

- Syntax: inductive IO mirroring the 25 IO constructors (Pure, Error, Delay, Map, FlatMap, Attempt, HandleErrorWith, Canceled, OnCancel, Uncancelable, UnmaskRunLoop, IOCont/Get, Cede, Start, RacePair, Sleep, …).
- Per-fiber state: continuation stack, mask counter (IOFiber) or mask ids (spec), finalizer stack, cancel flag, finalizing flag, outcome cell, joiner callbacks.
- Global state: fibers, `Ref`/`Deferred` cells, virtual clock.
- Interleavings: a relation, or a step function indexed by a scheduler choice list. Cancel observation: a nondeterministic choice at each boundary, not the literal 512-step threshold.
- User code (thunks, finalizers, callbacks) as parameters that can raise, suspend and re-enter.
- Model both the real IOFiber (counter + poll ids) and the spec (fresh mask ids) to compare them.
- Kernel evaluation (toy spike, 2026-11-10): this shape (non-recursive `step`, structural fuel, `Nat` ids, `List` state, user code as a parameter) is kernel-evaluable. Refutation witnesses check in seconds; bounded "all schedules" proofs use `decide_cbv` plus one soundness lemma. See [Kernel evaluation of the model](../lean/kernel-evaluation.md).

## Properties to state

- Each MonadCancel, GenSpawn, Async law, under every schedule (outcome-set equivalence).
- The four external-cancel rules (masking, backpressure, idempotency, terminal).
- Finalizers run exactly once on Canceled; none after Succeeded.
- `bracket`: if acquire completed, release runs on every outcome.
- Mask balance across `uncancelable`.
- `race`, `both`, `timeout` leak no fibers.
- std primitives: no lost elements/wakeups, deadlock-freedom under cancel; linearizability (Porcupine-style check) for Queue/Semaphore/Mutex.

## Prior art notes

- **Marlow 2001**: small-step semantics of async exceptions: process soup, in-flight exception process, blocked vs unblocked contexts. GHC `mask`/`restore` ≈ CE3 `uncancelable`/`poll`, but GHC has *interruptible* blocking ops (CE3 does not) and `throwTo` returns on delivery (CE3 `cancel` waits for finalization — stronger).
- **dejafu**: typeclass with several implementations; systematic concurrency testing with preemption bounding (default 2); found real bugs. Random-scheduler mode is incomplete. Strong model for our schedule enumeration.
- **Lean IO**: `EStateM` over an opaque world; `Task`/`IO.cancel` are opaque. Lean gives no logical concurrency model, so we build our own deep embedding.
- **Std.Do / vcgen**: designed for single-threaded state with interruption; "more exotic effects have not yet been investigated". Probably not useful for the interpreter; maybe for std structure code.
- **Loom/Velvet**: multi-modal WP in Lean; angelic nondeterminism to prove a bug *exists* (incorrectness logic) — relevant for refutations over schedules.

## Pitfalls

- Equivalence must be outcome-set equivalence, not one trace.
- Deliberate monad-law violation of `onCancel`/`uncancelable` is not a bug.
- PureConc is not an oracle (#3430).
- The lock-free runtime (`LocalQueue`, `CallbackStack`) needs the JVM memory model — separate later effort.

## Open questions

- Model fairness/liveness, or safety only?
- How to abstract `evalOn`, `blocking`, the work-stealing pool — probably as scheduler choices.
- Not yet collected: "Tackling the awkward squad", Koka/Eff semantics, structured-concurrency formalizations, Spiewak talk transcripts.

## See Also

- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Semantics of CE3](../cats-effect/semantics.md)
- [Differential testing](../methodology/differential-testing.md)
- [Lean v4.35.0 toolchain](../lean/toolchain-v4-35.md)

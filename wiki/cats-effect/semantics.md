# Semantics of Cats Effect 3 (cancellation, masking, fibers, laws)

> Sources: cats-effect v3.7.1 scaladoc, laws and IOFiber source; CE docs; issues #634 (Spiewak 2019), #681 (Labella 2019), #1744, #1979, #3430; v3.5.0 release notes
> Raw: [MonadCancel laws](../../raw/effect-semantics/ce3-monadcancel-laws.md); [GenSpawn laws](../../raw/effect-semantics/ce3-genspawn-laws.md); [Async/Sync/Temporal laws](../../raw/effect-semantics/ce3-async-sync-temporal-laws.md); [Kernel scaladoc](../../raw/effect-semantics/ce3-kernel-monadcancel-genspawn-fiber-src.md); [IOFiber excerpts](../../raw/effect-semantics/ce3-iofiber-runloop-masking-excerpts.md); [PureConc](../../raw/effect-semantics/ce3-kernel-testkit-pureconc-model.md); [coop ThreadT](../../raw/effect-semantics/coop-threadt-cooperative-threads.md); [MonadCancel docs](../../raw/effect-semantics/ce3-docs-monadcancel.md); [Spawn docs](../../raw/effect-semantics/ce3-docs-spawn.md); [Concepts docs](../../raw/effect-semantics/ce3-docs-concepts.md); [CE3 proposal #634](../../raw/effect-semantics/2019-09-12-cats-effect-3-proposal-issue-634.md); [Interruption model #681](../../raw/cats-effect/2019-10-23-ce3-interruption-model-issue-681.md); [#1744](../../raw/effect-semantics/2021-02-28-ce3-issue-1744-uncancelable-boundaries-compose-poorly.md); [#1979](../../raw/effect-semantics/2021-05-18-ce3-discussion-1979-cancelation-model.md); [#3430](../../raw/effect-semantics/2023-02-17-ce3-issue-3430-pureconc-not-running-finalizers.md); [v3.5.0 notes](../../raw/effect-semantics/2023-05-12-cats-effect-v3-5-0-release-notes.md); [Laws source v3.7.1](../../raw/cats-effect/2026-08-23-cats-effect-v3-7-1-laws-source.md); [MonadCancel docs (cats-effect dir)](../../raw/cats-effect/cats-effect-docs-typeclass-monadcancel.md); [Spawn docs (cats-effect dir)](../../raw/cats-effect/cats-effect-docs-typeclass-spawn.md); [Async docs](../../raw/cats-effect/cats-effect-docs-typeclass-async.md); [Typeclasses overview](../../raw/cats-effect/cats-effect-docs-typeclasses-overview-and-small.md); [Concepts](../../raw/cats-effect/cats-effect-docs-concepts.md); [FAQ](../../raw/cats-effect/cats-effect-docs-faq.md); [CE3 proposal (cats-effect dir)](../../raw/cats-effect/2019-09-12-ce3-proposal-issue-634.md)

## Overview

The normative semantics of CE3 lives in three places: kernel scaladoc, the law files, and `IOFiber`. They do not fully agree with the pure test model PureConc. No prior Coq/Lean/Agda/Isabelle/TLA+ formalization of Cats Effect, ZIO or Monix was found (absence of evidence; confidence 0.7).

## Normative rules (scaladoc of MonadCancel, GenSpawn, Fiber)

- **Cancellation is advisory** and observed only at boundaries. Boundaries come *before* combinators, never after, so a `poll` result is not lost.
- **Masking by region**: `uncancelable(poll => body)`. Inside, `canceled` acts as `unit` but leaves the cancel flag set; the fiber is cancelled when fully unmasked. Nested `uncancelable` collapses; `poll` of an outer region inside a nested region is a no-op ("outer block wins").
- **External `cancel`** has four rules: masking (held until unmasked), **backpressure** (`cancel` waits until finalizers finish), idempotency, terminal (cancel of a finished fiber returns at once). `cancel` itself is uncancelable.
- **Finalizers** (`onCancel`, `guarantee`, `bracket`) run LIFO and masked.
- **Outcome** = `Succeeded(fa) | Errored(e) | Canceled()`.
- **Async (since 3.5.0)**: `async` whose registration returns `None` cannot be cancelled while suspended; `async_` is uncancelable. Callbacks may be called twice (second ignored, by law), may run before registration ends, may race with cancel.
- **Sync**: `delay` and `blocking` cannot be interrupted; `interruptible` can.
- A fiber cancelled before it first runs never registers its finalizers (#4488, "as designed").
- `uncancelable` is **not** inherited by fibers started inside it (GenSpawn law).

## Laws

- Files: MonadCancel, GenSpawn, GenTemporal, Sync, Async, Clock, Unique. **No GenConcurrent laws** — `Ref`/`Deferred` are tested only by unit specs.
- `onCancelAssociatesOverUncancelableBoundary` is commented "effectively in violation of the monad laws" — deliberate (#1744). **Do not report it as a bug.** The law itself holds for `IO`: the CE suite checks it, and the model's bounded checks agree. What it breaks is the monad laws (finalizers associate over `uncancelable` but not over `flatMap`). See [Outcome sets and `Eqv`](../semantics/outcome-equivalence.md).
- Laws needing nondeterministic substitutability are commented out; two race laws are deprecated since 3.5.0.
- Some MonadCancel laws apply only to Cancelable root scope, some only to Uncancelable (SyncIO).

## IOFiber implementation

- `masks: Int` counter; `uncancelable` does `masks += 1; id = masks`; `poll` unmasks only if `masks == id && self eq this`.
- `shouldFinalize() = canceled && masks == 0`, checked each loop step; read barrier only every `cancelationCheckThreshold` (512) iterations; auto-yield every 1024 by default.
- Cancel: `prepareFiberForCancelation` sets `finalizing`, increments masks, pops and runs finalizers one by one, then `done(Canceled)`.
- `IOCont`/`Get`: three-way race between callback, `get` and `cancel` via `ContState` atomic reference.

## PureConc (the kernel-testkit model) differs from IOFiber

- Built on coop `ThreadT` (free-monad green threads) + `MVar`, run by `ThreadT.roundRobin` — **one deterministic schedule**, so laws are never checked under other interleavings.
- `cancel` = `tryPut(Canceled)`: does **not** wait for finalizers (violates backpressure rule).
- #3430 (open since 2023-02, maintainers agree it is a bug): finalizers of a fiber parked in `never` are not run.
- Uses a fresh `MaskId` per mask instead of a counter. Hypothesis (unverified, confidence 0.5): an escaped `poll` reused in another `uncancelable` at the same depth may unmask it in IO but not in PureConc. Needs a difftest before calling it a bug.
- Conclusion: PureConc is **not** an oracle. A Lean model could become a better law-checking reference.

## Contested points (spec decisions, not bugs by default)

- Deadlock safety vs resource safety trade-off (#1979).
- Escaped `poll` behaviour.
- #4488 behaviour.

## See Also

- [Outcome sets, `Eqv` and the IO laws](../semantics/outcome-equivalence.md)

- [Modeling approaches for CE3 in Lean](../semantics/modeling-approaches.md)
- [Source layout](source-layout.md)
- [Bug history](bug-history.md)

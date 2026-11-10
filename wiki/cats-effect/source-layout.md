# Cats Effect v3.7.1 source layout

> Sources: typelevel/cats-effect source at v3.7.1, read 2026-11-10
> Raw: [Source layout notes](../../raw/cats-effect/2026-11-10-ce-v3-7-1-source-layout-notes.md); [Laws source](../../raw/cats-effect/2026-08-23-cats-effect-v3-7-1-laws-source.md); [Test runtime docs](../../raw/cats-effect/cats-effect-docs-test-runtime.md); [Thread model docs](../../raw/cats-effect/cats-effect-docs-thread-model.md); [Schedulers docs](../../raw/cats-effect/cats-effect-docs-schedulers.md); [Std docs](../../raw/cats-effect/cats-effect-docs-std-pages.md)

## Overview

Map of the code we will mirror. Line counts include ~16-line license headers. sbt modules: `kernel`, `kernel-testkit`, `laws`, `core`, `std`, `testkit`, `tests`.

## kernel (7,300 lines) — typeclasses and core data types

`MonadCancel` 1008 · `GenSpawn` 933 · `GenConcurrent` 576 · `GenTemporal` 406 · `Sync` 297 · `Async` 761 · `Clock` 238 · `Unique` 36 · `Poll` 25 · `CancelScope` 24 · `Cont` 66 · `Outcome` 255 · `Fiber` 87 · `Ref` 529 · `Deferred` 265 · `MiniSemaphore` 93 · `Resource` 1601.

Hierarchy: `MonadCancel ⊂ GenSpawn (+Unique) ⊂ GenConcurrent ⊂ GenTemporal (+Clock)`, with `Sync` (MonadCancel + Clock + Unique + `suspend`) and `Async` (GenTemporal + Sync + `cont`). Many combinators are **derived** in the typeclasses (`bracket*`, `guarantee*`, `race`, `both`, `memoize`, `timeout*`, `parTraverseN`, `async`, `syncStep`) and `IO` overrides some of them.

## laws (1,806 lines)

`MonadCancelLaws` 109, `GenSpawnLaws` 164, `GenTemporalLaws` 44, `SyncLaws` 80, `AsyncLaws` 94, `ClockLaws` 35, `UniqueLaws` 35. **There is no `GenConcurrentLaws`.** Some MonadCancel laws apply only to a Cancelable root scope, some only to Uncancelable (SyncIO). Law files saved verbatim in raw.

## core: IO (IO.scala 2404, IOFiber.scala 1648)

- **IO ADT**: 25 constructors with byte tags: `Pure 0, Error 1, Delay 2, RealTime 3, Monotonic 4, ReadEC 5, Map 6, FlatMap 7, Attempt 8, HandleErrorWith 9, Canceled 10, OnCancel 11, Uncancelable 12, UnmaskRunLoop 13 (internal), IOCont 14, IOCont.Get 15 (internal), Cede 16, Start 17, RacePair 18, Sleep 19, EvalOn 20, Blocking 21, Local 22, IOTrace 23, ReadRT 24, EndFiber -1 (internal)`. Plus a `SyncStep` interpreter (MaxSteps 512).
- **IOFiber state**: `objectState` and `conts` (byte stack of continuation tags), `finalizers` stack, `callbacks` (joiners), `masks: Int`, `canceled`, `finalizing`, `outcome`, `suspended` (atomic ownership of the run loop), `resumeTag`.
- **Run loop**: `@tailrec` switch on tag; checks `shouldFinalize() = canceled && masks == 0`; cancellation read barrier every `cancelationCheckThreshold` steps; auto-cede every `autoYieldThreshold` steps.
- Other: `SyncIO` 682, `IOLocal` 344, `IODeferred` 82, `ContState`, `IORuntime*`, `IOApp`.

## core: runtime (JVM/Native)

`WorkStealingThreadPool` 887, `WorkerThread` 1129, `LocalQueue` 970 (lock-free SPMC ring of 256 with a "steal tag"), `ScalQueue` 224, `TimerHeap` 553, `PollingSystem` 182 (+ Selector/Epoll/Kqueue), `CallbackStack` 256, `FiberMonitor` 299. Lock-free; a faithful model needs the JVM memory model. Treat as a later, separate target.

## std (8,690 lines)

`Queue` 1206 (two impls: Concurrent = Ref+Deferred state machine; Async = lock-free) · `Dispatcher` 656 · `Dequeue` 523 · `Supervisor` 410 · `AtomicCell` 329 · `Semaphore` 298 · `PQueue` 284 · `Hotswap` 120 · `Mutex` 112 · `CountDownLatch` 96 · `CyclicBarrier` 92 · `MapRef` 553. **None has laws** — properties must come from Scaladoc and obvious invariants.

## Test infrastructure (useful as oracles)

- **PureConc** (`kernel-testkit/pure.scala`, 396): a pure reference model of `GenConcurrent` built on coop's `ThreadT` (free-monad green threads) and `MVar`; `FiberCtx` holds masks and finalizers. A second, independent implementation to compare against (open bug #3430: it does not run finalizers on cancel).
- **TestContext** 331, **TimeT** 160, **Generators** 395 (ScalaCheck generators of programs).
- **TestControl** (testkit, 438): single-threaded mock runtime with virtual time; `tick`, `tickOne`, `tickAll`, `advance`, `results`, `isDeadlocked`; picks a random ready fiber with a seed. This is the natural harness for a deterministic difftest against the Lean model.
- `IOSuite` (2828) runs `AsyncTests[IO]` laws under a `Ticker`.

## See Also

- [Pinned version](pinned-version.md)
- [Semantics of CE3](semantics.md)
- [Bug history](bug-history.md)
- [Differential testing against Scala](../methodology/differential-testing.md)

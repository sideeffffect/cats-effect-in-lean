# Cats Effect v3.7.1 source layout for formalization (research note)

> Source: https://github.com/typelevel/cats-effect/tree/v3.7.1 (local checkout ~/Projects/cats-effect, detached HEAD at v3.7.1, commit eb0cc258fc732fc37f22f117c2e81d5554d67024)
> Collected: 2026-11-10
> Published: 2026-08-23

Own notes, written from reading the source at tag v3.7.1. Line counts are `wc -l` (including the license header, ~16 lines per file).

## Build

- `build.sbt`: Scala 2.12.20, 2.13.18, 3.3.4. Platforms JVM, Scala.js, Scala Native 0.5 (crossProject JS/JVM/Native).
- Dependencies: cats 2.13.0; kernel-testkit uses `org.typelevel::coop` 1.3.0 (ThreadT, MVar) for the pure model. Tests use munit + discipline-munit + ScalaCheck.
- sbt modules: `kernel`, `kernel-testkit`, `laws`, `core`, `std`, `testkit`, `tests`, `ioapp-tests`, `example`, `benchmarks`, `scalafix`, `graalvm-example`. Docs in `docs/` (markdown, mdoc).

## kernel (typeclass hierarchy) — kernel/shared/src/main/scala/cats/effect/kernel/ (7300 lines)

| File | Lines | Content |
|---|---|---|
| MonadCancel.scala | 1008 | `MonadCancel[F, E] extends MonadError`: `canceled`, `onCancel`, `uncancelable(Poll => F[A])`, `forceR`, `rootCancelScope`; derived `guarantee`, `guaranteeCase`, `bracket`, `bracketCase`, `bracketFull`. Instances for transformers. |
| CancelScope.scala | 24 | `Cancelable` / `Uncancelable` (root scope; e.g. SyncIO is Uncancelable). |
| Poll.scala | 25 | `Poll[F] extends (F ~> F)`. |
| Outcome.scala | 255 | `Outcome[F,E,A]` = `Succeeded(fa: F[A])` / `Errored(e)` / `Canceled()`; `embed`, `embedNever`. |
| GenSpawn.scala | 933 | `GenSpawn extends MonadCancel with Unique`: `start`, `never`, `cede`, `racePair`; derived `race`, `raceOutcome`, `both`, `bothOutcome`, `background`, `memoize`. |
| Fiber.scala | 87 | `Fiber[F,E,A]`: `cancel`, `join`, `joinWith`, `joinWithNever`. |
| GenConcurrent.scala | 576 | `GenConcurrent extends GenSpawn`: `ref`, `deferred`; derived `memoize`, `parReplicateAN`, `parSequenceN`, `parTraverseN`, `parTraverseN_` (rewritten in 3.6.4/3.7.1); overrides `racePair` (line 339) in terms of `start` + `Deferred`. NO laws file for GenConcurrent. |
| GenTemporal.scala | 406 | `sleep`; derived `delayBy`, `andWait`, `timeout`, `timeoutTo`, `timeoutAndForget`. |
| Clock.scala | 238 | `monotonic`, `realTime`. |
| Unique.scala | 36 | `unique: F[Unique.Token]`. |
| Sync.scala | 297 | `suspend(hint: Sync.Type)(thunk)`, `delay`, `blocking`, `interruptible`, `interruptibleMany`. Sync.Type = Delay / Blocking / InterruptibleOnce / InterruptibleMany. |
| Async.scala | 761 | `cont` (primitive, via `Cont`), `async`, `async_`, `asyncCheckAttempt`, `evalOn`, `executionContext`, `never`, `fromFuture`, `fromCompletableFuture`, `syncStep`. |
| Cont.scala | 66 | `Cont[F,K,R]`: rank-2 body `(K => Unit, F[K], G ~> F) => F[R]` — the low-level async primitive. |
| Ref.scala | 529 | `Ref` (AtomicReference-based `SyncRef`), `modify`, `update`, `access`, `tryUpdate`, `flatModify`. |
| Deferred.scala | 265 | `Deferred` (`get`, `complete`, `tryGet`), AsyncDeferred with callback map. |
| MiniSemaphore.scala | 93 | Internal semaphore used by `memoize` etc. |
| Resource.scala | 1601 | `Resource` ADT: `Allocate(resource: Poll[F] => F[(A, ExitCase => F[Unit])])`, `Bind`, `Pure`, `Eval`; `use`, `allocated`, `allocatedCase`, `allocatedFull`, `race`, `both`, `timeout`, `memoize`. |
| ParallelF.scala | 46 | Parallel newtype. |

## laws — laws/shared/src/main/scala/cats/effect/laws/ (1806 lines)

Saved verbatim in `2026-08-23-cats-effect-v3-7-1-laws-source.md`. Summary of what each law file states:

- MonadCancelLaws (109): uncancelable/poll algebra (poll is identity; nested uncancelable collapses; inverse nesting of polls is uncancelable; uncancelable eliminates onCancel; onCancel associates over uncancelable boundary — commented as "effectively in violation of the monad laws"); forceR laws; `canceled` with onCancel ordering (fin1 then fin2); `canceled >> fa <-> canceled` (only if rootCancelScope = Cancelable); `uncancelable(_ => fa) <-> fa` and `canceled <-> unit` (only if Uncancelable).
- GenSpawnLaws (164): race derived from racePair (left/right); race with never is identity; fiber outcomes for pure/error/cancel/canceled/never; `start(never).void <-> unit`; `fiberJoinIsGuaranteeCase`; `never >> fa <-> never`; uncancelable is NOT inherited by race children; `uncancelable(_ => f.cancel)` still cancels; `start` inside uncancelable creates a cancelable fiber. Two raceCanceledIdentity laws deprecated in 3.5.0 as "no longer applicable (or correct)".
- GenTemporalLaws (44): `sleep d >> monotonic = monotonic + d`; race of sleeps = min; start+sleep = max.
- SyncLaws (80): suspend value is pure; suspend throw is raiseError; unsequenced suspend is no-op; repeated suspend not memoized.
- AsyncLaws (94): asyncCheckAttempt immediate is pure; async with immediate callback = `uncancelable(_ => fu) >> pure(a)` (3.5.0 semantics: async registration is uncancelable); repeated callback ignored; cancel token unsequenced on completion/error; `never` derived from async; evalOn laws; `syncStepIdentity`.
- ClockLaws (35): monotonicity. UniqueLaws (35): two tokens differ.
- IsEq (84), Tolerance (30): equality with time tolerance.
- *Tests.scala: discipline RuleSets wiring laws to ScalaCheck.

## core IO — core/ (20929 lines in main)

### IO ADT — core/shared/src/main/scala/cats/effect/IO.scala (2404 lines)

`sealed abstract class IO[+A]` with `def tag: Byte`. Constructors (lines ~2205-2335):

| tag | Constructor | Meaning |
|---|---|---|
| 0 | Pure(value) | |
| 1 | Error(t) | |
| 2 | Delay(thunk, event) | `IO.delay` / `IO.apply` |
| 3 | RealTime | |
| 4 | Monotonic | |
| 5 | ReadEC | current ExecutionContext |
| 6 | Map(ioe, f, event) | |
| 7 | FlatMap(ioe, f, event) | |
| 8 | Attempt(ioa) | |
| 9 | HandleErrorWith(ioa, f, event) | |
| 10 | Canceled | self-cancelation |
| 11 | OnCancel(ioa, fin) | |
| 12 | Uncancelable(body: Poll[IO] => IO[A], event) | |
| 13 | Uncancelable.UnmaskRunLoop(ioa, id, self) | internal, made by `poll` |
| 14 | IOCont(body: Cont, event) | async primitive |
| 15 | IOCont.Get(state: ContState) | internal |
| 16 | Cede | |
| 17 | Start(ioa) | |
| 18 | RacePair(ioa, iob) | |
| 19 | Sleep(delay) | |
| 20 | EvalOn(ioa, ec) | |
| 21 | Blocking(hint, thunk, event) | blocking / interruptible |
| 22 | Local(f: IOLocalState => (IOLocalState, A)) | IOLocal |
| 23 | IOTrace | |
| 24 | ReadRT | IORuntime |
| -1 | EndFiber | internal terminal |

Also `SyncStep` (MaxSteps = 512) interpreter for `syncStep` (note: open bug #4687 says `syncStep` drops `uncancelable`/`onCancel` wrappers).

### Run loop — core/shared/src/main/scala/cats/effect/IOFiber.scala (1648 lines)

State of one fiber (fields, lines 85-107): `localState`, `currentCtx` (EC), `objectState: ArrayStack[AnyRef]` (continuation data), `finalizers: ArrayStack[IO[Unit]]`, `callbacks: CallbackStack[Outcome]` (joiners), `resumeTag: Byte`, `resumeIO`, `conts: ByteStack` (continuation tags such as FlatMapK, HandleErrorWithK, OnCancelK, UncancelableK, UnmaskK, CancelationLoopK, ...), `canceled: Boolean`, `masks: Int`, `finalizing: Boolean`, `outcome`. Ownership of the run loop is an `AtomicBoolean suspended` (IOFiber extends it): `resume() = suspended.getAndSet(false)`, `suspend() = suspended.set(true)`.

Key mechanisms:
- `runLoop(cur, cancelationIterations, autoCedeIterations)` is a `@tailrec` `tableswitch` on `tag`. Every `cancelationCheckThreshold` iterations a read barrier is done; every `autoYieldThreshold` iterations the fiber reschedules itself (`AutoCedeR`). Config requires `autoYieldThreshold % cancelationCheckThreshold == 0`.
- `shouldFinalize() = canceled && masks == 0`. Checked at the top of each loop iteration.
- Canceled (tag 10): sets `canceled = true`; if unmasked, runs finalizers now (`prepareFiberForCancelation`); else continues with `()`.
- OnCancel (11): pushes `EvalOn(fin, currentCtx)` to `finalizers`, pushes OnCancelK; `succeeded` pops the finalizer on normal completion.
- Uncancelable (12): `masks += 1; id = masks`; poll = `UnmaskRunLoop(ioa, id, this)`. UnmaskRunLoop (13) unmasks ONLY IF `masks == id && self eq this` ("outer block wins"); a poll from an outer region used inside a nested region is a no-op; a poll used in another fiber is a no-op.
- `prepareFiberForCancelation`: if finalizers non-empty and not yet finalizing, reset `conts` to [CancelationLoopK], set `finalizing = true`, `masks += 1` (finalizers run masked), pop and run finalizers one by one; else call `done(Outcome.Canceled)`.
- `cancel` (external): `IO.uncancelable { canceled = true; if (resume()) { if unmasked -> take over run loop and run finalizers via async_ (AsyncContinueCanceledWithFinalizerR) else suspend() and join } else join }`. So `cancel` back-pressures until finalizers are done.
- `join`: `asyncCheckAttempt` that pushes a callback to `callbacks` with double-check of `outcome`.
- `done(oc)`: sets `_join = pure(oc)`, `_cancel = unit`, `outcome`, calls callbacks, reports unhandled errors, `masks = 0`, clears all state.
- IOCont (14) / Get (15): a 3-way race between the callback `cb`, the `get`, and `cancel`, coordinated by `ContState` (AtomicReference with states null = initial, `waiting` sentinel, result) and by `suspended`. `cb` is idempotent (second call is a no-op). `wasFinalizing` guards against resuming into a different finalization scope. Get pushes a finalizer that resets `waiting -> null`.
- Resume tags in `run()`: ExecR, AsyncContinueSuccessfulR, AsyncContinueFailedR, AsyncContinueCanceledR, AsyncContinueCanceledWithFinalizerR, BlockingR, CedeR, AutoCedeR, DoneR.
- Fatal errors: `onFatalFailure` (non-`NonFatal` throwables) shut down the runtime.

### Runtime (JVM/Native) — core/jvm-native/src/main/scala/cats/effect/unsafe/

| File | Lines | Content |
|---|---|---|
| WorkStealingThreadPool.scala | 887 | Pool: worker array, external `ScalQueue`, parked-worker tracking, `notifyParked`, `stealFromOtherWorkerThread`, blocking-thread caching. |
| WorkerThread.scala | 1129 | Worker loop: local queue, external queue polling every N ticks, timers (TimerHeap), poller (PollingSystem), parking, `blocking` flag; on `IO.blocking` the worker becomes a blocker thread and a replacement worker is spawned/reused. |
| LocalQueue.scala | 970 | Lock-free SPMC ring buffer (capacity 256), head/tail packed with a "steal tag"; `enqueue`, `enqueueBatch`, `dequeue`, `stealInto`, overflow to external queue in batches. (Open bug #4674: dangling steal tag makes `enqueueBatch` spin forever.) |
| ScalQueue.scala | 224 | Striped external queue. |
| TimerHeap.scala | 553 | Per-worker timer heap with cancelation; stealing of timers. |
| PollingSystem.scala | 182 | Integrated I/O polling SPI (3.6+). SelectorSystem (jvm, 369), EpollSystem (native, 477), KqueueSystem (native, 451). |
| FiberMonitor.scala | 299 | Fiber dumps / suspended-fiber tracking (WeakBag). |
| CallbackStack.scala (jvm-native) | 256 | Lock-free stack of callbacks for join/Deferred; `pack` (history: #3359, #3935, #3940). |
| ArrayStack 98, ByteStack 92 | | Run-loop stacks. |

Other core files: SyncIO.scala 682 (synchronous IO, rootCancelScope Uncancelable), IOLocal.scala 344, IODeferred.scala 82, ContState.scala, IORuntime.scala 184, IORuntimeConfig.scala 273, IOApp.scala (jvm 631, native 470, js 323), CpuStarvationCheck 72, tracing/Tracing.scala 179.

## std — std/shared/src/main/scala/cats/effect/std/ (8690 lines in main, all platforms)

| File | Lines | Notes |
|---|---|---|
| Queue.scala | 1206 | `Queue.bounded/unbounded/synchronous/dropping/circularBuffer`; two impls: Concurrent (Ref+Deferred state machine) and Async (lock-free `unsafe.BoundedQueue`/`UnboundedQueue` + waiter lists). |
| Dispatcher.scala | 656 | Run `F` from impure code; `parallel` / `sequential`, `await` mode; worker fibers + atomic state. |
| Random.scala | 639 | |
| MapRef.scala | 553 | |
| Dequeue.scala | 523 | |
| Supervisor.scala | 410 | Tracks child fibers in a state map; `await` mode; cancels children on release. |
| AtomicCell.scala | 329 | Mutex-guarded cell with effectful `evalModify`. |
| Semaphore.scala | 298 | Ref-based state of permits + waiting queue; O(1) cancel since 3.7.1 (#4648). |
| PQueue.scala | 284 | BinomialHeap-based priority queue. |
| NonEmptyHotswap.scala, Hotswap.scala | 182, 120 | Swappable Resource. |
| Mutex.scala | 112 | Async impl uses lock-free `LockQueue` (110). |
| KeyedMutex.scala | 101 | |
| CountDownLatch.scala | 96 | |
| CyclicBarrier.scala | 92 | |
| Backpressure.scala | 93 | |
| UUIDGen 147, SecureRandom 169, Console*, Env, SystemProperties | | Not relevant to semantics. |

`Ref` and `Deferred` live in kernel (above).

## Test suites

- `laws/shared/src/test/...` (1431 lines): `PureConcSuite` checks `GenTemporalTests[TimeT[PureConc[Int,*],*], Int]`; FreeSync suites check `SyncTests`; transformer suites (EitherT, OptionT, IorT, WriterT, Kleisli, StateT, ReaderWriterStateT) over PureConc and FreeSync; `ResourcePureConcSuite`; `OutcomeSuite`; `TimeTSuite`.
- `kernel-testkit` (main): `pure.scala` (396) — PureConc = `Kleisli[ThreadT[Kleisli[Outcome[Id,E,*], FiberCtx[E], *], *], MVar.Universe, A]`: a PURE REFERENCE MODEL of GenConcurrent using coop's ThreadT (free-monad green threads) and MVars; FiberCtx holds `masks: List[MaskId]` and `finalizers`. Cancelation is checked at every flatten. `Generators.scala` (395) generates arbitrary effect programs for the laws. `TestContext.scala` (331) — deterministic ExecutionContext with virtual time. `TimeT.scala` (160) adds virtual time. `freeEval.scala` (86) — FreeSync model. Open issue #3430: "PureConc not running finalizers".
- `testkit` (main): `TestControl.scala` (438) — single-threaded mock runtime over TestContext; `tick`, `tickOne`, `tickAll`, `advance`, `results`, `executeEmbed`, `isDeadlocked`; picks randomly among ready fibers (seeded). `TestInstances.scala` (268): `Ticker`, `Eq[IO[A]]` by running under TestContext.
- `tests/` (18216 lines): IOSuite (2828; `checkAll("IO", AsyncTests[IO].async[Int,Int,Int](10.millis))` with a Ticker), ResourceSuite (1456; Resource law checks), QueueSuite (1026), IOConcurrencySuite (jvm-native, 782), DispatcherSuite (671), MemoizeSuite (406), SemaphoreSuite (352), SupervisorSuite (326), MutexSuite (235), DeferredSuite (207), ContSuite (194), CallbackStackSuite, IOFiberSuite, TestControlSuite (228), jvm unsafe/ (TimerHeapSuite, SleepersSuite, BlockingStressSuite, DrainBatchSuite, HelperThreadParkSuite, FiberMonitorSuite, StripedHashtableSuite).

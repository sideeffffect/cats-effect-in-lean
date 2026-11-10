# Cats Effect bug history (CE3 era) — research note

> Source: https://github.com/typelevel/cats-effect/issues?q=label%3A%22%3Abeetle%3A+bug%22 (via `gh issue list --label ":beetle: bug" --state all`), plus `gh search issues` for race / cancel / leak / deadlock / finalizer, plus 3.x release notes
> Collected: 2026-11-10
> Published: Unknown

Own analysis. Data: 156 issues have label `:beetle: bug` (23 open on 2026-11-10); 139 were created 2020-06 or later (CE3 era). Keyword searches: race 111, cancel 200 (capped), leak 70, deadlock 40, finalizer 50 hits. The 3.x release notes contain 101 "Bug Fixes" items in 16 releases (file `cats-effect-3x-release-bug-fixes.md`).

## Rough count of CE3-era bug-labeled issues by component (regex on titles; one issue can count twice)

| Count | Component |
|---|---|
| 35 | IOFiber / cancelation / masking / finalizers / bracket |
| 25 | WorkStealingThreadPool / worker / timers / blocking / pollers |
| 23 | timeout / race / par* combinators |
| 15 | async / cont / callbacks / fromFuture / fromCompletableFuture |
| 11 | Resource (+ memoize, Hotswap) |
| 11 | tracing / IOLocal |
| 10 | Queue / Dequeue / PQueue |
| 9 | Dispatcher |
| 8 | memory leaks |
| 7 | IOApp / shutdown |
| 4 | Supervisor |
| 3 | SyncIO / syncStep; 3 TestControl; 3 Ref/Deferred/AtomicCell; 2 Semaphore/Mutex |

## Bug classes with examples

### A. Cancelation lost-element / lost-wakeup in concurrent data structures (cancel races with offer/take)
- https://github.com/typelevel/cats-effect/issues/4571 (OPEN) Queue.take.timeout(...) loses elements on cancelation — element lost when the fiber running `take.timeout` is canceled.
- https://github.com/typelevel/cats-effect/issues/4483 (OPEN) `Queue#mapK` violates atomicity guarantees — mapK'd ops not wrapped in `uncancelable`, so elements can be lost.
- https://github.com/typelevel/cats-effect/issues/3603 Queue.synchronous may suffer from the "lost item" problem — take canceled at the moment offer completes loses the value.
- https://github.com/typelevel/cats-effect/issues/3998 Cancelling Async queue `take` makes other `take` hang — lost wakeup in the lock-free Async queue.
- https://github.com/typelevel/cats-effect/issues/3187 MPSC race condition in `Queue`.
- https://github.com/typelevel/cats-effect/issues/3554 In theory, waiters can be lost in `Mutex`; https://github.com/typelevel/cats-effect/issues/3564 Async mutex corrupts FIFO.
- https://github.com/typelevel/cats-effect/issues/2920 Harden `Queue#take`'s cancelation properties.

### B. Finalizers skipped, run twice, or run at the wrong time (masking / poll / Resource)
- https://github.com/typelevel/cats-effect/issues/4687 (OPEN) `IO#syncStep` drops `uncancelable` and `onCancel` from the returned IO, so Resource release is skipped (reproduced on 3.7.1).
- https://github.com/typelevel/cats-effect/issues/4627 (OPEN) `Resource.eval` extra cancelation point at the end (contradicts doc "preserves interruptibility of fa").
- https://github.com/typelevel/cats-effect/issues/3474 (OPEN) `cancelable` may leak resources on unsuccessful cancelation.
- https://github.com/typelevel/cats-effect/issues/4488 Finalizers not executed when fiber canceled quickly after start — `start` succeeded but `guarantee` inside never registered; led to Supervisor fix #4500 and proposal #4517 (fork-with-finalizer).
- https://github.com/typelevel/cats-effect/issues/2472 Unexpected finalization of uncancelable resource — led to `allocatedFull`.
- https://github.com/typelevel/cats-effect/issues/3757 `Resource#attempt` holds onto acquired resources even in case of error.
- https://github.com/typelevel/cats-effect/issues/3609 error in bracket finalizer can stop fiber from progressing (`IO.unit.bracket(_ => IO.unit)(_ => throw ...)`).
- https://github.com/typelevel/cats-effect/issues/1736 CE3 IOApp finishes early before all finalizers.
- https://github.com/typelevel/cats-effect/issues/2391 Canceling uncancelable doesn't wait (CE2 vs CE3 bracket semantics).
- https://github.com/typelevel/cats-effect/issues/3306 `flatModify` should be uncancelable.

### C. Timeout / race semantics and resource leaks under timeout
- https://github.com/typelevel/cats-effect/issues/4489 Timeout in 3.6.x caused http4s connection leaks (introduced by timeout change PR #4059; fixed in 3.6.4 by #4625).
- https://github.com/typelevel/cats-effect/issues/4697 (OPEN) `Resource#allocate` that fails produces `reportFailure` under timeout (handled error still reported).
- https://github.com/typelevel/cats-effect/issues/1816 Cancelation deadlock in `IO.race`.
- https://github.com/typelevel/cats-effect/issues/3111 Resource#race: late loser release.
- https://github.com/typelevel/cats-effect/issues/4434 parTraverseN performance problems in presence of errors or cancelations (full rewrite in 3.6.4).
- https://github.com/typelevel/cats-effect/issues/2238 Parallel map2 fails to short-circuit on error.

### D. Async callback / Cont protocol races
- https://github.com/typelevel/cats-effect/issues/3725 (OPEN) 3.5.0 async uncancelable changes are not enforced by laws (registration of `async` became uncancelable; no new law forces it. Note: the existing law `asyncRightIsUncancelableSequencedPure` dates from 2020-12 (before 3.0.0) and only covers the registration effect when the callback was already invoked; it does not state that `async` returning `None` makes the wait uncancelable).
- https://github.com/typelevel/cats-effect/issues/3891 Leaky `fromFutureCancelable`; https://github.com/typelevel/cats-effect/issues/2903 `fromCompletableFuture` should block if cancelation fails.
- https://github.com/typelevel/cats-effect/issues/4505 (OPEN) OutOfMemoryError not propagated when IO originates from CompletableFuture.
- https://github.com/typelevel/cats-effect/issues/4047 (OPEN, not labeled bug) unsafeToFutureCancelable's cancel future completes before setting the result future's cancellation state.
- https://github.com/typelevel/cats-effect/issues/3940 `CallbackStack#pack` can double-count removals when called concurrently; https://github.com/typelevel/cats-effect/issues/3935 IODeferred's CallbackStack becomes unboundedly large; https://github.com/typelevel/cats-effect/issues/3359 memory leak in CallbackStack (3.4.4).
- https://github.com/typelevel/cats-effect/issues/2858 IO.syncStep leads to double execution; https://github.com/typelevel/cats-effect/issues/4337 syncStep StackOverflowError.

### E. Dispatcher / Supervisor lifecycle (close vs. submit races, leaks)
- https://github.com/typelevel/cats-effect/issues/4490 Supervisor leaks memory when fibers are canceled quickly (fixed 3.6.4, #4500).
- https://github.com/typelevel/cats-effect/issues/3862 Supervisor accepts tasks after it is closed; https://github.com/typelevel/cats-effect/issues/3394 Closed Supervisor strangeness.
- https://github.com/typelevel/cats-effect/issues/3945 sequential dispatcher: race condition in release step causes disorder; https://github.com/typelevel/cats-effect/issues/3363 Dispatcher.sequential(await = true) can hang on release; https://github.com/typelevel/cats-effect/issues/3898 Cancelation hangs in Dispatcher#unsafeToFutureCancelable; https://github.com/typelevel/cats-effect/issues/3501 closing a Dispatcher from within it.
- https://github.com/typelevel/cats-effect/issues/4069 (OPEN) Queued but unstarted work on Dispatcher.sequential should be cancelable.
- https://github.com/typelevel/cats-effect/issues/4104 (OPEN, not labeled bug) TestControl + Dispatcher == deadlock.

### F. Scheduler (WorkStealingThreadPool) liveness: lost timers, starvation, hangs, spin loops
- https://github.com/typelevel/cats-effect/issues/4674 (OPEN) LocalQueue.enqueueBatch spins forever on a dangling steal tag; queue becomes permanently unstealable.
- https://github.com/typelevel/cats-effect/issues/4628 (OPEN) Integrated Selector: a ready I/O event can go undelivered for seconds while workers sit idle.
- https://github.com/typelevel/cats-effect/issues/3422 Rare runtime condition in which timers are lost; https://github.com/typelevel/cats-effect/issues/3948 far-future task blocks concurrently scheduled tasks; https://github.com/typelevel/cats-effect/issues/4228 external queue can starve timers/pollers; https://github.com/typelevel/cats-effect/issues/4229 workers shouldn't schedule local tasks while parked; https://github.com/typelevel/cats-effect/issues/4225 I/O polling hangs when computeWorkerThreadCount = 1; https://github.com/typelevel/cats-effect/issues/3548 hanging after IO.blocking in 3.5.0 RC; https://github.com/typelevel/cats-effect/issues/1327 WSTP not parking.
- https://github.com/typelevel/cats-effect/issues/3907 (OPEN) ArrayIndexOutOfBoundsException in ByteStack.

### G. Test model gaps
- https://github.com/typelevel/cats-effect/issues/3430 (OPEN) PureConc (the pure reference model in kernel-testkit) not running finalizers.
- https://github.com/typelevel/cats-effect/issues/2552 (OPEN) `raceOutcome` is not tested directly.
- https://github.com/typelevel/cats-effect/issues/2778 (OPEN) Laws testing with Arbitrary[IO[A]] from TestInstances.
- https://github.com/typelevel/cats-effect/issues/3899 (OPEN, not labeled bug) "We need to be more explicit about the Cats Effect memory model".
- https://github.com/typelevel/cats-effect/issues/4524 (OPEN) TestContext on Scala Native is not thread-safe (worked around in 3.7.1, #4569).

## Observations

1. The densest, still-open bug class is "cancelation at the wrong point loses an element or skips a finalizer" (A, B). These are about the uncancelable/poll/onCancel algebra composed with Ref/Deferred state machines. They are exactly the kind of property a formal model can state: "every element offered is either taken or still in the queue, under any cancelation interleaving".
2. Many bugs sit in DERIVED combinators (timeout, race, parTraverseN, Resource.eval, mapK, syncStep, cancelable, Dispatcher, Supervisor), not in the run-loop primitives. The derived code is written in terms of the kernel typeclasses, so a model of the typeclass semantics plus a faithful transcription of the combinator suffices.
3. Laws do not cover GenConcurrent (no GenConcurrentLaws) and std data structures have no laws at all; correctness of Queue/Semaphore/Mutex/Dispatcher/Supervisor is checked only by example tests and stress tests.
4. Lock-free runtime structures (LocalQueue, CallbackStack, ContState, Async Queue, LockQueue) have repeated bugs. These need a weak-memory / interleaving model; harder in Lean, but the protocols are small.

## Appendix: all issues labeled `:beetle: bug` (number, state O/C, created, title) as returned by gh on 2026-11-10

- #4697 O 2026-10-06 `Resource#allocate` that fails produces `reportFailure` under timeout
- #4687 O 2026-09-18 `IO#syncStep` drops `uncancelable` and `onCancel` from the returned `IO`, so `Resource` release is skipped
- #4674 O 2026-08-27 `LocalQueue.enqueueBatch` spins forever on a dangling steal tag, and the queue becomes permanently unstealable
- #4644 O 2026-07-26 TracingPlatform performs undefined behavior in JS that makes it unusable in Wasm
- #4628 O 2026-06-29 Integrated `Selector`: a ready I/O event can go undelivered for seconds while worker threads sit idle
- #4627 O 2026-06-28 `Resource.eval` extra cancellation point
- #4571 O 2026-03-19 Queue.take.timeout(...) loses elements on cancelation
- #4532 C 2025-12-16 `[[ExitCode]]` scaladoc reference is broken
- #4527 O 2025-11-23 SIGPIPE during tests on scala-native
- #4524 O 2025-11-18 `TestContext` on scala-native is not threadsafe
- #4509 C 2025-10-16 3.7.0-RC1 broken with SN 0.5.9
- #4505 O 2025-10-13 `OutOfMemoryError` not propagated when `IO` originates from `CompletableFuture`
- #4490 C 2025-09-22 Supervisor leaks memory when fibers are canceled quickly
- #4489 C 2025-09-18 Possible Issue with Timeout in Cats-Effect 3.6.x which resulted in Http4s Connection leaks
- #4483 O 2025-09-05 `Queue#mapK` violates atomicity guarantees
- #4448 C 2025-07-19 Poisoned pod, extremely slow, weird thread counts
- #4434 C 2025-07-08 parTraverseN performance problems in presence of errors or other cancellations
- #4367 C 2025-04-09 `IOFiber#toString` throws NPE if tracing is `none`
- #4337 C 2025-03-31 IO.syncStep(n).unsafeRunSync() fails with StackOverflowError
- #4329 C 2025-03-28 Allow `IO.onError` to be passed a total function
- #4328 C 2025-03-28 The Polling System CPU overhead
- #4306 C 2025-03-19 `onNonMainThreadDetected` always triggers on graalvm-community:24.0.0
- #4300 C 2025-03-16 `Random#betweenDouble` and `#betweenFloat` overflow
- #4293 O 2025-03-05 `cats.effect.std.SupervisorSuite.async - restart / cancel race` timeout
- #4291 C 2025-03-05 `DeferredJVMParallelism4Tests.Deferred — issue #380: with cooperative light async boundaries` failure
- #4283 C 2025-02-28 Private type in a public signature
- #4229 C 2025-01-07 Workers shouldn't schedule local tasks while parked
- #4228 C 2025-01-06 External queue can starve timers/pollers
- #4225 C 2025-01-05 I/O polling hangs when `computeWorkerThreadCount = 1`
- #4166 C 2024-11-12 Propagate Java thread interruption in `unsafeRunSync` et al.
- #4093 C 2024-06-26 Potential inconsistency between joinWithNever and docs
- #4069 O 2024-04-30 Queued but unstarted work on `Dispatcher.sequential` should be cancelable
- #4066 C 2024-04-25 When `IORuntime.global` shuts down, it doesn't shut down the WSTP
- #4058 C 2024-04-18 IO.onError is inconsistent with ApplicativeError
- #4055 O 2024-04-17 unsafeToFuture fails to raise a second InterruptedException if the exception is handled and retried
- #4014 O 2024-02-23 More efficient monitoring of fibers on virtual threads
- #4002 C 2024-02-17 `IO#asyncCheckAttempt` is inconsistent with `Async#asyncCheckAttempt`
- #3998 C 2024-02-13 Cancelling `Async` queue `take` makes other `take` hang
- #3948 C 2024-01-12 Delaying a task to be run far into the future can prevent concurrently scheduled tasks from running
- #3945 C 2024-01-11 sequential dispatcher: race condition in release `step` causes disorder
- #3940 C 2024-01-09 `CallbackStack#pack` can double-count removals when called concurrently
- #3935 C 2024-01-08 `IODeferred`'s `CallbackStack` becomes unboundedly large
- #3929 C 2024-01-03 Leaking fiber monitors when running in custom IORuntime using JDK 21 virtual threads 
- #3907 O 2023-11-26 `ArrayIndexOutOfBoundsException` in `ByteStack`
- #3898 C 2023-11-17 Cancelation hangs in `Dispatcher#unsafeToFutureCancelable`
- #3891 C 2023-11-09 Leaky `fromFutureCancelable`
- #3862 C 2023-10-02 `Supervisor` accepts tasks after it is closed
- #3840 C 2023-09-20 Hotswap#get scaladoc/impl mismatch
- #3827 C 2023-09-14 Native `IORuntime.global` causes `RPCCore$ClosedException` when used for `munitExecutionContext`
- #3802 C 2023-08-31 Prevent `Hotswap#get` from acquiring a lock when there is no `Resource` present
- #3776 C 2023-08-06 `Dispatcher` "raise an error on leaked runner" flake
- #3767 C 2023-08-02 `IO.raiseError(...)` doesn't immediately surface fatal errors
- #3757 C 2023-07-18 `Resource#attempt` holds onto acquired resources even in case of error
- #3609 C 2023-05-11 error in bracket finalizer can stop fiber from progressing.
- #3603 C 2023-05-06 `Queue.synchronous` may suffer from the "lost item" problem
- #3587 C 2023-05-02 `synchronous queue should not lose takers when offerer is canceled and there are no other takers` flake
- #3576 C 2023-04-28 `steal timers` test seems to be legitimately failing
- #3564 C 2023-04-26 `Async` mutex corrupts FIFO on happy(ish) path
- #3554 C 2023-04-24 In theory, waiters can be lost in `Mutex`
- #3548 C 2023-04-22 Hanging following `IO.blocking(...)` calls in v3.5.0 RC3 and RC4
- #3534 C 2023-04-15 `Dispatcher` internal await is uncancelable in 3.5.x
- #3501 C 2023-03-18 Closing a `Dispatcher` from within it seems to enter invalid state (?)
- #3474 O 2023-03-01 `cancelable` may leak resources on unsuccessful cancelation
- #3468 C 2023-02-28 `unsafeRunAndForget()` doesn't log errors
- #3430 O 2023-02-17 PureConc not running finalizers
- #3427 C 2023-02-17 NullPointerException when `blockedThreadDetectionEnabled` is set to `true`
- #3423 C 2023-02-16 `IO.println` never returns for long strings in nodejs runtime
- #3422 C 2023-02-16 Rare runtime condition in which timers are lost
- #3394 C 2023-02-02 Closed `Supervisor` strangeness
- #3392 C 2023-01-31 CPU starvation causes problems with scheduling fairness (compared to CE2)
- #3363 C 2023-01-16 `Dispatcher.sequential(await = true)` can hang on release
- #3359 C 2023-01-13 Memory leak in v3.4.4 for cats.effect.CallbackStack
- #3349 C 2023-01-06 `isDeadLocked` on `TestControl` returns true if result is available
- #3348 C 2023-01-06 `memoize` doc and implementation out of sync
- #3306 C 2022-12-05 `flatModify` should be uncancelable
- #3283 C 2022-11-25 "Only Once" example hangs
- #3279 C 2022-11-24 AtomicCell issue
- #3268 O 2022-11-18 Failed to register Cats Effect CPU starvation MBean
- #3187 C 2022-10-03 MPSC race condition in `Queue`
- #3140 C 2022-09-11 Custom `IOApp#runtime` is not installed as `IORuntime.global`
- #3094 C 2022-07-12 Error Building Native Image on 3.3.13
- #3076 C 2022-07-04 Handle `ClosedByInterruptException` in `interruptible`
- #3073 C 2022-07-04 Application locks up and fiber dumps don't work anymore
- #3051 C 2022-06-26 Unable to compile an hello world example with GraalVM native-image on any 3.3.x using `sbt-native-image`
- #3006 C 2022-05-24 Using the finalizer from `createDefaultComputeThreadPool` inside IO hangs subsequent `unsafeRunSync`s even on unrelated `IORuntime`s
- #2982 C 2022-05-07 Wrong async stacktrace
- #2973 C 2022-04-27 High-precision time test broken on Firefox?
- #2962 C 2022-04-14 using timeout prints stack trace to console if effect throws exception
- #2961 C 2022-04-14 `IO#unsafeRunAsync` and `unsafeRunAndForget` eat fatal errors
- #2927 C 2022-03-31 `IO` swallows fatal errors on JS
- #2920 C 2022-03-26 Harden `Queue#take`'s cancelation properties
- #2903 C 2022-03-24 `Async.fromCompletableFuture` should block if cancelation fails
- #2902 C 2022-03-24 Random.javaSecuritySecureRandom doesn't link on Scala.js
- #2871 C 2022-03-11 MBean `BlockedWorkerThreadCount` can be negative
- #2865 C 2022-03-08 UUIDGen does not use Random[F]
- #2858 C 2022-03-07 IO.syncStep leads to double execution
- #2816 C 2022-02-09 `Thunk.asFunction0` is broken in Scala 3 nightly
- #2778 O 2022-01-25 Laws testing with Arbitrary[IO[A]] from TestInstances
- #2766 C 2022-01-20 Random.javaUtilConcurrentThreadLocalRandom not thread-local
- #2745 C 2022-01-11 NonDaemonThreadLogger and SBT 1.6.x
- #2742 O 2022-01-10 Wrong stack trace with timeout
- #2730 C 2022-01-04 `Uncaught TypeErrror` in browser console after upgrading to 3.3.3
- #2728 C 2022-01-03 Memoized effect hangs for `Concurrent` instances of monad transformers
- #2720 C 2022-01-01 `FatalErrorUnsafeRun` test is now nondeterministic
- #2706 C 2021-12-31 Errors raised in unforked `IOApp`s terminate sbt 1.6.x
- #2704 C 2021-12-30 version 3.3.1 doesn't properly terminate on error in SBT
- #2634 C 2021-12-07 [3.3.0] Performance regression
- #2608 C 2021-11-29 `cats` anywhere in the package triggers filtering?
- #2606 C 2021-11-29 Duplicated fibers in fiber dump
- #2586 C 2021-11-27 `System.exit(1)` vs `Runtime#halt(1)` for fatal exceptions in `IOApp`
- #2574 C 2021-11-23 MBean exception during shutdown of example
- #2552 O 2021-11-16 `raceOutcome` is not tested (directly)
- #2551 C 2021-11-16 Fix stack trace filtering for Macrotask Executor
- #2472 C 2021-10-27 Unexpected finalization of uncancelable resource
- #2425 C 2021-10-18 `TraceSpec` is broken on WSLv2
- #2388 C 2021-10-04 JS `TimeoutOverflowWarning`
- #2320 C 2021-09-07 `Spawn[F[_]].background(fa)` does not evaluate `fa` under `TestContext`
- #2304 C 2021-09-04 `HelperThread` gives up if there's no immediate work available on the pool
- #2269 C 2021-08-28 NPE in catsEffect3RuntimePingPong
- #2251 C 2021-08-21 Sbt main process cancelation seems broken with timers
- #2244 C 2021-08-18 `timeout` eagerly creates `TimeoutException`
- #2238 C 2021-08-16 Parallel map2/map2Eval fails to short-circuit on error
- #2197 C 2021-08-04 Exception thrown when using attempt 
- #2095 C 2021-07-03 [CE3] Kleisli Stack safety
- #1995 C 2021-05-24 Weird fairness/scheduling issue
- #1918 C 2021-04-20 Initialization error when using unsafe.implicits.global within IOApp
- #1818 C 2021-03-24 Global runtime installation mechanism not working in Scastie
- #1816 C 2021-03-24 Cancelation deadlock in `IO.race`
- #1736 C 2021-02-25 CE3 IOApp finishes early before all finalizers
- #1714 C 2021-02-19 Report error somewhere if Dispatcher is closed with pending tasks
- #1548 C 2020-12-26 Side channel report on failed handleErrorWith
- #1535 C 2020-12-23 Uncaught error within bracketFull
- #1521 C 2020-12-19 Flaky Resource test
- #1513 O 2020-12-17 Over-aggressive Stack Trace Enhancement
- #1494 C 2020-12-10 Finalizer error semantics
- #1380 C 2020-11-02 AsyncBenchmark.race deadlocks
- #1332 C 2020-10-19 Dispatcher cancellation backpressure bug
- #1327 C 2020-10-18 Work stealing thread pool not parking
- #1106 C 2020-08-19 Benchmarks failing on series/2.x
- #746 C 2020-01-10 Deadlock in IOApp when calling System.exit
- #721 C 2019-12-08 IO's `Fiber#cancel` doesn't wait for finalizers if they already started running
- #692 C 2019-11-12 OutOfMemoryError in computation performed by Blocker doesn't halt the JVM
- #593 C 2019-07-27 TestContext should NOT have a deterministic mode
- #529 C 2019-05-11 IO#unsafeRunSync erroneously fails on JavaScript
- #382 C 2018-09-29 Bracket's acquire should not be uncancelable by law
- #375 C 2018-09-25 ConcurrentLaws.acquireIsNotCancelable unreasonable assumption about Fiber.cancel
- #330 C 2018-08-30 ConcurrentLaws Spurious Test Failures
- #316 C 2018-08-21 [1.0.0-RC3] StackOverflowError
- #276 C 2018-06-30 Bracket related laws in SyncLaws overreaching
- #181 C 2018-04-11 Properly deal with InterruptedException on the JVM
- #139 C 2018-03-07 Sync[State[F, S, ?]] instance is stack unsafe in left associative binds
- #129 C 2018-02-24 EffectLaws.runAsyncRaiseErrorProducesLeftIO assumes synchronous execution in F.runAsync(F.raiseError(e))
- #128 C 2018-02-24 EffectLaws.runAsyncPureProducesRightIO assumes synchronous execution in F.runAsync(F.pure(a))
- #127 C 2018-02-24 EffectLaws.repeatedCallbackIgnored assumes F.delay is synchronous
- #89 C 2017-11-27 Issues with recursion
- #82 C 2017-11-06 Problem with SyncLaws.repeatedAsyncEvaluationNotMemoized

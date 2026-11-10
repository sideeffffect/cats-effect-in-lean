# Cats Effect 3.x release notes: all Bug Fixes sections (extracted)

> Source: https://github.com/typelevel/cats-effect/releases (via gh api repos/typelevel/cats-effect/releases)
> Collected: 2026-11-10
> Published: Unknown

Extracted verbatim: the "### Bug Fixes" section of every v3.* GitHub release that has one (16 releases, 101 items). Older 3.x releases used a different notes format without that heading and are not included here; see the full releases page.

## v3.7.1 | 2026-08-23T19:19:52Z | prerelease=false
* Fix memory leak in `Supervisor` internal state by @durban in https://github.com/typelevel/cats-effect/pull/4500
* Fix scaladoc links in IOApp by @durban in https://github.com/typelevel/cats-effect/pull/4562
* Workaround #4524 by synchronizing tasks set by @armanbilge in https://github.com/typelevel/cats-effect/pull/4569
* Fix issue #4489 by @durban in https://github.com/typelevel/cats-effect/pull/4625
* Fix `Ticker` @implicitNotFound message to reference testkit-available API by @mvanhorn in https://github.com/typelevel/cats-effect/pull/4592
* Fix ownsPoller and ownsTimers for blocking threads by @durban in https://github.com/typelevel/cats-effect/pull/4631

## v3.6.4 | 2026-08-22T22:15:05Z | prerelease=false
* Fix memory leak in `Supervisor` internal state by @durban in https://github.com/typelevel/cats-effect/pull/4500
* Fix scaladoc links in IOApp by @durban in https://github.com/typelevel/cats-effect/pull/4562
* Fix issue #4489 by @durban in https://github.com/typelevel/cats-effect/pull/4625

## v3.7.0 | 2026-03-08T19:46:47Z | prerelease=false
* Don't expose private WSTP type in method signature by @armanbilge in https://github.com/typelevel/cats-effect/pull/4290
* Fix wstp shutdown interrupt (3.x edition) by @djspiewak in https://github.com/typelevel/cats-effect/pull/4344
* Make `IOFiber#{_join,_cancel}` volatile on Native by @durban in https://github.com/typelevel/cats-effect/pull/4400
* Removed `IORuntimeBuilder#addPoller` on Scala.js by @djspiewak in https://github.com/typelevel/cats-effect/pull/4419
* Use _exit instead of System.exit in fatal cases by @djspiewak in https://github.com/typelevel/cats-effect/pull/4428
* Make the heap in `TimerHeap` volatile on native by @armanbilge in https://github.com/typelevel/cats-effect/pull/4443

## v3.7.0-RC1 | 2025-07-30T20:13:50Z | prerelease=true
* Don't expose private WSTP type in method signature by @armanbilge in https://github.com/typelevel/cats-effect/pull/4290
* Make `IOFiber#{_join,_cancel}` volatile on Native by @durban in https://github.com/typelevel/cats-effect/pull/4400
* Removed `IORuntimeBuilder#addPoller` on Scala.js by @djspiewak in https://github.com/typelevel/cats-effect/pull/4419
  + As a brief callout, this change actually represents a **binary-breaking change** relative to Cats Effect 3.6.x on Scala.js! We almost universally avoid doing this, but in this case the type signature exposure was entirely accidental and the method never worked, so anyone who wrote code which called that method on Scala.js would have simply had broken code. For this reason, we felt justified in the binary break.
* Make the heap in `TimerHeap` volatile on native by @armanbilge in https://github.com/typelevel/cats-effect/pull/4443
* Fix wstp shutdown interrupt (3.x edition) by @djspiewak in https://github.com/typelevel/cats-effect/pull/4344
* Use `_exit` instead of System.exit in fatal cases by @djspiewak in https://github.com/typelevel/cats-effect/pull/4428
* Fix source compatibility with Scala 3.6 by @mbovel in https://github.com/typelevel/cats-effect/pull/4381

## v3.6.3 | 2025-07-23T00:12:07Z | prerelease=false
* Fix the spinlock from #4377 and probably also fix #4448 by @durban in https://github.com/typelevel/cats-effect/pull/4449


**Full Changelog**: https://github.com/typelevel/cats-effect/compare/v3.6.2...v3.6.3

## v3.6.2 | 2025-07-08T19:04:18Z | prerelease=false
* Make `IO#syncStep` interpreter stack-safe by @pantShrey in https://github.com/typelevel/cats-effect/pull/4352
* Set `mayInterruptIfRunning = true` when canceling `CompletableFuture` by @istreeter in https://github.com/typelevel/cats-effect/pull/4375
* Retrieve suspended fiber count directly through the WSTP by @iRevive in https://github.com/typelevel/cats-effect/pull/4406
* Handle `EPOLLHUP` in `EpollSystem` by @rahulrangers in https://github.com/typelevel/cats-effect/pull/4422
* Dynamically bypass selector polling if no I/O events are present by @djspiewak in https://github.com/typelevel/cats-effect/pull/4377
* Fix #4367: Wrap tracingEvents in Option to handle NPE by @pantShrey in https://github.com/typelevel/cats-effect/pull/4380
* PoC for not using a CHM in #4388 by @durban in https://github.com/typelevel/cats-effect/pull/4426
* Fix #4382: Fix thread leak in WSTP by replacing LinkedTransferQueue with SynchronousQueue and ConcurrentHashMap by @pantShrey in https://github.com/typelevel/cats-effect/pull/4388
* Update the main thread detection logic by @iRevive in https://github.com/typelevel/cats-effect/pull/4407

## v3.6.1 | 2025-04-07T22:01:10Z | prerelease=false
* Also interrupt pollers when shutting down the WSTP by @durban in https://github.com/typelevel/cats-effect/pull/4340
* Make deprecated `IO.onError` package private by @CJSmith-0141 in https://github.com/typelevel/cats-effect/pull/4343

## v3.6.0 | 2025-03-23T17:54:48Z | prerelease=false
* Join worker threads on pool shutdown by @armanbilge in https://github.com/typelevel/cats-effect/pull/3794
* Remove `IORuntime` from `allRuntimes` on shutdown by @RafalSierkiewicz in https://github.com/typelevel/cats-effect/pull/4090
* Make `IO#onError` consistent with `ApplicativeError` by @lenguyenthanh in https://github.com/typelevel/cats-effect/pull/4121
* Implement a safer `Resource.attempt` which releases acquired resource(s) in case of error by @lenguyenthanh in https://github.com/typelevel/cats-effect/pull/4128
* Removed implicit modifiers on deprecated instance to avoid unavoidable warnings by @djspiewak in https://github.com/typelevel/cats-effect/pull/4180
* Check target array length before allocating by @counter2015 in https://github.com/typelevel/cats-effect/pull/4159
* use worker thread index at startup by @biochimia in https://github.com/typelevel/cats-effect/pull/4197
* Blocked thread detection fixes by @biochimia in https://github.com/typelevel/cats-effect/pull/4195
* Fix MapRef.fromSeqRefs vulnerability by @underskyer in https://github.com/typelevel/cats-effect/pull/4208
* Fixed off-by-one error in other index selection by @djspiewak in https://github.com/typelevel/cats-effect/pull/4214
* Report non-fatal `Runnable` failures on `MainThread` EC by @armanbilge in https://github.com/typelevel/cats-effect/pull/4223
* Always report timers/events when worker unparked by @armanbilge in https://github.com/typelevel/cats-effect/pull/4227
* Introduce `PollResult`, `PollingSystem#processReadyEvents` by @armanbilge in https://github.com/typelevel/cats-effect/pull/4230
* Shutdown the runtime only when unforked by @armanbilge in https://github.com/typelevel/cats-effect/pull/4234
* Restore `ArrayBlockingQueue` for worker-to-blocking state transfer by @armanbilge in https://github.com/typelevel/cats-effect/pull/4255
* Refactor `WorkerThread` runloop; avoid pathological starvation of pollers by @armanbilge in https://github.com/typelevel/cats-effect/pull/4247
* Transfer tick state when replacing a blocked thread by @armanbilge in https://github.com/typelevel/cats-effect/pull/4264
* `WorkStealingPoolMetrics` -> `WorkStealingThreadPoolMetrics` by @armanbilge in https://github.com/typelevel/cats-effect/pull/4271
* Run finalizers in `IO#unsafeRunTimed` by @armanbilge in https://github.com/typelevel/cats-effect/pull/4279
* Create `UnsafeNonFatal` for use in the fiber runtime by @kapunga in https://github.com/typelevel/cats-effect/pull/4263
* Fix betweenDouble/betweenFloat by @durban in https://github.com/typelevel/cats-effect/pull/4302
* SelectorSystem - properly record operation metrics by @iRevive in https://github.com/typelevel/cats-effect/pull/4307

## v3.6.0-RC2 | 2025-02-28T02:26:33Z | prerelease=true
* Report non-fatal `Runnable` failures on `MainThread` EC by @armanbilge in https://github.com/typelevel/cats-effect/pull/4223
* Always report timers/events when worker unparked by @armanbilge in https://github.com/typelevel/cats-effect/pull/4227
* Introduce `PollResult`, `PollingSystem#processReadyEvents` by @armanbilge in https://github.com/typelevel/cats-effect/pull/4230
* Shutdown the runtime only when unforked by @armanbilge in https://github.com/typelevel/cats-effect/pull/4234
* Restore `ArrayBlockingQueue` for worker-to-blocking state transfer by @armanbilge in https://github.com/typelevel/cats-effect/pull/4255
* Refactor `WorkerThread` runloop; avoid pathological starvation of pollers by @armanbilge in https://github.com/typelevel/cats-effect/pull/4247
* Transfer tick state when replacing a blocked thread by @armanbilge in https://github.com/typelevel/cats-effect/pull/4264
* `WorkStealingPoolMetrics` -> `WorkStealingThreadPoolMetrics` by @armanbilge in https://github.com/typelevel/cats-effect/pull/4271
* Run finalizers in `IO#unsafeRunTimed` by @armanbilge in https://github.com/typelevel/cats-effect/pull/4279
* Create `UnsafeNonFatal` for use in the fiber runtime by @kapunga in https://github.com/typelevel/cats-effect/pull/4263

## v3.6.0-RC1 | 2024-12-28T00:30:08Z | prerelease=true
* Join worker threads on pool shutdown by @armanbilge in https://github.com/typelevel/cats-effect/pull/3794
* Remove `IORuntime` from `allRuntimes` on shutdown by @RafalSierkiewicz in https://github.com/typelevel/cats-effect/pull/4090
* Make `IO#onError` consistent with `ApplicativeError` by @lenguyenthanh in https://github.com/typelevel/cats-effect/pull/4121
* Implement a safer `Resource.attempt` which releases acquired resource(s) in case of error by @lenguyenthanh in https://github.com/typelevel/cats-effect/pull/4128
* Removed implicit modifiers on deprecated instance to avoid unavoidable warnings by @djspiewak in https://github.com/typelevel/cats-effect/pull/4180
* Check target array length before allocating by @counter2015 in https://github.com/typelevel/cats-effect/pull/4159
* use worker thread index at startup by @biochimia in https://github.com/typelevel/cats-effect/pull/4197
* Blocked thread detection fixes by @biochimia in https://github.com/typelevel/cats-effect/pull/4195
* Fix MapRef.fromSeqRefs vulnerability by @underskyer in https://github.com/typelevel/cats-effect/pull/4208
* Fixed off-by-one error in other index selection by @djspiewak in https://github.com/typelevel/cats-effect/pull/4214

## v3.5.6 | 2024-11-19T18:00:50Z | prerelease=false
* Fix `size` updates in `Dequeue` state machine by @armanbilge, @reardonj in https://github.com/typelevel/cats-effect/pull/4171

## v3.5.5 | 2024-10-27T19:24:37Z | prerelease=false
* Fix #4066: shut down executors when `IORuntime.global` shuts down by @durban in https://github.com/typelevel/cats-effect/pull/4067
* Use `IOApp#reportFailure` instead of `printStackTrace()` for blocking EC by @fredfp in https://github.com/typelevel/cats-effect/pull/4044
* Fix `cancelable` to `guarantee` cancelation by @armanbilge in https://github.com/typelevel/cats-effect/pull/4118

## v3.5.4 | 2024-03-05T21:45:25Z | prerelease=false
* Fix a few Supervisor bugs by @durban in https://github.com/typelevel/cats-effect/pull/3972
* Clear the CallbackStack more aggressively by @samspills in https://github.com/typelevel/cats-effect/pull/3973
* Fix issue #3998 by @durban in https://github.com/typelevel/cats-effect/pull/4001
* Fix issue #4002 by @durban in https://github.com/typelevel/cats-effect/pull/4003
* Introduce `WeakList` and use in `FiberMonitor` by @armanbilge in https://github.com/typelevel/cats-effect/pull/3964

## v3.5.3 | 2024-01-15T22:37:22Z | prerelease=false
* Fix cancelation leak in `fromFuture`, `fromFutureCancelable` by @TimWSpence in https://github.com/typelevel/cats-effect/pull/3892
* Fix #3898 for `Dispatcher.parallel` by @durban in https://github.com/typelevel/cats-effect/pull/3900
* Immediately surface fatal errors in `IO.raiseError` by @scott-thomson239 in https://github.com/typelevel/cats-effect/pull/3811
* Fix off-by-1 in `CallbackStack#pack` by @armanbilge in https://github.com/typelevel/cats-effect/pull/3936
* Prevent `Hotswap#get` from acquiring a lock when there is no `Resource` present by @josgarmar28 in https://github.com/typelevel/cats-effect/pull/3922
* Refactor `CallbackStack` based on new "pack locking" strategy by @armanbilge, @samspills, @mernst-github in https://github.com/typelevel/cats-effect/pull/3943

## v3.5.2 | 2023-09-27T22:36:55Z | prerelease=false
* Fix `Hotswap#get` being blocked by `Hotswap#swap` by @forkedcancel in https://github.com/typelevel/cats-effect/pull/3800
* Acquire exclusive lock before finalizing `Hotswap` by @armanbilge in https://github.com/typelevel/cats-effect/pull/3841

## v3.5.1 | 2023-06-24T19:20:26Z | prerelease=false
* Fix issue #3589 by @durban in https://github.com/typelevel/cats-effect/pull/3622
* Don't use `object` for `executeBatchTaskRunnable` by @armanbilge in https://github.com/typelevel/cats-effect/pull/3642
* Catch exceptions in IOCont by @durban in https://github.com/typelevel/cats-effect/pull/3670
* Directly get secure random data to array on native by @armanbilge in https://github.com/typelevel/cats-effect/pull/3678
* Document that signals don't work for fiber dumps on JDK8 by @armanbilge in https://github.com/typelevel/cats-effect/pull/3680
* Fix `queueMicrotask` polyfill by @armanbilge in https://github.com/typelevel/cats-effect/pull/3693
* Cache `now` in `WorkerThread` in states 4-63 by @djspiewak in https://github.com/typelevel/cats-effect/pull/3690
* Dispatcher: remove `alive` in favour of nullifying queues by @samspills in https://github.com/typelevel/cats-effect/pull/3701

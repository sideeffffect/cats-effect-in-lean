# Cats Effect v3.5.0 release notes (async cancelation semantics change)

> Source: https://github.com/typelevel/cats-effect/releases/tag/v3.5.0
> Collected: 2026-11-10
> Published: 2023-05-12

This is the forty-fifth release in the Cats Effect 3.x lineage. It is fully binary compatible with every 3.x release.

## ⚠️  Important note

This release contains some changes that may be semantically breaking. If you're using [fs2](https://github.com/typelevel/fs2/), [http4s](https://github.com/http4s/http4s/), or other libraries from the ecosystem, make sure you've upgraded to versions of these libraries that are compatible with this release (for fs2, that's [3.7.0](https://github.com/typelevel/fs2/releases/tag/v3.7.0), for http4s it's [0.23.19](https://github.com/http4s/http4s/releases/tag/v0.23.19))!

Additionally, if you're using methods like `fromFuture`, make sure you're aware of the major changes to `async`, described in these release notes.

---

This is an incredibly exciting release! 3.5.0 represents the very first steps towards a fully [integrated runtime](https://github.com/typelevel/cats-effect/discussions/3070), with support for timers (`IO.sleep`) built directly into the Cats Effect fiber runtime. This considerably increases performance for existing Cats Effect applications, but particularly those which rely more heavily on native `IO` concurrency (e.g. Http4s Ember will see more benefits than Http4s Blaze).

Additionally, we've taken the opportunity presented by a minor release to fix some breaking semantic issues within some of the core `IO` functionality, particularly related to `async`. For most applications this should be essentially invisible, but it closes a long-standing loophole in the cancelation and backpressure model, ensuring a greater degree of safety in Cats Effect's guarantees.

## Major Changes

Despite the deceptively short list of merged pull requests, this release contains an unusually large number of significant changes in runtime semantics. The changes in `async` cancelation (and particularly the implications on `async_`) are *definitely* expected to have user-facing impact, potentially breaking existing code in subtle ways. **If you have any code which uses `async_` (or `async`) directly, you should read this section very carefully and potentially make the corresponding changes.**

### `async` Cancelation Semantics

The `IO.async` (and correspondingly, `Async#async`) constructor takes a function which returns a value of type `IO[Option[IO[Unit]]]`, with the `Some` case indicating the finalizer which should be invoked if the fiber is canceled while asynchronously suspended at this precise point, and `None` indicating that there is no finalizer for the current asynchronous suspension. This mechanism is most commonly used for "unregister" functions. For example, consider the following reimplementation of the `sleep` constructor:

```scala
def sleep(time: FiniteDuration, executor: ScheduledExecutorService): IO[Unit] =
  IO.async[Unit] { cb =>
    IO {
      val f = executor.schedule(() => cb(Right(())), time.toNanos, TimeUnit.NANOSECONDS)
      Some(IO(f.cancel()))
    }
  }
```

In the above, the `IO` returned from `sleep` will suspend for `time`. If its fiber is canceled, the `f.cancel()` function will be invoked (on `ScheduledFuture`), which in turn removes the `Runnable` from the `ScheduledExecutorService`, avoiding memory leaks and such. If we had instead returned `None` from the registration effect, there would have been no finalizer and no way for fiber cancelation to clean up the stray `ScheduledFuture`.

The entirety of Cats Effect's design is prescriptively oriented around *safe* cancelation. If Cats Effect cannot guarantee that a resource is safely released, it will prevent cancelation from short-circuiting until execution proceeds to a point at which all finalization is safe. This design does have some tradeoffs (it can lead to deadlocks in poorly behaved programs), but it has the helpful outcome of strictly avoiding resource leaks, either due to incorrect finalization or circumvented backpressure.

...except in `IO.async`. Prior to 3.5.0, defining an `async` effect without a finalizer (i.e. producing `None`) resulted in an effect which could be canceled *unconditionally*, without the invocation of any finalizer. This was most seriously felt in the `async_` convenience constructor, which always returns `None`. Unfortunately, this semantic is very much the wrong default. It makes the assumption that the *normal* case for `async` is that the callback just cleans itself up (somehow) and no unregistration is possible or necessary. **In almost all cases, the opposite is true.**

It is exceptionally rare, in fact, for an `async` effect to *not* have an obvious finalizer. By defining the default in this fashion, Cats Effect made it very easy to engineer resource leaks and backpressure loss. This loophole is now closed, both in the `IO` implementation and in the laws which govern its behavior.

As of 3.5.0, the following is now considered to be *uncancelable*:

```scala
IO.async[A] { cb =>
  IO {
    // ...
    None    // we aren't returning a finalizer
  }
}
```

Previously, the above was cancelable without any caveats. Notably, this applies to *all* uses of the `async_` constructor!

In practice, we expect that usage of the `async` constructor which was already well behaved will be unaffected by this change. However, any use which is (possibly unintentionally) relying on the old semantic will break, potentially resulting in deadlock as a cancelation which was previously observed will now be suppressed until the `async` completes. For this reason, users are advised to carefully audit their use of `async` to ensure that they always return `Some(...)` with the appropriate finalizer that unregisters their callback.

In the event that you *need* to restore the previous semantics, they can be approximated by producing `Some(IO.unit)` from the registration. This is a very rare situation, but it does arise in some cases. For example, the definition of `IO.never` had to be adjusted to the following:

```scala
def never: IO[Nothing] =
  IO.async(_ => IO.pure(Some(IO.unit)))  // was previously IO.pure(None)
```

This change can result in some very subtle consequences. If you find unexpected effects in your application after upgrading to 3.5.0, you should start your investigation with this change! (note that this change also affects third-party libraries using `async`, even if they have themselves not yet updated to 3.5.0 or higher!)

### Integrated Timers

From the very beginning, Cats Effect and applications built on top of it have managed timers (i.e. `IO.sleep` and everything built on top of it) on the JVM by using a separate thread pool. In particular, `ScheduledExecutorService`. This is an extremely standard approach used prolifically by almost all JVM applications. Unfortunately, it is also fundamentally suboptimal.

The problem stems from the fact that `ScheduledExecutorService` isn't *magic*. It works by maintaining one or more event dispatch threads which interrogate a data structure containing all active timers. If any timers have passed their expiry, the thread invokes their `Runnable`. If no timers are expired, the thread blocks for the minimum time until the next timer becomes available. In its default configuration, the Cats Effect runtime provisions exactly one event dispatch thread for this purpose.

This isn't *so* bad when an application makes very little use of timers, since the thread in question will spend almost all of its time blocked, doing nothing. This affects timeslice granularity within the OS kernel and adds an additional GC root, but both effects are small enough that they are usually unnoticed. The bigger problem comes when an application is using a *lot* of timers and the thread is constantly busy reading that data structure and dispatching the next set of `Runnable`(s) (all of which complete `async`s and immediately shift back into the Cats Effect compute pool).

Unfortunately, this situation where a *lot* of timers are in use is exactly what happens in every network application, since each and every active socket must have *at least* one `IO.sleep` associated with it to time out handling if the remote side stops responding (in most cases, such as HTTP, even more than one timer is needed). In other words, the fact that `IO.sleep` is relatively inefficient when a lot of concurrent `sleep`s are scheduled is particularly egregiously bad, since this is precisely the situation that describes most real-world usage of Cats Effect.

So we made this better! Cats Effect 3.5.0 introduces a new implementation of timers based on *cooperative polling*, which is basically the idea that timers can be dispatched and handled entirely by the same threads which handle *compute* work. Every time a compute worker thread runs out of work to do (and has nothing to steal), rather than just parking and waiting for more work, it first checks to see if there are any outstanding timers. If there are some which are ready to run, it runs them. Otherwise, if there are timers which aren't yet completed, the worker parks for *that* period of time (or until awakened by new work), ensuring the timer fires on schedule. In the event that a worker has not had the opportunity to park in some number of iterations, it proactively checks on its timers just to see if any have expired while it has been busy doing CPU-bound work.

This technique works extremely well in Cats Effect precisely because every timer had to shift back to the compute pool *anyway*, meaning that it was already impossible for any timer to have a granularity which was finer than that of the compute worker thread task queue. Thus, having that same task queue manage the dispatching of the timers themselves ensures that *at worst* those timers run with the same precision as previously, and at best we are able to avoid a considerable amount of overhead both in the form of OS kernel scheduler contention (since we are removing a whole thread from the application!) and the expense of a round-trip context shift and passage through the external work queue.

And, as mentioned, this optimization applies specifically to a scenario which is present in almost all real-world Cats Effect applications! To that end, we tested the performance of a relatively simple Http4s Ember server while under heavy load generated using the `hey` benchmark tool. The result was a roughly 15-25% improvement in sustained maximum requests per second, and a roughly 15% improvement in the 99th percentile latencies (P99). In practical terms, this means that **this one change makes standard microservice applications around 15% more efficient with no other adjustments.**

Obviously, you should do your own benchmarking to measure the impact of this optimization, but we expect the results to be very visible in production top-line metrics.

## User-Facing Pull Requests

- #3615 – Fixed issue in which failing `uncancelable` would remain masked for one stage (@djspiewak)
- #3611 – Treat non-positive sleep durations as `cede`s (@armanbilge)
- #3610 – Catch stray exceptions in `uncancelable` body (@armanbilge)
- #3606 – Adjusted `Queue.synchronous` to include a two-phase commit (@djspiewak)
- #3604 – Reset the global runtime when it is shutdown (@armanbilge)
- #3599 – Revised `Queue.synchronous` internals to simplify concurrent hand-off (@djspiewak)
- #3596 – Fix `Mutex` memory leak (@BalmungSan)
- #3496 – Add console as config in `ioRuntimeConfig`, pass it to `CPUStarvation` (@manuelcueto)
- #3586 – Try to fix #3568 (@durban)
- #3579 – dispatcher releasing itself rejects new tasks (@samspills)
- #3562 – New `AsyncMutex` implementation (@BalmungSan)
- #3567 – Make `blockedThreadDetectionEnabled` configurable via a system property (@chunjef)
- #3555 – Fix mutex cancelled acquire even more (@durban)
- #3556 – Fix problem with nextGaussian test (@antoniojimeneznieto)
- #3549 – Fix mutex cancelled acquire (@durban)
- #3546 – Cpu-starvation warnings one line (@mox692)
- #3428 – Parallel `map2` optimization (@durban)
- #3499 – Shared timers (@durban)
- #3518 – `AtomicCell#get` should not semantically block (@armanbilge)
- #3465 – Make `Console#readLine` cancelable (@armanbilge)
- #3435 – Further optimize `IODeferred` (@armanbilge)
- #3480 – Make `HotSwap` safe to concurrent access (@armanbilge)
- #3516 – Add basic tests for RandomSpec (@antoniojimeneznieto)
- #3490 – Fix "support re-enablement via cancelable" test (@armanbilge)
- #3484 – Allow that the renamed blocker thread is terminated (@aeons)
- #3478 – Fix `IORuntimeBuilder` `failureReporter` config on JS (@armanbilge)
- #3460 – Added `cancelable` (@djspiewak)
- #3453 – Corrected handling of self-cancelation within `timeout` (@djspiewak)
- #3432 – Fixed issues in the timer handling state machine integration (@djspiewak)
- #3434 – Fix NPE in blocked thread detection (@djspiewak)
- #3409 – Even faster async mutex (@armanbilge)
- #3408 – Add 'flatModify', 'flatModifyFull' and corresponding 'State' methods (@seigert)
- #3387 – Thread blocking detection (@TimWSpence)
- #3374 – Add `fromFutureCancelable` and friends (@armanbilge)
- #3346 – Optimize `Mutex` & `AtomicCell` (@BalmungSan)
- #3405 – Remove `IOLocal#scope`, revert #3214 (@armanbilge)
- #3347 – `ConcurrentAtomicCell` (@BalmungSan)
- #3302 – Add 'IOLocal.lens' method to produce lens 'A <=> B' (@seigert)
- #3360 – `IOLocal` - generalize `scope` function (@iRevive)
- #3388 – Protect timers against Long overflow (@durban)
- #3219 – Integrated timers (@djspiewak)
- #3225 – Introduce a `BatchingMacrotaskExecutor` (@armanbilge)
- #3311 – Remove `Ref`'s `flatModify` (@mn98)
- #3328 – Use `asyncCheckAttempt` in `IODeferred#get` (@armanbilge)
- #3304 – Add `IO#supervise`, `IO#toResource`, `IO#metered` (@kamilkloch)
- #3299 – Add `IO#voidError` (@armanbilge)
- #3205 – Change `async_` to be uncancelable (@djspiewak)
- #3273 – A new combinator, `flatModify`, on `Ref` (@mn98)
- #3264 – `Defer` instance for `Resource` without `Sync` requirement (@Odomontois)
- #3091 – Add `Async#asyncCheckAttempt` for #3087 (@seigert)
- #3214 – Add `IOLocal#scope` (@iRevive)
- #3002, #3390, #3416, #3455, #3477 – Documentation fixes and improvements (@danicheg, @davidabrahams, @TimWSpence, @bplommer, @amast09)

A very special and heartfelt thanks to all of you!

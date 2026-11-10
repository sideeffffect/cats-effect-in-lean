# Cats Effect docs: Typeclasses overview, Concurrent, Sync, Temporal, Clock, Unique

> Source: https://typelevel.org/cats-effect/docs/typeclasses (and /typeclasses/{concurrent,sync,temporal,clock,unique})
> Collected: 2026-11-10
> Published: Unknown

Verbatim from the docs/ directory of github.com/typelevel/cats-effect at tag v3.7.1 (commit eb0cc258); rendered at the URL above.


---

<!-- file: docs/typeclasses.md -->

---
id: typeclasses
title: Overview
---

![](assets/hierarchy-impure.jpeg)

The typeclass hierarchy within Cats Effect defines what it means, fundamentally, to *be* a functional effect. This is very similar to how we have a set of rules which tell us what it means to be a number, or what it means to have a `flatMap` method. Broadly, the rules for functional effects can be broken down into the following categories:

- Resource safety and cancelation
- Parallel evaluation
- State sharing between parallel processes
- Interactions with time, including current time and `sleep`
- Safe capture of side-effects which return values
- Safe capture of side-effects which invoke a callback

These are listed roughly in order of increasing power. Parallelism cannot be safely defined without some notion of resource safety and cancelation. Interactions with time have no meaning if there is no notion of parallel evaluation, since it would be impossible to observe the passage of time. Capturing and controlling side-effects makes it possible to do *anything* simply by "cheating" and capturing something like `new Thread`, and thus it has the greatest power of all of these categories.

Beyond the above, certain capabilities are *assumed* by Cats Effect but defined elsewhere (or rather, defined within [Cats](https://typelevel.org/cats)). Non-exhaustively, those capabilities are as follows:

- Transforming the value inside an effect by `map`ping over it
- Putting a value *into* an effect
- Composing multiple effectful computations together sequentially, such that each is dependent on the previous
- Raising and handling errors

Taken together, all of these capabilities define what it means to be an effect. Just as you can rely on the properties of integers when you perform basic mental arithmetic (e.g. you can assume that `1 + 2 + 3` is the same as `1 + 5`), so too can you rely on these powerful and general properties of *effects* to hold when you write complex programs. This allows you to understand and refactor your code based on rules and abstractions, rather than having to think about every possible implementation detail and use-case. Additionally, it makes it possible for you and others to write very generic code which composes together making an absolute minimum of assumptions. This is the foundation of the Cats Effect ecosystem.

---

<!-- file: docs/typeclasses/concurrent.md -->

---
id: concurrent
title: Concurrent
---

This typeclass extends `Spawn` with the capability to allocate concurrent state
in the form of [Ref](../std/ref.md) and [Deferred](../std/deferred.md) and
to perform various operations which require the allocation of concurrent state,
including `memoize` and `parTraverseN`. `Ref` and `Deferred` are the concurrent
primitives necessary to implement arbitrarily complicated concurrent state machines.

### Memoization

We can memoize an effect so that it's only run once and the result used repeatedly.

```scala
def memoize[A](fa: F[A]): F[F[A]]
```

Usage looks like this:

```scala mdoc
import cats.effect.IO
import cats.effect.unsafe.implicits.global
 
val action: IO[String] = IO.println("This is only printed once").as("action")

val x: IO[String] = for {
  memoized <- action.memoize
  res1 <- memoized
  res2 <- memoized
} yield res1 ++ res2

x.unsafeRunSync()
```

### Why `Ref` and `Deferred`?

It is worth considering why `Ref` and `Deferred` are the primitives exposed by `Concurrent`.
Generally when implementing concurrent data structures we need access to the following:
- A way of allocating and atomically modifying state
- A means of waiting on a condition (semantic blocking)

Well this is precisely `Ref` and `Deferred` respectively! Consider for example,
implementing a `CountDownLatch`, which is instantiated with `n > 0` latches and
allows fibers to semantically block until all `n` latches are released. We can
model this situation with the following state

```scala
sealed trait State[F[_]]
case class Awaiting[F[_]](latches: Int, signal: Deferred[F, Unit]) extends State[F]
case class Done[F[_]]() extends State[F]
```

representing the fact that the countdown latch either has latches which have yet to be released
and so fibers should block on it using the `signal` (more on this in a minute) or all the
latches have been released and the countdown latch is done.

We can store this state in a `state: Ref[F, State[F]]` to allow for concurrent
modification. Then the implementation of await looks like this:
```scala
def await: F[Unit] =
  state.get.flatMap {
    case Awaiting(_, signal) => signal.get
    case Done() => F.unit
  }
```
As you can see, if we're still waiting for some of the latches to be released then we 
use `signal` to block. Otherwise we just pass through with `F.unit`.

Similarly the implementation of `release` is:
```scala
def release: F[Unit] =
  F.uncancelable { _ =>
    state.modify {
      case Awaiting(n, signal) =>
        if (n > 1) (Awaiting(n - 1, signal), F.unit) else (Done(), signal.complete(()).void)
      case d @ Done() => (d, F.unit)
    }.flatten
  }
```

Ignoring subtleties around cancelation, the implementation is straightforward. If there is more
than 1 latch remaining then we simply decrement the count. If we are already done then we do nothing. The interesting case is when there is precisely 1 latch remaining, in which case we
transition to the `Done` state and we also `complete` the signal which unblocks all the
fibers waiting on the countdown latch.

There has been plenty of excellent material written on this subject. See [here](https://typelevel.org/blog/2020/10/30/concurrency-in-ce3.html) and [here](https://systemfw.org/writings.html) for example.

---

<!-- file: docs/typeclasses/sync.md -->

---
id: sync
title: Sync
---

`Sync` is the synchronous [Foreign Function Interface](https://en.wikipedia.org/wiki/Foreign_function_interface) 
(FFI) for suspending side-effectful operations. The
means of suspension is dependent on whether the side effect you want to
suspend is blocking or not (see the [thread model docs](../thread-model.md)
for more details on why this is the case).

## Methods of suspension

If your side effect is not thread-blocking then you can use `Sync[F].delay`
```scala
val counter = new AtomicLong()

val inc: F[Long] = Sync[F].delay(counter.incrementAndGet())
```

If your side effect is thread blocking then you should use `Sync[F].blocking`,
which not only suspends the side effect but also shifts the evaluation
of the effect to a separate threadpool to avoid blocking the compute
threadpool. Execution is shifted back to the compute pool once
the blocking operation completes.
```scala
val contents: F[String] = Sync[F].blocking(Source.fromFile("file").mkString)
```

A downside of thread-blocking calls is that the fiber executing them is not
cancelable until the blocking call completes. If you have a very long-running
blocking operation then you may want to suspend it using `Sync[F].interruptible`
or `Sync[F].interruptibleMany` instead.  This behaves the same as `blocking` 
but will attempt to interrupt the blocking operation via a thread interrupt 
in the event on cancelation.

```scala
//interruptibleMany means we try thread interruption repeatedly until the blocking operation exits
val operation: F[Unit] = F.interruptibleMany(longRunningOp())

val run: F[Unit] = operation.timeout(30.seconds)
```

---

<!-- file: docs/typeclasses/temporal.md -->

---
id: temporal
title: Temporal
---

`Temporal` extends `Concurrent` with the ability to suspend a fiber by sleeping for
a specified duration.

```scala
firstThing >> Temporal[F].sleep(5.seconds) >> secondThing
```

Of course this could be achieved by `Sync[F].delay(Thread.sleep(duration))` but
this is a _very bad_ idea as it will block a thread from the compute pool (see
the [thread model docs](../thread-model.md) for more details on why this is
bad).  Instead, `Temporal[F]#sleep` is assigned its own typeclass and is a
primitive of the implementation that semantically blocks the execution of the
calling  fiber by de-scheduling it.  Internally a scheduler is used to wait for
the specified duration before rescheduling the fiber.

The ability to sleep for a specified duration enables us to define powerful
time-dependent derived combinators like `timeoutTo`:

```scala
val data = fetchFromRemoteService.timeoutTo(2.seconds, cachedValue)
```

---

<!-- file: docs/typeclasses/clock.md -->

---
id: clock
title: Clock
---

A typeclass that provides effectful monotonic and system time analogous to
`System.nanoTime()` and `System.currentTimeMillis()`

```scala
trait Clock[F[_]] {

  def monotonic: F[FiniteDuration]

  def realTime: F[FiniteDuration]

}
```

---

<!-- file: docs/typeclasses/unique.md -->

---
id: unique
title: Unique
---

A typeclass which is a source of unique tokens via `unique`. This is a fairly
low-level programming primitive, and is not usually suitable for identifying
business entities at the level of application logic.

```scala
trait Unique[F[_]] {
  def unique: F[Unique.Token]
}
```

Each evaluation of `unique` is guaranteed to produce a value that is distinct 
from any other currently allocated tokens. 

```scala
val token: F[Unique.Token] = Unique[F].unique
(token, token).mapN { (x, y) => x === y } <-> Monad[F].pure(false)
```

This uniqueness guarantee applies only in respect of equality comparison between
`Unique.Token` instances; it is not possible to serialize these instances or
convert them to another form. (The `hashCode` method, for example, is not guaranteed
to return a unique value.) Therefore, these values are meaningful only within a single
application process and cannot (for example) be shared across network boundaries,
persisted to a database, or exposed to end-users. If you need globally unique token
that is suitable for purposes such as these, use a
[UUID](https://docs.oracle.com/javase/8/docs/api/java/util/UUID.html) instead.

Both `Sync[F]` and `Spawn[F]` extend `Unique[F]` as both typeclasses trivially
have the ability to create unique values via `delay(new Unique.Token())` and
`start` respectively (fibers are always unique).

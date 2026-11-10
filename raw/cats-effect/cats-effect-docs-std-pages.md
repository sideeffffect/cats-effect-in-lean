# Cats Effect docs: std pages (Ref, Deferred, Semaphore, Queue, Resource, Supervisor, Dispatcher, Mutex, CountDownLatch, CyclicBarrier, Hotswap, AtomicCell, Backpressure, Dequeue, PQueue, MapRef)

> Source: https://typelevel.org/cats-effect/docs/std/<page>
> Collected: 2026-11-10
> Published: Unknown

Verbatim from the docs/ directory of github.com/typelevel/cats-effect at tag v3.7.1 (commit eb0cc258); rendered at the URL above.


---

<!-- file: docs/std/ref.md -->

---
id: ref
title: Ref
---

A concurrent mutable reference.

```scala mdoc:silent
abstract class Ref[F[_], A] {
  def get: F[A]
  def set(a: A): F[Unit]
  def updateAndGet(f: A => A): F[A]
  def modify[B](f: A => (A, B)): F[B]
  // ... and more
}
```

Provides safe concurrent access and modification of its content, but no functionality for synchronisation, which is instead handled by [Deferred](./deferred.md).

For this reason, a `Ref` is always initialised to a value.

The default implementation is nonblocking and lightweight, consisting
essentially of a purely functional wrapper over an `AtomicReference`.
Consequently it _must not_ be used to store mutable data as
`AtomicReference#compareAndSet` and friends are dependent
upon object reference equality.


### Concurrent Counter

This is probably one of the most common uses of this concurrency primitive.

In this example, the workers will concurrently run and update the value of the `Ref`.

```scala mdoc:reset:silent
//> using lib "org.typelevel::cats-effect:3.6.4"

import cats.effect.{IO, IOApp, Sync}
import cats.effect.kernel.Ref
import cats.syntax.all._

class Worker[F[_]](id: Int, ref: Ref[F, Int])(implicit F: Sync[F]) {

  private def putStrLn(value: String): F[Unit] =
    F.blocking(println(value))

  def start: F[Unit] =
    for {
      c1 <- ref.get
      _  <- putStrLn(show"Worker #$id >> $c1")
      c2 <- ref.updateAndGet(x => x + 1)
      _  <- putStrLn(show"Worker #$id >> $c2")
    } yield ()
}

object RefExample extends IOApp.Simple {

  val run: IO[Unit] =
    for {
      ref <- Ref[IO].of(0)
      w1 = new Worker[IO](1, ref)
      w2 = new Worker[IO](2, ref)
      w3 = new Worker[IO](3, ref)
      _ <- List(
        w1.start,
        w2.start,
        w3.start,
      ).parSequence.void
    } yield ()
}
```

This is one possible outcome showing “Worker #id » currentCount”:

```
Worker #1 >> 0
Worker #3 >> 0
Worker #2 >> 0
Worker #2 >> 3
Worker #1 >> 1
Worker #3 >> 2
```

---

<!-- file: docs/std/deferred.md -->

---
id: deferred
title: Deferred
---

A purely functional synchronization primitive which represents a single value which may not yet be available.

When created, a `Deferred` is empty. It can then be completed exactly once, and never be made empty again.

```scala mdoc:silent
abstract class Deferred[F[_], A] {
  def get: F[A]
  def complete(a: A): F[Boolean]
}
```

Expected behavior of `get`

- `get` on an empty `Deferred` will block until the `Deferred` is completed
- `get` on a completed `Deferred` will always immediately return its content
- `get` is cancelable and on cancelation it will unsubscribe the registered
  listener, an operation that's possible for as long as the `Deferred` value
  isn't complete

Expected behavior of `complete`

- `complete(a)` on an empty `Deferred` will set it to `a`, notify any and all readers currently blocked on a call to `get` and return `true`
- `complete(a)` on a `Deferred` that has already been completed will not modify its content, and will result `false`

Albeit simple, `Deferred` can be used in conjunction with `Ref` to build complex concurrent behaviour and data structures like queues and semaphores.

Finally, the blocking mentioned above is semantic only, no actual threads are blocked by the implementation.

### Only Once

Whenever you are in a scenario when many processes can modify the same value but you only care about the first one in doing so and stop processing, then this is a great use case of `Deferred[F, A]`.

Two processes will try to complete at the same time but only one will succeed, completing the deferred primitive exactly once. The loser one will get a `false` in `F` when trying to complete a `Deferred` already completed or automatically be canceled by the `IO.race` mechanism.

```scala mdoc:reset:silent
import cats.effect.{IO, Deferred}
import cats.syntax.all._

def start(d: Deferred[IO, Int]): IO[Unit] = {
  val attemptCompletion: Int => IO[Unit] = n => d.complete(n).void

  List(
    IO.race(attemptCompletion(1), attemptCompletion(2)),
    d.get.flatMap { n => IO(println(show"Result: $n")) }
  ).parSequence.void
}

val program: IO[Unit] =
  for {
    d <- Deferred[IO, Int]
    _ <- start(d)
  } yield ()
```

---

<!-- file: docs/std/semaphore.md -->

---
id: semaphore
title:  Semaphore
---

![](assets/semaphore.png)

A semaphore has a non-negative number of permits available. Acquiring a permit decrements the current number of permits and releasing a permit increases the current number of permits. An acquire that occurs when there are no permits available results in fiber blocking until a permit becomes available.

```scala
abstract class Semaphore[F[_]] {
  def available: F[Long]
  def acquire: F[Unit]
  def release: F[Unit]
  // ... and more
}
```

## Fiber Blocking and Cancellation

Semaphore does what we call "fiber" blocking (aka "semantic" blocking), meaning that no actual threads are
being blocked while waiting to acquire a permit. Blocking acquires are cancelable.

## Shared Resource

When multiple processes try to access a precious resource you might want to constraint the number of accesses. Here is where `Semaphore[F]` is useful.

Three processes are trying to access a shared resource at the same time but only one at a time will be granted access and the next process have to wait until the resource gets available again (availability is one as indicated by the semaphore counter).

`R1`, `R2` & `R3` will request access of the precious resource concurrently so this could be one possible outcome:

```
R1 >> Availability: 1
R2 >> Availability: 1
R2 >> Started | Availability: 0
R3 >> Availability: 0
--------------------------------
R1 >> Started | Availability: 0
R2 >> Done | Availability: 0
--------------------------------
R3 >> Started | Availability: 0
R1 >> Done | Availability: 0
--------------------------------
R3 >> Done | Availability: 1
```

This means when `R1` and `R2` requested the availability it was one and `R2` was faster in getting access to the resource so it started processing. `R3` was the slowest and saw that there was no availability from the beginning.

Once `R2` was done `R1` started processing immediately showing no availability. Once `R1` was done `R3` started processing immediately showing no availability. Finally, `R3` was done showing an availability of one once again.

```scala mdoc:reset:silent
import cats.effect.{IO, Temporal}
import cats.effect.std.{Console, Semaphore}
import cats.implicits._
import cats.effect.syntax.all._

import scala.concurrent.duration._

class PreciousResource[F[_]: Temporal](name: String, s: Semaphore[F])(implicit F: Console[F]) {
  def use: F[Unit] =
    for {
      x <- s.available
      _ <- F.println(s"$name >> Availability: $x")
      _ <- s.acquire
      y <- s.available
      _ <- F.println(s"$name >> Started | Availability: $y")
      _ <- s.release.delayBy(3.seconds)
      z <- s.available
      _ <- F.println(s"$name >> Done | Availability: $z")
    } yield ()
}

val program: IO[Unit] =
  for {
    s  <- Semaphore[IO](1)
    r1 = new PreciousResource[IO]("R1", s)
    r2 = new PreciousResource[IO]("R2", s)
    r3 = new PreciousResource[IO]("R3", s)
    _  <- List(r1.use, r2.use, r3.use).parSequence.void
  } yield ()
```

---

<!-- file: docs/std/queue.md -->

---
id: queue
title: Queue
---

A purely-functional concurrent implementation of a queue.

```scala
trait Queue[F[_], A] {

  def take: F[A]

  def tryTake: F[Option[A]]

  def offer(a: A): F[Unit]

  def tryOffer(a: A): F[Boolean]

}
```

`take` is fiber blocking when the queue is empty. A `Queue` may be constructed
with different policies for the behaviour of `offer` when the queue has reached
capacity:

- `bounded(capacity: Int)`: `offer` is fiber blocking when the queue is full
- `synchronous`: equivalent to `bounded(0)` - `offer` and `take` are both blocking
  until another fiber invokes the opposite action
- `unbounded`: `offer` never blocks
- `dropping(capacity: Int)`: `offer` never blocks but new elements are discarded if the
  queue is full
- `circularBuffer(capacity: Int)`: `offer` never blocks but the oldest elements are discarded
  in favour of new elements when the queue is full

## Variance

`Queue` is split into a `QueueSource` with a `Functor` instance and a
`QueueSink` with a `Contravariant` functor instance. This allows us to
treat a `Queue[F, A]` as a `QueueSource[F, B]` by mapping with `A => B`
or as a `QueueSink[F, B]` by contramapping with `B => A`.

```scala mdoc:reset
import cats.{Contravariant, Functor}
import cats.implicits._
import cats.effect._
import cats.effect.std.{Queue, QueueSource, QueueSink}
import cats.effect.unsafe.implicits.global

def covariant(list: List[Int]): IO[List[Long]] = (
  for {
    q <- Queue.bounded[IO, Int](10)
    qOfLongs: QueueSource[IO, Long] = Functor[QueueSource[IO, *]].map(q)(_.toLong)
    _ <- list.traverse(q.offer(_))
    l <- List.fill(list.length)(()).traverse(_ => qOfLongs.take)
  } yield l
)

covariant(List(1,4,2,3)).flatMap(IO.println(_)).unsafeRunSync()

def contravariant(list: List[Boolean]): IO[List[Int]] = (
  for {
    q <- Queue.bounded[IO, Int](10)
    qOfBools: QueueSink[IO, Boolean] =
      Contravariant[QueueSink[IO, *]].contramap(q)(b => if (b) 1 else 0)
    _ <- list.traverse(qOfBools.offer(_))
    l <- List.fill(list.length)(()).traverse(_ => q.take)
  } yield l
)

contravariant(List(true, false)).flatMap(IO.println(_)).unsafeRunSync()
```

---

<!-- file: docs/std/resource.md -->

---
id: resource
title: Resource
---

## Motivation

A common pattern is to acquire a resource (eg a file or a socket), perform
some action on it and then run a finalizer (eg closing the file handle),
regardless of the outcome of the action.

This can be achieved with `MonadCancel#bracket`

```scala
def bracket[A, B](acquire: F[A])(use: A => F[B])(release: A => F[Unit]): F[B]
```

However, composing this quickly becomes unwieldy

```scala
val concat: IO[Unit] = IO.bracket(openFile("file1")) { file1 =>
  IO.bracket(openFile("file2")) { file2 =>
    IO.bracket(openFile("file3")) { file3 =>
      for {
        bytes1 <- read(file1)
        bytes2 <- read(file2)
        _ <- write(file3, bytes1 ++ bytes2)
      } yield ()
    }(file3 => close(file3))
  }(file2 => close(file2))
}(file1 => close(file1))
```

and it also couples the logic to acquire the resource with the logic to use
the resource.

`Resource[F[_], A]` is a solution to this which encapsulates the logic
to acquire and finalize a resource of type `A` and forms a `Monad`
in `A` so that we can construct composite resources without the
deep nesting of `bracket`.

## Resource

The simplest way to construct a `Resource` is with `Resource#make` and the simplest way to
consume a resource is with `Resource#use`. Arbitrary actions can also be lifted to
resources with `Resource#eval`

```scala
object Resource {
  def make[F[_], A](acquire: F[A])(release: A => F[Unit]): Resource[F, A]

  def eval[F[_], A](fa: F[A]): Resource[F, A]
}

abstract class Resource[F, A] {
  def use[B](f: A => F[B]): F[B]
}
```

Our concat example then becomes:

```scala
def file(name: String): Resource[IO, File] = Resource.make(openFile(name))(file => close(file))

val concat: IO[Unit] =
  (
    for {
      in1 <- file("file1")
      in2 <- file("file2")
      out <- file("file3")
    } yield (in1, in2, out)
  ).use { case (file1, file2, file3) =>
    for {
      bytes1 <- read(file1)
      bytes2 <- read(file2)
      _ <- write(file3, bytes1 ++ bytes2)
    } yield ()
  
  }
```

Note that the resources are released in reverse order to the acquire and that
both `acquire` and `release` are non-interruptible and hence safe in the face of
cancelation. Outer resources will be released irrespective of failure in the
lifecycle of an inner resource.

Also note that finalization happens as soon as the `use` block finishes and
hence the following will throw an error as the file is already closed when we
attempt to read it:
```scala
open(file1).use(IO.pure).flatMap(readFile)
```
As a corollary, this means that the resource is acquired every time `use` is invoked.
So `file.use(read) >> file.use(read)` opens the file twice whereas
`file.use { file => read(file) >> read(file) }` will only open it once.

---

<!-- file: docs/std/supervisor.md -->

---
id: supervisor
title: Supervisor
---

## Motivation

[Spawn](../typeclasses/spawn.md) provides multiple ways to spawn a [fiber](../concepts.md#fibers) to run an action:

`Spawn[F]#start`: start and forget, no lifecycle management for the spawned fiber 

`Spawn[F]#background`: ties the lifecycle of the spawned fiber to that of the fiber that invoked `background`

The following diagrams illustrate the lifecycle of the spawned fiber in both cases.
In each example, some fiber A is spawning another fiber B.
Each box represents the lifecycle of a fiber.
If a box is enclosed within another box, it means that the lifecycle of the former is confined within the lifecycle of the latter.
In other words, if an outer fiber terminates, the inner fibers are guaranteed to be terminated as well.

`Spawn[F]#start`:
```
Fiber A lifecycle
+---------------------+
|                 |   |
+-----------------|---+
                  |
                  |A starts B
Fiber B lifecycle |
+-----------------|---+
|                 +   |
+---------------------+
```

`Spawn[F]#background`:
```
Fiber A lifecycle
+------------------------+
|                    |   |
| Fiber B lifecycle  |A starts B
| +------------------|-+ |
| |                  | | |
| +--------------------+ |
+------------------------+
```

But what if we want to spawn a fiber that should outlive the scope that created
it, but we still want to control its lifecycle?

## Supervisor

A supervisor spawns fibers whose lifecycles are bound to that of the supervisor.

```scala
trait Supervisor[F[_]] {
  def supervise[A](fa: F[A]): F[Fiber[F, Throwable, A]]
}

object Supervisor {
  def apply[F[_]](await: Boolean)(implicit F: Concurrent[F]): Resource[F, Supervisor[F]]
}
```

Any fibers created via the supervisor will be finalized when the supervisor itself
is finalized via `Resource#use`.

The lifecycle of fibers spawned with `Supervisor` can be illustrated in the same style as above:

```
Supervisor lifecycle
+---------------------+
| Fiber B lifecycle   |
| +-----------------+ |
| |               + | |
| +---------------|-+ |
+-----------------|---+
                  |
                  | A starts B
Fiber A lifecycle |
+-----------------|---+
|                 |   |
+---------------------+
```


There are two finalization strategies according to the `await` parameter of the constructor:
- `true` - wait for the completion of the active fibers
- `false` - cancel the active fibers

**Note:** if an effect that never completes is supervised by a `Supervisor` with the awaiting 
termination policy, the termination of the `Supervisor` is indefinitely suspended:
```scala mdoc:silent
import cats.effect.IO
import cats.effect.std.Supervisor

Supervisor[IO](await = true).use { supervisor =>
  supervisor.supervise(IO.never).void
}
```

---

<!-- file: docs/std/dispatcher.md -->

---
id: dispatcher
title: Dispatcher
---

![](assets/dispatcher.jpeg)

`Dispatcher` is a [fiber](../concepts.md#fibers)-based [`Supervisor`](./supervisor.md) utility for evaluating effects across an impure boundary. This is useful when working with reactive interfaces that produce potentially many values (as opposed to one), and for each value, some effect in `F` (like inserting each value into a queue) must be performed as a side effect by an impure callback. This allows effectful code to be sequenced within the control flow of impure code, reversing the more common scenario where impure code, suspended using `delay` or `blocking`, is sequenced within effectful code. 


An instance of `Dispatcher` can be derived for any effect type conforming to the [`Async`](../typeclasses/async.md) typeclass.

Let's say we are integrating with an interface that looks like this:

```scala
abstract class ImpureInterface {
  def onMessage(msg: String): Unit

  def init(): Unit = {
    onMessage("init")
  }

  // ...
}
```

As a user we're supposed to create an implementation of this class where we implement `onMessage`.

Let's say that we have a [`queue`](./queue.md) and that we want to add each message received to the queue. We might,
naively, try to do the following

```scala
for {
    queue <- Queue.unbounded[IO, String]
    impureInterface = new ImpureInterface {
      override def onMessage(msg: String): Unit = queue.offer(msg) // This returns an IO, so nothing really happens!
    }
    _ <- IO.delay(impureInterface.init())
    value <- queue.tryTake
  } yield value match {
    case Some(v) => println(s"Value found in queue! $v")
    case None    => println("Value not found in queue :(")
  }
```

This will print "Value not found in queue :(", since our implementation of `onMessage` 
doesn't really *do* anything. It just creates an `IO` value which is just a description of an effect,
without actually executing it. (Here the `scalac` option `-Ywarn-value-discard` might help hint at this problem.)

It is in these cases that `Dispatcher` comes in handy. Here's how it could be used:

```scala
Dispatcher.sequential[IO] use { dispatcher =>
  for {
    queue <- Queue.unbounded[IO, String]
    impureInterface <-
      IO.delay {
        new ImpureInterface {
          override def onMessage(msg: String): Unit =
            dispatcher.unsafeRunAndForget(queue.offer(msg))
        }
      }
    _ <- IO.delay(impureInterface.init())
    value <- queue.tryTake
  } yield value match {
    case Some(v) => println(s"Value found in queue! $v")
    case None    => println("Value not found in queue :(")
  }
}
```

It prints "Value found in queue! init"!

The example above calls `unsafeRunAndForget` on the dispatcher, but more functions are exposed:

```scala

trait Dispatcher[F[_]] extends DispatcherPlatform[F] {

  def unsafeToFutureCancelable[A](fa: F[A]): (Future[A], () => Future[Unit])

  def unsafeToFuture[A](fa: F[A]): Future[A] =
    unsafeToFutureCancelable(fa)._1

  def unsafeRunCancelable[A](fa: F[A]): () => Future[Unit] =
    unsafeToFutureCancelable(fa)._2

  def unsafeRunAndForget[A](fa: F[A]): Unit = {
    unsafeToFutureCancelable(fa)
    ()
  }

  //Only on the JVM
  def unsafeRunSync[A](fa: F[A]): A
}
```

Creating an instance of `Dispatcher` is very cheap - you are encouraged to instantiate it 
where necessary rather than wiring a single instance throughout an application.


## Cats Effect 2

Users of Cats Effect 2 may be familiar with the `Effect` and `ConcurrentEffect`
typeclasses. These have been removed as they constrained implementations of the
typeclasses too much by forcing them to be embeddable in `IO` via `def
toIO[A](fa: F[A]): IO[A]`. However, these typeclasses also had a valid use-case
for unsafe running of effects to interface with impure APIs (`Future`, `NIO`,
etc). `Dispatcher` now addresses this use-case.

---

<!-- file: docs/std/mutex.md -->

---
id: mutex
title: Mutex
---

`Mutex` is a concurrency primitive that can be used to give access to a resource to only **one**
fiber at a time. Basically, it's a [`Semaphore`](./semaphore.md) with a single available permit.

```scala mdoc:silent
import cats.effect.Resource

trait Mutex[F[_]] {
  def lock: Resource[F, Unit]
}
```

**Caution**: This lock is not reentrant,
thus doing `mutex.lock.surround(mutex.lock.use_)`
will deadlock.

## Using `Mutex`

```scala mdoc:reset:silent
import cats.effect.{IO, Ref}
import cats.effect.std.Mutex

trait State
class Service(mutex: Mutex[IO], ref: Ref[IO, State]) {
  def modify(f: State => IO[State]): IO[Unit] =
    mutex.lock.surround {
      for {
        current <- ref.get
        next <- f(current)
        _ <- ref.set(next)
      } yield ()
    }
}
```

---

<!-- file: docs/std/countdown-latch.md -->

---
id: countdown-latch
title: Count Down Latch
---

A one-shot concurrency primitive that blocks any fibers that wait on
it. It is initialized with a positive integer `n` latches and waiting
fibers are semantically blocked until all `n` latches are released.
After this, further `await`s are no-ops (equivalent to `IO.unit`).

```scala
trait CountDownLatch[F[_]] {

  def release: F[Unit]

  def await: F[Unit]

}
```

Cancelation of `await` is supported.

```scala mdoc
import cats.implicits._
import cats.effect._
import cats.effect.std.CountDownLatch
import cats.effect.unsafe.implicits.global

val run = (
  for {
    c <- CountDownLatch[IO](2)
    f <- (c.await >> IO.println("Countdown latch unblocked")).start
    _ <- c.release
    _ <- IO.println("Before latch is unblocked")
    _ <- c.release
    _ <- f.join
  } yield ()
)

run.unsafeRunSync()
```

---

<!-- file: docs/std/cyclic-barrier.md -->

---
id: cyclic-barrier
title: Cyclic Barrier
---

A re-usable synchronization primitive that allows a set of
fibers to wait until they've all reached the same point.

```scala

trait CyclicBarrier[F[_]] {

  def await: F[Unit]

}
```

A cyclic barrier is initialized with a positive integer `n` and
fibers which call `await` are semantically blocked until `n` of
them have invoked `await`, at which point all of them are unblocked
and the cyclic barrier is reset.

`await` cancelation is supported, in which case the number of
fibers required to unblock the cyclic barrier is incremented again.

```scala mdoc
import cats.implicits._
import cats.effect._
import cats.effect.std.CyclicBarrier
import cats.effect.unsafe.implicits.global
import scala.concurrent.duration._

val run = (for {
  b <- CyclicBarrier[IO](2)
  f1 <- (IO.println("fast fiber before barrier") >>
      b.await >> 
      IO.println("fast fiber after barrier")
    ) .start
  f2 <- (IO.sleep(1.second) >>
      IO.println("slow fiber before barrier") >>
      IO.sleep(1.second) >>
      b.await >>
      IO.println("slow fiber after barrier")
    ).start
  _ <- (f1.join, f2.join).tupled
} yield ())

run.unsafeRunSync()
```

---

<!-- file: docs/std/hotswap.md -->

---
id: hotswap
title: Hotswap
---

## Motivation

Constructing a new [`Resource`](./resource.md) inside the body of a
`Resource#use` can lead to memory leaks as the outer resource is not finalized
until after the inner resource is released. Consider for example writing a
logger that will rotate log files every `n` bytes. 

## NonEmptyHotswap

`NonEmptyHotswap` addresses this by exposing a linear sequence of resources as a single
`Resource`. We can run the finalizers for the current resource and advance to
the next one in the sequence using `NonEmptyHotswap#swap`. An error may be raised if
the previous resource in the sequence is referenced after `swap` is invoked
(as the resource will have been finalized).

```scala
sealed trait NonEmptyHotswap[F[_], R] {
  def swap(next: Resource[F, R]): F[Unit]
  def get: Resource[F, R]
}
```

A rotating logger would then look something like this:

```scala
def rotating(n: Int): Resource[IO, Logger[IO]] = {
  def file(name: String): Resource[IO, File] = ???
  def write(file: File, msg: String): IO[Unit] = ???

  NonEmptyHotswap[IO, File](file("0.log").flatMap { hs =>
    Resource.eval {
      for {
        index <- Ref[IO].of(0)
        count <- Ref[IO].of(0)
      } yield new Logger[IO] {
        def log(msg: String): IO[Unit] =
          count.get.flatMap { currentCount =>
            if (msg.length() < n - currentCount)
              hs.get.use { currentFile =>
                write(currentFile, msg) *>
                  count.update(_ + msg.length())
              }
            else
              for {
                // Reset the log length counter
                _ <- count.set(msg.length())
                // Increment the counter for the log file name
                idx <- index.updateAndGet(_ + 1)
                // Close the old log file and open the new one
                _ <- hs.swap(file(s"$idx.log"))
                _ <- hs.get.use(write(_, msg))
              } yield ()
          }
      }
    }
  }
}
```
---

<!-- file: docs/std/atomic-cell.md -->

---
id: atomic-cell
title: Atomic Cell
---

A synchronized, concurrent, mutable reference.

```scala mdoc:silent
abstract class AtomicCell[F[_], A] {
  def get: F[A]
  def set(a: A): F[Unit]
  def modify[B](f: A => (A, B)): F[B]
  def evalModify[B](f: A => F[(A, B)]): F[B]
  def evalUpdate(f: A => F[A]): F[Unit]
  // ... and more
}
```

Provides safe concurrent access and modification of its contents, by ensuring only one fiber
can operate on them at the time. Thus, all operations except `get` may semantically block the
calling fiber.

## Using `AtomicCell`

The `AtomicCell` can be treated as a combination of `Mutex` and `Ref`:

```scala mdoc:reset:silent
import cats.effect.IO
import cats.effect.std.AtomicCell

trait State

class Service(cell: AtomicCell[IO, State]) {
  def modify(f: State => IO[State]): IO[Unit] =
    cell.evalUpdate(f)
}
```

### Example

Imagine a random data generator,
that requires running some effectual operations _(e.g. checking a database)_
to produce a new value.
In that case, it may be better to block than to repeat the operation.

```scala mdoc:reset:silent
import cats.effect.IO
import cats.effect.std.AtomicCell

trait Data

class RandomDataGenerator(cell: AtomicCell[IO, Data]) {
  // Generates a new random value.
  def next: IO[Data] =
    cell.evalUpdateAndGet(generate)

  private def generate(previous: Data): IO[Data] =
    ???
}
```

---

<!-- file: docs/std/backpressure.md -->

---
id: backpressure
title: Backpressure
---

`Backpressure` allows running effects through the rate-limiting strategy.
`Backpressure` can be utilized in a scenario where a large number of tasks need to be processed, but only a certain number of resources are available.
In other words, backpressure is needed when there is not enough time or resources available for processing all the requests on your system.

`Backpressure` has two strategies that work as follows:
- `Lossy` - an effect **will not be** run in the presence of backpressure.
- `Lossless` - an effect **will run** in the presence of backpressure. However, the effect will semantically block until backpressure is alleviated.

```scala
trait Backpressure[F[_]] {
  def metered[A](f: F[A]): F[Option[A]]
}
```

## Using `Backpressure`

```scala mdoc:silent
import cats.effect.IO
import cats.effect.std.Backpressure
import scala.concurrent.duration._

val program = 
  for {
    backpressure <- Backpressure[IO](Backpressure.Strategy.Lossless, 1)
    f1 <- backpressure.metered(IO.sleep(1.second) *> IO.pure(1)).start
    f2 <- backpressure.metered(IO.sleep(1.second) *> IO.pure(1)).start
    res1 <- f1.joinWithNever
    res2 <- f2.joinWithNever
  } yield (res1, res2)
```

---

<!-- file: docs/std/dequeue.md -->

---
id: dequeue
title: Dequeue
---

A purely-functional concurrent implementation of a double-ended queue.

```scala
trait Dequeue[F[_], A] extends Queue[F, A] {

  def offerBack(a: A): F[Unit]

  def tryOfferBack(a: A): F[Boolean]

  def takeBack: F[A]

  def tryTakeBack: F[Option[A]]

  def offerFront(a: A): F[Unit]

  def tryOfferFront(a: A): F[Boolean]

  def takeFront: F[A]

  def tryTakeFront: F[Option[A]]

  def reverse: F[Unit]

  override def offer(a: A): F[Unit] = offerBack(a)

  override def tryOffer(a: A): F[Boolean] = tryOfferBack(a)

  override def take: F[A] = takeFront

  override def tryTake: F[Option[A]] = tryTakeFront

}
```

A `Dequeue` may be constructed as `bounded` or `unbounded`. If bounded then
`offer` may semantically block if the pqueue is already full. `take` is
fiber blocking if the pqueue is empty.

## Variance

`Dequeue` is split into a `DequeueSource` with a `Functor` instance and a
`DequeueSink` with a `Contravariant` functor instance. This allows us to treat a
`Dequeue[F, A]` as a `DequeueSource[F, B]` by mapping with `A => B`  or as a
`DequeueSink[F, B]` by contramapping with `B => A`.

```scala mdoc:reset
import cats.{Contravariant, Functor}
import cats.implicits._
import cats.effect._
import cats.effect.std.{Dequeue, DequeueSource, DequeueSink}
import cats.effect.unsafe.implicits.global

def covariant(list: List[Int]): IO[List[Long]] = (
  for {
    q <- Dequeue.bounded[IO, Int](10)
    qOfLongs: DequeueSource[IO, Long] = Functor[DequeueSource[IO, *]].map(q)(_.toLong)
    _ <- list.traverse(q.offer(_))
    l <- List.fill(list.length)(()).traverse(_ => qOfLongs.take)
  } yield l
)

covariant(List(1,4,2,3)).flatMap(IO.println(_)).unsafeRunSync()

def contravariant(list: List[Boolean]): IO[List[Int]] = (
  for {
    q <- Dequeue.bounded[IO, Int](10)
    qOfBools: DequeueSink[IO, Boolean] =
      Contravariant[DequeueSink[IO, *]].contramap(q)(b => if (b) 1 else 0)
    _ <- list.traverse(qOfBools.offer(_))
    l <- List.fill(list.length)(()).traverse(_ => q.take)
  } yield l
)

contravariant(List(true, false)).flatMap(IO.println(_)).unsafeRunSync()
```

---

<!-- file: docs/std/pqueue.md -->

---
id: pqueue
title: Priority Queue
---

A purely-functional concurrent implementation of a priority queue, using
a cats `Order` instance to determine the relative priority of elements.

```scala
trait PQueue[F[_], A : Order] {

  def take: F[A]

  def tryTake: F[Option[A]]

  def offer(a: A): F[Unit]

  def tryOffer(a: A): F[Boolean]

}
```

A `PQueue` may be constructed as `bounded` or `unbounded`. If bounded then
`offer` may semantically block if the pqueue is already full. `take` is
fiber blocking if the pqueue is empty.

```scala mdoc
import cats.Order
import cats.implicits._
import cats.effect._
import cats.effect.std.PQueue
import cats.effect.unsafe.implicits.global

val list = List(1,4,3,7,5,2,6,9,8)

implicit val orderForInt: Order[Int] = Order.fromLessThan((x, y) => x < y)

def absurdlyOverengineeredSort(list: List[Int]) = (
  for {
    pq <- PQueue.bounded[IO, Int](10)
    _ <- list.traverse(pq.offer(_))
    l <- List.fill(list.length)(()).traverse( _ => pq.take)
  } yield l
)

absurdlyOverengineeredSort(list).flatMap(IO.println(_)).unsafeRunSync()
```

## Variance

`PQueue` is split into a `PQueueSource` with a `Functor` instance and a
`PQueueSink` with a `Contravariant` functor instance. This allows us to
treat a `PQueue[F, A]` as a `PQueueSource[F, B]` by mapping with `A => B`
or as a `PQueueSink[F, B]` by contramapping with `B => A`.

```scala mdoc:reset
import cats.Order
import cats.{Contravariant, Functor}
import cats.implicits._
import cats.effect._
import cats.effect.std.{PQueue, PQueueSource, PQueueSink}
import cats.effect.unsafe.implicits.global

implicit val orderForInt: Order[Int] = Order.fromLessThan((x, y) => x < y)

def covariant(list: List[Int]): IO[List[Long]] = (
  for {
    pq <- PQueue.bounded[IO, Int](10)
    pqOfLongs: PQueueSource[IO, Long] = Functor[PQueueSource[IO, *]].map(pq)(_.toLong)
    _ <- list.traverse(pq.offer(_))
    l <- List.fill(list.length)(()).traverse(_ => pqOfLongs.take)
  } yield l
)

covariant(List(1,4,2,3)).flatMap(IO.println(_)).unsafeRunSync()

def contravariant(list: List[Boolean]): IO[List[Int]] = (
  for {
    pq <- PQueue.bounded[IO, Int](10)
    pqOfBools: PQueueSink[IO, Boolean] =
      Contravariant[PQueueSink[IO, *]].contramap(pq)(b => if (b) 1 else 0)
    _ <- list.traverse(pqOfBools.offer(_))
    l <- List.fill(list.length)(()).traverse(_ => pq.take)
  } yield l
)

contravariant(List(true, false)).flatMap(IO.println(_)).unsafeRunSync()
```

---

<!-- file: docs/std/mapref.md -->

---
id: mapref
title: MapRef
---

A total map from a key to a `Ref` of its value.

```scala mdoc:silent
import cats.effect.Ref

trait MapRef[F[_], K, V] {

  /**
   * Access the reference for this Key
   */
  def apply(k: K): Ref[F, V]
}
```

It is conceptually similar to a `Ref[F, Map[K, V]]`,
but with better ergonomics when working on a per key basis.
Note, however, that it does not support atomic updates to multiple keys.

Additionally, some implementations also provide less contention:
since all operations are performed on individual key-value pairs,
the pairs can be sharded by key.
Thus, multiple concurrent updates may be executed independently to each other,
as long as their keys belong to different shards.

### In-Memory database

This is probably one of the most common uses of this datatype.

```scala mdoc:reset:silent
//> using lib "org.typelevel::cats-effect:3.6.4"

import cats.effect.IO
import cats.effect.std.MapRef

trait DatabaseClient[F[_], Id, Data] {
  def getDataById(id: Id): F[Option[Data]]
  def upsertData(id: Id, data: Data): F[Unit]
}

object DatabaseClient {
  def inMemory[Id, Data]: IO[DatabaseClient[IO, Id, Data]] =
    MapRef.ofShardedImmutableMap[IO, Id, Data](
      shardCount = 5 // Arbitrary number of shards just for demonstration.
    ).map { mapRef =>
      new DatabaseClient[IO, Id, Data] {
        override def getDataById(id: Id): IO[Option[Data]] =
          mapRef(id).get

        override def upsertData(id: Id, data: Data): IO[Unit] =
          mapRef(id).update(_ => Some(data))
      }
    }
}
```

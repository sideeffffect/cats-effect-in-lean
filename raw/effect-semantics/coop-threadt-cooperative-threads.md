# coop: cooperative multithreading as a pure monad transformer (README, ThreadF, ThreadT)

> Source: https://github.com/typelevel/coop
> Collected: 2026-11-10
> Published: Unknown

## README.md

# coop

Based on http://www.haskellforall.com/2013/06/from-zero-to-cooperative-threads-in-33.html. All credit to Gabriella Gonzalez. The minor API and implementation differences from her Haskell version are due to Scala being Scala, and not any sign of original thought on my part.

...okay I take that back. The implementation of monitors is original, but it's so obvious that I'm not sure it counts as anything to take credit for.

## Usage

```sbt
libraryDependencies += "org.typelevel" %% "coop" % "<version>"
```

Published for Scala 2.13, 2.12, 3.1, with cross-publication for ScalaJS 1.10 and Scala Native 0.4.5. Depends on Cats Free 2.8.0 and Cats MTL 1.3.0.

```scala
import coop.ThreadT

// with cats-effect
import cats.effect.IO
import cats.implicits._

val thread1 = (ThreadT.liftF(IO(println("yo"))) >> ThreadT.cede).foreverM
val thread2 = (ThreadT.liftF(IO(println("dawg"))) >> ThreadT.cede).foreverM

val main = ThreadT.start(thread1) >> ThreadT.start(thread2)

val ioa = ThreadT.roundRobin(main)     // => IO[Unit]
ioa.unsafeRunSync()
```

This will print the following endlessly:

```
yo
dawg
yo
dawg
yo
dawg
...
```

Or if you think that some witchcraft is happening due to the use of `IO` in the above, here's an example using `State` instead:

```scala
import coop.ThreadT

import cats.data.State
import cats.implicits._

import scala.collection.immutable.Vector

val thread1 = {
  val mod = ThreadT.liftF(State.modify[Vector[Int]](_ :+ 0)) >> ThreadT.cede
  mod.untilM_(ThreadT.liftF(State.get[Vector[Int]]).map(_.length >= 10))
}

val thread2 = {
  val mod = ThreadT.liftF(State.modify[Vector[Int]](_ :+ 1)) >> ThreadT.cede
  mod.untilM_(ThreadT.liftF(State.get[Vector[Int]]).map(_.length >= 10))
}

val main = ThreadT.start(thread1) >> ThreadT.start(thread2)

ThreadT.roundRobin(main).runS(Vector()).value   // => Vector(0, 1, 0, 1, 0, 1, 0, 1, 0, 1)
```

Of course, it's quite easy to see what happens if we're *not* cooperative and a single thread hogs all of the resources:

```scala
import coop.ThreadT

import cats.data.State
import cats.implicits._

import scala.collection.immutable.Vector

val thread1 = {
  val mod = ThreadT.liftF(State.modify[Vector[Int]](_ :+ 0)) // >> ThreadT.cede
  mod.untilM_(ThreadT.liftF(State.get[Vector[Int]]).map(_.length >= 10))
}

val thread2 = {
  val mod = ThreadT.liftF(State.modify[Vector[Int]](_ :+ 1)) // >> ThreadT.cede
  mod.untilM_(ThreadT.liftF(State.get[Vector[Int]]).map(_.length >= 10))
}

val main = ThreadT.start(thread1) >> ThreadT.start(thread2)

ThreadT.roundRobin(main).runS(Vector()).value   // => Vector(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
```

The first thread runs until it has filled the entire vector with `0`s, after which it *finally* yields and the second thread only has a chance to insert a single value (which immediately overflows the length).

## MTL Style

A `ApplicativeThread` typeclass, in the style of [Cats MTL](https://github.com/typelevel/cats-mtl), is also provided to make it easier to use `ThreadT` as part of more complex stacks:

```scala
def thread1[F[_]: Monad: ApplicativeThread](implicit F: MonadState[F, Vector[Int]]): F[Unit] = {
  val mod = F.modify(_ :+ 0) >> ApplicativeThread[F].cede
  mod.untilM(F.get.map(_.length >= 10))
}

def main[F[_]: Apply: ApplicativeThread](thread1: F[Unit], thread2: F[Unit]): F[Unit] =
  ApplicativeThread[F].start(thread1) *> ApplicativeThread[F].start(thread2)
```

`ApplicativeThread` will inductively derive over `Kleisli` and `EitherT`, and defines a base instance for `FreeT[S[_], F[_], *]` given an `InjectK[ThreadF, S]` (so, strictly more general than just `ThreadT` itself). It notably will not auto-derive over `StateT` or `WriterT`, due to the value loss which occurs in `fork`/`start`. If you need `StateT`-like functionality, it is recommended you either include some sort of `StateF` in your `FreeT` suspension, or nest the `State` functionality *within* the `FreeT`.

You will probably want to `import FreeTInstances._` to ensure that the appropriate Cats MTL machinery for `FreeT` itself is made available in scope, otherwise instances will not propagate correctly across `FreeT` in the transformer stack. This machinery is probably going to get contributed upstream into a Cats MTL submodule.

## `MVar`

An experimental implementation of `MVar` is made available, mostly because it makes it theoretically possible to define all the things. The API mirrors Haskell's. The implementation assumes an `ApplicativeAsk` (from Cats MTL) of an `UnsafeRef` which contains the uniquely indexed state for every `MVar`. This could have just been done using a private `var` instead, but I wanted to be explicit about the state management.

`UnsafeRef` is used rather than `StateT` or `InjectK[StateF[S, *], F]` to avoid issues with `MonadError` instances in the stack. Additionally, as mentioned earlier, `ApplicativeThread` will not auto-derive over `StateT` due to issues with value loss, so all in all it's a better approach if we aren't going to use a `var`.

## Monitors and Locks

`ThreadT` implements a relatively basic form of await/notify locking as part of the core system. This takes the form of the following three constructors:

- `ThreadT.monitor: ThreadT[M, MonitorId]`
- `ThreadT.await(id: MonitorId): ThreadT[M, Unit]`
- `ThreadT.notify(id: MonitorId): ThreadT[M, Unit]`

Notification has "notify all" semantics. `MonitorId` is simply an opaque identifier which can be used for awaiting/notifying. Sequencing `await` places the current fiber into a locked state. Any number of fibers may be awaiting a given monitor at any time. Sequencing `notify` with a given monitor will reactivate all fibers that are locked on that monitor, in the order in which they `await`ed.

This system exists in order to allow `roundRobin` to implement a form of deadlock detection. Rather than producing an `M[Unit]` from a `ThreadT[M, A]`, it actually produces an `M[Boolean]`, where the `Boolean` indicates whether or not all work was fully completed. If the produced value is `false`, then one or more monitors had awaiting fibers when the worker queue emptied, meaning that those fibers are deadlocked.

## core/src/main/scala/coop/ThreadF.scala

```scala
/*
 * Copyright 2021 Typelevel
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package coop

import cats.Functor

sealed trait ThreadF[+A] extends Product with Serializable

object ThreadF {

  implicit val functor: Functor[ThreadF] = new Functor[ThreadF] {
    def map[A, B](fa: ThreadF[A])(f: A => B): ThreadF[B] = fa match {
      case Fork(left, right) => Fork(() => f(left()), () => f(right()))
      case Cede(results) => Cede(() => f(results()))
      case Done => Done

      case Monitor(body) => Monitor(body.andThen(f))
      case Await(id, results) => Await(id, () => f(results()))
      case Notify(id, results) => Notify(id, () => f(results()))

      case Annotate(text, results) => Annotate(text, () => f(results()))
      case Indent(results) => Indent(() => f(results()))
      case Dedent(results) => Dedent(() => f(results()))
    }
  }

  final case class Fork[A](left: () => A, right: () => A) extends ThreadF[A]
  final case class Cede[A](results: () => A) extends ThreadF[A]
  case object Done extends ThreadF[Nothing]

  final case class Monitor[A](body: MonitorId => A) extends ThreadF[A]
  final case class Await[A](id: MonitorId, results: () => A) extends ThreadF[A]
  final case class Notify[A](id: MonitorId, results: () => A) extends ThreadF[A]

  final case class Annotate[A](text: String, results: () => A) extends ThreadF[A]
  final case class Indent[A](results: () => A) extends ThreadF[A]
  final case class Dedent[A](results: () => A) extends ThreadF[A]

  // an opaque fresh id
  final class MonitorId private[coop] ()
}
```

## core/src/main/scala/coop/ThreadT.scala

```scala
/*
 * Copyright 2021 Typelevel
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package coop

import cats.{~>, Applicative, Functor, Monad, Show}
import cats.data.Const
import cats.free.FreeT
import cats.implicits._

import scala.collection.immutable.Queue

object ThreadT {
  import ThreadF._

  def liftF[M[_]: Functor, A](ma: M[A]): ThreadT[M, A] =
    FreeT.liftT[ThreadF, M, A](ma)

  def fork[M[_]: Applicative, A](left: => A, right: => A): ThreadT[M, A] =
    FreeT.liftF[ThreadF, M, A](Fork(() => left, () => right))

  def cede[M[_]: Applicative]: ThreadT[M, Unit] =
    FreeT.liftF[ThreadF, M, Unit](Cede(() => ()))

  def done[M[_]: Applicative, A]: ThreadT[M, A] =
    FreeT.liftF[ThreadF, M, A](Done)

  def monitor[M[_]: Applicative]: ThreadT[M, MonitorId] =
    FreeT.liftF[ThreadF, M, MonitorId](Monitor(m => m))

  def await[M[_]: Applicative](id: MonitorId): ThreadT[M, Unit] =
    FreeT.liftF[ThreadF, M, Unit](Await(id, () => ()))

  def notify[M[_]: Applicative](id: MonitorId): ThreadT[M, Unit] =
    FreeT.liftF[ThreadF, M, Unit](Notify(id, () => ()))

  def start[M[_]: Applicative, A](child: ThreadT[M, A]): ThreadT[M, Unit] =
    fork[M, Boolean](false, true).ifM(child >> done[M, Unit], ().pure[ThreadT[M, *]])

  def annotate[M[_]: Applicative, A](name: String, indent: Boolean = false)(body: ThreadT[M, A]): ThreadT[M, A] =
    FreeT.liftF[ThreadF, M, Unit](Annotate(name, () => ())) *> {
      if (indent)
        FreeT.liftF[ThreadF, M, Unit](Indent(() => ())) *> body <* FreeT.liftF[ThreadF, M, Unit](Dedent(() => ()))
      else
        body
    }

  def roundRobin[M[_]: Monad, A](main: ThreadT[M, A]): M[Boolean] = {
    // we maintain a separate head just to avoid queue prepending
    case class LoopState(
        head: Option[() => ThreadT[M, _]],
        work: Queue[() => ThreadT[M, _]],
        locks: Map[MonitorId, Queue[() => ThreadT[M, _]]])

    Monad[M].tailRecM(LoopState(Some(() => main), Queue.empty, Map.empty)) { ls =>
      val LoopState(head, work, locks) = ls

      head.tupleRight(work).orElse(work.dequeueOption) match {
        case Some((head, tail)) =>
          head().resume map {
            case Left(Fork(left, right)) =>
              Left(LoopState(Some(left), tail.enqueue(right), locks))

            case Left(Cede(results)) =>
              val tail2 = tail.enqueue(results)
              Left(LoopState(None, tail2, locks))

            case Left(Done) | Right(_) =>
              Left(LoopState(None, tail, locks))

            case Left(Monitor(f)) =>
              val id = new MonitorId()
              Left(LoopState(Some(() => f(id)), tail, locks + (id -> Queue.empty)))

            case Left(Await(id, results)) =>
              Left(LoopState(None, tail, locks.updated(id, locks(id).enqueue(results))))

            case Left(Notify(id, results)) =>
              // enqueueAll was added in 2.13
              val tail2 = locks(id).foldLeft(tail)(_.enqueue(_))
              Left(LoopState(None, tail2.enqueue(results), locks.updated(id, Queue.empty)))

            case Left(Annotate(_, results)) =>
              Left(LoopState(Some(results), tail, locks))

            case Left(Indent(results)) =>
              Left(LoopState(Some(results), tail, locks))

            case Left(Dedent(results)) =>
              Left(LoopState(Some(results), tail, locks))
          }

        // if we have outstanding awaits but no active fibers, then we're deadlocked
        case None =>
          locks.forall(_._2.isEmpty).asRight[LoopState].pure[M]
      }
    }
  }

  private[this] def constK[M[_]]: M ~> Const[Option[String], *] =
    new (M ~> Const[Option[String], *]) {
      def apply[a](ma: M[a]) = Const(None)
    }

  def prettyPrint[M[_]: Monad, A: Show](
      target: ThreadT[M, A],
      render: M ~> Const[Option[String], *] = constK[M],
      limit: Int = 512)   // sanity limit on the number of bytes allowed in the output
      : M[String] = {
    val TurnRight = "╰"
    val TurnLeft = "╯"

    val InverseTurnRight = "╭"
    val InverseTurnLeft = "╮"

    val IndentStr = TurnRight + InverseTurnLeft
    val DedentStr = InverseTurnRight + TurnLeft
    val IndentSpacing = IndentStr.length - 1

    val Junction = "├"
    val Line = "│"

    val ForkStr = Line + " " + TurnRight + InverseTurnLeft
    val ForkSpacing = ForkStr.length - 2

    def drawSpaces(num: Int): String =
      (0 until num).map(_ => ' ').mkString

    def drawIndent(level0: List[Boolean], term: String): String = {
      def loop(level: List[Boolean]): String =
        level match {
          case true :: tail =>
            Line + drawSpaces(ForkSpacing) + loop(tail)

          case false :: tail =>
            drawSpaces(IndentSpacing) + loop(tail)

          case Nil =>
            term
        }

      loop(level0.reverse)
    }

    def drawId(id: MonitorId): String = "0x" + id.hashCode.toHexString.toUpperCase

    case class LoopState(
        target: ThreadT[M, A],
        acc: String,
        indent: List[Boolean],
        init: Boolean = false)

    def loop(target: ThreadT[M, A], acc: String, indent: List[Boolean], init: Boolean): M[String] = {
      Monad[M].tailRecM(LoopState(target, acc, indent, init)) { ls =>
        val LoopState(target, acc0, indent, init) = ls

        val junc0 = if (init) InverseTurnRight else Junction
        val trailing = if (indent != Nil) "\n" + drawIndent(indent, "") else ""

        val resumed = target.resume

        val (junc, front) = render(resumed) match {
          case Const(Some(str)) => (Junction, drawIndent(indent, junc0 + " " + str) + "\n")
          case Const(None) => (junc0, "")
        }

        val acc = acc0 + front

        if (acc.length >= limit) {
          (acc + "\n...").asRight[LoopState].pure[M]
        } else {
          // stack is still proportional to the number of forked fibers, but not the number of binds
          resumed flatMap {
            case Left(Fork(left, right)) =>
              val leading = drawIndent(indent, junc + " Fork") + "\n" + drawIndent(indent, ForkStr)

              loop(right(), "", true :: indent, false) map { rightStr =>
                val acc2 = acc + leading + "\n" + rightStr + "\n"
                LoopState(left(), acc2, indent, false).asLeft[String]
              }

            case Left(Cede(results)) =>
              val acc2 = acc + drawIndent(indent, junc + " Cede") + "\n"
              LoopState(results(), acc2, indent, false).asLeft[String].pure[M]

            case Left(Done) =>
              (acc + drawIndent(indent, TurnRight + " Done" + trailing)).asRight[LoopState].pure[M]

            case Left(Monitor(f)) =>
              val id = new MonitorId
              LoopState(f(id), acc, indent, init).asLeft[String].pure[M]   // don't render the creation

            case Left(Await(id, results)) =>
              val acc2 = acc + drawIndent(indent, junc + " Await ") + drawId(id) + "\n"
              LoopState(results(), acc2, indent, false).asLeft[String].pure[M]

            case Left(Notify(id, results)) =>
              val acc2 = acc + drawIndent(indent, junc + " Notify ") + drawId(id) + "\n"
              LoopState(results(), acc2, indent, false).asLeft[String].pure[M]

            case Left(Annotate(name, results)) =>
              val acc2 = acc + drawIndent(indent, junc + s" $name") + "\n"
              LoopState(results(), acc2, indent, false).asLeft[String].pure[M]

            case Left(Indent(results)) =>
              val acc2 = acc + drawIndent(indent, IndentStr) + "\n"
              LoopState(results(), acc2, false :: indent, false).asLeft[String].pure[M]

            case Left(Dedent(results)) =>
              val indent2 = indent.tail
              val acc2 = acc + drawIndent(indent2, DedentStr) + "\n"
              LoopState(results(), acc2, indent2, false).asLeft[String].pure[M]

            case Right(a) =>
              (acc + drawIndent(indent, TurnRight + " Pure " + a.show + trailing)).asRight[LoopState].pure[M]
          }
        }
      }
    }

    loop(target, "", Nil, true)
  }
}
```


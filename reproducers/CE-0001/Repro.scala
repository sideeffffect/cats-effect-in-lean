//> using scala 3.3.7
//> using dep org.typelevel::cats-effect:3.7.1
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0001 (upstream typelevel/cats-effect#4687):
// `IO#syncStep` drops `uncancelable` and `onCancel` from the `IO` that it returns in `Left`.
//
// Promise: AsyncLaws.syncStepIdentity (laws/.../AsyncLaws.scala:84 at v3.7.1):
//   F.syncStep(fa, limit).flatMap { case Left(fa) => fa; case Right(a) => F.pure(a) } <-> fa
// and the Scaladoc of `IO#syncStep` (core/.../IO.scala:1154-1156): the `Left` value is the rest of
// the original `IO`. So "step, then run the rest" must behave like "run the original".
//
// Method: run each program two ways under TestControl (deterministic, no wall clock):
//   direct  = the program itself
//   stepped = syncStep(Int.MaxValue) in SyncIO, then the `Left` remainder
// Start it as a fiber, let it reach its async boundary, cancel it, and observe the effects.
// The bug shows when `direct` and `stepped` disagree.

import cats.effect.*
import cats.effect.unsafe.implicits.global
import cats.effect.testkit.TestControl
import scala.concurrent.duration.*

object Repro {
  val Id = "CE-0001"

  // Case 1: Resource.use must run the release when the use is canceled.
  def resourceCase(flag: Ref[IO, Boolean]): IO[Unit] =
    Resource.make(IO.unit)(_ => flag.set(true)).use(_ => IO.never)

  // Case 2: an uncancelable region must finish before cancel takes effect.
  def maskCase(flag: Ref[IO, Boolean]): IO[Unit] =
    IO.uncancelable(_ => IO.sleep(1.second) *> flag.set(true))

  // Case 3: onCancel must run its finalizer.
  def onCancelCase(flag: Ref[IO, Boolean]): IO[Unit] =
    IO.never[Unit].onCancel(flag.set(true))

  // The SyncIO prefix only touches the program structure; the program itself allocates nothing
  // before its first async boundary except the Ref, which we make outside.
  def stepped(io: IO[Unit]): IO[Unit] =
    io.syncStep(Int.MaxValue).to[IO].flatMap {
      case Left(rest) => rest
      case Right(a) => IO.pure(a)
    }

  // Start, wait 10 ms of virtual time, cancel, wait for the cancel to finish, read the flag.
  def observe(mk: Ref[IO, Boolean] => IO[Unit], step: Boolean): IO[Boolean] =
    for {
      flag <- IO.ref(false)
      prog = mk(flag)
      fib <- (if (step) stepped(prog) else prog).start
      _ <- IO.sleep(10.millis)
      _ <- fib.cancel
      _ <- fib.join
      v <- flag.get
    } yield v

  def main(args: Array[String]): Unit = {
    val cases = List(
      "Resource.use release runs on cancel" -> resourceCase,
      "uncancelable body completes before cancel" -> maskCase,
      "onCancel finalizer runs on cancel" -> onCancelCase
    )
    var bad = 0
    cases.foreach { case (name, mk) =>
      val d = TestControl.executeEmbed(observe(mk, step = false)).unsafeRunSync()
      val s = TestControl.executeEmbed(observe(mk, step = true)).unsafeRunSync()
      val ok = d == s
      if (!ok) bad += 1
      println(s"$name: direct=$d stepped=$s ${if (ok) "same" else "DIFFERENT"}")
    }
    println(s"cases that differ: $bad / ${cases.size}")
    println(if (bad > 0) s"REPRODUCED $Id" else s"NOT REPRODUCED $Id")
  }
}

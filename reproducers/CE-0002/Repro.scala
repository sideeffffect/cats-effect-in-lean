//> using scala 3.3.7
//> using dep org.typelevel::cats-effect:3.7.1
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0002 (upstream typelevel/cats-effect#4627):
// `Resource.eval` adds a cancelation point after `fa`.
//
// Promise: Scaladoc of `Resource.eval` (kernel/.../Resource.scala:986-987 at v3.7.1):
//   "Lifts an applicative into a resource. The resource has a no-op release. Preserves
//    interruptibility of `fa`."
// So if `fa` is uncancelable, `Resource.eval(fa)` must not be canceled after `fa` completes.
// Twin: `Resource.make(fa)(_ => unit)` has the same no-op release and keeps `fa` masked.
//
// Method: deterministic (TestControl, virtual time; case B uses no time at all).
//   Case A (issue form): Resource.eval(IO.uncancelable(_ => IO.sleep(100 ms))).timeout(10 ms).use_
//     Timeout docs (IO.scala:807): "If the source effect is uncancelable, a TimeoutException
//     will never be raised."
//   Case B (test from upstream fix PR #4630): an uncancelable `fa` that calls `IO.canceled`
//     inside its own mask; the resource is allocated inside `poll` of an outer uncancelable.
//     The continuation after `allocatedCase` must run.
//   Case C (the Lean witness, resourceEvalPreservesUncancelable_refuted): with
//     fa = IO.uncancelable(_ => IO.canceled), `Resource.eval(fa).allocatedCase` must have the same
//     outcome as `IO.uncancelable(_ => Resource.eval(fa).allocatedCase)` (fa is uncancelable, so the
//     allocation must be uncancelable too). Each runs as its own fiber; no time is used.
// Each case runs with `Resource.eval(fa)` and with the twin `Resource.make(fa)(_ => IO.unit)`.

import cats.effect.*
import cats.effect.syntax.all.*
import cats.effect.unsafe.implicits.global
import cats.effect.testkit.TestControl
import scala.concurrent.duration.*

object Repro {
  val Id = "CE-0002"

  type Lift = IO[Unit] => Resource[IO, Unit]
  val viaEval: Lift = fa => Resource.eval(fa)
  val viaMake: Lift = fa => Resource.make(fa)(_ => IO.unit)

  // Case A: true when no TimeoutException is raised.
  def caseA(lift: Lift): IO[Boolean] =
    lift(IO.uncancelable(_ => IO.sleep(100.millis))).timeout(10.millis).use_.attempt.map(_.isRight)

  // Case B: true when the continuation after allocatedCase ran.
  def caseB(lift: Lift): IO[Boolean] = {
    val res = Resource.make(IO.pure(42))(_ => IO.unit).flatMap(_ => lift(IO.uncancelable(_ => IO.canceled)))
    for {
      ctr <- IO.ref(0)
      fib <- IO.uncancelable(poll => poll(res.allocatedCase).flatMap(_ => ctr.update(_ + 1))).start
      _ <- fib.join
      c <- ctr.get
    } yield c == 1
  }

  // Case C: true when masking the allocation does not change its outcome kind.
  def caseC(lift: Lift): IO[Boolean] = {
    val alloc = lift(IO.uncancelable(_ => IO.canceled)).allocatedCase
    for {
      plain <- alloc.start.flatMap(_.join)
      masked <- IO.uncancelable(_ => alloc).start.flatMap(_.join)
    } yield plain.isSuccess == masked.isSuccess && plain.isCanceled == masked.isCanceled
  }

  def main(args: Array[String]): Unit = {
    var bad = 0
    List(
      "A: eval(uncancelable sleep).timeout" -> caseA,
      "B: allocatedCase continuation" -> caseB,
      "C: allocatedCase vs uncancelable(allocatedCase)" -> caseC).foreach {
      case (name, c) =>
        val e = TestControl.executeEmbed(c(viaEval)).unsafeRunSync()
        val m = TestControl.executeEmbed(c(viaMake)).unsafeRunSync()
        if (!e) bad += 1
        println(s"$name: eval ok=$e, make ok=$m ${if (e) "" else "(eval violates the promise)"}")
    }
    println(s"cases that fail with Resource.eval: $bad / 3")
    println(if (bad > 0) s"REPRODUCED $Id" else s"NOT REPRODUCED $Id")
  }
}

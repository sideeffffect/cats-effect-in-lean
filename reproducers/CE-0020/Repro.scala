//> using scala 3.3.7
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0020: `Resource#both` can skip the finalizers of one side when a finalizer of the other
// side raises an error. The skipped resource is never released (a leak).
//
// Resource#both (kernel/.../Resource.scala:286-314 at v3.7.1) stores the finalizers of each
// side in a Ref and runs them in the release of `makeCase`:
//   finalizers.get.flatMap { case (thisFin, thatFin) => F.void(F.both(thisFin(ec), thatFin(ec))) }
// `F.both` runs the two chains in two child fibers (racePair). When `thisFin(ec)` ends with an
// error, `F.both` cancels the other fiber (GenSpawn.scala:476-498). A child fiber is not masked.
// If it has not started yet, or is before the first `guarantee` of its chain
// (`F.unit >> fin(ec).guarantee(release(ec))`), the cancel stops it and `release(ec)` of the
// other side never runs.
// The Scaladoc of `both` (Resource.scala:248-257) says that the finalizers of the two resources
// run concurrently, and that within each resource the nested finalizers run in reverse order.
//
// Program: Resource.make(IO.unit)(_ => markA *> IO.raiseError(boom))
//            .both(Resource.make(IO.unit)(_ => markB)).use_
// Check: after the run, did the release of the right side (markB) run?
// 1. TestControl (deterministic, one thread), seeds 0..999: count of seeds where markB did not run.
// 2. The same program through `parTupled` (the `Parallel[Resource]` instance, which is `both`).
// 3. The default runtime (multi-threaded), 20,000 runs: count of runs where markB did not run.
// 4. `fixedBoth` (a possible fix, not Cats Effect code): run both chains with `attempt`, then
//    raise the first error. Same TestControl seeds; expected 0.
// The last line is REPRODUCED CE-0020 if (1) finds at least one seed.

package cats.effect.repro0020 {

  import cats.effect.*
  import cats.effect.kernel.Resource
  import cats.syntax.all.*
  import cats.effect.syntax.all.*

  /** Not Cats Effect code. `Resource#both` with the release changed (fix candidate). */
  object FixedBoth {
    def both[F[_], A, B](self: Resource[F, A], that: Resource[F, B])(
        implicit F: kernel.Concurrent[F]): Resource[F, (A, B)] = {
      type Finalizer = Resource.ExitCase => F[Unit]
      type Update = (Finalizer => Finalizer) => F[Unit]

      def allocate[C](r: Resource[F, C], storeFinalizer: Update): F[C] =
        r.fold(
          _.pure[F],
          (release, _) => storeFinalizer(fin => ec => F.unit >> fin(ec).guarantee(release(ec)))
        )

      val noop: Finalizer = _ => F.unit
      val bothFinalizers = F.ref((noop, noop))

      Resource
        .makeCase(bothFinalizers) { (finalizers, ec) =>
          finalizers.get.flatMap {
            case (thisFin, thatFin) =>
              F.both(thisFin(ec).attempt, thatFin(ec).attempt).flatMap {
                case (x, y) => F.fromEither(x) *> F.fromEither(y)
              }
          }
        }
        .evalMap { store =>
          val thisStore: Update = f => store.update(_.bimap(f, identity))
          val thatStore: Update = f => store.update(_.bimap(identity, f))
          F.both(allocate(self, thisStore), allocate(that, thatStore))
        }
    }
  }
}

import cats.effect.*
import cats.effect.testkit.TestControl
import cats.effect.unsafe.implicits.global
import cats.syntax.all.*
import java.util.Base64

object Repro {
  type Both = (Resource[IO, Unit], Resource[IO, Unit]) => Resource[IO, (Unit, Unit)]

  val boom = new RuntimeException("boom")

  /** Returns (release of A ran, release of B ran). */
  def prog(both: Both): IO[(Boolean, Boolean)] = for {
    ra <- IO.ref(false)
    rb <- IO.ref(false)
    a = Resource.make(IO.unit)(_ => ra.set(true) *> IO.raiseError[Unit](boom))
    b = Resource.make(IO.unit)(_ => rb.set(true))
    _ <- both(a, b).use_.attempt
    x <- ra.get
    y <- rb.get
  } yield (x, y)

  val ceBoth: Both = (a, b) => a.both(b)
  val parBoth: Both = (a, b) => (a, b).parTupled
  val fixed: Both = (a, b) => cats.effect.repro0020.FixedBoth.both(a, b)

  def seed(s: Int): String = Base64.getEncoder.encodeToString(s.toString.getBytes)

  def missedSeeds(both: Both, n: Int): (Int, Option[Int]) = {
    var missed = 0
    var first: Option[Int] = None
    for (s <- 0 until n) {
      val (_, y) = TestControl.executeEmbed(prog(both), seed = Some(seed(s))).unsafeRunSync()
      if (!y) { missed += 1; if (first.isEmpty) first = Some(s) }
    }
    (missed, first)
  }

  def main(args: Array[String]): Unit = {
    val n = 1000
    val (m1, f1) = missedSeeds(ceBoth, n)
    println(s"1. Resource#both, TestControl seeds 0..${n - 1}: release of B skipped in $m1 seeds (first: $f1)")
    val (m2, f2) = missedSeeds(parBoth, n)
    println(s"2. parTupled (Parallel[Resource]), same seeds: release of B skipped in $m2 seeds (first: $f2)")
    var m3 = 0
    for (_ <- 0 until 20000) if (!prog(ceBoth).unsafeRunSync()._2) m3 += 1
    println(s"3. Resource#both, default runtime, 20000 runs: release of B skipped in $m3 runs")
    val (m4, f4) = missedSeeds(fixed, n)
    println(s"4. fixed twin (attempt both chains), same seeds: release of B skipped in $m4 seeds (first: $f4)")
    println(if (m1 > 0) "REPRODUCED CE-0020" else "NOT REPRODUCED CE-0020")
  }
}

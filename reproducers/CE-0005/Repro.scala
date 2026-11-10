//> using scala 3.3.7
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0005: `IO.bracketFull` and the kernel `MonadCancel#bracketFull` disagree when a cancel is
// requested during acquire and `use` throws when it is called.
//
// IO.bracketFull (core/.../IO.scala:1826-1830 at v3.7.1):
//   IO.uncancelable { poll =>
//     acquire(poll).flatMap { a => IO.defer(poll(use(a))).guaranteeCase(release(a, _)) } }
// `use(a)` is called inside IO.defer, while the fiber is still masked. The cancel waits.
// The throw becomes an error: release gets Errored(e), and the fiber ends Errored(e).
//
// Kernel default (kernel/.../MonadCancel.scala:447-456), the body that every other
// MonadCancel instance uses:
//   uncancelable { poll => acquire(poll).flatMap { a => guaranteeCase(poll(unit >> use(a)))(release(a, _)) } }
// `poll` unmasks first; the run loop sees the cancel before `use(a)` is called:
// release gets Canceled, and the fiber ends Canceled.
// The kernel comment says "we need to lazily evaluate `use` so that uncaught exceptions are
// caught within the effect runtime" (MonadCancel.scala:452-453), so a throwing `use` is a case
// that Cats Effect handles on purpose.
//
// A: acquire = IO.canceled (cancel request inside the mask), run in a child fiber.
// B: the parent cancels the child while acquire runs (decision 50 of the project).
// C: same as B, but `use` has a side effect when it is called (it is called only by IO.bracketFull).
// `kernelBF` is the kernel body written with the same IO operations (`IO#guaranteeCase` is what
// the kernel calls for IO, IO.scala:2026-2027). `fixedBF` is a possible fix (poll before the defer).
//
// Deterministic: TestControl.executeEmbed (virtual time, one thread).

import cats.effect.*
import cats.effect.kernel.*
import cats.effect.testkit.TestControl
import cats.syntax.all.*
import scala.concurrent.duration.*

object Repro extends IOApp.Simple {
  type BF = (Poll[IO] => IO[Unit]) => (Unit => IO[Unit]) => ((Unit, OutcomeIO[Unit]) => IO[Unit]) => IO[Unit]

  val ioBF: BF = a => u => r => IO.bracketFull(a)(u)(r)
  val kernelBF: BF = acquire => use => release =>
    IO.uncancelable { poll => acquire(poll).flatMap { a => poll(IO.unit >> use(a)).guaranteeCase(release(a, _)) } }
  val fixedBF: BF = acquire => use => release =>
    IO.uncancelable { poll => acquire(poll).flatMap { a => poll(IO.defer(use(a))).guaranteeCase(release(a, _)) } }

  val boom = new RuntimeException("boom")

  /** (outcome of the fiber, outcome that release got, was use called) */
  def caseA(bf: BF): IO[(String, String, Boolean)] =
    for {
      log <- Ref[IO].of("-")
      prog = bf(_ => IO.canceled)(_ => throw boom)((_, oc) => log.set(oc.toString))
      oc <- prog.start.flatMap(_.join)
      l <- log.get
    } yield (oc.toString, l, false)

  def caseB(bf: BF, throwing: Boolean): IO[(String, String, Boolean)] =
    for {
      log <- Ref[IO].of("-")
      used <- IO(new java.util.concurrent.atomic.AtomicBoolean(false))
      latch <- Deferred[IO, Unit]
      use = (_: Unit) => { used.set(true); if (throwing) throw boom else IO.unit }
      prog = bf(_ => latch.complete(()) >> IO.sleep(1.second))(use)((_, oc) => log.set(oc.toString))
      fib <- prog.start
      _ <- latch.get
      _ <- fib.cancel
      oc <- fib.join
      l <- log.get
    } yield (oc.toString, l, used.get)

  def show(name: String, r: (String, String, Boolean)): IO[Unit] =
    IO.println(s"  $name: outcome=${r._1}, release got ${r._2}, use called=${r._3}")

  def run = TestControl.executeEmbed(for {
    _ <- IO.println("A: acquire = IO.canceled, use throws")
    a1 <- caseA(ioBF); _ <- show("IO.bracketFull", a1)
    a2 <- caseA(kernelBF); _ <- show("kernel default", a2)
    a3 <- caseA(fixedBF); _ <- show("fixed twin    ", a3)
    _ <- IO.println("B: parent cancels during acquire, use throws")
    b1 <- caseB(ioBF, true); _ <- show("IO.bracketFull", b1)
    b2 <- caseB(kernelBF, true); _ <- show("kernel default", b2)
    b3 <- caseB(fixedBF, true); _ <- show("fixed twin    ", b3)
    _ <- IO.println("C: parent cancels during acquire, use has a side effect")
    c1 <- caseB(ioBF, false); _ <- show("IO.bracketFull", c1)
    c2 <- caseB(kernelBF, false); _ <- show("kernel default", c2)
    reproduced = a1._1 != a2._1 && b1._1 != b2._1 && b1._1.startsWith("Errored")
    _ <- IO.println(if (reproduced) "REPRODUCED CE-0005" else "NOT REPRODUCED CE-0005")
  } yield ())
}

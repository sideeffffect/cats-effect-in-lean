//> using scala 3.3.7
//> using dep org.typelevel::cats-effect:3.7.1
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// Phase 6, track R: smoke test of "no leaked fiber" on the real library (Cats Effect 3.7.1).
// Each side increments a counter when it starts and decrements it in `guarantee` when it ends
// (also when it is canceled). After the combinator returns (or after the parent's
// `cancel` + `join`, decision 50), the counter must be 0: no side is still alive.
// Many TestControl seeds; sides from a small family (pure, raise, canceled, never, sleep,
// masked sleep, cede). Prints the number of runs and violations.

import cats.effect.*
import cats.effect.testkit.TestControl
import cats.syntax.all.*
import scala.concurrent.duration.*

object LeakSmoke extends IOApp.Simple:
  type Side = Ref[IO, Int] => IO[Int]

  def tracked(live: Ref[IO, Int], body: IO[Int]): IO[Int] =
    IO.uncancelable(poll => live.update(_ + 1) *> poll(body).guarantee(live.update(_ - 1)))

  val fam: List[(String, IO[Int])] = List(
    "pure" -> IO.pure(1),
    "raise" -> IO.raiseError(new Exception("boom")),
    "canceled" -> (IO.canceled *> IO.pure(2)),
    "never" -> IO.never[Int],
    "sleep1" -> IO.sleep(1.milli).as(3),
    "maskedSleep" -> IO.uncancelable(_ => IO.sleep(2.millis).as(4)),
    "cede" -> (IO.cede *> IO.pure(5))
  )

  val combs: List[(String, (IO[Int], IO[Int]) => IO[Any])] = List(
    "race" -> ((a, b) => a.race(b)),
    "raceOutcome" -> ((a, b) => a.raceOutcome(b)),
    "both" -> ((a, b) => a.both(b)),
    "bothOutcome" -> ((a, b) => a.bothOutcome(b)),
    "timeout" -> ((a, _) => a.timeout(1.milli))
  )

  def direct(comb: (IO[Int], IO[Int]) => IO[Any], a: IO[Int], b: IO[Int]): IO[Option[Int]] =
    for
      live <- Ref[IO].of(0)
      _ <- comb(tracked(live, a), tracked(live, b)).attempt.void
      n <- live.get
    yield Some(n)

  def parent(comb: (IO[Int], IO[Int]) => IO[Any], a: IO[Int], b: IO[Int], wait: IO[Unit]): IO[Option[Int]] =
    for
      live <- Ref[IO].of(0)
      f <- comb(tracked(live, a), tracked(live, b)).start
      _ <- wait
      _ <- f.cancel
      _ <- f.join
      n <- live.get
    yield Some(n)

  def runOne(io: IO[Option[Int]], seed: Int): IO[Option[Int]] =
    TestControl.execute(io, seed = Some(java.util.Base64.getEncoder.encodeToString(seed.toString.getBytes))).flatMap { c =>
      c.tickFor(1.second) *> c.results.map {
        case Some(Outcome.Succeeded(n)) => n
        case _ => None // root did not complete (blocked by design: masked never, etc.)
      }
    }

  val run: IO[Unit] =
    val waits = List(IO.unit, IO.cede, IO.sleep(1.milli), IO.cede *> IO.cede)
    val jobs = for
      (cn, comb) <- combs
      (an, a) <- fam
      (bn, b) <- fam
      seed <- 0 until 6
      (mode, io) <- ("direct", direct(comb, a, b)) :: waits.zipWithIndex.map((w, i) => (s"parent$i", parent(comb, a, b, w)))
    yield (s"$cn $an $bn $mode seed $seed", io, seed)
    jobs.traverse { (name, io, seed) =>
      runOne(io, seed).map(r => (name, r))
    }.flatMap { rs =>
      val done = rs.count(_._2.isDefined)
      val bad = rs.collect { case (n, Some(k)) if k != 0 => s"$n: live $k" }
      IO.println(s"runs ${rs.size}, root completed ${done}, violations ${bad.size}") *>
        bad.take(20).traverse_(IO.println)
    }

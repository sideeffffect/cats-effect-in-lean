//> using scala 3.3.7
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0090: an effect submitted to a parallel `Dispatcher` while its release runs is accepted (no
// `IllegalStateException`), but it never runs and its `Future` never completes.
//
// Dispatcher (std/.../Dispatcher.scala at v3.7.1): the release runs the finalizers in reverse
// order (:254-285). First each `Worker` resource offers a `PoisonPill` to its queue (:487); the
// worker takes it, sets its own `doneR` and from then on only waits for `terminationLatch`
// (:461-469): it never takes from its queue again. Then the executor `Supervisor(await)` is
// released (:615-621): with `await = true` it waits for all running tasks (with `await = false` it
// cancels them). Only after that the `termination` finalizer sets the dispatcher `doneR` (:257-258).
// `unsafeToFutureCancelable` checks only that `doneR` (:293-295). A submission between the poison
// pill and `doneR.set(true)` passes the check and is offered to a worker queue behind the pill
// (:331-338): nobody takes it.
// Scaladoc of `parallel`/`sequential` (:130-133, :168-171): "Once the resource scope exits, ...
// all active effects will be canceled or awaited, and attempts to submit new effects will throw
// an exception."
//
// Program: Dispatcher.parallel[IO](await = true).allocated; submit task 1 (it waits on a gate);
// start the release in a fiber; 100 ms later (the release waits for task 1) submit task 2 with
// `unsafeToFuture` (task 2 sets a flag and returns 42); open the gate; join the release; wait
// 1 s. Expected: submit 2 throws IllegalStateException, or task 2 runs and its Future completes.
// Actual: submit 2 returns, task 2 never runs, its Future is never completed.
// Runs under TestControl (seeds 0..49) and on the default runtime (50 runs); also once with
// `await = false` on the default runtime (the window is the time the release needs to cancel
// the tasks, about 70 ms here, so it is timing-dependent).
// The last line is REPRODUCED CE-0090 if every await = true run shows the lost submission.

package cats.effect.repro0090 {

  import cats.effect.*
  import cats.effect.std.Dispatcher
  import cats.effect.testkit.TestControl
  import cats.effect.unsafe.implicits.global
  import scala.concurrent.duration.*

  object Repro {

    def seedOf(s: Int): String = java.util.Base64.getEncoder.encodeToString(s.toString.getBytes)

    /** "threw", "ran", or "lost" (submit returned; task did not run; Future not completed). */
    def prog(await: Boolean): IO[String] =
      Dispatcher.parallel[IO](await).allocated.flatMap { case (d, release) =>
        for {
          started <- Deferred[IO, Unit]
          gate <- Deferred[IO, Unit]
          ran <- IO.ref(false)
          _ <- IO(d.unsafeRunAndForget(started.complete(()) *> gate.get))
          _ <- started.get
          relFib <- release.start
          _ <- IO.sleep(100.millis)
          sub <- IO(Right(d.unsafeToFuture(ran.set(true).as(42)))).handleError(e => Left(e))
          _ <- gate.complete(())
          _ <- relFib.joinWithNever
          _ <- IO.sleep(1.second)
          r <- ran.get
        } yield sub match {
          case Left(_: IllegalStateException) => "threw"
          case Left(e) => s"other error $e"
          case Right(f) => if (r || f.value.isDefined) s"ran (${f.value})" else "lost"
        }
      }

    def main(args: Array[String]): Unit = {
      val tc = (0 until 50).map { seed =>
        TestControl
          .executeEmbed(prog(await = true), seed = Some(seedOf(seed)))
          .timeout(1.hour)
          .unsafeRunSync()
      }
      val tcLost = tc.count(_ == "lost")
      println(s"await=true TestControl: ${tc.groupBy(identity).view.mapValues(_.size).toMap}; lost in $tcLost/50 seeds")
      val rt = (0 until 50).map(_ => prog(await = true).timeout(30.seconds).unsafeRunSync())
      val rtLost = rt.count(_ == "lost")
      println(s"await=true default runtime: ${rt.groupBy(identity).view.mapValues(_.size).toMap}; lost in $rtLost/50 runs")
      val f = prog(await = false).timeout(30.seconds).unsafeRunSync()
      println(s"await=false default runtime (timing-dependent): $f")
      if (tcLost == 50 && rtLost == 50) println("REPRODUCED CE-0090")
      else println("NOT REPRODUCED CE-0090")
    }
  }
}

//> using scala 3.3.7
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0091: `Dispatcher.parallel(await = true)` drops an effect that was submitted before the
// scope exits but that no worker has taken yet. The effect never runs, its `Future` never
// completes, and the worker fiber dies with `IllegalStateException: supervisor already shutdown`.
// `Dispatcher.sequential(await = true)` runs the same effect (its "drain" test passes).
//
// Dispatcher (std/.../Dispatcher.scala at v3.7.1): the release runs the finalizers in reverse
// order (:254-285): the Worker finalizer offers a PoisonPill behind the pending registration
// (:487), then the executor `Supervisor(await = true)` is released (:615-621): it sets its done
// flag and joins the fibers it holds, which are none, because the worker has not taken the
// registration yet. When the worker then takes the registration it calls
// `executor(action)` = `supervisor.supervise(task)` (:417, :619) on the closed supervisor, which
// raises `IllegalStateException("supervisor already shutdown")` (Supervisor.scala:320-323). The
// worker fiber fails; the outer Supervisor does not restart it (its own release has begun); the
// promise of the submission is never completed.
// Issue #3506 ("Dispatcher#unsafeRunAndForget seems not to await despite (await = true)") was
// closed as fixed in 3.4.9 with this program shape; the current test for #3506
// (DispatcherSuite.scala:639-647) waits until the effect has started before leaving the scope,
// so it does not cover a pending registration.
// Scaladoc of `parallel(await)` (:130-133, :160-163): "Once the resource scope exits ... all
// active effects will be ... awaited"; "true - wait for the completion of the active fibers".
//
// Program: P(par) = ran <- Ref(false); (if par parallel else sequential)(await = true).use(d =>
// IO(d.unsafeRunAndForget(ran.set(true)))) >> sleep 1s >> ran.get. Also once with
// `unsafeToFuture`: its Future after the scope and 1 s.
// Expected: P(true) = P(false) = true (the effect is awaited), and the Future is completed.
// Runs under TestControl (seeds 0..49) and on the default runtime (200 runs, timing-dependent).
// The last line is REPRODUCED CE-0091 if P(true) is false in every TestControl seed and P(false)
// is true in every TestControl seed.

package cats.effect.repro0091 {

  import cats.effect.*
  import cats.effect.std.Dispatcher
  import cats.effect.testkit.TestControl
  import cats.effect.unsafe.implicits.global
  import scala.concurrent.duration.*

  object Repro {

    def seedOf(s: Int): String = java.util.Base64.getEncoder.encodeToString(s.toString.getBytes)

    def res(par: Boolean) =
      if (par) Dispatcher.parallel[IO](await = true) else Dispatcher.sequential[IO](await = true)

    def prog(par: Boolean): IO[Boolean] = IO.ref(false).flatMap { ran =>
      res(par).use(d => IO(d.unsafeRunAndForget(ran.set(true)))) >> IO.sleep(1.second) >> ran.get
    }

    def future(par: Boolean): IO[String] =
      res(par).use(d => IO(d.unsafeToFuture(IO.pure(42)))).flatMap(f => IO.sleep(1.second) >> IO(s"${f.value}"))

    def main(args: Array[String]): Unit = {
      val tcPar = (0 until 50).map(i => TestControl.executeEmbed(prog(true), seed = Some(seedOf(i))).unsafeRunSync())
      val tcSeq = (0 until 50).map(i => TestControl.executeEmbed(prog(false), seed = Some(seedOf(i))).unsafeRunSync())
      println(s"parallel(await = true) TestControl: effect ran in ${tcPar.count(identity)}/50 seeds")
      println(s"sequential(await = true) TestControl: effect ran in ${tcSeq.count(identity)}/50 seeds")
      val rtPar = (0 until 200).map(_ => prog(true).unsafeRunSync())
      val rtSeq = (0 until 200).map(_ => prog(false).unsafeRunSync())
      println(s"parallel(await = true) default runtime: effect ran in ${rtPar.count(identity)}/200 runs")
      println(s"sequential(await = true) default runtime: effect ran in ${rtSeq.count(identity)}/200 runs")
      val fp = TestControl.executeEmbed(future(true), seed = Some(seedOf(0))).unsafeRunSync()
      val fs = TestControl.executeEmbed(future(false), seed = Some(seedOf(0))).unsafeRunSync()
      println(s"unsafeToFuture after the scope (TestControl seed 0): parallel $fp, sequential $fs")
      if (tcPar.forall(!_) && tcSeq.forall(identity)) println("REPRODUCED CE-0091")
      else println("NOT REPRODUCED CE-0091")
    }
  }
}

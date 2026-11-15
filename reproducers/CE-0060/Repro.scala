//> using scala 3.3.7
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0060: `Semaphore#count` counts canceled waiters. After the waiters are canceled, nobody
// waits, but `count` stays negative until a release reaches the canceled request.
//
// Semaphore (std/.../Semaphore.scala at v3.7.1, PR #4648): a canceled `acquireN` completes its
// gate and calls `reclaim(req)` (:188-191). `reclaim` removes the request only if it is the head
// of the queue (:168-177). A canceled request behind the head stays in the queue; a later
// `releaseN` sweeps it (:237-251). If the head is canceled too, `reclaim(head)` removes the head
// and calls `releaseN(head.sunk)`; with `sunk = 0` that is `F.unit` (:229), so no sweep runs.
// `count` = `-waiting.foldMap(_.remaining)` (:258-263) then counts the canceled request.
// Scaladoc of `count` (:47-53): "returns the number of permits callers are waiting for when there
// are no permits available".
//
// Program A: Semaphore[IO](0); fiber a = s.acquire, wait until count == -1; fiber b = s.acquire,
// wait until count == -2; cancel b; cancel a. Both fibers have ended; nobody waits.
// Expected: count == available == 0. Check: count after the cancels, and again after 1 second.
// Program B: Semaphore[IO](1); the parent takes the permit; a and b wait and are canceled as in A.
// Expected: count == 0 (the parent holds the permit, nobody waits). Then the parent releases.
// Both programs run under TestControl (seeds 0..99) and on the default runtime (200 runs).
// The last line is REPRODUCED CE-0060 if program A shows count != available in every run.

package cats.effect.repro0060 {

  import cats.effect.*
  import cats.effect.std.Semaphore
  import cats.effect.testkit.TestControl
  import cats.effect.unsafe.implicits.global
  import scala.concurrent.duration.*

  object Repro {

    def seedOf(s: Int): String = java.util.Base64.getEncoder.encodeToString(s.toString.getBytes)

    def waitCount(s: Semaphore[IO], c: Long): IO[Unit] =
      s.count.flatMap(n => if (n == c) IO.unit else IO.cede *> waitCount(s, c))

    /** Program A: (count, available, count after 1 s). */
    val programA: IO[(Long, Long, Long)] =
      for {
        s <- Semaphore[IO](0)
        a <- s.acquire.start
        _ <- waitCount(s, -1)
        b <- s.acquire.start
        _ <- waitCount(s, -2)
        _ <- b.cancel
        _ <- a.cancel
        c <- s.count
        v <- s.available
        _ <- IO.sleep(1.second)
        c2 <- s.count
      } yield (c, v, c2)

    /** Program B: (count while the parent holds the permit, count after its release). */
    val programB: IO[(Long, Long)] =
      for {
        s <- Semaphore[IO](1)
        _ <- s.acquire
        a <- s.acquire.start
        _ <- waitCount(s, -1)
        b <- s.acquire.start
        _ <- waitCount(s, -2)
        _ <- b.cancel
        _ <- a.cancel
        c <- s.count
        _ <- s.release
        c2 <- s.count
      } yield (c, c2)

    def main(args: Array[String]): Unit = {
      val seedsA = (0 until 100).map(i => TestControl.executeEmbed(programA, seed = Some(seedOf(i))).unsafeRunSync())
      val badA = seedsA.count { case (c, v, _) => c != v }
      println(s"A TestControl: results ${seedsA.distinct.mkString(", ")}; count != available in $badA/100 seeds")
      val realA = (0 until 200).map(_ => programA.unsafeRunSync())
      val badRealA = realA.count { case (c, v, _) => c != v }
      println(s"A default runtime: results ${realA.distinct.mkString(", ")}; count != available in $badRealA/200 runs")
      val seedsB = (0 until 100).map(i => TestControl.executeEmbed(programB, seed = Some(seedOf(i))).unsafeRunSync())
      println(s"B TestControl: (count while held, count after release) ${seedsB.distinct.mkString(", ")} (expected (0,1))")
      if (badA == 100 && badRealA == 200) println("REPRODUCED CE-0060") else println("NOT REPRODUCED CE-0060")
    }
  }
}

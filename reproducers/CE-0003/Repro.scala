//> using scala 3.3.7
//> using dep org.typelevel::cats-effect:3.7.1
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0003 (upstream typelevel/cats-effect#4571):
// `Queue.take.timeout(d)` loses an element when the fiber that runs it is canceled.
// Cause (upstream comments): `racePair` / `timeout`, not `Queue`. The child fiber of
// `racePair` takes the element; the parent is canceled before it reads the child outcome,
// so the outcome is dropped.
//
// Promise: "no lost element" (undisputed invariant): an element that `take` removed from
// the queue is returned to some caller, or it stays in the queue.
// Supporting Scaladoc, IO#timeout (core/.../IO.scala:800-802 at v3.7.1):
//   "The resulting effect will always wait for the source effect to complete (and to complete
//    its finalizers), and will return the source's outcome over raising a `TimeoutException`."
//
// Method: deterministic. TestControl with explicit seeds 0 until Trials. Each seed gives one
// fixed interleaving. A seed "loses" when the consumer did not return the element and the
// queue is empty after all fibers are done. We print the number of losing seeds and the first.

import cats.effect.*
import cats.effect.std.Queue
import cats.effect.unsafe.implicits.global
import cats.effect.testkit.TestControl
import scala.concurrent.duration.*
import java.util.Base64

object Repro {
  val Id = "CE-0003"
  val Trials = 500

  def seed(n: Int): String = Base64.getEncoder.encodeToString(n.toString.getBytes)

  // A: consumer `take.timeout(1 s)` is canceled from outside just after the offer.
  val external: IO[Boolean] = for {
    q <- Queue.unbounded[IO, Int]
    consumer <- q.take.timeout(1.second).start
    _ <- IO.sleep(1.milli)
    _ <- q.offer(42)
    _ <- consumer.cancel
    oc <- consumer.join
    rest <- q.tryTake
  } yield oc.isCanceled && rest.isEmpty

  // B: issue form, nested timeouts; the outer timeout cancels the inner one.
  val nested: IO[Boolean] = for {
    q <- Queue.unbounded[IO, Int]
    _ <- (IO.sleep(1.milli) *> q.offer(42)).start
    r <- q.take.timeout(1.milli).timeout(1.milli).attempt
    _ <- IO.sleep(1.second) // let the producer finish in every interleaving
    rest <- q.tryTake
  } yield r.isLeft && rest.isEmpty

  def search(name: String, p: IO[Boolean]): Int = {
    val lost = (0 until Trials).filter(i => TestControl.executeEmbed(p, seed = Some(seed(i))).unsafeRunSync())
    println(s"$name: element lost in ${lost.size} / $Trials seeds, first seed ${lost.headOption.getOrElse(-1)}")
    lost.size
  }

  def main(args: Array[String]): Unit = {
    val a = search("A: take.timeout canceled from outside", external)
    val b = search("B: take.timeout.timeout (issue form)", nested)
    println(if (a + b > 0) s"REPRODUCED $Id" else s"NOT REPRODUCED $Id")
  }
}

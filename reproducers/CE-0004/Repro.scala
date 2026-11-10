//> using scala 3.3.7
//> using dep org.typelevel::cats-effect:3.7.1

// CE-0004: `SyncIO` and `IO` handle a fatal `raiseError` differently.
//
// IO run loop (core/.../IOFiber.scala:265-269 at v3.7.1), branch `Error`:
//   if (!UnsafeNonFatal(ex)) onFatalFailure(ex)
// so `IO.raiseError(fatal)` shuts down all runtimes and rethrows; no handler sees it
// (since PR #3811, issue #3767).
// SyncIO run loop (core/.../SyncIO.scala:257-259 at v3.7.1), branch `Error`:
//   runLoop(failed(cur.t, 0))
// no fatal check, so `SyncIO.raiseError(fatal)` is an ordinary error that `handleErrorWith`
// catches.
//
// Observable twin difference (public API only):
//   sio = SyncIO.raiseError(fatal).handleErrorWith(_ => SyncIO.pure(1))
//   A: sio.unsafeRunSync()                                   -> 1
//   B: sio.to[IO].syncStep(Int.MaxValue).unsafeRunSync()      -> Right(1)  (the SyncIO run loop again)
//   C: sio.to[IO].unsafeRunSync()                            -> throws the fatal error
// `SyncIO#to` "translates this SyncIO to any F[_]" (SyncIO.scala:190-208), and `IO#syncStep` must
// satisfy AsyncLaws.syncStepIdentity (laws/.../AsyncLaws.scala:84-88). A and B give 1, C does not.
//
// Deterministic: A and B run on the caller thread (no runtime). C runs once, last: the first
// fatal failure shuts down all runtimes (IOFiber.scala:1597-1646) and completes the
// `unsafeRunSync` callback with the error, so the caller gets it. A second fatal run in the same
// JVM would not be observable (the global flag is set), so there is only one.

import cats.effect.*
import cats.effect.unsafe.implicits.global
import scala.concurrent.duration.*

object Repro {
  val Id = "CE-0004"

  // A fatal error (`VirtualMachineError`, UnsafeNonFatal.scala:37-41). No stack trace, so the
  // runtime's error report on stderr stays short.
  final class Fatal extends OutOfMemoryError("CE-0004 fatal error") {
    override def fillInStackTrace(): Throwable = this
  }

  def sio: SyncIO[Int] =
    SyncIO.raiseError[Int](new Fatal).handleErrorWith(_ => SyncIO.pure(1))

  def show(r: => Any): String =
    try r.toString
    catch { case t: Throwable => s"threw ${t.getClass.getSimpleName}" }

  def main(args: Array[String]): Unit = {
    val a = show(sio.unsafeRunSync())
    println(s"A SyncIO.unsafeRunSync: $a")

    val b = show(sio.to[IO].syncStep(Int.MaxValue).unsafeRunSync())
    println(s"B to[IO].syncStep(Int.MaxValue).unsafeRunSync: $b")

    val c = show(sio.to[IO].unsafeRunTimed(10.seconds) match {
      case Some(v) => v
      case None => "timeout"
    })
    println(s"C to[IO].unsafeRunSync: $c")

    val differs = a == "1" && b == "Right(1)" && c != "1"
    println(s"SyncIO recovers from the fatal error, IO does not: ${if (differs) "DIFFERENT" else "same"}")
    println(if (differs) s"REPRODUCED $Id" else s"NOT REPRODUCED $Id")
  }
}

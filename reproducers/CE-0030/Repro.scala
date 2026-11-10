//> using scala 3.3.7
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// CE-0030: a `get` of `IO#memoize` hangs forever, and cannot be canceled, when `fa` cancels
// itself while the `get` is between `state.get` and `state.flatModifyFull`.
//
// GenConcurrent#memoize (kernel/shared/src/main/scala/cats/effect/kernel/GenConcurrent.scala:43-110
// at v3.7.1; IO#memoize = Concurrent[IO].memoize, IO.scala:944-945):
//   state.get.flatMap {
//     case Finished(result) => fromEither(result).flatten          // line 108: not masked
//     case _ => evalOrSubscribe                                     // -> state.flatModifyFull { ... }
//   }
//   ... state.flatModifyFull {                                      // = uncancelable(poll => flatten(modify(...)))
//     case (_, finished @ Finished(result)) => finished -> fromEither(result).flatten   // lines 91-92: masked, no poll
//   }
// When `fa` cancels itself, the result is Finished(Right(canceled *> never)). A `get` that reads
// Finished in `state.get` runs `canceled *> never` unmasked and ends Canceled. A `get` that read
// Unevaluated/Evaluating in `state.get` and then sees Finished in `flatModifyFull` runs
// `canceled *> never` inside the mask: `canceled` does nothing, and `never` waits forever.
// `fiber.cancel` on that fiber waits forever too (cancel is backpressured and the fiber is masked).
//
// Program: memo <- IO.canceled.memoize; a <- memo.start; b <- memo.start; then join both.
// TestControl (one thread, virtual time). The window needs a fiber switch between two run-loop
// iterations of `get`; on one thread that is an auto-yield, so the runs use small
// IORuntimeConfig thresholds (cancelationCheckThreshold, autoYieldThreshold). A multi-threaded
// runtime switches fibers anywhere; the thresholds are not a promise of Cats Effect.
// Each case runs 200 TestControl seeds. "hang" = the join of a or b did not end in 10 s (virtual)
// and `b.cancel` / `a.cancel` did not end either.
//
// `fixedMemoize` is a possible fix (not Cats Effect code): `poll(fromEither(result).flatten)` in the
// Finished case. `copyMemoize` is the same code without the fix (a check that the copy is faithful).

import cats.effect.*
import cats.effect.kernel.*
import cats.effect.unsafe.IORuntimeConfig
import cats.effect.testkit.TestControl
import cats.syntax.all.*
import scala.concurrent.duration.*
import java.util.Base64

object Repro extends IOApp.Simple {

  sealed trait M[A]
  final case class Unevaluated[A]() extends M[A]
  final case class Evaluating[A](fiber: Deferred[IO, Fiber[IO, Throwable, A]], subscribers: Int) extends M[A]
  final case class Finished[A](result: Either[Throwable, IO[A]]) extends M[A]

  // GenConcurrent.memoize with F = IO, copied; `fix` adds `poll` in the Finished case.
  def memo[A](fa: IO[A], fix: Boolean): IO[IO[A]] = {
    val F = Concurrent[IO]
    IO.ref[M[A]](Unevaluated()).map { state =>
      def evalOrSubscribe: IO[A] =
        IO.deferred[Fiber[IO, Throwable, A]].flatMap { deferredFiber =>
          state.flatModifyFull {
            case (poll, Unevaluated()) =>
              val go = {
                def tryComplete(result: M[A]): IO[Unit] = state.update {
                  case Evaluating(fiber, _) if fiber eq deferredFiber => result
                  case other => other
                }
                fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_)).guaranteeCase {
                  case Outcome.Canceled() => tryComplete(Finished(Right(F.productR(F.canceled)(F.never))))
                  case Outcome.Errored(err) => tryComplete(Finished(Left(err)))
                  case Outcome.Succeeded(fa) => tryComplete(Finished(Right(fa)))
                }
              }
              val eval = go.start.flatMap { fiber =>
                deferredFiber.complete(fiber) *>
                  poll(fiber.join.flatMap(_.embed(F.productR(F.canceled)(F.never))))
                    .onCancel(unsubscribe(deferredFiber))
              }
              Evaluating(deferredFiber, 1) -> eval
            case (poll, Evaluating(fiber, subscribers)) =>
              Evaluating(fiber, subscribers + 1) ->
                poll(fiber.get.flatMap(_.join).flatMap(_.embed(F.productR(F.canceled)(F.never))))
                  .onCancel(unsubscribe(fiber))
            case (poll, finished @ Finished(result)) =>
              val io = F.fromEither(result).flatten
              finished -> (if (fix) poll(io) else io)
          }
        }
      def unsubscribe(expected: Deferred[IO, Fiber[IO, Throwable, A]]): IO[Unit] =
        state.modify {
          case Evaluating(fiber, subscribers) if fiber eq expected =>
            if (subscribers == 1) Unevaluated[A]() -> fiber.get.flatMap(_.cancel)
            else Evaluating(fiber, subscribers - 1) -> IO.unit
          case other => other -> IO.unit
        }.flatten
      state.get.flatMap {
        case Finished(result) => F.fromEither(result).flatten
        case _ => evalOrSubscribe
      }
    }
  }

  type Memoize = IO[Unit] => IO[IO[Unit]]
  val ioMemoize: Memoize = _.memoize
  val copyMemoize: Memoize = memo(_, fix = false)
  val fixedMemoize: Memoize = memo(_, fix = true)

  /** true = a `get` hangs (its join does not end, and its cancel does not end). */
  def prog(m: Memoize): IO[Boolean] = for {
    get <- m(IO.canceled)
    a <- get.start
    b <- get.start
    oa <- a.join.timeout(10.seconds).attempt
    ob <- b.join.timeout(10.seconds).attempt
    ca <- a.cancel.start
    cb <- b.cancel.start
    ra <- ca.join.timeout(10.seconds).attempt
    rb <- cb.join.timeout(10.seconds).attempt
  } yield (oa.isLeft && ra.isLeft) || (ob.isLeft && rb.isLeft)

  def seed(n: Int): String = Base64.getEncoder.encodeToString(n.toString.getBytes)
  val Seeds = 200

  def count(m: Memoize, cfg: IORuntimeConfig): IO[Int] =
    (0 until Seeds).toList.traverse(s => TestControl.executeEmbed(prog(m), cfg, Some(seed(s)))).map(_.count(identity))

  def run = {
    val cfgs = List(IORuntimeConfig(1, 2), IORuntimeConfig(1, 4), IORuntimeConfig(2, 4), IORuntimeConfig())
    for {
      rows <- cfgs.traverse { cfg =>
        for {
          io <- count(ioMemoize, cfg)
          cp <- count(copyMemoize, cfg)
          fx <- count(fixedMemoize, cfg)
          name = s"(${cfg.cancelationCheckThreshold},${cfg.autoYieldThreshold})"
          _ <- IO.println(f"thresholds $name%-11s seeds with a hung get: IO#memoize $io%3d/$Seeds, copy $cp%3d/$Seeds, fixed twin $fx%3d/$Seeds")
        } yield (io, fx)
      }
      bug = rows.exists(_._1 > 0) && rows.forall(_._2 == 0)
      _ <- IO.println(if (bug) "REPRODUCED CE-0030" else "NOT REPRODUCED CE-0030")
    } yield ()
  }
}

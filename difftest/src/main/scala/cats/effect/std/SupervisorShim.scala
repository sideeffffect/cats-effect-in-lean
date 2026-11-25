package cats.effect.std

import cats.effect.{IO, Outcome, Resource}

/** Difftest access (format v2, Phase 7 track V) to the private `Supervisor` entry points:
  * `Supervisor.apply(await, checkRestart)` (`private[std]`, `Supervisor.scala:131-139`; `IO` takes
  * the `Async` branch) and `Supervisor.applyForConcurrent` (`private[effect]`,
  * `Supervisor.scala:331-366`). `rs = true` is Dispatcher's `checkRestart = Some(_ => true)`.
  */
object SupervisorShim:
  def apply(await: Boolean, rs: Boolean, cv: Boolean): Resource[IO, Supervisor[IO]] =
    val checkRestart: Option[Outcome[IO, Throwable, ?] => Boolean] =
      if rs then Some((_: Outcome[IO, Throwable, ?]) => true) else None
    if cv then Supervisor.applyForConcurrent[IO](await, checkRestart)
    else Supervisor[IO](await, checkRestart)

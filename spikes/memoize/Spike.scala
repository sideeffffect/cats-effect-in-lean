//> using scala 3.3.7
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// Track M spike (Phase 6): does a `get` of `IO#memoize` hang when `fa` cancels itself
// while a second `get` is between `state.get` and `state.flatModifyFull`?
// Run: scala-cli run spikes/memoize/Spike.scala

import cats.effect.*
import cats.effect.kernel.*
import cats.effect.unsafe.IORuntimeConfig
import cats.effect.testkit.TestControl
import cats.syntax.all.*
import scala.concurrent.duration.*

object Spike extends IOApp.Simple {
  def prog: IO[String] = for {
    memo <- IO.canceled.memoize
    a <- memo.start
    b <- memo.start
    oa <- a.join.timeout(10.seconds).attempt
    ob <- b.join.timeout(10.seconds).attempt
    cf <- b.cancel.start
    cb <- cf.join.timeout(10.seconds).attempt
  } yield s"A=${oa.fold(_ => "HANG", _.toString)} B=${ob.fold(_ => "HANG", _.toString)} cancelB=${cb.fold(_ => "HANG", _ => "ok")}"

  def run = {
    val cfgs = List(IORuntimeConfig(), IORuntimeConfig(1, 2), IORuntimeConfig(1, 4), IORuntimeConfig(2, 4))
    cfgs.traverse_ { cfg =>
      (0 until 200).toList.traverse { s =>
        TestControl.executeEmbed(prog, cfg, Some(java.util.Base64.getEncoder.encodeToString(s.toString.getBytes))).handleError(e => "ERR " + e.getClass.getSimpleName)
      }.flatMap { rs =>
        IO.println(s"cfg=(${cfg.cancelationCheckThreshold},${cfg.autoYieldThreshold}): " + rs.groupBy(identity).view.mapValues(_.size).toMap)
      }
    }
  }
}

//> using scala 3.3.7
//> using dep org.typelevel::cats-effect:3.7.1

// Track M spike (CE-0030): does the hung `get` also happen on the default multi-threaded
// runtime (default IORuntimeConfig)? Two `get` fibers race a self-canceling `fa`.
// Run: scala-cli run spikes/memoize/RealRuntime.scala -- 20000

import cats.effect.*
import cats.syntax.all.*
import scala.concurrent.duration.*

object RealRuntime extends IOApp {
  def once: IO[Boolean] = for {
    get <- IO.canceled.memoize
    a <- get.start
    b <- get.start
    oa <- a.join.timeout(500.millis).attempt
    ob <- b.join.timeout(500.millis).attempt
  } yield oa.isLeft || ob.isLeft

  def run(args: List[String]) = {
    val n = args.headOption.map(_.toInt).getOrElse(20000)
    (1 to n).toList.traverse(_ => once).flatMap { rs =>
      IO.println(s"default runtime, ${Runtime.getRuntime.availableProcessors} CPUs: hung get in ${rs.count(identity)} of $n runs")
    }.as(ExitCode.Success)
  }
}

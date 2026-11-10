//> using scala 3.3.4
//> using dep org.typelevel::cats-effect:3.7.1
//> using dep org.typelevel::cats-effect-testkit:3.7.1

// Phase 0 step 2 spike: can a chosen schedule drive real IO, and can we log it?
// Part A: TestControl with seeds (random order, reproducible per seed, no choice).
// Part B: a scripted ExecutionContext in a real IORuntime. A choice list picks
//         which ready task runs next. Each step is logged with its fiber.

import cats.effect.{IO, Ref}
import cats.effect.testkit.TestControl
import cats.effect.unsafe.{IORuntime, IORuntimeConfig, Scheduler}
import cats.syntax.all.*

import scala.collection.mutable
import scala.concurrent.ExecutionContext
import scala.concurrent.duration.*

// Two fibers. Each appends a label, cedes, appends a second label.
// The final list shows the interleaving that happened.
def program: IO[List[String]] =
  for
    log <- Ref[IO].of(Vector.empty[String])
    fa <- (log.update(_ :+ "a1") >> IO.cede >> log.update(_ :+ "a2")).start
    fb <- (log.update(_ :+ "b1") >> IO.cede >> log.update(_ :+ "b2")).start
    _ <- fa.join >> fb.join
    r <- log.get
  yield r.toList

// ---------------------------------------------------------------- Part B
final class ScriptedEC extends ExecutionContext:
  val ready = mutable.ArrayBuffer.empty[Runnable]
  def execute(r: Runnable): Unit = ready += r
  def reportFailure(t: Throwable): Unit = println(s"reportFailure: $t")

final class Driver(choices: List[Int]):
  val ec = ScriptedEC()
  private var now = 0L // virtual nanos
  private val timers = mutable.ArrayBuffer.empty[(Long, Runnable)]
  private val ids = mutable.Map.empty[Int, String] // identityHashCode -> label
  val trace = mutable.ArrayBuffer.empty[String]

  private def label(r: Runnable): String =
    val isFiber = r.getClass.getName == "cats.effect.IOFiber" // IOFiber is private[effect]
    val key = System.identityHashCode(r)
    ids.getOrElseUpdate(key, (if isFiber then "fiber#" else "task#") + ids.size)

  val scheduler = new Scheduler:
    def sleep(d: FiniteDuration, t: Runnable): Runnable =
      val e = (now + d.toNanos, t); timers += e; () => { timers -= e; () }
    def nowMillis(): Long = now / 1000000
    def monotonicNanos(): Long = now

  val runtime = IORuntime(ec, ec, scheduler, () => (), IORuntimeConfig())

  def run[A](io: IO[A]): (Option[cats.effect.Outcome[cats.Id, Throwable, A]], List[String]) =
    var result: Option[cats.effect.Outcome[cats.Id, Throwable, A]] = None
    io.unsafeRunAsyncOutcome(oc => result = Some(oc))(runtime)
    var cs = choices
    var step = 0
    while ec.ready.nonEmpty || timers.nonEmpty do
      if ec.ready.isEmpty then // advance virtual time to the earliest timer
        val (t, r) = timers.minBy(_._1); timers -= ((t, r)); now = t; ec.ready += r
      val readyLabels = ec.ready.map(label).toList
      val pick = cs match
        case h :: t => cs = t; if h < 0 then ec.ready.size - 1 else h % ec.ready.size // -1 = newest
        case Nil => 0 // default: oldest first (FIFO)
      val r = ec.ready.remove(pick)
      trace += s"step $step: ready=${readyLabels.mkString("[", ",", "]")} pick=$pick -> ${label(r)}"
      r.run()
      step += 1
    (result, trace.toList)

@main def main(): Unit =
  import cats.effect.unsafe.implicits.global

  println("== Part A: TestControl, seeds ==")
  val seeds = List(1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L).map(s =>
    java.util.Base64.getEncoder.encodeToString(s.toString.getBytes))
  for s <- seeds do
    val r1 = TestControl.executeEmbed(program, seed = Some(s)).unsafeRunSync()
    val r2 = TestControl.executeEmbed(program, seed = Some(s)).unsafeRunSync()
    println(s"seed=$s -> $r1 (rerun equal: ${r1 == r2})")

  println("== Part B: scripted schedule ==")
  for (name, choices) <- List("FIFO (all 0)" -> Nil, "chosen [0,1,0,1,...]" -> List(0, 1, 0, 1, 0, 1, 0, 1, 0, 1),
      "chosen pick newest (LIFO)" -> List.fill(20)(-1)) do
    val d = Driver(choices)
    val (res, trace) = d.run(program)
    println(s"-- $name -> outcome $res")
    trace.foreach(l => println("   " + l))

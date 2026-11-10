package cats.effect.difftest

import cats.effect.{IO, Outcome}
import cats.effect.testkit.TestControl
import cats.effect.unsafe.{IORuntime, IORuntimeConfig, Scheduler}

import scala.collection.mutable
import scala.concurrent.ExecutionContext
import scala.concurrent.duration.*

/** Ready list of the scripted runtime. `execute` appends; the driver removes by index. Each
  * runnable gets a stable label at its first enqueue: `f<k>` for IOFibers (k = order of first
  * enqueue, root = f0), `x<k>` for external-cancel fibers, or its own label (`cb..`, `t..`).
  */
final class ScriptedEC extends ExecutionContext:
  val ready = mutable.ArrayBuffer.empty[Runnable]
  val failures = mutable.ArrayBuffer.empty[String]
  private val labels = new java.util.IdentityHashMap[Runnable, String]
  private var fiberCount = 0

  /** If set, the next new IOFiber gets this label instead of `f<k>` (external cancelers). */
  var nextLabel: Option[String] = None

  def label(r: Runnable): String =
    r match
      case l: Labeled => l.label
      case _ =>
        val old = labels.get(r)
        if old != null then old
        else
          val l = nextLabel.getOrElse { fiberCount += 1; s"f${fiberCount - 1}" }
          nextLabel = None
          labels.put(r, l)
          l

  def execute(r: Runnable): Unit =
    label(r)
    ready += r

  // A TimeoutException message holds the duration, which the Lean model does not keep (v1).
  def reportFailure(t: Throwable): Unit = t match
    case _: java.util.concurrent.TimeoutException => failures += "TimeoutException"
    case _ => failures += s"${t.getClass.getSimpleName}: ${t.getMessage}"

/** Result of one case, before JSON encoding. */
final case class RunResult(
    outcome: ujson.Value,
    trace: List[ujson.Value],
    steps: Int,
    timeMs: Option[Long],
    schedule: ujson.Value,
    fifoFrom: Option[Int],
    fibers: ujson.Value,
    pending: Int,
    failures: List[String])

object Runner:

  private def outcomeJson(oc: Outcome[cats.Id, Throwable, Val]): ujson.Value = oc match
    case Outcome.Succeeded(v) => ujson.Obj("t" -> "succeeded", "v" -> Json.encodeVal(v))
    case Outcome.Errored(t) =>
      Json.encodeErr(t match
        case CodeOf(c) => Err.User(c)
        case o => Err.Foreign(s"${o.getClass.getSimpleName}: ${o.getMessage}"))
    case Outcome.Canceled() => ujson.Obj("t" -> "canceled")

  def run(c: TestCase): ujson.Value =
    val r = c.mode match
      case Mode.Replay(choices) => replay(c.prog, choices, c.maxSteps)
      case Mode.TestControlSeed(seed) => testControl(c.prog, seed, c.maxSteps)
    val modeName = c.mode match
      case _: Mode.Replay => "replay"
      case _: Mode.TestControlSeed => "testcontrol"
    ujson.Obj(
      "v" -> c.version,
      "id" -> c.id,
      "mode" -> modeName,
      "outcome" -> r.outcome,
      "trace" -> ujson.Arr.from(r.trace),
      "steps" -> r.steps,
      "time" -> r.timeMs.fold[ujson.Value](ujson.Null)(t => ujson.Num(t.toDouble)),
      "schedule" -> r.schedule,
      "fifoFrom" -> r.fifoFrom.fold[ujson.Value](ujson.Null)(i => ujson.Num(i)),
      "fibers" -> r.fibers,
      "pending" -> r.pending,
      "failures" -> ujson.Arr.from(r.failures.map(ujson.Str(_)))
    )

  // ---------------------------------------------------------- replay mode

  /** Scripted run. One step = remove one ready task and run it (one IOFiber.run() or one
    * callback/timer task). Time moves only when the ready list is empty: then all timers with
    * the earliest due time move to the ready list in creation order. The run stops when the
    * root fiber has an outcome, when nothing is ready and no timer exists ("blocked"), or at
    * maxSteps ("fuel").
    */
  def replay(prog: Prog, choices: List[Choice], maxSteps: Int): RunResult =
    val h = Harness()
    val ec = ScriptedEC()
    var now = 0L // virtual nanoseconds
    var timerCount = 0
    val timers = mutable.ArrayBuffer.empty[(Long, Labeled)]
    val scheduler = new Scheduler:
      def sleep(d: FiniteDuration, t: Runnable): Runnable =
        val task = CbTask(s"t$timerCount", () => t.run())
        timerCount += 1
        val e = (now + d.toNanos, task)
        timers += e
        () => { timers -= e; () }
      def nowMillis(): Long = now / 1000000
      def monotonicNanos(): Long = now
    val runtime = IORuntime(ec, ec, scheduler, () => (), IORuntimeConfig())

    var result: Option[Outcome[cats.Id, Throwable, Val]] = None
    val root = Interp(h).root(prog).unsafeRunFiber(
      { result = Some(Outcome.Canceled()) },
      t => result = Some(Outcome.Errored(t)),
      v => result = Some(Outcome.Succeeded[cats.Id, Throwable, Val](v)),
      registerCallback = false
    )(runtime)
    h.setRoot(root)

    val log = mutable.ArrayBuffer.empty[ujson.Value]
    var cs = choices
    var step = 0
    var cancels = 0
    var fifoFrom: Option[Int] = None
    var stop: Option[String] = None

    while result.isEmpty && stop.isEmpty do
      cs match
        case Choice.CancelFiber(hd) :: rest =>
          // External cancel. It does not need a ready task. The canceler is a new fiber:
          // unsafeRunFiber enqueues it, then it runs at once as this step.
          cs = rest
          if step >= maxSteps then stop = Some("fuel")
          else
            h.fiberAt(hd) match
              case None => log += ujson.Obj("cancel" -> hd, "skipped" -> true)
              case Some(f) =>
                val readyLabels = ujson.Arr.from(ec.ready.map(r => ujson.Str(ec.label(r))))
                ec.nextLabel = Some(s"x$cancels")
                cancels += 1
                val canceler = f.cancel.unsafeRunFiber((), _ => (), _ => (), registerCallback = false)(runtime)
                ec.ready -= canceler
                log += ujson.Obj("step" -> step, "ready" -> readyLabels, "cancel" -> hd, "task" -> ec.label(canceler))
                canceler.run()
                step += 1
        case _ =>
          if step >= maxSteps then stop = Some("fuel")
          else if ec.ready.isEmpty && timers.isEmpty then stop = Some("blocked")
          else
            if ec.ready.isEmpty then
              val t = timers.map(_._1).min
              val due = timers.filter(_._1 == t).toList
              timers --= due
              now = t
              due.foreach((_, task) => ec.execute(task))
              log += ujson.Obj("advance" -> (t / 1000000).toDouble, "woken" -> ujson.Arr.from(due.map(d => ujson.Str(d._2.label))))
            val readyLabels = ujson.Arr.from(ec.ready.map(r => ujson.Str(ec.label(r))))
            val i = cs match
              case Choice.Pick(i) :: rest => cs = rest; i
              case _ =>
                if fifoFrom.isEmpty then fifoFrom = Some(step)
                0
            val idx = i % ec.ready.size
            val r = ec.ready.remove(idx)
            log += ujson.Obj("step" -> step, "ready" -> readyLabels, "pick" -> idx, "task" -> ec.label(r))
            r.run()
            step += 1

    val outcome = result match
      case Some(oc) => outcomeJson(oc)
      case None => ujson.Obj("t" -> stop.get)
    val fibers = ujson.Obj.from(h.fibers.zipWithIndex.collect {
      case (f, i) if f != null => i.toString -> ujson.Str(ec.label(f.asInstanceOf[Runnable]))
    })
    runtime.shutdown()
    RunResult(outcome, h.trace, step, Some(now / 1000000), ujson.Arr.from(log), fifoFrom, fibers,
      ec.ready.size + timers.size, ec.failures.toList)

  // ------------------------------------------------------ testcontrol mode

  /** TestControl run with a seed. One step = one successful `tickOne`. When no task is ready,
    * time advances by `nextInterval`. At maxSteps the outcome is "inconclusive" (decision 4).
    */
  def testControl(prog: Prog, seed: Long, maxSteps: Int): RunResult =
    import cats.effect.unsafe.implicits.global
    val h = Harness()
    val b64 = java.util.Base64.getEncoder.encodeToString(seed.toString.getBytes("UTF-8"))

    def loop(c: TestControl[Val], steps: Int): IO[(ujson.Value, Int)] =
      c.results.flatMap {
        case Some(oc) => IO.pure((outcomeJson(oc), steps))
        case None if steps >= maxSteps => IO.pure((ujson.Obj("t" -> "inconclusive"), steps))
        case None =>
          c.tickOne.flatMap { ran =>
            if ran then loop(c, steps + 1)
            else
              c.isDeadlocked.flatMap { dead =>
                if dead then IO.pure((ujson.Obj("t" -> "blocked"), steps))
                else c.nextInterval.flatMap(d => c.advance(d) *> loop(c, steps))
              }
          }
      }

    val prog0 = Interp(h).root(prog)
    val (outcome, steps) = TestControl.execute(prog0, seed = Some(b64)).flatMap(loop(_, 0)).unsafeRunSync()
    RunResult(outcome, h.trace, steps, None, ujson.Obj("seed" -> seed.toDouble), None,
      ujson.Obj(), 0, Nil)

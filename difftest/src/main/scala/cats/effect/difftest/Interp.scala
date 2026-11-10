package cats.effect.difftest

import cats.effect.{Deferred, Fiber, IO, Outcome, Poll, Ref, Resource}
import cats.effect.std.Queue

import scala.collection.mutable.ArrayBuffer
import scala.concurrent.duration.*
import scala.util.control.NonFatal

import java.util.concurrent.TimeoutException

import Val.*

/** A runnable with a fixed label for the schedule log (callback tasks, timer tasks). */
trait Labeled extends Runnable:
  def label: String

final class CbTask(val label: String, body: () => Unit) extends Labeled:
  def run(): Unit = body()

/** Run-time state of one test case: trace and handle tables. Handle ids count up from 0 in
  * creation order per kind. Fiber handle 0 is the root fiber (replay mode only).
  */
final class Harness:
  private val buf = ArrayBuffer.empty[ujson.Value]
  def emit(ev: ujson.Obj): Unit = synchronized { buf += ev; () }
  def trace: List[ujson.Value] = synchronized(buf.toList)

  val fibers = ArrayBuffer[Fiber[IO, Throwable, Val]](null) // slot 0: root
  private val fiberIds = new java.util.IdentityHashMap[AnyRef, Integer]
  val refs = ArrayBuffer.empty[Ref[IO, Val]]
  val deferreds = ArrayBuffer.empty[Deferred[IO, Val]]
  private var asyncs = 0

  def setRoot(f: Fiber[IO, Throwable, Val]): Unit = synchronized {
    fibers(0) = f; fiberIds.put(f, 0); ()
  }

  def fiberHandle(f: Fiber[IO, Throwable, Val]): Int = synchronized {
    val old = fiberIds.get(f)
    if old != null then old.intValue
    else
      fibers += f
      fiberIds.put(f, fibers.size - 1)
      fibers.size - 1
  }

  /** Fiber object of a handle, if it exists (used for external cancel). */
  def fiberAt(h: Int): Option[Fiber[IO, Throwable, Val]] = synchronized {
    if h >= 0 && h < fibers.size then Option(fibers(h)) else None
  }

  /** Handle of a fiber object, if it has one (used to label tasks). */
  def handleOf(r: AnyRef): Option[Int] = synchronized(Option(fiberIds.get(r)).map(_.intValue))

  def newRef(r: Ref[IO, Val]): Int = synchronized { refs += r; refs.size - 1 }
  def newDeferred(d: Deferred[IO, Val]): Int = synchronized { deferreds += d; deferreds.size - 1 }
  val queues = ArrayBuffer.empty[Queue[IO, Val]]
  def newQueue(q: Queue[IO, Val]): Int = synchronized { queues += q; queues.size - 1 }
  def newAsync(): Int = synchronized { asyncs += 1; asyncs - 1 }

/** The error code of `java.util.concurrent.TimeoutException` (format v1). The value language has
  * no other way to see it. Lean: `Model.Timeout.timeoutCode` (10^6) minus the user-code offset 2.
  * Generated programs never raise this code.
  */
val TimeoutCode: Long = 999998L

/** The error code of a `Throwable` in the value language, if it has one. */
object CodeOf:
  def unapply(t: Throwable): Option[Long] = t match
    case UserError(c) => Some(c)
    case _: TimeoutException => Some(TimeoutCode)
    case _ => None

/** Interpreter: Prog => IO[Val]. Each case is one fixed IO term; the Lean model mirrors these
  * terms one to one (see the spec table in wiki/methodology/difftest-program-format.md).
  */
final class Interp(h: Harness):
  private enum Bound:
    case V(v: Val)
    case P(p: Poll[IO])

  private type Env = Map[String, Bound]

  def apply(p: Prog): IO[Val] = run(p, Map.empty)

  /** The root program. A root `syncStep` runs here, on the caller thread, before the runtime
    * runs anything: `e.syncStep(limit).unsafeRunSync()`, then `Left(io) => io`,
    * `Right(a) => IO.pure(a)` (AsyncLaws.scala:84-88); a throw gives `IO.raiseError(t)`.
    */
  def root(p: Prog): IO[Val] = p match
    case Prog.SyncStep(e, limit) =>
      try
        run(e, Map.empty).syncStep(limit).unsafeRunSync() match
          case Left(io) => io
          case Right(a) => IO.pure(a)
      catch case NonFatal(t) => IO.raiseError(t)
    case _ => apply(p)

  private def atom(a: Atom, env: Env): Val = a match
    case Atom.Lit(v) => v
    case Atom.Var(x) =>
      env.get(x) match
        case Some(Bound.V(v)) => v
        case _ => throw TypeError(s"'$x' is not a bound value") // the decoder prevents this

  private def ev(kind: String, fields: (String, ujson.Value)*): ujson.Obj =
    ujson.Obj.from(("ev" -> ujson.Str(kind)) +: fields)

  private def call(fn: Int, v: Val): Val =
    h.emit(ev("call", "fn" -> fn, "arg" -> Json.encodeVal(v)))
    UserFns(fn, v)

  private def errOf(t: Throwable): Err = t match
    case CodeOf(c) => Err.User(c)
    case other => Err.Foreign(s"${other.getClass.getSimpleName}: ${other.getMessage}")

  private def ocVal(oc: Outcome[IO, Throwable, Val]): IO[Val] = oc match
    case Outcome.Succeeded(fa) => fa.map(VSucceeded(_))
    case Outcome.Errored(t) => IO.pure(VErrored(errOf(t)))
    case Outcome.Canceled() => IO.pure(VCanceled)

  private def fiberOf(v: Val): Fiber[IO, Throwable, Val] = v match
    case VFiber(i) if h.fiberAt(i).isDefined => h.fiberAt(i).get
    case _ => throw TypeError(s"not a fiber handle: $v")

  private def refOf(v: Val): (Int, Ref[IO, Val]) = v match
    case VRef(i) => (i, h.refs(i))
    case _ => throw TypeError(s"not a ref handle: $v")

  private def queueOf(v: Val): Queue[IO, Val] = v match
    case VQueue(i) => h.queues(i)
    case _ => throw TypeError(s"not a queue handle: $v")

  private def deferredOf(v: Val): (Int, Deferred[IO, Val]) = v match
    case VDeferred(i) => (i, h.deferreds(i))
    case _ => throw TypeError(s"not a deferred handle: $v")

  private def run(p: Prog, env: Env): IO[Val] = p match
    case Prog.Pure(a) => IO.pure(atom(a, env))
    case Prog.Raise(c) => IO.raiseError(UserError(c))
    case Prog.Delay(fn, a) => IO.delay(call(fn, atom(a, env)))
    case Prog.Bind(x, e, k) => run(e, env).flatMap(v => run(k, env + (x -> Bound.V(v))))
    case Prog.Seq(ps) => ps.tail.foldLeft(run(ps.head, env))((acc, q) => acc.flatMap(_ => run(q, env)))
    case Prog.Map(e, fn) => run(e, env).map(v => call(fn, v))
    case Prog.HandleErrorWith(e, x, k) =>
      run(e, env).handleErrorWith {
        case CodeOf(c) => run(k, env + (x -> Bound.V(VNat(c))))
        case t => IO.raiseError(t)
      }
    case Prog.Attempt(e) =>
      run(e, env).attempt.map {
        case Right(v) => VRight(v)
        case Left(CodeOf(c)) => VLeft(VNat(c))
        case Left(t) => throw t
      }
    case Prog.Uncancelable(q, body) => IO.uncancelable(poll => run(body, env + (q -> Bound.P(poll))))
    case Prog.Poll(q, e) =>
      env(q) match
        case Bound.P(poll) => poll(run(e, env))
        case _ => IO.raiseError(TypeError(s"'$q' is not a poll"))
    case Prog.OnCancel(e, fin, tag) =>
      run(e, env).onCancel(IO.delay(h.emit(ev("fin", "op" -> "onCancel", "tag" -> tag.toDouble))) *> run(fin, env).void)
    case Prog.GuaranteeCase(e, x, fin, tag) =>
      run(e, env).guaranteeCase { oc =>
        ocVal(oc).flatMap { o =>
          IO.delay(h.emit(ev("fin", "op" -> "guaranteeCase", "tag" -> tag.toDouble, "oc" -> Json.encodeVal(o)))) *>
            run(fin, env + (x -> Bound.V(o))).void
        }
      }
    case Prog.Canceled => IO.canceled.as(VUnit)
    case Prog.Cede => IO.cede.as(VUnit)
    case Prog.Start(e) => run(e, env).start.map(f => VFiber(h.fiberHandle(f)))
    case Prog.Join(f) => fiberOf(atom(f, env)).join.flatMap(ocVal)
    case Prog.Cancel(f) => fiberOf(atom(f, env)).cancel.as(VUnit)
    case Prog.RacePair(a, b) =>
      IO.racePair(run(a, env), run(b, env)).flatMap {
        case Left((oc, fb)) => ocVal(oc).map(o => VLeft(VPair(o, VFiber(h.fiberHandle(fb)))))
        case Right((fa, oc)) => ocVal(oc).map(o => VRight(VPair(VFiber(h.fiberHandle(fa)), o)))
      }
    case Prog.Sleep(ms) => IO.sleep(ms.millis).as(VUnit)
    case Prog.RefNew(a) => IO.ref(atom(a, env)).map(r => VRef(h.newRef(r)))
    case Prog.RefGet(r) => refOf(atom(r, env))._2.get
    case Prog.RefSet(r, a) =>
      locally {
        val (i, ref) = refOf(atom(r, env))
        val v = atom(a, env)
        ref.set(v) *> IO.delay { h.emit(ev("set", "ref" -> i, "v" -> Json.encodeVal(v))); VUnit }
      }
    case Prog.RefModify(r, fn) =>
      locally {
        refOf(atom(r, env))._2.modify { s =>
          call(fn, s) match
            case VPair(next, out) => (next, out)
            case other => throw TypeError(s"refModify: function $fn must return a pair, got $other")
        }
      }
    case Prog.DeferredNew => IO.deferred[Val].map(d => VDeferred(h.newDeferred(d)))
    case Prog.DeferredGet(d) => deferredOf(atom(d, env))._2.get
    case Prog.DeferredComplete(d, a) =>
      locally {
        val (i, dfd) = deferredOf(atom(d, env))
        val v = atom(a, env)
        dfd.complete(v).flatMap { ok =>
          IO.delay { h.emit(ev("complete", "deferred" -> i, "v" -> Json.encodeVal(v), "ok" -> ok)); VBool(ok) }
        }
      }
    case Prog.Async(cbs, fin, tag) =>
      IO.executionContext.flatMap { ec =>
        IO.async[Val] { cb =>
          IO.delay {
            val id = h.newAsync()
            h.emit(ev("asyncReg", "async" -> id))
            cbs.zipWithIndex.foreach { (c, i) =>
              val fire = () => {
                h.emit(ev("cb", "async" -> id, "i" -> i))
                cb(c.res.left.map(code => UserError(code)))
              }
              c.when match
                case When.Sync => fire()
                case When.Later => ec.execute(CbTask(s"cb$id.$i", fire))
            }
            fin.map(f => IO.delay(h.emit(ev("fin", "op" -> "async", "tag" -> tag.toDouble))) *> run(f, env).void)
          }
        }
      }
    case Prog.Never => IO.never[Val]
    case Prog.Case(on, l, lk, r, rk) =>
      locally {
        atom(on, env) match
          case VLeft(v) => run(lk, env + (l -> Bound.V(v)))
          case VRight(v) => run(rk, env + (r -> Bound.V(v)))
          case other => IO.raiseError(TypeError(s"case: not an either: $other"))
      }
    case Prog.Split(on, a, b, k) =>
      locally {
        atom(on, env) match
          case VPair(x, y) => run(k, env + (a -> Bound.V(x)) + (b -> Bound.V(y)))
          case other => IO.raiseError(TypeError(s"split: not a pair: $other"))
      }
    // ---- format v1
    case Prog.SyncStep(_, _) => IO.raiseError(TypeError("syncStep below the root")) // the decoder prevents this
    case Prog.Timeout(e, ms) => run(e, env).timeout(ms.millis)
    case Prog.TimeoutTo(e, ms, fb) => run(e, env).timeoutTo(ms.millis, run(fb, env))
    case Prog.QueueNew => Queue.unbounded[IO, Val].map(q => VQueue(h.newQueue(q)))
    case Prog.QueueOffer(q, a) => queueOf(atom(q, env)).offer(atom(a, env)).as(VUnit)
    case Prog.QueueTake(q) => queueOf(atom(q, env)).take
    case Prog.QueueTryTake(q) =>
      queueOf(atom(q, env)).tryTake.map {
        case Some(v) => VRight(v)
        case None => VLeft(VUnit)
      }
    case Prog.AllocatedCase(r) => res(r, env).allocatedCase.map(_._1)
    // ---- format v2 (Phase 6, track G)
    case Prog.Guarantee(e, fin, tag) =>
      run(e, env).guarantee(IO.delay(h.emit(ev("fin", "op" -> "guarantee", "tag" -> tag.toDouble))) *> run(fin, env).void)
    case Prog.Bracket(acq, x, use, rel, tag) =>
      run(acq, env).bracket(a => run(use, env + (x -> Bound.V(a)))) { a =>
        IO.delay(h.emit(ev("fin", "op" -> "bracket", "tag" -> tag.toDouble))) *> run(rel, env + (x -> Bound.V(a))).void
      }
    case Prog.BracketCase(acq, x, use, y, rel, tag) =>
      run(acq, env).bracketCase(a => run(use, env + (x -> Bound.V(a))))(caseRelease("bracketCase", x, y, rel, tag, env))
    case Prog.BracketFull(q, acq, x, use, y, rel, tag) =>
      IO.bracketFull[Val, Val](poll => run(acq, env + (q -> Bound.P(poll))))(a => run(use, env + (x -> Bound.V(a))))(
        caseRelease("bracketFull", x, y, rel, tag, env))

  /** `(a, oc) => ocVal(oc).flatMap(o => IO.delay(emit fin) *> run(rel, env + x + y).void)` (format v2). */
  private def caseRelease(op: String, x: String, y: String, rel: Prog, tag: Long, env: Env)
      : (Val, Outcome[IO, Throwable, Val]) => IO[Unit] =
    (a, oc) =>
      ocVal(oc).flatMap { o =>
        IO.delay(h.emit(ev("fin", "op" -> op, "tag" -> tag.toDouble, "oc" -> Json.encodeVal(o)))) *>
          run(rel, env + (x -> Bound.V(a)) + (y -> Bound.V(o))).void
      }

  /** A `Resource[IO, Val]`. Each case is one fixed `Resource` term. */
  private def res(r: Res, env: Env): Resource[IO, Val] = r match
    case Res.RPure(a) => Resource.pure[IO, Val](atom(a, env))
    case Res.REval(e) => Resource.eval(run(e, env))
    case Res.RMake(acq, x, rel) => Resource.make(run(acq, env))(a => run(rel, env + (x -> Bound.V(a))).void)
    case Res.RFlatMap(r0, x, k) => res(r0, env).flatMap(v => res(k, env + (x -> Bound.V(v))))

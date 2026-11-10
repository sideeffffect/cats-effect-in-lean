package cats.effect.difftest

// Program language, format v1 (v0 is a subset). Spec: wiki/methodology/difftest-program-format.md

/** An error value. `User(code)` is the error that the program raises. `Foreign` is any
  * other Throwable (a harness or CE internal error); a generated program must not produce it.
  */
enum Err:
  case User(code: Long)
  case Foreign(desc: String)

/** The untyped value domain. Handles (fiber, ref, deferred) are only made at run time. */
enum Val:
  case VUnit
  case VBool(b: Boolean)
  case VNat(n: Long)
  case VPair(a: Val, b: Val)
  case VLeft(v: Val)
  case VRight(v: Val)
  case VSucceeded(v: Val)
  case VErrored(e: Err)
  case VCanceled
  case VFiber(id: Int)
  case VRef(id: Int)
  case VDeferred(id: Int)
  case VQueue(id: Int) // v1
  case VMemo(id: Int) // v2 (track M): the `get` of a `memoize`

/** An argument position: a literal value or a bound variable. */
enum Atom:
  case Lit(v: Val)
  case Var(x: String)

enum When:
  case Sync, Later

/** One call of an `async` callback. `res` is Right(value) or Left(error code). */
final case class CbCall(when: When, res: Either[Long, Val])

enum Prog:
  case Pure(a: Atom)
  case Raise(code: Long)
  case Delay(fn: Int, arg: Atom)
  case Bind(x: String, e: Prog, k: Prog)
  case Seq(ps: List[Prog])
  case Map(e: Prog, fn: Int)
  case HandleErrorWith(e: Prog, x: String, k: Prog)
  case Attempt(e: Prog)
  case Uncancelable(p: String, body: Prog)
  case Poll(p: String, e: Prog)
  case OnCancel(e: Prog, fin: Prog, tag: Long)
  case GuaranteeCase(e: Prog, x: String, fin: Prog, tag: Long)
  case Canceled
  case Cede
  case Start(e: Prog)
  case Join(f: Atom)
  case Cancel(f: Atom)
  case RacePair(a: Prog, b: Prog)
  case Sleep(ms: Long)
  case RefNew(a: Atom)
  case RefGet(r: Atom)
  case RefSet(r: Atom, a: Atom)
  case RefModify(r: Atom, fn: Int)
  case DeferredNew
  case DeferredGet(d: Atom)
  case DeferredComplete(d: Atom, a: Atom)
  case Async(cbs: List[CbCall], fin: Option[Prog], tag: Long)
  case Never
  case Case(on: Atom, l: String, lk: Prog, r: String, rk: Prog)
  case Split(on: Atom, a: String, b: String, k: Prog)
  // ---- format v1
  /** Root only: `e.syncStep(limit).unsafeRunSync()` before the run, then the selected `IO`. */
  case SyncStep(e: Prog, limit: Int)
  case Timeout(e: Prog, ms: Long)
  case TimeoutTo(e: Prog, ms: Long, fb: Prog)
  case QueueNew
  case QueueOffer(q: Atom, a: Atom)
  case QueueTake(q: Atom)
  case QueueTryTake(q: Atom)
  case AllocatedCase(r: Res)
  // ---- format v2 (track R: race, both, raceOutcome, bothOutcome)
  case Race(a: Prog, b: Prog)
  case RaceOutcome(a: Prog, b: Prog)
  case Both(a: Prog, b: Prog)
  case BothOutcome(a: Prog, b: Prog)
  // ---- format v2 (Phase 6, track G)
  /** `e.guarantee(IO.delay(emit fin) *> fin.void)`. */
  case Guarantee(e: Prog, fin: Prog, tag: Long)
  /** `acq.bracket(x => use)(x => IO.delay(emit fin) *> rel.void)`. */
  case Bracket(acq: Prog, x: String, use: Prog, rel: Prog, tag: Long)
  /** `acq.bracketCase(x => use)((x, oc) => ocVal(oc).flatMap(y => IO.delay(emit fin) *> rel.void))`. */
  case BracketCase(acq: Prog, x: String, use: Prog, y: String, rel: Prog, tag: Long)
  /** `IO.bracketFull(poll => acq)(x => use)((x, oc) => ...)` (release as in `BracketCase`). */
  case BracketFull(poll: String, acq: Prog, x: String, use: Prog, y: String, rel: Prog, tag: Long)
  // ---- format v2 (Phase 6, track M)
  /** `e.memoize.map(get => VMemo(h.newMemo(get)))`. */
  case Memoize(e: Prog)
  /** The `get` of a memo handle (the `IO[Val]` itself). */
  case MemoGet(m: Atom)

/** A `Resource[IO, Val]` (format v1). It occurs only under `AllocatedCase`. */
enum Res:
  case RPure(a: Atom)
  case REval(e: Prog)
  case RMake(acq: Prog, x: String, rel: Prog)
  case RFlatMap(r: Res, x: String, k: Res)

/** One entry of a replay choice list. */
enum Choice:
  case Pick(i: Int)
  case CancelFiber(handle: Int)

enum Mode:
  case Replay(choices: List[Choice])
  case TestControlSeed(seed: Long)

/** `runtime`: the `IORuntimeConfig` thresholds (cancelation check, auto-yield) of a replay run;
  * `None` is the default config.
  */
final case class TestCase(
    id: String,
    mode: Mode,
    prog: Prog,
    maxSteps: Int,
    version: Int = Json.FormatVersion,
    runtime: Option[(Int, Int)] = None)

final class DecodeError(msg: String) extends Exception(msg)

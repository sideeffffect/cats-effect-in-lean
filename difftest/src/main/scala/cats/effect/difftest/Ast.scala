package cats.effect.difftest

// Program language, format v0. Spec: wiki/methodology/difftest-program-format.md

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

/** One entry of a replay choice list. */
enum Choice:
  case Pick(i: Int)
  case CancelFiber(handle: Int)

enum Mode:
  case Replay(choices: List[Choice])
  case TestControlSeed(seed: Long)

final case class TestCase(id: String, mode: Mode, prog: Prog, maxSteps: Int)

final class DecodeError(msg: String) extends Exception(msg)

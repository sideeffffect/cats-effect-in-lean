package cats.effect.difftest

import Val.*

/** The error that a program raises. The code is a natural number. */
final case class UserError(code: Long) extends Exception(s"UserError($code)", null, false, false)

/** A user function got an argument of the wrong shape. A generated program must not do this. */
final class TypeError(msg: String) extends Exception(msg, null, false, false)

/** The fixed table of user functions (format v0). Lean implements the same table. Each function
  * is total on its domain; on a wrong argument shape it throws TypeError. Function 3 throws
  * UserError on purpose. The interpreter records a `call` trace event before each application.
  */
object UserFns:
  val names: Vector[String] =
    Vector("id", "unit", "inc", "raise", "dup", "incOld", "not", "isZero", "fst", "snd")

  def size: Int = names.size

  private def bad(fn: Int, v: Val): Nothing =
    throw TypeError(s"user function ${names(fn)} ($fn): bad argument $v")

  def apply(fn: Int, v: Val): Val = (fn, v) match
    case (0, x) => x
    case (1, _) => VUnit
    case (2, VNat(n)) => VNat(n + 1)
    case (3, VNat(c)) => throw UserError(c)
    case (4, x) => VPair(x, x)
    case (5, VNat(n)) => VPair(VNat(n + 1), VNat(n))
    case (6, VBool(b)) => VBool(!b)
    case (7, VNat(n)) => VBool(n == 0)
    case (8, VPair(a, _)) => a
    case (9, VPair(_, b)) => b
    case _ => bad(fn, v)

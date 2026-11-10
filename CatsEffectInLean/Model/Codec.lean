import CatsEffectInLean.Model.Syntax

/-!
# Closures with captured values as `Fn.user` ids

`Fn.user (id : Nat)` names user code; `UserEnv.callV id arg view` runs it
(`CatsEffectInLean/Model/Syntax.lean`). Library code that is written over the public API (for
example `std.Queue`, `IO#timeoutTo`) has lambdas that capture run-time values: a `poll`, a
`ContState` id, a `Ref` id, an outcome. So the id must carry the captured values.

This file gives a lossless encoding:

* `pair a b`: interleave the bits of `a` and `b` (a bijection `Nat × Nat → Nat`).
* `encList`: a list of `Nat` as one `Nat` (`[] ↦ 0`, `a :: as ↦ pair a (encList as) + 1`).
* `Val.enc`: a `Val` as one `Nat` (constructor index, then the fields).

The decoders `unpair`, `decList`, `decVal` invert them (the examples at the end check this). Only `Nat` `+`, `*`, `/`, `%` and `==` are used, and all recursion is structural on
a fuel argument, so `decide +kernel` evaluates them (`wiki/lean/kernel-evaluation.md`).

The encoding does not bound the size of a value, so a model that uses it is correct for all
ids (the earlier examples use `tag + 100 * a`, which is lossy for ids `≥ 100`).
-/

namespace CatsEffectInLean.Model.Codec

open CatsEffectInLean.Model

/-- Interleave the bits of `a` (even positions) and `b` (odd positions). `fuel` must be more
than the bit length of `a` and `b`; `pair` gives `a + b + 1`. -/
def pairF : (fuel a b : Nat) → Nat
  | 0, _, _ => 0
  | f + 1, a, b =>
    if a == 0 && b == 0 then 0 else a % 2 + 2 * (b % 2) + 4 * pairF f (a / 2) (b / 2)

/-- A bijection `Nat × Nat → Nat` (bit interleaving). `pair a b ≥ a` and `pair a b ≥ b`. -/
def pair (a b : Nat) : Nat := pairF (a + b + 1) a b

/-- The inverse of `pairF`. -/
def unpairF : (fuel n : Nat) → Nat × Nat
  | 0, _ => (0, 0)
  | f + 1, n =>
    if n == 0 then (0, 0)
    else
      let r := unpairF f (n / 4)
      (n % 2 + 2 * r.1, (n / 2) % 2 + 2 * r.2)

/-- The inverse of `pair`. -/
def unpair (n : Nat) : Nat × Nat := unpairF (n + 1) n

/-- A list of `Nat` as one `Nat`. -/
def encList : List Nat → Nat
  | [] => 0
  | a :: as => pair a (encList as) + 1

/-- The inverse of `encList`. Each tail code is smaller than its list code, so fuel `n + 1`
is enough. -/
def decListF : (fuel n : Nat) → List Nat
  | 0, _ => []
  | f + 1, n =>
    if n == 0 then []
    else
      let r := unpair (n - 1)
      r.1 :: decListF f r.2

/-- The inverse of `encList`. -/
def decList (n : Nat) : List Nat := decListF (n + 1) n

/-- `Int` as `Nat` (zigzag). -/
def zig (i : Int) : Nat := if i ≥ 0 then 2 * i.toNat else 2 * (-i).toNat - 1

/-- The inverse of `zig`. -/
def unzig (n : Nat) : Int := if n % 2 == 0 then ((n / 2 : Nat) : Int) else -(((n + 1) / 2 : Nat) : Int)

/-- `ErrKind` as `Nat`. -/
def ErrKind.enc : ErrKind → Nat
  | .nonFatal => 0
  | .interrupted => 1
  | .fatal => 2

/-- The inverse of `ErrKind.enc`. -/
def ErrKind.dec : Nat → Option ErrKind
  | 0 => some .nonFatal
  | 1 => some .interrupted
  | 2 => some .fatal
  | _ => none

/-- `Val` as one `Nat`: `encList (constructor index :: fields)`. A nested `Val` field is
its own code. -/
def Val.enc : Val → Nat
  | .unit => encList [0]
  | .bool b => encList [1, if b then 1 else 0]
  | .nat n => encList [2, n]
  | .int i => encList [3, zig i]
  | .pair a b => encList [4, Val.enc a, Val.enc b]
  | .left v => encList [5, Val.enc v]
  | .right v => encList [6, Val.enc v]
  | .none => encList [7]
  | .some v => encList [8, Val.enc v]
  | .err e => encList [9, e.code, ErrKind.enc e.kind]
  | .ocSucceeded v => encList [10, Val.enc v]
  | .ocErrored e => encList [11, e.code, ErrKind.enc e.kind]
  | .ocCanceled => encList [12]
  | .fiber i => encList [13, i]
  | .ref i => encList [14, i]
  | .deferred i => encList [15, i]
  | .poll m f => encList [16, m, f]
  | .cont s => encList [17, s]
  | .ec i => encList [18, i]
  | .trace => encList [19]
  | .runtime => encList [20]

/-- The inverse of `Val.enc`. A field code is smaller than the code of the whole value, so
fuel `n + 1` is enough. -/
def decValF : (fuel n : Nat) → Option Val
  | 0, _ => none
  | f + 1, n =>
    match decList n with
    | [0] => some .unit
    | [1, b] => some (.bool (b == 1))
    | [2, k] => some (.nat k)
    | [3, i] => some (.int (unzig i))
    | [4, a, b] => do
      let a ← decValF f a
      let b ← decValF f b
      pure (.pair a b)
    | [5, v] => (decValF f v).map .left
    | [6, v] => (decValF f v).map .right
    | [7] => some .none
    | [8, v] => (decValF f v).map .some
    | [9, c, k] => (ErrKind.dec k).map fun k => .err { code := c, kind := k }
    | [10, v] => (decValF f v).map .ocSucceeded
    | [11, c, k] => (ErrKind.dec k).map fun k => .ocErrored { code := c, kind := k }
    | [12] => some .ocCanceled
    | [13, i] => some (.fiber i)
    | [14, i] => some (.ref i)
    | [15, i] => some (.deferred i)
    | [16, m, p] => some (.poll m p)
    | [17, s] => some (.cont s)
    | [18, i] => some (.ec i)
    | [19] => some .trace
    | [20] => some .runtime
    | _ => none

/-- The inverse of `Val.enc`. -/
def decVal (n : Nat) : Option Val := decValF (n + 1) n

/-- A closure of library namespace `ns` with lambda tag and captured fields `l`. -/
def nsFn (ns : Nat) (l : List Nat) : Fn := .user (encList (ns :: l))

/-! ## Checks -/

example : unpair (pair 5 9) = (5, 9) := by decide
example : unpair (pair 0 0) = (0, 0) := by decide
example : decList (encList [3, 0, 17, 2]) = [3, 0, 17, 2] := by decide +kernel
example : decVal (Val.enc (.pair (.ocSucceeded (.nat 42)) (.fiber 3))) =
    some (.pair (.ocSucceeded (.nat 42)) (.fiber 3)) := by decide +kernel
example : decVal (Val.enc (.ocErrored { code := 7, kind := .fatal })) =
    some (.ocErrored { code := 7, kind := .fatal }) := by decide +kernel
example : decVal (Val.enc (.int (-3))) = some (.int (-3)) := by decide +kernel

end CatsEffectInLean.Model.Codec

import CatsEffectInLean.Model.Val

/-!
# A `Val` ↔ `Nat` code (for closure ids)

Phase 5 (CE-0002). A library closure that captures data (for example the
`a => continue(Resource.pure(a), stack, release)` of `Resource#allocatedCase`) must be a
`Fn.user id` in the first-order syntax (`CatsEffectInLean/Model/Syntax.lean`). So its id must
hold the captured data. This file gives an injective code from `Val` to `Nat` and its decoder.
`CatsEffectInLean/Model/Resource.lean` writes each closure as a `Val` and uses this code.

This is not Cats Effect code. It is a modelling device, like the `Val.nat` handles.

## Format

A `Val` becomes a bit string (`List Bool`): a 5-bit constructor tag (least significant bit
first), then the fields. A `Nat` field is in Elias-gamma code: for `m = n + 1` with `k + 1`
binary digits, `k` zeros, a one, then the low `k` bits of `m` (least significant first). The
bit string becomes a `Nat` with a sentinel one above the last bit, so that trailing zeros
stay.

All loops are structural (on a fuel or on the input), so `decide +kernel` can evaluate them
(`wiki/lean/kernel-evaluation.md`).
-/

namespace CatsEffectInLean.Model.Codec

/-- `true` ↦ 1, `false` ↦ 0. -/
def bit (b : Bool) : Nat := if b then 1 else 0

/-- The binary digits of `n`, least significant first (`[]` for `0`). `fuel ≥` the number of
digits (`fuel = n` is enough). -/
def bitsLE : (fuel : Nat) → Nat → List Bool
  | 0, _ => []
  | f + 1, n => if n == 0 then [] else (n % 2 == 1) :: bitsLE f (n / 2)

/-- The low `w` bits of `n`, least significant first. -/
def fixedBits : (w : Nat) → Nat → List Bool
  | 0, _ => []
  | w + 1, n => (n % 2 == 1) :: fixedBits w (n / 2)

/-- Read `k` bits, least significant first. -/
def readLE : (k : Nat) → List Bool → Option (Nat × List Bool)
  | 0, r => some (0, r)
  | _ + 1, [] => none
  | k + 1, b :: r =>
    match readLE k r with
    | some (v, r') => some (2 * v + bit b, r')
    | none => none

/-- Elias-gamma code of `n + 1`. -/
def encNat (n : Nat) : List Bool :=
  let bs := bitsLE (n + 1) (n + 1)
  let k := bs.length - 1
  List.replicate k false ++ true :: bs.take k

/-- Count the zeros before the first one. -/
def countZeros : (fuel : Nat) → List Bool → Option (Nat × List Bool)
  | 0, _ => none
  | _ + 1, [] => none
  | _ + 1, true :: r => some (0, r)
  | f + 1, false :: r =>
    match countZeros f r with
    | some (k, r') => some (k + 1, r')
    | none => none

/-- Decode one `encNat`. -/
def decNat (bs : List Bool) : Option (Nat × List Bool) :=
  match countZeros bs.length bs with
  | some (k, r) =>
    match readLE k r with
    | some (low, r') => some (2 ^ k + low - 1, r')
    | none => none
  | none => none

/-- The 5-bit tag. -/
def tag (t : Nat) : List Bool := fixedBits 5 t

def encKind : ErrKind → List Bool
  | .nonFatal => [false, false]
  | .interrupted => [true, false]
  | .fatal => [false, true]

def encErr (e : Err) : List Bool := encNat e.code ++ encKind e.kind

def encInt : Int → List Bool
  | .ofNat n => false :: encNat n
  | .negSucc n => true :: encNat n

/-- The bit string of a `Val`. Tags follow the constructor order of `Val`. -/
def encVal : Val → List Bool
  | .unit => tag 0
  | .bool b => tag 1 ++ [b]
  | .nat n => tag 2 ++ encNat n
  | .int i => tag 3 ++ encInt i
  | .pair a b => tag 4 ++ encVal a ++ encVal b
  | .left v => tag 5 ++ encVal v
  | .right v => tag 6 ++ encVal v
  | .none => tag 7
  | .some v => tag 8 ++ encVal v
  | .err e => tag 9 ++ encErr e
  | .ocSucceeded v => tag 10 ++ encVal v
  | .ocErrored e => tag 11 ++ encErr e
  | .ocCanceled => tag 12
  | .fiber n => tag 13 ++ encNat n
  | .ref n => tag 14 ++ encNat n
  | .deferred n => tag 15 ++ encNat n
  | .poll m s => tag 16 ++ encNat m ++ encNat s
  | .cont n => tag 17 ++ encNat n
  | .ec n => tag 18 ++ encNat n
  | .trace => tag 19
  | .runtime => tag 20

def decKind : List Bool → Option (ErrKind × List Bool)
  | false :: false :: r => some (.nonFatal, r)
  | true :: false :: r => some (.interrupted, r)
  | false :: true :: r => some (.fatal, r)
  | _ => none

def decErr (bs : List Bool) : Option (Err × List Bool) :=
  match decNat bs with
  | some (c, r) =>
    match decKind r with
    | some (k, r') => some ({ code := c, kind := k }, r')
    | none => none
  | none => none

def decInt : List Bool → Option (Int × List Bool)
  | false :: r => (decNat r).map fun (n, r') => (.ofNat n, r')
  | true :: r => (decNat r).map fun (n, r') => (.negSucc n, r')
  | [] => none

/-- Map the first part of a decode result. -/
@[inline] def mapFst {α β : Type} (f : α → β) : Option (α × List Bool) → Option (β × List Bool)
  | some (a, r) => some (f a, r)
  | none => none

/-- Decode one `encVal`. Structural on `fuel`; `fuel = bs.length` is enough (each value has at
least 5 bits). -/
def decVal : (fuel : Nat) → List Bool → Option (Val × List Bool)
  | 0, _ => none
  | f + 1, bs =>
    match readLE 5 bs with
    | none => none
    | some (t, r) =>
      match t with
      | 0 => some (.unit, r)
      | 1 => match r with
        | b :: r' => some (.bool b, r')
        | [] => none
      | 2 => mapFst .nat (decNat r)
      | 3 => mapFst .int (decInt r)
      | 4 =>
        match decVal f r with
        | some (a, r') =>
          match decVal f r' with
          | some (b, r'') => some (.pair a b, r'')
          | none => none
        | none => none
      | 5 => mapFst .left (decVal f r)
      | 6 => mapFst .right (decVal f r)
      | 7 => some (.none, r)
      | 8 => mapFst .some (decVal f r)
      | 9 => mapFst .err (decErr r)
      | 10 => mapFst .ocSucceeded (decVal f r)
      | 11 => mapFst .ocErrored (decErr r)
      | 12 => some (.ocCanceled, r)
      | 13 => mapFst .fiber (decNat r)
      | 14 => mapFst .ref (decNat r)
      | 15 => mapFst .deferred (decNat r)
      | 16 =>
        match decNat r with
        | some (m, r') => mapFst (.poll m) (decNat r')
        | none => none
      | 17 => mapFst .cont (decNat r)
      | 18 => mapFst .ec (decNat r)
      | 19 => some (.trace, r)
      | 20 => some (.runtime, r)
      | _ => none

/-- Bits to a number, with a sentinel one above the last bit. -/
def ofBits : List Bool → Nat
  | [] => 1
  | b :: r => 2 * ofBits r + bit b

/-- The code of a `Val`. Never `0`. -/
def valToNat (v : Val) : Nat := ofBits (encVal v)

/-- Decode a code. `none` if `n` is not the code of a `Val`. -/
def natToVal (n : Nat) : Option Val :=
  let bs := (bitsLE n n).dropLast
  match decVal bs.length bs with
  | some (v, []) => some v
  | _ => none

/-! Smoke tests (kernel evaluation). -/

example : natToVal (valToNat (.pair (.nat 1000) (.poll 3 0))) = some (.pair (.nat 1000) (.poll 3 0)) := by
  decide +kernel

example : natToVal (valToNat (.some (.err { code := 7, kind := .fatal }))) =
    some (.some (.err { code := 7, kind := .fatal })) := by
  decide +kernel

example : natToVal (valToNat (.int (-5))) = some (.int (-5)) := by decide +kernel

example : natToVal 0 = none := by decide +kernel

end CatsEffectInLean.Model.Codec

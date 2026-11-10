import CatsEffectInLean.Model.Syntax

/-!
# The closure codec: a `Val` ↔ `Nat` code for closure ids

A closure that captures data (for example the `a => continue(Resource.pure(a), stack, release)`
of `Resource#allocatedCase`, or the `poll => ...` lambdas of `Queue#take`) must be a
`Fn.user id` in the first-order syntax (`CatsEffectInLean/Model/Syntax.lean`). So its id must
hold the captured data. This file gives an injective code from `Val` to `Nat`, its decoder,
and the one id convention of the project (decision 31,
`raw/project-decisions/2026-11-10-phase0-decisions.md`):

* a closure is a `Val` (`cloVal ns tag fields`, or any `Val` that a model chooses);
* a **library** closure (mirrored Cats Effect code) has the odd id `2 * valToNat c + 1`
  (`libFn`);
* a **user** function has an even id. A user closure with captured values `c` has the id
  `2 * valToNat c` (`userFn`). A plain user function `k` without captured values can also use
  the id `2 * k` (`uid`), as long as no handle is in `natToVal k`.

Captured values are `Val`s, so a handle that a closure captures (`Val.ref`, `Val.fiber`,
`Val.poll`, `Val.cont`, `Val.deferred`) is visible in its id. `Model/WellFormed.lean` uses
this.

This is not Cats Effect code. It is a modelling device, like the `Val.nat` handles.

History: this file replaces two codecs (decision 31). The other one (bit interleaving of
`Nat` pairs, `encList`) gave codes whose bit length doubles at each nesting level. This one
gives codes whose bit length is linear in the size of the value, so the kernel evaluates it
faster. The roundtrip theorem is `natToVal_valToNat` (below).

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

/-! ## Roundtrip: `natToVal (valToNat v) = some v` -/

/-- The value of a bit list, least significant first (no sentinel). -/
def valLE : List Bool → Nat
  | [] => 0
  | b :: r => 2 * valLE r + bit b

theorem readLE_append (l r : List Bool) : readLE l.length (l ++ r) = some (valLE l, r) := by
  induction l with
  | nil => rfl
  | cons b l ih => simp [readLE, ih, valLE]

theorem bitsLE_zero (f : Nat) : bitsLE f 0 = [] := by cases f <;> rfl

theorem bit_mod (m : Nat) : bit (m % 2 == 1) = m % 2 := by
  rcases Nat.mod_two_eq_zero_or_one m with h | h <;> simp [h, bit]

/-- For `m ≥ 1` and enough fuel, the binary digits of `m` end with a one, and their value is
`m`. -/
theorem bitsLE_spec : ∀ (f m : Nat), 1 ≤ m → m ≤ f →
    ∃ l, bitsLE f m = l ++ [true] ∧ valLE l + 2 ^ l.length = m
  | 0, m, h1, h2 => by omega
  | f + 1, m, h1, h2 => by
    have hm : (m == 0) = false := by simp; omega
    by_cases hq : m / 2 = 0
    · refine ⟨[], ?_, ?_⟩
      · have : m = 1 := by omega
        subst this; simp [bitsLE, bitsLE_zero]
      · simp [valLE]; omega
    · obtain ⟨l, hl, hv⟩ := bitsLE_spec f (m / 2) (by omega) (by omega)
      refine ⟨(m % 2 == 1) :: l, ?_, ?_⟩
      · simp only [bitsLE, hm, Bool.false_eq_true, ite_false, hl, List.cons_append]
      · simp only [valLE, List.length_cons, Nat.pow_succ, bit_mod]
        have := Nat.div_add_mod m 2
        have h2l : 2 ^ l.length * 2 = 2 * 2 ^ l.length := Nat.mul_comm _ _
        omega

theorem countZeros_spec : ∀ (k fuel : Nat) (r : List Bool), k < fuel →
    countZeros fuel (List.replicate k false ++ true :: r) = some (k, r)
  | 0, f + 1, r, _ => rfl
  | k + 1, f + 1, r, h => by
    simp [List.replicate_succ, countZeros, countZeros_spec k f r (by omega)]

theorem decNat_encNat (n : Nat) (r : List Bool) : decNat (encNat n ++ r) = some (n, r) := by
  obtain ⟨l, hl, hv⟩ := bitsLE_spec (n + 1) (n + 1) (by omega) (Nat.le_refl _)
  have he : encNat n = List.replicate l.length false ++ true :: l := by
    simp [encNat, hl]
  rw [he, decNat]
  simp only [List.append_assoc, List.cons_append]
  rw [countZeros_spec l.length _ _ (by simp)]
  simp only [readLE_append]
  congr 2
  omega

theorem fixedBits_length (w n : Nat) : (fixedBits w n).length = w := by
  induction w generalizing n with
  | zero => rfl
  | succ w ih => simp [fixedBits, ih]

theorem valLE_fixedBits_tag : ∀ t, t < 21 → valLE (fixedBits 5 t) = t := by decide

theorem readLE_tag (t : Nat) (ht : t < 21) (r : List Bool) : readLE 5 (tag t ++ r) = some (t, r) := by
  have := readLE_append (fixedBits 5 t) r
  rw [fixedBits_length, valLE_fixedBits_tag t ht] at this
  exact this

theorem decInt_encInt (i : Int) (r : List Bool) : decInt (encInt i ++ r) = some (i, r) := by
  cases i <;> simp [encInt, decInt, decNat_encNat]

theorem decErr_encErr (e : Err) (r : List Bool) : decErr (encErr e ++ r) = some (e, r) := by
  obtain ⟨c, k⟩ := e
  cases k <;> simp [encErr, encKind, decErr, decNat_encNat, decKind]

theorem tag_length (t : Nat) : (tag t).length = 5 := fixedBits_length 5 t

theorem decVal_encVal : ∀ (v : Val) (f : Nat) (r : List Bool), (encVal v).length ≤ f →
    decVal f (encVal v ++ r) = some (v, r) := by
  intro v
  induction v with
  | pair a b iha ihb =>
    intro f r h
    obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by simp [encVal, tag_length] at h; omega⟩
    simp only [encVal, List.append_assoc] at h ⊢
    simp only [decVal, readLE_tag 4 (by decide)]
    simp only [List.length_append, tag_length] at h
    simp only [iha f _ (by omega), ihb f _ (by omega)]
  | left a ih | right a ih | some a ih | ocSucceeded a ih =>
    intro f r h
    obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by simp [encVal, tag_length] at h; omega⟩
    simp only [encVal, List.append_assoc] at h ⊢
    simp only [List.length_append, tag_length] at h
    simp [decVal, readLE_tag, ih f _ (by omega), mapFst]
  | _ =>
    intro f r h
    obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by simp [encVal, tag_length] at h; omega⟩
    simp only [encVal, List.append_assoc]
    simp [decVal, readLE_tag, decNat_encNat, decInt_encInt, decErr_encErr, mapFst]

theorem ofBits_pos : ∀ bs : List Bool, 1 ≤ ofBits bs
  | [] => Nat.le_refl 1
  | _ :: bs => by have := ofBits_pos bs; simp only [ofBits]; omega

theorem bitsLE_ofBits : ∀ (bs : List Bool) (f : Nat), ofBits bs ≤ f →
    bitsLE f (ofBits bs) = bs ++ [true]
  | [], f, h => by
    obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by simp [ofBits] at h; omega⟩
    simp [ofBits, bitsLE, bitsLE_zero]
  | b :: bs, f, h => by
    have h1 : 1 ≤ ofBits bs := ofBits_pos bs
    have hb : bit b ≤ 1 := by cases b <;> simp [bit]
    obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by simp [ofBits] at h; omega⟩
    simp only [ofBits] at h ⊢
    have hne : (2 * ofBits bs + bit b == 0) = false := by simp; omega
    have hmod : ((2 * ofBits bs + bit b) % 2 == 1) = b := by cases b <;> simp [bit]
    have hdiv : (2 * ofBits bs + bit b) / 2 = ofBits bs := by omega
    simp only [bitsLE, hne, Bool.false_eq_true, ite_false, hmod, hdiv,
      bitsLE_ofBits bs f (by omega), List.cons_append]

/-- The codec is lossless: decoding a code gives the value back. -/
theorem natToVal_valToNat (v : Val) : natToVal (valToNat v) = some v := by
  simp only [natToVal, valToNat, bitsLE_ofBits _ _ (Nat.le_refl _), List.dropLast_concat]
  rw [show encVal v = encVal v ++ [] from (List.append_nil _).symm,
    decVal_encVal v _ [] (by simp)]

/-! Smoke tests (kernel evaluation). -/

example : natToVal (valToNat (.pair (.nat 1000) (.poll 3 0))) = some (.pair (.nat 1000) (.poll 3 0)) := by
  decide +kernel

example : natToVal (valToNat (.some (.err { code := 7, kind := .fatal }))) =
    some (.some (.err { code := 7, kind := .fatal })) := by
  decide +kernel

example : natToVal (valToNat (.int (-5))) = some (.int (-5)) := by decide +kernel

example : natToVal 0 = none := by decide +kernel

/-! ## Closures and the id convention -/

/-- A list of values as one `Val`: `[] ↦ unit`, `a :: as ↦ pair a (listV as)`. -/
def listV : List Val → Val
  | [] => .unit
  | a :: as => .pair a (listV as)

/-- The inverse of `listV` (`none` for a value of another shape). -/
def unlistV : Val → Option (List Val)
  | .unit => some []
  | .pair a r => (unlistV r).map (a :: ·)
  | _ => none

/-- A closure value: namespace `ns`, lambda tag `tag`, captured fields `fs`. -/
def cloVal (ns tag : Nat) (fs : List Val) : Val := .pair (.nat ns) (.pair (.nat tag) (listV fs))

/-- The inverse of `cloVal`. -/
def ofCloVal : Val → Option (Nat × Nat × List Val)
  | .pair (.nat ns) (.pair (.nat tag) fs) => (unlistV fs).map fun l => (ns, tag, l)
  | _ => none

/-- A library closure with closure value `c` (odd id). -/
def libFn (c : Val) : Fn := .user (2 * valToNat c + 1)

/-- A user closure with captured values `c` (even id). -/
def userFn (c : Val) : Fn := .user (2 * valToNat c)

/-- Is `id` the id of a library closure (odd)? -/
def isLibId (id : Nat) : Bool := id % 2 == 1

/-- The closure value in id `id` (both sides), if `id / 2` is a code. -/
def cloOfId (id : Nat) : Option Val := natToVal (id / 2)

example : natToVal (valToNat (cloVal 1 3 [.ref 4, .poll 2 1])) = some (cloVal 1 3 [.ref 4, .poll 2 1]) := by
  decide +kernel

example : ofCloVal (cloVal 1 3 [.ref 4, .nat 7]) = some (1, 3, [.ref 4, .nat 7]) := by decide

end CatsEffectInLean.Model.Codec

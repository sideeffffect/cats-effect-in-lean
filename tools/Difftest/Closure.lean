import Difftest.Prog
import CatsEffectInLean.Model.Syntax
import CatsEffectInLean.Model.Codec

/-!
# Closures as `Fn.user` ids

The model has no closures: `Fn.user (id : Nat)` names user code, and `UserEnv.call id arg refs`
runs it (`CatsEffectInLean/Model/Syntax.lean`). A difftest program has lambdas that capture
run-time values (`bind x e k`: `k` sees `x` and all outer variables). So the id must carry the
captured values.

A closure is `⟨node, lam, vals⟩`:

* `node`: the pre-order number of the AST node that made the lambda (`Prog.at?`).
* `lam`: which lambda of that node (`Lam`), because one node can make several lambdas
  (for example `guaranteeCase` makes eight).
* `vals`: the captured values (the de Bruijn environment, plus extra values for some lambdas).

`Clo.encode` packs this into one `Nat` without loss; `Clo.decode?` unpacks it. Only `Nat`
`div`/`mod`/`mul`/`add` are used, which the kernel evaluates with GMP.

Format v1 programs also run library closures of the mirrors: `Std.Queue` (`Codec.nsFn` namespace
1), `Model.Timeout` (namespace 2) and `Model.Resource` (odd ids `2 * valToNat c + 1`). So a
difftest closure id is `Codec.userFn (.nat (Clo.encode c))` (even). This id is
even (`encList (h :: t)` is even for an odd head `h`), so it is never a `Resource` id, and its
namespace 3 is never a queue or timeout id. `Difftest/Env.lean` (`dispatch`) checks the rest.
-/

namespace Difftest

open CatsEffectInLean.Model

/-- Each lambda that the translation makes. The comment names the Scala lambda. -/
inductive Lam where
  /-- `delay`: `() => call(fn, ⟦arg⟧)`. -/
  | delayThunk
  /-- `bind`: `v => I(k)[x := v]`. -/
  | bindK
  /-- `seq`: `_ => I(p2)`. -/
  | seqK
  /-- `map`: `v => call(fn, v)`. -/
  | mapFn
  /-- `handleErrorWith`: `{ case UserError(c) => I(k)[x := c]; case t => IO.raiseError(t) }`. -/
  | hewK
  /-- `attempt`: the `.map { case Right … }` function. -/
  | attemptMap
  /-- `uncancelable`: `poll => I(body)`. -/
  | uncBody
  /-- `onCancel`: the thunk of `IO.delay(emit fin)`. -/
  | ocFinEmit
  /-- `onCancel`: `_ => I(fin).void` (the `*>`). -/
  | ocFinThen
  /-- `IO#void`: `_ => ()` (`IO.scala:961-962`). -/
  | voidFn
  /-- `IO#as(VUnit)`: `_ => VUnit` (`IO.scala:182-183`). -/
  | asUnit
  /-- `guaranteeCase`: the `IO.uncancelable { poll => … }` body (`IO.scala:524-530`). -/
  | gcBody
  /-- `guaranteeCase`: the `onError` handler `t => pf.applyOrElse(t, …) *> IO.raiseError(t)`
  (`IO.scala:605-606`, `pf` from `IO.scala:526-528`). -/
  | gcOnError
  /-- `*> IO.raiseError(t)`: `_ => IO.raiseError(t)`. `vals = [err t]`. -/
  | constRaise
  /-- `reportError`: `t => IO.executionContext.flatMap(…)` (`IO.scala:967-971`). -/
  | reportK
  /-- `reportError`: `ec => IO(ec.reportFailure(t))`. `vals = [err t]`. -/
  | reportEc
  /-- `reportError`: the thunk `ec.reportFailure(t)`. `vals = [err t]`. -/
  | reportThunk
  /-- `guaranteeCase`: the `flatTap` function `a => finalizer(Succeeded(pure a)).as(a)`
  (`IO.scala:474`, `IO.scala:529`). -/
  | gcTap
  /-- `as(a)`: `_ => a`. `vals = [a]`. -/
  | constVal
  /-- `ocVal`: `fa.map(VSucceeded(_))`. -/
  | succFn
  /-- `guaranteeCase` finalizer: `o => IO.delay(emit …) *> I(fin)[x := o].void`. -/
  | gcFinK
  /-- `guaranteeCase` finalizer: the `emit` thunk. `vals = o :: env`. -/
  | gcFinEmit
  /-- `guaranteeCase` finalizer: `_ => I(fin)[x := o].void`. `vals = o :: env`. -/
  | gcFinThen
  /-- `start`: `f => VFiber(h.fiberHandle(f))`. -/
  | fiberHandle
  /-- `join`: `ocVal` as a `flatMap` function. -/
  | ocValK
  /-- `racePair`: the `.flatMap { case Left … case Right … }` function. -/
  | rpK
  /-- `racePair`: `o => VLeft(VPair(o, VFiber(h.fiberHandle(fb))))`. `vals = [fiber fb]`. -/
  | rpLeft
  /-- `racePair`: `o => VRight(VPair(VFiber(h.fiberHandle(fa)), o))`. `vals = [fiber fa]`. -/
  | rpRight
  /-- `Ref#get`: `F.delay(ar.get)` (`kernel/jvm-native/.../SyncRef.scala:30`). -/
  | refGetThunk
  /-- `Ref#set`: `F.delay(ar.set(a))` (`SyncRef.scala:32`). -/
  | refSetThunk
  /-- `refSet`: `_ => IO.delay { emit set; VUnit }` (the `*>`). -/
  | refSetThen
  /-- `refSet`: the thunk `{ emit set; VUnit }`. -/
  | refSetEmit
  /-- `Ref#modify`: `F.delay(spin)` (`SyncRef.scala:85-94`). -/
  | refModifyThunk
  /-- `async`: `ec => IO.async[Val] { cb => … }`. -/
  | asyncEc
  /-- `IO.async`: the `IOCont` body `(resume, get, lift) => G.uncancelable(…)`
  (`IO.scala:1419-1428`). `vals = ec :: env`. -/
  | asyncBody
  /-- `IO.async`: `poll => lift(k(resume)).flatMap(…)`. `vals = cont s :: ec :: env`. -/
  | asyncUnc
  /-- `async`: the registration thunk `IO.delay { … }` of the interpreter.
  `vals = cont s :: ec :: env`. -/
  | asyncReg
  /-- `IO.async`: `{ case Some(fin) => G.onCancel(poll(get), lift(fin)); case None => get }`.
  `vals = poll :: cont s :: ec :: env`. -/
  | asyncSel
  /-- `async` finalizer: the `emit fin` thunk. -/
  | asyncFinEmit
  /-- `async` finalizer: `_ => I(fin).void`. -/
  | asyncFinThen
  /-- `IO.never = async(_ => pure(Some(unit)))` (`kernel/.../Async.scala:168`): `IOCont` body. -/
  | neverBody
  /-- `IO.never`: `poll => lift(k(resume)).flatMap(…)`. `vals = [cont s]`. -/
  | neverUnc
  /-- `IO.never`: the `Some`/`None` selection. `vals = [poll, cont s]`. -/
  | neverSel
  /-- `IO.ref(v)`: the thunk `Ref.unsafe(v)` (`IO.scala:1822`, `Ref.scala:314`). -/
  | refNewThunk
  /-- `refNew`: `r => VRef(h.newRef(r))`. -/
  | refHandle
  /-- `IO.deferred`: the thunk `new IODeferred[A]` (`IO.scala:1824`). -/
  | deferredNewThunk
  /-- `deferredNew`: `d => VDeferred(h.newDeferred(d))`. -/
  | deferredHandle
  /-- `deferredComplete`: `ok => IO.delay { emit complete; VBool(ok) }`. -/
  | dcThen
  /-- `deferredComplete`: the thunk `{ emit complete; VBool(ok) }`. `vals = bool ok :: env`. -/
  | dcEmit
  -- format v1
  /-- `queueNew`: `q => VQueue(h.newQueue(q))`. -/
  | queueHandle
  /-- `queueTryTake`: `{ case Some(v) => VRight(v); case None => VLeft(VUnit) }`. -/
  | optEither
  /-- `allocatedCase`: `_._1`. -/
  | allocFst
  /-- `timeout`: not a lambda. The source code `src` of `Timeout.timeoutIO src ms`: the
  program `I(e)`, built when the `timeout` term is built. `vals = snap :: env`. -/
  | timeoutSrc
  /-- `rFlatMap`: `v => I_R(k)[x := v]` (the `REnv.bind` code). `vals = env`. -/
  | resBind
  /-- `rMake`: the acquire `I(acq)` (the `REnv.acquire` code). `vals = env`. -/
  | resAcquire
  /-- `rMake`: `a => I(rel)[x := a].void` (the `REnv.release` code). `vals = env`. -/
  | resRelease
  -- format v2 (track R)
  /-- `race`/`raceOutcome`/`both`/`bothOutcome`: not a lambda. The source code of `I(a)` of the
  combinator at `node` (`Race.call` builds it with `srcIO`). `vals = snap :: env`. -/
  | raceSrcA
  /-- The same for `I(b)`. -/
  | raceSrcB
  /-- `race`: `{ case Left(v) => VLeft(v); case Right(v) => VRight(v) }`. -/
  | raceK
  /-- `raceOutcome`: `{ case Left(oc) => ocVal(oc).map(VLeft(_)); case Right(oc) => ... }`. -/
  | roK
  /-- `VLeft(_)`. -/
  | mkLeft
  /-- `VRight(_)`. -/
  | mkRight
  /-- `both`: `{ case (x, y) => VPair(x, y) }`. -/
  | pairK
  /-- `bothOutcome`: `{ case (oa, ob) => ocVal(oa).flatMap(x => ...) }`. -/
  | boK
  /-- `bothOutcome`: `x => ocVal(ob).map(y => VPair(x, y))`. `vals = [ob]`. -/
  | boK2
  /-- `bothOutcome`: `y => VPair(x, y)`. `vals = [x]`. -/
  | boK3
  deriving DecidableEq, Repr

/-- All lambdas, in a fixed order. The index is the code of the lambda. -/
def Lam.all : List Lam :=
  [.delayThunk, .bindK, .seqK, .mapFn, .hewK, .attemptMap, .uncBody, .ocFinEmit, .ocFinThen,
   .voidFn, .asUnit, .gcBody, .gcOnError, .constRaise, .reportK, .reportEc, .reportThunk, .gcTap,
   .constVal, .succFn, .gcFinK, .gcFinEmit, .gcFinThen, .fiberHandle, .ocValK, .rpK, .rpLeft,
   .rpRight, .refGetThunk, .refSetThunk, .refSetThen, .refSetEmit, .refModifyThunk, .asyncEc,
   .asyncBody, .asyncUnc, .asyncReg, .asyncSel, .asyncFinEmit, .asyncFinThen, .neverBody,
   .neverUnc, .neverSel, .refNewThunk, .refHandle, .deferredNewThunk, .deferredHandle, .dcThen,
   .dcEmit, .queueHandle, .optEither, .allocFst, .timeoutSrc, .resBind, .resAcquire, .resRelease,
   .raceSrcA, .raceSrcB, .raceK, .roK, .mkLeft, .mkRight, .pairK, .boK, .boK2, .boK3]

def Lam.toNat (l : Lam) : Nat := Lam.all.idxOf l
def Lam.ofNat? (n : Nat) : Option Lam := Lam.all[n]?

/-- A closure: node, lambda and captured values. -/
structure Clo where
  node : Nat
  lam : Lam
  vals : List Val
  deriving DecidableEq, Repr

/-! ## Tokens: `Val` as a list of `Nat` (prefix code) -/

private def errKindToNat : ErrKind → Nat
  | .nonFatal => 0 | .interrupted => 1 | .fatal => 2

private def errKindOfNat? : Nat → Option ErrKind
  | 0 => some .nonFatal | 1 => some .interrupted | 2 => some .fatal | _ => none

private def intToNat (i : Int) : Nat := if i ≥ 0 then 2 * i.toNat else 2 * (-i).toNat - 1
private def intOfNat (n : Nat) : Int := if n % 2 = 0 then (n / 2 : Nat) else -((n + 1) / 2 : Nat)

/-- Prefix code of a value. -/
def valTokens : Val → List Nat
  | .unit => [0]
  | .bool b => [1, if b then 1 else 0]
  | .nat n => [2, n]
  | .int i => [3, intToNat i]
  | .pair a b => 4 :: valTokens a ++ valTokens b
  | .left v => 5 :: valTokens v
  | .right v => 6 :: valTokens v
  | .none => [7]
  | .some v => 8 :: valTokens v
  | .err e => [9, e.code, errKindToNat e.kind]
  | .ocSucceeded v => 10 :: valTokens v
  | .ocErrored e => [11, e.code, errKindToNat e.kind]
  | .ocCanceled => [12]
  | .fiber i => [13, i]
  | .ref i => [14, i]
  | .deferred i => [15, i]
  | .poll m f => [16, m, f]
  | .cont s => [17, s]
  | .ec i => [18, i]
  | .trace => [19]
  | .runtime => [20]

/-- Read one value from the front of a token list. `fuel` bounds the depth. -/
def valOfTokens? : (fuel : Nat) → List Nat → Option (Val × List Nat)
  | 0, _ => none
  | _, [] => none
  | fuel + 1, t :: ts =>
    match t, ts with
    | 0, r => some (.unit, r)
    | 1, b :: r => some (.bool (b == 1), r)
    | 2, n :: r => some (.nat n, r)
    | 3, n :: r => some (.int (intOfNat n), r)
    | 4, r => do
      let (a, r) ← valOfTokens? fuel r
      let (b, r) ← valOfTokens? fuel r
      pure (.pair a b, r)
    | 5, r => do let (v, r) ← valOfTokens? fuel r; pure (.left v, r)
    | 6, r => do let (v, r) ← valOfTokens? fuel r; pure (.right v, r)
    | 7, r => some (.none, r)
    | 8, r => do let (v, r) ← valOfTokens? fuel r; pure (.some v, r)
    | 9, c :: k :: r => do pure (.err { code := c, kind := ← errKindOfNat? k }, r)
    | 10, r => do let (v, r) ← valOfTokens? fuel r; pure (.ocSucceeded v, r)
    | 11, c :: k :: r => do pure (.ocErrored { code := c, kind := ← errKindOfNat? k }, r)
    | 12, r => some (.ocCanceled, r)
    | 13, i :: r => some (.fiber i, r)
    | 14, i :: r => some (.ref i, r)
    | 15, i :: r => some (.deferred i, r)
    | 16, m :: f :: r => some (.poll m f, r)
    | 17, s :: r => some (.cont s, r)
    | 18, i :: r => some (.ec i, r)
    | 19, r => some (.trace, r)
    | 20, r => some (.runtime, r)
    | _, _ => none

/-- Read `n` values. -/
def valsOfTokens? (fuel : Nat) : (n : Nat) → List Nat → Option (List Val × List Nat)
  | 0, ts => some ([], ts)
  | n + 1, ts => do
    let (v, ts) ← valOfTokens? fuel ts
    let (vs, ts) ← valsOfTokens? fuel n ts
    pure (v :: vs, ts)

/-! ## Tokens as one `Nat`

Each token `t` becomes its binary digits (least significant first), written as base-3 digits
`1` (bit 0) and `2` (bit 1), then a separator `0`. The digit list is read as a base-3 number
(first digit least significant) below a leading sentinel `1`, so leading zeros are kept. -/

/-- Base-3 digits of one token, with the separator. `fuel` bounds the bit count. -/
def tokenDigits : (fuel t : Nat) → List Nat
  | 0, _ => [0]
  | fuel + 1, t => if t = 0 then [0] else (if t % 2 = 0 then 1 else 2) :: tokenDigits fuel (t / 2)

/-- Pack tokens into one `Nat`. -/
def packTokens (ts : List Nat) : Nat :=
  (ts.flatMap fun t => tokenDigits (t + 1) t).foldr (fun d acc => d + 3 * acc) 1

/-- Base-3 digits below the sentinel. -/
def unpackDigits : (fuel n : Nat) → List Nat
  | 0, _ => []
  | fuel + 1, n => if n ≤ 1 then [] else n % 3 :: unpackDigits fuel (n / 3)

/-- Tokens from base-3 digits. `acc`/`bit` hold the token being read. -/
def tokensOfDigits : List Nat → (acc bit : Nat) → Option (List Nat)
  | [], 0, _ => some []
  | [], _, _ => none
  | 0 :: ds, acc, _ => (acc :: ·) <$> tokensOfDigits ds 0 1
  | 1 :: ds, acc, bit => tokensOfDigits ds acc (2 * bit)
  | 2 :: ds, acc, bit => tokensOfDigits ds (acc + bit) (2 * bit)
  | _ :: _, _, _ => none

/-- Unpack tokens. -/
def unpackTokens? (n : Nat) : Option (List Nat) :=
  tokensOfDigits (unpackDigits (n.log2 + 2) n) 0 1

/-! ## Closures as `Nat` -/

/-- Encode a closure as a `Fn.user` id. -/
def Clo.encode (c : Clo) : Nat :=
  packTokens (c.node :: c.lam.toNat :: c.vals.length :: c.vals.flatMap valTokens)

/-- Decode a `Fn.user` id. -/
def Clo.decode? (id : Nat) : Option Clo := do
  let ts ← unpackTokens? id
  match ts with
  | node :: lam :: n :: rest =>
    let lam ← Lam.ofNat? lam
    let (vals, rest) ← valsOfTokens? (rest.length + 1) n rest
    if rest.isEmpty then pure { node, lam, vals } else none
  | _ => none

/-- The `Codec.nsFn` namespace of the difftest closures. -/
def cloNs : Nat := 3

/-- The `Fn` of a closure: a user closure (even id, `Codec.userFn`) holding `.nat (Clo.encode c)`. -/
def Clo.fn (c : Clo) : Fn := CatsEffectInLean.Model.Codec.userFn (.nat c.encode)

/-- The closure of a `Fn.user` id, if the id is a difftest closure id. -/
def cloOfId? (id : Nat) : Option Clo :=
  if id % 2 == 0 then
    match CatsEffectInLean.Model.Codec.cloOfId id with
    | some (.nat e) => Clo.decode? e
    | _ => none
  else none

/-- Shorthand: `Fn` of lambda `lam` at node `node` with captured `vals`. -/
def clo (node : Nat) (lam : Lam) (vals : List Val) : Fn := Clo.fn { node, lam, vals }

end Difftest

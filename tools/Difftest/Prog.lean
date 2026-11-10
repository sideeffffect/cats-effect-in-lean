import Lean.Data.Json
import CatsEffectInLean.Model.Val

/-!
# Difftest program format v1: AST and JSON decoder (Lean side)

Spec: `wiki/methodology/difftest-program-format.md`. Scala twin:
`difftest/src/main/scala/cats/effect/difftest/{Ast,Json}.scala`.

The decoder has the same rules as the Scala decoder (`Json.scala`): unknown keys, unknown ops,
handle literals, unbound variables and poll misuse are decode errors.

Differences in representation (not in meaning):

* Variables are de Bruijn indices (0 = innermost binder). The decoder resolves names with the
  same shadowing rules as the Scala `Map` update (`scope + (x -> kind)`).
* `seq [p1, …, pn]` becomes left-nested binary `seq`. `seq [p]` is `p`. This is the same
  `IO` term as `ps.tail.foldLeft(run(ps.head))(…)` in `Interp.scala`.
* `async` with and without `fin` are two constructors (no nested `Option Prog`).
* Literal values are `CatsEffectInLean.Model.Val`. `errored code` is `Val.ocErrored (userErr code)`.
* Format v1 adds `syncStep` (root only), `timeout`, `timeoutTo`, the queue ops and
  `allocatedCase`. The resource nodes (`rPure`, `rEval`, `rMake`, `rFlatMap`) are `Prog`
  constructors too, so that one pre-order numbering covers them; the decoder allows them only
  in resource positions (`allocatedCase.res`, `rFlatMap.res`, `rFlatMap.k`). A v1 op in a v0
  case is a decode error.

This module is test-harness code. It is not part of the `CatsEffectInLean` library.
-/

namespace Difftest

open Lean (Json)
open CatsEffectInLean.Model

/-! ## Errors

`Err.code` encodes the Scala exception class. Codes 0 and 1 are reserved for harness errors,
so a `UserError(c)` has code `c + 2`. Code `10^6` is the model `TimeoutException`
(`Timeout.timeoutCode`), so `UserError(c)` for `c + 2 ≥ 10^6` has code `c + 3`. (Before
2026-11-10, `UserError(999998)` had code `10^6` and printed as `TimeoutException`: a program
that catches a `TimeoutException` gets `nat 999998` and can raise it again as a `UserError`.)
Both errors give the value-language code 999998 (`Interp.scala` `CodeOf`). -/

/-- The code of `Model.Timeout.timeoutErr` (`Tests.lean` checks that they agree). -/
def timeoutModelCode : Nat := 1000000

/-- `UserError(c)` (`difftest/.../UserFns.scala:6`). -/
def userErr (c : Nat) : Err := { code := if c + 2 < timeoutModelCode then c + 2 else c + 3 }

/-- `TypeError` (`difftest/.../UserFns.scala:9`): a value of the wrong shape. -/
def typeErr : Err := { code := 0 }

/-- A harness error: the translation reached a construct that the Lean model cannot express
yet (see `wiki/methodology/difftest-program-format.md`, "Lean side"). It never occurs in Scala. -/
def harnessErr : Err := { code := 1 }

/-- The value-language code of an error (`Interp.scala` `CodeOf`): `c` for `UserError(c)`, and
999998 for the model `TimeoutException`. -/
def userCode? (e : Err) : Option Nat :=
  if e.kind = .nonFatal ∧ e.code ≥ 2 then
    some (if e.code ≤ timeoutModelCode then e.code - 2 else e.code - 3)
  else none

/-! ## AST -/

/-- An argument position: a literal or a variable (de Bruijn index). -/
inductive Atom where
  | lit (v : Val)
  | var (i : Nat)
  deriving DecidableEq, Repr

/-- When an `async` callback is called. -/
inductive When where
  | sync
  | later
  deriving DecidableEq, Repr

/-- The result that one callback call passes: `ok v` or `err code` (a `UserError`). -/
inductive CbRes where
  | ok (v : Val)
  | err (code : Nat)
  deriving DecidableEq, Repr

/-- One `async` callback call. -/
structure CbCall where
  when : When
  res : CbRes
  deriving DecidableEq, Repr

/-- The callback result as `Either[Throwable, Val]` (`Val.ofExcept`). -/
def CbRes.toVal : CbRes → Val
  | .ok v => Val.ofExcept (.ok v)
  | .err c => Val.ofExcept (.error (userErr c))

/-- A program (format v1). Binders: `bind.k`, `handleErrorWith.k`, `guaranteeCase.fin`,
`case.lk`, `case.rk`, `rMake.rel`, `rFlatMap.k` bind one value; `uncancelable.body` binds one
poll; `split.k` binds two values (`b` is index 0, `a` is index 1). -/
inductive Prog where
  | pure (a : Atom)
  | raise (code : Nat)
  | delay (fn : Nat) (arg : Atom)
  | bind (e k : Prog)
  | seq (e k : Prog)
  | map (e : Prog) (fn : Nat)
  | handleErrorWith (e k : Prog)
  | attempt (e : Prog)
  | uncancelable (body : Prog)
  | poll (q : Nat) (e : Prog)
  | onCancel (e fin : Prog) (tag : Nat)
  | guaranteeCase (e fin : Prog) (tag : Nat)
  | canceled
  | cede
  | never
  | start (e : Prog)
  | join (f : Atom)
  | cancel (f : Atom)
  | racePair (a b : Prog)
  | sleep (ms : Nat)
  | refNew (v : Atom)
  | refGet (r : Atom)
  | refSet (r v : Atom)
  | refModify (r : Atom) (fn : Nat)
  | deferredNew
  | deferredGet (d : Atom)
  | deferredComplete (d v : Atom)
  | async (cbs : List CbCall) (tag : Nat)
  | asyncFin (cbs : List CbCall) (fin : Prog) (tag : Nat)
  | case (on : Atom) (lk rk : Prog)
  | split (on : Atom) (k : Prog)
  -- format v1
  /-- Root only: `e.syncStep(limit).unsafeRunSync()`, then the selected `IO`. -/
  | syncStep (e : Prog) (limit : Nat)
  | timeout (e : Prog) (ms : Nat)
  | timeoutTo (e fb : Prog) (ms : Nat)
  | queueNew
  | queueOffer (q v : Atom)
  | queueTake (q : Atom)
  | queueTryTake (q : Atom)
  /-- `I_R(res).allocatedCase.map(_._1)`; `res` is a resource node. -/
  | allocatedCase (res : Prog)
  /-- Resource nodes (only in resource positions). -/
  | rPure (a : Atom)
  | rEval (e : Prog)
  | rMake (acq rel : Prog)
  | rFlatMap (res k : Prog)
  -- format v2 (track R)
  /-- `I(a).race(I(b))` then `Left(v) ↦ left v`, `Right(v) ↦ right v`. -/
  | race (a b : Prog)
  /-- `I(a).raceOutcome(I(b))` then `ocVal` under `left`/`right`. -/
  | raceOutcome (a b : Prog)
  /-- `I(a).both(I(b))` then `(x, y) ↦ pair x y`. -/
  | both (a b : Prog)
  /-- `I(a).bothOutcome(I(b))` then `ocVal` of each, as a pair. -/
  | bothOutcome (a b : Prog)
  -- format v2 (Phase 6, track G)
  /-- `I(e).guarantee(IO.delay(emit fin) *> I(fin).void)`. -/
  | guarantee (e fin : Prog) (tag : Nat)
  /-- `I(acq).bracket(x => I(use))(x => IO.delay(emit fin) *> I(rel).void)`; `use` and `rel`
  bind `x`. -/
  | bracket (acq use rel : Prog) (tag : Nat)
  /-- `I(acq).bracketCase(x => I(use))((x, oc) => ocVal(oc).flatMap(y => …))`; `use` binds `x`,
  `rel` binds `x` and `y` (`y` is index 0). -/
  | bracketCase (acq use rel : Prog) (tag : Nat)
  /-- `IO.bracketFull(poll => I(acq))(x => I(use))((x, oc) => …)`; `acq` binds the poll. -/
  | bracketFull (acq use rel : Prog) (tag : Nat)
  -- format v2 (Phase 6, track M)
  /-- `I(e).memoize.map(get => VMemo(h.newMemo(get)))`. -/
  | memoize (e : Prog)
  /-- The `get` of a memo handle. -/
  | memoGet (m : Atom)
  deriving DecidableEq, Repr

/-- Number of nodes. Nodes are numbered in pre-order from 0; the children of a node with
number `n` are `n + 1` and `n + 1 + size first`. -/
def Prog.size : Prog → Nat
  | .bind e k | .seq e k | .handleErrorWith e k | .onCancel e k _ | .guaranteeCase e k _
  | .racePair e k | .case _ e k | .timeoutTo e k _ | .rMake e k | .rFlatMap e k
  | .race e k | .raceOutcome e k | .both e k | .bothOutcome e k => 1 + e.size + k.size
  | .map e _ | .attempt e | .uncancelable e | .poll _ e | .start e | .asyncFin _ e _
  | .split _ e | .syncStep e _ | .timeout e _ | .allocatedCase e | .rEval e | .memoize e => 1 + e.size
  | .guarantee e k _ => 1 + e.size + k.size
  | .bracket a u r _ | .bracketCase a u r _ | .bracketFull a u r _ => 1 + a.size + u.size + r.size
  | _ => 1

/-- The node with pre-order number `i`. -/
def Prog.at? : Prog → Nat → Option Prog
  | p, 0 => some p
  | p, i + 1 =>
    match p with
    | .bind e k | .seq e k | .handleErrorWith e k | .onCancel e k _ | .guaranteeCase e k _
    | .racePair e k | .case _ e k | .timeoutTo e k _ | .rMake e k | .rFlatMap e k
    | .race e k | .raceOutcome e k | .both e k | .bothOutcome e k =>
      if i < e.size then e.at? i else k.at? (i - e.size)
    | .map e _ | .attempt e | .uncancelable e | .poll _ e | .start e | .asyncFin _ e _
    | .split _ e | .syncStep e _ | .timeout e _ | .allocatedCase e | .rEval e | .memoize e => e.at? i
    | .guarantee e k _ => if i < e.size then e.at? i else k.at? (i - e.size)
    | .bracket a u r _ | .bracketCase a u r _ | .bracketFull a u r _ =>
      if i < a.size then a.at? i
      else if i - a.size < u.size then u.at? (i - a.size)
      else r.at? (i - a.size - u.size)
    | _ => none

/-- The op name of the root node (JSON `op`). -/
def Prog.opName : Prog → String
  | .pure .. => "pure" | .raise .. => "raise" | .delay .. => "delay" | .bind .. => "bind"
  | .seq .. => "seq" | .map .. => "map" | .handleErrorWith .. => "handleErrorWith"
  | .attempt .. => "attempt" | .uncancelable .. => "uncancelable" | .poll .. => "poll"
  | .onCancel .. => "onCancel" | .guaranteeCase .. => "guaranteeCase"
  | .canceled => "canceled" | .cede => "cede" | .never => "never" | .start .. => "start"
  | .join .. => "join" | .cancel .. => "cancel" | .racePair .. => "racePair"
  | .sleep .. => "sleep" | .refNew .. => "refNew" | .refGet .. => "refGet"
  | .refSet .. => "refSet" | .refModify .. => "refModify" | .deferredNew => "deferredNew"
  | .deferredGet .. => "deferredGet" | .deferredComplete .. => "deferredComplete"
  | .async .. | .asyncFin .. => "async" | .case .. => "case" | .split .. => "split"
  | .syncStep .. => "syncStep" | .timeout .. => "timeout" | .timeoutTo .. => "timeoutTo"
  | .queueNew => "queueNew" | .queueOffer .. => "queueOffer" | .queueTake .. => "queueTake"
  | .queueTryTake .. => "queueTryTake" | .allocatedCase .. => "allocatedCase"
  | .rPure .. => "rPure" | .rEval .. => "rEval" | .rMake .. => "rMake" | .rFlatMap .. => "rFlatMap"
  | .race .. => "race" | .raceOutcome .. => "raceOutcome" | .both .. => "both"
  | .bothOutcome .. => "bothOutcome"
  | .guarantee .. => "guarantee" | .bracket .. => "bracket" | .bracketCase .. => "bracketCase"
  | .bracketFull .. => "bracketFull"
  | .memoize .. => "memoize" | .memoGet .. => "memoGet"

/-- The two sub-programs of a v2 combinator (`race`, `raceOutcome`, `both`, `bothOutcome`). -/
def Prog.combArgs? : Prog → Option (Prog × Prog)
  | .race a b | .raceOutcome a b | .both a b | .bothOutcome a b => some (a, b)
  | _ => none

/-- All op names that occur in the program (pre-order, with repeats). -/
def Prog.ops (p : Prog) : List String :=
  p.opName :: match p with
    | .bind e k | .seq e k | .handleErrorWith e k | .onCancel e k _ | .guaranteeCase e k _
    | .racePair e k | .case _ e k | .timeoutTo e k _ | .rMake e k | .rFlatMap e k
    | .race e k | .raceOutcome e k | .both e k | .bothOutcome e k => e.ops ++ k.ops
    | .map e _ | .attempt e | .uncancelable e | .poll _ e | .start e | .asyncFin _ e _
    | .split _ e | .syncStep e _ | .timeout e _ | .allocatedCase e | .rEval e | .memoize e => e.ops
    | .guarantee e k _ => e.ops ++ k.ops
    | .bracket a u r _ | .bracketCase a u r _ | .bracketFull a u r _ => a.ops ++ u.ops ++ r.ops
    | _ => []

/-- Does building `I(p)` read mutable state (`fib.join`, `fib.cancel`, `deferred.get` at a
position that Scala builds at once)? Lazy positions (a `bind` continuation, an `uncancelable`
body, a finalizer that runs later, an `async` finalizer) do not count. -/
def Prog.eagerReads : Prog → Bool
  | .join _ | .cancel _ | .deferredGet _ => true
  | .bind e _ | .seq e _ | .map e _ | .handleErrorWith e _ | .attempt e | .poll _ e
  | .guaranteeCase e _ _ | .start e | .timeout e _ | .rEval e | .syncStep e _
  | .allocatedCase e => e.eagerReads
  | .onCancel e k _ | .racePair e k | .timeoutTo e k _ | .case _ e k | .rMake e k
  | .rFlatMap e k => e.eagerReads || k.eagerReads
  | .race e k | .raceOutcome e k | .both e k | .bothOutcome e k => e.eagerReads || k.eagerReads
  | .split _ k => k.eagerReads
  -- format v2: `guarantee` builds `e` and `fin` at once; `bracket`/`bracketCase` build `acq`
  | .guarantee e k _ => e.eagerReads || k.eagerReads
  | .bracket a _ _ _ | .bracketCase a _ _ _ => a.eagerReads
  -- format v2 (track M): `memoize` builds `e` at once
  | .memoize e => e.eagerReads
  | _ => false

/-- The resource restriction: no `IO` program inside a resource node reads state when it is
built (`Prog.eagerReads`). The `Resource` mirror builds these programs without a view
(`REnv.bind`, `REnv.acquire`, `REnv.release` take no `View`). -/
def Prog.resViewFree : Prog → Bool
  | .rEval e => !e.eagerReads && e.resViewFree
  | .rMake a r => !a.eagerReads && !r.eagerReads && a.resViewFree && r.resViewFree
  | .bind e k | .seq e k | .handleErrorWith e k | .onCancel e k _ | .guaranteeCase e k _
  | .racePair e k | .case _ e k | .timeoutTo e k _ | .rFlatMap e k => e.resViewFree && k.resViewFree
  | .race e k | .raceOutcome e k | .both e k | .bothOutcome e k => e.resViewFree && k.resViewFree
  | .map e _ | .attempt e | .uncancelable e | .poll _ e | .start e | .asyncFin _ e _
  | .split _ e | .syncStep e _ | .timeout e _ | .allocatedCase e | .memoize e => e.resViewFree
  | .guarantee e k _ => e.resViewFree && k.resViewFree
  | .bracket a u r _ | .bracketCase a u r _ | .bracketFull a u r _ =>
    a.resViewFree && u.resViewFree && r.resViewFree
  | _ => true

/-- One replay choice. -/
inductive Choice where
  | pick (i : Nat)
  | cancelFiber (handle : Nat)
  deriving DecidableEq, Repr

/-- The run mode of a test case. -/
inductive Mode where
  | replay (choices : List Choice)
  | testcontrol (seed : Nat)
  deriving DecidableEq, Repr

/-- One test case (one input line). -/
structure TestCase where
  /-- The format version of the line (0, 1 or 2). -/
  version : Nat := 2
  id : String
  mode : Mode
  prog : Prog
  maxSteps : Nat
  /-- `IORuntimeConfig.cancelationCheckThreshold` of a replay run (optional case field
  `runtime`; default 512, `IORuntimeConfig.scala`). -/
  cancelCheck : Nat := 512
  /-- `IORuntimeConfig.autoYieldThreshold` of a replay run (default 1024). A small value puts
  an auto-yield (the effect of a `preempt` choice, `Model/SchedP.lean`) at many points. -/
  autoYield : Nat := 1024
  deriving Repr

/-- `Json.FormatVersion` in `Json.scala`. Versions 0, 1 and 2 are accepted. -/
def formatVersion : Nat := 2
/-- `Json.MaxLimit`: `Int.MaxValue`, the largest `syncStep` limit. -/
def maxLimit : Nat := 2147483647
/-- Ops of format v1 (`Json.V1Ops`). -/
def v1Ops : List String :=
  ["syncStep", "timeout", "timeoutTo", "queueNew", "queueOffer", "queueTake", "queueTryTake",
   "allocatedCase", "rPure", "rEval", "rMake", "rFlatMap"]
/-- Ops of format v2 (`Json.V2Ops`): a decode error in a v0 or v1 case. -/
def v2Ops : List String := ["race", "raceOutcome", "both", "bothOutcome", "guarantee", "bracket",
  "bracketCase", "bracketFull", "memoize", "memoGet"]
/-- The resource ops. -/
def resOps : List String := ["rPure", "rEval", "rMake", "rFlatMap"]
/-- `Json.DefaultMaxSteps` in `Json.scala`. -/
def defaultMaxSteps : Nat := 10000
/-- Number of user functions (`UserFns.size`). -/
def userFnCount : Nat := 10

/-! ## Decoder -/

/-- Decoder monad: the error is a message (the caller adds the `decode: ` prefix). -/
abbrev D := Except String

private def fail {α : Type} (msg : String) : D α := throw msg

private def obj (j : Json) (ctx : String) : D (List (String × Json)) :=
  match j with
  | .obj kvs => pure kvs.toList
  | _ => fail s!"{ctx}: expected an object, got {j.compress}"

private def keys (o : List (String × Json)) (allowed : List String) (ctx : String) : D Unit := do
  let extra := (o.map (·.1)).filter (fun k => !allowed.contains k)
  unless extra.isEmpty do fail s!"{ctx}: unknown keys {",".intercalate extra}"

private def get? (o : List (String × Json)) (k : String) : Option Json :=
  (o.find? (·.1 == k)).map (·.2)

private def field (o : List (String × Json)) (k : String) (ctx : String) : D Json :=
  match get? o k with
  | some v => pure v
  | none => fail s!"{ctx}: missing key '{k}'"

/-- A JSON number that is a natural number `≤ 9·10^15` (same bound as `Json.scala` `nat`). -/
private def nat (j : Json) (ctx : String) : D Nat :=
  match j with
  | .num n =>
    let den := 10 ^ n.exponent
    if n.mantissa ≥ 0 ∧ n.mantissa % den = 0 ∧ (n.mantissa / den).toNat ≤ 9000000000000000 then
      pure (n.mantissa / den).toNat
    else fail s!"{ctx}: expected a natural number, got {j.compress}"
  | _ => fail s!"{ctx}: expected a natural number, got {j.compress}"

private def str (j : Json) (ctx : String) : D String :=
  match j with
  | .str s => if s.isEmpty then fail s!"{ctx}: expected a non-empty string, got {j.compress}"
              else pure s
  | _ => fail s!"{ctx}: expected a non-empty string, got {j.compress}"

/-- Decode a value literal (`Json.decodeVal`). Handles are rejected. -/
partial def decodeVal (j : Json) : D Val := do
  let o ← obj j "value"
  let t ← str (← field o "t" "value") "value.t"
  let only (ks : List String) : D Unit := keys o ("t" :: ks) s!"value '{t}'"
  match t with
  | "unit" => only []; pure .unit
  | "bool" =>
    only ["v"]
    match ← field o "v" t with
    | .bool b => pure (.bool b)
    | x => fail s!"bool: expected true/false, got {x.compress}"
  | "nat" => only ["v"]; pure (.nat (← nat (← field o "v" t) "nat.v"))
  | "pair" => only ["a", "b"]; pure (.pair (← decodeVal (← field o "a" t)) (← decodeVal (← field o "b" t)))
  | "left" => only ["v"]; pure (.left (← decodeVal (← field o "v" t)))
  | "right" => only ["v"]; pure (.right (← decodeVal (← field o "v" t)))
  | "succeeded" => only ["v"]; pure (.ocSucceeded (← decodeVal (← field o "v" t)))
  | "errored" => only ["code"]; pure (.ocErrored (userErr (← nat (← field o "code" t) "errored.code")))
  | "canceled" => only []; pure .ocCanceled
  | "fiber" | "ref" | "deferred" | "queue" | "memo" => fail s!"value '{t}': handles cannot be literals"
  | _ => fail s!"unknown value tag '{t}'"

/-- The kind of a bound name. -/
inductive Kind where
  | v
  | p
  deriving DecidableEq

/-- A scope: innermost binder first. The index of a name is its first position. -/
abbrev Scope := List (String × Kind)

private def lookup (s : Scope) (x : String) : Option (Nat × Kind) :=
  go s 0
where
  go : Scope → Nat → Option (Nat × Kind)
    | [], _ => none
    | (y, k) :: rest, i => if y == x then some (i, k) else go rest (i + 1)

private def atom (j : Json) (scope : Scope) (ctx : String) : D Atom := do
  match j with
  | .obj kvs =>
    let o := kvs.toList
    if get? o "t" == some (.str "var") then
      keys o ["t", "x"] ctx
      let x ← str (← field o "x" ctx) s!"{ctx}.x"
      match lookup scope x with
      | some (i, .v) => pure (.var i)
      | some (_, .p) => fail s!"{ctx}: '{x}' is a poll, not a value"
      | none => fail s!"{ctx}: unbound variable '{x}'"
    else .lit <$> decodeVal j
  | _ => .lit <$> decodeVal j

private def cb (j : Json) : D CbCall := do
  let o ← obj j "callback"
  keys o ["when", "ok", "err"] "callback"
  let when ← match ← str (← field o "when" "callback") "callback.when" with
    | "sync" => pure When.sync
    | "later" => pure When.later
    | w => fail s!"callback.when: expected sync or later, got '{w}'"
  match get? o "ok", get? o "err" with
  | some v, none => pure { when, res := .ok (← decodeVal v) }
  | none, some c => pure { when, res := .err (← nat c "callback.err") }
  | _, _ => fail "callback: give exactly one of 'ok' or 'err'"

/-- The position of a node: an `IO` program or a resource (`Json.prog` / `Json.res`). -/
inductive Pos where
  | io
  | res
  deriving DecidableEq

/-- Decode a program (`Json.prog`) or, at a resource position, a resource (`Json.res`).
`ver`: the format version of the case. -/
partial def decodeProgIn (j : Json) (scope : Scope) (ver : Nat) (pos : Pos := .io) : D Prog := do
  let o ← obj j "prog"
  let op ← str (← field o "op" "prog") "prog.op"
  let ctx := s!"op '{op}'"
  if ver < 1 && v1Ops.contains op then fail s!"{ctx}: not in format v0 (use v 1)"
  if ver < 2 && v2Ops.contains op then fail s!"{ctx}: not in format v{ver} (use v 2)"
  if pos == .res && !resOps.contains op then
    fail s!"{ctx}: not a resource op (expected rPure, rEval, rMake or rFlatMap)"
  if pos == .io && resOps.contains op then fail s!"{ctx}: a resource op outside a resource position"
  let only (ks : List String) : D Unit := keys o ("op" :: ks) ctx
  let p (k : String) (s : Scope := scope) : D Prog := do decodeProgIn (← field o k ctx) s ver
  let r (k : String) (s : Scope := scope) : D Prog := do decodeProgIn (← field o k ctx) s ver .res
  let a (k : String) : D Atom := do atom (← field o k ctx) scope s!"{ctx}.{k}"
  let n (k : String) : D Nat := do nat (← field o k ctx) s!"{ctx}.{k}"
  let s (k : String) : D String := do str (← field o k ctx) s!"{ctx}.{k}"
  let tag : D Nat := match get? o "tag" with
    | some t => nat t s!"{ctx}.tag"
    | none => pure 0
  let fn (k : String) : D Nat := do
    let i ← n k
    if i ≥ userFnCount then fail s!"{ctx}.{k}: unknown user function {i}" else pure i
  match op with
  | "pure" => only ["v"]; .pure <$> a "v"
  | "raise" => only ["code"]; .raise <$> n "code"
  | "delay" =>
    only ["fn", "arg"]
    let f ← fn "fn"
    let arg ← match get? o "arg" with
      | some x => atom x scope s!"{ctx}.arg"
      | none => pure (.lit .unit)
    pure (.delay f arg)
  | "bind" =>
    only ["x", "e", "k"]; let x ← s "x"
    pure (.bind (← p "e") (← p "k" ((x, .v) :: scope)))
  | "seq" =>
    only ["ps"]
    match ← field o "ps" ctx with
    | .arr ps =>
      match ps.toList with
      | [] => fail s!"{ctx}.ps: expected a non-empty array, got []"
      | q :: qs =>
        let first ← decodeProgIn q scope ver
        qs.foldlM (fun acc r => do pure (Prog.seq acc (← decodeProgIn r scope ver))) first
    | x => fail s!"{ctx}.ps: expected a non-empty array, got {x.compress}"
  | "map" => only ["e", "fn"]; pure (.map (← p "e") (← fn "fn"))
  | "handleErrorWith" =>
    only ["e", "x", "k"]; let x ← s "x"
    pure (.handleErrorWith (← p "e") (← p "k" ((x, .v) :: scope)))
  | "attempt" => only ["e"]; .attempt <$> p "e"
  | "uncancelable" =>
    only ["poll", "body"]; let q ← s "poll"
    .uncancelable <$> p "body" ((q, .p) :: scope)
  | "poll" =>
    only ["poll", "e"]; let q ← s "poll"
    match lookup scope q with
    | some (i, .p) => pure (.poll i (← p "e"))
    | _ => fail s!"{ctx}: '{q}' is not a bound poll"
  | "onCancel" => only ["e", "fin", "tag"]; pure (.onCancel (← p "e") (← p "fin") (← tag))
  | "guaranteeCase" =>
    only ["e", "x", "fin", "tag"]; let x ← s "x"
    pure (.guaranteeCase (← p "e") (← p "fin" ((x, .v) :: scope)) (← tag))
  | "canceled" => only []; pure .canceled
  | "cede" => only []; pure .cede
  | "never" => only []; pure .never
  | "start" => only ["e"]; .start <$> p "e"
  | "join" => only ["f"]; .join <$> a "f"
  | "cancel" => only ["f"]; .cancel <$> a "f"
  | "racePair" => only ["a", "b"]; pure (.racePair (← p "a") (← p "b"))
  | "sleep" => only ["ms"]; .sleep <$> n "ms"
  | "refNew" => only ["v"]; .refNew <$> a "v"
  | "refGet" => only ["r"]; .refGet <$> a "r"
  | "refSet" => only ["r", "v"]; pure (.refSet (← a "r") (← a "v"))
  | "refModify" => only ["r", "fn"]; pure (.refModify (← a "r") (← fn "fn"))
  | "deferredNew" => only []; pure .deferredNew
  | "deferredGet" => only ["d"]; .deferredGet <$> a "d"
  | "deferredComplete" => only ["d", "v"]; pure (.deferredComplete (← a "d") (← a "v"))
  | "async" =>
    only ["cbs", "fin", "tag"]
    let cbs ← match ← field o "cbs" ctx with
      | .arr cs => cs.toList.mapM cb
      | x => fail s!"{ctx}.cbs: expected an array, got {x.compress}"
    match get? o "fin" with
    | some f => pure (.asyncFin cbs (← decodeProgIn f scope ver) (← tag))
    | none => pure (.async cbs (← tag))
  | "case" =>
    only ["on", "l", "lk", "r", "rk"]; let l ← s "l"; let r ← s "r"
    pure (.case (← a "on") (← p "lk" ((l, .v) :: scope)) (← p "rk" ((r, .v) :: scope)))
  | "split" =>
    only ["on", "a", "b", "k"]; let x ← s "a"; let y ← s "b"
    pure (.split (← a "on") (← p "k" ((y, .v) :: (x, .v) :: scope)))
  | "timeout" => only ["e", "ms"]; pure (.timeout (← p "e") (← n "ms"))
  | "timeoutTo" =>
    only ["e", "ms", "fb"]; let e ← p "e"; let ms ← n "ms"
    pure (.timeoutTo e (← p "fb") ms)
  | "queueNew" => only []; pure .queueNew
  | "queueOffer" => only ["q", "v"]; pure (.queueOffer (← a "q") (← a "v"))
  | "queueTake" => only ["q"]; .queueTake <$> a "q"
  | "queueTryTake" => only ["q"]; .queueTryTake <$> a "q"
  | "allocatedCase" => only ["res"]; .allocatedCase <$> r "res"
  | "syncStep" => fail s!"{ctx}: only at the root of a program"
  | "rPure" => only ["v"]; .rPure <$> a "v"
  | "rEval" => only ["e"]; .rEval <$> p "e"
  | "rMake" =>
    only ["acq", "x", "rel"]; let x ← s "x"
    pure (.rMake (← p "acq") (← p "rel" ((x, .v) :: scope)))
  | "rFlatMap" =>
    only ["res", "x", "k"]; let x ← s "x"
    pure (.rFlatMap (← r "res") (← r "k" ((x, .v) :: scope)))
  | "race" => only ["a", "b"]; pure (.race (← p "a") (← p "b"))
  | "raceOutcome" => only ["a", "b"]; pure (.raceOutcome (← p "a") (← p "b"))
  | "both" => only ["a", "b"]; pure (.both (← p "a") (← p "b"))
  | "bothOutcome" => only ["a", "b"]; pure (.bothOutcome (← p "a") (← p "b"))
  -- format v2
  | "guarantee" => only ["e", "fin", "tag"]; pure (.guarantee (← p "e") (← p "fin") (← tag))
  | "bracket" =>
    only ["acq", "x", "use", "rel", "tag"]; let x ← s "x"
    pure (.bracket (← p "acq") (← p "use" ((x, .v) :: scope)) (← p "rel" ((x, .v) :: scope)) (← tag))
  | "bracketCase" =>
    only ["acq", "x", "use", "y", "rel", "tag"]; let x ← s "x"; let y ← s "y"
    pure (.bracketCase (← p "acq") (← p "use" ((x, .v) :: scope))
      (← p "rel" ((y, .v) :: (x, .v) :: scope)) (← tag))
  | "bracketFull" =>
    only ["poll", "acq", "x", "use", "y", "rel", "tag"]; let q ← s "poll"; let x ← s "x"; let y ← s "y"
    pure (.bracketFull (← p "acq" ((q, .p) :: scope)) (← p "use" ((x, .v) :: scope))
      (← p "rel" ((y, .v) :: (x, .v) :: scope)) (← tag))
  -- format v2 (track M)
  | "memoize" => only ["e"]; pure (.memoize (← p "e"))
  | "memoGet" => only ["m"]; .memoGet <$> a "m"
  | _ => fail s!"unknown op '{op}'"

/-- Reject a v2 op anywhere in `j` (a case of format v0 or v1; `Json.checkNoV2`). -/
partial def checkNoV2 : Json → D Unit
  | .obj kvs => do
    match kvs.toList.lookup "op" with
    | some (.str op) =>
      if v2Ops.contains op then fail s!"op '{op}': not in format v0/v1 (use \"v\":2)"
    | _ => pure ()
    kvs.toList.forM fun (_, v) => checkNoV2 v
  | .arr xs => xs.toList.forM checkNoV2
  | _ => pure ()

/-- Decode a closed program. `syncStep` is allowed only here, at the root. -/
def decodeProg (j : Json) (version : Nat := formatVersion) : D Prog := do
  let v1 := version ≥ 1
  if version < 2 then checkNoV2 j
  let o ← obj j "prog"
  match get? o "op" with
  | some (.str "syncStep") =>
    if !v1 then fail "op 'syncStep': not in format v0 (use v 1)"
    keys o ["op", "e", "limit"] "op 'syncStep'"
    let limit ← nat (← field o "limit" "op 'syncStep'") "op 'syncStep'.limit"
    if limit > maxLimit then fail s!"op 'syncStep'.limit: more than Int.MaxValue: {limit}"
    pure (.syncStep (← decodeProgIn (← field o "e" "op 'syncStep'") [] version) limit)
  | _ => decodeProgIn j [] version

private def choice (j : Json) : D Choice :=
  match j with
  | .num _ => .pick <$> nat j "choice"
  | .obj kvs => do
    let o := kvs.toList
    keys o ["cancel"] "choice"
    .cancelFiber <$> nat (← field o "cancel" "choice") "choice.cancel"
  | _ => fail s!"choice: expected a number or \{\"cancel\":n}, got {j.compress}"

/-- Decode one test case (`Json.decodeCase`). -/
def decodeCase (j : Json) : D TestCase := do
  let o ← obj j "case"
  keys o ["v", "id", "mode", "choices", "seed", "maxSteps", "runtime", "prog"] "case"
  let v ← nat (← field o "v" "case") "case.v"
  if v > formatVersion then fail s!"case.v: unsupported format version {v}"
  let id ← str (← field o "id" "case") "case.id"
  let mode ← match ← str (← field o "mode" "case") "case.mode" with
    | "replay" =>
      if (get? o "seed").isSome then fail "case: 'seed' is only for mode testcontrol"
      let cs ← match get? o "choices" with
        | none => pure []
        | some (.arr cs) => cs.toList.mapM choice
        | some x => fail s!"case.choices: expected an array, got {x.compress}"
      pure (Mode.replay cs)
    | "testcontrol" =>
      if (get? o "choices").isSome then fail "case: 'choices' is only for mode replay"
      pure (Mode.testcontrol (← nat (← field o "seed" "case") "case.seed"))
    | m => fail s!"case.mode: unknown mode '{m}'"
  let maxSteps ← match get? o "maxSteps" with
    | some x => nat x "case.maxSteps"
    | none => pure defaultMaxSteps
  -- `runtime`: the `IORuntimeConfig` thresholds of a replay run, with the checks of
  -- `IORuntimeConfig.scala:33-40` (auto-yield > 1, cancelation check > 0, a multiple).
  let (cancelCheck, autoYield) ← match get? o "runtime" with
    | none => pure (512, 1024)
    | some r =>
      if (get? o "seed").isSome then fail "case: 'runtime' is only for mode replay"
      let ro ← obj r "case.runtime"
      keys ro ["cancelationCheckThreshold", "autoYieldThreshold"] "case.runtime"
      let c ← nat (← field ro "cancelationCheckThreshold" "case.runtime") "case.runtime.cancelationCheckThreshold"
      let a ← nat (← field ro "autoYieldThreshold" "case.runtime") "case.runtime.autoYieldThreshold"
      if c == 0 || a ≤ 1 || a % c != 0 || a > maxLimit then
        fail s!"case.runtime: invalid thresholds {c}, {a}"
      pure (c, a)
  pure { version := v, id, mode, prog := ← decodeProg (← field o "prog" "case") v, maxSteps,
         cancelCheck, autoYield }

end Difftest

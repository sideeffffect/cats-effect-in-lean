import Lean.Data.Json
import CatsEffectInLean.Model.Val

/-!
# Difftest program format v0: AST and JSON decoder (Lean side)

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

This module is test-harness code. It is not part of the `CatsEffectInLean` library.
-/

namespace Difftest

open Lean (Json)
open CatsEffectInLean.Model

/-! ## Errors

`Err.code` encodes the Scala exception class. Codes 0 and 1 are reserved for harness errors,
so a `UserError(c)` has code `c + 2`. -/

/-- `UserError(c)` (`difftest/.../UserFns.scala:6`). -/
def userErr (c : Nat) : Err := { code := c + 2 }

/-- `TypeError` (`difftest/.../UserFns.scala:9`): a value of the wrong shape. -/
def typeErr : Err := { code := 0 }

/-- A harness error: the translation reached a construct that the Lean model cannot express
yet (see `wiki/methodology/difftest-program-format.md`, "Lean side"). It never occurs in Scala. -/
def harnessErr : Err := { code := 1 }

/-- The `UserError` code of an error, if it is a `UserError`. -/
def userCode? (e : Err) : Option Nat :=
  if e.kind = .nonFatal ∧ e.code ≥ 2 then some (e.code - 2) else none

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

/-- A program (format v0). Binders: `bind.k`, `handleErrorWith.k`, `guaranteeCase.fin`,
`case.lk`, `case.rk` bind one value; `uncancelable.body` binds one poll; `split.k` binds two
values (`b` is index 0, `a` is index 1). -/
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
  deriving DecidableEq, Repr

/-- Number of nodes. Nodes are numbered in pre-order from 0; the children of a node with
number `n` are `n + 1` and `n + 1 + size first`. -/
def Prog.size : Prog → Nat
  | .bind e k | .seq e k | .handleErrorWith e k | .onCancel e k _ | .guaranteeCase e k _
  | .racePair e k | .case _ e k => 1 + e.size + k.size
  | .map e _ | .attempt e | .uncancelable e | .poll _ e | .start e | .asyncFin _ e _
  | .split _ e => 1 + e.size
  | _ => 1

/-- The node with pre-order number `i`. -/
def Prog.at? : Prog → Nat → Option Prog
  | p, 0 => some p
  | p, i + 1 =>
    match p with
    | .bind e k | .seq e k | .handleErrorWith e k | .onCancel e k _ | .guaranteeCase e k _
    | .racePair e k | .case _ e k => if i < e.size then e.at? i else k.at? (i - e.size)
    | .map e _ | .attempt e | .uncancelable e | .poll _ e | .start e | .asyncFin _ e _
    | .split _ e => e.at? i
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

/-- All op names that occur in the program (pre-order, with repeats). -/
def Prog.ops (p : Prog) : List String :=
  p.opName :: match p with
    | .bind e k | .seq e k | .handleErrorWith e k | .onCancel e k _ | .guaranteeCase e k _
    | .racePair e k | .case _ e k => e.ops ++ k.ops
    | .map e _ | .attempt e | .uncancelable e | .poll _ e | .start e | .asyncFin _ e _
    | .split _ e => e.ops
    | _ => []

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
  id : String
  mode : Mode
  prog : Prog
  maxSteps : Nat
  deriving Repr

/-- `Json.FormatVersion` in `Json.scala`. -/
def formatVersion : Nat := 0
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
  | "fiber" | "ref" | "deferred" => fail s!"value '{t}': handles cannot be literals"
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

/-- Decode a program (`Json.prog`). -/
partial def decodeProgIn (j : Json) (scope : Scope) : D Prog := do
  let o ← obj j "prog"
  let op ← str (← field o "op" "prog") "prog.op"
  let ctx := s!"op '{op}'"
  let only (ks : List String) : D Unit := keys o ("op" :: ks) ctx
  let p (k : String) (s : Scope := scope) : D Prog := do decodeProgIn (← field o k ctx) s
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
        let first ← decodeProgIn q scope
        qs.foldlM (fun acc r => do pure (Prog.seq acc (← decodeProgIn r scope))) first
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
    | some f => pure (.asyncFin cbs (← decodeProgIn f scope) (← tag))
    | none => pure (.async cbs (← tag))
  | "case" =>
    only ["on", "l", "lk", "r", "rk"]; let l ← s "l"; let r ← s "r"
    pure (.case (← a "on") (← p "lk" ((l, .v) :: scope)) (← p "rk" ((r, .v) :: scope)))
  | "split" =>
    only ["on", "a", "b", "k"]; let x ← s "a"; let y ← s "b"
    pure (.split (← a "on") (← p "k" ((y, .v) :: (x, .v) :: scope)))
  | _ => fail s!"unknown op '{op}'"

/-- Decode a closed program. -/
def decodeProg (j : Json) : D Prog := decodeProgIn j []

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
  keys o ["v", "id", "mode", "choices", "seed", "maxSteps", "prog"] "case"
  let v ← nat (← field o "v" "case") "case.v"
  if v ≠ formatVersion then fail s!"case.v: unsupported format version {v}"
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
  pure { id, mode, prog := ← decodeProg (← field o "prog" "case"), maxSteps }

end Difftest

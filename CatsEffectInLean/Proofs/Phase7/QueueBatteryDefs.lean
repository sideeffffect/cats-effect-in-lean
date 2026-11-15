import CatsEffectInLean.Props.Phase7.Queue

/-!
# The wrong-function battery of decision 63 for `Queue` (definitions)

For each public operation (`offer`, `tryOffer`, `take`, `tryTake`, `size`) and each variant
(`raises`, `hangs`, `drops`, `doubles`), `battery op var` is `henv` with that operation broken: the
`IO` that the method returns is replaced. This is a wrong implementation of the method itself (a
method is the `IO` it returns); the harness records results as before.

* `raises`: `IO.raiseError(E77)` (non-fatal).
* `hangs`: an `IOCont` whose callback is never called (`IO.never` without a finalizer).
* `drops`: the method returns without its effect: `offer` returns `()`, `tryOffer` returns `true`,
  `take` returns `0` (an element that was never offered), `tryTake` returns `None`; nothing is
  added or removed.
* `doubles`: the effect twice: `offer(x) *> offer(x)`, `tryOffer(x) *> tryOffer(x)`,
  `take <* take`, `tryTake <* tryTake` (the first result is returned for the removals).
* `size` `drops` and `doubles` are meaningless: `size` only reads; there is no effect to skip,
  and two reads give the same value as one.

The wrong closures (`hangs`, `doubles`) live in namespace 59, answered by the wrong environment.
`Proofs/Phase7/QueueBatteryConc.lean` and `QueueBatteryAsync.lean` hold the kernel-checked
breaks.
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

inductive OpK where
  | offer | tryOffer | take | tryTake | size
  deriving DecidableEq, Repr

inductive Var where
  | raises | hangs | drops | doubles
  deriving DecidableEq, Repr

def OpK.code : OpK → Nat
  | .offer => 0 | .tryOffer => 1 | .take => 2 | .tryTake => 3 | .size => 4

/-- Wrong closures (namespace 59): 0 = never body; 1 = `_ => real(op)`; 2 = `a => real(op).as(a)`;
3 = `_ => a`. -/
def wns : Nat := 59
def wId (tag : Nat) (fs : List Val) : Nat := 2 * valToNat (cloVal wns tag fs) + 1

/-- The real program of an operation on queue `o` (element `x` for the offers). -/
def realIO (op : OpK) (o : Nat) (x : Val) : IO :=
  match op with
  | .offer => offerIO o x
  | .tryOffer => tryOfferIO o x
  | .take => takeIO o
  | .tryTake => tryTakeIO o
  | .size => sizeIO o

def opOfCode : Nat → Option OpK
  | 0 => some .offer | 1 => some .tryOffer | 2 => some .take | 3 => some .tryTake | 4 => some .size
  | _ => none

/-- The wrong program of `op` with variant `var`. -/
def wrongIO (op : OpK) (var : Var) (o : Nat) (x : Val) : IO :=
  match var, op with
  | .raises, _ => .error { code := 77 }
  | .hangs, _ => .ioCont (.user (wId 0 []))
  | .drops, .offer => .pure .unit
  | .drops, .tryOffer => .pure (.bool true)
  | .drops, .take => .pure (.nat 0)
  | .drops, .tryTake => .pure .none
  | .drops, .size => realIO .size o x
  | .doubles, .offer | .doubles, .tryOffer => .flatMap (realIO op o x) (.user (wId 1 [.nat op.code, .fn o, x]))
  | .doubles, .take | .doubles, .tryTake => .flatMap (realIO op o x) (.user (wId 2 [.nat op.code, .fn o, x]))
  | .doubles, .size => realIO .size o x

/-- The wrong closures. -/
def wCall (id : Nat) (arg : Val) : Option UserResult :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (59, 0, []) =>
      match arg with
      | .cont s => some { out := .prog (.contGet s) }
      | _ => none
    | some (59, 1, [.nat c, .fn o, x]) => (opOfCode c).map fun op => { out := .prog (realIO op o x) }
    | some (59, 2, [.nat c, .fn o, x]) =>
      (opOfCode c).map fun op => { out := .prog (.map (realIO op o x) (.user (wId 3 [arg]))) }
    | some (59, 3, [a]) => some { out := .ret a }
    | _ => none
  else none

/-- The harness with operation `op` broken by variant `var`. -/
def battery (op : OpK) (var : Var) : UserEnv :=
  let f (id : Nat) (arg : Val) (v : View) : UserResult :=
    match wCall id arg with
    | some r => r
    | none =>
      match QH.ofId? id, arg with
      | some (.offerPoll o i x m p), _ =>
        if op = .offer then { out := .prog (.map (IO.applyPoll (wrongIO op var o x) m p) (QH.recC i evOffered x).fn) }
        else henv.callV id arg v
      | some (.opBody o i opv), .poll m p =>
        match Op.ofVal? opv, op with
        | some (.tryOffer x), .tryOffer =>
          { out := .prog (.map (IO.applyPoll (wrongIO op var o x) m p) (QH.recTO i x).fn) }
        | some .take, .take => { out := .prog (.map (IO.applyPoll (wrongIO op var o .unit) m p) (QH.recK i evTook).fn) }
        | some .tryTake, .tryTake =>
          { out := .prog (.map (IO.applyPoll (wrongIO op var o .unit) m p) (QH.recK i evTryTook).fn) }
        | some .size, .size => { out := .prog (.map (IO.applyPoll (wrongIO op var o .unit) m p) (QH.recK i evSize).fn) }
        | _, _ => henv.callV id arg v
      | _, _ => henv.callV id arg v
  { call := fun id arg refs => f id arg { refs }, callV := f }

/-- The input of each operation (one fiber): every claim of `SeqSpec` is visible in the trace. -/
def inputOf : OpK → List Op
  | .offer => [.offer (.nat 1), .size]
  | .tryOffer => [.tryOffer (.nat 1), .size]
  | .take => [.offer (.nat 1), .offer (.nat 2), .take, .size]
  | .tryTake => [.offer (.nat 1), .offer (.nat 2), .tryTake, .size]
  | .size => [.offer (.nat 1), .size]

/-- `SeqSpec` as a `Bool` for one observation. -/
def specB (k : QKind) (s : List Op) (o : Obs) : Bool :=
  let t := specRun (ruleOf k) [] s
  events o.out == t.1 && o.summary == (if t.2 then .blocked else .done (.succeeded .unit))

/-- One FIFO-schedule run of input `inputOf op` on kind `k` with environment `e`. -/
def runOp (e : UserEnv) (k : QKind) (op : OpK) : Option Obs :=
  runObsP {} counterMaskModel e 3000 [] (rootIO k [inputOf op] [] (.join [0]))

/-- The claim of `SeqSpec` on that run. -/
def specOK (e : UserEnv) (k : QKind) (op : OpK) : Option Bool := (runOp e k op).map (specB k (inputOf op))

end CatsEffectInLean.Proofs.Phase7.QueueBattery

import CatsEffectInLean.Model.ParTraverse
import CatsEffectInLean.Model.WellFormed
import CatsEffectInLean.Model.Outcomes

/-!
# `parTraverseN`: result order, success, error and cancel propagation (Phase 6, batch 6.3)

Model: `CatsEffectInLean/Model/ParTraverse.lean`, the kernel default
`GenConcurrent#parTraverseN` (`kernel/shared/src/main/scala/cats/effect/kernel/GenConcurrent.scala:145-249`)
with the `IO` operations; `IO.parTraverseN` (`core/shared/src/main/scala/cats/effect/IO.scala:1593-1594`)
calls it. Scaladoc (`GenConcurrent.scala:132-144`): "The first n actions will be started first,
with subsequent actions starting in order as each one completes. ... Any errors or
self-cancelation will immediately abort the sequence. ... If all actions succeed, their results
are returned in the same order as their corresponding inputs, regardless of the order in which
they executed."

All statements quantify over all user code `u` (even ids), all limits `n ≥ 1` (`require`,
`GenConcurrent.scala:146`), all fuel values and all `PChoice` schedules (`outcomesP`, preemption
at any run-loop iteration). They state outcomes and result values only, so they need no test
marker (decision 56). Hypotheses:

* `WellFormed` of the program (decision 27): user code is code Scala can write; library
  closures (`ptIsLib`: the `Bracket`, `Race`, `Timeout` and `ParTraverse` mirrors) may occur in
  user programs.
* The model limit `as.length ≤ 4`: Scala keeps the supervision `Set` as `Set1`..`Set4` (insertion
  order) up to 4 elements and as a `HashSet` (identity-hash order) above; the model mirrors only
  the first (`ParTraverse.setLimitCode`). This is a limit of the mirror, stated, not hidden.
* Statements 2-4 fix the behaviour of `f` (an ordinary input for each claim).

## Statements

1. `parTraverseNOrder`: if the traversal succeeds, its result holds one entry per input, in input
   order: `f` is wrapped by the harness as `a => f(a).map(b => (a, b))`, and the first
   components of the result are exactly the inputs (no lost, no duplicated, no reordered entry).
2. `parTraverseNPureSucceeds`: if `f(a) = IO.pure(g(a))`, every run that stops ends `Succeeded`
   with `as.map(g)`: no deadlock, no error, the right order.
3. `parTraverseNErrorAborts`: if `f(a0)` raises `e` and every other `f(a)` never completes, and
   `a0` is among the first `n` inputs (so it gets a permit), every run that stops ends
   `Errored(e)`: the error cancels the other actions, nothing hangs.
4. `parTraverseNCancelAborts`: the same with `f(a0) = IO.canceled`: every run that stops ends
   `Canceled`.
-/

namespace CatsEffectInLean.Props.Phase6.ParTraverse

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.ParTraverse

/-- Library closures that user programs may contain (`WellFormed`). -/
def ptIsLib (id : Nat) : Bool :=
  Bracket.isLib id || (Race.ofId? id).isSome || (PT.ofId? id).isSome ||
    (isLibId id &&
      match (cloOfId id).bind ofCloVal with
      | some (k, tag, fs) => k == Timeout.ns && (Timeout.TLam.ofFields tag fs).isSome
      | none => false)

/-! ## The tagging harness of statement 1 (namespace 42) -/

def tns : Nat := 42

/-- `a => f(a).map(b => (a, b))` and its `map` function. -/
inductive TL where
  | tag (f : Nat)
  | pairWith (a : Val)
  deriving DecidableEq, Repr

def TL.toVal : TL → Val
  | .tag f => cloVal tns 0 [.nat f]
  | .pairWith a => cloVal tns 1 [a]

def TL.id (l : TL) : Nat := 2 * valToNat l.toVal + 1

def TL.ofId? (id : Nat) : Option TL :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (42, 0, [.nat f]) => some (.tag f)
    | some (42, 1, [a]) => some (.pairWith a)
    | _ => none
  else none

/-- User code `u` with the tagging closures. -/
def tagged (u : UserEnv) : UserEnv where
  call id a refs := u.call id a refs
  callV id a v :=
    match TL.ofId? id with
    | some (.tag f) =>
      let r := u.callV f a v
      match r.out with
      | .prog p => { effects := r.effects, out := .prog (.map p (.user (TL.pairWith a).id)) }
      | .throw e => { effects := r.effects, out := .throw e }
      | .ret _ => { out := .throw { code := illCode, kind := .fatal } }
    | some (.pairWith a0) => { out := .ret (.pair a0 a) }
    | none => u.callV id a v

/-- The first component of a pair. -/
def fstOf : Val → Val
  | .pair a _ => a
  | v => v

/-- Statement 1: the result holds one entry per input, in input order. -/
def parTraverseNOrder : Prop :=
  ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat),
    1 ≤ n → as.length ≤ 4 → f % 2 = 0 →
    WellFormed ptIsLib [] (env (tagged u)) (parTraverseNIO n as (TL.tag f).id) →
    ∀ o, outcomesP {} counterMaskModel (env (tagged u)) (parTraverseNIO n as (TL.tag f).id) o →
      ∀ v, o.summary = .done (.succeeded v) → (unlistV v).map (·.map fstOf) = some as

/-- Statement 2: a pure `f` gives `Succeeded(as.map(g))` in every run that stops. -/
def parTraverseNPureSucceeds : Prop :=
  ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (g : Val → Val),
    1 ≤ n → as.length ≤ 4 → f % 2 = 0 →
    (∀ a v, u.callV f a v = { out := .prog (.pure (g a)) }) →
    WellFormed ptIsLib [] (env u) (parTraverseNIO n as f) →
    ∀ o, outcomesP {} counterMaskModel (env u) (parTraverseNIO n as f) o →
      o.summary = .done (.succeeded (listV (as.map g)))

/-- Statement 3: an error of one started action aborts the traversal with that error. -/
def parTraverseNErrorAborts : Prop :=
  ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (a0 : Val) (e : Err),
    1 ≤ n → as.length ≤ 4 → f % 2 = 0 → a0 ∈ as.take n → e.kind = .nonFatal →
    (∀ a v, u.callV f a v = { out := .prog (if a = a0 then .error e else Timeout.neverIO) }) →
    WellFormed ptIsLib [] (env u) (parTraverseNIO n as f) →
    ∀ o, outcomesP {} counterMaskModel (env u) (parTraverseNIO n as f) o →
      o.summary = .done (.errored e)

/-- Statement 4: a self-cancel of one started action aborts the traversal as `Canceled`. -/
def parTraverseNCancelAborts : Prop :=
  ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (a0 : Val),
    1 ≤ n → as.length ≤ 4 → f % 2 = 0 → a0 ∈ as.take n →
    (∀ a v, u.callV f a v = { out := .prog (if a = a0 then .canceled else Timeout.neverIO) }) →
    WellFormed ptIsLib [] (env u) (parTraverseNIO n as f) →
    ∀ o, outcomesP {} counterMaskModel (env u) (parTraverseNIO n as f) o →
      o.summary = .done .canceled

end CatsEffectInLean.Props.Phase6.ParTraverse

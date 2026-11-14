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

All statements quantify over all input lists (any length), all limits `n ≥ 1` (`require`,
`GenConcurrent.scala:146`), all fuel values, all `PChoice` schedules (`outcomesP`, preemption
at any run-loop iteration) and all `HashSet` iteration orders `ord` (the supervision `Set` is a
`HashSet` from 5 elements; its order comes from identity hashes, so the model takes any
permutation, `(ord xs).Perm xs`). They state outcomes and result values only, so they need no
test marker (decision 56). Hypotheses:

* `WellFormed` of the program (decision 27, statements 1-4): user code is code Scala can write;
  library closures (`ptIsLib`: the `Bracket`, `Race`, `Timeout` and `ParTraverse` mirrors) may
  occur in user programs.
* Statements 2-7 fix the behaviour of `f` (an ordinary input for each claim).

## Statements

1. `parTraverseNOrder`: if the traversal succeeds, its result holds one entry per input, in input
   order: `f` is wrapped by the harness as `a => f(a).map(b => (a, b))`, and the first
   components of the result are exactly the inputs (no lost, no duplicated, no reordered entry).
   Review 7: believed false as stated, because `WellFormed` lets `f` reach the per-input result
   `Deferred` through a number field of its closure id. It waits for track Res's `WellFormed`
   fix (decision 56); the statement is not changed here.
2. `parTraverseNPureSucceeds`: if `f(a) = IO.pure(g(a))`, every run that stops ends `Succeeded`
   with `as.map(g)`: no deadlock, no error, the right order.
3. `parTraverseNErrorAborts`: if `f(a0)` raises `e` and every other `f(a)` never completes, and
   `a0` is among the first `n` inputs (so it gets a permit), every run that stops ends
   `Errored(e)`: the error cancels the other actions, nothing hangs.
4. `parTraverseNCancelAborts`: the same with `f(a0) = IO.canceled`: every run that stops ends
   `Canceled`.

Statements 5-7 give `f` by a behaviour table `bh : Val → Nat × Base` (harness, namespace 43):
`f(a)` is `IO.cede` `k` times, then the base action of `bh a`: `IO.pure(v)`, `IO.raiseError(e)`,
`IO.canceled` or `IO.never`. This is Scala code (`a => IO.cede.replicateA_(k) *> base(a)`) that
holds no handle, so these statements need no `WellFormed` hypothesis. The table covers siblings
that complete, actions that suspend before they finish, an error in an action that starts later
than the first `n`, and two errors at once.

5. `parTraverseNSucceedsGen`: if every base is `pure`, every run that stops ends `Succeeded` with
   the values in input order.
6. `parTraverseNErrorAbortsGen`: no base is `canceled`, every raised error is non-fatal, and some
   input `a_i` raises while fewer than `n` inputs before it never complete (so `a_i` gets a
   permit): every run that stops ends `Errored(e)` with an `e` that one of the inputs raises.
7. `parTraverseNCancelAbortsGen`: the same with `canceled` in place of the error and no error:
   every run that stops ends `Canceled`.
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
  ∀ (ord : List Val → List Val), (∀ xs, (ord xs).Perm xs) → ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat),
    1 ≤ n → f % 2 = 0 →
    WellFormed ptIsLib [] (env ord (tagged u)) (parTraverseNIO n as (TL.tag f).id) →
    ∀ o, outcomesP {} counterMaskModel (env ord (tagged u)) (parTraverseNIO n as (TL.tag f).id) o →
      ∀ v, o.summary = .done (.succeeded v) → (unlistV v).map (·.map fstOf) = some as

/-- Statement 2: a pure `f` gives `Succeeded(as.map(g))` in every run that stops. -/
def parTraverseNPureSucceeds : Prop :=
  ∀ (ord : List Val → List Val), (∀ xs, (ord xs).Perm xs) → ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (g : Val → Val),
    1 ≤ n → f % 2 = 0 →
    (∀ a v, u.callV f a v = { out := .prog (.pure (g a)) }) →
    WellFormed ptIsLib [] (env ord u) (parTraverseNIO n as f) →
    ∀ o, outcomesP {} counterMaskModel (env ord u) (parTraverseNIO n as f) o →
      o.summary = .done (.succeeded (listV (as.map g)))

/-- Statement 3: an error of one started action aborts the traversal with that error. -/
def parTraverseNErrorAborts : Prop :=
  ∀ (ord : List Val → List Val), (∀ xs, (ord xs).Perm xs) → ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (a0 : Val) (e : Err),
    1 ≤ n → f % 2 = 0 → a0 ∈ as.take n → e.kind = .nonFatal →
    (∀ a v, u.callV f a v = { out := .prog (if a = a0 then .error e else Timeout.neverIO) }) →
    WellFormed ptIsLib [] (env ord u) (parTraverseNIO n as f) →
    ∀ o, outcomesP {} counterMaskModel (env ord u) (parTraverseNIO n as f) o →
      o.summary = .done (.errored e)

/-- Statement 4: a self-cancel of one started action aborts the traversal as `Canceled`. -/
def parTraverseNCancelAborts : Prop :=
  ∀ (ord : List Val → List Val), (∀ xs, (ord xs).Perm xs) → ∀ (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (a0 : Val),
    1 ≤ n → f % 2 = 0 → a0 ∈ as.take n →
    (∀ a v, u.callV f a v = { out := .prog (if a = a0 then .canceled else Timeout.neverIO) }) →
    WellFormed ptIsLib [] (env ord u) (parTraverseNIO n as f) →
    ∀ o, outcomesP {} counterMaskModel (env ord u) (parTraverseNIO n as f) o →
      o.summary = .done .canceled

/-! ## The behaviour harness of statements 5-7 (namespace 43) -/

def bns : Nat := 43

/-- The last action of `f(a)`. -/
inductive Base where
  | ok (v : Val)
  | err (e : Err)
  | canc
  | never
  deriving DecidableEq, Repr

def Base.io : Base → IO
  | .ok v => .pure v
  | .err e => .error e
  | .canc => .canceled
  | .never => Timeout.neverIO

/-- `body`: `f` itself; `step a k`: the rest of `f(a)` after a `cede`, with `k` cedes left. -/
inductive BL where
  | body
  | step (a : Val) (k : Nat)
  deriving DecidableEq, Repr

def BL.toVal : BL → Val
  | .body => cloVal bns 0 []
  | .step a k => cloVal bns 1 [a, .nat k]

def BL.id (l : BL) : Nat := 2 * valToNat l.toVal + 1

def BL.ofId? (id : Nat) : Option BL :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (43, 0, []) => some .body
    | some (43, 1, [a, .nat k]) => some (.step a k)
    | _ => none
  else none

/-- `IO.cede` `k` times, then the base action of `a`. -/
def stepIO (bh : Val → Nat × Base) (a : Val) : Nat → IO
  | 0 => (bh a).2.io
  | k + 1 => .flatMap .cede (.user (BL.step a k).id)

def behCall (bh : Val → Nat × Base) (id : Nat) (a : Val) : UserResult :=
  match BL.ofId? id with
  | some .body => { out := .prog (stepIO bh a (bh a).1) }
  | some (.step a0 k) => { out := .prog (stepIO bh a0 k) }
  | none => { out := .throw { code := illCode, kind := .fatal } }

/-- `f = a => IO.cede.replicateA_((bh a)._1) *> base(bh a)._2`, and no other user code. -/
def behaved (bh : Val → Nat × Base) : UserEnv where
  call id a _ := behCall bh id a

/-- The value of an `ok` base. -/
def Base.okVal : Base → Val
  | .ok v => v
  | _ => .unit

/-- The number of inputs that never complete. -/
def nevers (bh : Val → Nat × Base) (as : List Val) : Nat :=
  (as.filter fun a => (bh a).2 == .never).length

/-- Statement 5: if every action succeeds, the results come back in input order. -/
def parTraverseNSucceedsGen : Prop :=
  ∀ (ord : List Val → List Val), (∀ xs, (ord xs).Perm xs) →
  ∀ (n : Nat) (as : List Val) (bh : Val → Nat × Base),
    1 ≤ n → (∀ a ∈ as, ∃ v, (bh a).2 = .ok v) →
    ∀ o, outcomesP {} counterMaskModel (env ord (behaved bh)) (parTraverseNIO n as BL.body.id) o →
      o.summary = .done (.succeeded (listV (as.map fun a => (bh a).2.okVal)))

/-- Statement 6: an error of an action that gets a permit aborts the traversal with an error
that one of the actions raised. -/
def parTraverseNErrorAbortsGen : Prop :=
  ∀ (ord : List Val → List Val), (∀ xs, (ord xs).Perm xs) →
  ∀ (n : Nat) (as : List Val) (bh : Val → Nat × Base),
    1 ≤ n → (∀ a ∈ as, (bh a).2 ≠ .canc) →
    (∀ a ∈ as, ∀ e, (bh a).2 = .err e → e.kind = .nonFatal) →
    (∃ i, ∃ h : i < as.length, (∃ e, (bh as[i]).2 = .err e) ∧ nevers bh (as.take i) < n) →
    ∀ o, outcomesP {} counterMaskModel (env ord (behaved bh)) (parTraverseNIO n as BL.body.id) o →
      ∃ a ∈ as, ∃ e, (bh a).2 = .err e ∧ o.summary = .done (.errored e)

/-- Statement 7: a self-cancel of an action that gets a permit aborts the traversal as
`Canceled`. -/
def parTraverseNCancelAbortsGen : Prop :=
  ∀ (ord : List Val → List Val), (∀ xs, (ord xs).Perm xs) →
  ∀ (n : Nat) (as : List Val) (bh : Val → Nat × Base),
    1 ≤ n → (∀ a ∈ as, ∀ e, (bh a).2 ≠ .err e) →
    (∃ i, ∃ h : i < as.length, (bh as[i]).2 = .canc ∧ nevers bh (as.take i) < n) →
    ∀ o, outcomesP {} counterMaskModel (env ord (behaved bh)) (parTraverseNIO n as BL.body.id) o →
      o.summary = .done .canceled

end CatsEffectInLean.Props.Phase6.ParTraverse

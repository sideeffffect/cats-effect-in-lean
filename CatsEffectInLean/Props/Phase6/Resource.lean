import CatsEffectInLean.Model.ResourceUse
import CatsEffectInLean.Props.Phase6.HarnessPrivacy

/-!
# `Resource`: `use`, `both`, `flatMap` finalizer order, the cancelable direction of CE-0002 (Phase 6, track Res)

Model: `CatsEffectInLean/Model/ResourceUse.lean` (mirror of `Resource#fold`/`use`
`Resource.scala:156-208`, `allocated` `:550-552`, the application of `rel2` `:490`, `both`
`:286-314`), on the Phase 5 mirror `Model/Resource.lean` (`allocatedCase` `:464-531`), the
`IO.bracketFull`/`IO#guarantee` mirror of track G and the `GenSpawn#both` mirror of track R.
`Resource.scala` = `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala` at `v3.7.1`.

All statements run on the scheduler with preemption at any run-loop iteration (`outcomesP`,
`EqvP`; `Model/Outcomes.lean`), default `Config`, `counterMaskModel`. They quantify over all
`UEnv` (user code at the `Resource` level and the meaning of `Res` codes), all user functions
and all schedules.

## The test harness (decision 56, `Props/Phase6/HarnessPrivacy.lean`)

* The root program is the harness: it first allocates the log cell (`Ref` 0, the token; the heap
  is empty at the start, so no other cell can get id 0), then runs the test body. The harness
  closures (`HLam`, namespace 21) are library closures of the statement's `Lib` (`libH`), except
  the event closures `markA`, `markT`, which capture the token and are in no `Lib`.
* A resource under test is a marked `make` (`MarkedMake`): acquire is `a0.flatMap(markA tag)`
  (appends `tag` to the log when acquire completes, inside the mask of `Allocate`), release is
  `IO.delay(markT tag) *> q(..)` (appends `tag` when release starts). The acquire and release
  codes and the resource code are token names.
* User code cannot name a token (`Private`: every user result, `Bind` result, other acquire or
  release program and other resource is token-free; no escape clause). With `WellFormed` (deep
  `captured`, `Lib.fields`) this makes every log entry come from a harness position, for every
  user code and schedule (module doc of `HarnessPrivacy`).
* The parent fiber of decision 50: `withParent` (`HLam.cancelJoin`).
* Each statement has a Lean satisfiability witness (decision 53): `Proofs/Phase6/ResourceWitness.lean`
  (with and without the parent); the CE-0020 refutation is the one of statement 1.

## Statements

1. `bothReleasesBoth` (source (b); Scaladoc `Resource.scala:248-257`): `Resource.both(A, B).use(f)`.
   In every run that ends with a root outcome, each release tag is in the log as often as its
   acquire tag. Refuted: CE-0020. `BothReleasesBothFor impl` is the same statement for another
   `both` (the fixed-twin check uses `fixedBothRes`).
2. `useReleaseOnce` (source (b), decision 50): `make(acq)(rel).use(f)`, directly or under the
   parent. Release runs exactly once iff acquire completed.
3. `flatMapReleaseOrder`: `make(A).flatMap(_ => make(B)).use(f)`: each release iff its acquire,
   and `B` is released before `A` (LIFO).
4. `resourceEvalPreservesCancelable` (decision 41): if masking `fa` changes it, masking
   `Resource.eval(fa).allocatedCase` changes it too.
-/

namespace CatsEffectInLean.Props.Phase6.Resource

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.HarnessPrivacy

/-- `r.use(f)` built when the body runs (view `{}`: the resources of the statements start with
`Allocate`, so no user function is called when the term is built). -/
def useOf (U : UEnv) (f : Nat) (r : Res) : IO :=
  match (useIO U U.userCall f r {}).2 with
  | .ok p => p
  | .error e => .error e

/-! ## The harness -/

/-- The namespace of the harness closures (track Res: namespaces 20-29). -/
def hns : Nat := 21

/-- The log cell (the token): `Ref` 0. -/
def logCell : Nat := 0

/-- The tokens of the statements. -/
def toks : List Handle := [.ref logCell]

/-- The harness lambdas (test harness, not user code, not Cats Effect code). -/
inductive HLam where
  /-- The thunk `Ref.unsafe(Nil)`: the log cell. -/
  | newCells
  /-- `_ => body`: the test body. -/
  | afterCells
  /-- `x => { log :+= tag; IO.pure(x) }` (acquire completed). Captures the log cell. -/
  | markA (c : Nat) (tag : Val)
  /-- The thunk `log :+= tag` (release started). Captures the log cell. -/
  | markT (c : Nat) (tag : Val)
  /-- `f => f.cancel.flatMap(_ => f.join)`. -/
  | cancelJoin
  /-- `_ => f.join`. -/
  | thenJoin (f : Nat)
  deriving DecidableEq, Repr

def HLam.toVal : HLam → Val
  | .newCells => cloVal hns 0 []
  | .afterCells => cloVal hns 1 []
  | .markA c tag => cloVal hns 2 [.ref c, tag]
  | .markT c tag => cloVal hns 3 [.ref c, tag]
  | .cancelJoin => cloVal hns 4 []
  | .thenJoin f => cloVal hns 5 [.fiber f]

def HLam.ofFields : Nat → List Val → Option HLam
  | 0, [] => some .newCells
  | 1, [] => some .afterCells
  | 2, [.ref c, tag] => some (.markA c tag)
  | 3, [.ref c, tag] => some (.markT c tag)
  | 4, [] => some .cancelJoin
  | 5, [.fiber f] => some (.thenJoin f)
  | _, _ => none

def HLam.id (l : HLam) : Nat := 2 * valToNat l.toVal + 1

def HLam.fn (l : HLam) : Fn := .user l.id

def HLam.ofId? (id : Nat) : Option HLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == hns then HLam.ofFields tag fs else none
    | none => none
  else none

/-- Append `tag` to log cell `c` (one atomic step, a `SyncRef.update` in Scala). -/
def append (c : Nat) (tag : Val) (v : View) : UserEffect :=
  .writeRef c (listV (((unlistV (v.refs.getD c .unit)).getD []) ++ [tag]))

/-- Run a harness lambda; `body` is the test body. -/
def HLam.call (body : IO) (l : HLam) (arg : Val) (v : View) : UserResult :=
  match l, arg with
  | .newCells, _ => { effects := [.allocRef (listV [])], out := .ret (.ref v.refs.length) }
  | .afterCells, _ => { out := .prog body }
  | .markA c tag, x => { effects := [append c tag v], out := .prog (.pure x) }
  | .markT c tag, _ => { effects := [append c tag v], out := .ret .unit }
  | .cancelJoin, .fiber f => { out := .prog (.flatMap (IO.cancelOf f (v.outcome f)) (HLam.thenJoin f).fn) }
  | .thenJoin f, _ => { out := .prog (IO.joinOf f (v.outcome f)) }
  | _, _ => { out := .throw { code := 999999, kind := .fatal } }

/-- The environment of a test: the harness lambdas, then `U.toEnv`. -/
def envH (U : UEnv) (body : IO) : UserEnv where
  call id arg refs := match HLam.ofId? id with
    | some l => l.call body arg { refs }
    | none => U.toEnv.call id arg refs
  callV id arg v := match HLam.ofId? id with
    | some l => l.call body arg v
    | none => U.toEnv.callV id arg v

/-- The harness closures that a program may name: not the event closures. -/
def HLam.public : HLam → Bool
  | .markA _ _ | .markT _ _ => false
  | _ => true

/-- The `Lib` of a test program: the `Resource` mirror (with its function fields) and the public
harness closures. -/
def libH : Lib :=
  { ok := fun id => ResourceUse.isLib id || ((HLam.ofId? id).map HLam.public).getD false,
    fields := ResourceUse.fnFields }

/-- The root program: allocate the log cell, then run the body. -/
def harness : IO := .flatMap (.delay HLam.newCells.fn) HLam.afterCells.fn

/-- The test body: `p`, or `p.start.flatMap(f => f.cancel.flatMap(_ => f.join))`. -/
def withParent (viaParent : Bool) (p : IO) : IO :=
  if viaParent then .flatMap (.start p) HLam.cancelJoin.fn else p

/-- The log at the end of a run (oldest first). -/
def logOf (o : Obs) : List Val := (unlistV (o.refs.getD logCell .unit)).getD []

/-- The tags. -/
def tagA : Val := .nat 1
def tagB : Val := .nat 2
def tagRA : Val := .nat 3
def tagRB : Val := .nat 4

/-! ## Hypotheses -/

/-- A resource `Res` is token-free. -/
def tokFreeRes (toks : List Handle) : Res → Bool
  | .allocate (.user k) => tokFreeV toks (.nat k)
  | .allocate (.make a r) => tokFreeV toks (.nat a) && tokFreeV toks (.nat r)
  | .bind s f => tokFreeRes toks s && tokFreeV toks (.nat f)
  | .pure v => tokFreeV toks v
  | .eval fa => tokFreeIO toks fa

/-- A marked `make` with code `c`: `make(a0.flatMap(markA tA))(_ => IO.delay(markT tR) *> q(..))`.
The codes are token names; `a0` is token-free user code; `q` is any user function. -/
def MarkedMake (U : UEnv) (c : Val) (acq rel : Nat) (a0 : IO) (tA tR : Val) : Prop :=
  U.resOf c = some (Res.make acq rel) ∧
    U.r.acquire acq = .flatMap a0 (HLam.markA logCell tA).fn ∧
    (∀ a, ∃ q, U.r.release rel a = .ok (.flatMap (.delay (HLam.markT logCell tR).fn) (uid q))) ∧
    tokFreeIO toks a0 = true ∧
    tokFreeV toks c = false ∧ tokFreeV toks (.nat acq) = false ∧ tokFreeV toks (.nat rel) = false

/-- User code cannot name a token (decision 56, `HarnessPrivacy`): user results (even ids), user
`Bind` results, other acquire and release programs, other resources are token-free. `acqs`,
`rels`, `ks`, `cs`: the harness codes. -/
def Private (U : UEnv) (acqs rels ks : List Nat) (cs : List Val) : Prop :=
  UserPrivate U.toEnv toks ∧
  (∀ k a r, k ∉ ks → U.r.bind k a = .ok r → tokFreeRes toks r = true) ∧
  (∀ k, k ∉ acqs → tokFreeIO toks (U.r.acquire k) = true) ∧
  (∀ k a q, k ∉ rels → U.r.release k a = .ok q → tokFreeIO toks q = true) ∧
  (∀ c r, c ∉ cs → U.resOf c = some r → tokFreeRes toks r = true)

/-! ## Statements -/

/-- 1, for an implementation `impl ca cb` of `Resource.both` (`Resource.scala:286-314`, Scaladoc
`:248-257`): `impl(A, B).use(f)` releases both sides. -/
def BothReleasesBothFor (impl : Val → Val → Res) : Prop :=
  ∀ (U : UEnv) (ca cb : Val) (acqA relA acqB relB : Nat) (a0 b0 : IO) (f : Nat) (viaParent : Bool),
    MarkedMake U ca acqA relA a0 tagA tagRA →
    MarkedMake U cb acqB relB b0 tagB tagRB →
    Private U [acqA, acqB] [relA, relB] [] [ca, cb] →
    WellFormed libH [] (envH U (withParent viaParent (useOf U f (impl ca cb)))) harness →
    ∀ o, outcomesP {} counterMaskModel (envH U (withParent viaParent (useOf U f (impl ca cb)))) harness o →
      (∃ oc, o.summary = .done oc) →
      (logOf o).count tagRA = (logOf o).count tagA ∧ (logOf o).count tagRB = (logOf o).count tagB

/-- 1. `Resource.both` releases both sides (v3.7.1 mirror). -/
def bothReleasesBoth : Prop := BothReleasesBothFor bothRes

/-- 2. `make(acq)(rel).use(f)` releases exactly once iff acquire completed
(`Resource.scala:156-208` with `IO.bracketFull`). -/
def useReleaseOnce : Prop :=
  ∀ (U : UEnv) (c : Val) (acq rel : Nat) (a0 : IO) (f : Nat) (viaParent : Bool),
    MarkedMake U c acq rel a0 tagA tagRA →
    Private U [acq] [rel] [] [c] →
    WellFormed libH [] (envH U (withParent viaParent (useOf U f (Res.make acq rel)))) harness →
    ∀ o, outcomesP {} counterMaskModel (envH U (withParent viaParent (useOf U f (Res.make acq rel)))) harness o →
      (∃ oc, o.summary = .done oc) → (logOf o).count tagRA = (logOf o).count tagA

/-- `x` comes before `y` in `l`. -/
def Before (l : List Val) (x y : Val) : Prop := l.idxOf x < l.idxOf y

/-- 3. `make(A).flatMap(_ => make(B)).use(f)`: each release iff its acquire, and `B` is released
before `A` (`Resource.scala:156-196`: nested `bracketFull`). `k` is the harness `flatMap` function
(`_ => make(B)`), a token name. -/
def flatMapReleaseOrder : Prop :=
  ∀ (U : UEnv) (ca cb : Val) (acqA relA acqB relB : Nat) (a0 b0 : IO) (f k : Nat) (viaParent : Bool),
    MarkedMake U ca acqA relA a0 tagA tagRA →
    MarkedMake U cb acqB relB b0 tagB tagRB →
    (∀ x, U.r.bind k x = .ok (Res.make acqB relB)) → tokFreeV toks (.nat k) = false →
    Private U [acqA, acqB] [relA, relB] [k] [ca, cb] →
    WellFormed libH [] (envH U (withParent viaParent (useOf U f ((Res.make acqA relA).flatMap k)))) harness →
    ∀ o, outcomesP {} counterMaskModel
        (envH U (withParent viaParent (useOf U f ((Res.make acqA relA).flatMap k)))) harness o →
      (∃ oc, o.summary = .done oc) →
      (logOf o).count tagRA = (logOf o).count tagA ∧ (logOf o).count tagRB = (logOf o).count tagB ∧
      (tagRA ∈ logOf o → tagRB ∈ logOf o → Before (logOf o) tagRB tagRA)

/-- 4. Decision 41, the cancelable direction of CE-0002 (`Resource.scala:986-993`: `eval`
"preserves interruptibility of `fa`"): if `fa` is cancelable (masking it changes some
observation), then `Resource.eval(fa).allocatedCase` is cancelable. `u1 = _ => fa`,
`u2 = _ => alloc` (`IOI.Lam.constProg`). -/
def resourceEvalPreservesCancelable : Prop :=
  ∀ (r : REnv) (u1 u2 : Nat) (fa alloc : IO),
    IOI.Lam.constProg r.user u1 fa →
    allocatedCase r (Res.evalOf fa) = .ok alloc →
    IOI.Lam.constProg r.user u2 alloc →
    r.WellFormed fa → r.WellFormed (IOI.uncancelable (uid u1)) →
    r.WellFormed alloc → r.WellFormed (IOI.uncancelable (uid u2)) →
    ¬ EqvP {} counterMaskModel r.toEnv fa (IOI.uncancelable (uid u1)) →
    ¬ EqvP {} counterMaskModel r.toEnv alloc (IOI.uncancelable (uid u2))

end CatsEffectInLean.Props.Phase6.Resource

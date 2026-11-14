import CatsEffectInLean.Model.ResourceUse
import CatsEffectInLean.Props.Phase6.HarnessNames

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

## The test harness (review batch 5, decisions 53-54)

* A resource under test is a marked `make` (`MarkedMake`): acquire is `a0.map(markA)`, release is
  `IO.delay(markR) *> q(..)`. `markA` emits `A`, `markR` emits `R`. Only these two user functions
  emit `A` and `R` (`EmitsOnly`).
* The names of the harness (`markA`, `markR` as program ids and `REnv` indices, the acquire and
  release codes, the resource code, a harness `Bind` code) form the list `bad`. User code never
  introduces such a name (`NoForge`, with the deep check of `HarnessNames`): a user result, a user
  `Bind` result, a user acquire or release program, a user resource mentions a harness name only
  if its argument does. So user code cannot run a marker in another position, also not through a
  library closure that forwards an id from its fields (the forgery of review batch 5:
  `.map (.pure ()) (ULam.allocFn (.user mR)).fn`). The library gives no harness name to user code
  in these programs: `f` gets the acquired value (`unit` from `markA`), `q` gets `unit`, the
  parent gets a fiber.
* The parent fiber of decision 50 is a harness closure (`HLam`, library namespace 21, so not user
  code): `b.start.flatMap(f => f.cancel.flatMap(_ => f.join))`.
* Each statement has a Lean satisfiability witness (decision 53) in
  `Proofs/Phase6/ResourceWitness.lean` (with and without the parent); the CE-0020 refutation is
  one for statement 1.

## Statements

1. `bothReleasesBoth` (source (b); Scaladoc `Resource.scala:248-257`): `Resource.both(A, B).use(f)`.
   In every run that ends with a root outcome, each release runs exactly as often as its acquire
   completed. Refuted: CE-0020. `BothReleasesBothFor impl` is the same statement for another
   `both` (the fixed twin check uses `fixedBothRes`).
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
open CatsEffectInLean.Props.Phase6.HarnessNames

/-- `r.use(f)` built at the root (view `{}`), `f` = program function `f`. The resources of the
statements start with `Allocate`, so no user function is called when the term is built. -/
def useOf (U : UEnv) (f : Nat) (r : Res) : IO :=
  match (useIO U U.userCall f r {}).2 with
  | .ok p => p
  | .error e => .error e

/-! ## The harness parent fiber (decision 50) -/

/-- The namespace of the harness closures (track Res: namespaces 20-29). -/
def hns : Nat := 21

/-- The parent lambdas (test harness, not user code, not Cats Effect code). -/
inductive HLam where
  /-- `f => f.cancel.flatMap(_ => f.join)`. -/
  | cancelJoin
  /-- `_ => f.join`. -/
  | thenJoin (f : Nat)
  deriving DecidableEq, Repr

def HLam.toVal : HLam → Val
  | .cancelJoin => cloVal hns 0 []
  | .thenJoin f => cloVal hns 1 [.fiber f]

def HLam.id (l : HLam) : Nat := 2 * valToNat l.toVal + 1

def HLam.fn (l : HLam) : Fn := .user l.id

def HLam.ofId? (id : Nat) : Option HLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, 0, []) => if k == hns then some .cancelJoin else none
    | some (k, 1, [.fiber f]) => if k == hns then some (.thenJoin f) else none
    | _ => none
  else none

/-- Run a parent lambda. `f.cancel`/`f.join` read `_cancel`/`_join` (`IO.cancelOf`, `IO.joinOf`). -/
def HLam.call (l : HLam) (arg : Val) (v : View) : UserResult :=
  match l, arg with
  | .cancelJoin, .fiber f => { out := .prog (.flatMap (IO.cancelOf f (v.outcome f)) (HLam.thenJoin f).fn) }
  | .thenJoin f, _ => { out := .prog (IO.joinOf f (v.outcome f)) }
  | _, _ => { out := .throw { code := 999999, kind := .fatal } }

/-- The environment of a test program: the parent lambdas, then `U.toEnv`. -/
def envH (U : UEnv) : UserEnv where
  call id arg refs := match HLam.ofId? id with
    | some l => l.call arg { refs }
    | none => U.toEnv.call id arg refs
  callV id arg v := match HLam.ofId? id with
    | some l => l.call arg v
    | none => U.toEnv.callV id arg v

/-- Library closures of a test program (`WellFormed`): the mirror and the parent lambdas. -/
def isLibH (id : Nat) : Bool := ResourceUse.isLib id || (HLam.ofId? id).isSome

/-- The root program: `p`, or `p.start.flatMap(f => f.cancel.flatMap(_ => f.join))`. -/
def withParent (viaParent : Bool) (p : IO) : IO :=
  if viaParent then .flatMap (.start p) HLam.cancelJoin.fn else p

/-! ## Markers and harness names -/

/-- A `delay` marker: user function `m` emits `x` and returns `unit`. -/
def Marker (env : UserEnv) (m : Nat) (x : Val) : Prop :=
  ∀ (a : Val) (v : View), env.callV m a v = { effects := [.emit x], out := .ret .unit }

/-- A `map` marker: user function `m` emits `x` and returns `unit` (`fa.map(_ => { emit x; () })`). -/
def MapMarker (env : UserEnv) (m : Nat) (x : Val) : Prop :=
  ∀ (a : Val) (v : View), env.callV m a v = { effects := [.emit x], out := .ret .unit }

/-- No user function (even id) other than `ms` emits a value of `xs` (library closures emit
nothing themselves). -/
def EmitsOnly (env : UserEnv) (ms : List Nat) (xs : List Val) : Prop :=
  ∀ id, id % 2 = 0 → id ∉ ms → ∀ (a : Val) (v : View) (x : Val), x ∈ xs → .emit x ∉ (env.callV id a v).effects

/-- The harness names of one marked `make`: the markers as program ids and as `REnv` indices,
the acquire and release codes, the resource code. -/
def names (c : Val) (acq rel mA mR : Nat) : List Val :=
  [.nat (2 * mA), .nat mA, .nat (2 * mR), .nat mR, .nat acq, .nat rel, c]

/-- A resource `Res` mentions a harness name. -/
def mentionsRes (bad : List Val) : Res → Bool
  | .allocate (.user k) => mentionsV bad (.nat k)
  | .allocate (.make a r) => mentionsV bad (.nat a) || mentionsV bad (.nat r)
  | .bind s f => mentionsRes bad s || mentionsV bad (.nat f)
  | .pure v => mentionsV bad v
  | .eval fa => mentionsIO bad fa

/-- A marked `make` with code `c`: `make(a0.map(markA))(_ => IO.delay(markR) *> q(..))`. `mA`
emits `A` when acquire completes (inside the mask of `Allocate`); `mR` emits `R` when release
starts. `a0` and the rest `q` of release are user code without harness names. -/
def MarkedMake (U : UEnv) (bad : List Val) (c : Val) (acq rel : Nat) (a0 : IO) (mA mR : Nat)
    (A R : Val) : Prop :=
  U.resOf c = some (Res.make acq rel) ∧ U.r.acquire acq = .map a0 (uid mA) ∧
    MapMarker U.toEnv (2 * mA) A ∧ Marker U.toEnv (2 * mR) R ∧
    (∀ a, ∃ q, U.r.release rel a = .ok (.flatMap (.delay (uid mR)) (uid q)) ∧
      mentionsV bad (.nat (2 * q)) = false) ∧
    mentionsIO bad a0 = false

/-- User code introduces no harness name (module doc). `ms`: the marker program ids (they emit,
nothing else); `acqs`, `rels`, `ks`, `cs`: the harness acquire, release, `Bind` and resource codes
(harness data, not user code). -/
def NoForge (U : UEnv) (bad : List Val) (ms acqs rels ks : List Nat) (cs : List Val) : Prop :=
  (∀ id, id % 2 = 0 → id ∉ ms → ∀ (a : Val) (v : View),
    mentionsR bad (U.toEnv.callV id a v) = true → mentionsV bad a = true) ∧
  (∀ k a r, k ∉ ks → U.r.bind k a = .ok r → mentionsRes bad r = true → mentionsV bad a = true) ∧
  (∀ k, k ∉ acqs → mentionsIO bad (U.r.acquire k) = false) ∧
  (∀ k a q, k ∉ rels → U.r.release k a = .ok q → mentionsIO bad q = true → mentionsV bad a = true) ∧
  (∀ c r, c ∉ cs → U.resOf c = some r → mentionsRes bad r = false)

/-! ## Statements -/

/-- 1, for an implementation `impl ca cb` of `Resource.both` (`Resource.scala:286-314`, Scaladoc
`:248-257`): `impl(A, B).use(f)` releases both sides. -/
def BothReleasesBothFor (impl : Val → Val → Res) : Prop :=
  ∀ (U : UEnv) (ca cb : Val) (acqA relA acqB relB : Nat) (a0 b0 : IO) (mA mB mRA mRB f : Nat)
    (A B RA RB : Val) (viaParent : Bool),
    MarkedMake U (names ca acqA relA mA mRA ++ names cb acqB relB mB mRB) ca acqA relA a0 mA mRA A RA →
    MarkedMake U (names ca acqA relA mA mRA ++ names cb acqB relB mB mRB) cb acqB relB b0 mB mRB B RB →
    [A, B, RA, RB].Nodup →
    EmitsOnly U.toEnv [2 * mA, 2 * mB, 2 * mRA, 2 * mRB] [A, B, RA, RB] →
    NoForge U (names ca acqA relA mA mRA ++ names cb acqB relB mB mRB) [2 * mA, 2 * mB, 2 * mRA, 2 * mRB]
      [acqA, acqB] [relA, relB] [] [ca, cb] →
    mentionsV (names ca acqA relA mA mRA ++ names cb acqB relB mB mRB) (.nat f) = false →
    WellFormed isLibH [] (envH U) (withParent viaParent (useOf U f (impl ca cb))) →
    ∀ o, outcomesP {} counterMaskModel (envH U) (withParent viaParent (useOf U f (impl ca cb))) o →
      (∃ oc, o.summary = .done oc) →
      o.out.count RA = o.out.count A ∧ o.out.count RB = o.out.count B

/-- 1. `Resource.both` releases both sides (v3.7.1 mirror). -/
def bothReleasesBoth : Prop := BothReleasesBothFor bothRes

/-- 2. `make(acq)(rel).use(f)` releases exactly once iff acquire completed
(`Resource.scala:156-208` with `IO.bracketFull`). -/
def useReleaseOnce : Prop :=
  ∀ (U : UEnv) (c : Val) (acq rel : Nat) (a0 : IO) (mA mR f : Nat) (A R : Val) (viaParent : Bool),
    MarkedMake U (names c acq rel mA mR) c acq rel a0 mA mR A R →
    A ≠ R →
    EmitsOnly U.toEnv [2 * mA, 2 * mR] [A, R] →
    NoForge U (names c acq rel mA mR) [2 * mA, 2 * mR] [acq] [rel] [] [c] →
    mentionsV (names c acq rel mA mR) (.nat f) = false →
    WellFormed isLibH [] (envH U) (withParent viaParent (useOf U f (Res.make acq rel))) →
    ∀ o, outcomesP {} counterMaskModel (envH U) (withParent viaParent (useOf U f (Res.make acq rel))) o →
      (∃ oc, o.summary = .done oc) → o.out.count R = o.out.count A

/-- `x` comes before `y` in `l` (`out` is newest first: `x` was emitted after `y`). -/
def Before (l : List Val) (x y : Val) : Prop := l.idxOf x < l.idxOf y

/-- 3. `make(A).flatMap(_ => make(B)).use(f)`: each release iff its acquire, and `B` is released
before `A` (`Resource.scala:156-196`: nested `bracketFull`). `k` is the harness `flatMap` function
(`_ => make(B)`). -/
def flatMapReleaseOrder : Prop :=
  ∀ (U : UEnv) (ca cb : Val) (acqA relA acqB relB : Nat) (a0 b0 : IO) (mA mB mRA mRB f k : Nat)
    (A B RA RB : Val) (viaParent : Bool),
    MarkedMake U (.nat k :: names ca acqA relA mA mRA ++ names cb acqB relB mB mRB) ca acqA relA a0 mA mRA A RA →
    MarkedMake U (.nat k :: names ca acqA relA mA mRA ++ names cb acqB relB mB mRB) cb acqB relB b0 mB mRB B RB →
    (∀ x, U.r.bind k x = .ok (Res.make acqB relB)) →
    [A, B, RA, RB].Nodup →
    EmitsOnly U.toEnv [2 * mA, 2 * mB, 2 * mRA, 2 * mRB] [A, B, RA, RB] →
    NoForge U (.nat k :: names ca acqA relA mA mRA ++ names cb acqB relB mB mRB)
      [2 * mA, 2 * mB, 2 * mRA, 2 * mRB] [acqA, acqB] [relA, relB] [k] [ca, cb] →
    mentionsV (.nat k :: names ca acqA relA mA mRA ++ names cb acqB relB mB mRB) (.nat f) = false →
    WellFormed isLibH [] (envH U) (withParent viaParent (useOf U f ((Res.make acqA relA).flatMap k))) →
    ∀ o, outcomesP {} counterMaskModel (envH U)
        (withParent viaParent (useOf U f ((Res.make acqA relA).flatMap k))) o →
      (∃ oc, o.summary = .done oc) →
      o.out.count RA = o.out.count A ∧ o.out.count RB = o.out.count B ∧
      (RA ∈ o.out → RB ∈ o.out → Before o.out RA RB)

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

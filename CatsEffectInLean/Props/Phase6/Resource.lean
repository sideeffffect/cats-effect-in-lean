import CatsEffectInLean.Model.ResourceUse
import CatsEffectInLean.Props.Phase6.Bracket

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
and all schedules. The only other hypotheses are `WellFormed` (decision 27) and the definitions
of the test program (markers, the parent fiber of decision 50).

## Statements

1. `bothReleasesBoth` (source (b), invariant; Scaladoc `Resource.scala:248-257`: "The finalizers
   for the two resources are also run concurrently ... nested finalizers are run in the usual
   reverse order"): `Resource.both(A, B).use(f)`, each side a `make` with markers. In every run
   that ends with a root outcome, each release runs exactly as often as its acquire completed.
   Refuted: CE-0020 (a release of one side raises an error; `F.both` then cancels the fiber that
   runs the other side's finalizers before it starts).
2. `useReleaseOnce` (source (b), decision 50): `make(acq)(rel).use(f)`, directly or in a child
   that the parent cancels at any point. Release runs exactly once iff acquire completed.
3. `flatMapReleaseOrder` (source (b); Scaladoc of `both`, `Resource.scala:251-252`, and of
   `flatMap`): `make(A).flatMap(_ => make(B)).use(f)`: each release runs iff its acquire
   completed, and `B` is released before `A` (LIFO).
4. `resourceEvalPreservesCancelable` (decision 41, the cancelable direction of CE-0002): if
   masking `fa` changes its behaviour, masking `Resource.eval(fa).allocatedCase` changes it too.
   An over-masking `Eval` (a wrong function) breaks it.
-/

namespace CatsEffectInLean.Props.Phase6.Resource

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Bracket (Marker ParentEnv parent usesId)

/-- `r.use(f)` built at the root (view `{}`), `f` = program function `f`. The resources of the
statements start with `Allocate`, so no user function is called when the term is built. -/
def useOf (U : UEnv) (f : Nat) (r : Res) : IO :=
  match (useIO U U.userCall f r {}).2 with
  | .ok p => p
  | .error e => .error e

/-- The root program: `p` itself, or `parent p` (decision 50: a parent starts `p`, cancels it at
a point that the schedule picks, and joins it). -/
def withParent (viaParent : Bool) (p : IO) : IO := if viaParent then parent p else p

/-- No user function (even id) other than `ms` emits a value of `xs`, and no user function returns
a program that names a marker. Library closures (odd ids) are the mirror: they call user
functions, so they are not restricted. (Unlike `Bracket.MarkersOnly`, which also restricts the
odd ids; a library closure that calls a marker function emits its value.) Limit: a user program
that builds a library closure whose field names a marker function is not excluded. -/
def UserMarkersOnly (env : UserEnv) (ms : List Nat) (xs : List Val) : Prop :=
  (∀ id, id % 2 = 0 → id ∉ ms → ∀ (a : Val) (v : View) (x : Val), x ∈ xs → .emit x ∉ (env.callV id a v).effects) ∧
  (∀ id, id % 2 = 0 → ∀ (a : Val) (v : View) (p : IO), (env.callV id a v).out = .prog p →
    ∀ m ∈ ms, usesId m p = false)

/-- A `map` marker: user function `m` emits `x` and returns `unit` (`fa.map(_ => { emit x; () })`). -/
def MapMarker (env : UserEnv) (m : Nat) (x : Val) : Prop :=
  ∀ (a : Val) (v : View), env.callV m a v = { effects := [.emit x], out := .ret .unit }

/-- A marked `make`: `make(a0.map(_ => emit A))(a => IO.delay(emit R) *> q(..))`, with resource
code `c` (`U.resOf c`). `mA` emits `A` when acquire completes (inside the mask of `Allocate`:
nothing can cancel between `a0` and the marker); `mR` emits `R` when release starts. `a0` and
the rest of release are arbitrary. -/
def MarkedMake (U : UEnv) (c : Val) (a0 : IO) (mA mR : Nat) (A R : Val) : Prop :=
  ∃ acq rel, U.resOf c = some (Res.make acq rel) ∧ U.r.acquire acq = .map a0 (uid mA) ∧
    MapMarker U.toEnv (2 * mA) A ∧ Marker U.toEnv (2 * mR) R ∧
    (∀ a, ∃ q, U.r.release rel a = .ok (.flatMap (.delay (uid mR)) (uid q))) ∧
    usesId (2 * mA) a0 = false ∧ usesId (2 * mR) a0 = false

/-- 1. `Resource.both` releases both sides (`Resource.scala:286-314`, Scaladoc `:248-257`). -/
def bothReleasesBoth : Prop :=
  ∀ (U : UEnv) (ca cb : Val) (a0 b0 : IO) (mA mB mRA mRB f : Nat) (A B RA RB : Val) (viaParent : Bool),
    MarkedMake U ca a0 mA mRA A RA → MarkedMake U cb b0 mB mRB B RB →
    [A, B, RA, RB].Nodup →
    UserMarkersOnly U.toEnv [2 * mA, 2 * mB, 2 * mRA, 2 * mRB] [A, B, RA, RB] →
    (viaParent = true → ParentEnv U.toEnv) →
    WellFormed ResourceUse.isLib [] U.toEnv (withParent viaParent (useOf U f (bothRes ca cb))) →
    ∀ o, outcomesP {} counterMaskModel U.toEnv (withParent viaParent (useOf U f (bothRes ca cb))) o →
      (∃ oc, o.summary = .done oc) →
      o.out.count RA = o.out.count A ∧ o.out.count RB = o.out.count B

/-- 2. `make(acq)(rel).use(f)` releases exactly once iff acquire completed
(`Resource.scala:156-208` with `IO.bracketFull`). -/
def useReleaseOnce : Prop :=
  ∀ (U : UEnv) (c : Val) (a0 : IO) (mA mR f : Nat) (A R : Val) (r : Res) (viaParent : Bool),
    MarkedMake U c a0 mA mR A R → U.resOf c = some r →
    A ≠ R →
    UserMarkersOnly U.toEnv [2 * mA, 2 * mR] [A, R] →
    (viaParent = true → ParentEnv U.toEnv) →
    WellFormed ResourceUse.isLib [] U.toEnv (withParent viaParent (useOf U f r)) →
    ∀ o, outcomesP {} counterMaskModel U.toEnv (withParent viaParent (useOf U f r)) o →
      (∃ oc, o.summary = .done oc) → o.out.count R = o.out.count A

/-- `x` comes before `y` in `l` (`out` is newest first: `x` was emitted after `y`). -/
def Before (l : List Val) (x y : Val) : Prop := l.idxOf x < l.idxOf y

/-- 3. `make(A).flatMap(_ => make(B)).use(f)`: each release runs iff its acquire completed, and
the release of `B` starts before the release of `A` (`Resource.scala:156-196`: nested
`bracketFull`). `k` is the `flatMap` function; it ignores its argument. -/
def flatMapReleaseOrder : Prop :=
  ∀ (U : UEnv) (ca cb : Val) (a0 b0 : IO) (mA mB mRA mRB f k : Nat) (A B RA RB : Val)
    (resA resB : Res) (viaParent : Bool),
    MarkedMake U ca a0 mA mRA A RA → MarkedMake U cb b0 mB mRB B RB →
    U.resOf ca = some resA → U.resOf cb = some resB →
    (∀ x, U.r.bind k x = .ok resB) →
    [A, B, RA, RB].Nodup →
    UserMarkersOnly U.toEnv [2 * mA, 2 * mB, 2 * mRA, 2 * mRB] [A, B, RA, RB] →
    (viaParent = true → ParentEnv U.toEnv) →
    WellFormed ResourceUse.isLib [] U.toEnv (withParent viaParent (useOf U f (resA.flatMap k))) →
    ∀ o, outcomesP {} counterMaskModel U.toEnv (withParent viaParent (useOf U f (resA.flatMap k))) o →
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

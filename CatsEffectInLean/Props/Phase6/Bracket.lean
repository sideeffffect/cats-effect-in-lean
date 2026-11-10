import CatsEffectInLean.Model.Bracket
import CatsEffectInLean.Model.IOInstance
import CatsEffectInLean.Model.WellFormed

/-!
# `guarantee` and `bracket*`: law, twins and invariants (Phase 6, track G)

Model: `CatsEffectInLean/Model/Bracket.lean` (mirror of `IO#guarantee` `IO.scala:496-501`,
`IO#guaranteeCase` `:523-530`, `IO#bracket` `:338-339`, `IO#bracketCase` `:370-371`,
`IO.bracketFull` `:1826-1830`, `reportError` `:967-972`, and the kernel defaults
`K/MonadCancel.scala:344-456` with the `IO` operations), on the `IOFiber` mirror
(`Model/Step.lean`, `counterMaskModel`, default `Config`). Paths at Cats Effect `v3.7.1`.

`<->` is `EqvP` (all schedules with preemption at any run-loop iteration, no outside
cancel; `Model/Outcomes.lean`). Each statement quantifies over all user environments `env` that
run the mirror's library closures as the mirror (`Bracket.LibEnv`, the "library" part), over
all external programs `ioOf`, and over all user functions. The only other hypotheses are
`WellFormed` (decision 27: the programs and user code are ones Scala can write) and, for the
invariants, the definitions of the test program (markers and the parent fiber).

## Statements

1. `guaranteeIsGuaranteeCase`: the law `L/MonadCancelLaws.scala:28-29` at `IO`.
   `IOAsync` overrides both sides with different bodies (`IO.scala:2023-2027`).
2. `bracketFullIsKernelDefault`: twin (source (a)): `IO.bracketFull` (the `IOAsync` override,
   `IO.scala:2062-2064`) against the kernel default body `K/MonadCancel.scala:447-456` with the
   same `IO` operations. Refuted: CE-0005.
3. `bracketFullIsKernelDefaultPureUse`: the same twin for ordinary inputs (the rule "if only an
   exotic input refutes a property, also state it for ordinary inputs"): `use` is a pure
   function (no effect and no throw when it is called; the `IO` it returns is arbitrary).
4. `bracketReleaseOnce` (source (b), decision 50): `bracket` in a child fiber that the parent
   cancels at any point (the schedule picks it), then joins. Release runs exactly once if and
   only if acquire completed, for every outcome of `use`.
5. `guaranteeFinalizerOnce` (source (b)): the same for `guarantee`: the finalizer runs at most
   once, and it runs if `fa` started.
-/

namespace CatsEffectInLean.Props.Phase6.Bracket

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket

/-- `<->` for `IO` (as `Props/IO/MonadCancelLaws.lean`). -/
def IOEqv (env : UserEnv) (p q : IO) : Prop := EqvP {} counterMaskModel env p q

/-- `L/MonadCancelLaws.scala:28-29` at `IO`: `F.guarantee(fa, fin) <-> F.guaranteeCase(fa)(_ => fin)`.
`F.guarantee` = `IO#guarantee` (`IO.scala:2023-2024`), `F.guaranteeCase` = `IO#guaranteeCase`
(`IO.scala:2026-2027`). `fa = ioOf s`, `fin = ioOf f`; `k` is the user lambda `_ => fin`. -/
def guaranteeIsGuaranteeCase : Prop :=
  ∀ (env : UserEnv) (ioOf : Val → IO) (s f : Val) (k : Nat),
    LibEnv env ioOf →
    IOI.Lam.constProg env k (ioOf f) →
    WellFormed isLib [] env (ioOf s) →
    WellFormed isLib [] env (ioOf f) →
    WellFormed isLib [] env (guaranteeIO (.ext s) (.ext f)) →
    WellFormed isLib [] env (guaranteeCaseIO (.ext s) k) →
    IOEqv env (guaranteeIO (.ext s) (.ext f)) (guaranteeCaseIO (.ext s) k)

/-- Twin: `IO.bracketFull(acquire)(use)(release)` (`IO.scala:1826-1830`) `<->` the kernel
`MonadCancel#bracketFull` body (`K/MonadCancel.scala:447-456`) with the `IO` operations. All
user functions (`acq`, `use`, `rel`) are arbitrary well-formed user code. -/
def bracketFullIsKernelDefault : Prop :=
  ∀ (env : UserEnv) (ioOf : Val → IO) (acq use rel : Nat),
    LibEnv env ioOf →
    WellFormed isLib [] env (bracketFullIO acq use rel) →
    WellFormed isLib [] env (defaultBracketFullIO acq use rel) →
    IOEqv env (bracketFullIO acq use rel) (defaultBracketFullIO acq use rel)

/-- `use` is a pure function: a call has no effect and does not throw. -/
def PureFn (env : UserEnv) (use : Nat) : Prop :=
  ∀ (a : Val) (v : View), ∃ p, env.callV use a v = { out := .prog p }

/-- The twin of `bracketFullIsKernelDefault` for ordinary inputs: `use` is pure. -/
def bracketFullIsKernelDefaultPureUse : Prop :=
  ∀ (env : UserEnv) (ioOf : Val → IO) (acq use rel : Nat),
    LibEnv env ioOf →
    PureFn env use →
    WellFormed isLib [] env (bracketFullIO acq use rel) →
    WellFormed isLib [] env (defaultBracketFullIO acq use rel) →
    IOEqv env (bracketFullIO acq use rel) (defaultBracketFullIO acq use rel)

/-! ## The test program of the invariants (decision 50)

`parent b` = `b.start.flatMap(f => f.cancel.flatMap(_ => f.join))`: the root starts `b` in a child fiber,
cancels it, and waits for it. The schedule decides where the cancel lands (before the child
runs, in acquire, in use, in release, or after the end). The two lambdas are user code (even
ids, `Codec.userFn`, namespace `pns`); `f.cancel`/`f.join` read `_cancel`/`_join` when Scala
builds them (`IO.cancelOf`, `IO.joinOf`). -/

/-- The namespace of the parent lambdas. -/
def pns : Nat := 8

/-- The lambdas of `parent`. -/
inductive PLam where
  /-- `f => f.cancel.flatMap(_ => f.join)`. -/
  | cancelJoin
  /-- `_ => f.join`. -/
  | thenJoin (f : Nat)
  deriving DecidableEq, Repr

/-- The closure value. -/
def PLam.toVal : PLam → Val
  | .cancelJoin => cloVal pns 0 []
  | .thenJoin f => cloVal pns 1 [.fiber f]

/-- The closure as a user function. -/
def PLam.fn (l : PLam) : Fn := userFn l.toVal

/-- Run a parent lambda. -/
def PLam.call (l : PLam) (arg : Val) (v : View) : UserResult :=
  match l, arg with
  | .cancelJoin, .fiber f => { out := .prog (.flatMap (IO.cancelOf f (v.outcome f)) (PLam.thenJoin f).fn) }
  | .thenJoin f, _ => { out := .prog (IO.joinOf f (v.outcome f)) }
  | _, _ => { out := .throw { code := 999999, kind := .fatal } }

/-- `env` runs the parent lambdas. -/
def ParentEnv (env : UserEnv) : Prop :=
  ∀ (l : PLam) (arg : Val) (v : View), env.callV (2 * valToNat l.toVal) arg v = l.call arg v

/-- The test program: `b.start.flatMap(f => f.cancel.flatMap(_ => f.join))`. -/
def parent (b : IO) : IO := .flatMap (.start b) PLam.cancelJoin.fn

/-- Does a term name user function `id` (directly, or inside a runtime closure)? -/
def usesId (id : Nat) : IO → Bool
  | .map p f | .flatMap p f | .handleErrorWith p f => usesId id p || fnUses id f
  | .delay f | .uncancelable f | .ioCont f | .blocking _ f | .local f => fnUses id f
  | .attempt p | .start p | .unmaskRunLoop p _ _ | .evalOn p _ => usesId id p
  | .onCancel p q | .racePair p q => usesId id p || usesId id q
  | _ => false
where
  /-- `Fn` case (runtime closures hold no user function ids that matter here except `racePair`). -/
  fnUses (id : Nat) : Fn → Bool
    | .user k => k == id
    | .rt _ => false

/-- A marker: user function `m` emits `x` and returns `unit` (the thunk of `IO.delay(emit x)`). -/
def Marker (env : UserEnv) (m : Nat) (x : Val) : Prop :=
  ∀ (a : Val) (v : View), env.callV m a v = { effects := [.emit x], out := .ret .unit }

/-- No user code other than `ms` emits a value of `xs`, and no user function returns a program
that names a marker (so each marker runs only where the test program puts it). -/
def MarkersOnly (env : UserEnv) (ms : List Nat) (xs : List Val) : Prop :=
  (∀ id, id ∉ ms → ∀ (a : Val) (v : View) (x : Val), x ∈ xs → .emit x ∉ (env.callV id a v).effects) ∧
  (∀ id, id % 2 = 0 → ∀ (a : Val) (v : View) (p : IO), (env.callV id a v).out = .prog p →
    ∀ m ∈ ms, usesId m p = false)

/-- Release runs exactly once iff acquire completed (decision 50: the cancel comes from the
parent fiber). `acquire = a0.flatMap(mA)`: `mA` emits `A` when acquire completes (inside the
`bracket` mask, `IO.scala:1828`, so nothing can cancel between `a0` and the marker), then gives
the value back. `release(a) = IO.delay(emit R) *> q(..)`: `mR` emits `R` when release starts. `use`
and the rest of release are arbitrary. Claim: in every run that ends with a root outcome,
`R` appears as often as `A` (0 or 1 times). -/
def bracketReleaseOnce : Prop :=
  ∀ (env : UserEnv) (ioOf : Val → IO) (sA : Val) (a0 : IO) (mA mR use rel : Nat) (A R : Val),
    LibEnv env ioOf → ParentEnv env →
    ioOf sA = .flatMap a0 (.user mA) →
    (∀ (x : Val) (v : View), env.callV mA x v = { effects := [.emit A], out := .prog (.pure x) }) →
    Marker env mR R →
    (∀ (x : Val) (v : View), ∃ q, env.callV rel x v = { out := .prog (.flatMap (.delay (.user mR)) (.user q)) }) →
    A ≠ R → use ≠ mA → use ≠ mR →
    MarkersOnly env [mA, mR] [A, R] →
    usesId mA a0 = false → usesId mR a0 = false →
    WellFormed isLib [] env a0 →
    WellFormed isLib [] env (parent (bracketIO (.ext sA) use rel)) →
    ∀ o, outcomesP {} counterMaskModel env (parent (bracketIO (.ext sA) use rel)) o →
      (∃ oc, o.summary = .done oc) → o.out.count R = o.out.count A

/-- The `guarantee` finalizer runs at most once, and it runs if `fa` started
(`IO.scala:496-501`). `fa = IO.delay(emit A) *> k(..)` (`mA` emits `A` when `fa` starts),
`fin = IO.delay(emit R) *> q(..)`. Same parent fiber as `bracketReleaseOnce`. -/
def guaranteeFinalizerOnce : Prop :=
  ∀ (env : UserEnv) (ioOf : Val → IO) (s f : Val) (mA mR k q : Nat) (A R : Val),
    LibEnv env ioOf → ParentEnv env →
    ioOf s = .flatMap (.delay (.user mA)) (.user k) →
    ioOf f = .flatMap (.delay (.user mR)) (.user q) →
    Marker env mA A → Marker env mR R →
    A ≠ R → k ≠ mA → k ≠ mR → q ≠ mA → q ≠ mR →
    MarkersOnly env [mA, mR] [A, R] →
    WellFormed isLib [] env (ioOf s) → WellFormed isLib [] env (ioOf f) →
    WellFormed isLib [] env (parent (guaranteeIO (.ext s) (.ext f))) →
    ∀ o, outcomesP {} counterMaskModel env (parent (guaranteeIO (.ext s) (.ext f))) o →
      (∃ oc, o.summary = .done oc) → o.out.count R ≤ 1 ∧ o.out.count A ≤ o.out.count R

end CatsEffectInLean.Props.Phase6.Bracket

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
invariants, the test program (the harness `henv`, with its own markers and parent fiber;
decisions 53, 54).

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
   only if acquire completed, for every outcome of `use`. Restated after review batch 4 (the
   first form was vacuous); satisfiability witness in `Proofs/Phase6/BracketWitness.lean`.
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

/-! ## The test program of the invariants (decisions 50, 53, 54)

Review batch 4 found the first form of statements 4 and 5 vacuous: its marker hypothesis
(`MarkersOnly`) could never hold together with the others. The redesign (decision 54):

* The test program is the harness. Its lambdas are harness closures (`HLam`, odd ids, namespace
  `hns`), run by the statement's own environment `henv`, not by hypotheses on an arbitrary
  environment. User code is an arbitrary `u : UserEnv` (all even ids) and an arbitrary acquire
  program `a0`.
* The harness first makes two counter cells: `Ref` 0 counts "acquire completed" (bracket) or
  "`fa` started" (guarantee); `Ref` 1 counts "release/finalizer started". The markers are
  harness closures that capture the cell handle (`markA c`, `markS c`, `markR c`). `WellFormed`
  (with no handle at the start, `H0 = []`) makes the cells unreachable for user code: user code
  cannot write them, cannot name a marker (its id captures the handle), and cannot forward one
  through a `Bracket` closure (a good `BLam` takes only user functions or `Bracket` leaves as
  function fields, `Bracket.isLib`; a marker is neither).
* `parent b` = `Ref(0), Ref(0)` then `b.start.flatMap(f => f.cancel.flatMap(_ => f.join))`: the
  schedule picks where the parent's cancel lands (before the child runs, in acquire, in use, in
  release, or after the end).

Scala form of the bracket test program (`c0`, `c1` are the counters):

```scala
(a0.flatMap(a => c0.update(_ + 1).as(a))).bracket(use)(a => c1.update(_ + 1).flatMap(_ => rel(a)))
```
-/

/-- The namespace of the harness closures (track G: 40..49). -/
def hns : Nat := 40

/-- The harness lambdas. `c`: a counter cell; `use`, `rel`, `k`, `q`: user functions;
`g`: 0 = the bracket program, 1 = the guarantee program. -/
inductive HLam where
  /-- The thunk `(Ref.unsafe(0), Ref.unsafe(0))`: two new counter cells. -/
  | newCells
  /-- `cs => parent body`: the cells are `Val.ref c0`, `Val.ref c1`. -/
  | afterCells (g use rel : Nat)
  /-- `a => c.update(_ + 1).as(a)` in one step (the acquire marker). -/
  | markA (c : Nat)
  /-- The thunk `c.update(_ + 1)` (`fa` started, or release started). -/
  | markThunk (c : Nat)
  /-- The release of the bracket program: `a => IO.delay(markR).flatMap(_ => rel(a))`. -/
  | relW (c rel : Nat)
  /-- `_ => rel(a)`. -/
  | relCall (rel : Nat) (a : Val)
  /-- `f => f.cancel.flatMap(_ => f.join)`. -/
  | cancelJoin
  /-- `_ => f.join`. -/
  | thenJoin (f : Nat)
  deriving DecidableEq, Repr

def HLam.toVal : HLam → Val
  | .newCells => cloVal hns 0 []
  | .afterCells g use rel => cloVal hns 1 [.nat g, .nat use, .nat rel]
  | .markA c => cloVal hns 2 [.ref c]
  | .markThunk c => cloVal hns 3 [.ref c]
  | .relW c rel => cloVal hns 4 [.ref c, .nat rel]
  | .relCall rel a => cloVal hns 5 [.nat rel, a]
  | .cancelJoin => cloVal hns 6 []
  | .thenJoin f => cloVal hns 7 [.fiber f]

def HLam.ofFields : Nat → List Val → Option HLam
  | 0, [] => some .newCells
  | 1, [.nat g, .nat use, .nat rel] => some (.afterCells g use rel)
  | 2, [.ref c] => some (.markA c)
  | 3, [.ref c] => some (.markThunk c)
  | 4, [.ref c, .nat rel] => some (.relW c rel)
  | 5, [.nat rel, a] => some (.relCall rel a)
  | 6, [] => some .cancelJoin
  | 7, [.fiber f] => some (.thenJoin f)
  | _, _ => none

/-- A harness closure is a library closure (odd id). -/
def HLam.id (l : HLam) : Nat := 2 * valToNat l.toVal + 1
def HLam.fn (l : HLam) : Fn := .user l.id

def HLam.ofId? (id : Nat) : Option HLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == hns then HLam.ofFields tag fs else none
    | none => none
  else none

/-- `c.update(_ + 1)` on the view. -/
def bump (c : Nat) (v : View) : UserEffect :=
  .writeRef c (match v.refs[c]? with | some (.nat n) => .nat (n + 1) | _ => .nat 1)

/-- The source codes of the external programs (`Bracket.Src.ext`). Each holds a counter handle,
so a user program that names a closure with this code must hold the handle (`WellFormed`). -/
def srcAcq (c : Nat) : Val := .pair (.ref c) (.nat 0)
def srcFa (c k : Nat) : Val := .pair (.ref c) (.pair (.nat 1) (.nat k))
def srcFin (c q : Nat) : Val := .pair (.ref c) (.pair (.nat 2) (.nat q))

/-- The external programs: acquire `a0.flatMap(markA)`, `fa = IO.delay(markS) *> k(..)`,
`fin = IO.delay(markR) *> q(..)`. -/
def hioOf (a0 : IO) : Val → IO
  | .pair (.ref c) (.nat 0) => .flatMap a0 (HLam.markA c).fn
  | .pair (.ref c) (.pair (.nat 1) (.nat k)) => .flatMap (.delay (HLam.markThunk c).fn) (.user k)
  | .pair (.ref c) (.pair (.nat 2) (.nat q)) => .flatMap (.delay (HLam.markThunk c).fn) (.user q)
  | _ => .error { code := 999999, kind := .fatal }

/-- The child program of the harness: `g = 0` the bracket, `g = 1` the guarantee. `g = 2, 3`
are broken implementations for the wrong-function tests only (not Cats Effect code): a bracket
that never runs release (`acquire.flatMap(use)`), a guarantee that never runs the finalizer
(`fa` alone). The statements use only `g = 0, 1`. -/
def childOf (g use rel : Nat) (c0 c1 : Nat) : IO :=
  if g == 0 then Bracket.bracketIO (.ext (srcAcq c0)) use (HLam.relW c1 rel).id
  else if g == 1 then Bracket.guaranteeIO (.ext (srcFa c0 use)) (.ext (srcFin c1 rel))
  else if g == 2 then .flatMap (.flatMap (.pure .unit) (BLam.constThis (srcAcq c0)).fn) (.user use)
  else .flatMap (.pure .unit) (BLam.constThis (srcFa c0 use)).fn

private def hprog (p : IO) : UserResult := { out := .prog p }

/-- Run a harness closure. `u`: user code (for `rel(a)`). -/
def HLam.call (u : UserEnv) (l : HLam) (arg : Val) (v : View) : UserResult :=
  match l, arg with
  | .newCells, _ =>
    { effects := [.allocRef (.nat 0), .allocRef (.nat 0)],
      out := .ret (.pair (.ref v.refs.length) (.ref (v.refs.length + 1))) }
  | .afterCells g use rel, .pair (.ref c0) (.ref c1) =>
    hprog (.flatMap (.start (childOf g use rel c0 c1)) HLam.cancelJoin.fn)
  | .markA c, x => { effects := [bump c v], out := .prog (.pure x) }
  | .markThunk c, _ => { effects := [bump c v], out := .ret .unit }
  | .relW c rel, a => hprog (.flatMap (.delay (HLam.markThunk c).fn) (HLam.relCall rel a).fn)
  | .relCall rel a, _ => u.callV rel a v
  | .cancelJoin, .fiber f => hprog (.flatMap (IO.cancelOf f (v.outcome f)) (HLam.thenJoin f).fn)
  | .thenJoin f, _ => hprog (IO.joinOf f (v.outcome f))
  | _, _ => { out := .throw { code := 999999, kind := .fatal } }

/-- User calls from the mirror: harness closures, else user code. -/
def hcall (u : UserEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match HLam.ofId? id with
  | some h => h.call u arg v
  | none => u.callV id arg v

/-- The environment of the statements: the harness, the `Bracket` mirror, then user code. -/
def hdispatch (a0 : IO) (u : UserEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match HLam.ofId? id with
  | some h => h.call u arg v
  | none =>
    match BLam.ofId? id with
    | some l => Bracket.call (hcall u) (hioOf a0) l arg v
    | none => u.callV id arg v

def henv (a0 : IO) (u : UserEnv) : UserEnv where
  call id arg refs := hdispatch a0 u id arg { refs }
  callV := hdispatch a0 u

/-- The harness program `g` (0 bracket, 1 guarantee). -/
def harness (g use rel : Nat) : IO := .flatMap (.delay HLam.newCells.fn) (HLam.afterCells g use rel).fn

/-- A counter in an observation (cell `c`, 0 if absent). -/
def count (o : Obs) (c : Nat) : Nat :=
  match o.refs[c]? with
  | some (.nat n) => n
  | _ => 0

/-- Release runs exactly once iff acquire completed (decision 50: the parent fiber cancels the
child at any point). For all user code `u` and acquire programs `a0` that Scala can write
(`WellFormed`, no handle at the start), all user functions `use`, `rel`, all fuel values and
all `PChoice` schedules: when the root completes, the release counter equals the acquire
counter. -/
def bracketReleaseOnce : Prop :=
  ∀ (u : UserEnv) (a0 : IO) (use rel : Nat),
    use % 2 = 0 → rel % 2 = 0 →
    WellFormed isLib [] (henv a0 u) a0 →
    ∀ o, outcomesP {} counterMaskModel (henv a0 u) (harness 0 use rel) o →
      (∃ oc, o.summary = .done oc) → count o 1 = count o 0

/-- The `guarantee` finalizer runs at most once, and it runs if `fa` started
(`IO.scala:496-501`). `fa = IO.delay(markS) *> k(..)`, `fin = IO.delay(markR) *> q(..)` with
user functions `k`, `q`. Same harness and quantifiers as `bracketReleaseOnce`. -/
def guaranteeFinalizerOnce : Prop :=
  ∀ (u : UserEnv) (k q : Nat),
    k % 2 = 0 → q % 2 = 0 →
    WellFormed isLib [] (henv (.pure .unit) u) (.pure .unit) →
    ∀ o, outcomesP {} counterMaskModel (henv (.pure .unit) u) (harness 1 k q) o →
      (∃ oc, o.summary = .done oc) → count o 1 ≤ 1 ∧ count o 0 ≤ count o 1

end CatsEffectInLean.Props.Phase6.Bracket

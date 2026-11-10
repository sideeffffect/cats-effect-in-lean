import CatsEffectInLean.Model.Codec

/-!
# `WellFormed`: programs and user code that Scala can express (decision 27)

A property quantifies over programs `p : IO` and user environments `env : UserEnv`. Without a
restriction this domain is larger than Scala: a model program can name any fiber, `Ref`,
`Deferred`, `poll` or `ContState` id, and user code can read every cell of the heap
(`review/2026-11-10-review-batch-1.md`, wider concern 1). A refutation that needs such a
program is not a Cats Effect bug.

`WellFormed lib H0 env p` is a type invariant: each clause below states a fact that the Scala
type system or the Cats Effect API gives. So it is an allowed hypothesis (`AGENTS.md`,
properties). It makes refutations stronger: the witness must be a program that Scala can
write, and each refutation proves that its witness is well-formed.

## Capabilities

A **handle** (`Handle`) is a capability: a fiber (`FiberIO`), a `Ref`, a `Deferred`, a
`Poll` (mask id and fiber), or the `cb`/`get` pair of an `IOCont` (`ContState` id). Scala code
gets a handle only as a value: as the argument of a lambda, as a captured variable of a
closure, by reading a cell that it holds, or by allocating it. It cannot make one from a
number.

**Held handles** of one user call: the handles in its argument, the handles that its closure
captured (`captured`: the closure value in the id, `Model/Codec.lean`), the handles `H0` of
the scope of the whole program (for example a `Ref` made before the program), and all handles
that it can read from these (`Reach`: the value of a held `Ref` or `Deferred`, the outcome of a
held fiber).

## Clauses

1. **Fiber handles only as received** (`progOK`, `Fn.rt` cases `cancel`, `join`). A program
   names a fiber only through a held fiber handle. Scala: `FiberIO` has no public
   constructor; a fiber value comes from `start`, `racePair`, or a value that holds one.
2. **No forged `poll` or `ContState`** (`progOK`, cases `unmaskRunLoop`, `contGet`; effects
   `invokeCb`, `deferCb`). `UnmaskRunLoop(fa, id, self)` needs a held `poll`, `Get(state)` and a
   callback call need a held `ContState`. Scala: `Poll` is the argument of the `uncancelable`
   body (`IOFiber.scala:562-567`); `cb` and `get` are the arguments of the `IOCont` body
   (`IO.scala:2278-2286`). `UnmaskRunLoop`, `Get` and `EndFiber` are `private[effect]`
   (`IO.scala:2272-2334`). `EndFiber` is never allowed. User code makes
   `UnmaskRunLoop(fa, m, s)` only by applying a real poll (`IO.applyPoll`), so `m ≠ 0`: mask id
   `0` is `IdPoll` of `IO#syncStep`, whose `apply` is the identity (`IO.scala:2391-2393`), and
   `IO.applyPoll fa 0 s = fa` (decision 37).
3. **Closure ids only from their side** (`fnOK`). A user function has an even id; an odd id is
   a library closure, and a program may hold it only if `lib id` (it decodes to a mirrored
   library lambda) and its captured handles are held. Scala: user code cannot build a private
   lambda of Cats Effect with chosen captured values; it gets library closures only through
   the public API, which captures values that the caller passed. The runtime closures
   (`Fn.rt`) that public operations build are allowed with held handles: `fib.cancel`
   (`cancel`), `fib.join` (`join`), `deferred.get` (`deferredDefer`, `deferredFlatten`),
   `deferred.complete` (`deferredComplete`), `void` (`voidK`). All other `Fn.rt` closures are
   internal to `IOFiber` and never allowed.
4. **User code reads only through held handles** (`CallOK`, first part). The result of a user
   call does not change when cells outside the held set change. It can see the number of
   `Ref` and `Deferred` cells: the model gives the id of a new cell as that number
   (`UserEffect.allocRef`). Scala: a lambda reads a `Ref`, a `Deferred` or a fiber outcome only
   through its handle.
5. **Effects and results use held handles** (`ResultOK`). A `Ref` write needs a held `Ref`; a
   callback call needs a held `ContState`; values written, emitted or returned hold only held
   handles. A new `Ref` or `Deferred` is held after its allocation.
6. **`Poll` values are opaque** (`PollOpaque`, decision 37). User code can pass a `Poll` on,
   store it, or apply it (`poll(fa)`, `IO.applyPoll`). It cannot read the mask id or the fiber
   of a `Poll`: a user call on inputs with renamed `Poll` handles gives the renamed result.
   Scala: `Poll` is a trait with only `apply`; the `IOFiber` poll and `IdPoll` are anonymous
   classes in private code. Only reflection or the `Object` methods (`eq`, `hashCode`,
   `toString`) can tell two polls apart, and the model leaves these out. Without this clause a
   well-formed body could branch on `Val.poll 0 0` (`IdPoll`) and tell `syncStep` apart from
   the run loop (`review/2026-11-10-review-batch-2.md`, entry 5).

`WellFormed` checks the start program `p` with `progOK` against `H0` (decidable), every user
function (each even id, each argument, each heap view) with `CallOK`, and all user code with
`PollOpaque`. Library closures (odd ids)
are mirrored Cats Effect code; they are not user code, so `WellFormed` does not restrict them.

Not restricted: `ExecutionContext` ids (Scala code can make an `ExecutionContext`), `Val.trace`,
`Val.runtime`, and the values of errors. Out of scope: a user function that loops forever.
-/

namespace CatsEffectInLean.Model

/-- A capability: a value that Scala code can only receive, never make from a number. -/
inductive Handle where
  /-- A `FiberIO` (`Val.fiber`). -/
  | fiber (id : Nat)
  /-- A `Ref` (`Val.ref`). -/
  | ref (id : Nat)
  /-- A `Deferred` (`Val.deferred`). -/
  | deferred (id : Nat)
  /-- A `Poll` (`Val.poll`). -/
  | poll (maskId : Nat) (fiber : Nat)
  /-- The `cb` and `get` of one `IOCont` (`Val.cont`). -/
  | cont (state : Nat)
  deriving DecidableEq, Repr

/-- The handles in a value. -/
def Val.handles : Val → List Handle
  | .pair a b => a.handles ++ b.handles
  | .left v | .right v | .some v | .ocSucceeded v => v.handles
  | .fiber i => [.fiber i]
  | .ref i => [.ref i]
  | .deferred i => [.deferred i]
  | .poll m s => [.poll m s]
  | .cont s => [.cont s]
  | _ => []

namespace WF

open Codec

/-- The handles that the closure with id `id` captured (`Model/Codec.lean`): the handles in
its closure value, or none if `id / 2` is not a code. -/
def captured (id : Nat) : List Handle :=
  match cloOfId id with
  | some c => c.handles
  | none => []

/-- Are all handles of `hs` held (`mem`)? -/
def sub (mem : Handle → Bool) (hs : List Handle) : Bool := hs.all mem

/-- Clause 3 for runtime closures: only the ones that public operations build, with held
handles. -/
def rtOK (mem : Handle → Bool) : RtFn → Bool
  -- `fib.cancel` (`IOFiber.scala:197-201`), `fib.join` (`IOFiber.scala:203-207`)
  | .cancel t | .join t => mem (.fiber t)
  -- `deferred.get` (`IODeferred.scala:71`, `Syntax.lean`, `IO.deferredGetOf`)
  | .deferredDefer d | .deferredFlatten d => mem (.deferred d)
  -- `deferred.complete(a)` (`IODeferred.scala:62-69`)
  | .deferredComplete d v => mem (.deferred d) && sub mem v.handles
  -- `void` (`IO.scala:961-962`)
  | .voidK => true
  | _ => false

/-- Clause 3: a function in a program that user code built. -/
def fnOK (lib : Nat → Bool) (mem : Handle → Bool) : Fn → Bool
  | .user id => (id % 2 == 0 || lib id) && sub mem (captured id)
  | .rt k => rtOK mem k

/-- Clauses 1-3: a program that user code built, with held handles `mem`. -/
def progOK (lib : Nat → Bool) (mem : Handle → Bool) : IO → Bool
  | .pure v => sub mem v.handles
  | .error _ | .realTime | .monotonic | .readEC | .canceled | .cede | .sleep _
  | .ioTrace | .readRT => true
  | .delay f | .uncancelable f | .ioCont f | .blocking _ f | .local f => fnOK lib mem f
  | .map p f | .flatMap p f | .handleErrorWith p f => progOK lib mem p && fnOK lib mem f
  | .attempt p | .start p | .evalOn p _ => progOK lib mem p
  | .onCancel p q | .racePair p q => progOK lib mem p && progOK lib mem q
  -- `poll(fa)` (`IOFiber.scala:564-567`): only the result of `IO.applyPoll` with a held real
  -- poll (clause 6). Mask id `0` is `IdPoll`, whose `apply` is the identity (`IO.scala:2391-2393`).
  | .unmaskRunLoop p m s => m != 0 && mem (.poll m s) && progOK lib mem p
  -- `get` of an `IOCont` (`IO.scala:2284-2286`)
  | .contGet s => mem (.cont s)
  -- `EndFiber` (`IO.scala:2331-2334`) is internal
  | .endFiber => false

/-- The handles that a user call can reach from `base` in heap view `v` (clause 4): `base`,
and the handles in the value of a reached `Ref`, `Deferred` or fiber outcome. -/
inductive Reach (v : View) (base : List Handle) : Handle → Prop where
  | base {h : Handle} : h ∈ base → Reach v base h
  | ref {i : Nat} {x : Val} {h : Handle} : Reach v base (.ref i) → v.refs[i]? = some x →
      h ∈ x.handles → Reach v base h
  | deferred {d : Nat} {x : Val} {h : Handle} : Reach v base (.deferred d) →
      v.deferred d = some x → h ∈ x.handles → Reach v base h
  | fiber {t : Nat} {oc : Outcome} {h : Handle} : Reach v base (.fiber t) →
      v.outcome t = some oc → h ∈ oc.toVal.handles → Reach v base h

/-- Two views agree on the held handles `R` (clause 4). -/
def Agree (R : Handle → Prop) (v w : View) : Prop :=
  v.refs.length = w.refs.length ∧ v.deferreds.length = w.deferreds.length ∧
  (∀ i, R (.ref i) → v.refs[i]? = w.refs[i]?) ∧
  (∀ d, R (.deferred d) → v.deferred d = w.deferred d) ∧
  (∀ t, R (.fiber t) → v.outcome t = w.outcome t)

open Classical in
/-- A held-handle predicate as a `Bool` test (classical; only for statements). -/
noncomputable def memOf (R : Handle → Prop) : Handle → Bool := fun h => decide (R h)

/-- Clause 5 for the output. -/
def OutOK (lib : Nat → Bool) (R : Handle → Prop) : UserOut → Prop
  | .ret x => ∀ h ∈ x.handles, R h
  | .prog p => progOK lib (memOf R) p = true
  | .throw _ => True

/-- Clause 5: the effects in order, then the output. `nr`, `nd`: the ids of the next new `Ref`
and `Deferred` (`UserEffect.allocRef`, `allocDeferred`). A new cell is held after its
allocation. -/
def EffectsOK (lib : Nat → Bool) (out : UserOut) :
    (R : Handle → Prop) → (nr nd : Nat) → List UserEffect → Prop
  | R, _, _, [] => OutOK lib R out
  | R, nr, nd, .writeRef i x :: es =>
    R (.ref i) ∧ (∀ h ∈ x.handles, R h) ∧ EffectsOK lib out R nr nd es
  | R, nr, nd, .invokeCb s x :: es =>
    R (.cont s) ∧ (∀ h ∈ x.handles, R h) ∧ EffectsOK lib out R nr nd es
  | R, nr, nd, .deferCb s x :: es =>
    R (.cont s) ∧ (∀ h ∈ x.handles, R h) ∧ EffectsOK lib out R nr nd es
  | R, nr, nd, .emit x :: es => (∀ h ∈ x.handles, R h) ∧ EffectsOK lib out R nr nd es
  | R, nr, nd, .allocRef x :: es =>
    (∀ h ∈ x.handles, R h) ∧ EffectsOK lib out (fun h => R h ∨ h = .ref nr) (nr + 1) nd es
  | R, nr, nd, .allocDeferred :: es =>
    EffectsOK lib out (fun h => R h ∨ h = .deferred nd) nr (nd + 1) es
  | R, nr, nd, .report _ :: es => EffectsOK lib out R nr nd es

/-- Clause 5 for one call result in view `v`. -/
def ResultOK (lib : Nat → Bool) (R : Handle → Prop) (v : View) (r : UserResult) : Prop :=
  EffectsOK lib r.out R v.refs.length v.deferreds.length r.effects

/-- Clauses 4 and 5 for the call of user function `id` on `arg` in view `v`. `H0`: the handles
of the scope of the whole program. -/
def CallOK (lib : Nat → Bool) (H0 : List Handle) (env : UserEnv) (id : Nat) (arg : Val)
    (v : View) : Prop :=
  let R := Reach v (H0 ++ arg.handles ++ captured id)
  (∀ w, Agree R v w → env.callV id arg w = env.callV id arg v) ∧
  ResultOK lib R v (env.callV id arg v)

/-! ## Clause 6: `Poll` values are opaque (decision 37)

A renaming `σ` maps each `Poll` handle `(m, s)` to a `Poll` handle `σ m s`. `rnp σ` applies it
to every `Val.poll` in a value, a program, a view or a call result. A user closure (`Fn.user`)
holds its captured values in its id (`Model/Codec.lean`), so `rnId σ` renames them there too.
`UnmaskRunLoop(io, m, s)` is what `IO.applyPoll io m s` gives for a real poll, so the renaming
applies the new poll to the renamed `io`. The renaming must keep mask id `0` (`IdPoll`), because
`IO.applyPoll io 0 s = io`: then `rnp σ (IO.applyPoll io m s) = IO.applyPoll (rnp σ io) (σ m s)`
for every poll. -/

/-- A renaming of `Poll` handles. -/
abbrev PollRen := Nat → Nat → Nat × Nat

/-- Does a value hold a `Poll` handle? -/
def hasPoll : Val → Bool
  | .pair a b => hasPoll a || hasPoll b
  | .left v | .right v | .some v | .ocSucceeded v => hasPoll v
  | .poll _ _ => true
  | _ => false

/-- Rename the `Poll` handles of a value. -/
def rnVal (σ : PollRen) : Val → Val
  | .pair a b => .pair (rnVal σ a) (rnVal σ b)
  | .left v => .left (rnVal σ v)
  | .right v => .right (rnVal σ v)
  | .some v => .some (rnVal σ v)
  | .ocSucceeded v => .ocSucceeded (rnVal σ v)
  | .poll m s => .poll (σ m s).1 (σ m s).2
  | v => v

/-- Rename the `Poll` handles of an outcome. -/
def rnOutcome (σ : PollRen) : Outcome → Outcome
  | .succeeded v => .succeeded (rnVal σ v)
  | oc => oc

/-- Rename the `Poll` handles in the captured values of closure id `id`. An id whose closure
value holds no `Poll` stays the same. -/
def rnId (σ : PollRen) (id : Nat) : Nat :=
  match cloOfId id with
  | some c => if hasPoll c then 2 * valToNat (rnVal σ c) + id % 2 else id
  | none => id

/-- Rename the `Poll` handles of a function. Runtime closures other than `deferred.complete(a)`
are internal (`rtOK` rejects them in user programs); they stay the same. -/
def rnFn (σ : PollRen) : Fn → Fn
  | .user id => .user (rnId σ id)
  | .rt (.deferredComplete d v) => .rt (.deferredComplete d (rnVal σ v))
  | .rt k => .rt k

/-- Rename the `Poll` handles of a program. -/
def rnIO (σ : PollRen) : IO → IO
  | .pure v => .pure (rnVal σ v)
  | .delay f => .delay (rnFn σ f)
  | .map p f => .map (rnIO σ p) (rnFn σ f)
  | .flatMap p f => .flatMap (rnIO σ p) (rnFn σ f)
  | .handleErrorWith p f => .handleErrorWith (rnIO σ p) (rnFn σ f)
  | .attempt p => .attempt (rnIO σ p)
  | .start p => .start (rnIO σ p)
  | .evalOn p ec => .evalOn (rnIO σ p) ec
  | .onCancel p q => .onCancel (rnIO σ p) (rnIO σ q)
  | .racePair p q => .racePair (rnIO σ p) (rnIO σ q)
  | .uncancelable f => .uncancelable (rnFn σ f)
  | .ioCont f => .ioCont (rnFn σ f)
  | .blocking h f => .blocking h (rnFn σ f)
  | .local f => .local (rnFn σ f)
  | .unmaskRunLoop p m s => IO.applyPoll (rnIO σ p) (σ m s).1 (σ m s).2
  | io => io

/-- Rename the `Poll` handles of an effect. -/
def rnEffect (σ : PollRen) : UserEffect → UserEffect
  | .writeRef i x => .writeRef i (rnVal σ x)
  | .invokeCb s x => .invokeCb s (rnVal σ x)
  | .deferCb s x => .deferCb s (rnVal σ x)
  | .emit x => .emit (rnVal σ x)
  | .allocRef x => .allocRef (rnVal σ x)
  | .allocDeferred => .allocDeferred
  | .report e => .report e

/-- Rename the `Poll` handles of a call result. -/
def rnResult (σ : PollRen) (r : UserResult) : UserResult :=
  { effects := r.effects.map (rnEffect σ)
    out := match r.out with
      | .ret x => .ret (rnVal σ x)
      | .prog p => .prog (rnIO σ p)
      | .throw e => .throw e }

/-- Rename the `Poll` handles of a heap view. -/
def rnView (σ : PollRen) (v : View) : View :=
  { refs := v.refs.map (rnVal σ)
    outcomes := v.outcomes.map (Option.map (rnOutcome σ))
    deferreds := v.deferreds.map (Option.map (rnVal σ)) }

/-- Clause 6: user code treats `Poll` values as opaque. For each renaming `σ` that keeps
`IdPoll` (mask id `0`), a user call on renamed inputs (closure id, argument, view) gives the
renamed result. So user code cannot branch on a mask id or a fiber id of a `Poll`; it can only
pass a `Poll` on, store it, or apply it (`IO.applyPoll`).

Scala: `Poll[F]` is a trait with one method, `apply` (`kernel/shared/src/main/scala/cats/effect/kernel/Poll.scala`).
The `IOFiber` poll (`IOFiber.scala:562-567`) and `IdPoll` (`IO.scala:2391-2393`) are anonymous
classes in private code; the mask id and the fiber are private fields of the closure. So
well-typed code that does not use reflection or the `Object` methods (`eq`, `hashCode`,
`toString`, `getClass`) cannot read them. These methods have no behavior contract in Cats
Effect, so the model leaves them out. -/
def PollOpaque (env : UserEnv) : Prop :=
  ∀ σ : PollRen, (∀ s, (σ 0 s).1 = 0) → ∀ id, id % 2 = 0 → ∀ (arg : Val) (v : View),
    env.callV (rnId σ id) (rnVal σ arg) (rnView σ v) = rnResult σ (env.callV id arg v)

end WF

/-- Programs and user code that Scala can express (decision 27; clauses in the module doc).

* `lib id`: odd id `id` is a library closure of the model (a mirrored Cats Effect lambda).
* `H0`: the handles in the scope of the whole program (for example `Ref` cells that exist
  before it starts). Empty for a program that runs alone.
* The start program `p` passes `progOK` with `H0` (decidable).
* Each user function (even id) passes `CallOK` for each argument and each heap view.
* User code treats `Poll` values as opaque (`PollOpaque`, clause 6). -/
def WellFormed (lib : Nat → Bool) (H0 : List Handle) (env : UserEnv) (p : IO) : Prop :=
  WF.progOK lib (H0.contains ·) p = true ∧
  (∀ id, id % 2 = 0 → ∀ (arg : Val) (v : View), WF.CallOK lib H0 env id arg v) ∧
  WF.PollOpaque env

/-- `WellFormed` for plain `IO` programs: no library closures, no handles before the start. -/
abbrev WellFormedIO (env : UserEnv) (p : IO) : Prop := WellFormed (fun _ => false) [] env p

namespace WF

open Codec

/-! ## Lemmas for proofs of `WellFormed` -/

theorem reach_of_mem {v : View} {base : List Handle} {h : Handle} (hm : h ∈ base) :
    Reach v base h := .base hm

@[simp] theorem memOf_eq (R : Handle → Prop) (h : Handle) : memOf R h = true ↔ R h := by
  simp [memOf]

theorem cloOfId_libFn (c : Val) : cloOfId (2 * valToNat c + 1) = some c := by
  simp only [cloOfId]
  rw [show (2 * valToNat c + 1) / 2 = valToNat c by omega, natToVal_valToNat]

theorem cloOfId_userFn (c : Val) : cloOfId (2 * valToNat c) = some c := by
  simp only [cloOfId]
  rw [show (2 * valToNat c) / 2 = valToNat c by omega, natToVal_valToNat]

theorem captured_libFn (c : Val) : captured (2 * valToNat c + 1) = c.handles := by
  simp [captured, cloOfId_libFn]

theorem captured_userFn (c : Val) : captured (2 * valToNat c) = c.handles := by
  simp [captured, cloOfId_userFn]

theorem fnOK_userFn (lib : Nat → Bool) (mem : Handle → Bool) (c : Val) :
    fnOK lib mem (userFn c) = sub mem c.handles := by
  simp [fnOK, userFn, captured_userFn]

theorem fnOK_libFn (lib : Nat → Bool) (mem : Handle → Bool) (c : Val) :
    fnOK lib mem (libFn c) = (lib (2 * valToNat c + 1) && sub mem c.handles) := by
  simp only [fnOK, libFn, captured_libFn]
  rw [show (2 * valToNat c + 1) % 2 = 1 by omega]
  rfl

/-! ### Lemmas for clause 6 (`PollOpaque`) -/

theorem rnVal_of_hasPoll_false (σ : PollRen) : ∀ v : Val, hasPoll v = false → rnVal σ v = v := by
  intro v
  induction v <;> simp_all [hasPoll, rnVal]

@[simp] theorem hasPoll_rnVal (σ : PollRen) : ∀ v : Val, hasPoll (rnVal σ v) = hasPoll v := by
  intro v
  induction v <;> simp_all [hasPoll, rnVal]

theorem cloOfId_two_mul_add (c : Val) (b : Nat) (hb : b < 2) :
    cloOfId (2 * valToNat c + b) = some c := by
  rcases (show b = 0 ∨ b = 1 by omega) with rfl | rfl
  · exact cloOfId_userFn c
  · exact cloOfId_libFn c

theorem cloOfId_rnId (σ : PollRen) (id : Nat) :
    cloOfId (rnId σ id) = (cloOfId id).map (rnVal σ) := by
  unfold rnId
  cases hc : cloOfId id with
  | none => simp [hc]
  | some c =>
    by_cases hp : hasPoll c = true
    · simp only [hp, ite_true, Option.map_some]
      exact cloOfId_two_mul_add _ _ (Nat.mod_lt _ (by omega))
    · simp only [Bool.not_eq_true] at hp
      simp [hp, hc, rnVal_of_hasPoll_false σ c hp]

theorem rnId_mod_two (σ : PollRen) (id : Nat) : rnId σ id % 2 = id % 2 := by
  unfold rnId
  split
  · split <;> omega
  · rfl

/-- An id whose closure value holds no `Poll` keeps its id. -/
theorem rnId_of_noPoll (σ : PollRen) (id : Nat)
    (h : ∀ c, cloOfId id = some c → hasPoll c = false) : rnId σ id = id := by
  unfold rnId
  split
  · next c hc => simp [h c hc]
  · rfl

/-- `rnId_of_noPoll` with a decidable hypothesis. -/
theorem rnId_of_all (σ : PollRen) (id : Nat) (h : (cloOfId id).all (fun c => !hasPoll c) = true) :
    rnId σ id = id :=
  rnId_of_noPoll σ id fun c hc => by rw [hc] at h; simpa using h

/-- A user closure whose closure value holds no `Poll` does not change (decidable hypothesis). -/
theorem rnFn_user_of_all (σ : PollRen) (id : Nat)
    (h : (cloOfId id).all (fun c => !hasPoll c) = true) : rnFn σ (.user id) = .user id := by
  simp [rnFn, rnId_of_all σ id h]

/-- Only `id` itself renames to an id `j` whose closure value holds no `Poll`. -/
theorem eq_of_rnId_eq (σ : PollRen) {id j : Nat} (hj : ∀ c, cloOfId j = some c → hasPoll c = false)
    (h : rnId σ id = j) : id = j := by
  have hcl := cloOfId_rnId σ id
  rw [h] at hcl
  cases hc : cloOfId id with
  | none => rw [← h, rnId_of_noPoll σ id (by simp [hc])]
  | some c =>
    rw [hc] at hcl
    have := hj _ hcl
    simp only [hasPoll_rnVal] at this
    rw [← h, rnId_of_noPoll σ id (by intro c' hc'; rw [hc] at hc'; cases hc'; exact this)]

@[simp] theorem rnFn_userFn (σ : PollRen) (c : Val) : rnFn σ (userFn c) = userFn (rnVal σ c) := by
  simp only [rnFn, userFn, rnId, cloOfId_userFn]
  by_cases hp : hasPoll c = true
  · simp [hp]
  · simp only [Bool.not_eq_true] at hp
    simp [hp, rnVal_of_hasPoll_false σ c hp]

@[simp] theorem rnFn_libFn (σ : PollRen) (c : Val) : rnFn σ (libFn c) = libFn (rnVal σ c) := by
  simp only [rnFn, libFn, rnId, cloOfId_libFn]
  by_cases hp : hasPoll c = true
  · simp only [hp, ite_true]
    rw [show (2 * valToNat c + 1) % 2 = 1 by omega]
  · simp only [Bool.not_eq_true] at hp
    simp [hp, rnVal_of_hasPoll_false σ c hp]

/-- Clause 6 for user code that ignores its argument and its view. The result of even id `id`
is `f id`. The ids in `ks` have closure values without a `Poll`, and their results do not change
under a renaming; every other even id gives the same result `d`, which does not change either. -/
theorem pollOpaque_of_const (env : UserEnv) (f : Nat → UserResult) (ks : List Nat)
    (d : UserResult)
    (hcall : ∀ id arg v, id % 2 = 0 → env.callV id arg v = f id)
    (hks : ∀ k ∈ ks, (cloOfId k).all (fun c => !hasPoll c) = true)
    (hother : ∀ id, id % 2 = 0 → id ∉ ks → f id = d)
    (hfix : ∀ σ : PollRen, (∀ s, (σ 0 s).1 = 0) → ∀ k ∈ ks, rnResult σ (f k) = f k)
    (hd : ∀ σ : PollRen, (∀ s, (σ 0 s).1 = 0) → rnResult σ d = d) :
    PollOpaque env := by
  have hks : ∀ k ∈ ks, ∀ c, cloOfId k = some c → hasPoll c = false := fun k hk c hc => by
    have := hks k hk
    rw [hc] at this
    simpa using this
  intro σ hσ id hid arg v
  have hid' : rnId σ id % 2 = 0 := by rw [rnId_mod_two]; exact hid
  rw [hcall _ _ _ hid', hcall _ _ _ hid]
  by_cases hk : id ∈ ks
  · rw [rnId_of_noPoll σ id (hks id hk), hfix σ hσ id hk]
  · have hk' : rnId σ id ∉ ks := by
      intro hm
      exact hk (eq_of_rnId_eq σ (hks _ hm) rfl ▸ hm)
    rw [hother _ hid' hk', hother _ hid hk, hd σ hσ]

end WF

end CatsEffectInLean.Model

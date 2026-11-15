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
   the run loop (`review/2026-11-10-review-batch-2.md`, entry 5). The renaming also reaches the
   values that closure references (`Val.fn`) name (`rnRef`, review batch 9 W1).

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
  /-- A closure reference (`Val.fn`, decision 58). -/
  | fn (id : Nat)
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
  | .fn i => [.fn i]
  | _ => []

/-- The library of a model: `ok id` says that odd id `id` is a library closure that user code may
name in a program (a public operation builds it). Decision 58: closure references are `Val.fn`
values, so `WellFormed` follows them structurally (`Val.handles`); `fields` is **ignored** (kept
only until the other tracks drop it; see `wiki/semantics/outcome-equivalence.md`). -/
structure Lib where
  ok : Nat → Bool
  fields : Val → List Nat := fun _ => []

/-- A library given by `ok` only. -/
@[reducible] def Lib.idFree (ok : Nat → Bool) : Lib := { ok := ok }

/-- A `Nat → Bool` is a library. -/
instance : Coe (Nat → Bool) Lib := ⟨Lib.idFree⟩

namespace WF

open Codec

/-- Are all handles of `hs` held (`mem`)? -/
def sub (mem : Handle → Bool) (hs : List Handle) : Bool := hs.all mem

/-- The depth bound of `availD`: a user closure that captured a reference to a user closure that
captured ... Each nested id is strictly smaller than its parent (its code is inside the parent's
code), so real chains are short. At the bound `availD` answers "held only" (stricter). -/
def capDepth : Nat := 64

/-- The handles that the closure with id `id` captured: the handles of its closure value
(`Model/Codec.lean`), closure references (`Handle.fn`) included. A number that is not a closure
code captures nothing. `lib` is not used (decision 58: no field lists). -/
def cloHandles (id : Nat) : List Handle :=
  match cloOfId id with
  | some c => c.handles
  | none => []

/-- `cloHandles`, with the library of the statement (not used). -/
def captured (_lib : Lib) (id : Nat) : List Handle := cloHandles id

/-- The id of a closure reference. -/
def _root_.CatsEffectInLean.Model.Handle.fnId? : Handle → Option Nat
  | .fn k => some k
  | _ => none

/-- **The structural rule of decision 58.** A handle is available to code with held handles `mem`
if it is held, or if it is a reference to a user closure (even id) whose captured handles are all
available: user code makes new closures only through its own even ids, which carry their own
captured values. A library closure (odd id) or any other handle is available only if held. -/
def availD (mem : Handle → Bool) : Nat → Handle → Bool
  | 0, h => mem h
  | d + 1, h =>
    mem h ||
      match h.fnId? with
      | some k => k % 2 == 0 && (cloHandles k).all (availD mem d)
      | none => false

/-- `availD` with the depth bound. -/
def avail (mem : Handle → Bool) (h : Handle) : Bool := availD mem capDepth h

/-- All handles of `hs` are available. -/
def subA (mem : Handle → Bool) (hs : List Handle) : Bool := hs.all (avail mem)

/-- A program may name closure `id` only if all its captured handles are available. -/
def capOK (lib : Lib) (mem : Handle → Bool) (id : Nat) : Bool := subA mem (captured lib id)

/-- Clause 3 for runtime closures: only the ones that public operations build, with held
handles. -/
def rtOK (mem : Handle → Bool) : RtFn → Bool
  -- `fib.cancel` (`IOFiber.scala:197-201`), `fib.join` (`IOFiber.scala:203-207`)
  | .cancel t | .join t => mem (.fiber t)
  -- `deferred.get` (`IODeferred.scala:71`, `Syntax.lean`, `IO.deferredGetOf`)
  | .deferredDefer d | .deferredFlatten d => mem (.deferred d)
  -- `deferred.complete(a)` (`IODeferred.scala:62-69`)
  | .deferredComplete d v => mem (.deferred d) && subA mem v.handles
  -- `void` (`IO.scala:961-962`)
  | .voidK => true
  | _ => false

/-- Clause 3: a function in a program that user code built. -/
def fnOK (lib : Lib) (mem : Handle → Bool) : Fn → Bool
  | .user id => mem (.fn id) || ((id % 2 == 0 || lib.ok id) && capOK lib mem id)
  | .rt k => rtOK mem k

/-- Clauses 1-3: a program that user code built, with held handles `mem`. -/
def progOK (lib : Lib) (mem : Handle → Bool) : IO → Bool
  | .pure v => subA mem v.handles
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

/-- `avail` for a held-handle predicate (decision 58): held, or an own user closure. -/
def AvailP (R : Handle → Prop) (h : Handle) : Prop := avail (memOf R) h = true

/-- Clause 5 for the output. -/
def OutOK (lib : Lib) (R : Handle → Prop) : UserOut → Prop
  | .ret x => ∀ h ∈ x.handles, R h
  | .prog p => progOK lib (memOf R) p = true
  | .throw _ => True

/-- Clause 5: the effects in order, then the output. `nr`, `nd`: the ids of the next new `Ref`
and `Deferred` (`UserEffect.allocRef`, `allocDeferred`). A new cell is held after its
allocation. -/
def EffectsOK (lib : Lib) (out : UserOut) :
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
def ResultOK (lib : Lib) (R : Handle → Prop) (v : View) (r : UserResult) : Prop :=
  EffectsOK lib r.out R v.refs.length v.deferreds.length r.effects

/-- Clauses 4 and 5 for the call of user function `id` on `arg` in view `v`. `H0`: the handles
of the scope of the whole program. The held handles are the available ones (`AvailP`, decision 58):
the reachable handles, and references to own user closures that capture only available handles. -/
def CallOK (lib : Lib) (H0 : List Handle) (env : UserEnv) (id : Nat) (arg : Val)
    (v : View) : Prop :=
  let R := AvailP (Reach v (H0 ++ arg.handles ++ captured lib id))
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

/-- The fuel of `hasPollF`/`rnValF` (nesting depth of the values inside closure references; at the
bound the rest of the value counts as holding no `Poll` and stays unchanged, consistently). -/
def pollFuel : Nat := 4096

/-- `hasPoll` with fuel, also inside closure references (`Val.fn`, review batch 9 W1). -/
def hasPollF : Nat → Val → Bool
  | 0, _ => false
  | f + 1, .pair a b => hasPollF f a || hasPollF f b
  | f + 1, .left v | f + 1, .right v | f + 1, .some v | f + 1, .ocSucceeded v => hasPollF f v
  | _ + 1, .poll _ _ => true
  | f + 1, .fn k =>
    match cloOfId k with
    | some c => hasPollF f c
    | none => false
  | _ + 1, _ => false

/-- `rnVal` with fuel, also inside closure references: a reference to a closure whose value holds
a `Poll` becomes the reference to the renamed closure value (as `rnId`). -/
def rnValF : Nat → PollRen → Val → Val
  | 0, _, v => v
  | f + 1, σ, .pair a b => .pair (rnValF f σ a) (rnValF f σ b)
  | f + 1, σ, .left v => .left (rnValF f σ v)
  | f + 1, σ, .right v => .right (rnValF f σ v)
  | f + 1, σ, .some v => .some (rnValF f σ v)
  | f + 1, σ, .ocSucceeded v => .ocSucceeded (rnValF f σ v)
  | _ + 1, σ, .poll m s => .poll (σ m s).1 (σ m s).2
  | f + 1, σ, .fn k =>
    match cloOfId k with
    | some c => if hasPollF f c then .fn (2 * valToNat (rnValF f σ c) + k % 2) else .fn k
    | none => .fn k
  | _ + 1, _, v => v

/-- Does the closure that a reference names hold a `Poll` (review batch 9 W1)? -/
def hasPollRef (k : Nat) : Bool :=
  match cloOfId k with
  | some c => hasPollF pollFuel c
  | none => false

/-- The reference to the renamed closure value. -/
def rnRef (σ : PollRen) (k : Nat) : Nat :=
  match cloOfId k with
  | some c => if hasPollF pollFuel c then 2 * valToNat (rnValF pollFuel σ c) + k % 2 else k
  | none => k

/-- Does a value hold a `Poll` handle (also inside a closure reference)? -/
def hasPoll : Val → Bool
  | .pair a b => hasPoll a || hasPoll b
  | .left v | .right v | .some v | .ocSucceeded v => hasPoll v
  | .poll _ _ => true
  | .fn k => hasPollRef k
  | _ => false

/-- Rename the `Poll` handles of a value (also inside closure references). -/
def rnVal (σ : PollRen) : Val → Val
  | .pair a b => .pair (rnVal σ a) (rnVal σ b)
  | .left v => .left (rnVal σ v)
  | .right v => .right (rnVal σ v)
  | .some v => .some (rnVal σ v)
  | .ocSucceeded v => .ocSucceeded (rnVal σ v)
  | .poll m s => .poll (σ m s).1 (σ m s).2
  | .fn k => .fn (rnRef σ k)
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

* `lib.ok id`: odd id `id` is a library closure that user code may name in a program (a public
  operation builds it). Closure references are `Val.fn` values, which `WellFormed` follows
  structurally (decision 58; `lib.fields` is ignored).
* `H0`: the handles in the scope of the whole program (for example `Ref` cells that exist
  before it starts). Empty for a program that runs alone.
* The start program `p` passes `progOK` with `H0` (decidable).
* Each user function (even id) passes `CallOK` for each argument and each heap view.
* User code treats `Poll` values as opaque (`PollOpaque`, clause 6). -/
def WellFormed (lib : Lib) (H0 : List Handle) (env : UserEnv) (p : IO) : Prop :=
  WF.progOK lib (H0.contains ·) p = true ∧
  (∀ id, id % 2 = 0 → ∀ (arg : Val) (v : View), WF.CallOK lib H0 env id arg v) ∧
  WF.PollOpaque env

/-- `WellFormed` for plain `IO` programs: no library closures, no handles before the start. -/
abbrev WellFormedIO (env : UserEnv) (p : IO) : Prop := WellFormed (Lib.idFree fun _ => false) [] env p

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

theorem captured_eq (lib : Lib) (id : Nat) : captured lib id = cloHandles id := rfl

theorem cloHandles_libFn (c : Val) : cloHandles (2 * valToNat c + 1) = c.handles := by
  simp [cloHandles, cloOfId_libFn]

theorem cloHandles_userFn (c : Val) : cloHandles (2 * valToNat c) = c.handles := by
  simp [cloHandles, cloOfId_userFn]

/-- A number that is not a closure code captures nothing. -/
theorem cloHandles_of_none (id : Nat) (h : cloOfId id = none) : cloHandles id = [] := by
  simp [cloHandles, h]

theorem captured_of_none (lib : Lib) (id : Nat) (h : cloOfId id = none) : captured lib id = [] :=
  cloHandles_of_none id h

theorem capOK_of_none (lib : Lib) (mem : Handle → Bool) (id : Nat) (h : cloOfId id = none) :
    capOK lib mem id = true := by
  simp [capOK, captured, cloHandles_of_none id h, subA]

theorem captured_libFn (lib : Lib) (c : Val) : captured lib (2 * valToNat c + 1) = c.handles :=
  cloHandles_libFn c

theorem captured_userFn (lib : Lib) (c : Val) : captured lib (2 * valToNat c) = c.handles :=
  cloHandles_userFn c

/-- A held handle is available. -/
theorem avail_of_mem {mem : Handle → Bool} {h : Handle} (hm : mem h = true) : avail mem h = true := by
  show availD mem (63 + 1) h = true
  rw [availD, hm, Bool.true_or]

/-- A handle that is not a closure reference is available only if held. -/
theorem avail_iff_of_not_fn (mem : Handle → Bool) (h : Handle) (hh : ∀ k, h ≠ .fn k) :
    avail mem h = mem h := by
  show availD mem (63 + 1) h = mem h
  rw [availD]
  cases h with
  | fn k => exact absurd rfl (hh k)
  | _ => simp [Handle.fnId?]

/-- A reference to a library closure (odd id) is available only if held: user code cannot make
one (decision 58). -/
theorem avail_fn_odd (mem : Handle → Bool) (k : Nat) (hk : k % 2 = 1) :
    avail mem (.fn k) = mem (.fn k) := by
  show availD mem (63 + 1) (.fn k) = mem (.fn k)
  rw [availD]
  simp [Handle.fnId?, hk]

/-- An available reference to a user closure that is not held: every handle it captured is
available (one level of the rule; the depth bound only makes it stricter). -/
theorem avail_fn_even_captured (mem : Handle → Bool) (d k : Nat) (h : availD mem (d + 1) (.fn k) = true)
    (hn : mem (.fn k) = false) : k % 2 = 0 ∧ ∀ h' ∈ cloHandles k, availD mem d h' = true := by
  rw [availD] at h
  simp only [hn, Bool.false_or, Handle.fnId?, Bool.and_eq_true, beq_iff_eq, List.all_eq_true] at h
  exact h

@[simp] theorem subA_nil (mem : Handle → Bool) : subA mem [] = true := rfl

@[simp] theorem subA_cons (mem : Handle → Bool) (h : Handle) (hs : List Handle) :
    subA mem (h :: hs) = (avail mem h && subA mem hs) := rfl

theorem subA_append (mem : Handle → Bool) (a b : List Handle) :
    subA mem (a ++ b) = (subA mem a && subA mem b) := by simp [subA, List.all_append]

@[simp] theorem avail_ref (mem : Handle → Bool) (i : Nat) : avail mem (.ref i) = mem (.ref i) :=
  avail_iff_of_not_fn mem _ (by intro k h; cases h)
@[simp] theorem avail_fiber (mem : Handle → Bool) (i : Nat) : avail mem (.fiber i) = mem (.fiber i) :=
  avail_iff_of_not_fn mem _ (by intro k h; cases h)
@[simp] theorem avail_deferred (mem : Handle → Bool) (i : Nat) : avail mem (.deferred i) = mem (.deferred i) :=
  avail_iff_of_not_fn mem _ (by intro k h; cases h)
@[simp] theorem avail_poll (mem : Handle → Bool) (m i : Nat) : avail mem (.poll m i) = mem (.poll m i) :=
  avail_iff_of_not_fn mem _ (by intro k h; cases h)
@[simp] theorem avail_cont (mem : Handle → Bool) (i : Nat) : avail mem (.cont i) = mem (.cont i) :=
  avail_iff_of_not_fn mem _ (by intro k h; cases h)

/-- `capOK` unfolded (for a library given by `ok` only, as before decision 58). -/
theorem capOK_coe (f : Nat → Bool) (mem : Handle → Bool) (id : Nat) :
    capOK (f : Lib) mem id = subA mem (match cloOfId id with | some c => c.handles | none => []) := rfl

theorem captured_coe (f : Nat → Bool) (id : Nat) :
    captured (f : Lib) id = (match cloOfId id with | some c => c.handles | none => []) := rfl

/-- A closure without captured handles passes `capOK`. -/
theorem capOK_coe_of_nil (f : Nat → Bool) (mem : Handle → Bool) (id : Nat)
    (h : (match cloOfId id with | some c => c.handles | none => []) = []) : capOK (f : Lib) mem id = true := by
  rw [capOK_coe, h]; rfl

/-- `subA` holds if all handles are held. -/
theorem subA_of_sub {mem : Handle → Bool} {hs : List Handle} (h : sub mem hs = true) : subA mem hs = true := by
  simp only [sub, subA, List.all_eq_true] at *
  exact fun x hx => avail_of_mem (h x hx)

theorem availP_iff_of_not_fn (R : Handle → Prop) (h : Handle) (hh : ∀ k, h ≠ .fn k) :
    AvailP R h ↔ R h := by
  simp [AvailP, avail_iff_of_not_fn _ h hh]

@[simp] theorem availP_ref (R : Handle → Prop) (i : Nat) : AvailP R (.ref i) ↔ R (.ref i) :=
  availP_iff_of_not_fn R _ (by intro k h; cases h)
@[simp] theorem availP_fiber (R : Handle → Prop) (i : Nat) : AvailP R (.fiber i) ↔ R (.fiber i) :=
  availP_iff_of_not_fn R _ (by intro k h; cases h)
@[simp] theorem availP_deferred (R : Handle → Prop) (i : Nat) : AvailP R (.deferred i) ↔ R (.deferred i) :=
  availP_iff_of_not_fn R _ (by intro k h; cases h)
@[simp] theorem availP_poll (R : Handle → Prop) (m i : Nat) : AvailP R (.poll m i) ↔ R (.poll m i) :=
  availP_iff_of_not_fn R _ (by intro k h; cases h)
@[simp] theorem availP_cont (R : Handle → Prop) (i : Nat) : AvailP R (.cont i) ↔ R (.cont i) :=
  availP_iff_of_not_fn R _ (by intro k h; cases h)

/-- `AvailP` holds for a held handle. -/
theorem availP_of {R : Handle → Prop} {h : Handle} (hr : R h) : AvailP R h :=
  avail_of_mem (by simpa [memOf] using hr)

theorem capOK_of_sub (lib : Lib) (mem : Handle → Bool) (id : Nat) (h : sub mem (cloHandles id) = true) :
    capOK lib mem id = true := subA_of_sub h

theorem fnOK_userFn (lib : Lib) (mem : Handle → Bool) (c : Val) :
    fnOK lib mem (userFn c) = (mem (.fn (2 * valToNat c)) || subA mem c.handles) := by
  simp only [fnOK, userFn, capOK, captured, cloHandles_userFn]
  rw [show 2 * valToNat c % 2 = 0 by omega]
  simp

theorem fnOK_libFn (lib : Nat → Bool) (mem : Handle → Bool) (c : Val) :
    fnOK (lib : Lib) mem (libFn c) =
      (mem (.fn (2 * valToNat c + 1)) || (lib (2 * valToNat c + 1) && subA mem c.handles)) := by
  simp only [fnOK, libFn, capOK, captured, cloHandles_libFn]
  rw [show (2 * valToNat c + 1) % 2 = 1 by omega]
  rfl

/-- `fnOK` of a user closure whose captured handles are available (a conditional `simp` lemma). -/
theorem fnOK_userFn_of (lib : Lib) (mem : Handle → Bool) (c : Val) (h : subA mem c.handles = true) :
    fnOK lib mem (userFn c) = true := by
  rw [fnOK_userFn, h, Bool.or_true]

/-- `fnOK` of a library closure that `lib` allows, with available captured handles. -/
theorem fnOK_libFn_of (lib : Nat → Bool) (mem : Handle → Bool) (c : Val)
    (hl : lib (2 * valToNat c + 1) = true) (h : subA mem c.handles = true) :
    fnOK (lib : Lib) mem (libFn c) = true := by
  rw [fnOK_libFn, hl, h]; simp

/-! ### Monotonicity: more held handles keep every clause -/

theorem availD_mono {m1 m2 : Handle → Bool} (hm : ∀ h, m1 h = true → m2 h = true) :
    ∀ d h, availD m1 d h = true → availD m2 d h = true
  | 0, h, H => hm h H
  | d + 1, h, H => by
    rw [availD] at H ⊢
    simp only [Bool.or_eq_true] at H ⊢
    rcases H with H | H
    · exact .inl (hm h H)
    · right
      revert H
      cases h.fnId? with
      | none => simp
      | some k =>
        simp only [Bool.and_eq_true, List.all_eq_true]
        exact fun ⟨hk, hall⟩ => ⟨hk, fun x hx => availD_mono hm d x (hall x hx)⟩

theorem avail_mono {m1 m2 : Handle → Bool} (hm : ∀ h, m1 h = true → m2 h = true) (h : Handle)
    (H : avail m1 h = true) : avail m2 h = true := availD_mono hm _ h H

theorem subA_mono {m1 m2 : Handle → Bool} (hm : ∀ h, m1 h = true → m2 h = true) (hs : List Handle)
    (H : subA m1 hs = true) : subA m2 hs = true := by
  simp only [subA, List.all_eq_true] at *
  exact fun x hx => avail_mono hm x (H x hx)

theorem fnOK_mono (lib : Lib) {m1 m2 : Handle → Bool} (hm : ∀ h, m1 h = true → m2 h = true) (f : Fn)
    (H : fnOK lib m1 f = true) : fnOK lib m2 f = true := by
  cases f with
  | user id =>
    simp only [fnOK, capOK, Bool.or_eq_true, Bool.and_eq_true] at H ⊢
    rcases H with H | ⟨h1, h2⟩
    · exact .inl (hm _ H)
    · exact .inr ⟨h1, subA_mono hm _ h2⟩
  | rt k =>
    simp only [fnOK] at H ⊢
    cases k <;> simp only [rtOK, Bool.and_eq_true] at H ⊢ <;>
      first | exact hm _ H | exact ⟨hm _ H.1, subA_mono hm _ H.2⟩ | exact H

theorem progOK_mono (lib : Lib) {m1 m2 : Handle → Bool} (hm : ∀ h, m1 h = true → m2 h = true) :
    ∀ p : IO, progOK lib m1 p = true → progOK lib m2 p = true
  | .pure v, H => subA_mono hm _ H
  | .error _, _ | .realTime, _ | .monotonic, _ | .readEC, _ | .canceled, _ | .cede, _ | .sleep _, _
  | .ioTrace, _ | .readRT, _ => rfl
  | .delay f, H | .uncancelable f, H | .ioCont f, H | .blocking _ f, H | .local f, H =>
    fnOK_mono lib hm f H
  | .map p f, H | .flatMap p f, H | .handleErrorWith p f, H => by
    simp only [progOK, Bool.and_eq_true] at H ⊢
    exact ⟨progOK_mono lib hm p H.1, fnOK_mono lib hm f H.2⟩
  | .attempt p, H | .start p, H | .evalOn p _, H => progOK_mono lib hm p H
  | .onCancel p q, H | .racePair p q, H => by
    simp only [progOK, Bool.and_eq_true] at H ⊢
    exact ⟨progOK_mono lib hm p H.1, progOK_mono lib hm q H.2⟩
  | .unmaskRunLoop p m s, H => by
    simp only [progOK, Bool.and_eq_true] at H ⊢
    exact ⟨⟨H.1.1, hm _ H.1.2⟩, progOK_mono lib hm p H.2⟩
  | .contGet s, H => hm _ H
  | .endFiber, H => H

/-- `ResultOK` is monotone in the held handles. -/
theorem effectsOK_mono (lib : Lib) (out : UserOut) :
    ∀ (es : List UserEffect) (R1 R2 : Handle → Prop) (nr nd : Nat), (∀ h, R1 h → R2 h) →
      EffectsOK lib out R1 nr nd es → EffectsOK lib out R2 nr nd es
  | [], R1, R2, _, _, hR, H => by
    cases out with
    | ret x => exact fun h hh => hR h (H h hh)
    | prog p => exact progOK_mono lib (fun h => by simpa [memOf] using hR h) p H
    | throw _ => trivial
  | e :: es, R1, R2, nr, nd, hR, H => by
    cases e with
    | writeRef i x => exact ⟨hR _ H.1, fun h hh => hR h (H.2.1 h hh), effectsOK_mono lib out es R1 R2 nr nd hR H.2.2⟩
    | invokeCb s x => exact ⟨hR _ H.1, fun h hh => hR h (H.2.1 h hh), effectsOK_mono lib out es R1 R2 nr nd hR H.2.2⟩
    | deferCb s x => exact ⟨hR _ H.1, fun h hh => hR h (H.2.1 h hh), effectsOK_mono lib out es R1 R2 nr nd hR H.2.2⟩
    | emit x => exact ⟨fun h hh => hR h (H.1 h hh), effectsOK_mono lib out es R1 R2 nr nd hR H.2⟩
    | allocRef x =>
      exact ⟨fun h hh => hR h (H.1 h hh), effectsOK_mono lib out es _ _ (nr + 1) nd
        (fun h hh => hh.elim (fun a => .inl (hR h a)) .inr) H.2⟩
    | allocDeferred =>
      exact effectsOK_mono lib out es _ _ nr (nd + 1) (fun h hh => hh.elim (fun a => .inl (hR h a)) .inr) H
    | report _ => exact effectsOK_mono lib out es R1 R2 nr nd hR H

theorem resultOK_mono (lib : Lib) {R1 R2 : Handle → Prop} (hR : ∀ h, R1 h → R2 h) (v : View)
    (r : UserResult) (H : ResultOK lib R1 v r) : ResultOK lib R2 v r :=
  effectsOK_mono lib r.out r.effects R1 R2 _ _ hR H

theorem agree_availP (R : Handle → Prop) (v w : View) : Agree (AvailP R) v w ↔ Agree R v w := by
  simp [Agree]

/-- `CallOK` from the reachable handles only (no own closures): the form of the proofs before
decision 58. -/
theorem callOK_of_reach {lib : Lib} {H0 : List Handle} {env : UserEnv} {id : Nat} {arg : Val} {v : View}
    (hag : ∀ w, Agree (Reach v (H0 ++ arg.handles ++ captured lib id)) v w → env.callV id arg w = env.callV id arg v)
    (hres : ResultOK lib (Reach v (H0 ++ arg.handles ++ captured lib id)) v (env.callV id arg v)) :
    CallOK lib H0 env id arg v :=
  ⟨fun w hw => hag w ((agree_availP _ v w).1 hw), resultOK_mono lib (fun _ h => availP_of h) v _ hres⟩

/-! ### Lemmas for clause 6 (`PollOpaque`) -/

theorem rnValF_of_hasPollF_false (σ : PollRen) : ∀ (f : Nat) (v : Val), hasPollF f v = false → rnValF f σ v = v
  | 0, _, _ => rfl
  | f + 1, v, h => by
    cases v with
    | pair a b =>
      simp only [hasPollF, Bool.or_eq_false_iff] at h
      simp only [rnValF, rnValF_of_hasPollF_false σ f a h.1, rnValF_of_hasPollF_false σ f b h.2]
    | left v => simp only [hasPollF] at h; simp only [rnValF, rnValF_of_hasPollF_false σ f v h]
    | right v => simp only [hasPollF] at h; simp only [rnValF, rnValF_of_hasPollF_false σ f v h]
    | some v => simp only [hasPollF] at h; simp only [rnValF, rnValF_of_hasPollF_false σ f v h]
    | ocSucceeded v => simp only [hasPollF] at h; simp only [rnValF, rnValF_of_hasPollF_false σ f v h]
    | poll m s => simp [hasPollF] at h
    | fn k =>
      simp only [rnValF]
      cases hc : cloOfId k with
      | none => rfl
      | some c => simp only [hasPollF, hc] at h; simp [h]
    | _ => rfl

theorem cloOfId_two_mul_add' (c : Val) (b : Nat) (hb : b < 2) :
    cloOfId (2 * valToNat c + b) = some c := by
  rcases (show b = 0 ∨ b = 1 by omega) with rfl | rfl
  · simp only [cloOfId]; rw [show (2 * valToNat c + 0) / 2 = valToNat c by omega, natToVal_valToNat]
  · simp only [cloOfId]; rw [show (2 * valToNat c + 1) / 2 = valToNat c by omega, natToVal_valToNat]

theorem hasPollF_rnValF (σ : PollRen) : ∀ (f : Nat) (v : Val), hasPollF f (rnValF f σ v) = hasPollF f v
  | 0, _ => rfl
  | f + 1, v => by
    cases v with
    | pair a b => simp only [rnValF, hasPollF, hasPollF_rnValF σ f a, hasPollF_rnValF σ f b]
    | left v => simp only [rnValF, hasPollF, hasPollF_rnValF σ f v]
    | right v => simp only [rnValF, hasPollF, hasPollF_rnValF σ f v]
    | some v => simp only [rnValF, hasPollF, hasPollF_rnValF σ f v]
    | ocSucceeded v => simp only [rnValF, hasPollF, hasPollF_rnValF σ f v]
    | poll m s => rfl
    | fn k =>
      cases hc : cloOfId k with
      | none => simp only [rnValF, hasPollF, hc]
      | some c =>
        by_cases hp : hasPollF f c = true
        · simp only [rnValF, hc, hp, ite_true, hasPollF]
          rw [cloOfId_two_mul_add' _ _ (Nat.mod_lt _ (by omega))]
          simp only [hasPollF_rnValF σ f c, hp]
        · simp only [Bool.not_eq_true] at hp
          simp only [rnValF, hc, hp, Bool.false_eq_true, ite_false, hasPollF]
    | _ => rfl

theorem rnVal_of_hasPoll_false (σ : PollRen) : ∀ v : Val, hasPoll v = false → rnVal σ v = v := by
  intro v
  induction v with
  | fn k =>
    intro h
    simp only [hasPoll, hasPollRef] at h
    simp only [rnVal, rnRef]
    cases hc : cloOfId k with
    | none => rfl
    | some c => rw [hc] at h; simp [h]
  | _ => simp_all [hasPoll, rnVal]

@[simp] theorem hasPoll_rnVal (σ : PollRen) : ∀ v : Val, hasPoll (rnVal σ v) = hasPoll v := by
  intro v
  induction v with
  | fn k =>
    simp only [rnVal, hasPoll, hasPollRef, rnRef]
    cases hc : cloOfId k with
    | none => simp [hc]
    | some c =>
      by_cases hp : hasPollF pollFuel c = true
      · simp only [hp, ite_true]
        rw [cloOfId_two_mul_add' _ _ (Nat.mod_lt _ (by omega))]
        simp only [hasPollF_rnValF, hp]
      · simp only [Bool.not_eq_true] at hp
        simp [hc, hp]
  | _ => simp_all [hasPoll, rnVal]

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

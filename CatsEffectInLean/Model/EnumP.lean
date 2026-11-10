import CatsEffectInLean.Model.Outcomes

/-!
# Exact outcome sets with preemption (`outcomesP`, `EqvP`)

The preemptive scheduler (`CatsEffectInLean/Model/SchedP.lean`) keeps no task count and no
schedule log. So a program that always terminates has a finite set of reachable states, also
over unbounded fuel and unbounded choice lists. This file computes that set and uses it to
decide `outcomesP` exactly (not only a lower bound as `Enum.lean`).

* `ClosedP S`: every state of `S` that can go on has all its successors (`succsP`) in `S`.
* `runSchedStateP_mem`: a closed `S` that holds the start state holds every run.
* `exploreP`: a breadth-first search from `Sched.init` that records, for each state, the
  choice list that reaches it (reversed).
* `pathsOK`: each result state of the search is the result of its recorded choice list.
* `outcomesP_iff_of_exactP`: if the search result is closed, holds the start state, and its
  paths are correct, then `outcomesP io o ↔ o` is an observation of a listed state.
* `eqvP_of_checkEqvP`, `not_eqvP_of_checkNotEqvP`: decide `EqvP` (or its negation) for two
  concrete programs. `decide +kernel` evaluates the checks.

The search has a step bound. If the bound is too small, the result is not closed and the
check gives `false`; it never gives a wrong `true`.
-/

namespace CatsEffectInLean.Model

section
variable {M : Type} [DecidableEq M] (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- A cheap part of a state: run-loop counters, list lengths, halt, and per-fiber tags. Equal
states have equal keys. Kernel evaluation compares keys first, so most unequal states are
told apart without a full structural comparison. -/
def Sched.key (s : Sched M) :
    Option (Nat × Nat × Nat × Nat) × Nat × Nat × Bool × List (Nat × Nat × Bool × Bool) :=
  (s.cur.map (fun l => (l.cancelIters, l.autoCedeIters, l.exec.fib.id, l.exec.fib.conts.length)),
   s.heap.ready.length, s.heap.out.length, s.halt.isSome,
   s.fibers.map (fun f => (f.resumeTag.toNat, f.conts.length, f.outcome.isSome, f.canceled)))

/-- Equality with a cheap pre-test on `Sched.key`. -/
def Sched.fastEq (a b : Sched M) : Bool := a.key == b.key && a == b

/-- `t ∈ S`, with `Sched.fastEq`. -/
def memFast (t : Sched M) (S : List (Sched M)) : Bool := S.any (Sched.fastEq t)

theorem memFast_iff (t : Sched M) (S : List (Sched M)) : memFast t S = true ↔ t ∈ S := by
  simp only [memFast, List.any_eq_true, Sched.fastEq, Bool.and_eq_true, beq_iff_eq]
  constructor
  · rintro ⟨x, hx, -, rfl⟩; exact hx
  · intro h; exact ⟨t, h, rfl, rfl⟩

/-- `S` is closed under the preemptive scheduler. -/
def ClosedP (S : List (Sched M)) : Bool :=
  S.all fun s => s.halt.isSome || (succsP cfg mm env s).all (fun t => memFast t S)

theorem runSchedStateP_mem {S : List (Sched M)} (hS : ClosedP cfg mm env S = true) :
    ∀ (fuel : Nat) (cs : List PChoice) (s : Sched M), s ∈ S →
      runSchedStateP cfg mm env fuel cs s ∈ S
  | 0, _, _, h => h
  | f + 1, cs, s, h => by
    cases hh : s.halt with
    | some _ => simp only [runSchedStateP, hh]; exact h
    | none =>
      simp only [runSchedStateP, hh]
      apply runSchedStateP_mem hS
      have hs := List.all_eq_true.mp hS s h
      simp only [hh, Option.isSome_none, Bool.false_or, List.all_eq_true, memFast_iff] at hs
      exact hs _ (tickP_mem_succsP cfg mm env s _)

/-- With a closed `S` that holds the start state, every observation is one of a state in
`S`. -/
theorem outcomesP_sub_closed {S : List (Sched M)} {io : IO} {o : Obs}
    (hS : ClosedP cfg mm env S = true) (h0 : Sched.init mm io ∈ S)
    (h : outcomesP cfg mm env io o) : o ∈ S.filterMap Sched.obs := by
  obtain ⟨fuel, cs, h⟩ := h
  exact List.mem_filterMap.mpr ⟨_, runSchedStateP_mem cfg mm env hS fuel cs _ h0, h⟩

/-- One search step from state `s` with reversed path `p`: the successors that are not in
`seen`, without duplicates. -/
def exploreNew (seen : List (Sched M × List PChoice)) (s : Sched M) (p : List PChoice) :
    List (Sched M × List PChoice) :=
  let cands := (PChoice.preempt :: (List.range (max 1 s.heap.ready.length)).map .pick).map
    (fun c => (s.tickP cfg mm env c, c :: p))
  cands.foldl (fun acc tq =>
    if acc.any (fun x => x.1.fastEq tq.1) || seen.any (fun x => x.1.fastEq tq.1) then acc
    else acc ++ [tq]) []

/-- Breadth-first search: at most `bound` expansions. `todo` is the work list, `seen` all
states found so far, each with its reversed choice list. -/
def exploreGo : (bound : Nat) → List (Sched M × List PChoice) → List (Sched M × List PChoice) →
    List (Sched M × List PChoice)
  | 0, _, seen => seen
  | _ + 1, [], seen => seen
  | n + 1, (s, p) :: todo, seen =>
    if s.halt.isSome then exploreGo n todo seen
    else
      let new := exploreNew cfg mm env seen s p
      exploreGo n (todo ++ new) (seen ++ new)

/-- The states that `io` can reach (if `bound` is large enough), with their choice lists. -/
def exploreP (bound : Nat) (io : IO) : List (Sched M × List PChoice) :=
  let s0 := Sched.init mm io
  exploreGo cfg mm env bound [(s0, [])] [(s0, [])]

/-- Each listed state with an observation is the result of its (reversed) choice list. -/
def pathsOK (io : IO) (L : List (Sched M × List PChoice)) : Bool :=
  L.all fun x =>
    match x.1.obs with
    | none => true
    | some o => runObsP cfg mm env x.2.length x.2.reverse io == some o

/-- The full check: `L` is closed, holds the start state, and its paths are correct. -/
def exactP (io : IO) (L : List (Sched M × List PChoice)) : Bool :=
  ClosedP cfg mm env (L.map Prod.fst) && (L.map Prod.fst).contains (Sched.init mm io) &&
    pathsOK cfg mm env io L

/-- The observations of the listed states. -/
def obsList (L : List (Sched M × List PChoice)) : List Obs :=
  (L.map Prod.fst).filterMap Sched.obs

theorem outcomesP_iff_of_exactP {io : IO} {L : List (Sched M × List PChoice)}
    (h : exactP cfg mm env io L = true) (o : Obs) :
    outcomesP cfg mm env io o ↔ o ∈ obsList L := by
  simp only [exactP, Bool.and_eq_true, List.contains_iff_mem] at h
  obtain ⟨⟨hS, h0⟩, hp⟩ := h
  constructor
  · exact outcomesP_sub_closed cfg mm env hS h0
  · intro ho
    simp only [obsList, List.mem_filterMap, List.mem_map] at ho
    obtain ⟨s, ⟨x, hx, rfl⟩, hso⟩ := ho
    have hx' := List.all_eq_true.mp hp x hx
    rw [hso] at hx'
    exact ⟨x.2.length, x.2.reverse, by simpa using hx'⟩

/-- `EqvP p q` in the search bound: both searches are exact and give the same observations. -/
def checkEqvP (bound : Nat) (p q : IO) : Bool :=
  let lp := exploreP cfg mm env bound p
  let lq := exploreP cfg mm env bound q
  exactP cfg mm env p lp && exactP cfg mm env q lq &&
    (obsList lp).all (fun o => (obsList lq).contains o) &&
    (obsList lq).all (fun o => (obsList lp).contains o)

theorem eqvP_of_checkEqvP {bound : Nat} {p q : IO} (h : checkEqvP cfg mm env bound p q = true) :
    EqvP cfg mm env p q := by
  simp only [checkEqvP, Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at h
  obtain ⟨⟨⟨hp, hq⟩, h1⟩, h2⟩ := h
  intro o
  rw [outcomesP_iff_of_exactP cfg mm env hp, outcomesP_iff_of_exactP cfg mm env hq]
  exact ⟨h1 o, h2 o⟩

/-- `¬ EqvP p q`: both searches are exact and the observation sets differ. -/
def checkNotEqvP (bound : Nat) (p q : IO) : Bool :=
  let lp := exploreP cfg mm env bound p
  let lq := exploreP cfg mm env bound q
  exactP cfg mm env p lp && exactP cfg mm env q lq &&
    !((obsList lp).all (fun o => (obsList lq).contains o) &&
      (obsList lq).all (fun o => (obsList lp).contains o))

theorem not_eqvP_of_checkNotEqvP {bound : Nat} {p q : IO}
    (h : checkNotEqvP cfg mm env bound p q = true) : ¬ EqvP cfg mm env p q := by
  simp only [checkNotEqvP, Bool.and_eq_true, Bool.not_eq_true'] at h
  obtain ⟨⟨hp, hq⟩, hne⟩ := h
  intro he
  have hiff : ∀ o, o ∈ obsList (exploreP cfg mm env bound p) ↔
      o ∈ obsList (exploreP cfg mm env bound q) := fun o => by
    rw [← outcomesP_iff_of_exactP cfg mm env hp, ← outcomesP_iff_of_exactP cfg mm env hq]
    exact he o
  have : ((obsList (exploreP cfg mm env bound p)).all
      (fun o => (obsList (exploreP cfg mm env bound q)).contains o) &&
    (obsList (exploreP cfg mm env bound q)).all
      (fun o => (obsList (exploreP cfg mm env bound p)).contains o)) = true := by
    simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem]
    exact ⟨fun o h => (hiff o).1 h, fun o h => (hiff o).2 h⟩
  rw [this] at hne
  cases hne

/-- A tool for proofs where the program has free variables (no `decide`): the search result as
a table. Entry `i`: the choice list (in run order) of state `i`, whether it halted, and the
indices of its successors (`succsP` order: `preempt`, then `pick 0`, `pick 1`, ...). `none`
for a successor that is not in the list. Compute it with `#eval` on a closed instance. -/
def exploreTable (bound : Nat) (io : IO) : List (List PChoice × Bool × List (Option Nat)) :=
  let l := exploreP cfg mm env bound io
  let sts := l.map Prod.fst
  l.map fun x =>
    (x.2.reverse, x.1.halt.isSome,
      if x.1.halt.isSome then [] else (succsP cfg mm env x.1).map (fun t => sts.idxOf? t))

omit [DecidableEq M] in
/-- With at most one ready task, every `pick m` is `pick 0`. -/
theorem tickP_pick_single (s : Sched M) (m : Nat) (h : s.heap.ready.length ≤ 1) :
    s.tickP cfg mm env (.pick m) = s.tickP cfg mm env (.pick 0) := by
  have h1 : max 1 s.heap.ready.length = 1 := by omega
  simp only [Sched.tickP, h1, Nat.mod_one]

omit [DecidableEq M] in
/-- Symbolic closure (for programs with free variables): a family `st 0, ..., st (n - 1)` of
states, with the successor index `np i` for `preempt` and `nk i` for every `pick`. Then every
run from a family state ends in a family state. -/
theorem runSchedStateP_family (n : Nat) (st : Nat → Sched M) (np nk : Nat → Nat)
    (hn : ∀ i, i < n → np i < n ∧ nk i < n)
    (hpre : ∀ i, i < n → (st i).halt = none → (st i).tickP cfg mm env .preempt = st (np i))
    (hpick : ∀ i, i < n → (st i).halt = none → ∀ m,
      (st i).tickP cfg mm env (.pick m) = st (nk i)) :
    ∀ (fuel : Nat) (cs : List PChoice) (i : Nat), i < n →
      ∃ j, j < n ∧ runSchedStateP cfg mm env fuel cs (st i) = st j := by
  intro fuel
  induction fuel with
  | zero => intro _ i hi; exact ⟨i, hi, rfl⟩
  | succ f ih =>
    intro cs i hi
    cases hh : (st i).halt with
    | some _ => exact ⟨i, hi, by simp [runSchedStateP, hh]⟩
    | none =>
      simp only [runSchedStateP, hh]
      cases hc : cs.headD (.pick 0) with
      | preempt => rw [hpre i hi hh]; exact ih _ _ (hn i hi).1
      | pick m => rw [hpick i hi hh m]; exact ih _ _ (hn i hi).2

omit [DecidableEq M] in
/-- The outcome set of a family whose start state is `st 0`: each observation is one of a
family state. -/
theorem outcomesP_family {io : IO} {o : Obs} (n : Nat) (st : Nat → Sched M) (np nk : Nat → Nat)
    (hn : ∀ i, i < n → np i < n ∧ nk i < n)
    (hpre : ∀ i, i < n → (st i).halt = none → (st i).tickP cfg mm env .preempt = st (np i))
    (hpick : ∀ i, i < n → (st i).halt = none → ∀ m,
      (st i).tickP cfg mm env (.pick m) = st (nk i))
    (h0 : 0 < n) (hst0 : st 0 = Sched.init mm io)
    (h : outcomesP cfg mm env io o) : ∃ j, j < n ∧ (st j).obs = some o := by
  obtain ⟨fuel, cs, h⟩ := h
  obtain ⟨j, hj, he⟩ := runSchedStateP_family cfg mm env n st np nk hn hpre hpick fuel cs 0 h0
  refine ⟨j, hj, ?_⟩
  rw [← he, hst0]
  exact h

/-- The state after the choice list `ps[i]` (`true` = `preempt`, `false` = `pick 0`), with one
micro-step per choice. A family of such states is the input of `runSchedStateP_family`. -/
def famSt (io : IO) (ps : List (List Bool)) (i : Nat) : Sched M :=
  let p := (ps.getD i []).map (fun b => if b then PChoice.preempt else .pick 0)
  runSchedStateP cfg mm env p.length p (Sched.init mm io)

omit [DecidableEq M] in
/-- A program with one observation `o₀` over all schedules with preemption, from a family. -/
theorem outcomesP_single_of_family {io : IO} {o₀ : Obs} (n : Nat) (st : Nat → Sched M)
    (np nk : Nat → Nat)
    (hn : ∀ i, i < n → np i < n ∧ nk i < n)
    (hpre : ∀ i, i < n → (st i).halt = none → (st i).tickP cfg mm env .preempt = st (np i))
    (hpick : ∀ i, i < n → (st i).halt = none → ∀ m,
      (st i).tickP cfg mm env (.pick m) = st (nk i))
    (h0 : 0 < n) (hst0 : st 0 = Sched.init mm io)
    (hobs : ∀ j, j < n → (st j).obs = none ∨ (st j).obs = some o₀)
    (hwit : ∃ fuel, runObsP cfg mm env fuel [] io = some o₀) :
    ∀ o, outcomesP cfg mm env io o ↔ o = o₀ := by
  intro o
  constructor
  · intro h
    obtain ⟨j, hj, he⟩ := outcomesP_family cfg mm env n st np nk hn hpre hpick h0 hst0 h
    rcases hobs j hj with h' | h'
    · rw [h'] at he; cases he
    · rw [h'] at he; cases he; rfl
  · rintro rfl
    obtain ⟨fuel, h⟩ := hwit
    exact ⟨fuel, [], h⟩

/-- The exact observation set of one program (for smoke tests and examples). -/
def outcomesPList (bound : Nat) (io : IO) : Option (List Obs) :=
  let l := exploreP cfg mm env bound io
  if exactP cfg mm env io l then some (obsList l) else none

theorem outcomesPList_sound {bound : Nat} {io : IO} {os : List Obs}
    (h : outcomesPList cfg mm env bound io = some os) (o : Obs) :
    outcomesP cfg mm env io o ↔ o ∈ os := by
  simp only [outcomesPList] at h
  split at h
  · cases h
    exact outcomesP_iff_of_exactP cfg mm env (by assumption) o
  · cases h

end

end CatsEffectInLean.Model

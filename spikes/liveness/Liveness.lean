/-!
# Liveness spike (Phase 0, step 4)

A toy fiber interpreter, NOT the library model. It tests the statement shapes for
fairness and liveness that Phase 2 and Phase 4 will use.

* A schedule is an infinite stream of choices `Nat → Choice`.
  A choice names the fiber that steps and says if a pending cancel is observed now.
* `FiberFair s`: each fiber is picked infinitely often.
* `Fair s`: each fiber is picked infinitely often *with* `observe = true`
  (cancel fairness; implies `FiberFair`).
* `Terminates st`: for every fair schedule there is a step count `n` with `done`.

Picking a finished or busy-waiting fiber is a stutter (the state does not change).
Because of this, the schedule-only predicate `FiberFair` covers weak fairness:
the adversary can still pick a fiber only at moments when it cannot progress.

Results (all without `sorry`; axioms: see `#print axioms` at the end):
1. `simple_terminates`, `twoFinite_terminates`: programs of finite fibers terminate
   under every `FiberFair` schedule (ranking function per fiber + induction on the
   rank, fairness gives the next index where the fiber steps).
2. `spinWait_terminates` and `spinWait_not_terminatesAlways`: a busy-wait program
   terminates under fair schedules, but the unfair schedule `fun _ => ⟨0, true⟩`
   runs it forever.
3. `cancelLoop_observes_cancel`: a fiber in an endless loop of cancelable points
   (`IO.cede.foreverM`) that another fiber cancels finishes as `canceled` under every
   `Fair` schedule. `cancelLoop_fiberFair_not_enough`: `FiberFair` alone is not enough.
   `maskedLoop_never_finishes`: a fiber already inside `uncancelable` never finishes,
   under every schedule (intended Cats Effect behaviour).
4. `lasso_not_terminates`: a finite lasso (prefix + cycle that covers every fiber with
   `observe = true`) refutes `Terminates`; all side conditions are checked by `decide`.
   Example: `maskedLoop_not_terminates_lasso`.

Not built by `lake build` (outside the library). Check with
`lean -M 8000 spikes/liveness/Liveness.lean` (about 1 s).
-/

namespace Spike.Liveness

/-- Toy instructions. One instruction is one atomic step. -/
inductive Instr where
  /-- `IO.delay` of a terminating thunk. -/
  | work
  /-- `IO.cede`: a yield; in this toy it is one step. -/
  | cede
  /-- Set the shared flag (a `Ref` write). -/
  | setFlag
  /-- Busy wait (`ref.get.flatMap(b => if b then unit else cede >> loop)`):
  advance only if the flag is set. -/
  | spin
  /-- Enter an `uncancelable` region (mask counter + 1). -/
  | mask
  /-- Leave an `uncancelable` region (mask counter − 1). -/
  | unmask
  /-- `IO.cede.foreverM`: never advances; each step is a cancelable point. -/
  | loop
  /-- `fiber(j).cancel`, without the backpressure wait. -/
  | cancel (j : Fin 2)
  deriving DecidableEq, Repr

inductive Outcome where
  | succeeded
  | canceled
  deriving DecidableEq, Repr

structure Fiber where
  code : List Instr
  masks : Nat := 0
  canceled : Bool := false
  outcome : Option Outcome := none
  deriving DecidableEq, Repr

/-- Two fibers and one shared flag. -/
structure St where
  f0 : Fiber
  f1 : Fiber
  flag : Bool := false
  deriving DecidableEq, Repr

def St.get (st : St) (i : Fin 2) : Fiber :=
  if i.val = 0 then st.f0 else st.f1

def St.set (st : St) (i : Fin 2) (fb : Fiber) : St :=
  if i.val = 0 then { st with f0 := fb } else { st with f1 := fb }

def St.cancelFiber (st : St) (j : Fin 2) : St :=
  st.set j { st.get j with canceled := true }

/-- One scheduler choice: which fiber steps, and whether a pending cancel is observed
at this step (models the `cancelationCheckThreshold` read barrier). -/
structure Choice where
  fiber : Fin 2
  observe : Bool
  deriving DecidableEq, Repr

/-- An infinite schedule. -/
abbrev Schedule := Nat → Choice

def stepAux (st : St) (c : Choice) (fb : Fiber) : St :=
  match fb.outcome with
  | some _ => st
  | none =>
    if fb.canceled = true ∧ fb.masks = 0 ∧ c.observe = true then
      st.set c.fiber { fb with outcome := some .canceled }
    else
      match fb.code with
      | [] => st.set c.fiber { fb with outcome := some .succeeded }
      | .work :: rest => st.set c.fiber { fb with code := rest }
      | .cede :: rest => st.set c.fiber { fb with code := rest }
      | .setFlag :: rest => { st.set c.fiber { fb with code := rest } with flag := true }
      | .spin :: rest => if st.flag = true then st.set c.fiber { fb with code := rest } else st
      | .mask :: rest => st.set c.fiber { fb with code := rest, masks := fb.masks + 1 }
      | .unmask :: rest => st.set c.fiber { fb with code := rest, masks := fb.masks - 1 }
      | .loop :: _ => st
      | .cancel j :: rest => (st.set c.fiber { fb with code := rest }).cancelFiber j

/-- One step of the picked fiber. The order mirrors `IOFiber.runLoop`: first the
`shouldFinalize()` check (`canceled && masks == 0`), then the instruction. -/
def step (st : St) (c : Choice) : St := stepAux st c (st.get c.fiber)

/-- State after the first `n` choices of `s`. -/
def exec (s : Schedule) (st : St) : Nat → St
  | 0 => st
  | n + 1 => step (exec s st n) (s n)

def St.done (st : St) : Bool := st.f0.outcome.isSome && st.f1.outcome.isSome

/-! ## Fairness and termination -/

/-- Weak fairness on the schedule only: each fiber is picked infinitely often. -/
def FiberFair (s : Schedule) : Prop :=
  ∀ (i : Fin 2) (n : Nat), ∃ m, n ≤ m ∧ (s m).fiber = i

/-- Fairness with cancel observation: each fiber is picked infinitely often at a
step that observes a pending cancel. -/
def Fair (s : Schedule) : Prop :=
  ∀ (i : Fin 2) (n : Nat), ∃ m, n ≤ m ∧ s m = ⟨i, true⟩

theorem Fair.fiberFair {s : Schedule} (h : Fair s) : FiberFair s := by
  intro i n
  obtain ⟨m, hm, hs⟩ := h i n
  exact ⟨m, hm, by rw [hs]⟩

/-- Bounded fairness: every window of `B` choices contains an observing pick of each
fiber. The JVM read barrier gives such a bound per fiber (`cancelationCheckThreshold`),
but nothing bounds the steps of *other* fibers, so CE does not promise this. -/
def BoundedFair (B : Nat) (s : Schedule) : Prop :=
  ∀ (i : Fin 2) (n : Nat), ∃ m, n ≤ m ∧ m < n + B ∧ s m = ⟨i, true⟩

theorem BoundedFair.fair {B : Nat} {s : Schedule} (h : BoundedFair B s) : Fair s := by
  intro i n
  obtain ⟨m, h1, -, h3⟩ := h i n
  exact ⟨m, h1, h3⟩

/-- Liveness: every fair run finishes after finitely many steps. -/
def Terminates (st : St) : Prop :=
  ∀ s : Schedule, Fair s → ∃ n, (exec s st n).done = true

/-- Termination under all schedules (not only fair ones). -/
def TerminatesAlways (st : St) : Prop :=
  ∀ s : Schedule, ∃ n, (exec s st n).done = true

/-! ## Accessor lemmas -/

theorem fin2_cases (i : Fin 2) : i = 0 ∨ i = 1 := by
  rcases i with ⟨_ | _ | k, h⟩
  · exact Or.inl rfl
  · exact Or.inr rfl
  · omega

@[simp] theorem get_zero (st : St) : st.get 0 = st.f0 := rfl
@[simp] theorem get_one (st : St) : st.get 1 = st.f1 := rfl
@[simp] theorem set_zero (st : St) (fb : Fiber) : st.set 0 fb = { st with f0 := fb } := rfl
@[simp] theorem set_one (st : St) (fb : Fiber) : st.set 1 fb = { st with f1 := fb } := rfl

theorem get_set_same (st : St) (i : Fin 2) (fb : Fiber) : (st.set i fb).get i = fb := by
  rcases fin2_cases i with rfl | rfl <;> rfl

theorem get_set_other (st : St) {i j : Fin 2} (h : i ≠ j) (fb : Fiber) :
    (st.set i fb).get j = st.get j := by
  rcases fin2_cases i with rfl | rfl <;> rcases fin2_cases j with rfl | rfl <;>
    first | rfl | exact absurd rfl h

@[simp] theorem set_flag (st : St) (i : Fin 2) (fb : Fiber) : (st.set i fb).flag = st.flag := by
  rcases fin2_cases i with rfl | rfl <;> rfl

@[simp] theorem cancelFiber_flag (st : St) (j : Fin 2) : (st.cancelFiber j).flag = st.flag := by
  simp [St.cancelFiber]

/-- `cancelFiber` changes only the `canceled` field. -/
theorem cancelFiber_get (st : St) (j k : Fin 2) :
    ((st.cancelFiber j).get k).code = (st.get k).code ∧
    ((st.cancelFiber j).get k).masks = (st.get k).masks ∧
    ((st.cancelFiber j).get k).outcome = (st.get k).outcome := by
  unfold St.cancelFiber
  by_cases h : j = k
  · subst h; simp [get_set_same]
  · simp [get_set_other _ h]

@[simp] theorem get_with_flag (st : St) (i : Fin 2) (b : Bool) :
    ({ st with flag := b } : St).get i = st.get i := by
  rcases fin2_cases i with rfl | rfl <;> rfl

/-! ## Frame lemmas for `step` -/

/-- The flag never goes back to `false`. -/
theorem step_flag_mono (st : St) (c : Choice) (h : st.flag = true) : (step st c).flag = true := by
  unfold step
  generalize st.get c.fiber = fb
  unfold stepAux
  split
  · exact h
  · split
    · simp [h]
    · split <;> (try split) <;> simp [h]

/-- A step of another fiber does not change the code, masks and outcome of fiber `i`. -/
theorem step_other (st : St) (c : Choice) (i : Fin 2) (hne : c.fiber ≠ i) :
    ((step st c).get i).code = (st.get i).code ∧
    ((step st c).get i).masks = (st.get i).masks ∧
    ((step st c).get i).outcome = (st.get i).outcome := by
  have hs : ∀ fb, (st.set c.fiber fb).get i = st.get i := fun fb => get_set_other st hne fb
  unfold step
  generalize st.get c.fiber = fb
  unfold stepAux
  split
  · exact ⟨rfl, rfl, rfl⟩
  · split
    · simp [hs]
    · split
      · simp [hs]
      · simp [hs]
      · simp [hs]
      · simp [hs]
      · split <;> simp [hs]
      · simp [hs]
      · simp [hs]
      · exact ⟨rfl, rfl, rfl⟩
      · rename_i j rest _
        have := cancelFiber_get (st.set c.fiber { fb with code := rest }) j i
        simp only [hs] at this
        exact this

/-- A finished fiber stays finished, with the same outcome. -/
theorem step_outcome_stable (st : St) (c : Choice) (i : Fin 2) (o : Outcome)
    (h : (st.get i).outcome = some o) : ((step st c).get i).outcome = some o := by
  by_cases hne : c.fiber = i
  · subst hne
    unfold step
    simp [stepAux, h]
  · rw [(step_other st c i hne).2.2, h]

theorem exec_outcome_stable (s : Schedule) (st : St) (i : Fin 2) (o : Outcome) (n : Nat)
    (h : ((exec s st n).get i).outcome = some o) :
    ∀ k, ((exec s st (n + k)).get i).outcome = some o := by
  intro k
  induction k with
  | zero => exact h
  | succ k ih => exact step_outcome_stable _ _ _ _ ih

/-! ## Ranking function and progress -/

/-- An instruction that always lets its fiber advance (given the current flag). -/
def Instr.progressive (flag : Bool) : Instr → Bool
  | .loop => false
  | .spin => flag
  | _ => true

/-- Fiber `i` advances each time it is picked (no `loop`; `spin` only after the flag). -/
def Prog (st : St) (i : Fin 2) : Prop :=
  ∀ x ∈ (st.get i).code, x.progressive st.flag = true

/-- Rank of a fiber: remaining instructions + 1, or 0 when finished. -/
def rank (fb : Fiber) : Nat :=
  match fb.outcome with
  | some _ => 0
  | none => fb.code.length + 1

theorem progressive_mono {flag flag' : Bool} (hf : flag = true → flag' = true) (x : Instr)
    (h : x.progressive flag = true) : x.progressive flag' = true := by
  cases x <;> simp_all [Instr.progressive]

theorem Prog_of_flag {st st' : St} {i : Fin 2} (hc : (st'.get i).code = (st.get i).code)
    (hf : st.flag = true → st'.flag = true) (h : Prog st i) : Prog st' i := by
  intro x hx
  rw [hc] at hx
  exact progressive_mono hf x (h x hx)

/-- `Prog` for a state whose code of fiber `i` is a sublist (here: equal or a tail). -/
theorem Prog_sub {st' : St} {i : Fin 2} {flag : Bool} {L : List Instr}
    (hp : ∀ x ∈ L, x.progressive flag = true)
    (hsub : ∀ x ∈ (st'.get i).code, x ∈ L)
    (hf : flag = true → st'.flag = true) : Prog st' i :=
  fun x hx => progressive_mono hf x (hp x (hsub x hx))

/-- Own step of a progressive, unfinished fiber: its rank falls and it stays progressive. -/
theorem step_self (st : St) (c : Choice) (hp : Prog st c.fiber)
    (hn : (st.get c.fiber).outcome = none) :
    rank ((step st c).get c.fiber) < rank (st.get c.fiber) ∧ Prog (step st c) c.fiber := by
  have gs : ∀ fb, (st.set c.fiber fb).get c.fiber = fb := fun fb => get_set_same st c.fiber fb
  unfold Prog at hp
  unfold step
  generalize st.get c.fiber = fb at hp hn ⊢
  have hr : rank fb = fb.code.length + 1 := by simp [rank, hn]
  rw [hr]
  unfold stepAux
  simp only [hn]
  split
  · -- cancel observed: the fiber finishes as `canceled`
    refine ⟨by simp [gs, rank], Prog_sub hp (by simp [gs]) (by simp)⟩
  · split
    · refine ⟨by simp [gs, rank], Prog_sub hp (by simp [gs]) (by simp)⟩
    · rename_i rest hcode
      refine ⟨by simp [gs, rank, hcode], Prog_sub hp ?_ (by simp)⟩
      intro x hx; simp only [gs] at hx; rw [hcode]; exact List.mem_cons_of_mem _ hx
    · rename_i rest hcode
      refine ⟨by simp [gs, rank, hcode], Prog_sub hp ?_ (by simp)⟩
      intro x hx; simp only [gs] at hx; rw [hcode]; exact List.mem_cons_of_mem _ hx
    · rename_i rest hcode
      refine ⟨by simp [gs, rank, hcode], Prog_sub hp ?_ (by simp)⟩
      intro x hx; simp only [get_with_flag, gs] at hx; rw [hcode]; exact List.mem_cons_of_mem _ hx
    · rename_i rest hcode
      have hf : st.flag = true := by
        have := hp .spin (by rw [hcode]; exact List.mem_cons_self ..)
        simpa [Instr.progressive] using this
      simp only [hf, ite_true]
      refine ⟨by simp [gs, rank, hcode], Prog_sub hp ?_ (by simp)⟩
      intro x hx; simp only [gs] at hx; rw [hcode]; exact List.mem_cons_of_mem _ hx
    · rename_i rest hcode
      refine ⟨by simp [gs, rank, hcode], Prog_sub hp ?_ (by simp)⟩
      intro x hx; simp only [gs] at hx; rw [hcode]; exact List.mem_cons_of_mem _ hx
    · rename_i rest hcode
      refine ⟨by simp [gs, rank, hcode], Prog_sub hp ?_ (by simp)⟩
      intro x hx; simp only [gs] at hx; rw [hcode]; exact List.mem_cons_of_mem _ hx
    · rename_i rest hcode
      have := hp .loop (by rw [hcode]; exact List.mem_cons_self ..)
      simp [Instr.progressive] at this
    · rename_i j rest hcode
      have cf := cancelFiber_get (st.set c.fiber { fb with code := rest, outcome := none }) j c.fiber
      simp only [gs] at cf
      obtain ⟨cc, _, co⟩ := cf
      refine ⟨by simp [rank, cc, co, hcode], Prog_sub hp ?_ (by simp)⟩
      intro x hx; rw [cc] at hx; rw [hcode]; exact List.mem_cons_of_mem _ hx

/-- Any step: the rank of a progressive fiber does not grow and it stays progressive. -/
theorem step_mono (st : St) (c : Choice) (i : Fin 2) (hp : Prog st i) :
    rank ((step st c).get i) ≤ rank (st.get i) ∧ Prog (step st c) i := by
  by_cases hne : c.fiber = i
  · subst hne
    cases ho : (st.get c.fiber).outcome with
    | none =>
      have := step_self st c hp ho
      exact ⟨Nat.le_of_lt this.1, this.2⟩
    | some o =>
      have hstut : step st c = st := by unfold step; simp [stepAux, ho]
      rw [hstut]; exact ⟨Nat.le_refl _, hp⟩
  · obtain ⟨hc, _, ho⟩ := step_other st c i hne
    refine ⟨by simp [rank, hc, ho], Prog_of_flag hc (step_flag_mono st c) hp⟩

theorem exec_mono (s : Schedule) (st : St) (i : Fin 2) (n : Nat) (hp : Prog (exec s st n) i) :
    ∀ k, rank ((exec s st (n + k)).get i) ≤ rank ((exec s st n).get i) ∧
      Prog (exec s st (n + k)) i := by
  intro k
  induction k with
  | zero => exact ⟨Nat.le_refl _, hp⟩
  | succ k ih =>
    have := step_mono (exec s st (n + k)) (s (n + k)) i ih.2
    exact ⟨Nat.le_trans this.1 ih.1, this.2⟩

/-- Core liveness lemma: under a `FiberFair` schedule, a progressive fiber finishes.
Proof: induction on the rank; fairness gives the next index `m` where the fiber steps. -/
theorem fiber_finishes (s : Schedule) (hs : FiberFair s) (st : St) (i : Fin 2) :
    ∀ r n, rank ((exec s st n).get i) ≤ r → Prog (exec s st n) i →
      ∃ m, ((exec s st m).get i).outcome.isSome = true := by
  intro r
  induction r with
  | zero =>
    intro n hr _
    refine ⟨n, ?_⟩
    cases h : ((exec s st n).get i).outcome with
    | some _ => rfl
    | none => simp [rank, h] at hr
  | succ r ih =>
    intro n hr hp
    obtain ⟨m, hnm, hsm⟩ := hs i n
    obtain ⟨hrm, hpm⟩ := exec_mono s st i n hp (m - n)
    rw [Nat.add_sub_cancel' hnm] at hrm hpm
    cases ho : ((exec s st m).get i).outcome with
    | some _ => exact ⟨m, by simp [ho]⟩
    | none =>
      have hpm' : Prog (exec s st m) (s m).fiber := by rw [hsm]; exact hpm
      have ho' : ((exec s st m).get (s m).fiber).outcome = none := by rw [hsm]; exact ho
      have hlt := (step_self (exec s st m) (s m) hpm' ho').1
      have hlt' : rank ((exec s st (m + 1)).get i) < rank ((exec s st m).get i) := by
        show rank ((step (exec s st m) (s m)).get i) < _
        rw [← hsm]; exact hlt
      have hp1 : Prog (exec s st (m + 1)) i := (step_mono _ (s m) i hpm).2
      exact ih (m + 1) (by omega) hp1

theorem finished_eventually (s : Schedule) (hs : FiberFair s) (st : St) (i : Fin 2) (n : Nat)
    (hp : Prog (exec s st n) i) : ∃ m, n ≤ m ∧ ((exec s st m).get i).outcome.isSome = true := by
  obtain ⟨m, hm⟩ := fiber_finishes s hs st i _ n (Nat.le_refl _) hp
  cases ho : ((exec s st m).get i).outcome with
  | none => simp [ho] at hm
  | some o =>
    refine ⟨n + m, Nat.le_add_right _ _, ?_⟩
    rw [Nat.add_comm, exec_outcome_stable s st i o m ho n]; rfl

/-- If both fibers finish at some points, the run is done at the later point. -/
theorem done_of_both (s : Schedule) (st : St) (m0 m1 : Nat)
    (h0 : ((exec s st m0).get 0).outcome.isSome = true)
    (h1 : ((exec s st m1).get 1).outcome.isSome = true) :
    ∃ n, (exec s st n).done = true := by
  refine ⟨m0 + m1, ?_⟩
  simp only [get_zero, get_one] at h0 h1
  cases o0 : (exec s st m0).f0.outcome with
  | none => rw [o0] at h0; exact absurd h0 (by decide)
  | some a =>
  cases o1 : (exec s st m1).f1.outcome with
  | none => rw [o1] at h1; exact absurd h1 (by decide)
  | some b =>
  have e0 := exec_outcome_stable s st 0 a m0 o0 m1
  have e1 := exec_outcome_stable s st 1 b m1 o1 m0
  rw [Nat.add_comm m1 m0] at e1
  simp only [get_zero, get_one] at e0 e1
  simp [St.done, e0, e1]

/-! ## Result 1: programs of finite fibers terminate under every fair schedule -/

/-- A fiber without `loop` and `spin` (only finite work). -/
def simpleCode (code : List Instr) : Prop := ∀ x ∈ code, x ≠ .loop ∧ x ≠ .spin

theorem Prog_of_simple (st : St) (i : Fin 2) (h : simpleCode (st.get i).code) : Prog st i := by
  intro x hx
  obtain ⟨h1, h2⟩ := h x hx
  cases x <;> simp_all [Instr.progressive]

/-- Any two finite fibers (with any masks and cancel flags) terminate under `FiberFair`. -/
theorem simple_terminates (st : St) (h0 : simpleCode st.f0.code) (h1 : simpleCode st.f1.code)
    (s : Schedule) (hs : FiberFair s) : ∃ n, (exec s st n).done = true := by
  obtain ⟨m0, -, e0⟩ := finished_eventually s hs st 0 0 (Prog_of_simple st 0 h0)
  obtain ⟨m1, -, e1⟩ := finished_eventually s hs st 1 0 (Prog_of_simple st 1 h1)
  exact done_of_both s st m0 m1 e0 e1

def twoFinite : St :=
  { f0 := { code := [.work, .mask, .work, .unmask, .cede, .work] },
    f1 := { code := [.work, .cede, .cancel 0, .work] } }

theorem twoFinite_terminates : Terminates twoFinite := by
  intro s hs
  apply simple_terminates twoFinite _ _ s hs.fiberFair <;> (unfold simpleCode; decide)

/-! ## Result 2: terminates under fair schedules, not under an unfair one -/

/-- Fiber 0 busy-waits for the flag; fiber 1 sets it. -/
def spinWait : St :=
  { f0 := { code := [.spin] }, f1 := { code := [.setFlag] } }

/-- All states reachable from `spinWait` (closed under `step`, checked by `decide`). -/
def spinWaitReach : List St :=
  let a : Fiber := { code := [.spin] }
  let b : Fiber := { code := [] }
  let c : Fiber := { code := [], outcome := some .succeeded }
  let d : Fiber := { code := [.setFlag] }
  [ { f0 := a, f1 := d, flag := false },
    { f0 := a, f1 := b, flag := true }, { f0 := a, f1 := c, flag := true },
    { f0 := b, f1 := b, flag := true }, { f0 := b, f1 := c, flag := true },
    { f0 := c, f1 := b, flag := true }, { f0 := c, f1 := c, flag := true } ]

theorem spinWaitReach_closed :
    ∀ st ∈ spinWaitReach, ∀ i : Fin 2, ∀ b : Bool, step st ⟨i, b⟩ ∈ spinWaitReach := by
  decide

/-- Invariant by induction on `n` from a closed finite set. -/
theorem exec_mem (R : List St) (hR : ∀ st ∈ R, ∀ i : Fin 2, ∀ b : Bool, step st ⟨i, b⟩ ∈ R)
    (s : Schedule) (st : St) (h : st ∈ R) : ∀ n, exec s st n ∈ R := by
  intro n
  induction n with
  | zero => exact h
  | succ n ih => exact hR _ ih (s n).fiber (s n).observe

theorem spinWaitReach_flag :
    ∀ st ∈ spinWaitReach, st.f1.outcome.isSome = true → st.flag = true ∧ st.f0.code ⊆ [.spin] := by
  decide

theorem spinWait_terminates_fiberFair (s : Schedule) (hs : FiberFair s) :
    ∃ n, (exec s spinWait n).done = true := by
  have hmem := exec_mem spinWaitReach spinWaitReach_closed s spinWait (by decide)
  have p1 : Prog (exec s spinWait 0) 1 := by
    intro x hx; simp [exec, spinWait] at hx; subst hx; rfl
  obtain ⟨m1, -, e1⟩ := finished_eventually s hs spinWait 1 0 p1
  obtain ⟨hf, hc⟩ := spinWaitReach_flag _ (hmem m1) e1
  have p0 : Prog (exec s spinWait m1) 0 := by
    intro x hx
    have := hc hx
    simp at this; subst this; simp [Instr.progressive, hf]
  obtain ⟨m0, -, e0⟩ := finished_eventually s hs spinWait 0 m1 p0
  exact done_of_both s spinWait m0 m1 e0 e1

theorem spinWait_terminates : Terminates spinWait :=
  fun s hs => spinWait_terminates_fiberFair s hs.fiberFair

/-- The unfair witness: always pick fiber 0. -/
def alwaysZero : Schedule := fun _ => ⟨0, true⟩

theorem alwaysZero_not_fiberFair : ¬ FiberFair alwaysZero := by
  intro h
  obtain ⟨m, -, hm⟩ := h 1 0
  simp [alwaysZero] at hm

theorem alwaysZero_spinWait_stuck : ∀ n, exec alwaysZero spinWait n = spinWait := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih => show step (exec alwaysZero spinWait n) _ = _; rw [ih]; rfl

/-- Refutation: `spinWait` does not terminate under every schedule. -/
theorem spinWait_not_terminatesAlways : ¬ TerminatesAlways spinWait := by
  intro h
  obtain ⟨n, hn⟩ := h alwaysZero
  rw [alwaysZero_spinWait_stuck n] at hn
  exact absurd hn (by decide)

/-! ## Result 3: a pending cancel is eventually observed -/

/-- Fiber 0 runs `IO.cede.foreverM`; fiber 1 cancels it. -/
def cancelLoop : St :=
  { f0 := { code := [.loop] }, f1 := { code := [.cancel 0] } }

def cancelLoopReach : List St :=
  let a : Fiber := { code := [.loop] }
  let a' : Fiber := { code := [.loop], canceled := true }
  let a'' : Fiber := { code := [.loop], canceled := true, outcome := some .canceled }
  let d : Fiber := { code := [.cancel 0] }
  let b : Fiber := { code := [] }
  let c : Fiber := { code := [], outcome := some .succeeded }
  [ { f0 := a, f1 := d }, { f0 := a', f1 := b }, { f0 := a', f1 := c },
    { f0 := a'', f1 := b }, { f0 := a'', f1 := c } ]

theorem cancelLoopReach_closed :
    ∀ st ∈ cancelLoopReach, ∀ i : Fin 2, ∀ b : Bool, step st ⟨i, b⟩ ∈ cancelLoopReach := by
  decide

/-- Once fiber 1 is done, one observing step of fiber 0 leaves it `canceled`. -/
theorem cancelLoopReach_observe :
    ∀ st ∈ cancelLoopReach, st.f1.outcome.isSome = true →
      (step st ⟨0, true⟩).f0.outcome = some .canceled := by
  decide

theorem cancelLoop_observes_cancel (s : Schedule) (hs : Fair s) :
    ∃ n, (exec s cancelLoop n).f0.outcome = some .canceled := by
  have hmem := exec_mem cancelLoopReach cancelLoopReach_closed s cancelLoop (by decide)
  have p1 : Prog (exec s cancelLoop 0) 1 := by
    intro x hx; simp [exec, cancelLoop] at hx; subst hx; rfl
  obtain ⟨m1, -, e1⟩ := finished_eventually s hs.fiberFair cancelLoop 1 0 p1
  obtain ⟨m, hm, hsm⟩ := hs 0 m1
  simp only [get_one] at e1
  cases o1 : (exec s cancelLoop m1).f1.outcome with
  | none => rw [o1] at e1; exact absurd e1 (by decide)
  | some o =>
  have st1 := exec_outcome_stable s cancelLoop 1 o m1 o1 (m - m1)
  rw [Nat.add_sub_cancel' hm] at st1
  refine ⟨m + 1, ?_⟩
  show (step (exec s cancelLoop m) (s m)).f0.outcome = _
  rw [hsm]
  exact cancelLoopReach_observe _ (hmem m) (by simp only [get_one] at st1; simp [st1])

/-- The whole `cancelLoop` program terminates under `Fair`. -/
theorem cancelLoop_terminates : Terminates cancelLoop := by
  intro s hs
  obtain ⟨n0, h0⟩ := cancelLoop_observes_cancel s hs
  have p1 : Prog (exec s cancelLoop 0) 1 := by
    intro x hx; simp [exec, cancelLoop] at hx; subst hx; rfl
  obtain ⟨m1, -, e1⟩ := finished_eventually s hs.fiberFair cancelLoop 1 0 p1
  exact done_of_both s cancelLoop n0 m1 (by simp [h0]) e1

/-- `FiberFair` alone is not enough: a schedule that never observes the cancel. -/
def neverObserve : Schedule := fun n => ⟨⟨n % 2, Nat.mod_lt _ (by decide)⟩, false⟩

theorem neverObserve_fiberFair : FiberFair neverObserve := by
  intro i n
  refine ⟨2 * n + i.val, by omega, ?_⟩
  apply Fin.ext
  show (2 * n + i.val) % 2 = i.val
  have := i.isLt
  omega

theorem cancelLoopReach_noObserve :
    ∀ st ∈ cancelLoopReach, st.f0.outcome = none → ∀ i : Fin 2,
      (step st ⟨i, false⟩).f0.outcome = none := by
  decide

theorem cancelLoop_fiberFair_not_enough :
    ∃ s, FiberFair s ∧ ∀ n, (exec s cancelLoop n).f0.outcome = none := by
  refine ⟨neverObserve, neverObserve_fiberFair, ?_⟩
  have hmem := exec_mem cancelLoopReach cancelLoopReach_closed neverObserve cancelLoop (by decide)
  intro n
  induction n with
  | zero => rfl
  | succ n ih => exact cancelLoopReach_noObserve _ (hmem n) ih _

/-- Fiber 0 is already inside `uncancelable(_ => IO.cede.foreverM)` (mask counter 1);
fiber 1 cancels it. (If the cancel comes before the fiber enters the mask, the fiber
is canceled; `decide` found this when the toy started with `[.mask, .loop]`.) -/
def maskedLoop : St :=
  { f0 := { code := [.loop], masks := 1 }, f1 := { code := [.cancel 0] } }

def maskedLoopReach : List St :=
  let m : Fiber := { code := [.loop], masks := 1 }
  let m1 : Fiber := { code := [.loop], masks := 1, canceled := true }
  let d : Fiber := { code := [.cancel 0] }
  let b : Fiber := { code := [] }
  let c : Fiber := { code := [], outcome := some .succeeded }
  [ { f0 := m, f1 := d }, { f0 := m1, f1 := b }, { f0 := m1, f1 := c } ]

theorem maskedLoopReach_closed :
    ∀ st ∈ maskedLoopReach, ∀ i : Fin 2, ∀ b : Bool, step st ⟨i, b⟩ ∈ maskedLoopReach := by
  decide

/-- Intended CE behaviour: an `uncancelable` endless loop never observes the cancel,
under every schedule (fair or not). -/
theorem maskedLoop_never_finishes :
    ∀ s n, (exec s maskedLoop n).f0.outcome = none := by
  intro s n
  have h := exec_mem maskedLoopReach maskedLoopReach_closed s maskedLoop (by decide) n
  have key : ∀ st ∈ maskedLoopReach, st.f0.outcome = none := by decide
  exact key _ h

theorem maskedLoop_not_terminates : ¬ Terminates maskedLoop := by
  intro h
  obtain ⟨n, hn⟩ := h (fun n => ⟨⟨n % 2, Nat.mod_lt _ (by decide)⟩, true⟩) (by
    intro i n
    refine ⟨2 * n + i.val, by omega, ?_⟩
    have := i.isLt
    show (⟨⟨(2 * n + i.val) % 2, _⟩, true⟩ : Choice) = ⟨i, true⟩
    congr 1
    apply Fin.ext
    show (2 * n + i.val) % 2 = i.val
    omega)
  have := maskedLoop_never_finishes (fun n => ⟨⟨n % 2, Nat.mod_lt _ (by decide)⟩, true⟩) n
  simp [St.done, this] at hn

/-! ## Lasso refutations: a finite certificate for "does not terminate under `Fair`"

A prefix of `n0` steps, then a cycle of `p` steps that returns to the same state, picks
every fiber with `observe = true`, and is not `done`. Repeating the cycle gives a fair
infinite schedule that never finishes. All side conditions of a concrete lasso are
closed terms, so `decide` checks them. -/

theorem exec_add (s : Schedule) (st : St) (n m : Nat) :
    exec s st (n + m) = exec (fun k => s (n + k)) (exec s st n) m := by
  induction m with
  | zero => rfl
  | succ m ih => show step (exec s st (n + m)) (s (n + m)) = _; rw [ih]; rfl

theorem done_stable (s : Schedule) (st : St) (n : Nat) (h : (exec s st n).done = true) :
    ∀ k, (exec s st (n + k)).done = true := by
  intro k
  simp only [St.done, Bool.and_eq_true] at h ⊢
  obtain ⟨h0, h1⟩ := h
  cases o0 : (exec s st n).f0.outcome with
  | none => rw [o0] at h0; exact absurd h0 (by decide)
  | some a =>
  cases o1 : (exec s st n).f1.outcome with
  | none => rw [o1] at h1; exact absurd h1 (by decide)
  | some b =>
  have e0 := exec_outcome_stable s st 0 a n o0 k
  have e1 := exec_outcome_stable s st 1 b n o1 k
  simp only [get_zero, get_one] at e0 e1
  simp [e0, e1]

theorem lasso_not_terminates (st : St) (s : Schedule) (n0 p : Nat) (hp : 0 < p)
    (hper : ∀ n, s (n0 + n + p) = s (n0 + n))
    (hcov : ∀ i : Fin 2, ∃ j, j < p ∧ s (n0 + j) = ⟨i, true⟩)
    (hloop : exec s st (n0 + p) = exec s st n0)
    (hnd : (exec s st n0).done = false) : ¬ Terminates st := by
  have per' : ∀ k j, s (n0 + k * p + j) = s (n0 + j) := by
    intro k
    induction k with
    | zero => intro j; simp
    | succ k ih =>
      intro j
      have : n0 + (k + 1) * p + j = n0 + (k * p + j) + p := by
        rw [Nat.succ_mul]; omega
      rw [this, hper, ← ih j, Nat.add_assoc]
  have loopk : ∀ k, exec s st (n0 + k * p) = exec s st n0 := by
    intro k
    induction k with
    | zero => simp
    | succ k ih =>
      have e : n0 + (k + 1) * p = (n0 + k * p) + p := by rw [Nat.succ_mul]; omega
      rw [e, exec_add, ih]
      have hs : (fun j => s (n0 + k * p + j)) = (fun j => s (n0 + j)) := funext (per' k)
      rw [hs, ← exec_add, hloop]
  have hfair : Fair s := by
    intro i n
    obtain ⟨j, hj, hsj⟩ := hcov i
    refine ⟨n0 + n * p + j, ?_, by rw [per']; exact hsj⟩
    have : n ≤ n * p := Nat.le_mul_of_pos_right n hp
    omega
  intro hT
  obtain ⟨N, hN⟩ := hT s hfair
  have hge : N ≤ n0 + N * p := by
    have : N ≤ N * p := Nat.le_mul_of_pos_right N hp
    omega
  have := done_stable s st N hN (n0 + N * p - N)
  rw [Nat.add_sub_cancel' hge, loopk] at this
  rw [hnd] at this
  exact absurd this (by decide)

/-- Round robin with cancel observation at every step. -/
def roundRobin : Schedule := fun n => ⟨⟨n % 2, Nat.mod_lt _ (by decide)⟩, true⟩

/-- The same refutation as `maskedLoop_not_terminates`, by a lasso certificate:
prefix 4 steps, cycle 2 steps. -/
theorem maskedLoop_not_terminates_lasso : ¬ Terminates maskedLoop := by
  apply lasso_not_terminates maskedLoop roundRobin 4 2 (by decide)
  · intro n
    show (⟨⟨(4 + n + 2) % 2, _⟩, true⟩ : Choice) = ⟨⟨(4 + n) % 2, _⟩, true⟩
    congr 2
    omega
  · intro i
    rcases fin2_cases i with rfl | rfl
    · exact ⟨0, by decide, rfl⟩
    · exact ⟨1, by decide, rfl⟩
  · decide
  · decide

/-! ## Axiom audit -/

#print axioms BoundedFair.fair
#print axioms twoFinite_terminates
#print axioms simple_terminates
#print axioms spinWait_terminates
#print axioms spinWait_not_terminatesAlways
#print axioms cancelLoop_observes_cancel
#print axioms cancelLoop_terminates
#print axioms cancelLoop_fiberFair_not_enough
#print axioms maskedLoop_not_terminates
#print axioms maskedLoop_never_finishes
#print axioms maskedLoop_not_terminates_lasso

end Spike.Liveness

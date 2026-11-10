import KernelEval.Toy
/-!
Proof shapes that the real project will use, checked on the toy model.

1. A concrete run, proved by kernel evaluation.
2. A refutation: `¬ Prop` with a concrete schedule as the witness.
3. A bounded "for all schedules" proof: a Bool checker evaluated by
   `decide_cbv`, plus one generic soundness lemma that links the checker
   to the `Prop` statement.

`#print axioms` for each theorem must show only `propext`,
`Classical.choice`, `Quot.sound` (or no axioms).
-/
namespace KernelEval

/-! ## 1. Concrete run (2 fibers, 51 steps) -/

theorem twoChains3_run :
    summary (run code false 51 (roundRobin 2 51) (init (twoChains 3))) = some (.nat 6) := by
  decide +kernel

/-! ## 2. Property and refutation on the buggy toy -/

/-- "Finalizers run at most once", for all schedules of length ≤ `k` over `cs`. -/
def FinAtMostOnce (bug : Bool) (cs : List Choice) (k : Nat) (p : Prog) : Prop :=
  ∀ l : List Choice, l.length ≤ k → (∀ c ∈ l, c ∈ cs) →
    finRuns (exec code bug l (init p)) ≤ 1

/-- The deliberately buggy toy runs the finalizer twice. -/
theorem finAtMostOnce_buggy_refuted : ¬ FinAtMostOnce true choices2 15 (cancelProg 4) := by
  intro h
  have := h doubleFinSched (by decide) (by decide)
  revert this
  decide +kernel

/-! ## 3. Bounded proof for all schedules -/

/-- Soundness of the Bool checker `forallSched`. Proved once, for every model
that has a `step` function of this shape. -/
theorem forallSched_sound (code : Code) (bug : Bool) (cs : List Choice) (P : State → Bool) :
    ∀ (k : Nat) (s : State), forallSched code bug cs P k s = true →
      ∀ l : List Choice, l.length ≤ k → (∀ c ∈ l, c ∈ cs) → P (exec code bug l s) = true := by
  intro k
  induction k with
  | zero =>
    intro s h l hl _
    have : l = [] := List.eq_nil_of_length_eq_zero (Nat.le_zero.mp hl)
    subst this
    simpa [forallSched, exec] using h
  | succ k ih =>
    intro s h l hl hc
    simp only [forallSched, Bool.and_eq_true, List.all_eq_true] at h
    cases l with
    | nil => simpa [exec] using h.1
    | cons c l =>
      simp only [exec]
      exact ih _ (h.2 c (hc c (by simp))) l (by simp at hl; omega)
        (fun c' hc' => hc c' (by simp [hc']))

/-- The correct toy runs the finalizer at most once, for all 4^30 schedules of
length ≤ 30 over `choices2`. `decide_cbv` memoizes equal states, so it visits
only 2,775 (depth, state) pairs. -/
theorem finAtMostOnce_correct_proven : FinAtMostOnce false choices2 30 (cancelProg 4) := by
  intro l hl hc
  have hcheck : forallSched code false choices2 atMostOnce 30 (init (cancelProg 4)) = true := by
    decide_cbv
  exact of_decide_eq_true (forallSched_sound code false choices2 atMostOnce 30 _ hcheck l hl hc)

end KernelEval

#print axioms KernelEval.twoChains3_run
#print axioms KernelEval.finAtMostOnce_buggy_refuted
#print axioms KernelEval.forallSched_sound
#print axioms KernelEval.finAtMostOnce_correct_proven

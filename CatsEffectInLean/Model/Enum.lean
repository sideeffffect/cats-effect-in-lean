import CatsEffectInLean.Model.Outcomes

/-!
# Bounded schedule enumerator (Phase 2 step 10)

The set of observations of `runObs` (`CatsEffectInLean/Model/Outcomes.lean`) over all choice
lists up to a bound. The bound has three parts:

* `alpha`: the choices that a list can contain (for example `pick 0`, `pick 1`, and, for
  outside cancels, `cancel 0`);
* `depth`: the maximum list length. A list is used up only at task boundaries; after its end
  the scheduler picks ready task 0 (FIFO). So `depth` bounds the number of scheduling
  decisions (dejafu-style schedule bounding);
* `fuel`: the micro-steps of each run (also the task limit).

`choiceLists alpha depth` lists all choice lists of length `≤ depth` over `alpha`.
`enumObs` runs each of them. This is a plain enumeration: it does not share prefixes and it
does not remove duplicates. `decide_cbv` shares equal subterms by itself
(`wiki/lean/kernel-evaluation.md`).

Lemmas:

* `mem_choiceLists`: `cs ∈ choiceLists alpha depth ↔ cs.length ≤ depth ∧ ∀ c ∈ cs, c ∈ alpha`.
* `enumObs_sound`: every listed result comes from one concrete choice list in the bound.
* `enumObs_complete`: every choice list in the bound gives a listed result.
* `enumResults_outcomes`: for a pick-only alphabet, every listed observation is in
  `outcomes` (the unbounded set). So the enumeration is a lower bound of `outcomes`. It is
  the full set only if `outcomes` needs no longer list and no more fuel; that is not checked
  here.
-/

namespace CatsEffectInLean.Model

/-- All choice lists of length `≤ depth` over `alpha`. -/
def choiceLists (alpha : List RChoice) : Nat → List (List RChoice)
  | 0 => [[]]
  | d + 1 => [] :: alpha.flatMap (fun c => (choiceLists alpha d).map (c :: ·))

theorem mem_choiceLists (alpha : List RChoice) :
    ∀ (depth : Nat) (cs : List RChoice),
      cs ∈ choiceLists alpha depth ↔ cs.length ≤ depth ∧ ∀ c ∈ cs, c ∈ alpha
  | 0, cs => by
    cases cs <;> simp [choiceLists]
  | d + 1, [] => by simp [choiceLists]
  | d + 1, c :: cs => by
    have ih := mem_choiceLists alpha d cs
    rw [List.forall_mem_cons]
    simp only [choiceLists, List.mem_cons, List.mem_flatMap, List.mem_map, List.length_cons]
    constructor
    · rintro (h | ⟨c', hc', cs', hcs', heq⟩)
      · cases h
      · cases heq
        exact ⟨by have := (ih.mp hcs').1; omega, hc', (ih.mp hcs').2⟩
    · rintro ⟨hl, hc, hcs⟩
      exact Or.inr ⟨c, hc, cs, ih.mpr ⟨by omega, hcs⟩, rfl⟩

/-- The pick choices `pick 0`, ..., `pick (k - 1)`. -/
def picks (k : Nat) : List RChoice := (List.range k).map .pick

theorem picks_isPick (k : Nat) : ∀ c ∈ picks k, c.isPick = true := by
  intro c hc
  simp only [picks, List.mem_map] at hc
  obtain ⟨_, _, rfl⟩ := hc
  rfl

section
variable {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- The result of each choice list in the bound (`none`: out of fuel). -/
def enumObs (fuel : Nat) (alpha : List RChoice) (depth : Nat) (io : IO) : List (Option Obs) :=
  (choiceLists alpha depth).map (fun cs => runObs cfg mm env fuel cs io)

/-- The observations in the bound (runs that ran out of fuel are left out). -/
def enumResults (fuel : Nat) (alpha : List RChoice) (depth : Nat) (io : IO) : List Obs :=
  (enumObs cfg mm env fuel alpha depth io).filterMap id

/-- Soundness: each listed result comes from a concrete choice list in the bound. -/
theorem enumObs_sound {fuel depth : Nat} {alpha : List RChoice} {io : IO} {r : Option Obs}
    (h : r ∈ enumObs cfg mm env fuel alpha depth io) :
    ∃ cs, cs.length ≤ depth ∧ (∀ c ∈ cs, c ∈ alpha) ∧ runObs cfg mm env fuel cs io = r := by
  simp only [enumObs, List.mem_map] at h
  obtain ⟨cs, hcs, rfl⟩ := h
  exact ⟨cs, ((mem_choiceLists alpha depth cs).mp hcs).1,
    ((mem_choiceLists alpha depth cs).mp hcs).2, rfl⟩

/-- Completeness for the bound: each choice list in the bound gives a listed result. -/
theorem enumObs_complete {fuel depth : Nat} {alpha : List RChoice} {io : IO}
    {cs : List RChoice} (hl : cs.length ≤ depth) (ha : ∀ c ∈ cs, c ∈ alpha) :
    runObs cfg mm env fuel cs io ∈ enumObs cfg mm env fuel alpha depth io := by
  simp only [enumObs, List.mem_map]
  exact ⟨cs, (mem_choiceLists alpha depth cs).mpr ⟨hl, ha⟩, rfl⟩

/-- Soundness for observations: each listed observation comes from a choice list in the
bound. -/
theorem enumResults_sound {fuel depth : Nat} {alpha : List RChoice} {io : IO} {o : Obs}
    (h : o ∈ enumResults cfg mm env fuel alpha depth io) :
    ∃ cs, cs.length ≤ depth ∧ (∀ c ∈ cs, c ∈ alpha) ∧ runObs cfg mm env fuel cs io = some o := by
  simp only [enumResults, List.mem_filterMap, id] at h
  obtain ⟨r, hr, rfl⟩ := h
  exact enumObs_sound cfg mm env hr

/-- Completeness for observations. -/
theorem enumResults_complete {fuel depth : Nat} {alpha : List RChoice} {io : IO}
    {cs : List RChoice} {o : Obs} (hl : cs.length ≤ depth) (ha : ∀ c ∈ cs, c ∈ alpha)
    (h : runObs cfg mm env fuel cs io = some o) :
    o ∈ enumResults cfg mm env fuel alpha depth io := by
  simp only [enumResults, List.mem_filterMap, id]
  exact ⟨some o, h ▸ enumObs_complete cfg mm env hl ha, rfl⟩

/-- With a pick-only alphabet, each listed observation is in the unbounded `outcomes`. -/
theorem enumResults_outcomes {fuel depth : Nat} {alpha : List RChoice} {io : IO} {o : Obs}
    (hα : ∀ c ∈ alpha, c.isPick = true)
    (h : o ∈ enumResults cfg mm env fuel alpha depth io) : outcomes cfg mm env io o := by
  obtain ⟨cs, _, ha, h⟩ := enumResults_sound cfg mm env h
  exact ⟨fuel, cs, fun c hc => hα c (ha c hc), h⟩

/-- With any alphabet, each listed observation is in `outcomesExt`. -/
theorem enumResults_outcomesExt {fuel depth : Nat} {alpha : List RChoice} {io : IO} {o : Obs}
    (h : o ∈ enumResults cfg mm env fuel alpha depth io) : outcomesExt cfg mm env io o := by
  obtain ⟨cs, _, _, h⟩ := enumResults_sound cfg mm env h
  exact ⟨fuel, cs, h⟩

/-- A `Bool` checker: the listed observations are exactly the members of `expected` (as sets).
`decide_cbv` evaluates it. -/
def enumMatches (fuel : Nat) (alpha : List RChoice) (depth : Nat) (io : IO)
    (expected : List Obs) : Bool :=
  let rs := enumResults cfg mm env fuel alpha depth io
  rs.all (fun o => expected.contains o) && expected.all (fun o => rs.contains o)

theorem enumMatches_sound {fuel depth : Nat} {alpha : List RChoice} {io : IO}
    {expected : List Obs} (h : enumMatches cfg mm env fuel alpha depth io expected = true) :
    ∀ o, o ∈ enumResults cfg mm env fuel alpha depth io ↔ o ∈ expected := by
  simp only [enumMatches, Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at h
  intro o
  exact ⟨h.1 o, h.2 o⟩

/-- Two programs have the same bounded observation sets. A smoke test of `Eqv`, not a proof. -/
def enumAgree (fuel : Nat) (alpha : List RChoice) (depth : Nat) (p q : IO) : Bool :=
  let rp := enumResults cfg mm env fuel alpha depth p
  let rq := enumResults cfg mm env fuel alpha depth q
  rp.all (fun o => rq.contains o) && rq.all (fun o => rp.contains o)

end

end CatsEffectInLean.Model

import CatsEffectInLean.Model.EnumP

/-!
# Certificate checker for closed state sets of the preemptive scheduler (Phase 6, track P)

`exactP`/`checkEqvP` (`Model/EnumP.lean`) find the state set by a search that removes
duplicates with list membership: about `n²/2` state comparisons. The kernel cannot run this for
a few thousand states (the law `uncancelableRaceNotInherited` has 4,441).

Here the search runs in compiled code (`#eval`, outside the trusted base), and it writes a
**certificate**. The kernel only checks the certificate, in linear time:

* `instrs : List (Option PChoice)`: a depth-first spanning tree of the state set. `some c` makes
  the child `tickP top c` of the top state of a stack (the top must not be halted), lists it
  and pushes it; `none` pops. `certStates` runs this from `Sched.init mm io`. So the listed states
  are reachable (`certStates_reach`) and the first one is the start state.
* `succ : List (List Nat)`: for each listed state that is not halted, the list index of each
  successor in `succsP` order. `certClosed` checks each edge with one comparison.

Soundness: `certClosed = true` gives `ClosedP` (`closedP_of_certClosed`), so
`outcomesP_sub_closed` applies. With reachability, `outcomesP_iff_of_cert` gives the exact
outcome set, like `outcomesP_iff_of_exactP`. A wrong certificate makes the check `false`, never
a wrong theorem.
-/

namespace CatsEffectInLean.Proofs.Lemmas.CertP

open CatsEffectInLean.Model

/-- Decode one instruction of a generated certificate: `0` = pop, `1` = `some preempt`,
`n + 2` = `some (pick n)`. -/
def decodeInstr : Nat → Option PChoice
  | 0 => none
  | 1 => some .preempt
  | n + 2 => some (.pick n)

section
variable {M : Type} [DecidableEq M] (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Run the tree instructions. `stack`: the path of states (top first); `acc`: listed states,
newest first. A bad instruction (child of a halted state, pop of the last state) makes the
result `none`. -/
def certGo : List (Option PChoice) → List (Sched M) → List (Sched M) → Option (List (Sched M))
  | [], _, acc => some acc
  | some c :: is, s :: st, acc =>
    if s.halt.isSome then none
    else
      let t := s.tickP cfg mm env c
      certGo is (t :: s :: st) (t :: acc)
  | none :: is, _ :: s :: st, acc => certGo is (s :: st) acc
  | _, _, _ => none

/-- The listed states of a certificate, in list order (start state first). -/
def certStates (io : IO) (instrs : List (Option PChoice)) : Option (List (Sched M)) :=
  let s0 := Sched.init mm io
  (certGo cfg mm env instrs [s0] [s0]).map List.reverse

/-- The edge check of one listed state `p.1` with successor indices `p.2`. -/
def edgeOK (L : List (Sched M)) (p : Sched M × List Nat) : Bool :=
  p.1.halt.isSome ||
    ((succsP cfg mm env p.1).length == p.2.length &&
      ((succsP cfg mm env p.1).zip p.2).all fun (t, j) =>
        match L[j]? with
        | some u => Sched.fastEq t u
        | none => false)

/-- Each non-halted listed state has its successors at the given indices. -/
def certClosed (L : List (Sched M)) (succ : List (List Nat)) : Bool :=
  L.length == succ.length && (L.zip succ).all (edgeOK cfg mm env L)

/-! ## Closure -/

theorem closedP_of_certClosed {L : List (Sched M)} {succ : List (List Nat)}
    (h : certClosed cfg mm env L succ = true) : ClosedP cfg mm env L = true := by
  simp only [certClosed, edgeOK, Bool.and_eq_true, beq_iff_eq, List.all_eq_true] at h
  obtain ⟨hlen, hall⟩ := h
  simp only [ClosedP, List.all_eq_true, Bool.or_eq_true]
  intro s hs
  obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hs
  have hi' : i < succ.length := hlen ▸ hi
  have hz : (L[i], succ[i]) ∈ L.zip succ := by
    rw [List.mem_iff_getElem]
    exact ⟨i, by rw [List.length_zip]; exact Nat.lt_min.mpr ⟨hi, hi'⟩, by simp⟩
  have := hall _ hz
  simp only [Bool.or_eq_true, Bool.and_eq_true] at this
  rcases this with hh | ⟨hl, hedges⟩
  · exact Or.inl hh
  · right
    intro t ht
    obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem ht
    have hl' : (succsP cfg mm env L[i]).length = succ[i].length := by simpa using hl
    have hk' : k < succ[i].length := hl' ▸ hk
    have hz' : ((succsP cfg mm env L[i])[k], succ[i][k]) ∈ (succsP cfg mm env L[i]).zip succ[i] := by
      rw [List.mem_iff_getElem]
      exact ⟨k, by rw [List.length_zip]; exact Nat.lt_min.mpr ⟨hk, hk'⟩, by simp⟩
    have he := List.all_eq_true.mp hedges _ hz'
    simp only at he
    split at he
    · next u hu =>
      rw [memFast_iff]
      simp only [Sched.fastEq, Bool.and_eq_true, beq_iff_eq] at he
      rw [he.2]
      exact List.mem_of_getElem? hu
    · cases he

/-! ## Reachability of the listed states -/

/-- `t` is reachable from `s` by micro-steps of non-halted states. -/
inductive Reach (s : Sched M) : Sched M → Prop where
  | refl : Reach s s
  | tail {u : Sched M} (c : PChoice) : Reach s u → u.halt = none → Reach s (u.tickP cfg mm env c)

omit [DecidableEq M] in
theorem certGo_reach (s0 : Sched M) :
    ∀ (is : List (Option PChoice)) (st acc : List (Sched M)) (L : List (Sched M)),
      (∀ x ∈ st, Reach cfg mm env s0 x) → (∀ x ∈ acc, Reach cfg mm env s0 x) →
      certGo cfg mm env is st acc = some L → ∀ x ∈ L, Reach cfg mm env s0 x
  | [], st, acc, L, _, hacc, h => by
    simp only [certGo, Option.some.injEq] at h; subst h; exact hacc
  | some c :: is, s :: st, acc, L, hst, hacc, h => by
    simp only [certGo] at h
    split at h
    · cases h
    · next hh =>
      have hr : Reach cfg mm env s0 (s.tickP cfg mm env c) :=
        .tail c (hst s List.mem_cons_self) (by simpa using hh)
      refine certGo_reach s0 is _ _ L ?_ ?_ h
      · intro x hx
        rcases List.mem_cons.mp hx with rfl | hx
        · exact hr
        · exact hst x hx
      · intro x hx
        rcases List.mem_cons.mp hx with rfl | hx
        · exact hr
        · exact hacc x hx
  | some _ :: _, [], _, _, _, _, h => by simp [certGo] at h
  | none :: is, _ :: s :: st, acc, L, hst, hacc, h => by
    simp only [certGo] at h
    exact certGo_reach s0 is _ _ L (fun x hx => hst x (List.mem_cons_of_mem _ hx)) hacc h
  | none :: _, [], _, _, _, _, h => by simp [certGo] at h
  | none :: _, [_], _, _, _, _, h => by simp [certGo] at h

omit [DecidableEq M] in
theorem certStates_reach {io : IO} {is : List (Option PChoice)} {L : List (Sched M)}
    (h : certStates cfg mm env io is = some L) :
    ∀ x ∈ L, Reach cfg mm env (Sched.init mm io) x := by
  simp only [certStates, Option.map_eq_some_iff] at h
  obtain ⟨L', h', rfl⟩ := h
  intro x hx
  exact certGo_reach cfg mm env _ is _ _ L' (by simp [Reach.refl]) (by simp [Reach.refl]) h' x
    (List.mem_reverse.mp hx)

omit [DecidableEq M] in
theorem certGo_last (s0 : Sched M) :
    ∀ (is : List (Option PChoice)) (st acc : List (Sched M)) (L : List (Sched M)),
      acc.getLast? = some s0 → certGo cfg mm env is st acc = some L → L.getLast? = some s0
  | [], st, acc, L, ha, h => by
    simp only [certGo, Option.some.injEq] at h; subst h; exact ha
  | some c :: is, s :: st, acc, L, ha, h => by
    simp only [certGo] at h
    split at h
    · cases h
    · refine certGo_last s0 is _ _ L ?_ h
      cases acc with
      | nil => simp at ha
      | cons a as => simpa [List.getLast?_cons] using ha
  | some _ :: _, [], _, _, _, h => by simp [certGo] at h
  | none :: is, _ :: s :: st, acc, L, ha, h => by
    simp only [certGo] at h
    exact certGo_last s0 is _ _ L ha h
  | none :: _, [], _, _, _, h => by simp [certGo] at h
  | none :: _, [_], _, _, _, h => by simp [certGo] at h

omit [DecidableEq M] in
theorem init_mem_certStates {io : IO} {is : List (Option PChoice)} {L : List (Sched M)}
    (h : certStates cfg mm env io is = some L) : Sched.init mm io ∈ L := by
  simp only [certStates, Option.map_eq_some_iff] at h
  obtain ⟨L', h', rfl⟩ := h
  have := certGo_last cfg mm env (Sched.init mm io) is _ _ L' (by simp) h'
  rw [List.mem_reverse]
  exact List.mem_of_getLast? this

omit [DecidableEq M] in
theorem run_halted {s : Sched M} {x : Summary} (hh : s.halt = some x) :
    ∀ (n : Nat) (cs : List PChoice), runSchedStateP cfg mm env n cs s = s
  | 0, _ => rfl
  | _ + 1, _ => by simp only [runSchedStateP, hh]

omit [DecidableEq M] in
/-- Running `cs` and then `c` is running `cs ++ [c]` (fuel = list length). -/
theorem run_snoc (c : PChoice) :
    ∀ (cs : List PChoice) (s : Sched M),
      (runSchedStateP cfg mm env cs.length cs s).halt = none →
      runSchedStateP cfg mm env (cs.length + 1) (cs ++ [c]) s =
        (runSchedStateP cfg mm env cs.length cs s).tickP cfg mm env c
  | [], s, h => by
    have h' : s.halt = none := h
    rw [List.nil_append, runSchedStateP_succ cfg mm env _ _ _ _ h']
    rfl
  | c' :: cs, s, h => by
    cases hh : s.halt with
    | some x =>
      rw [List.length_cons, run_halted cfg mm env hh] at h
      rw [hh] at h; cases h
    | none =>
      rw [List.cons_append, List.length_cons, runSchedStateP_succ cfg mm env _ _ _ _ hh,
        runSchedStateP_succ cfg mm env _ _ _ _ hh]
      rw [List.length_cons, runSchedStateP_succ cfg mm env _ _ _ _ hh] at h
      exact run_snoc c cs _ h

omit [DecidableEq M] in
theorem reach_run {s t : Sched M} (h : Reach cfg mm env s t) :
    ∃ (cs : List PChoice), runSchedStateP cfg mm env cs.length cs s = t := by
  induction h with
  | refl => exact ⟨[], rfl⟩
  | tail c _ hu ih =>
    obtain ⟨cs, hr⟩ := ih
    refine ⟨cs ++ [c], ?_⟩
    rw [List.length_append, List.length_singleton, run_snoc cfg mm env c cs s (hr ▸ hu), hr]

/-! ## The exact outcome set -/

/-- The full check of a certificate. -/
def certExact (io : IO) (is : List (Option PChoice)) (succ : List (List Nat)) : Bool :=
  match certStates cfg mm env io is with
  | some L => certClosed cfg mm env L succ
  | none => false

/-- The observations of a certificate's states (`[]` for a bad certificate). -/
def certObs (io : IO) (is : List (Option PChoice)) : List Obs :=
  match certStates cfg mm env io is with
  | some L => L.filterMap Sched.obs
  | none => []

theorem outcomesP_iff_of_cert {io : IO} {is : List (Option PChoice)} {succ : List (List Nat)}
    (h : certExact cfg mm env io is succ = true) (o : Obs) :
    outcomesP cfg mm env io o ↔ o ∈ certObs cfg mm env io is := by
  unfold certExact at h
  unfold certObs
  split at h
  · next L hL =>
    constructor
    · exact outcomesP_sub_closed cfg mm env (closedP_of_certClosed cfg mm env h)
        (init_mem_certStates cfg mm env hL)
    · intro ho
      obtain ⟨s, hs, hso⟩ := List.mem_filterMap.mp ho
      obtain ⟨cs, hr⟩ := reach_run cfg mm env (certStates_reach cfg mm env hL s hs)
      exact ⟨cs.length, cs, by simp only [runObsP, hr, hso]⟩
  · cases h

/-! ## Chunked checks

The kernel caches what it evaluates, so one `decide` over all edges of a few thousand states
needs too much memory. `certChunk` checks the edges of the states `a, ..., a + n - 1` only;
`certExact_of_chunks` puts the chunks together. -/

/-- The edge check of the listed states with indices in `[a, a + n)`. -/
def certChunk (io : IO) (is : List (Option PChoice)) (succ : List (List Nat)) (a n : Nat) : Bool :=
  match certStates cfg mm env io is with
  | some L => L.length == succ.length && (((L.zip succ).drop a).take n).all (edgeOK cfg mm env L)
  | none => false

theorem certExact_of_chunks {io : IO} {is : List (Option PChoice)} {succ : List (List Nat)}
    (n m : Nat) (hn : 0 < n) (hm0 : 0 < m) (hm : succ.length ≤ m * n)
    (h : ∀ i < m, certChunk cfg mm env io is succ (i * n) n = true) :
    certExact cfg mm env io is succ = true := by
  have h0 := h 0 hm0
  unfold certExact
  unfold certChunk at h h0
  split
  · next L hL =>
    rw [hL] at h h0
    simp only [Bool.and_eq_true, beq_iff_eq] at h0
    have hlen : L.length = succ.length := h0.1
    simp only [certClosed, hlen, beq_self_eq_true, Bool.true_and, List.all_eq_true]
    intro x hx
    obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem hx
    have hk' : k < succ.length := by simp at hk; omega
    have hi : k / n < m := by
      rw [Nat.div_lt_iff_lt_mul hn]; omega
    have hc := h (k / n) hi
    simp only [Bool.and_eq_true, List.all_eq_true] at hc
    apply hc.2
    rw [List.mem_iff_getElem]
    have hr : k % n < n := Nat.mod_lt _ hn
    have hdk : k / n * n + k % n = k := by rw [Nat.mul_comm]; exact Nat.div_add_mod k n
    refine ⟨k % n, ?_, ?_⟩
    · simp only [List.length_take, List.length_drop]; omega
    · simp only [List.getElem_take, List.getElem_drop]
      congr 1
  · next hL => rw [hL] at h0; cases h0

/-- A single-valued outcome set: every observation of the certificate is `o₀`, and there is
one. -/
def certObsOnly (io : IO) (is : List (Option PChoice)) (o₀ : Obs) : Bool :=
  (certObs cfg mm env io is).all (· == o₀) && (certObs cfg mm env io is).contains o₀

theorem outcomesP_iff_of_certObsOnly {io : IO} {is : List (Option PChoice)}
    {succ : List (List Nat)} {o₀ : Obs} (hc : certExact cfg mm env io is succ = true)
    (h : certObsOnly cfg mm env io is o₀ = true) (o : Obs) :
    outcomesP cfg mm env io o ↔ o = o₀ := by
  simp only [certObsOnly, Bool.and_eq_true, List.all_eq_true, beq_iff_eq,
    List.contains_iff_mem] at h
  obtain ⟨hall, hmem⟩ := h
  rw [outcomesP_iff_of_cert cfg mm env hc]
  constructor
  · exact hall o
  · rintro rfl; exact hmem

end

end CatsEffectInLean.Proofs.Lemmas.CertP

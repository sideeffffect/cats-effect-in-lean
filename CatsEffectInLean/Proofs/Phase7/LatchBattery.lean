import CatsEffectInLean.Proofs.Phase7.LatchWitness

/-!
# Decision 63: the wrong-function battery of `CountDownLatch` and `CyclicBarrier`

Decision 63 (`raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md`): for every
public operation and each wrong variant (raises, hangs, drops, doubles), one registered
statement breaks, kernel-checked on one input. The variants are in the mirrors
(`Std/CountDownLatch.lean`, `Std/CyclicBarrier.lean`, `v ≠ 0`; not Cats Effect code).
`cdlXV v` / `cbXV v` is registered statement `X` with variant `v`; `X ↔ XV 0` holds by
definition (`*_iff`).

| Operation | Variant | `v` | Breaks | Input |
|---|---|---|---|---|
| `CountDownLatch.release` | raises | 4 | `cdlReleaseTotal` | `n = 1`, one awaiter, one releaser: blocked, `completed = 0`, `started = 1` |
| `CountDownLatch.release` | hangs | 5 | `cdlReleaseTotal` | the same |
| `CountDownLatch.release` | drops | 6 | `cdlNoLostWakeup` | the same: blocked, `started = 1`, the awaiter in `await` |
| `CountDownLatch.release` | doubles | 7 | `cdlAwaitNotEarly` | `n = 2`, one release: the awaiter returns with `started = 1` |
| `CountDownLatch.await` | raises | 8 | `cdlAwaitCompletes` | `n = 1`: the root is done, the awaiter has status 1 |
| `CountDownLatch.await` | hangs | 9 | `cdlNoLostWakeup` | `n = 1`: blocked, `started = 1`, status 1 |
| `CountDownLatch.await` | drops | 10 | `cdlAwaitNotEarly` | `n = 1`, no releaser: returns with `started = 0` |
| `CountDownLatch.await` | doubles | — | meaningless | `await` has no effect on the state: two `await`s return at the same time as one |
| `CyclicBarrier.await` | raises | 5 | `cbAwaitCompletes` | `cap = 1`, one awaiter: done, `waiting = 1` |
| `CyclicBarrier.await` | hangs | 6 | `cbExactGenerations` | `cap = 1`, one awaiter: blocked, `waiting = 1` |
| `CyclicBarrier.await` | drops | 7 | `cbNoEarlyTrip` | `cap = 2`, one awaiter: `passed = 1`, `entered = 1` |
| `CyclicBarrier.await` | doubles | 8 | `cbNoEarlyTrip` | the same |

`CountDownLatch` has no public `count` (only `release`, `await`, `mapK`); `CyclicBarrier` only
`await` (and `mapK`). `mapK` only applies a natural transformation to the two methods (`F ~> G`;
with `G = IO` and the identity it is the same latch), so it has no battery row.

The companion success claims (decision 63, item 3) are `cdlAwaitCompletes` and
`cbAwaitCompletes`; their satisfiability witnesses are below (`*_sat`).

Harness privacy (track S note, review 11b): the harness closures `mark` and `incr` write cells by
number (`Ref` 0, 1, 2). They are not in the statement libraries `cdlLib`/`cbLib`, which list only
variant-0 mirror closures: `*_harness_not_public` proves that no id of the library decodes to a
harness closure, and `*_forged_*` that a user program which names one is not well-formed.
-/

namespace CatsEffectInLean.Proofs.Phase7.LatchBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Proofs.Phase7.LatchWitness (u p)

/-! ## `CountDownLatch` -/

namespace CDL

open CatsEffectInLean.Props.Phase7.CountDownLatch

theorem awaitNotEarly_iff : cdlAwaitNotEarly ↔ cdlAwaitNotEarlyV 0 := Iff.rfl
theorem noLostWakeup_iff : cdlNoLostWakeup ↔ cdlNoLostWakeupV 0 := Iff.rfl
theorem releaseTotal_iff : cdlReleaseTotal ↔ cdlReleaseTotalV 0 := Iff.rfl
theorem awaitCompletes_iff : cdlAwaitCompletes ↔ cdlAwaitCompletesV 0 := Iff.rfl

theorem allWF_p_nil : AllWF [p] [] u := by
  intro q hq
  simp only [List.cons_append, List.nil_append, List.mem_cons, List.not_mem_nil, or_false] at hq
  rw [hq]; exact LatchWitness.CDL.wf _ _ _ LatchWitness.CDL.p_ok

/-- `release` raises (variant 4). -/
theorem release_raises_breaks : ¬ cdlReleaseTotalV 4 := by
  intro h
  have hb : (run [p] [p] u 1 [] 400 [] 4).halt = some .blocked := by decide +kernel
  have hc : completed (run [p] [p] u 1 [] 400 [] 4) = 0 := by decide +kernel
  have hs : started (run [p] [p] u 1 [] 400 [] 4) = 1 := by decide +kernel
  have := h u 1 [p] [p] [] LatchWitness.CDL.allWF_p_p 400 [] (.inl hb)
  omega

/-- `release` hangs (variant 5). -/
theorem release_hangs_breaks : ¬ cdlReleaseTotalV 5 := by
  intro h
  have hb : (run [p] [p] u 1 [] 400 [] 5).halt = some .blocked := by decide +kernel
  have hc : completed (run [p] [p] u 1 [] 400 [] 5) = 0 := by decide +kernel
  have hs : started (run [p] [p] u 1 [] 400 [] 5) = 1 := by decide +kernel
  have := h u 1 [p] [p] [] LatchWitness.CDL.allWF_p_p 400 [] (.inl hb)
  omega

/-- `release` drops its effect (variant 6). -/
theorem release_drops_breaks : ¬ cdlNoLostWakeupV 6 := by
  intro h
  have hb : (run [p] [p] u 1 [] 400 [] 6).halt = some .blocked := by decide +kernel
  have hs : started (run [p] [p] u 1 [] 400 [] 6) = 1 := by decide +kernel
  have hst : status (run [p] [p] u 1 [] 400 [] 6) 0 = 1 := by decide +kernel
  exact h u 1 [p] [p] [] LatchWitness.CDL.allWF_p_p 400 [] hb (by omega) 0 hst

/-- `release` doubles its effect (variant 7). -/
theorem release_doubles_breaks : ¬ cdlAwaitNotEarlyV 7 := by
  intro h
  have hst : status (run [p] [p] u 2 [] 48 [] 7) 0 = 2 := by decide +kernel
  have hs : started (run [p] [p] u 2 [] 48 [] 7) = 1 := by decide +kernel
  have := h u 2 [p] [p] [] LatchWitness.CDL.allWF_p_p 48 [] 0 hst
  omega

/-- `await` raises (variant 8). -/
theorem await_raises_breaks : ¬ cdlAwaitCompletesV 8 := by
  intro h
  have hd : (run [p] [p] u 1 [] 400 [] 8).halt = some (.done (.succeeded .unit)) := by decide +kernel
  have hst : status (run [p] [p] u 1 [] 400 [] 8) 0 = 1 := by decide +kernel
  exact h u 1 [p] [p] [] LatchWitness.CDL.allWF_p_p 400 [] _ hd 0 hst

/-- `await` hangs (variant 9). -/
theorem await_hangs_breaks : ¬ cdlNoLostWakeupV 9 := by
  intro h
  have hb : (run [p] [p] u 1 [] 400 [] 9).halt = some .blocked := by decide +kernel
  have hs : started (run [p] [p] u 1 [] 400 [] 9) = 1 := by decide +kernel
  have hst : status (run [p] [p] u 1 [] 400 [] 9) 0 = 1 := by decide +kernel
  exact h u 1 [p] [p] [] LatchWitness.CDL.allWF_p_p 400 [] hb (by omega) 0 hst

/-- `await` drops its effect (variant 10): it returns before any `release`. -/
theorem await_drops_breaks : ¬ cdlAwaitNotEarlyV 10 := by
  intro h
  have hst : status (run [p] [] u 1 [] 400 [] 10) 0 = 2 := by decide +kernel
  have hs : started (run [p] [] u 1 [] 400 [] 10) = 0 := by decide +kernel
  have := h u 1 [p] [] [] allWF_p_nil 400 [] 0 hst
  omega

/-- `cdlAwaitCompletes` is not vacuous: the root is done and the awaiter returned. -/
theorem awaitCompletes_sat :
    AllWF [p] [p] u ∧ (run [p] [p] u 1 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      status (run [p] [p] u 1 [] 400 []) 0 = 2 :=
  ⟨LatchWitness.CDL.allWF_p_p, by decide +kernel, by decide +kernel⟩

/-! ### Harness privacy (track S note): `mark` and `incr` are not in `cdlLib` -/

theorem harness_not_public (id : Nat) (h : isLibV0 id = true) : HLam.ofId? id = none := by
  simp only [isLibV0, CatsEffectInLean.Std.CountDownLatch.CLam.ofId?] at h
  simp only [HLam.ofId?]
  split
  · rename_i hl
    simp only [hl, ↓reduceIte] at h
    rcases hm : (cloOfId id).bind ofCloVal with _ | ⟨k, tag, fs⟩
    · rfl
    · rw [hm] at h
      simp only at h ⊢
      by_cases hk : k = CatsEffectInLean.Std.CountDownLatch.ns
      · have : (k == hns) = false := by
          rw [hk]; decide
        simp [this]
      · simp [hk] at h
  · rfl

/-- A user program that names the harness `mark` (it writes `Ref` 2 by number) is not
well-formed. -/
theorem forged_mark : WF.progOK cdlLib (fun h => ([] : List Handle).contains h) (.delay (HLam.mark 0 2).fn) = false := by
  decide +kernel

/-- The same for `incr` (`Ref` 0, the `started` counter). -/
theorem forged_incr : WF.progOK cdlLib (fun h => ([] : List Handle).contains h) (.delay (HLam.incr 0).fn) = false := by
  decide +kernel

end CDL

/-! ## `CyclicBarrier` -/

namespace CB

open CatsEffectInLean.Props.Phase7.CyclicBarrier

theorem noEarlyTrip_iff : cbNoEarlyTrip ↔ cbNoEarlyTripV 0 := Iff.rfl
theorem exactGenerations_iff : cbExactGenerations ↔ cbExactGenerationsV 0 := Iff.rfl
theorem awaitCompletes_iff : cbAwaitCompletes ↔ cbAwaitCompletesV 0 := Iff.rfl

theorem allWF_p : AllWF [p] [] u := LatchWitness.CB.allWF _ _ (by decide) (by decide)

/-- `await` raises (variant 5). -/
theorem await_raises_breaks : ¬ cbAwaitCompletesV 5 := by
  intro h
  have hd : (run [p] [] u 1 [] 400 [] 5).halt = some (.done (.succeeded .unit)) := by decide +kernel
  have hw : waiting (run [p] [] u 1 [] 400 [] 5) = 1 := by decide +kernel
  have := h u 1 [p] [] [] allWF_p 400 [] _ hd
  omega

/-- `await` hangs (variant 6). -/
theorem await_hangs_breaks : ¬ cbExactGenerationsV 6 := by
  intro h
  have hb : (run [p] [] u 1 [] 400 [] 6).halt = some .blocked := by decide +kernel
  have hw : waiting (run [p] [] u 1 [] 400 [] 6) = 1 := by decide +kernel
  have := (h u 1 [p] [] allWF_p 400 [] hb).2
  omega

/-- `await` drops its effect (variant 7): it returns alone with `cap = 2`. -/
theorem await_drops_breaks : ¬ cbNoEarlyTripV 7 := by
  intro h
  have hp : passed (run [p] [] u 2 [] 400 [] 7) = 1 := by decide +kernel
  have he : entered (run [p] [] u 2 [] 400 [] 7) = 1 := by decide +kernel
  have := h u 2 [p] [] allWF_p 400 []
  omega

/-- `await` doubles its effect (variant 8): one `await` counts twice and trips `cap = 2`. -/
theorem await_doubles_breaks : ¬ cbNoEarlyTripV 8 := by
  intro h
  have hp : passed (run [p] [] u 2 [] 400 [] 8) = 1 := by decide +kernel
  have he : entered (run [p] [] u 2 [] 400 [] 8) = 1 := by decide +kernel
  have := h u 2 [p] [] allWF_p 400 []
  omega

/-- `cbAwaitCompletes` is not vacuous: the root is done after a trip. -/
theorem awaitCompletes_sat :
    AllWF [p, p] [] u ∧ (run [p, p] [] u 2 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      passed (run [p, p] [] u 2 [] 400 []) = 2 :=
  ⟨LatchWitness.CB.allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel⟩

/-! ### Harness privacy: `mark` is not in `cbLib` -/

theorem harness_not_public (id : Nat) (h : isLibV0 id = true) : HLam.ofId? id = none := by
  simp only [isLibV0, CatsEffectInLean.Std.CyclicBarrier.BLam.ofId?] at h
  simp only [HLam.ofId?]
  split
  · rename_i hl
    simp only [hl, ↓reduceIte] at h
    rcases hm : (cloOfId id).bind ofCloVal with _ | ⟨k, tag, fs⟩
    · rfl
    · rw [hm] at h
      simp only at h ⊢
      by_cases hk : k = CatsEffectInLean.Std.CyclicBarrier.ns
      · have : (k == hns) = false := by
          rw [hk]; decide
        simp [this]
      · simp [hk] at h
  · rfl

/-- A user program that names the harness `mark` (it writes `Ref` 0 by number) is not
well-formed. -/
theorem forged_mark : WF.progOK cbLib (fun h => ([] : List Handle).contains h) (.delay (HLam.mark 0 2).fn) = false := by
  decide +kernel

/-- The battery closure `neverK` is not public either. -/
theorem neverK_not_public :
    isLibV0 CatsEffectInLean.Std.CyclicBarrier.BLam.neverK.id = false := by decide +kernel

end CB

end CatsEffectInLean.Proofs.Phase7.LatchBattery

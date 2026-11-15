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
| `CountDownLatch.apply` | raises | 11 | `cdlAwaitCompletes` | `n = 1`, `[p]`, `[p]`: the root is done `Errored(IllegalArgumentException)` |
| `CountDownLatch.apply` | hangs | 12 | `cdlNoDeadlock` | `n = k = m = 1`: blocked before any fiber starts |
| `CountDownLatch.apply` | drops, doubles | — | meaningless | the factory's only effect is the allocation: without it there is no latch to return; a second allocation is unreachable |
| `CyclicBarrier.apply` | raises | 9 | `cbAwaitCompletes` | `cap = 1`, `[p]`: the root is done `Errored` |
| `CyclicBarrier.apply` | hangs | 10 | `cbNoDeadlock` | `cap = 1`, `g = 1`: blocked |
| `CyclicBarrier.apply` | drops, doubles | — | meaningless | as for `CountDownLatch.apply` |

Review batch 13 (H4): the first form of `*AwaitCompletes` ("if the root is done, no await is left
open") held for an `apply` that always raises (the root is done `Errored`, no fiber starts). The
statements now claim, for `n ≥ 1` / `cap ≥ 1`, that a done root is `Succeeded(())`, and two new
statements `cdlNoDeadlock`, `cbNoDeadlock` reject a factory (or operation) that never returns.

Review batch 13 (L4): `v0_*` below run the Cats Effect v3.7.1 mirror (variant 0) on every battery
input; on each, the broken statement's conclusion holds:

| Input | v3.7.1 run |
|---|---|
| `n = 1`, `[p]`, `[p]`, fuel 400 | done `Succeeded(())`, `started = completed = 1`, status 2 (`v0_n1`) |
| `n = 2`, `[p]`, `[p]`, fuel 48 and 400 | status 1 at 48; blocked at 400 with `started = 1 < n`, status 1 (`v0_n2`) |
| `n = 1`, `[p]`, `[]`, fuel 400 | blocked, `started = 0`, status 1 (`v0_noRelease`) |
| `cap = 1`, `[p]`, fuel 400 | done `Succeeded(())`, `passed = 1`, `waiting = 0` (`v0_cap1`) |
| `cap = 2`, `[p]`, fuel 400 | blocked, `passed = 0`, `entered = 1`, `waiting = 1 < 2` (`v0_cap2`) |

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
theorem noDeadlock_iff : cdlNoDeadlock ↔ cdlNoDeadlockV 0 := Iff.rfl

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
  exact (h u 1 [p] [p] [] LatchWitness.CDL.allWF_p_p (by decide) 400 [] _ hd).2 0 hst

/-- `apply` raises (variant 11): the root ends `Errored` before any fiber starts. -/
theorem apply_raises_breaks : ¬ cdlAwaitCompletesV 11 := by
  intro h
  have hd : (run [p] [p] u 1 [] 400 [] 11).halt =
      some (.done (.errored CatsEffectInLean.Std.CountDownLatch.iaeErr)) := by decide +kernel
  have := (h u 1 [p] [p] [] LatchWitness.CDL.allWF_p_p (by decide) 400 [] _ hd).1
  cases this

/-- `apply` hangs (variant 12): the run is blocked. -/
theorem apply_hangs_breaks : ¬ cdlNoDeadlockV 12 := by
  intro h
  have hb : (run [p] [p] u 1 [] 400 [] 12).halt = some .blocked := by decide +kernel
  exact h u 1 1 1 [] LatchWitness.CDL.allWF_p_p (by decide) (by decide) 400 [] hb

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

/-- `cdlAwaitCompletes` is not vacuous: `n ≥ 1`, the root is done `Succeeded(())` and the awaiter
returned. -/
theorem awaitCompletes_sat :
    AllWF [p] [p] u ∧ 1 ≤ 1 ∧ (run [p] [p] u 1 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      status (run [p] [p] u 1 [] 400 []) 0 = 2 :=
  ⟨LatchWitness.CDL.allWF_p_p, by decide, by decide +kernel, by decide +kernel⟩

/-- `cdlNoDeadlock` is not vacuous: its hypotheses hold (`k = m = n = 1`), the awaiter waits and is
released, and the run completes. -/
theorem noDeadlock_sat :
    AllWF (List.replicate 1 (.pure .unit)) (List.replicate 1 (.pure .unit)) u ∧ 1 ≤ 1 ∧ 1 ≤ 1 ∧
      (run [p] [p] u 1 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      status (run [p] [p] u 1 [] 400 []) 0 = 2 :=
  ⟨LatchWitness.CDL.allWF_p_p, by decide, by decide, by decide +kernel, by decide +kernel⟩

/-! ### Review 13 L4: Cats Effect v3.7.1 (variant 0) on every battery input -/

theorem v0_n1 :
    (run [p] [p] u 1 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      started (run [p] [p] u 1 [] 400 []) = 1 ∧ completed (run [p] [p] u 1 [] 400 []) = 1 ∧
      status (run [p] [p] u 1 [] 400 []) 0 = 2 :=
  ⟨by decide +kernel, by decide +kernel, by decide +kernel, by decide +kernel⟩

theorem v0_n2 :
    status (run [p] [p] u 2 [] 48 []) 0 = 1 ∧ (run [p] [p] u 2 [] 400 []).halt = some .blocked ∧
      started (run [p] [p] u 2 [] 400 []) = 1 ∧ status (run [p] [p] u 2 [] 400 []) 0 = 1 :=
  ⟨by decide +kernel, by decide +kernel, by decide +kernel, by decide +kernel⟩

theorem v0_noRelease :
    (run [p] [] u 1 [] 400 []).halt = some .blocked ∧ started (run [p] [] u 1 [] 400 []) = 0 ∧
      status (run [p] [] u 1 [] 400 []) 0 = 1 :=
  ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩

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
theorem noDeadlock_iff : cbNoDeadlock ↔ cbNoDeadlockV 0 := Iff.rfl

theorem allWF_p : AllWF [p] [] u := LatchWitness.CB.allWF _ _ (by decide) (by decide)

/-- `await` raises (variant 5). -/
theorem await_raises_breaks : ¬ cbAwaitCompletesV 5 := by
  intro h
  have hd : (run [p] [] u 1 [] 400 [] 5).halt = some (.done (.succeeded .unit)) := by decide +kernel
  have hw : waiting (run [p] [] u 1 [] 400 [] 5) = 1 := by decide +kernel
  have := (h u 1 [p] [] [] allWF_p (by decide) 400 [] _ hd).2
  omega

/-- `apply` raises (variant 9). -/
theorem apply_raises_breaks : ¬ cbAwaitCompletesV 9 := by
  intro h
  have hd : (run [p] [] u 1 [] 400 [] 9).halt =
      some (.done (.errored CatsEffectInLean.Std.CyclicBarrier.iaeErr)) := by decide +kernel
  have := (h u 1 [p] [] [] allWF_p (by decide) 400 [] _ hd).1
  cases this

/-- `apply` hangs (variant 10). -/
theorem apply_hangs_breaks : ¬ cbNoDeadlockV 10 := by
  intro h
  have hb : (run [p] [] u 1 [] 400 [] 10).halt = some .blocked := by decide +kernel
  exact h u 1 1 allWF_p (by decide) 400 [] hb

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

/-- `cbAwaitCompletes` is not vacuous: `cap ≥ 1`, the root is done `Succeeded(())` after a trip. -/
theorem awaitCompletes_sat :
    AllWF [p, p] [] u ∧ 1 ≤ 2 ∧ (run [p, p] [] u 2 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      passed (run [p, p] [] u 2 [] 400 []) = 2 :=
  ⟨LatchWitness.CB.allWF _ _ (by decide) (by decide), by decide, by decide +kernel, by decide +kernel⟩

/-- `cbNoDeadlock` is not vacuous: `cap = 2`, `g = 1`; the first awaiter waits, the second trips. -/
theorem noDeadlock_sat :
    AllWF (List.replicate (2 * 1) (.pure .unit)) [] u ∧ 1 ≤ 2 ∧
      (run [p, p] [] u 2 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      passed (run [p, p] [] u 2 [] 400 []) = 2 :=
  ⟨LatchWitness.CB.allWF _ _ (by decide) (by decide), by decide, by decide +kernel, by decide +kernel⟩

/-! ### Review 13 L4: Cats Effect v3.7.1 (variant 0) on every battery input -/

theorem v0_cap1 :
    (run [p] [] u 1 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      passed (run [p] [] u 1 [] 400 []) = 1 ∧ waiting (run [p] [] u 1 [] 400 []) = 0 :=
  ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩

theorem v0_cap2 :
    (run [p] [] u 2 [] 400 []).halt = some .blocked ∧ passed (run [p] [] u 2 [] 400 []) = 0 ∧
      entered (run [p] [] u 2 [] 400 []) = 1 ∧ waiting (run [p] [] u 2 [] 400 []) = 1 :=
  ⟨by decide +kernel, by decide +kernel, by decide +kernel, by decide +kernel⟩

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

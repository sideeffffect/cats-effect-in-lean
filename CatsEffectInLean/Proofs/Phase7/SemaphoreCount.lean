import CatsEffectInLean.Props.Phase7.Semaphore

/-!
# `count` at rest: refuted (CE-0060)

`Props.Phase7.Semaphore.semCountAtRest` is false. Witness: `Semaphore[IO](0)`, two fibers that
each run `uncancelable(poll => poll(s.acquireN(1)) *> s.releaseN(1))`; the parent cedes twice (both
fibers enqueue: `A` first, then `B`), then cancels `B`, then `A`.

* `B` is not the head of the queue: its `cleanup` completes its gate (`won = true`) and calls
  `reclaim(B)`, which does nothing because the head is `A` (`Semaphore.scala:171-175`).
* `A` is the head: `reclaim(A)` removes it and calls `releaseN(A.sunk) = releaseN(0) = F.unit`
  (`Semaphore.scala:173`, `:229`). No release reaches `B`, so the canceled `B` stays in the queue.

Both fibers have ended, nobody waits, `available = 0`, but `count = -1`
(`-waiting.foldMap(_.remaining)`, `Semaphore.scala:261`). The run is the default schedule
(`pick 0` at each step, FIFO), fuel 92; the kernel evaluates it.
-/

namespace CatsEffectInLean.Proofs.Phase7

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase7.Semaphore

/-- The two uses: `acquireN(1)` then `releaseN(1)`, the acquire cancelable. -/
def countBus : List BUse := [.acqRel 1, .acqRel 1]

/-- The parent: two cedes, then cancel the second fiber, then the first. -/
def countActs : List Act := [.cede, .cede, .cancel 1, .cancel 0]

/-- The witness root. -/
def countRoot : IO := lockRoot (.sem 0) (countBus.map BUse.toUse) countActs

/-- The witness run ends `Succeeded((0, -1))`. -/
theorem countRun :
    (runObsP {} counterMaskModel (env behaved) 92 [] countRoot).map Obs.summary =
      some (.done (.succeeded (.pair (.nat 0) (.int (-1))))) := by
  decide +kernel

theorem countEnded : AllEnded countBus.length countActs := by
  intro i hi
  simp only [countBus, List.length_cons, List.length_nil] at hi
  match i, hi with
  | 0, _ => exact .inl (by decide)
  | 1, _ => exact .inl (by decide)

theorem semCountAtRest_refuted : ¬ semCountAtRest := by
  intro h
  cases hr : runObsP {} counterMaskModel (env behaved) 92 [] countRoot with
  | none => have := countRun; rw [hr] at this; cases this
  | some o =>
    have hs : o.summary = .done (.succeeded (.pair (.nat 0) (.int (-1)))) := by
      have := countRun; rw [hr] at this; simpa using this
    obtain ⟨a, ha, hc⟩ := h 0 countBus countActs countEnded o ⟨92, [], hr⟩ _ hs
    simp only [availOf, Option.some.injEq] at ha
    subst ha
    simp [countOf] at hc

end CatsEffectInLean.Proofs.Phase7

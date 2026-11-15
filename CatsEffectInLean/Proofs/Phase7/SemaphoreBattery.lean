import CatsEffectInLean.Proofs.Phase7.SemaphoreBatteryDefs
import CatsEffectInLean.Proofs.Phase7.SemaphoreWitness

/-!
# Wrong-function battery of `Semaphore` and `Mutex` (decision 63): kernel-checked breaks

Generated table (one theorem per row): each wrong function (`SemaphoreBatteryDefs.lean`) runs on
one input that meets the decidable hypotheses of the named statement (checked in `inputs_ok`),
and the run violates the statement's conclusion (`c2`, `c4`, `c5`, `c7` = the conclusions of
`semNoDeadlock`, `mutexMutualExclusion`, `mutexNoDeadlock`, `semFifo`). The `good_*` theorems run
the same inputs on the v3.7.1 mirror, which meets the conclusion. Default schedule (`pick 0`),
fuel 3000, except `lock`/drops (one preemption at step 30; `mutexMutualExclusion` with the
constant user code `cu`, whose `WellFormed` hypothesis holds for the wrong environment too:
`lockDrops_wf`).

| op | raises | hangs | drops | doubles |
|---|---|---|---|---|
| acquire (`acquireN(1)`) | stmt 2 | stmt 2 | stmt 2 | stmt 2 |
| acquireN (`n ≥ 2`) | stmt 2 | stmt 2 | stmt 2 | stmt 2 |
| release (`releaseN(1)`) | stmt 2 | stmt 2 | stmt 2 | stmt 2 |
| releaseN (`n ≥ 2`) | stmt 2 | stmt 2 | stmt 2 | stmt 2 |
| tryAcquire | stmt 2 | stmt 2 | stmt 2 | stmt 2 |
| tryAcquireN | stmt 2 | stmt 2 | stmt 2 | stmt 2 |
| available | stmt 2 | stmt 2 | n/a (read): wrong value, stmt 2 | n/a (read) |
| count | stmt 2 | stmt 2 | n/a (read): wrong value, stmt 7 | n/a (read) |
| permit | stmt 2 | stmt 2 | stmt 2 | stmt 2 |
| lock | stmt 5 | stmt 5 | stmt 4 | stmt 5 |

Statement numbers: 2 `std.Semaphore.noDeadlock`, 4 `std.Mutex.lock.mutualExclusion`, 5
`std.Mutex.lock.noDeadlock`, 7 `std.Semaphore.acquireN.fifo`.
-/

namespace CatsEffectInLean.Proofs.Phase7.SemaphoreBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase7.Semaphore

/-- A semaphore row: the run of `lockRoot (.sem k)` on behaviour tables. -/
def semRun (e : UserEnv) (k : Nat) (bus : List BUse) (as : List Act) : Option Obs :=
  runObsP {} counterMaskModel e 3000 [] (lockRoot (.sem k) (bus.map BUse.toUse) as)

def mutRun (e : UserEnv) (bus : List BUse) (as : List Act) : Option Obs :=
  runObsP {} counterMaskModel e 3000 [] (lockRoot .mutex (bus.map BUse.toUse) as)

theorem acquire_raises : (semRun (wrongEnv .acquire .raises behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem acquire_hangs : (semRun (wrongEnv .acquire .hangs behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem acquire_drops : (semRun (wrongEnv .acquire .drops behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem acquire_doubles : (semRun (wrongEnv .acquire .doubles behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem good_acquire : (semRun (env behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some true := by
  decide +kernel

theorem acquireN_raises : (semRun (wrongEnv .acquireN .raises behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem acquireN_hangs : (semRun (wrongEnv .acquireN .hangs behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem acquireN_drops : (semRun (wrongEnv .acquireN .drops behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem acquireN_doubles : (semRun (wrongEnv .acquireN .doubles behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem good_acquireN : (semRun (env behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some true := by
  decide +kernel

theorem release_raises : (semRun (wrongEnv .release .raises behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem release_hangs : (semRun (wrongEnv .release .hangs behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem release_drops : (semRun (wrongEnv .release .drops behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem release_doubles : (semRun (wrongEnv .release .doubles behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some false := by
  decide +kernel

theorem good_release : (semRun (env behaved) 1 [.acqRel 1] [.join 0]).map (c2 [.acqRel 1] [.join 0] 1) = some true := by
  decide +kernel

theorem releaseN_raises : (semRun (wrongEnv .releaseN .raises behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem releaseN_hangs : (semRun (wrongEnv .releaseN .hangs behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem releaseN_drops : (semRun (wrongEnv .releaseN .drops behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem releaseN_doubles : (semRun (wrongEnv .releaseN .doubles behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some false := by
  decide +kernel

theorem good_releaseN : (semRun (env behaved) 2 [.acqRel 2] [.join 0]).map (c2 [.acqRel 2] [.join 0] 2) = some true := by
  decide +kernel

theorem tryAcquire_raises : (semRun (wrongEnv .tryAcquire .raises behaved) 2 [.tryRel 1] [.join 0]).map (c2 [.tryRel 1] [.join 0] 2) = some false := by
  decide +kernel

theorem tryAcquire_hangs : (semRun (wrongEnv .tryAcquire .hangs behaved) 2 [.tryRel 1] [.join 0]).map (c2 [.tryRel 1] [.join 0] 2) = some false := by
  decide +kernel

theorem tryAcquire_drops : (semRun (wrongEnv .tryAcquire .drops behaved) 2 [.tryRel 1] [.join 0]).map (c2 [.tryRel 1] [.join 0] 2) = some false := by
  decide +kernel

theorem tryAcquire_doubles : (semRun (wrongEnv .tryAcquire .doubles behaved) 2 [.tryRel 1] [.join 0]).map (c2 [.tryRel 1] [.join 0] 2) = some false := by
  decide +kernel

theorem good_tryAcquire : (semRun (env behaved) 2 [.tryRel 1] [.join 0]).map (c2 [.tryRel 1] [.join 0] 2) = some true := by
  decide +kernel

theorem tryAcquireN_raises : (semRun (wrongEnv .tryAcquireN .raises behaved) 4 [.tryRel 2] [.join 0]).map (c2 [.tryRel 2] [.join 0] 4) = some false := by
  decide +kernel

theorem tryAcquireN_hangs : (semRun (wrongEnv .tryAcquireN .hangs behaved) 4 [.tryRel 2] [.join 0]).map (c2 [.tryRel 2] [.join 0] 4) = some false := by
  decide +kernel

theorem tryAcquireN_drops : (semRun (wrongEnv .tryAcquireN .drops behaved) 4 [.tryRel 2] [.join 0]).map (c2 [.tryRel 2] [.join 0] 4) = some false := by
  decide +kernel

theorem tryAcquireN_doubles : (semRun (wrongEnv .tryAcquireN .doubles behaved) 4 [.tryRel 2] [.join 0]).map (c2 [.tryRel 2] [.join 0] 4) = some false := by
  decide +kernel

theorem good_tryAcquireN : (semRun (env behaved) 4 [.tryRel 2] [.join 0]).map (c2 [.tryRel 2] [.join 0] 4) = some true := by
  decide +kernel

theorem permit_raises : (semRun (wrongEnv .permit .raises behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem permit_hangs : (semRun (wrongEnv .permit .hangs behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem permit_drops : (semRun (wrongEnv .permit .drops behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem permit_doubles : (semRun (wrongEnv .permit .doubles behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem good_permit : (semRun (env behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some true := by
  decide +kernel

theorem available_raises : (semRun (wrongEnv .available .raises behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem available_hangs : (semRun (wrongEnv .available .hangs behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem available_wrongValue : (semRun (wrongEnv .available .wrongValue behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem count_raises : (semRun (wrongEnv .count .raises behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

theorem count_hangs : (semRun (wrongEnv .count .hangs behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := by
  decide +kernel

/-- `count` returns one more: the FIFO statement with no request (`releaseN(1)`, then `count`). -/
theorem count_wrongValue : (runObsP {} counterMaskModel (wrongFifo .count .wrongValue) 3000 [] (fifoRoot [] 1)).map (c7 [] 1) = some false := by
  decide +kernel
theorem good_count_fifo : (runObsP {} counterMaskModel fifoEnv 3000 [] (fifoRoot [] 1)).map (c7 [] 1) = some true := by
  decide +kernel

theorem lock_raises : (mutRun (wrongEnv .lock .raises behaved) [.permit 0 (.ok .unit)] [.join 0]).map (c5 [.permit 0 (.ok .unit)] [.join 0]) = some false := by
  decide +kernel

theorem lock_hangs : (mutRun (wrongEnv .lock .hangs behaved) [.permit 0 (.ok .unit)] [.join 0]).map (c5 [.permit 0 (.ok .unit)] [.join 0]) = some false := by
  decide +kernel

theorem lock_doubles : (mutRun (wrongEnv .lock .doubles behaved) [.permit 0 (.ok .unit)] [.join 0]).map (c5 [.permit 0 (.ok .unit)] [.join 0]) = some false := by
  decide +kernel

theorem good_lock : (mutRun (env behaved) [.permit 0 (.ok .unit)] [.join 0]).map (c5 [.permit 0 (.ok .unit)] [.join 0]) = some true := by
  decide +kernel

/-! ### `lock` drops: two holders at once (`mutexMutualExclusion`) -/

def lockRoot2 : IO := lockRoot .mutex [.counted 2, .counted 2] [.join 0, .join 1]

/-- One preemption at step 30. -/
def sched30 : List PChoice := List.replicate 29 (.pick 0) ++ [.preempt]

theorem lock_drops :
    (runObsP {} counterMaskModel (wrongEnv .lock .drops SemaphoreWitness.cu) 3000 sched30 lockRoot2).map c4 = some false := by
  decide +kernel

theorem good_lock_drops :
    (runObsP {} counterMaskModel (env SemaphoreWitness.cu) 3000 sched30 lockRoot2).map c4 = some true := by
  decide +kernel

theorem wrong_even (op : Op) (var : Var) (u : UserEnv) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (wrongEnv op var u).callV id a v = u.callV id a v := by
  have h1 : CatsEffectInLean.Model.Semaphore.SL.ofId? id = none := by
    simp [CatsEffectInLean.Model.Semaphore.SL.ofId?, isLibId, hid]
  have h2 : Mutex.ML.ofId? id = none := by simp [Mutex.ML.ofId?, isLibId, hid]
  have h3 : Bracket.BLam.ofId? id = none := Bracket.BLam.ofId?_even hid
  have h4 : HS.ofId? id = none := by simp [HS.ofId?, isLibId, hid]
  show (if id % 2 == 0 then _ else _) = _
  simp [hid, Mutex.env, Mutex.dispatch, Mutex.dispatch.go, h1, h2, h3, inner, harnessed, h4]

/-- The `WellFormed` hypothesis of `mutexMutualExclusion` holds for the wrong environment of the
`lock_drops` row (the wrong function changes only library closures, odd ids). -/
theorem lockDrops_wf : WellFormed semLib [] (wrongEnv .lock .drops SemaphoreWitness.cu) lockRoot2 := by
  have he : ∀ id, id % 2 = 0 → ∀ a v, (wrongEnv .lock .drops SemaphoreWitness.cu).callV id a v =
      SemaphoreWitness.cR (id / 2) := fun id hid a v => by rw [wrong_even _ _ _ id hid]; rfl
  exact ⟨by decide +kernel, fun id hid arg v => ⟨fun w _ => by rw [he id hid, he id hid],
    by rw [he id hid]; exact SemaphoreWitness.cR_ok _ _ _⟩, SemaphoreWitness.constOpaque _ he⟩

/-- The decidable hypotheses of the rows: `AllEnded` and `need ≤ k` (statement 2), `AllEnded` and
`permit` uses only (statement 5). -/
theorem inputs_ok :
    (∀ b ∈ ([.acqRel 1] : List BUse), b.need ≤ 1) ∧ (∀ b ∈ ([.acqRel 2] : List BUse), b.need ≤ 2) ∧
    (∀ b ∈ ([.tryRel 1] : List BUse), b.need ≤ 2) ∧ (∀ b ∈ ([.tryRel 2] : List BUse), b.need ≤ 4) ∧
    (∀ b ∈ ([.permit 0 (.ok .unit)] : List BUse), b.need ≤ 1) ∧
    AllEnded 1 [.join 0] := by
  refine ⟨by decide, by decide, by decide, by decide, by decide, ?_⟩
  intro i hi
  match i, hi with
  | 0, _ => exact .inr (by decide)

/-- `availRaises` of review batch 12 (H2): `Semaphore#available` always raises. The root ends
`Errored(E9)`, which the review-batch-12 form of statement 2 rejects. -/
theorem availRaises : (semRun (wrongEnv .available .raises behaved) 1 [.permit 0 (.ok .unit)] [.join 0]).map
    (c2 [.permit 0 (.ok .unit)] [.join 0] 1) = some false := available_raises


end CatsEffectInLean.Proofs.Phase7.SemaphoreBattery

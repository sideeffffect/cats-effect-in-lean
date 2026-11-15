import CatsEffectInLean.Proofs.Phase7.QueueBatteryDefs

/-!
# Decision 63 battery for `Queue`: the honest drops (review batch 14 C1)

`battery .tryOffer .dropsHonest`: `tryOffer` always answers `false` with no effect;
`battery .tryTake .dropsHonest`: `tryTake` always answers `None` with no effect. On each of the six
non-`Synchronous` classes (`BoundedQueue`, `DroppingQueue`, `CircularBufferQueue`, `BoundedAsyncQueue`, `UnboundedAsyncQueue`, `DroppingAsyncQueue`) each breaks `SeqSpec` on its input
(`inputOf`: `[tryOffer 1, size]`, `[offer 1, offer 2, tryTake, size]`; FIFO schedule, fuel 3000,
kernel-checked). The mirror rows are in `QueueBattery{Conc,Async,ConcOther,AsyncOther}`.
`Synchronous`: `QueueBatterySync` (`sync_tryOffer_false_breaks`, `sync_tryTake_drops`).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

theorem conc_tryOffer_dropsHonest : specOK (battery .tryOffer .dropsHonest) (.boundedConc 2) .tryOffer = some false := by
  decide +kernel

theorem conc_tryTake_dropsHonest : specOK (battery .tryTake .dropsHonest) (.boundedConc 2) .tryTake = some false := by
  decide +kernel

theorem droppingConc_tryOffer_dropsHonest : specOK (battery .tryOffer .dropsHonest) (.droppingConc 2) .tryOffer = some false := by
  decide +kernel

theorem droppingConc_tryTake_dropsHonest : specOK (battery .tryTake .dropsHonest) (.droppingConc 2) .tryTake = some false := by
  decide +kernel

theorem circular_tryOffer_dropsHonest : specOK (battery .tryOffer .dropsHonest) (.circular 2) .tryOffer = some false := by
  decide +kernel

theorem circular_tryTake_dropsHonest : specOK (battery .tryTake .dropsHonest) (.circular 2) .tryTake = some false := by
  decide +kernel

theorem async_tryOffer_dropsHonest : specOK (battery .tryOffer .dropsHonest) (.bounded 2) .tryOffer = some false := by
  decide +kernel

theorem async_tryTake_dropsHonest : specOK (battery .tryTake .dropsHonest) (.bounded 2) .tryTake = some false := by
  decide +kernel

theorem unboundedAsync_tryOffer_dropsHonest : specOK (battery .tryOffer .dropsHonest) (.unbounded) .tryOffer = some false := by
  decide +kernel

theorem unboundedAsync_tryTake_dropsHonest : specOK (battery .tryTake .dropsHonest) (.unbounded) .tryTake = some false := by
  decide +kernel

theorem droppingAsync_tryOffer_dropsHonest : specOK (battery .tryOffer .dropsHonest) (.dropping 2) .tryOffer = some false := by
  decide +kernel

theorem droppingAsync_tryTake_dropsHonest : specOK (battery .tryTake .dropsHonest) (.dropping 2) .tryTake = some false := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueBattery

import CatsEffectInLean.Proofs.Phase7.QueueBatteryDefs

/-!
# Decision 63 battery for `Queue`: `DroppingQueue` (`droppingForConcurrent(2)`) and `CircularBufferQueue` (`circularBuffer(2)`) (review batch 13 L1)

The same rows as `QueueBatteryConc`/`QueueBatteryAsync` on the other queue classes. Each theorem:
the broken operation breaks `SeqSpec` on its input (`inputOf op`, FIFO schedule, fuel 3000,
kernel-checked); `*_mirror`: the real mirror meets `SeqSpec` on the same input. `size`
`drops`/`doubles` are meaningless (read only).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

theorem droppingConc_offer_mirror : specOK henv (.droppingConc 2) .offer = some true := by
  decide +kernel

theorem droppingConc_offer_raises : specOK (battery .offer .raises) (.droppingConc 2) .offer = some false := by
  decide +kernel

theorem droppingConc_offer_hangs : specOK (battery .offer .hangs) (.droppingConc 2) .offer = some false := by
  decide +kernel

theorem droppingConc_offer_drops : specOK (battery .offer .drops) (.droppingConc 2) .offer = some false := by
  decide +kernel

theorem droppingConc_offer_doubles : specOK (battery .offer .doubles) (.droppingConc 2) .offer = some false := by
  decide +kernel

theorem droppingConc_tryOffer_mirror : specOK henv (.droppingConc 2) .tryOffer = some true := by
  decide +kernel

theorem droppingConc_tryOffer_raises : specOK (battery .tryOffer .raises) (.droppingConc 2) .tryOffer = some false := by
  decide +kernel

theorem droppingConc_tryOffer_hangs : specOK (battery .tryOffer .hangs) (.droppingConc 2) .tryOffer = some false := by
  decide +kernel

theorem droppingConc_tryOffer_drops : specOK (battery .tryOffer .drops) (.droppingConc 2) .tryOffer = some false := by
  decide +kernel

theorem droppingConc_tryOffer_doubles : specOK (battery .tryOffer .doubles) (.droppingConc 2) .tryOffer = some false := by
  decide +kernel

theorem droppingConc_take_mirror : specOK henv (.droppingConc 2) .take = some true := by
  decide +kernel

theorem droppingConc_take_raises : specOK (battery .take .raises) (.droppingConc 2) .take = some false := by
  decide +kernel

theorem droppingConc_take_hangs : specOK (battery .take .hangs) (.droppingConc 2) .take = some false := by
  decide +kernel

theorem droppingConc_take_drops : specOK (battery .take .drops) (.droppingConc 2) .take = some false := by
  decide +kernel

theorem droppingConc_take_doubles : specOK (battery .take .doubles) (.droppingConc 2) .take = some false := by
  decide +kernel

theorem droppingConc_tryTake_mirror : specOK henv (.droppingConc 2) .tryTake = some true := by
  decide +kernel

theorem droppingConc_tryTake_raises : specOK (battery .tryTake .raises) (.droppingConc 2) .tryTake = some false := by
  decide +kernel

theorem droppingConc_tryTake_hangs : specOK (battery .tryTake .hangs) (.droppingConc 2) .tryTake = some false := by
  decide +kernel

theorem droppingConc_tryTake_drops : specOK (battery .tryTake .drops) (.droppingConc 2) .tryTake = some false := by
  decide +kernel

theorem droppingConc_tryTake_doubles : specOK (battery .tryTake .doubles) (.droppingConc 2) .tryTake = some false := by
  decide +kernel

theorem droppingConc_size_mirror : specOK henv (.droppingConc 2) .size = some true := by
  decide +kernel

theorem droppingConc_size_raises : specOK (battery .size .raises) (.droppingConc 2) .size = some false := by
  decide +kernel

theorem droppingConc_size_hangs : specOK (battery .size .hangs) (.droppingConc 2) .size = some false := by
  decide +kernel

theorem circular_offer_mirror : specOK henv (.circular 2) .offer = some true := by
  decide +kernel

theorem circular_offer_raises : specOK (battery .offer .raises) (.circular 2) .offer = some false := by
  decide +kernel

theorem circular_offer_hangs : specOK (battery .offer .hangs) (.circular 2) .offer = some false := by
  decide +kernel

theorem circular_offer_drops : specOK (battery .offer .drops) (.circular 2) .offer = some false := by
  decide +kernel

theorem circular_offer_doubles : specOK (battery .offer .doubles) (.circular 2) .offer = some false := by
  decide +kernel

theorem circular_tryOffer_mirror : specOK henv (.circular 2) .tryOffer = some true := by
  decide +kernel

theorem circular_tryOffer_raises : specOK (battery .tryOffer .raises) (.circular 2) .tryOffer = some false := by
  decide +kernel

theorem circular_tryOffer_hangs : specOK (battery .tryOffer .hangs) (.circular 2) .tryOffer = some false := by
  decide +kernel

theorem circular_tryOffer_drops : specOK (battery .tryOffer .drops) (.circular 2) .tryOffer = some false := by
  decide +kernel

theorem circular_tryOffer_doubles : specOK (battery .tryOffer .doubles) (.circular 2) .tryOffer = some false := by
  decide +kernel

theorem circular_take_mirror : specOK henv (.circular 2) .take = some true := by
  decide +kernel

theorem circular_take_raises : specOK (battery .take .raises) (.circular 2) .take = some false := by
  decide +kernel

theorem circular_take_hangs : specOK (battery .take .hangs) (.circular 2) .take = some false := by
  decide +kernel

theorem circular_take_drops : specOK (battery .take .drops) (.circular 2) .take = some false := by
  decide +kernel

theorem circular_take_doubles : specOK (battery .take .doubles) (.circular 2) .take = some false := by
  decide +kernel

theorem circular_tryTake_mirror : specOK henv (.circular 2) .tryTake = some true := by
  decide +kernel

theorem circular_tryTake_raises : specOK (battery .tryTake .raises) (.circular 2) .tryTake = some false := by
  decide +kernel

theorem circular_tryTake_hangs : specOK (battery .tryTake .hangs) (.circular 2) .tryTake = some false := by
  decide +kernel

theorem circular_tryTake_drops : specOK (battery .tryTake .drops) (.circular 2) .tryTake = some false := by
  decide +kernel

theorem circular_tryTake_doubles : specOK (battery .tryTake .doubles) (.circular 2) .tryTake = some false := by
  decide +kernel

theorem circular_size_mirror : specOK henv (.circular 2) .size = some true := by
  decide +kernel

theorem circular_size_raises : specOK (battery .size .raises) (.circular 2) .size = some false := by
  decide +kernel

theorem circular_size_hangs : specOK (battery .size .hangs) (.circular 2) .size = some false := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueBattery

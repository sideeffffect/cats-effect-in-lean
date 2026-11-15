import CatsEffectInLean.Proofs.Phase7.QueueBatteryDefs

/-!
# Decision 63 battery for `Queue`: `UnboundedAsyncQueue` (`unbounded`) and `DroppingAsyncQueue` (`dropping(2)`) (review batch 13 L1)

The same rows as `QueueBatteryConc`/`QueueBatteryAsync` on the other queue classes. Each theorem:
the broken operation breaks `SeqSpec` on its input (`inputOf op`, FIFO schedule, fuel 3000,
kernel-checked); `*_mirror`: the real mirror meets `SeqSpec` on the same input. `size`
`drops`/`doubles` are meaningless (read only).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

theorem unboundedAsync_offer_mirror : specOK henv (.unbounded) .offer = some true := by
  decide +kernel

theorem unboundedAsync_offer_raises : specOK (battery .offer .raises) (.unbounded) .offer = some false := by
  decide +kernel

theorem unboundedAsync_offer_hangs : specOK (battery .offer .hangs) (.unbounded) .offer = some false := by
  decide +kernel

theorem unboundedAsync_offer_drops : specOK (battery .offer .drops) (.unbounded) .offer = some false := by
  decide +kernel

theorem unboundedAsync_offer_doubles : specOK (battery .offer .doubles) (.unbounded) .offer = some false := by
  decide +kernel

theorem unboundedAsync_tryOffer_mirror : specOK henv (.unbounded) .tryOffer = some true := by
  decide +kernel

theorem unboundedAsync_tryOffer_raises : specOK (battery .tryOffer .raises) (.unbounded) .tryOffer = some false := by
  decide +kernel

theorem unboundedAsync_tryOffer_hangs : specOK (battery .tryOffer .hangs) (.unbounded) .tryOffer = some false := by
  decide +kernel

theorem unboundedAsync_tryOffer_drops : specOK (battery .tryOffer .drops) (.unbounded) .tryOffer = some false := by
  decide +kernel

theorem unboundedAsync_tryOffer_doubles : specOK (battery .tryOffer .doubles) (.unbounded) .tryOffer = some false := by
  decide +kernel

theorem unboundedAsync_take_mirror : specOK henv (.unbounded) .take = some true := by
  decide +kernel

theorem unboundedAsync_take_raises : specOK (battery .take .raises) (.unbounded) .take = some false := by
  decide +kernel

theorem unboundedAsync_take_hangs : specOK (battery .take .hangs) (.unbounded) .take = some false := by
  decide +kernel

theorem unboundedAsync_take_drops : specOK (battery .take .drops) (.unbounded) .take = some false := by
  decide +kernel

theorem unboundedAsync_take_doubles : specOK (battery .take .doubles) (.unbounded) .take = some false := by
  decide +kernel

theorem unboundedAsync_tryTake_mirror : specOK henv (.unbounded) .tryTake = some true := by
  decide +kernel

theorem unboundedAsync_tryTake_raises : specOK (battery .tryTake .raises) (.unbounded) .tryTake = some false := by
  decide +kernel

theorem unboundedAsync_tryTake_hangs : specOK (battery .tryTake .hangs) (.unbounded) .tryTake = some false := by
  decide +kernel

theorem unboundedAsync_tryTake_drops : specOK (battery .tryTake .drops) (.unbounded) .tryTake = some false := by
  decide +kernel

theorem unboundedAsync_tryTake_doubles : specOK (battery .tryTake .doubles) (.unbounded) .tryTake = some false := by
  decide +kernel

theorem unboundedAsync_size_mirror : specOK henv (.unbounded) .size = some true := by
  decide +kernel

theorem unboundedAsync_size_raises : specOK (battery .size .raises) (.unbounded) .size = some false := by
  decide +kernel

theorem unboundedAsync_size_hangs : specOK (battery .size .hangs) (.unbounded) .size = some false := by
  decide +kernel

theorem droppingAsync_offer_mirror : specOK henv (.dropping 2) .offer = some true := by
  decide +kernel

theorem droppingAsync_offer_raises : specOK (battery .offer .raises) (.dropping 2) .offer = some false := by
  decide +kernel

theorem droppingAsync_offer_hangs : specOK (battery .offer .hangs) (.dropping 2) .offer = some false := by
  decide +kernel

theorem droppingAsync_offer_drops : specOK (battery .offer .drops) (.dropping 2) .offer = some false := by
  decide +kernel

theorem droppingAsync_offer_doubles : specOK (battery .offer .doubles) (.dropping 2) .offer = some false := by
  decide +kernel

theorem droppingAsync_tryOffer_mirror : specOK henv (.dropping 2) .tryOffer = some true := by
  decide +kernel

theorem droppingAsync_tryOffer_raises : specOK (battery .tryOffer .raises) (.dropping 2) .tryOffer = some false := by
  decide +kernel

theorem droppingAsync_tryOffer_hangs : specOK (battery .tryOffer .hangs) (.dropping 2) .tryOffer = some false := by
  decide +kernel

theorem droppingAsync_tryOffer_drops : specOK (battery .tryOffer .drops) (.dropping 2) .tryOffer = some false := by
  decide +kernel

theorem droppingAsync_tryOffer_doubles : specOK (battery .tryOffer .doubles) (.dropping 2) .tryOffer = some false := by
  decide +kernel

theorem droppingAsync_take_mirror : specOK henv (.dropping 2) .take = some true := by
  decide +kernel

theorem droppingAsync_take_raises : specOK (battery .take .raises) (.dropping 2) .take = some false := by
  decide +kernel

theorem droppingAsync_take_hangs : specOK (battery .take .hangs) (.dropping 2) .take = some false := by
  decide +kernel

theorem droppingAsync_take_drops : specOK (battery .take .drops) (.dropping 2) .take = some false := by
  decide +kernel

theorem droppingAsync_take_doubles : specOK (battery .take .doubles) (.dropping 2) .take = some false := by
  decide +kernel

theorem droppingAsync_tryTake_mirror : specOK henv (.dropping 2) .tryTake = some true := by
  decide +kernel

theorem droppingAsync_tryTake_raises : specOK (battery .tryTake .raises) (.dropping 2) .tryTake = some false := by
  decide +kernel

theorem droppingAsync_tryTake_hangs : specOK (battery .tryTake .hangs) (.dropping 2) .tryTake = some false := by
  decide +kernel

theorem droppingAsync_tryTake_drops : specOK (battery .tryTake .drops) (.dropping 2) .tryTake = some false := by
  decide +kernel

theorem droppingAsync_tryTake_doubles : specOK (battery .tryTake .doubles) (.dropping 2) .tryTake = some false := by
  decide +kernel

theorem droppingAsync_size_mirror : specOK henv (.dropping 2) .size = some true := by
  decide +kernel

theorem droppingAsync_size_raises : specOK (battery .size .raises) (.dropping 2) .size = some false := by
  decide +kernel

theorem droppingAsync_size_hangs : specOK (battery .size .hangs) (.dropping 2) .size = some false := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueBattery

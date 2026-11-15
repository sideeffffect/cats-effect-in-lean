import CatsEffectInLean.Proofs.Phase7.QueueBatteryDefs

/-!
# Decision 63 battery for `Queue`: `Async` family (`BaseBoundedAsyncQueue`, `BoundedAsyncQueue`)

Each theorem: the broken operation (`battery op var`) breaks `SeqSpec` on its input
(`inputOf op`, kind `bounded(2)`, FIFO schedule, fuel 3000, kernel-checked); the `*_mirror` theorems:
the real mirror meets `SeqSpec` on the same inputs. `size` `drops`/`doubles` are meaningless (see
`QueueBatteryDefs`).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

theorem async_offer_mirror : specOK henv (.bounded 2) .offer = some true := by
  decide +kernel

theorem async_offer_raises : specOK (battery .offer .raises) (.bounded 2) .offer = some false := by
  decide +kernel

theorem async_offer_hangs : specOK (battery .offer .hangs) (.bounded 2) .offer = some false := by
  decide +kernel

theorem async_offer_drops : specOK (battery .offer .drops) (.bounded 2) .offer = some false := by
  decide +kernel

theorem async_offer_doubles : specOK (battery .offer .doubles) (.bounded 2) .offer = some false := by
  decide +kernel

theorem async_tryOffer_mirror : specOK henv (.bounded 2) .tryOffer = some true := by
  decide +kernel

theorem async_tryOffer_raises : specOK (battery .tryOffer .raises) (.bounded 2) .tryOffer = some false := by
  decide +kernel

theorem async_tryOffer_hangs : specOK (battery .tryOffer .hangs) (.bounded 2) .tryOffer = some false := by
  decide +kernel

theorem async_tryOffer_drops : specOK (battery .tryOffer .drops) (.bounded 2) .tryOffer = some false := by
  decide +kernel

theorem async_tryOffer_doubles : specOK (battery .tryOffer .doubles) (.bounded 2) .tryOffer = some false := by
  decide +kernel

theorem async_take_mirror : specOK henv (.bounded 2) .take = some true := by
  decide +kernel

theorem async_take_raises : specOK (battery .take .raises) (.bounded 2) .take = some false := by
  decide +kernel

theorem async_take_hangs : specOK (battery .take .hangs) (.bounded 2) .take = some false := by
  decide +kernel

theorem async_take_drops : specOK (battery .take .drops) (.bounded 2) .take = some false := by
  decide +kernel

theorem async_take_doubles : specOK (battery .take .doubles) (.bounded 2) .take = some false := by
  decide +kernel

theorem async_tryTake_mirror : specOK henv (.bounded 2) .tryTake = some true := by
  decide +kernel

theorem async_tryTake_raises : specOK (battery .tryTake .raises) (.bounded 2) .tryTake = some false := by
  decide +kernel

theorem async_tryTake_hangs : specOK (battery .tryTake .hangs) (.bounded 2) .tryTake = some false := by
  decide +kernel

theorem async_tryTake_drops : specOK (battery .tryTake .drops) (.bounded 2) .tryTake = some false := by
  decide +kernel

theorem async_tryTake_doubles : specOK (battery .tryTake .doubles) (.bounded 2) .tryTake = some false := by
  decide +kernel

theorem async_size_mirror : specOK henv (.bounded 2) .size = some true := by
  decide +kernel

theorem async_size_raises : specOK (battery .size .raises) (.bounded 2) .size = some false := by
  decide +kernel

theorem async_size_hangs : specOK (battery .size .hangs) (.bounded 2) .size = some false := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueBattery

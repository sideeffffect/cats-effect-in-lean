import CatsEffectInLean.Proofs.Phase7.QueueBatteryDefs

/-!
# Decision 63 battery for `Queue`: `Concurrent` family (`AbstractQueue`, `BoundedQueue`)

Each theorem: the broken operation (`battery op var`) breaks `SeqSpec` on its input
(`inputOf op`, kind `boundedForConcurrent(2)`, FIFO schedule, fuel 3000, kernel-checked); the `*_mirror` theorems:
the real mirror meets `SeqSpec` on the same inputs. `size` `drops`/`doubles` are meaningless (see
`QueueBatteryDefs`).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

theorem conc_offer_mirror : specOK henv (.boundedConc 2) .offer = some true := by
  decide +kernel

theorem conc_offer_raises : specOK (battery .offer .raises) (.boundedConc 2) .offer = some false := by
  decide +kernel

theorem conc_offer_hangs : specOK (battery .offer .hangs) (.boundedConc 2) .offer = some false := by
  decide +kernel

theorem conc_offer_drops : specOK (battery .offer .drops) (.boundedConc 2) .offer = some false := by
  decide +kernel

theorem conc_offer_doubles : specOK (battery .offer .doubles) (.boundedConc 2) .offer = some false := by
  decide +kernel

theorem conc_tryOffer_mirror : specOK henv (.boundedConc 2) .tryOffer = some true := by
  decide +kernel

theorem conc_tryOffer_raises : specOK (battery .tryOffer .raises) (.boundedConc 2) .tryOffer = some false := by
  decide +kernel

theorem conc_tryOffer_hangs : specOK (battery .tryOffer .hangs) (.boundedConc 2) .tryOffer = some false := by
  decide +kernel

theorem conc_tryOffer_drops : specOK (battery .tryOffer .drops) (.boundedConc 2) .tryOffer = some false := by
  decide +kernel

theorem conc_tryOffer_doubles : specOK (battery .tryOffer .doubles) (.boundedConc 2) .tryOffer = some false := by
  decide +kernel

theorem conc_take_mirror : specOK henv (.boundedConc 2) .take = some true := by
  decide +kernel

theorem conc_take_raises : specOK (battery .take .raises) (.boundedConc 2) .take = some false := by
  decide +kernel

theorem conc_take_hangs : specOK (battery .take .hangs) (.boundedConc 2) .take = some false := by
  decide +kernel

theorem conc_take_drops : specOK (battery .take .drops) (.boundedConc 2) .take = some false := by
  decide +kernel

theorem conc_take_doubles : specOK (battery .take .doubles) (.boundedConc 2) .take = some false := by
  decide +kernel

theorem conc_tryTake_mirror : specOK henv (.boundedConc 2) .tryTake = some true := by
  decide +kernel

theorem conc_tryTake_raises : specOK (battery .tryTake .raises) (.boundedConc 2) .tryTake = some false := by
  decide +kernel

theorem conc_tryTake_hangs : specOK (battery .tryTake .hangs) (.boundedConc 2) .tryTake = some false := by
  decide +kernel

theorem conc_tryTake_drops : specOK (battery .tryTake .drops) (.boundedConc 2) .tryTake = some false := by
  decide +kernel

theorem conc_tryTake_doubles : specOK (battery .tryTake .doubles) (.boundedConc 2) .tryTake = some false := by
  decide +kernel

theorem conc_size_mirror : specOK henv (.boundedConc 2) .size = some true := by
  decide +kernel

theorem conc_size_raises : specOK (battery .size .raises) (.boundedConc 2) .size = some false := by
  decide +kernel

theorem conc_size_hangs : specOK (battery .size .hangs) (.boundedConc 2) .size = some false := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueBattery

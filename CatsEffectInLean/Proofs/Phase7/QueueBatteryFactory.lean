import CatsEffectInLean.Proofs.Phase7.QueueBatteryDefs

/-!
# Decision 63 battery for `Queue`: the factories (review batch 13 L2)

A wrong factory (`wrongFactory`: `raises`, `hangs`) replaces the `IO` that the factory returns, in
the harness root (`rootWith`; `rootWith (newIO k) = rootIO k`, `rootWith_newIO`). Input: one fiber
`[size]`. Each wrong factory breaks `SeqSpec` of the family of its kind (FIFO schedule, fuel
3000, kernel-checked); the real factory meets it (`*_mirror`). `drops`/`doubles` are meaningless
for a factory (no effect on an existing queue). Kinds: `bounded(2)` (`BoundedAsyncQueue`), `bounded(1)` (`BoundedQueue`), `unbounded` (`UnboundedAsyncQueue`), `dropping(2)` (`DroppingAsyncQueue`), `dropping(1)` (`DroppingQueue`), `circularBuffer(2)` (`CircularBufferQueue`), `synchronous` (`Synchronous`).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

theorem factory_bounded2_mirror : factoryOK (newIO (.bounded 2)) (.bounded 2) = some true := by
  decide +kernel
theorem factory_bounded2_raises : factoryOK (wrongFactory .raises) (.bounded 2) = some false := by
  decide +kernel
theorem factory_bounded2_hangs : factoryOK (wrongFactory .hangs) (.bounded 2) = some false := by
  decide +kernel

theorem factory_bounded1_mirror : factoryOK (newIO (.bounded 1)) (.bounded 1) = some true := by
  decide +kernel
theorem factory_bounded1_raises : factoryOK (wrongFactory .raises) (.bounded 1) = some false := by
  decide +kernel
theorem factory_bounded1_hangs : factoryOK (wrongFactory .hangs) (.bounded 1) = some false := by
  decide +kernel

theorem factory_unbounded_mirror : factoryOK (newIO (.unbounded)) (.unbounded) = some true := by
  decide +kernel
theorem factory_unbounded_raises : factoryOK (wrongFactory .raises) (.unbounded) = some false := by
  decide +kernel
theorem factory_unbounded_hangs : factoryOK (wrongFactory .hangs) (.unbounded) = some false := by
  decide +kernel

theorem factory_dropping2_mirror : factoryOK (newIO (.dropping 2)) (.dropping 2) = some true := by
  decide +kernel
theorem factory_dropping2_raises : factoryOK (wrongFactory .raises) (.dropping 2) = some false := by
  decide +kernel
theorem factory_dropping2_hangs : factoryOK (wrongFactory .hangs) (.dropping 2) = some false := by
  decide +kernel

theorem factory_dropping1_mirror : factoryOK (newIO (.dropping 1)) (.dropping 1) = some true := by
  decide +kernel
theorem factory_dropping1_raises : factoryOK (wrongFactory .raises) (.dropping 1) = some false := by
  decide +kernel
theorem factory_dropping1_hangs : factoryOK (wrongFactory .hangs) (.dropping 1) = some false := by
  decide +kernel

theorem factory_circular2_mirror : factoryOK (newIO (.circular 2)) (.circular 2) = some true := by
  decide +kernel
theorem factory_circular2_raises : factoryOK (wrongFactory .raises) (.circular 2) = some false := by
  decide +kernel
theorem factory_circular2_hangs : factoryOK (wrongFactory .hangs) (.circular 2) = some false := by
  decide +kernel

theorem factory_synchronous_mirror : factoryOK (newIO (.synchronous)) (.synchronous) = some true := by
  decide +kernel
theorem factory_synchronous_raises : factoryOK (wrongFactory .raises) (.synchronous) = some false := by
  decide +kernel
theorem factory_synchronous_hangs : factoryOK (wrongFactory .hangs) (.synchronous) = some false := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueBattery

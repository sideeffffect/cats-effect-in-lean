# Track Q: review batch 13 (G1, L1, L2) — full Queue battery table

> Source: own Lean work (`Props/Phase7/Queue.lean` statement 8 `syncHandoff`, `Proofs/Phase7/QueueBattery{Defs,Conc,Async,Sync,ConcOther,AsyncOther,Factory}.lean`, `Proofs/Phase7/QueueWitness.lean`); `review/2026-11-15-review-batch-13.md` section A.5; `Queue.scala:274-290`, `:347-353` at v3.7.1
> Collected: 2026-11-15
> Published: 2026-11-15 (own research note)

## G1: `Synchronous#tryOffer` always `false`

Statement 8 is now `syncHandoff` (entry `std.Queue.Synchronous.tryHandoff`, replaces `tryTakeHandoff`): FIFO replay schedule, for every element and fuel: (a) offerer waiting, then `tryTake` = `Some(x)`, both joins `Succeeded`; (b) taker waiting, then `tryOffer(x)` = `true`, the taker took `x`, both joins `Succeeded`. CE code: `tryOffer` with a taker completes the taker's latch with `(a, latch)` and returns the taker's `true` (`Q:274-290`, `:336-338`). Witness `syncHandoff_satisfiable` (both parts). Breaks (kernel-checked): `wSyncTryOfferFalse` (`sync_tryOffer_false_breaks`), `tryOffer` drops (`sync_tryOffer_drops_handoff`), `tryTake` drops (`sync_tryTake_drops`).

## Battery table (decision 63), every cell kernel-checked

Operation rows, statement `SeqSpec` (one fiber, `inputOf op`), per class:

| class (kind) | module | offer | tryOffer | take | tryTake | size |
|---|---|---|---|---|---|---|
| `BoundedQueue` (`boundedForConcurrent(2)`) | `QueueBatteryConc` | R H D 2 | R H D 2 | R H D 2 | R H D 2 | R H |
| `DroppingQueue` (`droppingForConcurrent(2)`) | `QueueBatteryConcOther` | R H D 2 | R H D 2 | R H D 2 | R H D 2 | R H |
| `CircularBufferQueue` (`circularBuffer(2)`) | `QueueBatteryConcOther` | R H D 2 | R H D 2 | R H D 2 | R H D 2 | R H |
| `BoundedAsyncQueue` (`bounded(2)`) | `QueueBatteryAsync` | R H D 2 | R H D 2 | R H D 2 | R H D 2 | R H |
| `UnboundedAsyncQueue` (`unbounded`) | `QueueBatteryAsyncOther` | R H D 2 | R H D 2 | R H D 2 | R H D 2 | R H |
| `DroppingAsyncQueue` (`dropping(2)`) | `QueueBatteryAsyncOther` | R H D 2 | R H D 2 | R H D 2 | R H D 2 | R H |
| `Synchronous` | `QueueBatterySync` | R H D: TakerLiveness; 2: NoDup | R H D: SeqSpec; 2: NoDup | R H 2: TakerLiveness; D: NoDup | R H: SeqSpec; D: syncHandoff; 2: NoLoss | R H: SeqSpec |

R = raises, H = hangs, D = drops, 2 = doubles. `size` drops/doubles: meaningless (read only; two reads give one value).

Factory rows (`QueueBatteryFactory`, statement `SeqSpec`, input `[size]`): `bounded(2)`, `bounded(1)`, `unbounded`, `dropping(2)`, `dropping(1)`, `circularBuffer(2)`, `synchronous` × raises, hangs. Factory drops/doubles: meaningless (no effect on an existing queue).

Build cost: ConcOther 137 s / 1.4 GB, AsyncOther 121 s / 1.4 GB, Factory 12 s / 0.8 GB.

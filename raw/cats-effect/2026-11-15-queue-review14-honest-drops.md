# Track Q: review batch 14 C1 — honest drops of tryOffer and tryTake

> Source: own Lean work (`Proofs/Phase7/QueueBatteryDefs.lean` variant `dropsHonest`, `Proofs/Phase7/QueueBatteryHonest.lean`); `review/2026-11-15-review-batch-14.md`
> Collected: 2026-11-15
> Published: 2026-11-15 (own research note)

- New battery variant `dropsHonest`: `tryOffer` answers `false`, `tryTake` answers `None`, both with no effect (the answer a full or empty queue would give).
- Kernel-checked breaks of `SeqSpec` (FIFO schedule, fuel 3000) on the six non-`Synchronous` classes: `BoundedQueue` (`boundedForConcurrent(2)`), `DroppingQueue` (`droppingForConcurrent(2)`), `CircularBufferQueue` (`circularBuffer(2)`), `BoundedAsyncQueue` (`bounded(2)`), `UnboundedAsyncQueue` (`unbounded`), `DroppingAsyncQueue` (`dropping(2)`), each for `tryOffer` (input `[tryOffer 1, size]`) and `tryTake` (input `[offer 1, offer 2, tryTake, size]`): 12 theorems, 30 s, 1.3 GB.
- The `tryTake` honest drop equals the earlier `drops` variant of `tryTake` (`None`, no effect), so those rows existed already; the new theorems restate them under `dropsHonest`.
- `Synchronous`: `sync_tryOffer_false_breaks` and `sync_tryTake_drops` (statement `syncHandoff`).
- Process rule (coordinator, 2026-11-15): stop only processes that this agent started, by PID; never a machine-wide `pkill`.

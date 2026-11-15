# Track Q: fixes after review batch 12 (H3) and the decision 63 battery

> Source: own Lean work on the track Q branch at `de9fcef` and later (`Props/Phase7/Queue.lean`, `Proofs/Phase7/QueueBattery*.lean`, `Proofs/Phase7/QueueWrongFunction.lean`, `Proofs/Phase7/QueueWitness.lean`); `review/2026-11-15-review-batch-12.md`; `raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md`
> Collected: 2026-11-15
> Published: 2026-11-15 (own research note)

## H3 / W3 fix

- The harness records each join outcome: event `(7, i, outcome)` after `join i` (closure `QH.joinRec`).
- `TakerLiveness` (both families): a run that ends `Succeeded` must also have `JoinsSucceeded`: every joined consumer that the plan does not cancel has a `Succeeded` join event. `QuietBlock` is unchanged.
- `wSyncTakeRaises` (`QC.sTakeK` throws): `[[take], [offer 1]]`, join `[0]`, `synchronous`: the consumer's join is `Errored`, the claim fails (kernel-checked `wSyncTakeRaises_breaks`); the mirror meets it (`syncTake_mirror_ok`).

## New statement: `SeqSpec` (decision 63 item 3, both families)

One fiber runs any script; the root joins it, cancels it, drains. The trace and the summary equal `specRun (ruleOf k)`: a sequential FIFO queue with the factory's capacity rule (`block cap`, `drop cap`, `circular cap`, `unbounded`, `sync`). Entries `std.Queue.Concurrent.seqSpec`, `std.Queue.Async.seqSpec`. Witness `seqSpec_satisfiable` (the twin script on `boundedForConcurrent(2)` and `bounded(2)`). `qsmoke` checks it for random scripts on every kind.

## Battery (decision 63)

The broken operation replaces the `IO` that the method returns (`QueueBatteryDefs.battery op var`): `raises` = `raiseError(E77)`; `hangs` = an `IOCont` that never resumes; `drops` = `offer` returns `()`, `tryOffer` returns `true`, `take` returns `0`, `tryTake` returns `None`, with no effect; `doubles` = `offer *> offer`, `tryOffer *> tryOffer`, `take <* take`, `tryTake <* tryTake`. Every break is a kernel-checked FIFO-schedule run; for each input the mirror meets the same claim.

`Concurrent` (representative `boundedForConcurrent(2)` = `BoundedQueue`, module `QueueBatteryConc`) and `Async` (representative `bounded(2)` = `BoundedAsyncQueue`, module `QueueBatteryAsync`):

| op | raises | hangs | drops | doubles |
|---|---|---|---|---|
| `offer` | SeqSpec | SeqSpec | SeqSpec | SeqSpec |
| `tryOffer` | SeqSpec | SeqSpec | SeqSpec | SeqSpec |
| `take` | SeqSpec | SeqSpec | SeqSpec | SeqSpec |
| `tryTake` | SeqSpec | SeqSpec | SeqSpec | SeqSpec |
| `size` | SeqSpec | SeqSpec | meaningless (read only) | meaningless (two reads = one read) |

Inputs (`inputOf`): `offer`, `size`: `[offer 1, size]`; `tryOffer`: `[tryOffer 1, size]`; `take`: `[offer 1, offer 2, take, size]`; `tryTake`: `[offer 1, offer 2, tryTake, size]`.

`Synchronous` (part of `Concurrent`; needs a partner, module `QueueBatterySync`):

| op | raises | hangs | drops | doubles |
|---|---|---|---|---|
| `offer` (`[[take],[take],[offer 1]]`, join `[0,1]`) | TakerLiveness | TakerLiveness | TakerLiveness | NoDup |
| `take` (`[[take],[offer 1]]`, join `[0]`) | TakerLiveness | TakerLiveness | NoDup | TakerLiveness |
| `tryOffer` | SeqSpec (`[tryOffer 1]`) | SeqSpec | SeqSpec | NoDup (`[[take],[take],[tryOffer 1]]`, join `[0,1]`) |
| `tryTake` | SeqSpec (`[tryTake]`) | SeqSpec | **gap** | NoLoss (`[[offer 1],[offer 2],[tryTake]]`, plan `[(3,2)]`, cancelAll) |
| `size` | SeqSpec (`[size]`) | SeqSpec | meaningless | meaningless |

Gap: `Synchronous#tryTake` `drops` (it answers `None` with no effect while an offerer waits) breaks no registered statement: a `tryTake` alone correctly answers `None`, and no statement claims that `tryTake` finds a waiting offerer. It needs a linearizability statement (open). The bounded and unbounded `tryTake` rows are covered by `SeqSpec`.

## Inventory

`std.Queue.UnsafeBounded.FailureSignal`, `std.UnsafeUnbounded.FailureSignal`: reason `deferred: phase 9 (weak memory model)`.

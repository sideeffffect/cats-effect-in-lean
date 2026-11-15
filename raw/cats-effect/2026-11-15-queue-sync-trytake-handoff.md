# Track Q: `Synchronous#tryTake` with a waiting offerer (decision 63 gap closed)

> Source: `std/shared/src/main/scala/cats/effect/std/Queue.scala:139-150`, `:246-272`, `:347-357`, `QueueSource.scala:31-38` at v3.7.1; own Lean runs (`Props/Phase7/Queue.lean` statement 8, `Proofs/Phase7/QueueBatterySync.lean`, `Proofs/Phase7/QueueWitness.lean`)
> Collected: 2026-11-15
> Published: 2026-11-15 (own research note)

## Facts

- Scaladoc `tryTake`: "Attempts to dequeue an element from the front of the queue, if one is available without fiber blocking." Scaladoc `synchronous`: "a single element can pass only in the case when there are at least one taking fiber and at least one offering fiber ... at which point both fibers are freed."
- Code: `Synchronous#tryTake` = `F uncancelable { _ => stateR.flatModify { case SyncState(offerers, takers) if offerers.nonEmpty => ... offerer.complete(true).as(value.some); case st => st -> none[A].pure[F] } }`. With a registered offerer, CE hands the element over and frees the offerer (its `checkCommit` reads `true`).
- So CE does what the docs say; no refutation candidate (case 2 of the coordinator's list).

## Why a FIFO-schedule statement

A claim over every run cannot tell "tryTake ignored a registered offerer" from "tryTake ran before the offerer registered": both give the observation `tryTook None`, offerer still waiting. So the statement fixes the order with the FIFO replay schedule: the root starts the offerer (fiber 0) and the `tryTake` fiber (fiber 1) and joins fiber 0; fiber 0 runs until it suspends in `offer` before fiber 1 starts.

## Statement and checks

- `syncTryTakeHandoff`: for every element `x` and fuel, a stopped FIFO run of `[[offer x], [tryTake]]`, join `[0, 1]`, on `synchronous` has `tryTook Some(x)`, both joins `Succeeded`, root `Succeeded`. Entry `std.Queue.Synchronous.tryTakeHandoff` (open).
- Witness: `syncTryTakeHandoff_satisfiable` (element 1, fuel 3000; events: offerStart 1, tryTook Some 1, offered 1, joined 0 and 1 Succeeded).
- Wrong function: `battery .tryTake .drops` gives `tryTook None` and the run stops `blocked` (`sync_tryTake_drops`, kernel-checked); the mirror meets the claim (`sync_tryTake_handoff_mirror`).

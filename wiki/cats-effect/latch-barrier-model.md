# CountDownLatch and CyclicBarrier model

> Sources: Cats Effect v3.7.1 (`std/.../CountDownLatch.scala`, `std/.../CyclicBarrier.scala`, `kernel/.../Ref.scala:123-141`, `kernel/jvm-native/.../SyncRef.scala`, `core/.../IODeferred.scala:55-79`, `core/.../IO.scala:1822-1824`, `:2008-2163`); read-only `gh` history and issue search; own Lean, scala-cli and difftest runs, 2026-11-15
> Raw: [Track L notes](../../raw/cats-effect/2026-11-15-track-l-latch-barrier-notes.md)

## Overview

Phase 7, batch 7.1, track L. Mirrors of `std.CountDownLatch` and `std.CyclicBarrier` with `F = IO`, difftest ops (format v2), seven registered properties, all `open`, each with a kernel-checked satisfiability witness, a wrong-function test and a smoke test. No bug found. Codec namespaces 70–75.

## Mirrors

- `Std/CountDownLatch.lean` (namespace 70, effect codes 71) and `Std/CyclicBarrier.lean` (72, 73). Every lambda of the Scala source is one closure (`CLam`, `BLam`), in the same order: `apply` (the `n < 1` throw is `apply? = none`), `State.initial`, `release` = `flatModify` = `Uncancelable(_ => flatten(modify(f)))`, `await`; for the barrier `F.deferred.map(State(capacity, 0, _)).flatMap(F.ref).map(...)`, `await` = `F.deferred.flatMap(gate => flatModifyFull(...))`, the `cleanup` update.
- The latch and the barrier object are closure references `Val.fn` (odd ids, decision 58). A method call is a call of that closure (latch: `nat 0` = `release`, `nat 1` = `await`; barrier: `nat 0` = `await`). A program that holds the object cannot read or write its state cell.
- The `F[Unit]` that `modify` returns is an effect code; `flattenK` builds the `IO`. Every handle in a code is a `Val` handle (capability).
- `unblock.get` is built inside the `modify` function, so the mirror keeps the cell snapshot of that step.
- Variants `v ≠ 0` are **not Cats Effect code**: wrong functions for the tests (latch: open early, never wake, raise after `Done`; barrier: trip at `cap - 1`, no re-increment, no epoch check, never wake).

## The two cancel races of CyclicBarrier

1. A released waiter (its `get` callback fired) is canceled before it runs: when it runs, the run loop leaves `poll` and pops the `cleanup` finalizer before it checks cancel again. The cancel is seen after `await` logically returned; `cleanup` does not run; the fiber ends `Canceled` but counted for the trip.
2. A waiter is canceled while it is suspended in `unblock.get`: its finalizers run in a later task, and another fiber can trip the barrier first. Then `cleanup` sees the new epoch. **Only this race needs the epoch check**; without it the next generation needs `capacity + 1` fibers and can hang.

## Difftest

Ops `cdlNew`, `cdlRelease`, `cdlAwait`, `cbNew`, `cbAwait` ([format](../methodology/difftest-program-format.md)). Generator templates `tpl_latch`, `tpl_barrier_race`, appended by `gen_case` with their own RNG (`p_latch`); other cases do not change. Fixed cases `latch.jsonl`: 54 agree.
- Mutation check (2,000 cases each): all 7 wrong variants killed (24–206 mismatches). The no-epoch-check mutant first survived (race 1 only); `tpl_barrier_race` (race 2) kills it.
- Depth run: see "Results" below.

## Properties (`Props/Phase7/`)

Harness: awaiters `user.attempt *> uncancelable(poll => mark 1 *> poll(await).onCancel(mark 3) *> mark 2)`; latch releasers `user.attempt *> uncancelable(_ => started += 1 *> release *> completed += 1)`; the root cancels some fibers (barrier: group A, cancels, group B), joins all. Harness cells are private (`WellFormed`, `H0 = []`); the statement library lists only variant-0 mirror closures. All user code, all counts, all `PChoice` schedules and fuel.

| Entry | Claim |
|---|---|
| `std.CountDownLatch.awaitNotEarly` | an awaiter returns only if `started ≥ n` (every state) |
| `std.CountDownLatch.noLostWakeup` | blocked and `started ≥ n` ⇒ no awaiter in `await` |
| `std.CountDownLatch.releaseTotal` | blocked or done ⇒ `completed = started` (release after 0 is a no-op) |
| `std.CyclicBarrier.noEarlyTrip` | no cancels: `passed ≤ cap * (entered / cap)` (every state) |
| `std.CyclicBarrier.exactGenerations` | no cancels, blocked ⇒ `cap ∣ passed` and `waiting < cap` |
| `std.CyclicBarrier.cancelNoHang` | cancels, blocked ⇒ `waiting < cap` |
| `std.CyclicBarrier.cancelRemoved` | `as.length < cap`: `passed ≤ cap * ((entered - canceledIn) / cap)` (every state) |

`cancelRemoved` needs `as.length < cap` (a test-program shape, not a Cats Effect precondition): with a full group A, race 1 gives a canceled waiter that counted, so the bound is false for every correct barrier. `cancelNoHang` covers both races.

## Results

- Witnesses and wrong-function facts: `Proofs/Phase7/LatchWitness.lean` (kernel, 1 min 52 s, 1.1 GB): one `*_sat` and one `*_wrong` per statement; `cancelNoHang_v0_race` (v3.7.1 passes the race schedule); `cdlAwaitNotEarly_v1_false`, `cbCancelNoHang_v3_false`.
- Smoke: `test/Phase7/LatchSmoke.lean` (random inputs and schedules; safety statements in every state; hypotheses evaluated).
- No proof yet: a proof needs a state invariant over `Step`/`SchedP` (as the Phase 6 open entries).

## See Also

- [memoize model](memoize-model.md)
- [Queue and timeout model](queue-model.md)
- [Scheduler model](scheduler-model.md)
- [Differential testing](../methodology/differential-testing.md)
- [Agent workflow and review protocol](../methodology/agent-workflow.md)

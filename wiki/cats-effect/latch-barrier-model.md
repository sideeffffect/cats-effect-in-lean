# CountDownLatch and CyclicBarrier model

> Sources: Cats Effect v3.7.1 (`std/.../CountDownLatch.scala`, `std/.../CyclicBarrier.scala`, `kernel/.../Ref.scala:123-141`, `kernel/jvm-native/.../SyncRef.scala`, `core/.../IODeferred.scala:55-79`, `core/.../IO.scala:1822-1824`, `:2008-2163`); read-only `gh` history and issue search; own Lean, scala-cli and difftest runs, 2026-11-15
> Raw: [Review batch 13 notes](../../raw/project-decisions/2026-11-15-review-batch-13-notes.md); [Track L notes](../../raw/cats-effect/2026-11-15-track-l-latch-barrier-notes.md); [Decision 63 battery](../../raw/cats-effect/2026-11-15-track-l-decision63-battery.md); [Review 13 fixes](../../raw/cats-effect/2026-11-15-track-l-review13-fix.md)

## Overview

Phase 7, batch 7.1, track L. Mirrors of `std.CountDownLatch` and `std.CyclicBarrier` with `F = IO`, difftest ops (format v2), eleven registered properties (seven reviewed FAITHFUL in batch 11b; two decision-63 companions, HOLLOW in batch 13 (H4) and restated; two `noDeadlock` claims added after batch 13), all `open`, each with a kernel-checked satisfiability witness, a wrong-function test and a smoke test. No bug found. Codec namespaces 70–75.

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
- Depth run: `opcount.py --seeds 71 72 73 --n 45000 --ops cdlNew cdlRelease cdlAwait cbNew cbAwait --boost tpl_cdl=12 tpl_cb=12`: 135,000 cases, **all agree**, 0 unsupported. Agreeing cases per op: `cdlNew`/`cdlAwait` 58,783, `cdlRelease` 56,600, `cbNew`/`cbAwait` 59,251 (each about 19,000 per seed). Model bugs found: none.

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

## Decision 63 battery

`Proofs/Phase7/LatchBattery.lean` (kernel, 42 s): each public operation × {raises, hangs, drops, doubles} breaks one registered statement.

| Operation | raises | hangs | drops | doubles |
|---|---|---|---|---|
| `CountDownLatch.release` | `releaseTotal` | `releaseTotal` | `noLostWakeup` | `awaitNotEarly` |
| `CountDownLatch.await` | `awaitCompletes` | `noLostWakeup` | `awaitNotEarly` | meaningless (no effect on the state) |
| `CyclicBarrier.await` | `awaitCompletes` | `exactGenerations` | `noEarlyTrip` | `noEarlyTrip` |
| `CountDownLatch.apply` | `awaitCompletes` | `noDeadlock` | not applicable (allocation only) | not applicable |
| `CyclicBarrier.apply` | `awaitCompletes` | `noDeadlock` | not applicable | not applicable |

- Review 13 (H4): the first `awaitCompletes` ("a done root leaves no await open") held for an `apply` that always raises (root done `Errored`, no fiber starts). Restated: for `n ≥ 1` / `cap ≥ 1` a done root is `Succeeded(())`. New `noDeadlock` claims (pure user programs, enough releasers / `cap * g` awaiters: never blocked) reject hangs. Lesson: "if done then ..." claims must say *how* the root is done.
- Review 13 (L4): `v0_*` theorems run the v3.7.1 mirror on every battery input.

- Gap found: an `await` that raises broke none of the first seven statements (the root still joins the errored awaiter and completes). Fix: the companion claims `std.CountDownLatch.awaitCompletes`, `std.CyclicBarrier.awaitCompletes` (a done root leaves no awaiter at status 1), with witnesses.
- Smoke of the companions: v3.7.1 0 violations (936 and 874 done runs); `await` raises: 838 and 1,384 violating runs.
- No public `count`; `mapK` only wraps the methods.
- Harness privacy: `mark`/`incr` write cells by number; kernel-checked that no library id decodes to them and that a program naming them is not well-formed.

## Results

- Witnesses and wrong-function facts: `Proofs/Phase7/LatchWitness.lean` (kernel, 1 min 52 s, 1.1 GB): one `*_sat` and one `*_wrong` per statement; `cancelNoHang_v0_race` (v3.7.1 passes the race schedule); `cdlAwaitNotEarly_v1_false`, `cbCancelNoHang_v3_false`.
- Smoke: `test/Phase7/LatchSmoke.lean` (9 min; random inputs and schedules; safety statements in every state; hypotheses evaluated: `progOK` of every user program, `as.length < cap`). v3.7.1: 0 violations of all 7 statements; 0 hypothesis failures. Latch (1,500 runs): 564 blocked, 311 with a returned awaiter; wrong variants 1/2/3 violate their statement in 160/238/225 runs. Barrier (1,500 runs each, no cancels / cancels): 625 / 749 blocked, 1,053 with a trip, 250 with a canceled waiter; variant 1 → 612, variant 4 → 584, variant 2 (statement 4) → 3. The cancel races need fixed shapes (800 schedules each, a preemption of the root at a FIFO prefix of 0–39 steps): race shape, variant 3 → 20 hangs, v3.7.1 → 0; removal shape, variant 2 → 20, v3.7.1 → 0. Lesson: random schedules almost never put the cancel in the narrow window where a waiter is suspended (FIFO prefix 9 or 10).
- The CDL witness `nv` (a program that waits forever) uses `CountDownLatch` closures; `cbLib` does not list them, so the barrier smoke has no `nv` (first run: 80 hypothesis failures, fixed).
- Review batch 11b (2026-11-15, [review](../../review/2026-11-15-review-batch-11b.md)): all 7 entries FAITHFUL as statements; mirrors faithful. "Without cancels" in `noEarlyTrip`/`exactGenerations` is needed (race 1 makes both false for every correct barrier); `cancelNoHang` and `cancelRemoved` cover the cancel case. `as.length < cap` shapes the test, keeps the interesting case. No forgery: the harness closures `mark`/`incr` write cells by data number and are safe only while no `HLam` is in `cdlLib`/`cbLib`. Low: no recorded difftest run after the merge fix `1e84acb`.
- No proof yet: a proof needs a state invariant over `Step`/`SchedP` (as the Phase 6 open entries).

## Review (batch 13, 2026-11-15)

[Review](../../review/2026-11-15-review-batch-13.md). The mirror is unchanged for `v = 0`; `X ↔ XV 0` holds by `Iff.rfl`; each battery break is a `¬ XV v` theorem. **HOLLOW (H4):** `cdlAwaitCompletes` and `cbAwaitCompletes` say "if the root is done", and a root `Errored` is done. An `apply` that always raises stops every run before any fiber starts and meets every latch statement; the battery has no `apply` row. Fix: claim a `Succeeded(())` root for `n ≥ 1` (`cap ≥ 1`), add the `apply` row. Low: 6 of 11 rows have no kernel mirror run on the same input. The other 7 entries stay FAITHFUL.

## See Also

- [memoize model](memoize-model.md)
- [Queue and timeout model](queue-model.md)
- [Scheduler model](scheduler-model.md)
- [Differential testing](../methodology/differential-testing.md)
- [Agent workflow and review protocol](../methodology/agent-workflow.md)

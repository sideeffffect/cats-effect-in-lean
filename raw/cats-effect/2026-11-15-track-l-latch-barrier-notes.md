# Track L (Phase 7): CountDownLatch and CyclicBarrier — own notes (2026-11-15)

Source: own work in the track L worktree. Cats Effect v3.7.1 (`~/Projects/cats-effect`, detached at
`v3.7.1`): `std/shared/src/main/scala/cats/effect/std/CountDownLatch.scala` (96 lines),
`std/shared/src/main/scala/cats/effect/std/CyclicBarrier.scala` (92 lines), `kernel/.../Ref.scala:123-141`,
`kernel/jvm-native/.../SyncRef.scala`, `core/.../IODeferred.scala:55-79`, `core/.../IO.scala:1822-1824`,
`:2008-2163` (`IOAsync`).

## Source facts

- `CountDownLatch.apply(n)` and `CyclicBarrier.apply(capacity)` throw `IllegalArgumentException`
  for `n < 1` while Scala builds the term (outside `F`). The mirrors return `none` (`apply?`);
  the difftest decoders accept only `n >= 1`.
- `CountDownLatch.release` = `state.flatModify` (uncancelable, `Ref.scala:123-124`). `await` =
  `state.get.flatMap { Awaiting(_, signal) => signal.get; Done() => F.unit }`: no cleanup on cancel
  (nothing to clean: `IODeferred.get` removes its own callback).
- `CyclicBarrier.await` = `F.deferred.flatMap(gate => state.flatModifyFull { ... })`
  (`Ref.scala:140-141`). The trip writes `State(capacity, epoch + 1, gate)` and returns
  `unblock.complete(()).void` (inside the mask). Otherwise `poll(unblock.get).onCancel(cleanup)`;
  `cleanup` re-increments `awaiting` only if the epoch did not change (`CyclicBarrier.scala:77-82`).
- `unblock.get` (`cell.get()`) is evaluated inside the `modify` function, so it reads the cell at
  the `modify` step (the mirror keeps that snapshot).
- History (read-only `gh api` of the file commits): CyclicBarrier came in PR #1407 (2020-11), state
  machine "mirror latch" and a cancelation race test (2020-11-13/14), `flatModifyFull` since
  2023-02-22 (PR #3455). CountDownLatch: PR of 2020-11-09/10 ("Make countdown latch release
  uncancelable"). Both files are unchanged on `series/3.x` (`de84c01`, 2026-09-28) since 2025-01
  (format and year only).

## Finding: when does the epoch check matter?

Two different cancel races:

1. The waiter was released (its `get` callback fired) and is canceled before it runs. When it runs,
   `succeeded` pops the continuations of `get`, of `UnmaskRunLoop` (the fiber is masked again) and of
   `OnCancel` (the `cleanup` finalizer is removed) before the next cancel check. The cancel is seen
   at the end of `flatModifyFull`'s `uncancelable`, after `await` logically returned. `cleanup` never
   runs. The fiber ends `Canceled`, but it counted for the trip.
2. The waiter is canceled while it is suspended in `unblock.get`. Its finalizers run in a later task
   of the waiter. Another fiber can trip the barrier before that task runs (the canceled waiter still
   counts). Then `cleanup` sees the new epoch and does nothing. Only this race needs the epoch check:
   without it, the next generation needs `capacity + 1` fibers and can hang.

The first difftest generator shape (parent trips, then cancels a released waiter) only made race 1;
the mutation "no epoch check" survived (1 of 2,000 cases). The template `tpl_barrier_race` (start
`cap - 1` waiters, cede, start a tripper fiber, cancel a waiter at once, then `cap` late awaiters)
makes race 2: the mutant is killed in 34 of 2,000 cases.

## Difftest (format v2 ops `cdlNew`, `cdlRelease`, `cdlAwait`, `cbNew`, `cbAwait`)

- Scala: `CountDownLatch[IO](n).map(l => VLatch(h.newLatch(l)))`, `latchOf(l).release.as(VUnit)`,
  `latchOf(l).await.as(VUnit)`, `CyclicBarrier[IO](n).map(b => VBarrier(...))`,
  `barrierOf(b).await.as(VUnit)`. Latch and barrier values are never printed by generated cases.
- Generator: `tpl_latch` / `tpl_barrier_race` appended by `gen_case` with its own RNG
  (`difftest-latch:{seed}:{i}`, `p_latch = 0.08`), so other cases do not change (checked: of 6,000
  cases, 456 changed, each only by an appended part).
- First run (seed 71, 2,000 cases, boost 12): all agree. Fixed cases `latch.jsonl`: 54 cases, all agree.
- Mutation check (seed 72, 2,000 cases each; one wrong variant in the translation): cdl v1 (early)
  98 mismatches, cdl v2 (never wake) 115, cdl v3 (raise after Done) 118, cb v1 (trip early) 206,
  cb v2 (no re-increment) 24, cb v3 (no epoch check) 34, cb v4 (never wake) 138. All killed.

## Properties

Harness programs and statements: `Props/Phase7/CountDownLatch.lean`, `Props/Phase7/CyclicBarrier.lean`.
Witnesses and wrong-function facts (kernel): `Proofs/Phase7/LatchWitness.lean` (1 min 52 s, 1.1 GB).
Smoke: `test/Phase7/LatchSmoke.lean`.

Duplicate searches (read-only): `gh search issues --repo typelevel/cats-effect "CyclicBarrier"`
(#1863, #1719, #1217), `"CountDownLatch"` (#1863, #1057, #3603, #3073, #2720, #1217, #1719),
`"cyclic barrier cancel"` (none), `"barrier epoch"` (none), `gh search prs ... "CyclicBarrier"`
(#1413, #1607), `"barrier"` (#1407, #1413, #1417 and runtime PRs). No open bug about either structure.

# Track L: decision 63 battery for CountDownLatch and CyclicBarrier (2026-11-15)

Source: own work after the coordinator message (review batch 11b: the 7 track L entries are
FAITHFUL; decision 63, `raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md`).

## Public operations

- `CountDownLatch`: `release`, `await`, `mapK`. No public `count` at v3.7.1.
- `CyclicBarrier`: `await`, `mapK`.
- `mapK` only wraps the two methods with a natural transformation; no battery row.

## Battery (kernel-checked, `Proofs/Phase7/LatchBattery.lean`)

| Operation | Variant | v | Breaks | Input |
|---|---|---|---|---|
| CDL.release | raises | 4 | cdlReleaseTotal | n = 1, [p], [p]: blocked, completed 0, started 1 |
| CDL.release | hangs | 5 | cdlReleaseTotal | same |
| CDL.release | drops | 6 | cdlNoLostWakeup | same: blocked, started 1, status 1 |
| CDL.release | doubles | 7 | cdlAwaitNotEarly | n = 2, [p], [p], fuel 48: status 2, started 1 |
| CDL.await | raises | 8 | cdlAwaitCompletes (new) | n = 1: done, status 1 |
| CDL.await | hangs | 9 | cdlNoLostWakeup | n = 1: blocked, started 1, status 1 |
| CDL.await | drops | 10 | cdlAwaitNotEarly | n = 1, [p], []: status 2, started 0 |
| CDL.await | doubles | - | meaningless | await has no effect on the state |
| CB.await | raises | 5 | cbAwaitCompletes (new) | cap = 1, [p]: done, waiting 1 |
| CB.await | hangs | 6 | cbExactGenerations | cap = 1, [p]: blocked, waiting 1 |
| CB.await | drops | 7 | cbNoEarlyTrip | cap = 2, [p]: passed 1, entered 1 |
| CB.await | doubles | 8 | cbNoEarlyTrip | same |

## Gap found

`await` that raises (latch and barrier) broke none of the 7 old statements: the awaiter ends
`Errored` with status 1, the root still joins it and completes, and no statement looked at a done
run. This is the gap of decision 63 (W1, H2, H3). Fix: companion success claims (decision 63
item 3) `cdlAwaitCompletes`, `cbAwaitCompletes`: in a run whose root is done, no awaiter is left at
status 1 (every `await` that began returned or was canceled). Stronger than item 3 asks: it holds
for all runs (with cancels and user errors), not only runs without them.

## Harness privacy guard (track S note)

The harness closures `mark`/`incr` write cells by number. Kernel-checked: no id of `cdlLib`/`cbLib`
decodes to a harness closure (`*_harness_not_public`), and user programs that name `mark`/`incr`
are not `progOK` (`forged_mark`, `forged_incr`). The battery closure `BLam.neverK` is not public
(`neverK_not_public`).

## Smoke (test/Phase7/LatchSmoke.lean, 11 min)

- `cdlAwaitCompletes`: v3.7.1 0 violations in 936 done runs (of 1,500); variant 8 (await raises)
  838 violating runs.
- `cbAwaitCompletes`: v3.7.1 0 violations in 874 done runs (of 1,500, with cancels); variant 5
  1,384 violating runs.
- All earlier smoke results unchanged.

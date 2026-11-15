# Track L: review batch 13 fixes (H4, L4) (2026-11-15)

Source: own work after review batch 13 (`review/2026-11-15-review-batch-13.md`, C.4).

## H4

`cdlAwaitCompletes` / `cbAwaitCompletes` said "if the root is done, no await is left open". An
`apply` that always raises stops every run with the root done `Errored` before any fiber starts,
so it met every latch statement. Fix:

- Restated: for `n >= 1` / `cap >= 1` (the documented precondition of `apply`), a done root is
  `Succeeded(())`, and no await is left at status 1.
- New statements `cdlNoDeadlock` (n >= 1, pure user programs, at least n releasers, any cancels:
  never blocked) and `cbNoDeadlock` (cap >= 1, cap * g pure awaiters, no cancels: never blocked).
  They reject a factory or operation that never returns.
- Battery rows for the factories: `CountDownLatch.apply` raises (v11, `apply? = none`, as in the
  review term) -> cdlAwaitCompletes; hangs (v12) -> cdlNoDeadlock. `CyclicBarrier.apply` raises
  (v9) -> cbAwaitCompletes; hangs (v10) -> cbNoDeadlock. "Drops" and "doubles" are meaningless for
  a factory: its only effect is the allocation (no latch to return without it; a second
  allocation is unreachable).

## L4

Kernel-checked runs of the v3.7.1 mirror on every battery input (`LatchBattery.CDL.v0_n1`,
`v0_n2`, `v0_noRelease`, `CB.v0_cap1`, `v0_cap2`): on each, the conclusion of the broken
statement holds (done Succeeded with status 2; status 1 with started < n; waiting < cap; ...).

## Smoke (test/Phase7/LatchSmoke.lean, 12.5 min)

- cdlAwaitCompletes (restated): v3.7.1 0 of 936 done runs; await raises 838; apply raises 1,390.
- cbAwaitCompletes (restated): v3.7.1 0 of 874 done runs; await raises 1,384; apply raises 1,500.
- cdlNoDeadlock (600 runs: n 1-3, k 0-3, m n or n+1, cancels): v3.7.1 0 blocked; release hangs
  600, await hangs 400, apply hangs 600.
- cbNoDeadlock (600 runs: cap 1-3, g 0-2): v3.7.1 0 blocked; await hangs 399, apply hangs 600.

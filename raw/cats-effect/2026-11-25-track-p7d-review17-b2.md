# Track P7D: review batch 17 B2 (2026-11-25)

Source: review/2026-11-25-review-batch-17.md (B2); own Lean runs. Do not edit.

- Counterexample check (compiled eval, input `pureInp [0, 1] [0, 0] [] IO.canceled IO.pure(())`, FIFO):
  v3.7.1 parallel: done, status [0, 0], rejected [0, 0], accepted [true, false];
  twin 32 parallel: done, status [2, 0], rejected [0, 0], accepted [true, false];
  v3.7.1 sequential: done, status [2, 0], rejected [0, 0], accepted [true, false].
  So the conclusion "rejected j = 1 or status j = 2" failed for task 1 on every implementation.
- Fix: conclusion `accepted j = true → status j = 2`. Harness: an `unsafeRunAndForget` result `()`
  is saved as `some ()`, and `accepted` accepts it (otherwise forget submissions were invisible).
  Regenerated runs R10-R14 (their states change), R33/R34 (observations).
- Success companion for "rejects everything": `dispAwaitDrains` with v1 (`awaitDrains_v1`, R02).

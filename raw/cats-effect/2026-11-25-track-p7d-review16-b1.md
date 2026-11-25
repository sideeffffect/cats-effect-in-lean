# Track P7D: review batch 16 B1 fix (2026-11-25)

Source: review/2026-11-25-review-batch-16.md (B1, C1, C4); own Lean runs. Do not edit.

- B1: `dispNoLostSubmission` let the root end without joining the fiber that submits
  concurrently; the scheduler stops at the root's outcome (`Model/Sched.lean:25-26`), so with
  `c = IO.never` the statement was false for every Dispatcher, including twin 32, and the R32
  fact did not show that task 1 was submitted.
- Fix (harness, `Props/Phase7/Dispatcher.lean`): with a concurrent submitter (`1 ∈ ps`) the body
  returns the concurrent fiber (`tailK`, `retV`) and the root joins it (`joinK`, `afterJoin`)
  before the late submissions. Inputs without a concurrent submitter keep the same program, so
  runs R01-R31 kept their states (all 88 modules rebuilt, unchanged literals for R01-R31).
- New observation `accepted s j` (cell 6 holds the `unsafeToFutureCancelable` result).
- Schedule search (seeds 0-399 of `sched _ 300`, `x90`, `parallel(await = true)`): the bug path
  "root done, task 0 ran, task 1 accepted, not rejected, status 0" in seeds 7, 14, 18, 29, 33, 35;
  twin 32 meets the conclusion on each. Chosen: seed 18 (v0 370 micro-steps, twin 384).
- Kernel: R32 (5 chunks) → `ce0090_accepted_never_run`; `dispNoLostSubmission_refuted` from it;
  R33 → `noLost_twin32` (done, and for j < 2: rejected or status 2; task 1's submission throws);
  R34 → `noLost_sat` (sequential FIFO: task 1's submission throws). Largest chunk 7.24 GB.

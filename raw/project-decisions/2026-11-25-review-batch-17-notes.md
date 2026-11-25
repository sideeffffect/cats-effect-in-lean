# Review batch 17 notes (2026-11-25)

Own notes of the independent reviewer. Full review: `review/2026-11-25-review-batch-17.md`. Commit reviewed: `646d12f` (local `phase6` = `origin/main` `78fd6b3` + track V merge). Read only; no build, test or difftest. Only `python3 scripts/check_wiki.py` was run.

## Scope

Re-check of the Phase 7 batch 7.2 gate after review batch 16 (FAIL, B1): B1, C1, C2, N3, spot-check of the other 13 entries, C3 withdrawal.

## Findings

- B1 fix (commit `6e9955b`): the root joins the concurrent submitter before the late submissions (`Props/Phase7/Dispatcher.lean:320-331`). This closes the `c = IO.never` hole. New observation `accepted` (cell 6). Kernel fact `ce0090_accepted_never_run` (R32) is correct: root `Succeeded(())`, task 0 status 2, task 1 accepted, not rejected, status 0. `dispNoLostSubmission_refuted` has exactly the negated type. Twin 32 meets the conclusion on R32's input (R33). `bugs/CE-0090.yaml` `lean` is consistent. Runs R01–R31 did not change (no file change; no input with `1 ∈ ps`).
- B2 (residual of B1): the conclusion is still `rejected j = 1 ∨ status j = 2`. With `c = IO.canceled` (well-formed: `WF.progOK .canceled = true`) the concurrent fiber starts unmasked, cancels itself before it submits, the root joins the `Canceled` outcome without error and ends `Succeeded(())`; the never-submitted task has `rejected = 0`, `status = 0`. False for every Dispatcher, also twin 32. By reading, not run (confidence 0.85). Fix: conclusion `accepted j = true → status j = 2`; R32's kernel fact already has `accepted 1 = true`; add `accepted 1 = false` to R33 and R34.
- C1 met. P7D: 121,500/121,500 (seeds 91–93, every Dispatcher op ≥ 52,132). Track V: 58,500 cases, 58,498 in-run, 2 Lean batch timeouts that agree when rerun; per op 51,137. The track V run used exactly the final harness (`git diff 211706f HEAD` on `difftest`, `tools/Difftest`, `Std`, `Model` is empty). The P7D run differs from the final harness only in `gen.py` (supervise bound) and `Main.lean` (fast path); both keep the Lean side a subset of the full outcome set.
- C2 met. Bound 8 `supervise`. The fast path (`tools/Difftest/Main.lean:76-90`) is used only by the difftest tool; `Model`, `Std`, `Props` and the witnesses keep every order (`IsOrder ho`; witnesses use `ho = id`). A subset check can only give false mismatches, never false agreements: sound.
- `ConcurrentHashMap` with all hashes equal: one bin, tail append; `treeifyBin` only when a ninth entry joins a bin with 8 nodes (and below table size 64 it resizes; a resize keeps a one-bit list as one run). So insertion order holds up to 8 entries. `Unique.Token` uses the identity hash (`Unique.scala:30`).
- N3 closed: `noLeak_v11 : ¬ supNoLeakV 11` (kernel), variant 11 = the restart guard of `SV:209` without the `canceled`/`done` flags (`Std/Supervisor.lean:1087`); in `scripts/check_twin_checks.sh` and lakefile `TwinChecks`.
- C3 withdrawal confirmed: `tools/Audit/Core.lean:160-190` (decision 28). Review 16's C3 was a rule error.
- Three inventory rows are `modelled` only through `std.Dispatcher.noLostSubmission` (`unsafeToFuture`, `UnsafeAsyncQueue.unsafeOffer`, `UnsafeAsyncQueue.take`); they do not count until B2 is fixed.

## Gate

FAIL. Blocker B2. C1, C2 met; C3 withdrawn; C4 open (before proofs); C5 on the B2 commit.

## Lesson

A "root done" claim about effects of a user-started fiber must speak only about events that happened ("accepted"), because the user program can stop the fiber (never, or cancel itself). Joining the fiber closes only the "never" case.

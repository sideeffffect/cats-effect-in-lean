# Phase 7 batch 7.2 gate report (draft, 2026-11-25, re-checked in review batch 17)

> Sources: review batch 17 (2026-11-25): B1 fix, C1, C2, N3 re-check; review batch 16 (2026-11-25): registries, Props, mirrors, witnesses, batteries, kernel runs R15/R32, CE-0090, CE-0091, reproducers, inventory, Scala source v3.7.1, read-only `gh issue view 3506`
> Raw: [Review batch 17 notes](../../raw/project-decisions/2026-11-25-review-batch-17-notes.md); [Review batch 16 notes](../../raw/project-decisions/2026-11-25-review-batch-16-notes.md); [Batch 7.2 start](../../raw/project-decisions/2026-11-25-phase7-batch2-start.md); [Decision 66](../../raw/project-decisions/2026-11-25-decision-66-dispatcher-after-supervisor.md); [Decision 67](../../raw/project-decisions/2026-11-25-decision-67-jvm-hashcode.md)

## Overview

Phase 7 batch 7.2 ran on 2026-11-25 in tracks V (`Supervisor`) and P7D (`Dispatcher`) (decisions 64–67). Gate rule ([Project plan](project-plan.md), Phase 7): rows reviewed FAITHFUL; decision 63: each battery complete. Full reviews: `review/2026-11-25-review-batch-16.md`, `review/2026-11-25-review-batch-17.md`.

**Gate: FAIL (review batch 17).** Blocker B2 (residual of B1): `std.Dispatcher.noLostSubmission` is still HOLLOW. C1 and C2 are met; C3 is withdrawn; C4 stays open before proofs; C5 waits for the B2 commit. 14 of 15 entries are FAITHFUL; both batteries are complete.

Review batch 16: FAIL, blocker B1, conditions C1–C5.

## Verdict table (all batch 7.2 registry entries)

| # | Entry | Status | Verdict (batch 16) |
|---|---|---|---|
| 1 | `std.Supervisor.noLeak` | open | FAITHFUL (statement) |
| 2 | `std.Supervisor.closedNoRun` | open | FAITHFUL (statement) |
| 3 | `std.Supervisor.runsOnce` | open | FAITHFUL (statement) |
| 4 | `std.Supervisor.awaitJoins` | open | FAITHFUL (statement) |
| 5 | `std.Supervisor.noDeadlock` | open | FAITHFUL (statement) |
| 6 | `std.Supervisor.removed` | open | FAITHFUL (statement, low strength: blocked states only) |
| 7 | `std.Supervisor.cancels` | open | FAITHFUL (statement) |
| 8 | `std.Dispatcher.runsOnce` | open | FAITHFUL (statement) |
| 9 | `std.Dispatcher.awaitDrains` (heavy) | refuted (CE-0091) | FAITHFUL |
| 10 | `std.Dispatcher.noLostSubmission` (heavy) | refuted (CE-0090) | **HOLLOW** (B1; batch 17: still HOLLOW, B2) |
| 11 | `std.Dispatcher.closedRejects` | open | FAITHFUL (statement) |
| 12 | `std.Dispatcher.seqFifo` | open | FAITHFUL (statement) |
| 13 | `std.Dispatcher.cancels` | open | FAITHFUL (statement) |
| 14 | `std.Dispatcher.noDeadlock` | open | FAITHFUL (statement) |
| 15 | `std.Dispatcher.cancelStops` | open | FAITHFUL (statement) |

Proven / refuted / open (registry): 0 / 2 / 13. Counted (FAITHFUL): 0 / 1 / 13.

## Blocker

- **B2** (review batch 17, open): the root now joins the concurrent submitter (closes `c = IO.never`), but the conclusion is still `rejected ∨ status 2`. With `c = IO.canceled` the submitter cancels itself before it submits, the root joins the `Canceled` outcome and ends `Succeeded(())`, and the never-submitted task has `rejected = 0`, `status = 0`: false for every Dispatcher, also twin 32. Fix: conclusion `accepted j = true → status j = 2`; R32's kernel fact `ce0090_accepted_never_run` already has `accepted 1 = true`; add `accepted 1 = false` to R33 and R34.
- **B1** (review batch 16; partly fixed in `6e9955b`): `dispNoLostSubmission` reads a task submitted by a fiber that nobody joins; the run stops when the root has an outcome. With the user program `c = IO.never` the statement is false for every Dispatcher. The kernel fact of R32 does not show that the lost task was submitted. Twin 32 also fails the statement. Fix: join the concurrent fiber before the root ends, or claim only for accepted submissions; re-derive R32 with the "submitted" fact; set the entry `open` until then. CE-0090 stays a bug candidate with a reproducer.

## Conditions

- **C1** (met, review batch 17): P7D 121,500/121,500 (seeds 91–93, each Dispatcher op ≥ 52,132); track V 58,500 (seeds 81–83, 51,137 per op; 2 Lean batch timeouts agree on rerun). Asked: difftest ≥ 50,000 cases over ≥ 3 seeds at 100 % with the final harness (`-XX:hashCode=2`, `pollVal` fix), track V and P7D ops.
- **C2** (met, review batch 17): bound 8; the insertion-order-only replay above 5 map entries is in `tools/Difftest/Main.lean` only; it checks against a subset of the outcome set, so it is sound. Asked: lift the 5-`supervise` cap of the track V generator (bound about 8, see N6 of the review).
- **C3** (withdrawn 2026-11-25 by the orchestrator; review batch 17 confirms, `tools/Audit/Core.lean:160-190`): asked to set 13 registry-linked `todo` rows to `modelled`. `lake exe audit` rejects this: a row is `modelled` only through a proven or refuted entry, and these rows link only to `open` entries ([project plan](project-plan.md), review-1 fixes: open entries mark no rows). `todo` is correct.
- **C4** (before any proof): the `unsafe*` calls are one atomic step each; split them into their visible steps or prove a reduction.
- **C5**: CI green on the commit that closes B2 (including `heavy-proofs` and `TwinChecks`).

## Batteries

| Structure | Complete | Note |
|---|---|---|
| Supervisor | yes | restart variant 11: kernel theorem `noLeak_v11` (review 17, N3 closed) |
| Dispatcher | yes | cancel "doubles" argued (idempotent), no theorem |

## Bugs

| Bug | Lean | Reproducer (v3.7.1, series/3.x, series/3.7.x) | Review 16 |
|---|---|---|---|
| CE-0091 `parallel(await = true)` drops a queued effect | `dispAwaitDrains_refuted` (R15), twin 31 (R16) | `REPRODUCED CE-0091` | FAITHFUL |
| CE-0090 submission during release accepted, never runs | `dispNoLostSubmission_refuted` (R32: `ce0090_accepted_never_run`), twin 32 (R33) | `REPRODUCED CE-0090` | kernel fact correct; statement HOLLOW (B2); bug candidate stands |

## Difftest

- Track V: 58,500 cases (seeds 81–83), all agree, before decision 67; generator capped at 5 `supervise`. C1 run with the final harness (bound 8): 58,500 cases, 0 mismatches, 2 timeouts that agree on rerun.
- Track P7D: 114,000 cases (seeds 91–93), 113,995 agree before the final harness; the 5 mismatches (1 Scala harness bug, 4 map-order harness limit) agree with the final harness; plus 6,000 CI-shaped and 3,000 fresh cases with the final harness. C1 run with the final harness: 121,500 cases, all agree.

## See Also

- [Phase 7 batch 7.1 gate report](phase7-batch1-gate-report.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Supervisor model](../cats-effect/supervisor-model.md)
- [Dispatcher model](../cats-effect/dispatcher-model.md)
- [Differential testing](differential-testing.md)

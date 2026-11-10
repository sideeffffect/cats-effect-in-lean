# Phase 5 gate report (2026-11-10)

> Sources: own gate summary from the registry, inventory, difftest runs, reproducers and review batches 1–3 (2026-11-10)
> Raw: [Phase 5 gate approval](../../raw/project-decisions/2026-11-10-phase5-gate-approval.md); [Phase decisions](../../raw/project-decisions/2026-11-10-phase0-decisions.md); [Review batch 3 notes](../../raw/project-decisions/2026-11-10-review-batch-3-notes.md); [CI memory notes](../../raw/project-decisions/2026-11-10-ci-memory-split-notes.md)

## Overview

Phases 0–5 ran autonomously on 2026-11-10. Review batch 3 says the Phase 5 gate **passes**. This page was the input for the user review. **The user approved the gate on 2026-11-10** ([approval](../../raw/project-decisions/2026-11-10-phase5-gate-approval.md)). Phase 6 may start.

## Headline numbers

| Metric | Value |
|---|---|
| Registry entries reviewed FAITHFUL (batch 3) | 9 of 9 |
| Settled: proven / refuted / open | 2 / 4 / 3 |
| Inventory rows `modelled` (only through settled entries) | 24 of 1,396 in scope (3,255 rows, 1,859 excluded) |
| Difftest replay agreement | 58,957 cases over 6 seeds, 0 mismatch (format v1); plus 150,000 earlier cases (format v0) |
| Calibration bugs refuted in Lean and reproduced on v3.7.1 | 3 of 3 (CE-0001, CE-0002, CE-0003) |
| New bug candidate | CE-0004 (fatal `raiseError`: `IO` run loop vs `SyncIO` run loop), low priority |
| Model bugs found by difftest and fixed | 1 (idpoll) |
| Review batches | 3 (batch 1: 2 HOLLOW; batch 2: 2 HOLLOW, gate failed; batch 3: 0 HOLLOW) |

## Calibration results

| Bug | Upstream | Lean | v3.7.1 | series/3.x | series/3.7.x | Fixed twin |
|---|---|---|---|---|---|---|
| CE-0001 `syncStep` drops masks | #4687 | refuted | REPRODUCED | REPRODUCED | REPRODUCED | PR #4700 twin passes 10/10 |
| CE-0002 `Resource.eval` cancel point | #4627 | refuted | REPRODUCED | REPRODUCED | NOT REPRODUCED (fix #4630) | PR #4630 twin passes 9/9 |
| CE-0003 `take.timeout` loses element | #4571 | refuted | REPRODUCED | REPRODUCED | REPRODUCED | none (draft PR #4710 too large) |
| CE-0004 fatal `raiseError` twin | none found | refuted | REPRODUCED | REPRODUCED | REPRODUCED | one-line twin passes |

## Open caveats (from review batch 3)

1. CE-0001: the PR #4700 twin was checked in an encoding outside the formal `WellFormed` domain. A stricter reviewer could call it HOLLOW.
2. CE-0003: no fixed twin.
3. Three observation models exist (`EqvP`, the single-fiber driver, the replay scheduler). `preempt` choices have no difftest.
4. Difftest depth for format-v1 ops is 5,000–10,000 cases each, not 50,000.
5. The two proven laws are low strength (`fa` never runs).
6. CI cost: one fixed-twin check needs 13 GB; it runs in its own job.

## Questions for the user

See `QUESTIONS.md` (Q1 monad-transformer scope, Q2 `sorryAx` pattern, Q3 law context).

## See Also

- [Project plan](project-plan.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Differential testing](differential-testing.md)
- [Bug history](../cats-effect/bug-history.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)

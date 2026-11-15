# Phase 6 gate report (draft, 2026-11-15)

> Sources: own gate summary from the registry, inventory, bug records, difftest notes and review batches 4–10 (2026-11-15)
> Raw: [Review batch 10 notes](../../raw/project-decisions/2026-11-15-review-batch-10-notes.md); [Review batch 9 notes](../../raw/project-decisions/2026-11-15-review-batch-9-notes.md); [Phase 6 start](../../raw/project-decisions/2026-11-10-phase6-start.md); [Decision 58 core notes](../../raw/cats-effect/2026-11-15-decision-58-core-notes.md); [R1 fix notes](../../raw/cats-effect/2026-11-15-review9-r1-notes.md); [Race and Memoize source references](../../raw/cats-effect/2026-11-15-race-memoize-source-refs.md)

## Overview

Phase 6 (derived combinators and `Resource`) ran from 2026-11-10 to 2026-11-15 in tracks G, R, M, Res, D and P. Gate rule ([Project plan](project-plan.md), Phase 6): rows reviewed FAITHFUL; refutations reproduced. Phases 6–8 have no user gate; this report is the input for the review gate. Full review: `review/2026-11-15-review-batch-10.md`.

**Gate verdict (review batch 10): PASS**, with the conditions below. No blocker.

## Verdict table (all Phase 6 registry entries)

An entry counts only if its latest verdict is FAITHFUL (FAITHFUL as a statement for an open entry).

| # | Entry | Status | Latest verdict | Batch |
|---|---|---|---|---|
| 1 | `core.IO.race.combNoLeak` | open | FAITHFUL (statement) | 10 |
| 2 | `core.IO.race.combCanceledNoLeak` | open | FAITHFUL (statement) | 10 |
| 3 | `core.IO.timeout.noLeak` | open | FAITHFUL (statement) | 10 |
| 4 | `core.IO.raceOutcome.isWinnerOutcome` | open | FAITHFUL (statement) | 10 |
| 5 | `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` (heavy) | proven | FAITHFUL (low strength) | 10 (7) |
| 6 | `core.IO.bracketFull.kernelDefaultTwin` (CE-0005) | refuted | FAITHFUL (low strength) | 4, diff re-checked 10 |
| 7 | `core.IO.bracketFull.kernelDefaultTwin.pureUse` | open | FAITHFUL (statement) | 4, diff re-checked 10 |
| 8 | `laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO` | open | FAITHFUL (statement) | 4, diff re-checked 10 |
| 9 | `core.IO.bracket.releaseOnce` | open | FAITHFUL (statement) | 9 |
| 10 | `core.IO.guarantee.finalizerOnce` | open | FAITHFUL (statement) | 9 |
| 11 | `core.IO.memoize.noStuckGet` (CE-0030) | refuted | FAITHFUL | 10 |
| 12 | `core.IO.memoize.getsAgree` | open | FAITHFUL (statement) | 10 |
| 13 | `core.IO.memoize.atMostOnce` | open | FAITHFUL (statement) | 10 |
| 14 | `kernel.Resource.both.releaseOnce` (CE-0020) | refuted | FAITHFUL | 10 |
| 15 | `kernel.Resource.use.releaseOnce` | open | FAITHFUL (statement) | 10 |
| 16 | `kernel.Resource.flatMap.releaseOrder` | open | FAITHFUL (statement) | 10 |
| 17 | `kernel.Resource.eval.preservesCancelable` | open | FAITHFUL (statement, caveats) | 5, diff re-checked 10 |
| 18 | `core.IO.parTraverseN.resultOrder` | open | FAITHFUL (statement) | 9 |
| 19 | `core.IO.parTraverseN.pureSucceeds` | open | FAITHFUL (statement) | 9 |
| 20 | `core.IO.parTraverseN.errorAborts` | open | FAITHFUL (statement) | 9 |
| 21 | `core.IO.parTraverseN.cancelAborts` | open | FAITHFUL (statement) | 9 |
| 22 | `core.IO.parTraverseN.succeedsGen` | open | FAITHFUL (statement) | 9 |
| 23 | `core.IO.parTraverseN.errorAbortsGen` | open | FAITHFUL (statement) | 9 |
| 24 | `core.IO.parTraverseN.cancelAbortsGen` | open | FAITHFUL (statement) | 9 |
| 25 | `core.IO.parTraverseN.atMostN` | open | FAITHFUL (statement) | 9 |

## Headline numbers

| Metric | Value |
|---|---|
| Phase 6 registry entries reviewed FAITHFUL (latest verdict) | 25 of 25 |
| Settled: proven / refuted / open | 1 / 3 / 21 |
| Inventory rows `modelled` (only through settled entries) | 30 of 1,396 in scope (3,255 rows, 1,859 excluded); 6 new in Phase 6 (`core.IO.memoize`, `kernel.GenConcurrent.memoize`, `core.IO.bracketFull`, `core.IO.IOAsync.bracketFull`, `kernel.MonadCancel.bracketFull`, `laws.GenSpawnLaws.uncancelableRaceNotInherited`) |
| Refutations with a bug record and a recorded `REPRODUCED` on v3.7.1 and series/3.x | 3 of 3 (CE-0005, CE-0020, CE-0030; also series/3.7.x) |
| Bug candidates that were not real (false positives) | 0 of 3 |
| HOLLOW verdicts per batch (statement defects, before the fix) | batch 4: 2/13, 5: 3/4, 6: 5/5, 7: 4/5, 8: 6/13, 9: 3/13, 10: 0/11 |
| Review batches in Phase 6 | 7 (batches 4–10) |

## Difftest (format v2, Phase 6 ops)

| Ops | Cases, seeds | Result |
|---|---|---|
| `race`, `raceOutcome`, `both`, `bothOutcome` | 225,000, seeds 1–3; ≥ 50,782 agreeing per op | 0 mismatch |
| `guarantee`, `bracket`, `bracketCase`, `bracketFull` | 51,290–55,575 agreeing per op, seeds 1–3; merged run 60,000, seeds 11–13 | 0 mismatch |
| `memoize`, `memoGet` | 108,000, seeds 1–3 (54,404 with `memoize`) | 0 mismatch |
| `rUse`, `rAllocated`, `rBoth` | 240,000, seeds 21–23; after decision 58: 60,000 (seeds 51–53, all ops) + 195,000 (seeds 61–64); rUse 117,382, rAllocated 87,564, rBoth 52,386 | 0 mismatch |
| `parTraverseN` | 200,000 (seeds 31–34) + 90,000 (seeds 41–43) + 60,000 after decision 58 (seeds 51–52); `HashSet` cases by refinement (`alternatives`), 32 fixed cases | 0 mismatch |

Sources: [Race, both and fiber leaks](../cats-effect/race-both-model.md), [guarantee and bracket model](../cats-effect/bracket-model.md), [memoize model](../cats-effect/memoize-model.md), [Resource use, allocated, both](../cats-effect/resource-use-both-model.md), [parTraverseN model](../cats-effect/partraverse-model.md).

## Bugs found in Phase 6

| Bug | Kind | Priority | Lean | v3.7.1 | series/3.x | Fixed twin |
|---|---|---|---|---|---|---|
| CE-0005 `IO.bracketFull` vs kernel `bracketFull` | twin divergence | low | refuted | REPRODUCED | REPRODUCED | `poll(IO.defer(use(a)))` agrees on 8 programs |
| CE-0020 `Resource#both` skips a release | invariant violation | medium | refuted | REPRODUCED | REPRODUCED | "attempt both chains": 120 schedules (kernel), 2,100 (smoke) |
| CE-0030 `IO#memoize` stuck `get` | liveness | medium | refuted | REPRODUCED | REPRODUCED | `poll(...)` in `Finished`: 7 `fa`, all one-preemption schedules < 120 |

The reproducers are re-run by another agent at this gate; this report judges the records only.

## Conditions (not blockers)

1. CI green on the reviewed commit `1dfe6ce` (build, audit, heavy and twin matrices). The reviewer did not run anything.
2. The reproducer re-run (other agent) confirms `REPRODUCED` on v3.7.1 and series/3.x.
3. One recorded `opcount.py` run of the `Resource` ops after the R1 encoding change (review batch 10, D2).

## Open caveats

1. 21 of 25 entries are open: the statements are FAITHFUL, but they need state invariants over `Step`/`SchedP` (bracket release, race control invariant, memo cell). Phase 6 adds 1 proof (a closed law, low strength).
2. Harness privacy needed six review rounds (batches 4–9: markers, leaf fields, clock numbers, number fields, `REnv` table indices). Decision 58 plus the R1 fix close it by construction for closure and table references; Phase 7 models must use `Val.fn` for every name from the start ([Agent workflow](agent-workflow.md), "Closure references").
3. Documentation drift (batch 10 D1, D3): a `Memoize` registry claim is false (no claim breaks); two bug records say "waits for review".
4. Inventory (batch 10 D4): `kernel.Resource.both`/`use`/`fold` can become `modelled` through CE-0020; `makeCase` is not mirrored in general.
5. Phase 5 twins `ResourceFixed`, `SyncStepFixed` still name entries by numbers; they run only closed programs, so this is not a risk.

## See Also

- [Phase 5 gate report](phase5-gate-report.md)
- [Project plan](project-plan.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Differential testing](differential-testing.md)
- [Bug history](../cats-effect/bug-history.md)

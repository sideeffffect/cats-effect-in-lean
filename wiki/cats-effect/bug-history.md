# Cats Effect bug history and target areas

> Sources: typelevel/cats-effect issues labelled `:beetle: bug` and 3.x release notes, collected 2026-11-10
> Raw: [Review 2 fixes notes](../../raw/cats-effect/2026-11-10-review2-ce0001-ce0004-notes.md); [Bug history notes](../../raw/cats-effect/2026-11-10-ce-bug-history-notes.md); [3.x release bug fixes](../../raw/cats-effect/cats-effect-3x-release-bug-fixes.md); [Open bug status check](../../raw/cats-effect/2026-11-10-open-bug-status-check.md); [Calibration reproducers notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md); [SyncIO and syncStep mirror notes](../../raw/cats-effect/2026-11-10-syncstep-mirror-notes.md); [Resource mirror notes](../../raw/cats-effect/2026-11-10-resource-mirror-notes.md)

## Overview

156 issues carry the `:beetle: bug` label (23 open; 139 from the CE3 era). 16 3.x releases list 101 bug-fix items. Bugs cluster in derived combinators, std data structures without laws, and lock-free runtime code. Component counts below come from a regex over titles, so they are approximate.

## Counts per component (approximate)

IOFiber / cancellation / finalizers 35 · scheduler 25 · timeout / race / `par*` 23 · async callbacks 15 · Resource 11 · tracing / IOLocal 11 · Queue 10 · Dispatcher 9.

## Bug classes

| Class | Examples (typelevel/cats-effect) |
|---|---|
| A. Cancel loses an element or a wakeup | [#4571](https://github.com/typelevel/cats-effect/issues/4571) (open, `Queue.take.timeout` loses elements), [#4483](https://github.com/typelevel/cats-effect/issues/4483) (open), #3603, #3998, #3187, #3554 |
| B. Finalizers skipped / cancel point in wrong place | [#4687](https://github.com/typelevel/cats-effect/issues/4687) (open, `syncStep` drops `uncancelable`/`onCancel`, so `Resource` release is skipped), [#4627](https://github.com/typelevel/cats-effect/issues/4627) (open, extra cancel point in `Resource.eval`), #3474 (open), #4488 (closed "as designed"), #2472, #3609, #1736 |
| C. timeout and race | #4489 (connection leak in 3.6.x), #4697 (open), #1816, #3111, #4434 |
| D. async callback protocol | #3725, #3891, #3940, #3935, #2858 |
| E. Dispatcher / Supervisor lifecycle | #4490, #3862, #3945, #3363, #4069 (open) |
| F. Scheduler liveness | [#4674](https://github.com/typelevel/cats-effect/issues/4674) (open, `LocalQueue.enqueueBatch` spins forever on a dangling steal tag), #4628 (open), #3422, #4228, #4225 |
| G. Gaps in the test model | #3430 (open, PureConc does not run finalizers), #2552, #3899 (memory model) |

Full list with titles and URLs is in the raw notes.

## Recommended first targets (in order)

1. MonadCancel + GenSpawn kernel semantics, checked against the existing laws (sanity test of the model).
2. Queue cancellation safety (#4571, #4483): "under any cancel interleaving, every offered element is taken or still in the queue".
3. `Resource.eval`, `allocated`, `timeout` (#4627, #4697, #4489).
4. `syncStep` keeps masks and finalizers (#4687).
5. Supervisor and Dispatcher lifecycle.
6. `LocalQueue` steal-tag protocol (#4674) — needs a weak-memory model; later.

Calibration idea: a faithful model must be able to refute the properties behind the known open bugs. If it cannot, the model is wrong or too abstract.

## Status of the calibration bugs (checked 2026-11-10)

All five are open issues and all five are present at v3.7.1. No release after v3.7.1 exists. Fixes go to `series/3.7.x` first and are merged forward into `series/3.x` later.

| Bug | Fix PR | Merged? | Code at v3.7.1 |
|---|---|---|---|
| #4687 `syncStep` | #4700 (open), tests #4686 (open) | no | `core/shared/src/main/scala/cats/effect/IO.scala:2390`, `:2396` (`SyncStep.interpret`) |
| #4627 `Resource.eval` | #4630 | yes, `series/3.7.x` only (`2f94201`, 2026-10-12); not on `series/3.x`; not released | `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala:485`, `:508`, `:526` (`allocatedCase`) |
| #4571 `take.timeout` | #4710 (draft); #4641 closed unmerged | no | `core/shared/src/main/scala/cats/effect/IOFiber.scala:909` (`RacePair`); cause is `racePair`, not `Queue` |
| #4483 `Queue#mapK` | none | no | `std/shared/src/main/scala/cats/effect/std/Queue.scala:51` |
| #4697 `Resource` timeout `reportFailure` | #4712 (open) | no | `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala:1455` (no `racePair` override) |

- #4627 stays open only because #4630 targets a non-default branch. For the `series/3.x` reproducer run, also run on `series/3.7.x`.
- #4697 is likely a `Resource` form of #2962 ("unfixable in general"). It is a weak calibration target.
- New bug-labelled issues since 2026-08-23: only #4674 (`LocalQueue`; open PRs #4688, #4696). It is a runtime target (Phase 9).

## Calibration bug records and reproducers (Phase 5, Scala side)

Draft records with deterministic `scala-cli` reproducers. Run all with `scripts/run_reproducers.sh` (not in CI). Lean status: all three are refuted in Lean (CE-0004, a new candidate, too). CE-0001: registry entry `core.IO.syncStep.syncStepIdentitySyncIO` ([SyncIO and syncStep model](syncio-and-syncstep-model.md)). CE-0002: `kernel.Resource.eval.preservesUncancelable` ([Resource model](resource-model.md)). CE-0003: `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement` ([Queue and timeout model](queue-model.md)). Review batch 1 found the CE-0001 property HOLLOW (it allows external cancel); a fix is in progress.

| Record | Upstream | Promise (short) | Reproducer method | v3.7.1 |
|---|---|---|---|---|
| [CE-0001](../../bugs/CE-0001.yaml) | #4687 | `AsyncLaws.syncStepIdentity` (`AsyncLaws.scala:84`) | `TestControl`; direct vs `syncStep` remainder, cancel after 10 ms | REPRODUCED (4/4 cases); Lean: refuted (case 4) |
| [CE-0002](../../bugs/CE-0002.yaml) | #4627 | `Resource.eval` "Preserves interruptibility of `fa`" (`Resource.scala:986`) | `TestControl`; `eval` vs `make` twin | REPRODUCED (3/3 cases); Lean: refuted (case C) |
| [CE-0003](../../bugs/CE-0003.yaml) | #4571 | No lost element; `IO#timeout` returns the source outcome (`IO.scala:800`) | `TestControl` seeds 0–499 | REPRODUCED (328/500 and 37/500 seeds); Lean: refuted (program A, FIFO schedule) |
| [CE-0004](../../bugs/CE-0004.yaml) | none (new; related #3767, #3811, #549) | `SyncIO#to` translates (`SyncIO.scala:190`); `AsyncLaws.syncStepIdentity` | no runtime for `SyncIO`; one fatal `IO` run, last | REPRODUCED on 3.7.1, `series/3.x`, `series/3.7.x`; Lean: refuted (`raiseErrorTwin`, fatal `e`) |

Results on `series/3.x` and `series/3.7.x` snapshots: see the records and the [raw notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md).

- CE-0003 is a `racePair` defect. Under `TestControl`, the external-cancel form loses the element in most seeds, so the Lean model needs only a small schedule search to find it. Confirmed: the FIFO schedule (no choices) of the model already loses the element (`takeTimeoutNoLostElement_refuted`).
- CE-0004 (review batch 2, decision 38): `IO.raiseError(fatal)` calls `onFatalFailure` (`IOFiber.scala:263-269`, PR #3811), `SyncIO.raiseError(fatal)` is an ordinary error (`SyncIO.scala:257-259`). `SyncIO#to[IO]` and `IO#syncStep` move a program between the two policies. Priority low, likely partly intended (maintainers keep fatal errors out of the laws, #549); no duplicate found. Not a calibration bug: it is the first new candidate. CE-0001 is now stated for non-fatal errors only. [SyncIO and syncStep model](syncio-and-syncstep-model.md).
- Fixed twins (decision 39): CE-0001 has a mirror of PR #4700 that satisfies the property on 10 programs; CE-0004 has a one-line `SyncIO` twin; CE-0003 has none (PR #4710 rewrites `IOFiber` cancelation).
- CE-0001: case 4 (`IO.uncancelable(_ => IO.canceled *> flag.set(true))`) needs no external cancel. It is the Lean counterexample (`syncStepIdentitySyncIO_refuted`). Also 4/4 on `series/3.x` and `series/3.7.x`.
- CE-0002: `Resource.make(fa)(noop)` is the twin that keeps `fa` masked. The record compares the two. Case C (`Resource.eval(IO.uncancelable(_ => IO.canceled)).allocatedCase` vs the same under `IO.uncancelable`) needs no time and no external cancel. It is the Lean counterexample (`resourceEvalPreservesUncancelable_refuted`). The fix on `series/3.7.x` passes all 3 cases.

## Open questions

- #4488 (a fiber cancelled before it first runs never registers its finalizers) is "as designed". Treat as a spec decision, not a bug.

## See Also

- [Pinned version](pinned-version.md)
- [Source layout](source-layout.md)
- [Semantics of CE3](semantics.md)
- [Lessons for Cats Effect in Lean](../methodology/lessons-for-cats-effect.md)
- [SyncIO and syncStep model](syncio-and-syncstep-model.md)
- [Resource model and CE-0002](resource-model.md)
- [Queue and timeout model](queue-model.md)

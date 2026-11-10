# Cats Effect bug history and target areas

> Sources: typelevel/cats-effect issues labelled `:beetle: bug` and 3.x release notes, collected 2026-11-10
> Raw: [Bug history notes](../../raw/cats-effect/2026-11-10-ce-bug-history-notes.md); [3.x release bug fixes](../../raw/cats-effect/cats-effect-3x-release-bug-fixes.md)

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

## Open questions

- Do the open bugs #4687, #4627, #4571 already have fix PRs on `series/3.x`? Check before working on them.
- #4488 (a fiber cancelled before it first runs never registers its finalizers) is "as designed". Treat as a spec decision, not a bug.

## See Also

- [Pinned version](pinned-version.md)
- [Source layout](source-layout.md)
- [Semantics of CE3](semantics.md)
- [Lessons for Cats Effect in Lean](../methodology/lessons-for-cats-effect.md)

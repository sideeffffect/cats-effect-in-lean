# Difftest generator: run-event coverage (decision 17) (own note)

> Source: own work in this repository (`difftest/py/gen.py`, `difftest/py/coverage.py`, `difftest/py/selftest.py`), run on 2026-11-10 against Cats Effect 3.7.1 (Scala runner v0)
> Collected: 2026-11-10
> Published: 2026-11-10

## Problem

Decision 17: some run events were rare before the 50,000-case gate. An external cancel acts only between tasks. Most programs ended in their first task (mean 1.3 prefix runs per case, see below), so most external cancels and child steps never ran.

## Measurement: `difftest/py/coverage.py`

- It counts what RAN in the Scala replay run, not what the program text contains.
- Step attribution: the Scala output does not tell which step emitted a trace event. The tool runs each case again with `maxSteps = k` for k = 1 .. steps-1. Each run stops after k steps, so its trace is a prefix of the full trace. The prefix lengths give the step and the task label of each event. The tool checks the prefix property. Result: 0 violations in 161,341 prefix runs, so the replay runner is deterministic and a fuel stop does not change earlier events.
- Owner of an event: the fiber label of its step. A canceler step `x<k>` belongs to the cancel target. A callback step `cb<a>.<i>` belongs to the fiber that emitted `asyncReg a`.
- Cancel request on fiber L: an external `{"cancel":h}` schedule entry, or an internal marker `delay fn1 arg fiber(h)` that the generator puts just before `cancel f`.
- Region markers: `delay fn1 arg nat M`, M = 7,700,000,000 + kind × 1,000,000 + 2 × id + exit. Kinds: 1 uncancelable body, 2 finalizer body, 3 escaped poll inside a finalizer, 4 join result follows (the next event is `delay fn1 o` with the join outcome). They only add `call` events; the Lean side runs them as normal `delay` nodes.
- Usage: `python3 difftest/py/coverage.py --seeds 1 2 3 --n 10000 [--gen OLD/gen.py] [--json FILE]`. About 30 s per 10,000 cases (53,000 prefix runs).

## Generator changes

- New template `tpl_scenario`: the parent starts a long-lived child, cedes n times, then cancels it (`cancel f` with a marker, or an external choice), and often joins it with a join marker. Kinds: `masked` (uncancelable region with cedes), `fin` (cancel in the core, or in a `guaranteeCase` finalizer with cedes; 40% get a second canceler fiber), `cb` (child waits in an async with a later callback; 85% with an async finalizer), `nested` (child started a grandchild), `escpoll` (child got an escaped poll and uses it in its finalizer), `complete` (`tpl_handoff` where parent and child both complete the Deferred).
- Timing window: n is in [lo, hi] such that under FIFO (parent and child take turns at each cede) the cancel lands at the planned point. External cancels use a hint (handle 1, steps 2·lo .. 2·hi).
- 60% of root programs (size ≥ 4) are a scenario; 70% of these get a choice list with mostly FIFO picks. `tpl_scenario` is also a composite production (weight 3, size ≥ 6; internal cancel only, because the handle is not known).
- Other changes: 50% of generated `cancel f` get the marker; `tpl_cancelChild` joins with a marker in 30%; `tpl_escapedPoll` finalizer shapes get a marker and the parent then joins (and cancels for `onCancel`); `tpl_handoff` lets both fibers complete the Deferred in 45%; `g_fin` suspend finalizers get finalizer markers in 60%. No feature was removed.
- Cost: mean program size 13.6 → 26.2 nodes (seed 1, 3,000 cases), max 79 → 139.

## Before and after (3 seeds × 10,000 cases, % of cases)

"n/a": the old generator has no markers, so the event cannot be seen.

| run event | before | after |
|-----------|-------:|------:|
| external cancel of a child (applied) | 1.86 | 22.41 |
| external cancel of a child (target still live) | 1.21 | 20.94 |
| async finalizer runs | 0.91 | 6.51 |
| `complete` returns false | 0.33 | 6.48 |
| finalizer with canceled outcome (onCancel, or guaranteeCase oc=canceled) | 6.72 | 15.83 |
| of these: guaranteeCase oc=canceled | 4.19 | 7.13 |
| choice among > 1 ready task | 16.30 | 56.70 |
| cancel while masked, then region exit | n/a (0) | 6.17 |
| cancel during a finalizer (finalizer then completes) | n/a (0) | 6.63 |
| escaped poll used inside a finalizer | n/a (0) | 6.57 |
| callback after its owner was canceled | 1.38 | 8.02 |
| join on a canceled fiber | n/a (0) | 18.90 |
| cancel of a nested parent (it started a fiber) | 0.04 | 5.87 |
| external cancel of the root | 12.38 | 15.18 |
| outcome blocked | 18.47 | 18.42 |
| outcome fuel | 0.75 | 1.77 |
| outcome succeeded / errored / canceled | 41.5 / 23.2 / 16.1 | 41.7 / 19.2 / 18.9 |
| `reportFailure` calls | 6.25 | 11.00 |
| pending tasks or timers at the end | 27.71 | 31.15 |
| prefix runs (sum of steps − 1) | 36,918 | 161,341 |

- TypeError, decode error, hang: 0 before and after.
- The before numbers match the generator-driver note (child cancel 1.9%, async finalizer 0.9%, complete false 0.3%, > 1 ready 16.3%).

## Self-test

- `selftest.py` step 7: `coverage.run` on 600 cases of seed 20261110. Each key event must be in ≥ 3.5% of cases (the 5% target with a margin for the small sample). Blocked + fuel < 25%. Values at commit time: lowest event 4.8% (`complete` false), blocked + fuel 20.2%. Self-test time 20.5 s.

## Observations about CE (Scala runs alone)

- The known "masked end" behaviour ([Scheduler model](../../wiki/cats-effect/scheduler-model.md), `cancel-child-masked-end`) is now common in generated runs. A fiber that is canceled while masked and whose masked region is its last action completes `Succeeded`. If any step follows the region, it completes `Canceled`. Seed 1, 3,000 cases: "cancel during a `guaranteeCase` finalizer after success" gave join results succeeded 72, errored 29, canceled 7. "Cancel while masked, then region exit" gave canceled 81, succeeded 27, errored 17.
- Hand check on the runner: `uncancelable(_ => seq(canceled, pure 1))` as the root gives `succeeded 1`; the same followed by `delay` gives `canceled`. A child `uncancelable(_ => seq(cede, pure 1))` canceled at the cede gives join `succeeded 1`; with a `delay` after the region it gives join `canceled`.
- Still to do: check the docs and the laws for this case (is it a promised behaviour?), before any bug record.
- No TypeError, no hang, no nondeterminism (`drive.py scala-check --seeds 1 2 3 --n 10000`: replay 30,000/30,000 and testcontrol 12,000/12,000 identical on rerun).
- TestControl outcome in the replay outcome set (FIFO + 8 random schedules): 99.2% (was 99.8%). Outcome and trace: 87.4% (was 97%). Programs now have more steps, so the schedule space is larger and 9 schedules sample less of it. This is a sampling gap, not a runtime difference (same reason as before); not analysed case by case.

# Difftest depth, `timeoutTo` mirror and preempt coverage (track D, batch 6.1) (own note)

> Source: own work in this repository (`difftest/`, `tools/Difftest/`, `CatsEffectInLean/Model/Timeout.lean`), runs on 2026-11-10 against Cats Effect 3.7.1
> Collected: 2026-11-10
> Published: 2026-11-10

Task: Phase 5 gate caveat 4 (format-v1 ops need at least 50,000 agreeing cases over at least 3 seeds) and caveat 3 (`preempt` choices have no difftest).

## Measurement before

- New: `drive.py run` prints, for each format-v1 op, the agreeing cases whose program contains the op (total and per seed; also in `--json` as `v1_op_agree`).
- Seeds 1-6 x 10,000 replay cases, old generator, old Lean side: 58,957 agree, 1,043 unsupported (all `timeoutTo`), 0 mismatch.

| op | agreeing cases before (seeds 1-6 x 10,000) |
|----|------:|
| syncStep | 5,392 |
| timeout | 7,311 |
| timeoutTo | 0 (unsupported) |
| queueNew | 5,241 |
| queueOffer | 3,348 |
| queueTake | 4,835 |
| queueTryTake | 3,586 |
| allocatedCase | 10,082 |
| rPure | 3,263 |
| rEval | 6,108 |
| rMake | 7,067 |
| rFlatMap | 5,439 |

## `timeoutTo` with a user fallback: now mirrored

- `Model/Timeout.lean`: the closures `body`, `sel`, `thenJoin`, `fold` get a fallback descriptor `fb : Val`. `Val.none` = the `TimeoutException` fallback that `timeout` passes (`IO.scala:820-822`); `Val.some c` = a caller fallback, built by `srcIO c` (`fallbackOf`). `timeoutIO src d` uses `Val.none`; new `timeoutToIO src fb d` (`IO.scala:850-860`). So both go through the same lambdas, as in Scala.
- Difftest: new closure kind `timeoutFb` (code of `I(fb)`, with the snapshot); `srcIO` builds `I(e)` of a `timeout` or `timeoutTo` node and `I(fb)` of a `timeoutTo` node. `unsupportedReason` has no entries now.
- The CE-0003 calibration proof (`Proofs/Calibration/QueueTimeout.lean`, `decide +kernel`) still builds.
- First run (seeds 1-6 x 10,000): all 1,043 `timeoutTo` cases agree. Mutation check: a model whose `fallbackOf` ignores the caller fallback gives 41 mismatches in 5,000 cases (seed 1).

## Generator weight change

- `timeoutTo`: 0.35 -> 1.2 (same as `timeout`). Reason: it was low because the op was unsupported; at 0.35 it was in 1.8 % of cases, so 50,000 agreeing cases would need about 2.9 million cases. Now 5.8 %.
- The other v1 ops were left as they were. Lowest share: `rPure` 5.2 %. 1.2 million cases give more than 50,000 for each op.
- `selftest.py`: the minimum share of `timeoutTo` is now 3 % (was 0.5 %), as for the other v1 ops.

## Preempt coverage: case field `runtime`

- `IORuntimeConfig().copy(cancelationCheckThreshold = c, autoYieldThreshold = a)` is public. With a small `a`, the run loop auto-yields after every few iterations (`IOFiber.scala:224-240`). The auto-yield builds the same fiber record as `SchedP.preemptRun` (`resumeTag = AutoCedeR`, `resumeIO = _cur0`, enqueue); `Step.lean:1141-1144` and `SchedP.lean` `preemptRun`. So these runs test the preemption transition at many run-loop positions, in the exact replay mode (no refinement needed).
- Format: optional case field `"runtime":{"cancelationCheckThreshold":c,"autoYieldThreshold":a}`, replay only, checks of `IORuntimeConfig.scala:33-40` (c > 0, a > 1, a mod c = 0) on both sides. Scala `Runner.replay(..., config)`; Lean `Config` from the case.
- Generator: 25 % of cases (`CONFIG['p_runtime']`), own RNG (`difftest-runtime:<seed>:<i>`), so the other fields of each case do not change. c in {1, 1, 2, 4}, a = c x k (k in 1..8, a > 1).
- Fixed cases `difftest/cases/preempt.jsonl` (`gen_preempt.py`, 14 cases, golden file): two children with default and small thresholds, a cancel that lands inside a run of `delay`s (with a = 2 the child is canceled before its last `delay`; with the default it runs to the end), a masked child, and 4 `timeoutTo` cases.
- What it does not cover: a preemption after fewer than `a - 1` iterations of a fresh task in every position at once (each case has one period); `preempt` with a pending cancel from another thread (`Loop.flush` at a preemption; the replay has no concurrent outside cancel); true parallel runs (two fibers at the same time).

## Mismatches found and fixed (both in the difftest glue, not in the CE model)

First big run (seeds 101-112 x 100,000, new generator): 1,199,995 agree, 5 mismatch.

1. `gcfin-snapshot` (2 cases, field `steps`, only with `runtime` thresholds). Interp: `o => IO.delay(emit) *> run(fin).void`. `*>` takes its argument by value (`IO.scala:138-139`), so Scala builds `run(fin)` when this function runs. The Lean closure `gcFinThen` built `I(fin)` one closure later, with the view of that moment; a comment said "nothing else runs in between". An auto-yield between the two let another fiber complete, so `fib.cancel` read `IO.unit` in Lean but the real canceller in Scala (more run-loop iterations, one more task). Fix: `gcFinK` captures the snapshot; `gcFinThen` builds with it. The default thresholds (1024) almost never put a yield there, so 1.6 million earlier cases did not show it.
2. `usererr-999998` (3 cases, field `failures`, default thresholds). A program caught a `TimeoutException` (value `nat 999998`) and raised it again through user function `raise`, so Scala reported `UserError(999998)`. Lean coded `UserError(c)` as `c + 2`, and `999998 + 2 = 10^6` is the model `TimeoutException` code, so Lean printed `TimeoutException`. Fix: `userErr` skips code `10^6` (`c + 3` above it); `userCode?` maps both back to 999998 (the value-language code, `Interp.scala` `CodeOf`). New `#guard`s in `Tests.lean`.

- Shrunk cases: `difftest/corpus/fixed-gcfin-snapshot-{a,b}.json`, `fixed-usererr-999998-{a,b}.json` (`triage: harness-bug`, `expect: agree`). The fifth case (seed 111) has the same `failures` cause; it agrees after the fix.
- Shrinking: `drive.py shrink` keeps the `runtime` field. The shrunk `gcfin` case mismatches only with a in {4} when c in {1, 2, 4} (threshold sweep 2..16), so a single fixed period would not have found it.

## Result after the fixes

Seeds 101-112 x 100,000 replay cases (1.2 million; 25 % with small thresholds): 1,200,000 agree, 0 mismatch, 0 unsupported, 0 generator bug, 0 hang. Time: 4 workers, about 16 minutes on a loaded machine.

| op | agreeing cases | lowest seed | highest seed |
|----|------:|------:|------:|
| syncStep | 108,490 | 8,917 | 9,191 |
| timeout | 153,662 | 12,618 | 12,948 |
| timeoutTo | 68,647 | 5,595 | 5,868 |
| queueNew | 108,973 | 8,946 | 9,306 |
| queueOffer | 70,928 | 5,756 | 6,102 |
| queueTake | 100,409 | 8,272 | 8,474 |
| queueTryTake | 74,189 | 6,082 | 6,351 |
| allocatedCase | 208,695 | 17,317 | 17,470 |
| rPure | 65,960 | 5,400 | 5,617 |
| rEval | 127,666 | 10,505 | 10,746 |
| rMake | 147,068 | 12,164 | 12,352 |
| rFlatMap | 112,859 | 9,293 | 9,504 |

Every op: more than 50,000 agreeing cases over 12 seeds (each seed more than 5,000).

## CI

- Job `difftest`: `check` also runs `preempt.jsonl`; `run --seeds 1 2 3 --n 2000` now gets `--min-v1-agree 150` (fails if a v1 op is in fewer than 150 agreeing cases; actual lowest 323, `rPure`). The `lean` job decodes `preempt.jsonl` too. Clean-clone run of the job steps: agreement steps 19 s (sbt test, self-test and build before them).
- `drive.py` help text for `--allow-known-model-bugs` said "CI uses it"; corrected (decision 32: CI never uses it).

## Not done: refinement against the multi-threaded runtime

Design and cost. Each real run on the work-stealing `IORuntime` gives one (outcome, trace); the check is "is it in the `EqvP` outcome set". `exploreP` (`EnumP.lean`) computes exact sets, but it is a kernel-oriented breadth-first search with list membership. Generated programs (mean 26 nodes, 2-4 fibers, 50-300 iterations) have state spaces far above the 322 states that the `EnumP` checks handle; the search needs a compiled run with hashing, a preemption bound (dejafu style, bound 2) and a `complete` flag, plus a refinement mode in `drive.py`. The trace of a real parallel run also depends on timing, so most programs need several runs. Estimate: 2-3 agent days, and a per-case cost that needs measuring. The `runtime` cases above test the same preemption transition in exact replay mode at a small cost, so they come first.

## Open item for the orchestrator

- The note of registry entry `takeTimeoutNoLostElement` (`CatsEffectInLean/Registry.lean`) says "the model mirrors timeoutTo only with the TimeoutException fallback". That is out of date since this track. Not changed here: the file is shared and the entry was reviewed. Inventory row `core.IO.timeoutTo` stays `todo` (no registry entry names it).

# Differential testing of the Lean model against Cats Effect

> Sources: synthesized from wiki articles on python-formalization, julia-in-lean, formalization precedents, CE source layout, Lean tooling (2026-11-10); TestControl spike (2026-11-10); generator and driver build (2026-11-10); first Lean-vs-Scala replay runs (2026-11-10); generator coverage work (2026-11-10); `RacePair`/`Sleep` runs (2026-11-10)
> Raw: [RacePair and Sleep notes](../../raw/cats-effect/2026-11-10-racepair-sleep-notes.md); [First difftest agreement notes](../../raw/project-decisions/2026-11-10-first-difftest-agreement-notes.md); [Generator coverage notes](../../raw/project-decisions/2026-11-10-generator-coverage-notes.md); [Generator and driver notes](../../raw/project-decisions/2026-11-10-difftest-generator-driver-notes.md); [Lean decoder notes](../../raw/project-decisions/2026-11-10-lean-difftest-decoder-notes.md); [python-formalization difftest harness](../../raw/python-formalization/2026-10-29-lean-core-and-difftest-harness.md); [Harness code copy](../../raw/lean-tooling/python-formalization-difftest-harness-code.md); [Cedar DRT + Lean FFI](../../raw/lean-tooling/cedar-spec-drt-and-lean-ffi-readmes.md); [TestControl docs](../../raw/lean-tooling/cats-effect-testcontrol-docs.md); [TestControl spike notes](../../raw/cats-effect/2026-11-10-testcontrol-spike-notes.md); [Netsem](../../raw/formalization-precedents/2018-10-netsem-engineering-with-logic-tcp-test-oracle.md); [SibylFS](../../raw/formalization-precedents/2015-10-sibylfs-formal-spec-oracle-based-testing-posix.md); [Orchestrator merge notes](../../raw/project-decisions/2026-11-10-orchestrator-merge-notes.md)

## Overview

Both agent precedents and Cedar require the model to agree with the real implementation on many generated inputs **before** any property is stated. A mismatch is a model bug until proven otherwise. CE adds a new difficulty that the precedents did not have: scheduling nondeterminism. This article records the design. Built so far: the schedule spike, the Scala runner v0 in `difftest/`, the Lean decoder and translation in `tools/Difftest/` (see [Difftest program format v0](difftest-program-format.md)), and the generator, driver and shrinker in `difftest/py/` (sections below). `cediff` runs replay cases on the model; section "Lean vs Scala results". All parts run in CI.

## Rules from precedents

- 100% agreement on ≥50,000 edge-heavy cases over several seeds before stating properties (python-formalization).
- Model is wrong on mismatch: fix the model, never the reproducer, never delete a generator case (julia, python).
- Generators must be type-directed and cover failure paths (Cedar). Measure *semantic* (rule) coverage, not line coverage (KJS, Cedar).
- Shrink failing cases; commit them as a CI regression suite (Cedar, Csmith).
- Run every *proved* statement against the real system too: proofs about wrong models happen (python-formalization found 4).

## Harness shape (proposed)

- Lean side: `lean_exe cediff` reads one JSON case per line (files or stdin) and writes one JSON result per line (python-formalization `pydiff` pattern). Built: decode, translation into `Model.IO`, and the replay run on `Model.Sched`. A subprocess is fast enough: 2,000 cases in 0.14 s.
- Ops that the model cannot run yet (none in format v0 since `RacePair` and `Sleep` are mirrored) and testcontrol mode are reported as `unsupported`. They are not approximated, because an approximation would make agreement meaningless ([Difftest program format v0](difftest-program-format.md), "Lean side").
- Scala side: an sbt project pinned to CE v3.7.1 generates programs (an IO AST), interprets them into real `IO`, runs them, and compares.
- Deterministic runs: a scripted `ExecutionContext` that follows a choice list ([TestControl and schedule replay](../cats-effect/testcontrol.md)); also `TestControl` (single thread, virtual time, random ready-fiber choice with a seed; `tick`, `tickOne`, `tickAll`, `advance`, `results`, `isDeadlocked`). Docs warn it can hide real multi-thread races.

## Handling nondeterminism

- **Refinement, not equality**: each observed CE outcome/trace must be in the set the Lean model allows over all schedules (Netsem/SibylFS "loose spec").
- Better: make the real side **log its choices** (which fiber ran, when cancel was observed) and feed them to the model, so checking is a total function (Netsem lesson).
- **Decision (2026-11-10, spike 0.2): both modes, replay first.** `TestControl` runs only seeds; it cannot take or report a schedule. A small scripted `ExecutionContext` in the public `IORuntime(...)` can do both, on the same IOFiber code path as `TestControl`. Primary mode: replay a choice list on both sides and compare exactly. Secondary mode: refinement for `TestControl` seeds and the real runtime. Choice points are task-level (cede, auto-cede, async resume, fiber end). Details: [TestControl and schedule replay](../cats-effect/testcontrol.md).
- Also run on the real `IORuntime` (work-stealing pool) to catch races TestControl hides; use refinement there.
- Model cancel observation as a nondeterministic choice at each boundary.

## Generator (`difftest/py/gen.py`)

- Seeded and deterministic: case i of seed s depends only on (s, i), the weight table and the size limit. Ids are `g<seed>-<i>`.
- Type-directed: `Gen.prog(T, env, size)` makes a program of type T. `typecheck.py` (first-order unification) checks every case. A `TypeError` in the Scala runner is a generator bug (decision 8). Result on 30,000 cases: 0.
- Weight table `WEIGHTS` (one weight per op and per template) and knobs `CONFIG`. Productions that use a fiber, ref or deferred in scope get ×2.5. Poll gets ×3 inside finalizers.
- Edge-case templates: escaped poll (`uncancelable(p => start(child that uses p))`, also poll inside the child's finalizer), finalizer stacks (1-3 onCancel/guaranteeCase layers around a suspend or cancel point; finalizers raise, suspend, or use an outer poll), cancel child, racePair with the loser in scope, Deferred handoff, Ref updates in parent and child. Async: 0-3 callbacks, sync or later, ok or err, 60% with a finalizer.
- Schedule per case: a choice list (80%), with 1-3 external `{"cancel":h}` choices in 50% of cases (root, a child, or an unknown handle), mostly at steps 1-3. 3% get `maxSteps` 1-5.
- `to_testcontrol(case, seed)` gives the same program in testcontrol mode (no external cancel there).
- Long-lived scenarios (decision 17). An external cancel acts only between tasks, and most old programs ended in their first task. So 60% of root programs are a `tpl_scenario`: the parent starts a child, cedes n times, cancels it (`cancel f`, or an external choice at a hinted step), and often joins it. Child kinds: `masked` (uncancelable region with cedes), `fin` (cancel in the core or inside a `guaranteeCase` finalizer with cedes; sometimes a second canceler fiber), `cb` (waits in an async with a later callback and a finalizer), `nested` (started a grandchild), `escpoll` (escaped poll used in its finalizer), `complete` (parent and child both complete a Deferred). n is in a window such that, under FIFO, the cancel lands at the planned point. 70% of these cases get mostly-FIFO picks. The template is also a normal production (internal cancel only). Mean program size went from 14 to 26 nodes.
- Markers: `delay fn1 arg nat M` (M ≥ 7.7·10^9 encodes kind, region id, enter/exit) around uncancelable bodies and finalizers, in escaped-poll finalizers, and before a join result; `delay fn1 arg f` before `cancel f`. They only add `call` events. They let `coverage.py` see what ran.

## Coverage (`difftest/py/coverage.py`)

- Counts run events of the Scala replay run (not program content). It reruns each case with `maxSteps = 1 .. steps-1`; the prefix traces give the step and the owner fiber of each trace event (0 prefix violations in 161,341 runs).
- Key events (3 seeds × 10,000 cases, before → after): external cancel of a live child 1.2 → 20.9%; async finalizer runs 0.9 → 6.5%; `complete` false 0.3 → 6.5%; finalizer with canceled outcome 6.7 → 15.8%; choice among > 1 ready 16.3 → 56.7%; cancel while masked then region exit → 6.2%; cancel during a finalizer → 6.6%; escaped poll used in a finalizer → 6.6%; callback after the owner was canceled 1.4 → 8.0%; join on a canceled fiber → 18.9%; cancel of a nested parent 0.04 → 5.9%. Blocked + fuel 19.2 → 20.2%. Full table: [raw note](../../raw/project-decisions/2026-11-10-generator-coverage-notes.md).
- `selftest.py` asserts each key event in ≥ 3.5% of 600 cases and blocked + fuel < 25%.
- Seen in Scala runs: the known "masked end" behaviour (a fiber canceled while masked, whose masked region is its last action, completes `Succeeded`; [Scheduler model](../cats-effect/scheduler-model.md)) is now frequent. Docs and laws for it are not checked yet.

## Driver (`difftest/py/drive.py`)

- `run`: generate, run Scala (`difftest/run.sh`, replay and testcontrol), run Lean (`--lean "lake exe cediff"`), sort into bins, `--shrink` mismatches into the corpus.
- `check FILE…`: fixed case files on Scala and Lean; fails unless each case agrees or is `unsupported`.
- `scala-check`: Scala alone. Replay and testcontrol determinism, "TestControl outcome is a replay outcome" over FIFO + 8 random schedules, coverage histogram (static ops and patterns, trace events, schedule events), timing.
- Compare. Replay: Lean lists the fields it can compare (`compare`); now all nine Scala fields (outcome, trace, steps, time, schedule, fifoFrom, fibers, pending, failures). They must be equal; the first differing field is the detail. Testcontrol: refinement. Proposed Lean output: `"outcomes":[{"outcome","trace"}…]` and `"complete":bool`; not in the set and complete → mismatch; not complete → inconclusive. Scala `inconclusive` (step cap) → inconclusive.
- Automatic bins: `agree`, `unsupported` (Lean prints `"outcome":"unsupported"`; not a mismatch), `inconclusive`, `mismatch`, `harness`, `generator-bug`, `hang` (a timed-out batch is bisected to the case).
- Shrinker: greedy delta debugging over well-typed candidates (replace a node by a child or by `raise 0`/`never`/`pure`/`canceled`/`cede`, drop seq elements, callbacks, finalizers, tags; drop choice chunks; picks → 0). A candidate is kept only if it is strictly smaller and the mismatch field is the same (without "strictly smaller" it cycles). One Scala batch and one Lean batch per round.
- Self-test `difftest/py/selftest.py` (about 20 s, CI job `difftest`): type checker, generator determinism, no generator bug, Scala determinism, bins and shrinking with a fake Lean side (`mock_lean.py`, planted fault: one missing `fin onCancel` event; a 113-node case shrinks to 3 nodes), corpus rerun, minimum run-event coverage.

## Corpus (`difftest/corpus/`)

One JSON file per shrunk mismatch: `case`, `scala` (outcome, trace), `lean`, `field`, `expect` (`agree` by default, or `mismatch` for an accepted difference), `triage`, `note`, `found`. `drive.py corpus [--lean CMD]` fails if the Scala result changed or the Lean result is not `expect`. Format table: `difftest/README.md`. The corpus is empty now: the first Lean runs had no mismatch to save.

## Scala-only results (2026-11-10)

3 seeds × 10,000 cases in 50 s. 0 generator bugs, 0 hangs. Replay and testcontrol runs are deterministic (30,000 and 12,000 cases, each run twice). TestControl outcome in the replay outcome set: 99.8% with 9 schedules per case; every outcome miss was found with more schedules (sampling gap, not a runtime difference). Weak coverage then: async finalizer runs 0.9%, external cancel of a child 1.9%. Full histogram: [raw note](../../raw/project-decisions/2026-11-10-difftest-generator-driver-notes.md). Fixed by the scenario template (section Coverage). After it: 0 generator bugs, replay and testcontrol still deterministic; TestControl outcome in the replay outcome set 99.2% (outcome and trace 87.4%: more steps per program, so 9 schedules sample less of the space).

## Lean vs Scala results (2026-11-10)

Replay mode, all nine fields compared. Details: [First difftest agreement notes](../../raw/project-decisions/2026-11-10-first-difftest-agreement-notes.md).

| run | agree | unsupported | mismatch |
|-----|------:|------------:|---------:|
| seeds 1, 2, 3 × 2,000 | 1588, 1663, 1616 | 412, 337, 384 | 0 |
| seeds 1-10 × 10,000 | 81,663 | 18,337 | 0 |
| seeds 11-20 × 10,000, max size 80 | 80,148 | 19,852 | 0 |
| `basic.jsonl` + `sched.jsonl` | 29 | 4 | 0 |
| after `RacePair`/`Sleep`: seeds 1-5 × 10,000 | 10,000 each | 0 | 0 |
| after `RacePair`/`Sleep`: seeds 11-20 × 10,000, max size 80 | 100,000 | 0 | 0 |
| after `RacePair`/`Sleep`: `basic`, `sched`, `deferred`, `racesleep` | 51 | 2 (testcontrol) | 0 |

- No model bug found: every runnable case agreed on the first full run, also after `RacePair` and `Sleep` ([RacePair and Sleep notes](../../raw/cats-effect/2026-11-10-racepair-sleep-notes.md)).
- Before `RacePair`/`Sleep`: `sleep` in 13% of cases, `racePair` in 7% were unsupported. Now no replay op is unsupported. Testcontrol cases: all (decision 15).
- Mutation test (one planted bug in `Step.lean`, 8,153 runnable cases): 9 of 13 mutants killed (12 to 250 mismatches each). 3 survivors are equivalent in single-thread replay. 1 was a coverage gap (2+ fibers waiting on one `Deferred` at `complete`); `difftest/cases/deferred.jsonl` now kills it.
- Mutation test of `RacePair`/`Sleep` (seed 1, 10,000 cases): 9 of 11 mutants killed (7 to 263 mismatches). 2 survive generated cases (wake order of timers with one due time); `racesleep.jsonl` (`sleep-order`) kills them.
- CI job `difftest` runs `check` on the fixed files (`basic`, `sched`, `deferred`, `racesleep`), the corpus, and 3 × 2,000 generated replay cases. Any mismatch fails the job.
- The 50,000-case gate is met for the replay mode, all ops (150,000 cases after `RacePair`/`Sleep`). Still open: testcontrol refinement, and the coverage gaps of decision 17.

## Triage bins for a mismatch

model bug · harness/glue bug · deliberate model simplification · intended CE behaviour (spec decision) · underspecified (ask maintainers) · real CE bug. Expect most early mismatches to be model bugs. A human sets the bin in the corpus entry (`triage`: `model-bug`, `harness-bug`, `model-simplification`, `intended-ce-behaviour`, `underspecified`, `ce-bug`; default `untriaged`).

## Gotcha: sbt class path cache

`difftest/run.sh` caches the sbt class path. sbt prints a terminal escape after the class path line, so take the line that ends in `.jar` or `/classes`, never the last line. A stale local cache hid this bug; CI was red for 4 pushes. Test harness changes in a clean clone ([merge notes](../../raw/project-decisions/2026-11-10-orchestrator-merge-notes.md)).

## See Also

- [Difftest program format v0 and Scala runner](difftest-program-format.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Lessons for Cats Effect in Lean](lessons-for-cats-effect.md)
- [Modeling approaches](../semantics/modeling-approaches.md)
- [Source layout](../cats-effect/source-layout.md)
- [TestControl and schedule replay](../cats-effect/testcontrol.md)
- [Scheduler model (multi-fiber, replay)](../cats-effect/scheduler-model.md)
- [Formalization precedents](../precedents/formalization-precedents.md)

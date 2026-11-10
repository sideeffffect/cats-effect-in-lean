# Differential testing of the Lean model against Cats Effect

> Sources: synthesized from wiki articles on python-formalization, julia-in-lean, formalization precedents, CE source layout, Lean tooling (2026-11-10); TestControl spike (2026-11-10); generator and driver build (2026-11-10)
> Raw: [Generator and driver notes](../../raw/project-decisions/2026-11-10-difftest-generator-driver-notes.md); [Lean decoder notes](../../raw/project-decisions/2026-11-10-lean-difftest-decoder-notes.md); [python-formalization difftest harness](../../raw/python-formalization/2026-10-29-lean-core-and-difftest-harness.md); [Harness code copy](../../raw/lean-tooling/python-formalization-difftest-harness-code.md); [Cedar DRT + Lean FFI](../../raw/lean-tooling/cedar-spec-drt-and-lean-ffi-readmes.md); [TestControl docs](../../raw/lean-tooling/cats-effect-testcontrol-docs.md); [TestControl spike notes](../../raw/cats-effect/2026-11-10-testcontrol-spike-notes.md); [Netsem](../../raw/formalization-precedents/2018-10-netsem-engineering-with-logic-tcp-test-oracle.md); [SibylFS](../../raw/formalization-precedents/2015-10-sibylfs-formal-spec-oracle-based-testing-posix.md)

## Overview

Both agent precedents and Cedar require the model to agree with the real implementation on many generated inputs **before** any property is stated. A mismatch is a model bug until proven otherwise. CE adds a new difficulty that the precedents did not have: scheduling nondeterminism. This article records the design. Built so far: the schedule spike, the Scala runner v0 in `difftest/`, the Lean decoder and translation in `tools/Difftest/` (see [Difftest program format v0](difftest-program-format.md)), and the generator, driver and shrinker in `difftest/py/` (sections below). The Lean run waits for the step function. All parts run in CI.

## Rules from precedents

- 100% agreement on ≥50,000 edge-heavy cases over several seeds before stating properties (python-formalization).
- Model is wrong on mismatch: fix the model, never the reproducer, never delete a generator case (julia, python).
- Generators must be type-directed and cover failure paths (Cedar). Measure *semantic* (rule) coverage, not line coverage (KJS, Cedar).
- Shrink failing cases; commit them as a CI regression suite (Cedar, Csmith).
- Run every *proved* statement against the real system too: proofs about wrong models happen (python-formalization found 4).

## Harness shape (proposed)

- Lean side: `lean_exe cediff` reads one JSON case per line (files or stdin) and writes one JSON result per line (python-formalization `pydiff` pattern). Built: decode + translation into `Model.IO`; the run is next. Cedar shows FFI is faster, but a subprocess is probably enough.
- Ops that the model cannot express yet (`join`, `cancel`, `refNew`, `deferred*`) are reported as `unsupported`. They are not approximated, because an approximation would make agreement meaningless ([Difftest program format v0](difftest-program-format.md), "Lean side").
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

## Driver (`difftest/py/drive.py`)

- `run`: generate, run Scala (`difftest/run.sh`, replay and testcontrol), run Lean (`--lean "lake exe cediff"`), sort into bins, `--shrink` mismatches into the corpus.
- `scala-check`: Scala alone. Replay and testcontrol determinism, "TestControl outcome is a replay outcome" over FIFO + 8 random schedules, coverage histogram (static ops and patterns, trace events, schedule events), timing.
- Compare. Replay: outcome, then trace, then schedule (if Lean prints one) must be equal; the first differing field is the detail. Testcontrol: refinement. Proposed Lean output: `"outcomes":[{"outcome","trace"}…]` and `"complete":bool`; not in the set and complete → mismatch; not complete → inconclusive. Scala `inconclusive` (step cap) → inconclusive.
- Automatic bins: `agree`, `unsupported` (Lean prints `"outcome":"unsupported"`; not a mismatch), `inconclusive`, `mismatch`, `harness`, `generator-bug`, `hang` (a timed-out batch is bisected to the case).
- Shrinker: greedy delta debugging over well-typed candidates (replace a node by a child or by `raise 0`/`never`/`pure`/`canceled`/`cede`, drop seq elements, callbacks, finalizers, tags; drop choice chunks; picks → 0). A candidate is kept only if it is strictly smaller and the mismatch field is the same (without "strictly smaller" it cycles). One Scala batch and one Lean batch per round.
- Self-test `difftest/py/selftest.py` (about 15 s, CI job `difftest`): type checker, generator determinism, no generator bug, Scala determinism, bins and shrinking with a fake Lean side (`mock_lean.py`, planted fault: one missing `fin onCancel` event; a 69-node case shrinks to 3 nodes), corpus rerun.

## Corpus (`difftest/corpus/`)

One JSON file per shrunk mismatch: `case`, `scala` (outcome, trace), `lean`, `field`, `expect` (`agree` by default, or `mismatch` for an accepted difference), `triage`, `note`, `found`. `drive.py corpus [--lean CMD]` fails if the Scala result changed or the Lean result is not `expect`. Format table: `difftest/README.md`. The corpus is empty now (no Lean run yet).

## Scala-only results (2026-11-10)

3 seeds × 10,000 cases in 50 s. 0 generator bugs, 0 hangs. Replay and testcontrol runs are deterministic (30,000 and 12,000 cases, each run twice). TestControl outcome in the replay outcome set: 99.8% with 9 schedules per case; every outcome miss was found with more schedules (sampling gap, not a runtime difference). Weak coverage: async finalizer runs 0.9%, external cancel of a child 1.9%. Full histogram: [raw note](../../raw/project-decisions/2026-11-10-difftest-generator-driver-notes.md).

## Triage bins for a mismatch

model bug · harness/glue bug · deliberate model simplification · intended CE behaviour (spec decision) · underspecified (ask maintainers) · real CE bug. Expect most early mismatches to be model bugs. A human sets the bin in the corpus entry (`triage`: `model-bug`, `harness-bug`, `model-simplification`, `intended-ce-behaviour`, `underspecified`, `ce-bug`; default `untriaged`).

## See Also

- [Difftest program format v0 and Scala runner](difftest-program-format.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Lessons for Cats Effect in Lean](lessons-for-cats-effect.md)
- [Modeling approaches](../semantics/modeling-approaches.md)
- [Source layout](../cats-effect/source-layout.md)
- [TestControl and schedule replay](../cats-effect/testcontrol.md)
- [Formalization precedents](../precedents/formalization-precedents.md)

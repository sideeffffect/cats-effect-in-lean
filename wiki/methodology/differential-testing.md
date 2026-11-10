# Differential testing of the Lean model against Cats Effect

> Sources: synthesized from wiki articles on python-formalization, julia-in-lean, formalization precedents, CE source layout, Lean tooling (2026-11-10); TestControl spike (2026-11-10)
> Raw: [python-formalization difftest harness](../../raw/python-formalization/2026-10-29-lean-core-and-difftest-harness.md); [Harness code copy](../../raw/lean-tooling/python-formalization-difftest-harness-code.md); [Cedar DRT + Lean FFI](../../raw/lean-tooling/cedar-spec-drt-and-lean-ffi-readmes.md); [TestControl docs](../../raw/lean-tooling/cats-effect-testcontrol-docs.md); [TestControl spike notes](../../raw/cats-effect/2026-11-10-testcontrol-spike-notes.md); [Netsem](../../raw/formalization-precedents/2018-10-netsem-engineering-with-logic-tcp-test-oracle.md); [SibylFS](../../raw/formalization-precedents/2015-10-sibylfs-formal-spec-oracle-based-testing-posix.md)

## Overview

Both agent precedents and Cedar require the model to agree with the real implementation on many generated inputs **before** any property is stated. A mismatch is a model bug until proven otherwise. CE adds a new difficulty that the precedents did not have: scheduling nondeterminism. This article records the design. Built so far: the schedule spike and the Scala runner v0 in `difftest/` (see [Difftest program format v0](difftest-program-format.md)). The Lean side is not built yet.

## Rules from precedents

- 100% agreement on ≥50,000 edge-heavy cases over several seeds before stating properties (python-formalization).
- Model is wrong on mismatch: fix the model, never the reproducer, never delete a generator case (julia, python).
- Generators must be type-directed and cover failure paths (Cedar). Measure *semantic* (rule) coverage, not line coverage (KJS, Cedar).
- Shrink failing cases; commit them as a CI regression suite (Cedar, Csmith).
- Run every *proved* statement against the real system too: proofs about wrong models happen (python-formalization found 4).

## Harness shape (proposed)

- Lean side: `lean_exe` (e.g. `cediff`) reads one JSON case per line on stdin, writes one JSON result per line (python-formalization `pydiff` pattern). Cedar shows FFI is faster, but a subprocess is probably enough.
- Scala side: an sbt project pinned to CE v3.7.1 generates programs (an IO AST), interprets them into real `IO`, runs them, and compares.
- Deterministic runs: a scripted `ExecutionContext` that follows a choice list ([TestControl and schedule replay](../cats-effect/testcontrol.md)); also `TestControl` (single thread, virtual time, random ready-fiber choice with a seed; `tick`, `tickOne`, `tickAll`, `advance`, `results`, `isDeadlocked`). Docs warn it can hide real multi-thread races.

## Handling nondeterminism

- **Refinement, not equality**: each observed CE outcome/trace must be in the set the Lean model allows over all schedules (Netsem/SibylFS "loose spec").
- Better: make the real side **log its choices** (which fiber ran, when cancel was observed) and feed them to the model, so checking is a total function (Netsem lesson).
- **Decision (2026-11-10, spike 0.2): both modes, replay first.** `TestControl` runs only seeds; it cannot take or report a schedule. A small scripted `ExecutionContext` in the public `IORuntime(...)` can do both, on the same IOFiber code path as `TestControl`. Primary mode: replay a choice list on both sides and compare exactly. Secondary mode: refinement for `TestControl` seeds and the real runtime. Choice points are task-level (cede, auto-cede, async resume, fiber end). Details: [TestControl and schedule replay](../cats-effect/testcontrol.md).
- Also run on the real `IORuntime` (work-stealing pool) to catch races TestControl hides; use refinement there.
- Model cancel observation as a nondeterministic choice at each boundary.

## Triage bins for a mismatch

model bug · harness/glue bug · deliberate model simplification · intended CE behaviour (spec decision) · underspecified (ask maintainers) · real CE bug. Expect most early mismatches to be model bugs.

## See Also

- [Difftest program format v0 and Scala runner](difftest-program-format.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Lessons for Cats Effect in Lean](lessons-for-cats-effect.md)
- [Modeling approaches](../semantics/modeling-approaches.md)
- [Source layout](../cats-effect/source-layout.md)
- [TestControl and schedule replay](../cats-effect/testcontrol.md)
- [Formalization precedents](../precedents/formalization-precedents.md)

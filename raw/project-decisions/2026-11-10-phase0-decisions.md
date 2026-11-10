# Phase 0 decisions (orchestrator)

> Source: own decisions after the Phase 0 spike reports, 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

Agents asked these questions. The orchestrator decided them, because they are technical and reversible.

1. Reproducers run on v3.7.1, `series/3.x`, and also `series/3.7.x`. Reason: fixes land on `series/3.7.x` first (#4627 fix is only there).
2. External cancel (`fiber.cancel` at a chosen step) is part of the difftest choice list from the first harness version. Reason: cancel is the main bug class.
3. Difftest primary mode: schedule replay through a scripted `ExecutionContext` in a custom `IORuntime`. Secondary mode: refinement against `TestControl` seeds and the real runtime.
4. Under `TestControl` refinement, a run that hits the step cap is "inconclusive", not a mismatch. Spin-wait programs stay in the generator.
5. Kernel evaluation: `decide +kernel` for single runs and witnesses; `decide_cbv` for bounded schedule enumeration. No CI time budget yet. Phase 2 measures the real model first.
6. Fairness definitions from the liveness spike (`Schedule := Nat → Choice`, `Fair`, `Terminates`) are adopted for Phase 2.
7. Monad-transformer instances stay `deferred:`. Logged as Q1 in `QUESTIONS.md`.

Later decisions on the same day (after Phase 1–3 agent reports):

8. Difftest `TypeError` (for example `inc` on a pair) is a generator bug. The generator must produce only well-typed programs. It is not modelled as a user error.
9. `Val` and `IO` stay separate inductives for now. Merge them into one mutual inductive only when a mirrored combinator needs an `IO` inside a value.
10. `sorryAx` in the forbidden list: logged as Q2 in `QUESTIONS.md`; no change now.

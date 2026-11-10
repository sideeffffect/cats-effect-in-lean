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

Decisions after the step-function and Lean-decoder reports:

11. Escaped `poll` is public API (a user can return `poll` out of `uncancelable`). "Escaped poll in a finalizer skips the remaining finalizers" is a bug candidate for Phase 8, not a user question. It gets a property, a refutation and a reproducer like any other candidate, with an honest `maybe_intended`.
12. Runtime-made closures (`join`, `cancel`, `IODeferred` get/complete, `racePair`/`sleep` registration) are `RtFn` cases. This mirrors CE, where these are closures over fiber fields.
13. `UserEffect` gets additive cases for trace output (`emit`) and allocation (new `Ref`/`Deferred`). `Fn.user` may carry captured values, so the id-encoding workaround in `tools/Difftest/Closure.lean` can go later.

Decisions after the scheduler, generator and kernel-typeclass reports:

14. External-cancel handles: the Scala runner keeps its handle numbering (handles count `start`/`racePair` results). The Lean side (`cediff`) maps handles to model fiber ids.
15. Testcontrol mode: Lean prints the set of allowed results from a bounded schedule search plus a `complete` flag (Phase 2 step 10). Until then, testcontrol mode checks Scala against itself only.
16. Law rows: one registry entry per (law, instance). The IO entry makes the row `modelled`. A SyncIO entry is added where the root-scope split applies; both entries list the same row.
17. Weak coverage spots (external cancel of a child 1.9%, async finalizer 0.9%, `complete` false 0.3%) need generator weights raised before the 50,000-case gate.

Decisions after the first Lean-vs-Scala agreement, calibration reproducers and coverage work:

18. Merged check (orchestrator, new generator): 5 seeds x 10,000 replay cases: 41,355 agree, 0 mismatch, 8,645 unsupported (`sleep` 6,670, `racePair` 2,543).
19. Properties about `join`, `cancel`, `Ref`, `Deferred` and masks may start now, restricted to programs without `sleep`/`racePair`. The 50,000-case gate is met for that fragment (161,811 + 41,355 agreeing cases over 25 seeds). Properties that need `racePair` or `sleep` wait for their mirrors and their own 50,000 cases.
20. "A canceled fiber whose last action is a masked region completes `Succeeded`" is a Phase 8 property candidate. Check it against the docs and laws. The generator keeps producing it often.
21. Reproducers are not in CI yet (scala-cli download time). They run with `scripts/run_reproducers.sh` at each gate.

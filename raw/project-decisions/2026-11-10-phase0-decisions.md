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

Decisions after the racePair/sleep, enumerator/laws and syncStep reports:

22. Law context: default (a), the program runs alone (Q3 in `QUESTIONS.md`). Model programs may use only fiber handles they received.
23. A property may use the single-fiber driver when the behaviour it states is single-fiber (for example `syncStep`). The statement must say so. The reviewer judges it.
24. Phase 8 twin candidate: a failed `racePair` loser is never sent to `reportFailure`, but a failed unjoined `start` fiber is.
25. Merged check: 3 seeds x 10,000 replay cases, 30,000 agree, 0 mismatch, 0 unsupported (all ops supported).

Decisions after review batch 1 (`review/2026-11-10-review-batch-1.md`) and the CE-0002/CE-0003 refutations:

26. CE-0001 property: remove external cancel from its schedules (the reviewer showed that a correct `syncStep` also refutes it). Cut its rows to those the witness uses.
27. All properties quantify over programs Scala can express: a `WellFormed` predicate (received fiber handles only, no forged poll/cont/closure ids, only even user-function ids) or quantification through `Translate.tr` of difftest programs. This is a type invariant, so it is an allowed hypothesis.
28. A row becomes `modelled` only through a proven or refuted entry. Open entries do not mark rows. The audit gets this extra check (a stricter gate).
29. Auto-yield position (iteration counts) is not a CE promise. Default for law `Eqv`: allow a preemption at any run-loop iteration, which matches the multi-threaded runtime. Q3 in `QUESTIONS.md` records this.
30. Mirrors of `syncStep`/SyncIO, `Resource` and `Queue` need difftest support before their rows pass review (method rule: difftest before properties).
31. The two closure codecs (`Model/Codec.lean`, `Model/ValCodec.lean`) must become one. The merge put `ValCodec` in its own namespace as a stop-gap.

Decisions after the review-1 fixes and difftest v1:

32. A known model bug keeps CI red until the mirror is fixed. CI never passes `--allow-known-model-bugs` (that would weaken a gate). The idpoll bug was fixed the same day (`IO.applyPoll`).
33. `Eqv` keeps the cut at root completion (as `IOApp` and CE's law-test `Eq[IO]`). Effects of child fibers after the root ends are not observed; leak and liveness properties state them separately.
34. Next gate step: review batch 2 of all registry entries after the fixes. The Phase 5 gate passes only when the 3 calibration refutations are FAITHFUL.

Decisions after review batch 2 (`review/2026-11-10-review-batch-2.md`; Phase 5 gate FAILED: CE-0001 and CE-0002 HOLLOW, CE-0003 FAITHFUL):

35. A failed gate means: do not start Phase 6. Fixing the gate's rows is still Phase 5 work, so agents continue with the fixes.
36. Do decision 29 now: `Eqv` gets a preemption choice at any run-loop iteration. Re-prove CE-0002 under it.
37. `WellFormed`: poll values are opaque to user code (user code can only apply them), and user programs cannot build `UnmaskRunLoop _ 0 _`.
38. The fatal-`raiseError` difference between the `IO` run loop (`IOFiber.scala:265-269`) and the `SyncIO` run loop (`SyncIO.scala:257-259`) is its own bug candidate (next id CE-0004). CE-0001 is stated for non-fatal errors only, and the ordinary-input rule then holds.
39. New rule for every refutation: a "fixed twin" check. Mirror the upstream fix (or the `possible_fix`) as a twin and show, on a bounded domain, that the fixed twin satisfies the property. A refutation that the fixed twin also fails is HOLLOW.

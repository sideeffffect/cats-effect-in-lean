# Project plan: Cats Effect v3.7.1 in Lean

> Sources: own plan, written 2026-11-10 from all wiki articles; user asked for "a detailed step by step plan how to do this whole thing"
> Raw: [Project plan draft note](../../raw/project-decisions/2026-11-10-project-plan-draft.md); [User decisions on the plan](../../raw/project-decisions/2026-11-10-plan-decisions.md); [Start signal](../../raw/project-decisions/2026-11-10-start-signal.md); [Phase 0 decisions](../../raw/project-decisions/2026-11-10-phase0-decisions.md)

## Overview

The end-to-end plan, from research to bug records. Status: **started 2026-11-10** (user: "Start the process"). Phase 0 runs now; Phases 1–5 follow without a user gate. Work in small steps; push each green step. Open questions for the user: `QUESTIONS.md`.
Each phase has an exit gate. Do not start a phase before the gate of the phase before it passes, except where noted.
Time estimates assume agents do the work and the user reviews at gates. Confidence in the estimates: 0.4.
Confidence in the phase order: 0.75 (same as the [lessons](lessons-for-cats-effect.md) synthesis).

## User decisions (2026-11-10)

1. **Values:** untyped `Val` universe; typed wrappers only in property statements.
2. **Scope:** safety **and** liveness/fairness from the start.
3. **Masks:** model both the `IOFiber` mask counter and the spec (fresh mask ids) in Phase 2.
4. **Execution:** after Phase 0 and "start", agents run Phases 1–5 autonomously in parallel worktrees. The user reviews at the Phase 5 gate.

## Phase 0 results (2026-11-10)

- Step 1 done: all 5 calibration bugs are open and present at v3.7.1 ([Bug history](../cats-effect/bug-history.md)).
- Step 2 done: `TestControl` is seed-random only; a scripted `ExecutionContext` replays and logs chosen schedules ([TestControl](../cats-effect/testcontrol.md)).
- Step 3 done: kernel evaluation is fast enough for witnesses and bounded enumeration ([Kernel evaluation](../lean/kernel-evaluation.md)).
- Step 4 done: `Schedule`, `Fair`, `Terminates` shapes proven on a toy ([Fairness and liveness](../semantics/fairness-and-liveness.md)).
- Step 5 decisions:
  1. Reproducers also run on `series/3.7.x`.
  2. External cancel is a schedule choice in the difftest.
  3. Difftest = replay first, refinement second; step-capped `TestControl` runs are inconclusive.
  4. Use `decide +kernel` for witnesses and `decide_cbv` for enumeration.
  5. Monad transformers stay deferred (Q1 in `QUESTIONS.md`).
- Phase 1 step 2 (inventory) done early: [Inventory](inventory.md).
- Phase 1 steps 1, 3, 4 done: layout, [Registry and audit](registry-and-audit.md), CI jobs.
- Phase 2 steps 1–4 (data) done: [IO ADT and fiber state](../cats-effect/io-adt-and-fiber-state.md).
- Phase 2 step 5 done for one fiber: [Run-loop model](../cats-effect/runloop-model.md). 7 predictions match CE 3.7.1. Next: multi-fiber scheduler and concurrency tags (steps 6–9).
- Phase 3 step 4 started: Lean decoder and `cediff` skeleton in `tools/Difftest/`; sbt job in CI.
- Decisions 11–13 (escaped `poll` = Phase 8 candidate; `RtFn` for runtime closures; `UserEffect.emit` and allocation).
- Phase 2 steps 6 and 8 (part) done: [Scheduler model](../cats-effect/scheduler-model.md); 15 replay cases agree with Scala (hand-translated). Missing: `RacePair`, `Sleep`, foreign `EvalOn`, `IODeferred`, bounded enumerator.
- Phase 3 steps 3 and 5 done: generator, driver, shrinker in `difftest/py/`; 30,000 Scala cases deterministic. Lean does not run cases yet.
- Phase 4 step 1 groundwork done: [Kernel typeclasses model](../cats-effect/kernel-typeclasses-model.md); 33 laws stated, none registered.
- Decisions 14–17 (handle mapping in `cediff`; Lean outcome sets for testcontrol; one registry entry per law and instance; raise weak generator weights).
- Phase 3 step 4 done for replay mode: `cediff` runs the model. 0 mismatches on 203,166 runnable generated cases (25 seeds); `IODeferred` mirrored. CI runs 3 x 2,000 cases. Gaps: `RacePair`, `Sleep`, testcontrol refinement.
- Generator coverage raised: every weak run event now ≥ 5.9% of cases.
- Phase 5 Scala side done: CE-0001 (#4687), CE-0002 (#4627), CE-0003 (#4571) reproduce on v3.7.1 ([Bug history](../cats-effect/bug-history.md)). Lean refutations need `syncStep`, `Resource`, `racePair`, `sleep`, `timeout`, `Queue`.
- Decisions 18–21 (properties may start on the fragment without `sleep`/`racePair`; masked-end `Succeeded` is a Phase 8 candidate; reproducers run at gates).
- Phase 2 steps 8 and 10 done: `RacePair`, `Sleep` mirrored; 150,000 replay cases agree, 0 unsupported. Bounded enumerator with soundness ([Outcome sets and Eqv](../semantics/outcome-equivalence.md)).
- Phase 4 started: 2 IO laws proven, 2 open (see Q3 in `QUESTIONS.md`).
- Phase 5: CE-0001 refuted in Lean ([SyncIO and syncStep model](../cats-effect/syncio-and-syncstep-model.md)); CE-0002, CE-0003 next.
- Decisions 22–25 (laws judged in isolation by default; single-fiber driver allowed when stated; `racePair` loser report twin is a Phase 8 candidate).
- Phase 5: all 3 calibration bugs refuted in Lean and reproduced on v3.7.1 ([Resource model](../cats-effect/resource-model.md), [Queue model](../cats-effect/queue-model.md)).
- Review batch 1: 3 FAITHFUL, 2 HOLLOW (CE-0001 property, `uncancelablePollIsIdentity` statement). Gate not passed yet. Fixes: decisions 26–31.
- Review-1 fixes done: one codec, `WellFormed` hypothesis on all entries, CE-0001 without external cancel (rows 27 → 5), stricter audit (open entries mark no rows; 23 rows `modelled`).
- Difftest v1 (`syncStep`, `Resource`, `Queue`, `timeout`): 58,957 cases agree; idpoll model bug fixed (decisions 32–34). Review batch 2: **gate FAILED** (CE-0001, CE-0002 HOLLOW; CE-0003 FAITHFUL). Fixes: decisions 35–39.
- Phase 3 steps 1–2 (Scala runner) done: [Difftest program format v0](difftest-program-format.md). sbt is not in CI yet.
- Later decisions: generator programs are well-typed (a `TypeError` is a generator bug); `Val` and `IO` stay separate until a combinator needs `IO` in a value.

## Phase map

| # | Phase | Output | Gate | Estimate |
|---|---|---|---|---|
| 0 | Close research gaps | 5 spike notes in the wiki, decisions recorded | User approves the plan and says "start" | 2–4 days |
| 1 | Scaffolding | Directory layout, inventory, registry, audits in CI | CI green with empty registry | 2–3 days |
| 2 | Core model of `IOFiber` | Executable small-step model, scheduler input, fairness, both mask models | Hand examples pass; kernel can evaluate a small run | 3–4 weeks |
| 3 | Difftest harness | Scala runner + Lean `cediff` + driver | 100% agreement, ≥50,000 cases, ≥3 seeds | 2–3 weeks (overlaps 2) |
| 4 | Kernel laws + liveness | Laws and termination under fair schedules, settled | All law rows settled and reviewed | 3–5 weeks |
| 5 | Calibration | Model refutes 3 known open bugs | 3 reproducers print `REPRODUCED`; **user review** | 1–2 weeks |
| 6 | Derived combinators, `Resource` | Mirrors + properties | Rows reviewed FAITHFUL | 3–5 weeks |
| 7 | std structures | Queue first, then the rest | Rows reviewed FAITHFUL | 6–10 weeks |
| 8 | Bug hunt | New bug candidates and records | Each candidate settled | ongoing |
| 9 | Runtime (optional) | `LocalQueue`, `CallbackStack` with a memory model | Separate decision | months |

## Phase 0 — close research gaps (still research; allowed now)

1. **Check the status of the open bugs** #4687, #4627, #4571, #4483, #4697 on `series/3.x` (read-only `gh`). Record fix PRs. A bug that is fixed on `series/3.x` is still a valid calibration target at v3.7.1.
2. **TestControl spike.** Read `testkit/.../TestControl.scala` and `TestContext.scala` at v3.7.1. Answer: can the runner follow a schedule that we choose, or only a seed? Can it log which task ran at each step? This decides the difftest mode (step 3.4).
3. **Kernel-evaluation spike.** A refutation is a concrete counterexample. Its proof must run the model inside the Lean kernel (`decide`, `rfl`, `decide_cbv`), because `native_decide` is forbidden. Build a toy fiber interpreter (fuel, structural recursion), run 2 fibers × 20 steps under `decide`, and measure time and memory. If it is too slow, plan proof by lemmas instead of brute evaluation.
4. **Liveness spike.** Liveness needs infinite schedules. Define a schedule as a stream of choices and a fairness predicate (each runnable fiber is picked infinitely often; each pending cancel is observed eventually). State "terminates" as: for every fair schedule there is a fuel `n` that finishes. Test this statement shape on the toy interpreter from step 3. Read how dejafu and Marlow 2001 treat fairness.
5. **Write the decisions** into the wiki: modeling approach (small-step + scheduler, [Modeling approaches](../semantics/modeling-approaches.md)), untyped `Val`, safety + liveness, both mask models, difftest mode, the fairness definition.
6. **Gate:** user approves this plan and says "start the formalization". Update `AGENTS.md` "Current phase". From here, Phases 1–5 run without a user gate.

## Phase 1 — scaffolding

1. **Layout.**
   - `CatsEffectInLean/Model/` — `Syntax`, `Val`, `Fiber`, `Step`, `Sched`, `Run`.
   - `CatsEffectInLean/Kernel/`, `Std/` — mirrors of derived combinators and std structures.
   - `CatsEffectInLean/Props/` — property definitions only (no proofs, no local notation).
   - `CatsEffectInLean/Proofs/` — `*_proven` / `*_refuted` theorems.
   - `CatsEffectInLean/Registry.lean` — one entry per property: id, inventory rows, `prop`, status, theorem name.
   - `inventory/`, `bugs/`, `difftest/` (sbt), `reproducers/` (scala-cli), `review/`.
2. **Inventory.** Write a script that lists every public method, `IO` constructor, `runLoop` branch and law at v3.7.1 (use `scalex` on `~/Projects/cats-effect`). One row each, status `todo`. Scope: kernel, core `IO`/`IOFiber`/`SyncIO`, std. Runtime rows start as `excluded` with reason `deferred:` and a link to phase 9.
3. **Registry audit** (Lean meta program, run in CI): each registered theorem has type exactly `prop` or `¬prop`; each `modelled` inventory row is named by a registry entry; `#print axioms` gives only `propext`, `Classical.choice`, `Quot.sound`.
4. **CI:** add the registry audit, the inventory check, and later the difftest regression corpus and the reproducer job.
5. **Gate:** CI green; the audit rejects a planted wrong theorem type.

## Phase 2 — core model of `IOFiber`

1. **Syntax.** One inductive with the 26 `IO` constructors in tag order (25 tags 0–24 plus `EndFiber` = -1) (`IO.scala`). Internal tags (`UnmaskRunLoop`, `IOCont.Get`, `EndFiber`) included.
2. **User code as parameters.** `Delay`, `Map`, `FlatMap`, `OnCancel`, async registration and `Ref.modify` functions are values of a `UserFn` type. A `UserFn` can return, raise, read and write `Ref` cells, and complete a callback zero, one or two times. Never a total "always succeeds" function.
3. **Fiber state.** Mirror the `IOFiber` fields: `conts` stack, `objectState`, `finalizers`, `callbacks`, `masks : Nat`, `canceled`, `finalizing`, `outcome`, `suspended`, `resumeTag`.
4. **Second mask model.** A twin fiber state with fresh mask ids per `uncancelable` (as in the scaladoc and PureConc). Same step function shape; only the mask and `poll` branches differ. Difftest both; the escaped-`poll` question is the first comparison.
5. **Step function.** Mirror `runLoop` branch by branch, in the same order, with `path:line` citations. Mirror `shouldFinalize`, `prepareFiberForCancelation`, `succeeded`/`failed` continuation handling, `done`.
6. **Scheduler.** The global state is a fiber soup + `Ref`/`Deferred` cells + virtual clock. The run takes a choice list: which fiber steps next, and whether a pending cancel is observed now. The 512-step read barrier and auto-yield become scheduler choices.
7. **Fairness.** The fairness predicate from spike 0.4 on choice streams. Liveness properties quantify over fair schedules only; safety properties over all schedules.
8. **Concurrency constructors.** `Start`, `RacePair`, `Cede`, `Sleep`, `IOCont`/`Get` with the `ContState` three-way race (callback vs `get` vs cancel), external `cancel` and `join`.
9. **Primitives.** `Ref` and `IODeferred` mirrors.
10. **Run.** Fuel-bounded; "out of fuel" is a separate result. A bounded enumerator gives the set of outcomes over all schedules up to a preemption bound (dejafu style).
11. **Gate:** 30+ hand examples agree with the docs; a 2-fiber program is evaluated by `decide` in the kernel; inventory rows for constructors move to `modelled` only with a registry entry.

## Phase 3 — difftest harness (starts in parallel with 2.4)

1. **Program language.** One JSON AST for test programs, shared by Scala and Lean.
2. **Scala side** (`difftest/`, sbt, CE pinned to 3.7.1, and a second build against `series/3.x`): decode the AST, interpret into real `IO`, run under `TestControl` with a seed, print outcome + observable trace (finalizer order, `Ref` writes, callback calls) as JSON lines.
3. **Generator.** Type-directed and edge-heavy: nested `uncancelable`/`poll`, escaped `poll`, finalizers that raise, callbacks called twice or after cancel, cancel at every boundary, races, `Start` inside `uncancelable`. Measure rule coverage (which `runLoop` branches fire), not line coverage.
4. **Lean side** (`lean_exe cediff`): read cases, then either (a) compute the outcome set and check membership (refinement), or (b) replay the logged schedule and check equality — mode (b) only if spike 0.2 shows the schedule can be logged.
5. **Driver** (Python): run both sides, compare, shrink failures, sort mismatches into the triage bins of [Differential testing](differential-testing.md), save shrunk cases as a CI regression corpus.
6. **Real runtime pass.** Also run on the real `IORuntime` and check refinement only, to catch races `TestControl` hides.
7. **Gate:** 100% agreement on ≥50,000 cases over ≥3 seeds. Each mismatch fixed in the model, never by removing a generator case. Record each model bug found in the wiki.

## Phase 4 — kernel laws (model sanity check)

1. Mirror the derived combinators in `MonadCancel`, `GenSpawn`, `Async`, `Sync`, generic over `F` (operations as parameters, laws as hypotheses), and the `IO` overrides. These are twins.
2. State each law from the law files as outcome-set equivalence over all schedules.
3. Liveness: `join` of a finished fiber returns; `cancel` returns once finalizers finish (backpressure rule); `cede` lets other fibers run; programs without `never`/blocked `async` terminate under every fair schedule.
4. Prove the laws that hold. `onCancelAssociatesOverUncancelableBoundary` is a deliberate violation ([Semantics](../cats-effect/semantics.md)): settle it but mark it intended.
5. Twins: `IO` vs `SyncIO`; derived vs override; `IOFiber` mask counter vs spec mask ids (escaped `poll` question).
6. Smoke-test each statement with Plausible and the difftest before you try a proof.
7. **Gate:** every law row is proven or refuted and reviewed FAITHFUL.

## Phase 5 — calibration on known bugs

1. Mirror `syncStep` (#4687), `Resource.eval` (#4627), Concurrent `Queue.take` + `timeout` (#4571).
2. State the promised property for each, from its Scaladoc.
3. The model must refute each one. If it cannot, the model is too abstract: go back to phase 2 or 3.
4. Write each Scala reproducer; it must print `REPRODUCED <id>` on v3.7.1. Record the `series/3.x` result.
5. Full bug record YAML for each, with `duplicates` pointing to the known issue.
6. **Gate:** 3 refutations reproduced and reviewed. **User review here** (first gate after "start"): metrics, a sample of reviewed rows, and the 3 bug records.

## Phase 6 — derived combinators and `Resource`

1. Order: `bracket*`, `guarantee*`, `race`, `both`, `timeout*`, `memoize`, `parTraverseN`, then `Resource` (`allocated`, `use`, `eval`, `both`, `timeout`, `flatMap` finalizer order).
2. Properties: release runs exactly once when acquire completed; finalizers LIFO and masked; no leaked fiber after `race`/`both`/`timeout`; the four external-cancel rules.
3. **Gate:** rows reviewed FAITHFUL; refutations reproduced.

## Phase 7 — std structures

1. Order by bug density: `Queue` (both implementations, as twins) → `Semaphore` → `Mutex` → `CountDownLatch`, `CyclicBarrier` → `Supervisor` → `Dispatcher` → `Hotswap`, `AtomicCell`, `Dequeue`, `PQueue`, `MapRef`.
2. Properties: no lost element and no lost wakeup under any cancel interleaving; no deadlock; every waiter wakes under fair schedules when its condition holds (liveness); linearizability against a sequential spec; finalizers once; no leaked fiber.
3. The lock-free Async `Queue` is first modelled under sequential consistency. Record this as a model simplification.
4. **Gate:** rows reviewed FAITHFUL.

## Phase 8 — bug hunt (the goal)

1. For each modelled area, collect properties: twins first, then invariants, then Scaladoc sentences.
2. Search for counterexamples with the bounded schedule enumerator before you try a proof. Cheap search first, proof second.
3. Each counterexample: refutation theorem, reproducer on v3.7.1 and `series/3.x`, duplicate search, honest `likelihood` and `maybe_intended`. Never file outside this repository.
4. Each proven property: also test it against the real library.

## Cross-cutting work (every phase)

- **Review.** After each batch, a different agent reviews rows read-only with the MIRROR / PROPERTY / SETTLED rubric and the wrong-function test ([Agent workflow](agent-workflow.md)).
- **Parallel agents.** One module per agent in its own worktree; a merge gate reruns the build, audits, difftest corpus and reproducers.
- **Wiki.** Record findings the same day; lint at the end of each task.
- **Metrics** (report at each gate): reviewed FAITHFUL / in scope, difftest cases and seeds, properties proven / refuted / open, reproduced refutations, false-positive rate, cost.
- **Pre-push checks:** `lake build --wfail`, `check_forbidden.py`, `check_wiki.py`, `lake check`.

## Main risks

| Risk | Effect | Mitigation |
|---|---|---|
| Kernel evaluation too slow for counterexamples | Refutations cannot be checked without `native_decide` | Spike 0.3; small counterexamples; proof by lemmas |
| `TestControl` cannot replay a schedule | Only refinement mode; weaker difftest | Spike 0.2; refinement is still sound |
| Model too abstract | Hollow proofs, no bugs found | Calibration gate (phase 5) |
| Breadth-first drift | Thin rows fail review | Headline metric = reviewed rows only |
| Autonomous run to Phase 5 drifts | Wasted weeks before the user sees it | Weekly metrics note in the wiki; agents stop at any failed gate |
| Liveness proofs over infinite schedules are hard | Phases 2 and 4 take longer | Spike 0.4; fuel-existence statement shape; keep hard ones `open` |
| Lock-free code needs a memory model | Runtime bugs out of reach | Phase 9 is a separate decision |
| Build memory and time grow | Slow CI | `-M8000`, module split, heavy runs on a big machine |

## See Also

- [Lessons for Cats Effect in Lean](lessons-for-cats-effect.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Differential testing](differential-testing.md)
- [Modeling approaches](../semantics/modeling-approaches.md)
- [Bug history](../cats-effect/bug-history.md)
- [Source layout](../cats-effect/source-layout.md)
- [Lean v4.35.0 toolchain](../lean/toolchain-v4-35.md)

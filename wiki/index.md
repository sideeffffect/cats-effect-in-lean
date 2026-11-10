# Knowledge Base Index

## methodology

How this project works: synthesis, agent loop, difftest design. Start here.

| Article | Summary | Updated |
|---------|---------|---------|
| [Lessons for Cats Effect in Lean](methodology/lessons-for-cats-effect.md) | Top-level synthesis: what to copy, what is new for CE, order of work | 2026-11-10 |
| [Agent workflow and review protocol](methodology/agent-workflow.md) | Inventory → mirror → difftest → prove/refute → review; rubric; bug records; no upstream filing | 2026-11-10 |
| [Project plan](methodology/project-plan.md) | Step-by-step plan: phases 0–9, gates, risks, user decisions; started 2026-11-10 | 2026-11-10 |
| [Phase 5 gate report](methodology/phase5-gate-report.md) | Gate PASS (review batch 3), user-approved 2026-11-10: 9/9 FAITHFUL, 3 calibration bugs refuted + reproduced, CE-0004, metrics, caveats | 2026-11-10 |
| [Differential testing](methodology/differential-testing.md) | Lean-vs-CE difftest harness, generator, driver, results; v1 ops ≥ 65,960 agreeing cases each; preempt coverage via small runtime thresholds; triage bins | 2026-11-10 |
| [Difftest program format v0](methodology/difftest-program-format.md) | JSON AST v0 (values, ops → exact IO terms, user-fn table, trace events); Scala runner modes replay/testcontrol; commands, limits | 2026-11-10 |
| [Inventory](methodology/inventory.md) | inventory/inventory.csv: columns, scope, exclusion rules, how to regenerate, counts (3,255 rows) | 2026-11-10 |
| [Registry and audit](methodology/registry-and-audit.md) | Registry Entry fields; audit checks exact theorem type, axioms, module prefixes, bug record, inventory cross-check; self-test fixtures; CI | 2026-11-10 |

## cats-effect

Facts about the pinned Cats Effect version, its code, semantics and bugs.

| Article | Summary | Updated |
|---------|---------|---------|
| [Pinned version: v3.7.1](cats-effect/pinned-version.md) | v3.7.1 (2026-08-23, eb0cc25) is the latest stable; pinned | 2026-11-10 |
| [Source layout](cats-effect/source-layout.md) | kernel, laws, IO ADT, IOFiber, runtime, std, PureConc, TestControl | 2026-11-10 |
| [Semantics of CE3](cats-effect/semantics.md) | Cancellation, masking, finalizers, laws; IOFiber vs PureConc | 2026-11-10 |
| [Bug history](cats-effect/bug-history.md) | Bug classes, open bugs (status on series/3.x checked), recommended first targets | 2026-11-10 |
| [TestControl and schedule replay](cats-effect/testcontrol.md) | TestControl is seed-random only; a scripted EC in IORuntime replays and logs chosen schedules; difftest = replay first, refinement second | 2026-11-10 |
| [IO ADT and fiber state (model data)](cats-effect/io-adt-and-fiber-state.md) | 26 IO constructors in tag order, UserFn/UserEnv, IOFiber fields, conts/resume tags, ContState, counter vs fresh-id mask models, NonFatal facts | 2026-11-10 |
| [Run-loop model (single fiber)](cats-effect/runloop-model.md) | step mirrors IOFiber.runLoop for one fiber; result types; 34 examples by decide +kernel; escaped poll: counter = Canceled (matches CE 3.7.1), spec = Succeeded; escaped poll in a finalizer skips finalizers | 2026-11-10 |
| [Scheduler model (multi-fiber, replay)](cats-effect/scheduler-model.md) | Task-level replay scheduler: ready-list order, IOCont/Get/Cede/Start, _cancel/_join closures, callback race; 15 difftest cases agree with Scala | 2026-11-10 |
| [Kernel typeclasses model](cats-effect/kernel-typeclasses-model.md) | MonadCancel/GenSpawn ops over abstract F; default-body mirrors; 33 laws as Props with Eqv parameter; IO twin table; unregistered default-instance lemmas | 2026-11-10 |
| [SyncIO and syncStep model](cats-effect/syncio-and-syncstep-model.md) | SyncIO run loop and SyncStep.interpret (G = SyncIO) mirror; syncStepIdentitySyncIO refuted (CE-0001, reproducer case 4) | 2026-11-10 |
| [Resource model and CE-0002](cats-effect/resource-model.md) | Resource ADT + allocatedCase mirror (F = IO), closure-id codec; resourceEvalPreservesUncancelable refuted (CE-0002, reproducer case C) | 2026-11-10 |
| [guarantee and bracket model, CE-0005](cats-effect/bracket-model.md) | IO#guarantee/guaranteeCase/bracket*/IO.bracketFull + kernel twins mirror; UserEffect.report; difftest v2; bracketFull twin refuted (CE-0005), 4 open | 2026-11-10 |
| [Queue and timeout model](cats-effect/queue-model.md) | UnboundedAsyncQueue + IO#timeout/timeoutTo/never mirror; takeTimeoutNoLostElement refuted by the FIFO schedule (CE-0003) | 2026-11-10 |
| [race, both and fiber leaks](cats-effect/race-both-model.md) | Kernel-default mirror of race/raceOutcome/both/bothOutcome (no IO twin), leak observation liveRaceChildren, difftest v2 (≥50k per op), 5 open entries, smoke 0 violations | 2026-11-10 |

## semantics

Formal modeling approaches for effect systems and concurrency.

| Article | Summary | Updated |
|---------|---------|---------|
| [Modeling approaches for CE3 in Lean](semantics/modeling-approaches.md) | Small-step + scheduler recommended; ITrees, dejafu, Marlow 2001 compared | 2026-11-10 |
| [Fairness and liveness](semantics/fairness-and-liveness.md) | Schedule = Nat → Choice; Fair/Terminates definitions; CE 512/1024 thresholds; ranking, decide, lasso refutations | 2026-11-10 |
| [Outcome sets, Eqv and the IO laws](semantics/outcome-equivalence.md) | outcomes/Eqv over pick schedules (trace, refs, reports); bounded enumerator + soundness; IO ops without a typed instance; 2 IO laws proven, 2 open; auto-yield finding | 2026-11-10 |
| [Race no-leak invariant and frame lemmas](semantics/race-invariant.md) | Invariant design for the 5 open race entries (NL, S, F3, F4, P1/P2, H, C(r)); F1/F2 frame lemmas proven for all runs; law LHS 4,441 states | 2026-11-10 |

## lean

Lean 4 toolchain facts and proof hygiene.

| Article | Summary | Updated |
|---------|---------|---------|
| [Lean v4.35.0 toolchain](lean/toolchain-v4-35.md) | lake check (+ bwrap/AppArmor failure), vcgen, native_decide axioms, recursion styles | 2026-11-10 |
| [Proof hygiene and agent tooling](lean/proof-hygiene-and-agent-tooling.md) | Forbidden tactics, axiom audit, CI gates (incl. this repo's CI), lean-lsp-mcp, lean4-skills, Plausible | 2026-11-10 |
| [Kernel evaluation of the model](lean/kernel-evaluation.md) | Toy spike: decide +kernel for runs/witnesses (5k steps in 6 s), decide_cbv memoizes schedule enumeration; design rules | 2026-11-10 |

## precedents

Other projects that formalized real languages/systems, and the debate around them.

| Article | Summary | Updated |
|---------|---------|---------|
| [python-formalization](precedents/python-formalization.md) | CPython 3.15.2 in Lean by agents; 418 bugs; AGENTS.md + review prompt | 2026-11-10 |
| [julia-in-lean](precedents/julia-in-lean.md) | Julia Base in Lean by agents; 689 bug records; 77 merged PRs; hollow-proof lesson | 2026-11-10 |
| [Formalization precedents](precedents/formalization-precedents.md) | Cedar, K, JSCert, WasmCert, seL4, Csmith, Netsem, SibylFS and more | 2026-11-10 |
| [Community critique](precedents/community-critique.md) | Arguments for/against; fidelity, intent, hollow proofs, maintainer burden | 2026-11-10 |

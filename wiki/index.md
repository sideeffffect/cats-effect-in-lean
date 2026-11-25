# Knowledge Base Index

## methodology

How this project works: synthesis, agent loop, difftest design. Start here.

| Article | Summary | Updated |
|---------|---------|---------|
| [Lessons for Cats Effect in Lean](methodology/lessons-for-cats-effect.md) | Top-level synthesis: what to copy, what is new for CE, order of work | 2026-11-10 |
| [Agent workflow and review protocol](methodology/agent-workflow.md) | Inventory → mirror → difftest → prove/refute → review; rubric; bug records; no upstream filing | 2026-11-15 |
| [Project plan](methodology/project-plan.md) | Step-by-step plan: phases 0–9, gates, risks, user decisions; started 2026-11-10 | 2026-11-15 |
| [Phase 5 gate report](methodology/phase5-gate-report.md) | Gate PASS (review batch 3), user-approved 2026-11-10: 9/9 FAITHFUL, 3 calibration bugs refuted + reproduced, CE-0004, metrics, caveats | 2026-11-10 |
| [Phase 6 gate report](methodology/phase6-gate-report.md) | Draft, review batch 10: gate PASS with conditions; 25/25 Phase 6 entries FAITHFUL (1 proven, 3 refuted, 21 open); CE-0005, CE-0020, CE-0030 reproduced; difftest v2 counts; caveats | 2026-11-15 |
| [Phase 7 batch 7.1 gate report](methodology/phase7-batch1-gate-report.md) | Gate PASSED 2026-11-25 (review batch 15, conditions C2 and C3 closed); 35/35 entries FAITHFUL as statements (0 proven, 1 refuted, 34 open); all 5 batteries complete; CE-0060 reproduced; difftest counts | 2026-11-25 |
| [Differential testing](methodology/differential-testing.md) | Lean-vs-CE difftest harness, generator, driver, results; v1 ops ≥ 65,960 agreeing cases each; preempt coverage via small runtime thresholds; triage bins | 2026-11-10 |
| [Difftest program format v0](methodology/difftest-program-format.md) | JSON AST v0 (values, ops → exact IO terms, user-fn table, trace events); Scala runner modes replay/testcontrol; commands, limits | 2026-11-10 |
| [Inventory](methodology/inventory.md) | inventory/inventory.csv: columns, scope, exclusion rules, how to regenerate, counts (3,255 rows) | 2026-11-10 |
| [Registry and audit](methodology/registry-and-audit.md) | Registry Entry fields; audit checks exact theorem type, axioms, module prefixes, bug record, inventory cross-check; self-test fixtures; CI | 2026-11-15 |

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
| [Resource model and CE-0002](cats-effect/resource-model.md) | Resource ADT + allocatedCase mirror (F = IO), closure-id codec; resourceEvalPreservesUncancelable refuted (CE-0002, reproducer case C); use/both in ResourceUse | 2026-11-10 |
| [guarantee and bracket model, CE-0005](cats-effect/bracket-model.md) | IO#guarantee/guaranteeCase/bracket*/IO.bracketFull + kernel twins mirror; UserEffect.report; difftest v2; bracketFull twin refuted (CE-0005), 4 open | 2026-11-14 |
| [parTraverseN model](cats-effect/partraverse-model.md) | Kernel default parTraverseN with IO ops (no twin), HashSet order as input, difftest op, 8 open properties (closure references, harness counter) with witnesses and smoke; HashSet difftest by refinement; Scala infix-precedence gotcha | 2026-11-15 |
| [Queue and timeout model](cats-effect/queue-model.md) | UnboundedAsyncQueue + IO#timeout/timeoutTo/never mirror; takeTimeoutNoLostElement refuted by the FIFO schedule (CE-0003) | 2026-11-10 |
| [Queue families model (Phase 7)](cats-effect/queue-families-model.md) | Track Q: `Concurrent` (`BoundedQueue`, `DroppingQueue`, `CircularBufferQueue`, `Synchronous`) and `Async` (`BoundedAsyncQueue`, `DroppingAsyncQueue`, `UnboundedAsyncQueue`, sequential consistency) mirrors; queue object = `Val.fn`; difftest v2 `q*` ops; 11 open statements (noLoss, noDup, fifo, noDeadlock, takerLiveness per family; twinSeq) with witnesses, wrong functions, qsmoke 0 violations; review 12: `fifo` FAITHFUL, `Concurrent.takerLiveness` HOLLOW (join outcomes ignored) | 2026-11-15 |
| [memoize model and CE-0030](cats-effect/memoize-model.md) | IO#memoize = kernel GenConcurrent#memoize mirror (no twin); difftest ops memoize/memoGet; CE-0030 refuted (masked `canceled *> never` hangs a racing get), 2 open | 2026-11-15 |
| [Resource use, allocated, both, and CE-0020](cats-effect/resource-use-both-model.md) | fold/use/allocated/rel2/both mirror (`ResourceUse`), difftest v2 rUse/rAllocated/rBoth (≥51k each), CE-0020 refuted (both skips a release), 3 open; harness privacy by construction (`HarnessPrivacy`, decision 56), satisfiability witnesses; Lib.fields probe check (2 defects fixed); decision 58 harness (Val.fn, S1 gone, S2 clauses); review 9: R1 `REnv` index forgery (HOLLOW) | 2026-11-15 |
| [Semaphore and Mutex model, CE-0060](cats-effect/semaphore-mutex-model.md) | Phase 7 track S: `Semaphore` (lazy cancelation of PR #4648) and `Mutex` (`LockQueue` CLH lock) mirrors, difftest v2 (9 ops, ≥ 51k cases each), 7 open statements with witnesses and smoke, CE-0060 refuted (`count` counts canceled waiters); review 11b: CE-0060 FAITHFUL, both `noDeadlock` entries HOLLOW (fatal `Base.err`); review 12: fatal fixed, `Semaphore.noDeadlock` HOLLOW again (root `Errored` allowed) | 2026-11-15 |
| [race, both and fiber leaks](cats-effect/race-both-model.md) | Kernel-default mirror of race/raceOutcome/both/bothOutcome (no IO twin), leak observation liveRaceChildren, difftest v2 (≥50k per op), 5 open entries, smoke 0 violations | 2026-11-15 |
| [CountDownLatch and CyclicBarrier model](cats-effect/latch-barrier-model.md) | Phase 7 track L (decision 63 battery: all rows break a statement; companion claims awaitCompletes): std.CountDownLatch/CyclicBarrier mirrors (latch object = `Val.fn`), difftest ops cdlNew/cdlRelease/cdlAwait/cbNew/cbAwait (mutation check: 7/7 wrong variants killed), 7 open properties with kernel witnesses, wrong-function tests and smoke; the two cancel races (epoch check needed only for a waiter canceled while suspended); review 11b: 7/7 FAITHFUL as statements | 2026-11-15 |
| [Supervisor model](cats-effect/supervisor-model.md) | Phase 7 track V: `std.Supervisor` mirror (both state kinds, restart path), difftest `supUse`/`supervise`, 7 open statements with kernel witnesses and the decision 63 battery; codec-size lesson | 2026-11-25 |
| [Dispatcher model, CE-0090 and CE-0091](cats-effect/dispatcher-model.md) | Phase 7 track P7D: `std.Dispatcher` mirror on track V's Supervisor (parallel, sequential, await), difftest v2 (5 ops, ≥ 50,425 agreeing cases each over 3 seeds; 4 two-map harness-limit cases), 8 statements (2 refuted: CE-0090 lost submission during release, CE-0091 #3506 regression; 6 open), kernel runs in chunks, battery, twins, smoke | 2026-11-25 |

## semantics

Formal modeling approaches for effect systems and concurrency.

| Article | Summary | Updated |
|---------|---------|---------|
| [Modeling approaches for CE3 in Lean](semantics/modeling-approaches.md) | Small-step + scheduler recommended; ITrees, dejafu, Marlow 2001 compared | 2026-11-10 |
| [Fairness and liveness](semantics/fairness-and-liveness.md) | Schedule = Nat → Choice; Fair/Terminates definitions; CE 512/1024 thresholds; ranking, decide, lasso refutations | 2026-11-10 |
| [Outcome sets, Eqv and the IO laws](semantics/outcome-equivalence.md) | outcomes/Eqv over pick schedules (trace, refs, reports); bounded enumerator + soundness; IO ops without a typed instance; 2 IO laws proven, 2 open; auto-yield finding; decision 58 `Val.fn` and `WF.avail` | 2026-11-15 |
| [Race no-leak invariant and frame lemmas](semantics/race-invariant.md) | Invariant design for the 4 open race leak/winner entries (NL, S, F3, F4, P1/P2, H, C(r)); F1/F1b/F2 frame lemmas proven for all runs; law proven by certificate | 2026-11-10 |

## lean

Lean 4 toolchain facts and proof hygiene.

| Article | Summary | Updated |
|---------|---------|---------|
| [Lean v4.35.0 toolchain](lean/toolchain-v4-35.md) | lake check (+ bwrap/AppArmor failure), vcgen, native_decide axioms, recursion styles | 2026-11-10 |
| [Proof hygiene and agent tooling](lean/proof-hygiene-and-agent-tooling.md) | Forbidden tactics, axiom audit, CI gates (incl. this repo's CI), lean-lsp-mcp, lean4-skills, Plausible | 2026-11-10 |
| [Kernel evaluation of the model](lean/kernel-evaluation.md) | Toy spike: decide +kernel for runs/witnesses (5k steps in 6 s), decide_cbv memoizes schedule enumeration; design rules | 2026-11-10 |
| [Certificate checks of closed state sets](lean/certificate-checker.md) | CertP: untrusted BFS generator + linear kernel check (tree replay, edge indices), chunking (EdgesUpTo), cost per state; proves uncancelableRaceNotInherited | 2026-11-10 |

## precedents

Other projects that formalized real languages/systems, and the debate around them.

| Article | Summary | Updated |
|---------|---------|---------|
| [python-formalization](precedents/python-formalization.md) | CPython 3.15.2 in Lean by agents; 418 bugs; AGENTS.md + review prompt | 2026-11-10 |
| [julia-in-lean](precedents/julia-in-lean.md) | Julia Base in Lean by agents; 689 bug records; 77 merged PRs; hollow-proof lesson | 2026-11-10 |
| [Formalization precedents](precedents/formalization-precedents.md) | Cedar, K, JSCert, WasmCert, seL4, Csmith, Netsem, SibylFS and more | 2026-11-10 |
| [Community critique](precedents/community-critique.md) | Arguments for/against; fidelity, intent, hollow proofs, maintainer burden | 2026-11-10 |

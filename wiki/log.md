# Wiki Log

## [2026-11-10] init | Wiki initialized

## [2026-11-10] ingest | python-formalization

## [2026-11-10] ingest | julia-in-lean

## [2026-11-10] ingest | Community critique of agent-driven formalization

## [2026-11-10] ingest | Formalization precedents (pre-AI era and industry)

## [2026-11-10] ingest | Pinned Cats Effect version: v3.7.1
- Updated: Cats Effect v3.7.1 source layout
- Updated: Cats Effect bug history and target areas

## [2026-11-10] ingest | Semantics of Cats Effect 3
- Updated: Modeling approaches for CE3 in Lean

## [2026-11-10] ingest | Lean v4.35.0 toolchain facts
- Updated: Proof hygiene and agent tooling for Lean

## [2026-11-10] ingest | Lessons for Cats Effect in Lean
- Updated: Agent workflow and review protocol
- Updated: Differential testing of the Lean model against Cats Effect

## [2026-11-10] lint | 2 issues found, 2 auto-fixed
- Fixed: two raw duplicates (Cedar DRT copy, AWS Lean blog copy) were not referenced; added to Formalization precedents Raw field.
- Report: duplicate raw copies exist across topics (CE3 proposal #634 in raw/cats-effect and raw/effect-semantics; python AGENTS.md in raw/python-formalization and raw/lean-tooling). Kept, since raw/ is immutable.
- Report: open contradiction to watch — Brooker & Desai 2025 says Cedar is "built in Dafny"; the Lean port (RFC 0032, 2023) supersedes it.

## [2026-11-10] ingest | Agent workflow and review protocol (user decision: no bugs outside this repo)
- Updated: Lessons for Cats Effect in Lean
- Updated: Community critique of agent-driven formalization

## [2026-11-10] ingest | Lean v4.35.0 toolchain facts (lake check bwrap/AppArmor diagnosis)

## [2026-11-10] lint | 0 issues found, 0 auto-fixed

## [2026-11-10] ingest | Lean v4.35.0 toolchain facts (bwrap AppArmor setup script)

## [2026-11-10] ingest | Lean v4.35.0 toolchain facts (lake check works after AppArmor fix)

## [2026-11-10] ingest | Proof hygiene and agent tooling for Lean (this repo's CI setup)

## [2026-11-10] lint | 0 issues found, 0 auto-fixed

## [2026-11-10] ingest | Proof hygiene and agent tooling for Lean (CI first runs, module-name gotcha)

## [2026-11-10] ingest | Project plan (draft)
- Created: Project plan
- Updated: Lessons for Cats Effect in Lean

## [2026-11-10] lint | 0 issues found, 0 auto-fixed

## [2026-11-10] ingest | Project plan (user decisions: Val, safety+liveness, both mask models, autonomous to Phase 5)
- Updated: Project plan

## [2026-11-10] lint | 0 issues found, 0 auto-fixed

## [2026-11-10] ingest | Start signal (formalization started)
- Updated: Project plan

## [2026-11-10] ingest | Phase 0 spikes and Phase 1 inventory (5 parallel agents)
- Updated: Bug history (status of #4687, #4627, #4571, #4483, #4697)
- Created: TestControl and schedule replay; Updated: Differential testing, Source layout
- Created: Kernel evaluation of the model; Updated: Lean v4.35.0 toolchain, Modeling approaches
- Created: Fairness and liveness; Updated: Modeling approaches
- Created: Inventory

## [2026-11-10] ingest | Phase 0 decisions
- Updated: Project plan, Inventory (csv gitignore gotcha)

## [2026-11-10] ingest | Phase 1 registry/audit, Phase 2 data model, Phase 3 Scala runner (3 parallel agents)
- Created: Registry and audit; Updated: Agent workflow, Inventory
- Created: IO ADT and fiber state; Updated: Source layout, Project plan (26 constructors, not 25)
- Created: Difftest program format v0; Updated: Differential testing

## [2026-11-10] ingest | Phase 2 single-fiber run loop; Phase 3 Lean decoder and CI (2 parallel agents)
- Created: Run-loop model (single fiber); Updated: IO ADT and fiber state
- Updated: Difftest program format v0 (Lean side), Differential testing
- Updated: Project plan (status, decisions 11–13)

## [2026-11-10] ingest | Scheduler model, difftest generator/driver, kernel typeclasses (3 parallel agents)
- Created: Scheduler model; Updated: Run-loop model
- Updated: Differential testing, Difftest program format v0 (generator, driver, corpus)
- Created: Kernel typeclasses model
- Updated: Project plan (status, decisions 14–17)

## [2026-11-10] ingest | First difftest agreement, calibration reproducers, generator coverage (3 parallel agents)
- Updated: Differential testing, Scheduler model, Difftest program format v0
- Updated: Bug history (calibration section, CE-0001..0003)
- Updated: Project plan (status, decisions 18–21)

## [2026-11-10] ingest | CI fix: sbt class path cache in difftest/run.sh
- Updated: Differential testing

## [2026-11-10] ingest | RacePair/Sleep, enumerator + first IO laws, SyncIO/syncStep (3 parallel agents)
- Updated: Scheduler model, Differential testing, Difftest program format v0
- Created: Outcome sets, Eqv and the IO laws; Updated: Kernel typeclasses model
- Created: SyncIO and syncStep model; Updated: Bug history (CE-0001 refuted in Lean)
- Updated: Project plan (status, decisions 22–25)

## [2026-11-10] ingest | Review batch 1; Resource (CE-0002) and Queue/timeout (CE-0003) refuted in Lean
- Updated: Agent workflow (review log)
- Created: Resource model and CE-0002; Created: Queue and timeout model
- Updated: Bug history (all 3 calibration bugs refuted in Lean)
- Updated: Project plan (status, decisions 26–31)

## [2026-11-10] ingest | Review-1 fixes, difftest v1, idpoll model bug fix
- Updated: Outcome sets and Eqv (WellFormed), SyncIO and syncStep model, Resource model, Queue model, Registry and audit
- Updated: Difftest program format (v1), Differential testing (status, idpoll)
- Updated: Project plan (status, decisions 32–34)

## [2026-11-10] ingest | Review batch 2 (Phase 5 gate failed); decisions 35-39
- Updated: Agent workflow (review log, fixed-twin rule), Project plan

## [2026-11-10] ingest | Review-2 fixes: EqvP, fixed twins, opaque polls, CE-0004
- Updated: Outcome sets and Eqv (EqvP, WellFormed opaque polls), Resource model, SyncIO and syncStep model, Queue model, Bug history (CE-0004)
- Updated: Project plan (decisions 40–43)

## [2026-11-10] ingest | Review batch 3 (gate PASS); CI memory split; Phase 5 gate report
- Created: Phase 5 gate report
- Updated: Agent workflow (review log), Project plan (status, decisions 44–46)

## [2026-11-10] ingest | User answers Q1–Q3
- Updated: Project plan, Inventory (out-of-scope transformers, regeneration hazard), Proof hygiene (sorryAx), Outcome sets and Eqv (law context)

## [2026-11-10] ingest | User approves the Phase 5 gate
- Updated: Phase 5 gate report (approved), Project plan (status: Phase 6 next)

## [2026-11-10] ingest | Phase 6 start: batches and decisions 47-52
- Updated: Project plan (status)

## [2026-11-10] ingest | Phase 6 track R: race, both, leak observation, difftest v2
- Created: race, both and fiber leaks
- Updated: Difftest program format (format v2), Kernel typeclasses model (no twin), Queue and timeout model, Outcome sets (See Also), index

## [2026-11-10] ingest | Track D: difftest depth, timeoutTo mirror, preempt coverage
- Raw: raw/project-decisions/2026-11-10-difftest-depth-track-d-notes.md
- Updated: Differential testing (format-v1 depth table, preempt coverage, CI), Difftest program format (`runtime` field, `timeoutTo` mirrored, UserError 999998 code, idpoll status), Outcome sets and Eqv (preempt vs auto-yield difftest), Phase 5 gate report (caveats 3 and 4 status)

## [2026-11-10] ingest | Phase 6 track G: guarantee, bracket*, CE-0005
- Created: guarantee and bracket model, CE-0005
- Updated: Difftest program format (format v2 ops, failure text of UserError 999998), Resource model (IO#guarantee now mirrored), Kernel typeclasses model (twin results), Bug history (CE-0005)
- Raw: raw/cats-effect/2026-11-10-track-g-bracket-notes.md

## [2026-11-10] ingest | Track G merged with tracks R and D
- Updated: guarantee and bracket model (merged difftest counts, weights, TwinChecks), Difftest program format (one format v2 section; 999998 fix of track D kept, track G Scala text fix dropped)

## [2026-11-10] ingest | Track P: race no-leak invariant design, frame lemmas F1/F2
- Raw: raw/cats-effect/2026-11-10-race-invariant-track-p-notes.md
- Created: Race no-leak invariant and frame lemmas
- Updated: race, both and fiber leaks (why open, 4,441 states), Lean v4.35.0 toolchain (tactic gotchas), Outcome sets (See Also), index

## [2026-11-10] ingest | Phase 6 track M: memoize, CE-0030
- Created: memoize model and CE-0030
- Updated: Bug history (CE-0030, memoize issue history), Difftest program format (ops `memoize`, `memoGet`; `Deferred` and memo handle renumbering)
- Raw: raw/cats-effect/2026-11-10-memoize-track-m-notes.md

## [2026-11-10] ingest | Phase 6 merge notes (orchestration)
- Updated: Agent workflow (orchestration)
## [2026-11-10] ingest | Review batch 4 (13 Phase 6 entries; 2 HOLLOW)
- Updated: Agent workflow (review log: CE-0030 and CE-0005 FAITHFUL; bracket.releaseOnce and guarantee.finalizerOnce vacuous; satisfiability-witness check)
- Raw: raw/project-decisions/2026-11-10-review-batch-4-notes.md

## [2026-11-10] ingest | Decisions 53-54 (satisfiability witness, harness-only markers)
- Updated: Agent workflow



## [2026-11-10] ingest | Track Res: Resource use, allocated, both; CE-0020
- New: Resource use, allocated, both, and CE-0020 (cats-effect/resource-use-both-model.md)
- Updated: Resource model (limits), guarantee and bracket model (MarkersOnly caveat), race and both model (See Also), Bug history (CE-0020), Difftest program format (track Res ops), index
- Raw: raw/cats-effect/2026-11-10-track-res-resource-notes.md

## [2026-11-10] ingest | Track Res merged with track M
- Updated: Resource use, allocated, both (generator weights after the merge)
- Raw: raw/cats-effect/2026-11-10-track-res-merge-m-notes.md
## [2026-11-10] ingest | Phase 6 merge notes (orchestration)
- Updated: Agent workflow (orchestration)
## [2026-11-10] ingest | Review batch 4 (13 Phase 6 entries; 2 HOLLOW)
- Updated: Agent workflow (review log: CE-0030 and CE-0005 FAITHFUL; bracket.releaseOnce and guarantee.finalizerOnce vacuous; satisfiability-witness check)
- Raw: raw/project-decisions/2026-11-10-review-batch-4-notes.md

## [2026-11-10] ingest | Decisions 53-54 (satisfiability witness, harness-only markers)
- Updated: Agent workflow

## [2026-11-10] ingest | Review batch 5 (4 track Res entries; 3 HOLLOW)
- Updated: Agent workflow (review log: CE-0020 HOLLOW as registered, bug real; use.releaseOnce and flatMap.releaseOrder HOLLOW; eval.preservesCancelable FAITHFUL; UserMarkersOnly forgeable through library closures)
- Raw: raw/project-decisions/2026-11-10-review-batch-5-notes.md

## [2026-11-10] ingest | Track R witnesses (decision 53)
- Updated: race, both and fiber leaks (witnesses, decision 54 check, citation fix)

## [2026-11-10] ingest | Reviewer evidence rule
- Updated: Agent workflow

## [2026-11-10] update | Track M follow-up: decisions 53-54, CE-0030 twin family
- Updated: memoize model (satisfiability witnesses, non-forgeable observations, fixed twin on 7 fa)
- Raw: raw/cats-effect/2026-11-10-memoize-track-m-followup-notes.md

## [2026-11-10] ingest | Track Res: review batch 5 fixes (harness names, witnesses)
- Updated: Resource use, allocated, both (harness, files, properties, inventory), guarantee and bracket model (caveat points to HarnessNames), index
- Raw: raw/cats-effect/2026-11-10-track-res-review5-fix-notes.md

## [2026-11-10] ingest | Track G review fixes (review batch 4, decisions 53-54)
- Updated: guarantee and bracket model (restated invariants with harness markers, satisfiability witnesses, smoke with hypotheses), race and both model (GenSpawnLaws citation :146-147)

## [2026-11-10] ingest | Track P round 2: certificate checker, law uncancelableRaceNotInherited proven, F1b
- Raw: raw/lean-tooling/2026-11-10-certificate-checker-track-p-notes.md
- Created: Certificate checks of closed state sets
- Updated: Race no-leak invariant (F1b, law proven), race, both and fiber leaks, Outcome sets (large sets), Kernel evaluation (See Also), index

## [2026-11-10] ingest | Decision 55: heavy proofs lib, heavy registry, heavy CI job
- Raw: raw/project-decisions/2026-11-10-decision-55-heavy-proofs.md
- Updated: Registry and audit (heavy proofs section, self-test), Certificate checks (CI layout)

## [2026-11-14] ingest | Review batch 6 (re-review of 5 track G/Res entries; 5 HOLLOW)
- Updated: Agent workflow (review log, satisfiable-hypotheses note), guarantee and bracket model, Resource use, allocated, both, index
- Raw: raw/project-decisions/2026-11-14-review-batch-6-notes.md

## [2026-11-14] ingest | Decision 56: harness privacy by construction or proof
- Updated: Agent workflow (harness privacy section)
- Raw: raw/project-decisions/2026-11-14-decision-56-harness-privacy.md

## [2026-11-14] ingest | Batch 6.3: parTraverseN
- Created: parTraverseN model
- Updated: Difftest program format (op `parTraverseN`), index
- Raw: raw/cats-effect/2026-11-14-partraverse-notes.md

## [2026-11-14] ingest | Review batch 7: parTraverseN and heavy-proof CI split
- Updated: Agent workflow (review log), Registry and audit (CI split gaps), parTraverseN model (review result), index
- Raw: raw/project-decisions/2026-11-14-review-batch-7-notes.md

## [2026-11-14] update | Review 7: parTraverseN fixes
- Updated: parTraverseN model (HashSet order as input `ho`, no `as.length ≤ 4`, statements 5-7 with a behaviour harness, resultOrder waits for decision 56), Difftest program format, index
- Raw: raw/cats-effect/2026-11-14-partraverse-review7.md
- Smoke `lake exe ptsmoke 100`: 55,980 stopped runs, 0 violations; behaviour tables 120/84/63; all 8 wrong functions break their claim (1000 permits: 72 and 26 runs of 100)

## [2026-11-14] ingest | Decision 57: heavy-proofs required, split into parallel jobs (user answer Q4)
- Updated: Registry and audit (heavy proofs section)
- Raw: raw/project-decisions/2026-11-14-decision-57-required-heavy-checks.md

## [2026-11-14] ingest | Track Res: harness privacy by construction (decision 56)
- Updated: Resource use, allocated, both (harness, files, inventory), guarantee and bracket model (deep captured), Outcome sets (WellFormed Lib), Agent workflow (implementation of decision 56), index
- Raw: raw/cats-effect/2026-11-14-harness-privacy-notes.md

## [2026-11-14] ingest | Track Res: review batch 7 defect D regression (parTraverseN)
- Updated: raw harness privacy note (parTraverseN user function as number field; deep Lib rejects it)
- Raw: raw/cats-effect/2026-11-14-harness-privacy-notes.md

## [2026-11-14] ingest | Track Res: audit check lib-fields, named id-free libraries
- Updated: Registry and audit (check 9 lib-fields), Outcome sets (Lib.idFree), raw harness privacy note (follow-up)
- Raw: raw/cats-effect/2026-11-14-harness-privacy-notes.md

## [2026-11-14] update | parTraverseN: deep Lib and statement 8
- Updated: parTraverseN model (ptLibDeep with ParTraverse.fnFields incl. srcAction codes; defect D closed; statement 8 atMostN with HarnessPrivacy; witness and kernel-checked wrong function), index
- Raw: raw/cats-effect/2026-11-14-partraverse-deep-lib.md

## [2026-11-14] ingest | Review batch 7 fixes for decision 55 (sandbox, derived lists, export scope)
- Raw: raw/project-decisions/2026-11-10-decision-55-heavy-proofs.md (section "Review batch 7 fixes")
- Updated: Registry and audit (heavy job steps, export scope, leanexport gotcha)

## [2026-11-14] ingest | Decision 57 implementation: heavy CI matrix, aggregate heavy-proofs, paranoid by kernel
- Raw: raw/project-decisions/2026-11-14-decision-57-implementation-track-p.md
- Updated: Registry and audit (heavy CI jobs, paranoid matrix)

## [2026-11-14] ingest | Track Res: Lib.fields probe check
- Updated: Resource use/both (probe check, 2 defects fixed), Outcome sets (Lib fields check), index
- Raw: raw/cats-effect/2026-11-14-lib-fields-probe-notes.md


## [2026-11-15] update | parTraverseN: decision 58 closure references, HashSet difftest
- Updated: parTraverseN model (Val.fn fields, TL.start root, statement 8 without UserPrivate, F2/F3 closed, ParTraversePrivacy), Difftest program format (alternatives for the HashSet branch), index
- Raw: raw/cats-effect/2026-11-15-partraverse-decision58.md

## [2026-11-15] ingest | Track Res: decision 58 core (Val.fn closure references)
- Updated: Outcome sets (decision 58 rule), Resource use/both (harness, Private = S2), Bracket model (F1), Registry and audit (check 9 removed), Agent workflow
- Raw: raw/cats-effect/2026-11-15-decision-58-core-notes.md

## [2026-11-15] review | Review batch 8: harness privacy, parTraverseN, heavy CI matrix
- Updated: Agent workflow (review log, harness privacy finding), index
- Raw: raw/project-decisions/2026-11-15-review-batch-8-notes.md
- Review: review/2026-11-15-review-batch-8.md

## [2026-11-15] ingest | Decision 58: separate closure references (user answer)
- Updated: Agent workflow (closure references section)
- Raw: raw/project-decisions/2026-11-15-decision-58-closure-refs.md
- Difftest after decision 58 (generator with 5-input option): `opcount.py --seeds 51 52 --n 30000 --ops parTraverseN --boost tpl_parTraverse=8 tpl_parTraverseCancel=8`: 60,000 cases, all agree; 34,924 use `parTraverseN` (17,465 / 17,459 per seed). Fixed `hashcases/partraverse_hash.jsonl`: 32 agree (3 runs).

## [2026-11-15] review | Review batch 9: decision 58 core, Bracket, Resource, parTraverseN
- Updated: Agent workflow (review log, closure references), Resource use/both (batch 9 finding R1), index
- Raw: raw/project-decisions/2026-11-15-review-batch-9-notes.md
- Review: review/2026-11-15-review-batch-9.md

## [2026-11-15] ingest | Track Res: decision 58 core (Val.fn closure references)
- Updated: Outcome sets (decision 58 rule), Resource use/both (harness, Private = S2), Bracket model (F1), Registry and audit (check 9 removed), Agent workflow
- Raw: raw/cats-effect/2026-11-15-decision-58-core-notes.md

## [2026-11-15] ingest | Heavy CI fixes after run 43651882144 and review batch 8
- Raw: raw/project-decisions/2026-11-14-decision-57-implementation-track-p.md (section "Fixes after CI run 43651882144")
- Updated: Registry and audit (heavy CI fixes)

## [2026-11-15] ingest | Twin checks as a parallel matrix (twin-checks)
- Raw: raw/project-decisions/2026-11-14-decision-57-implementation-track-p.md (section "Twin checks as a matrix")
- Updated: Registry and audit (twin layout)

## [2026-11-15] update | Twin matrix: combining-module rule, real-runner timings
- Raw: raw/project-decisions/2026-11-14-decision-57-implementation-track-p.md (twin section: combining modules, CI run 43682566345, lean job without cache, paranoid all green)
- Updated: Registry and audit (twin layout, critical path)

## [2026-11-15] ingest | Track Res: review batch 9 R1 (REnv table references), wrong-function tests, W1
- Updated: Resource use/both, Outcome sets
- Raw: raw/cats-effect/2026-11-15-review9-r1-notes.md

## [2026-11-15] update | Race and Memoize source codes as references
- Updated: race-both model, memoize model (decision 58 source references; regressions), registry notes
- Raw: raw/cats-effect/2026-11-15-race-memoize-source-refs.md

## [2026-11-15] ingest | Branch protection on main (decision 57 step 4)
- Updated: Registry and audit (required checks)
- Raw: raw/project-decisions/2026-11-15-branch-protection-set.md
- Memory (RSS sampled every 2 s, local): MemoizeFixedParts max 5.50 GiB (FamFixedCedeCanceled2A); RaceLawChunks4 8.29 GiB after the change and 8.30 GiB with the old Race.lean (unchanged by this change); ResourceEvalFixedParts/Fixed_childJoin 8.40 GiB (not touched here). RSS includes mapped .olean files.

## [2026-11-15] update | Phase 6 gate: reproducers re-run
- CE-0005, CE-0020, CE-0030: reproducers re-run on v3.7.1 and series/3.x (de84c01f76b2, head unchanged since 2026-09-28): last line REPRODUCED on both; fixed copies of CE-0020/CE-0030 do not reproduce (0 seeds, 0/200). Bug records: output and duplicate queries (no new upstream issue or PR).

## [2026-11-15] review | Review batch 10: R1 fix, Race/Memoize source references, Phase 6 gate
- Created: Phase 6 gate report (draft; gate PASS with conditions)
- Updated: Agent workflow (review log), Project plan (Phase 6 gate line), index
- Raw: raw/project-decisions/2026-11-15-review-batch-10-notes.md
- Review: review/2026-11-15-review-batch-10.md

## [2026-11-15] update | Review batch 10 low items (D1, D3, D4)
- D1: Memoize registry notes, Props doc and memoize model: user code can run fa again through its own cell (source `.ref k`), as Scala can by recursion; no claim breaks (the counter is cell 0, never given to user code).
- D3: CE-0005 and CE-0030 status comments name the review verdicts (batch 4; batch 8 witness check; batch 10). Stale memoLib doc fixed.
- D4: inventory rows kernel.Resource.both, use, fold are `modelled` through the refuted CE-0020 entry kernel.Resource.both.releaseOnce (FAITHFUL, batch 10).

## [2026-11-15] ingest | Phase 6 gate passed; Phase 7 starts
- Updated: Phase 6 gate report (conditions met), Project plan (Phase 6 status), AGENTS.md current phase
- Raw: raw/project-decisions/2026-11-15-phase6-gate-passed.md

## [2026-11-15] ingest | Phase 7 start: tracks Q, S, L (decisions 59-62)
- Updated: Project plan (Phase 7 status)
- Raw: raw/project-decisions/2026-11-15-phase7-start.md

## [2026-11-15] ingest | Phase 7 track Q: Queue families mirror, difftest, statements
- Created: Queue families model (cats-effect/queue-families-model.md)
- Updated: Difftest program format (format v2 track Q ops), Differential testing (track Q section), Queue and timeout model (See Also), index
- Raw: raw/cats-effect/2026-11-15-queue-track-q-notes.md, raw/cats-effect/2026-11-15-queue-track-q-results.md

## [2026-11-15] ingest | Phase 7 track S: Semaphore and Mutex mirrors, difftest, 8 statements, CE-0060
- Created: Semaphore and Mutex model (cats-effect/semaphore-mutex-model.md)
- Updated: Difftest program format (track S ops), Bug history (CE-0060), parTraverseN model (See Also; `rankOrder` gap), index
- Raw: raw/cats-effect/2026-11-15-semaphore-mutex-track-s-notes.md

## [2026-11-15] ingest | Track L: CountDownLatch and CyclicBarrier (Phase 7)
- Created: CountDownLatch and CyclicBarrier model (cats-effect/latch-barrier-model.md)
- Updated: Differential testing (format v2 ops of track L, mutation check)
- Raw: raw/cats-effect/2026-11-15-track-l-latch-barrier-notes.md

## [2026-11-15] review | Review batch 11a: track Q (Queue)
- Created: review/2026-11-15-review-batch-11a.md
- Updated: Agent workflow and review protocol (review log, raw link)
- Raw: raw/project-decisions/2026-11-15-review-batch-11a-notes.md

## [2026-11-15] lint | Review batch 11b: Phase 7 tracks S and L
- 15 entries. HOLLOW: `std.Semaphore.noDeadlock`, `std.Mutex.lock.noDeadlock` (a fatal `Base.err` stops the run with `Summary.fatal`: false for every implementation). FAITHFUL: CE-0060 `std.Semaphore.count.atRest`; as statements the other 5 track S and all 7 track L entries.
- Updated: Agent workflow (review log), Semaphore and Mutex model (review result), CountDownLatch and CyclicBarrier model (review result), index
- Raw: raw/project-decisions/2026-11-15-review-batch-11b-notes.md
- Review: review/2026-11-15-review-batch-11b.md

## [2026-11-15] update | parTraverseN difftest: rankOrder fix (track S case g61-9094)
- Updated: parTraverseN model (HashSet ghost list `all`, order input `ho all xs`), Difftest program format (rankOrder by index in `all`)
- Raw: raw/cats-effect/2026-11-15-partraverse-rankorder-fix.md
- Hash cases (33, with `pth-regress-g61-9094`): agree in 3 runs. `opcount.py --seeds 61 62 63 --n 20000 --boost tpl_sem=20 tpl_mutex=0`: 60,000 cases, all agree (g61-9094 included); parTraverseN 4,240, semNew 54,499, semAcquireN 29,725, semReleaseN 42,346, semPermit 37,377.

## [2026-11-15] ingest | Track Q: fixes after review batch 11a
- Updated: Queue families model (fifo per remover, takerLiveness QuietBlock, D1-D5, merged-generator difftest)
- Raw: raw/cats-effect/2026-11-15-queue-review11a-fixes.md

## [2026-11-15] update | Track S: review batch 11b fixes (H1, W1, L2, L4)
- Updated: Semaphore and Mutex model (noDeadlock statements restated: not blocked + join records; W1 wrong function; twin docstring; citation)
- Raw: raw/cats-effect/2026-11-15-semaphore-mutex-review11b-fixes.md

## [2026-11-15] review | Review batch 12: re-review of the 11a/11b fixes and the parTraverseN rankOrder change
- Created: review/2026-11-15-review-batch-12.md
- Updated: Agent workflow and review protocol (review log, rule on join outcomes and "not blocked"); Queue families model; Semaphore and Mutex model; parTraverseN model
- Raw: raw/project-decisions/2026-11-15-review-batch-12-notes.md
- Result: 24 of 26 Phase 7 entries FAITHFUL; HOLLOW: std.Queue.Concurrent.takerLiveness (H3), std.Semaphore.noDeadlock (H2); 8 parTraverseN statements stay FAITHFUL

## [2026-11-15] ingest | Decision 63: wrong-function battery per structure
- Updated: Agent workflow (wrong-function battery section)
- Raw: raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md

## [2026-11-15] update | parTraverseN boosted difftest on the new model
- Seeds 81-83 (30,000 each, parTraverseN boosted): 90,000 cases, all agree; 52,428 parTraverseN. The 2 unsupported cases of drive check are the old testcontrol cases two-fibers-tc-seed1/2 (decision 15), not new.
- Raw: raw/cats-effect/2026-11-15-partraverse-boosted-difftest.md

## [2026-11-15] update | Track L: decision 63 battery
- Updated: CountDownLatch and CyclicBarrier model (battery table, companion claims, harness guard)
- Raw: raw/cats-effect/2026-11-15-track-l-decision63-battery.md

## [2026-11-15] update | Track S: review batch 12 (H2, W2) and the decision-63 battery
- Updated: Semaphore and Mutex model (noDeadlock: Succeeded or fatal; battery table, 38 kernel rows)
- Raw: raw/cats-effect/2026-11-15-semaphore-mutex-review12-battery.md

## [2026-11-15] ingest | Track Q: review batch 12 H3 fix, SeqSpec, decision 63 battery
- Updated: Queue families model (join outcomes in TakerLiveness, SeqSpec entries, battery, FailureSignal rows)
- Raw: raw/cats-effect/2026-11-15-queue-review12-battery.md

## [2026-11-15] ingest | Track Q: Synchronous tryTake handoff (decision 63 gap closed)
- Updated: Queue families model (statement 8, battery table complete)
- Raw: raw/cats-effect/2026-11-15-queue-sync-trytake-handoff.md

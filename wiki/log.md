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

## [2026-11-10] ingest | Track P round 2: certificate checker, law uncancelableRaceNotInherited proven, F1b
- Raw: raw/lean-tooling/2026-11-10-certificate-checker-track-p-notes.md
- Created: Certificate checks of closed state sets
- Updated: Race no-leak invariant (F1b, law proven), race, both and fiber leaks, Outcome sets (large sets), Kernel evaluation (See Also), index

## [2026-11-10] ingest | Decision 55: heavy proofs lib, heavy registry, heavy CI job
- Raw: raw/project-decisions/2026-11-10-decision-55-heavy-proofs.md
- Updated: Registry and audit (heavy proofs section, self-test), Certificate checks (CI layout)

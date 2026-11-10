# Lessons for Cats Effect in Lean

> Sources: synthesis of all research ingested on 2026-11-10 (python-formalization, julia-in-lean, community critique, formalization precedents, CE3 source and bug history, effect semantics, Lean tooling)
> Raw: [CE bug history notes](../../raw/cats-effect/2026-11-10-ce-bug-history-notes.md); [Effect-semantics modeling notes](../../raw/effect-semantics/2026-11-10-findings-effect-semantics-modeling-notes.md); [python layout + metrics note](../../raw/python-formalization/repo-layout-and-metrics-note.md); [julia repo survey note](../../raw/julia-formalization/2026-11-10-julia-in-lean-repo-survey-note.md)

## Overview

The top-level synthesis. Read this first before planning formalization work. Confidence in the overall plan: 0.75 — the precedents are mostly sequential code, and CE is about concurrency.

## What to copy

1. **Pin one version** (CE v3.7.1) and cite `path:line` at that tag.
2. **Inventory first**: one row per method/constructor/law in kernel, core IO, std; status `todo | modelled | excluded`. Progress = reviewed-FAITHFUL rows only.
3. **Mirror the implementation** (IOFiber run loop, std structures), not the docs. Bugs live where code and docs disagree.
4. **Difftest before properties**; mismatch = model bug until shown otherwise.
5. **Prove or refute; never weaken.** Refutation needs a Scala reproducer printing `REPRODUCED <id>` on v3.7.1, also checked on `series/3.x`.
6. **Independent read-only review** with MIRROR/PROPERTY/SETTLED + wrong-function test.
7. **Mechanical gates**: forbidden tactics/axioms grep, exact `prop`/`¬prop` audit, axiom allowlist, CI.
8. **Fewer, deeper properties.** Breadth-first failed in both projects.
9. **No upstream filing** (user decision, 2026-11-10): never open bugs, PRs or comments in any repository other than this one. Bug records stay in this repo.

## What is new for CE (no precedent covers it fully)

- **Concurrency**: properties quantify over schedules; equivalence is outcome-set equivalence; difftest by refinement or logged schedules (Netsem/SibylFS, dejafu).
- **User code is fallible and re-entrant**: thunks, finalizers, `async` callbacks, `Ref.modify` functions can throw, suspend, run twice, race with cancel. This mirrors CPython's richest bug class (re-entrant callbacks).
- **Generic over `F[_]`**: derived combinators in typeclasses need the model of the typeclass operations as parameters plus law hypotheses; `IO` overrides need their own mirror. Derived vs overridden is a natural "twin" pair.
- **Twins to compare**: IO vs SyncIO; IO vs PureConc (known diverging, #3430); derived `Concurrent` combinators vs `IO` overrides; Concurrent vs Async `Queue` impls; JVM vs JS vs Native runtimes.
- **Deliberate oddities are not bugs**: `onCancel`/`uncancelable` monad-law violation, #4488. Keep `maybe_intended` and a `QUESTIONS.md` of maintainer rulings.

## Suggested order of work (not started; confirm with the user)

The detailed version is the [Project plan](project-plan.md).

1. Lean core: IO syntax, fiber state, scheduler-indexed small-step semantics with fuel.
2. Scala difftest harness (TestControl + JSON lines).
3. Kernel laws (MonadCancel, GenSpawn, Async) as properties — sanity check of the model.
4. Calibration on known open bugs (#4687 `syncStep`, #4571 Queue, #4627 `Resource.eval`): the model must refute them.
5. std structures (Queue, Semaphore, Mutex, Deferred, Ref, Resource, Supervisor, Dispatcher).
6. Later: lock-free runtime (`LocalQueue`, `CallbackStack`) with a weak-memory model.

## Metrics to report

Inventory coverage (reviewed FAITHFUL / in scope), difftest case counts and seeds, properties proven/refuted/open, refutations with reproducers, mismatch triage counts, false-positive rate (intended vs real), issues filed/accepted, cost.

## Open questions

- Model the real IOFiber (mask counter) or the spec (mask ids)? Probably both.
- Can TestControl replay a Lean-chosen schedule?
- Safety only, or fairness/liveness too?
- (Resolved 2026-11-10: no upstream filing; bug records stay in this repo.)
- Compute budget: python-formalization needed a 512 GB build machine at 613k lines.

## See Also

- [Project plan](project-plan.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Differential testing](differential-testing.md)
- [Modeling approaches](../semantics/modeling-approaches.md)
- [Semantics of CE3](../cats-effect/semantics.md)
- [Bug history](../cats-effect/bug-history.md)
- [Community critique](../precedents/community-critique.md)

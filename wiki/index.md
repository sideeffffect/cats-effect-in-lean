# Knowledge Base Index

## methodology

How this project works: synthesis, agent loop, difftest design. Start here.

| Article | Summary | Updated |
|---------|---------|---------|
| [Lessons for Cats Effect in Lean](methodology/lessons-for-cats-effect.md) | Top-level synthesis: what to copy, what is new for CE, order of work | 2026-11-10 |
| [Agent workflow and review protocol](methodology/agent-workflow.md) | Inventory → mirror → difftest → prove/refute → review; rubric; bug records; no upstream filing | 2026-11-10 |
| [Project plan](methodology/project-plan.md) | Draft step-by-step plan: phases 0–9, gates, estimates, risks, user decisions | 2026-11-10 |
| [Differential testing](methodology/differential-testing.md) | Planned Lean-vs-CE difftest harness, nondeterminism handling, triage bins | 2026-11-10 |

## cats-effect

Facts about the pinned Cats Effect version, its code, semantics and bugs.

| Article | Summary | Updated |
|---------|---------|---------|
| [Pinned version: v3.7.1](cats-effect/pinned-version.md) | v3.7.1 (2026-08-23, eb0cc25) is the latest stable; pinned | 2026-11-10 |
| [Source layout](cats-effect/source-layout.md) | kernel, laws, IO ADT, IOFiber, runtime, std, PureConc, TestControl | 2026-11-10 |
| [Semantics of CE3](cats-effect/semantics.md) | Cancellation, masking, finalizers, laws; IOFiber vs PureConc | 2026-11-10 |
| [Bug history](cats-effect/bug-history.md) | Bug classes, open bugs, recommended first targets | 2026-11-10 |

## semantics

Formal modeling approaches for effect systems and concurrency.

| Article | Summary | Updated |
|---------|---------|---------|
| [Modeling approaches for CE3 in Lean](semantics/modeling-approaches.md) | Small-step + scheduler recommended; ITrees, dejafu, Marlow 2001 compared | 2026-11-10 |

## lean

Lean 4 toolchain facts and proof hygiene.

| Article | Summary | Updated |
|---------|---------|---------|
| [Lean v4.35.0 toolchain](lean/toolchain-v4-35.md) | lake check (+ bwrap/AppArmor failure), vcgen, native_decide axioms, recursion styles | 2026-11-10 |
| [Proof hygiene and agent tooling](lean/proof-hygiene-and-agent-tooling.md) | Forbidden tactics, axiom audit, CI gates (incl. this repo's CI), lean-lsp-mcp, lean4-skills, Plausible | 2026-11-10 |

## precedents

Other projects that formalized real languages/systems, and the debate around them.

| Article | Summary | Updated |
|---------|---------|---------|
| [python-formalization](precedents/python-formalization.md) | CPython 3.15.2 in Lean by agents; 418 bugs; AGENTS.md + review prompt | 2026-11-10 |
| [julia-in-lean](precedents/julia-in-lean.md) | Julia Base in Lean by agents; 689 bug records; 77 merged PRs; hollow-proof lesson | 2026-11-10 |
| [Formalization precedents](precedents/formalization-precedents.md) | Cedar, K, JSCert, WasmCert, seL4, Csmith, Netsem, SibylFS and more | 2026-11-10 |
| [Community critique](precedents/community-critique.md) | Arguments for/against; fidelity, intent, hollow proofs, maintainer burden | 2026-11-10 |

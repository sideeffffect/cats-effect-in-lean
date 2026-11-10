# Agent workflow and review protocol

> Sources: synthesized from python-formalization AGENTS.md / REVIEW_PROMPT.md and julia-in-lean ARCHITECTURE.md / review prompts (2026-10..11)
> Raw: [User decision: no bugs outside this repo](../../raw/project-decisions/2026-11-10-no-bugs-outside-this-repo.md); [python AGENTS.md](../../raw/python-formalization/2026-11-09-agents-md-current.md); [python REVIEW_PROMPT.md](../../raw/python-formalization/2026-11-01-review-prompt.md); [python orchestration scripts](../../raw/python-formalization/2026-11-05-orchestration-scripts.md); [julia ARCHITECTURE.md](../../raw/julia-formalization/2026-11-07-julia-base-architecture.md); [julia coverage review prompt](../../raw/julia-formalization/2026-10-29-julia-base-coverage-review-prompt.md); [julia memsafety review prompt](../../raw/julia-formalization/2026-10-29-julia-base-memsafety-review-prompt.md)

## Overview

Both successful projects use the same loop: **inventory → mirror → difftest → state property → prove/refute → reproduce → independent review**. Only reviewed rows count as progress. Agents work in parallel, each in its own module, merged through a gate. This is the protocol adopted (adapted) in this repo's `AGENTS.md`.

## Loop per function

1. **Inventory row** exists for the function (`todo | modelled | excluded`, exclusions with a reason prefix).
2. **Mirror** the Scala body line by line, cite `path:line` at the pinned tag.
3. **Difftest** to 100% on many seeds (see [Differential testing](differential-testing.md)).
4. **State** a property from a law, Scaladoc, docs or an obvious invariant; quantify over all inputs/schedules; hypotheses only documented preconditions. Smoke-test it (Plausible / real CE) first.
5. **Prove** (`x_proven : P`) or **refute** (`x_refuted : ¬P` + bug record + reproducer that prints `REPRODUCED <id>`). Never weaken. Hard → `open` with a note.
6. **Review** by a different agent that only reads.

## Review rubric (adapted from both projects)

Three questions per modelled row; FAITHFUL only if all are yes, else HOLLOW; when unsure answer no:

1. **MIRROR** — does the proposition use a Lean function mirroring *this* body (branches, checks, loops, calls in the same order), not a hand-written spec or a bare variable? Are citations right?
2. **PROPERTY** — does it state a promised behaviour, quantified over all allowed inputs (and schedules), with only documented preconditions?
3. **SETTLED** — proven, or refuted with a bug record and reproducer?

Excluded rows: does the reason truly apply? Extra checks:
- **Wrong-function test**: would `fun _ => .error`, "always succeed", or "never run finalizers" also satisfy it? Then HOLLOW.
- **Vacuous hypotheses**: does a hypothesis assume the interesting case away ("not cancelled", "index in bounds")? julia: 128 of 130 quick proofs did.

## Known failure patterns (avoid)

Breadth-first thin properties (<50% survived review); success-path-only models; missing re-entrancy; callbacks as plain lists; `rfl` on one-liners; examples instead of quantification; bugs in internal helpers unreachable from the public API; stubbing definitions; editing statements.

## Bug records and filing

- One YAML per defect: id, title, priority, kind, area, files, functions, summary, likelihood, `maybe_intended`, reproducer, output per version, expected, `promised_by`, cause, possible_fix, duplicates (with recorded search queries), lean property/theorem.
- Exotic-input rule: also state the ordinary-case property.
- Flip on fix: after an upstream fix, re-mirror and prove the *same* statement.
- **Project decision (user, 2026-11-10): never open bugs, PRs, comments or reactions in any repository other than this one** (including `typelevel/cats-effect`). Bug records stay in this repo. Read-only `gh` on other repos is fine. (The precedents filed upstream after human review; we do not.)

## Orchestration (python-formalization)

Subagents in git worktrees (`worktree-agent-<hex>`), one module each; merge gate rejects files outside the module; review verdicts on main win conflicts; a lock serializes merges; every merge reruns all difftests and reproducers; heavy builds on a separate big machine with a memory watchdog.

## See Also

- [python-formalization](../precedents/python-formalization.md)
- [julia-in-lean](../precedents/julia-in-lean.md)
- [Proof hygiene and agent tooling](../lean/proof-hygiene-and-agent-tooling.md)
- [Lessons for Cats Effect in Lean](lessons-for-cats-effect.md)

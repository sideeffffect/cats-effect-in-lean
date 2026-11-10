# Python formalization (Broyojo/python-formalization)

> Sources: David Andrews (Broyojo), 2026-11-09; python-formalization repo, 2026-10-29..2026-11-09
> Raw: [Blog post](../../raw/python-formalization/2026-11-09-formalizing-cpython-blog.md); [AGENTS.md current](../../raw/python-formalization/2026-11-09-agents-md-current.md); [AGENTS.md v1](../../raw/python-formalization/2026-10-29-agents-md-v1.md); [AGENTS.md breadth-first](../../raw/python-formalization/2026-10-31-agents-md-breadth-first.md); [REVIEW_PROMPT.md](../../raw/python-formalization/2026-11-01-review-prompt.md); [README + CONTRIBUTING](../../raw/python-formalization/2026-11-09-readme-contributing.md); [Launch + issue drafts](../../raw/python-formalization/2026-11-09-launch-and-issue-drafts.md); [Prelaunch review](../../raw/python-formalization/2026-11-05-prelaunch-review.md); [Orchestration scripts](../../raw/python-formalization/2026-11-05-orchestration-scripts.md); [Lean core + difftest harness](../../raw/python-formalization/2026-10-29-lean-core-and-difftest-harness.md); [Bug record example + P1](../../raw/python-formalization/2026-11-05-bug-record-example-and-findings-p1.md); [Bug records list](../../raw/python-formalization/bug-records-list.md); [Layout + metrics note](../../raw/python-formalization/repo-layout-and-metrics-note.md); [Upstream reception note](../../raw/python-formalization/2026-11-10-upstream-reception-note.md)

## Overview

An agent-driven (Claude Opus 5.5 + Codex review) formalization of CPython 3.15.2 in Lean 4 v4.35.0 (no Mathlib). In 12 days (2026-10-29..11-09, ~2,300 commits in 4 days of parallel subagents in git worktrees) it produced 613k lines of Lean, 4,516 registry properties (3,834 proven, 588 refuted, 94 open) and 418 bug records that reproduce on 3.15.2. It was inspired by and adapted from [julia-in-lean](julia-in-lean.md). Its `AGENTS.md` and `coverage/REVIEW_PROMPT.md` are the main templates for our own agent rules.

## Method: four steps per function

1. **Mirror** the source line by line: same branch order, same checks, exact error messages, C integer wrap. Cite `file:line` of the one pinned version. Loops use fuel; the fuel-out error is never a real outcome.
2. **Difftest** before any property: Lean exe `pydiff` and real `python3` run the same JSON-lines cases. Need 100% agreement on ≥50,000 edge-heavy cases over several seeds. A mismatch is a model bug until proven otherwise; a mismatch between CPython's own C and Python twins is a finding.
3. **Prove or refute**: `theorem x_proven : P` or `theorem x_refuted : ¬P`. A refutation needs `bugs/<id>.yaml` whose reproducer prints `REPRODUCED <id>`. Never weaken a statement to get a proof; hard ones stay `.open` with a note.
4. **Independent review** by a separate agent that only reads (does not run). Three questions per row: MIRROR, PROPERTY, SETTLED. Verdict FAITHFUL only if all are yes, else HOLLOW. Only FAITHFUL rows count as coverage.

## Infrastructure

- **Coverage inventory**: a script parses the pinned source into `coverage/methods/*.tsv` (33,585 rows: functions, opcodes, grammar rules). Status `todo | modelled | excluded`. Exclusions need a reason prefix (`no-behaviour:`, `platform:`, `trivial:` …). Headline metric = reviewed-FAITHFUL rows (4,071 / 26,004 in scope, 15.7%).
- **Registry**: `Entry {id, pyFile, pyFns, statement, source, status, prop, thm, bug, notes}` per area.
- **Audit** (`Audit.lean` + `audit.sh`): each theorem's type is exactly `prop` or `¬prop`; axioms ⊆ {`propext`, `Classical.choice`, `Quot.sound`}; refuted ⇒ bug id. Grep forbids `sorry`, `admit`, `native_decide`, `bv_decide`, `ofReduceBool`, `implemented_by`, `@[extern]`, new axioms.
- **Merge gate**: a branch may touch only its own module paths; review verdicts on main always win conflicts; a lock serializes merges; each merge reruns all difftests and bug reproducers.
- **Version re-pin** (3.14.7 → 3.15.2): `repin.py` reset changed rows to `todo` with a `changed-in-3.15:` note and archived old reviews.
- **Compute**: a 64-CPU / 512 GB pod; `scripts/r` syncs a worktree and runs heavy commands there; a watchdog kills Lean processes over 64 GB RSS; `-M8000` per file.

## What failed and was fixed

- **Breadth-first brief failed.** "At least one property per function" gave <50% FAITHFUL rows (21% in `functools.py`). AGENTS.md was rewritten to "fewer, deeper properties".
- **Recurring hollow patterns** (now listed in AGENTS.md): success-path-only models; missing re-entrancy guards; int-only inputs; callbacks modelled as plain lists; `rfl` on one-line definitions; theorems a wrong function would also satisfy.
- **Wrong-function test**: if `fun _ => .error` or "always take the first" also satisfies the theorem, it is HOLLOW. Totals: 5,322 FAITHFUL, 295 HOLLOW/withdrawn. Some files needed up to 9 review rounds.
- **Valid proofs about wrong models**: four found (allocation never fails; lazy codec load; exact exception class compare; freed addresses never reused). Rule: run every proved statement against the real interpreter too. The address-reuse fix turned a "proof" into a real ABA bug.

## Bugs found

- Priorities: P1 19, P2 29, P3 120, P4 210, P5 58. The agents rated 331 of them Low/Very-low likelihood.
- Classes: C/Python twin disagreement 129; wrong result 56; crash 28; memory corruption 27; docs mismatch 26; wrong error 18; missing input check 12; other 122.
- Worst bugs come from **re-entrancy**: user `__eq__`/`__hash__`/`__index__`/`__del__` mutating a container while C holds pointers into it. C arithmetic was usually right; bugs were in parsers, missing error checks, NUL assumptions, wrong validation order.

## Upstream etiquette

- Only 6 issues filed at launch (gh-161688..161693); 3 got fix PRs from others within a day.
- In October 2026 an automated tool ("bugforge") bulk-filed ~90 CPython issues that were closed as spam; maintainers rejected literal one-sentence doc readings (python/cpython#158786).
- Response: a human reads every report; Codex re-runs each draft on release and main; related findings are grouped per module; agents may only read GitHub (never create issues or comments).

## Lessons for this project

See [Lessons for Cats Effect in Lean](../methodology/lessons-for-cats-effect.md). Key differences: Python declared multithreading out of scope; Cats Effect is about concurrency, so the difftest needs a deterministic scheduler (`TestControl`) or schedule replay.

## See Also

- [julia-in-lean](julia-in-lean.md)
- [Community critique](community-critique.md)
- [Formalization precedents](formalization-precedents.md)
- [Agent workflow and review protocol](../methodology/agent-workflow.md)

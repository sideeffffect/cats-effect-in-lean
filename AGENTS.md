# AGENTS.md

Rules for all AI agents that work in this repository.

## Goal

This project formalizes Cats Effect in Lean 4 to find bugs in Cats Effect.
We model the real Scala code, state the properties that Cats Effect promises, and prove or refute each one.
A refuted property is a bug candidate. It becomes a bug only when a Scala reproducer shows it on the real library.

The method comes from two earlier projects: [python-formalization](https://github.com/Broyojo/python-formalization) and [julia-in-lean](https://github.com/MilesCranmer/julia-in-lean).
Read `wiki/methodology/lessons-for-cats-effect.md` before you plan any work.

## Current phase: research only

The project is in the research phase. Do not start the formalization (models, proofs, harnesses) until the user tells you to start.
Research results go into the wiki.

## Pinned versions

- **Cats Effect v3.7.1** (tag `v3.7.1`, commit `eb0cc258fc732fc37f22f117c2e81d5554d67024`, 2026-08-23). Formalize only this version. Do not change the pin unless the user tells you to.
- Local source checkout: `~/Projects/cats-effect`, detached at `v3.7.1`. Cite source as `<path>:<line>` at this tag.
- A bug counts if it reproduces on v3.7.1. Also run each reproducer on the latest `series/3.x` and record the result.
- Lean toolchain: `leanprover/lean4:v4.35.0` (see `lean-toolchain`). Upgrade only when the user tells you to, in one separate change.
- `lean` and `lake` are in `~/.elan/bin`. They are not always on `PATH`.

## Knowledge wiki (MANDATORY)

This repository has an LLM wiki (Karpathy pattern). The wiki is the long-term memory of this project. You MUST use it and grow it in every session.

### Structure

- `raw/` — Source material (articles, papers, docs, notes, research output). Do not change files in `raw/` after you add them.
- `wiki/<topic>/<article>.md` — Compiled knowledge articles. One level of topic directories only.
- `wiki/index.md` — Index of all articles: link, summary, and Updated date, grouped by topic.
- `wiki/log.md` — Append-only log of all wiki operations.

Use the `karpathy-llm-wiki` skill for the exact formats and workflows (ingest, query, archive, lint). If the skill is not available, follow the structure above.

### 1. Learn from the wiki first

- At the start of each task, read `wiki/index.md`.
- Read all articles that relate to the task before you plan, design, or write code.
- Prefer facts from the wiki to your training knowledge. If the wiki and other evidence disagree, find out which is correct and fix the wiki.

### 2. Add all new knowledge to the wiki

Record each new item in the wiki in the same session that you find it. Do not wait for the end of the task. This includes:

- New facts about Lean 4, Cats Effect, effect systems, or the libraries we use.
- Findings from debugging, experiments, and proofs (what worked, what failed, and why).
- Research results, web sources, papers, and documentation that you read.
- Design decisions and their reasons.
- Gotchas, workarounds, and toolchain behavior.

Procedure:

1. Save the source material to `raw/<topic>/` (for your own findings, write a short note there as the source).
2. Merge the knowledge into an existing article, or make a new article.
3. Update related articles and their See Also links.
4. Update `wiki/index.md` and append to `wiki/log.md`.

### 3. Maintain and lint the wiki

- Run a wiki lint at the end of each task that changed the wiki, and at least once per session.
- Fix broken links, missing index entries, and missing cross-references.
- Mark contradictions and outdated claims. Correct them when you have evidence.
- Keep articles short, factual, and current. Merge duplicates.

## Formalization method (applies when the formalization starts)

Details and reasons: `wiki/methodology/agent-workflow.md` and `wiki/methodology/differential-testing.md`.

The headline number is **rows that pass independent review**, not rows marked `modelled`.
Fewer, deeper properties are better than many thin ones. Both earlier projects first tried "breadth first", and fewer than half of the results survived review.

### 0. Inventory

- Keep one inventory row for each method, IO constructor, run-loop branch, and law in scope (kernel, core IO, std).
- Status is `todo`, `modelled`, or `excluded`. An exclusion needs a reason prefix, for example `no-behaviour:`, `platform:`, `internal:`, `trivial:`, and a justification.
- A row counts as modelled only through a registry entry that names it.

### 1. Model (mirror)

- Mirror the Scala source line by line: same branch order, same check order, same early returns. Cite `<path>:<line>` at v3.7.1.
- Mirror the implementation (for example `IOFiber.runLoop`), not the docs. Bugs live where the code and the docs disagree.
- Errors and outcomes are values (`Outcome`: succeeded, errored, canceled). Model which exception is raised.
- Loops and the run loop use fuel. "Out of fuel" is a separate result. It is never a Cats Effect outcome.
- Do not use `partial def` for model logic. It is opaque to proofs.
- Scheduling is an explicit input (a choice list or a relation). Do not assume one fixed schedule.
- User code (thunks, finalizers, `async` callbacks, `Ref.modify` functions) is a parameter. It can raise, suspend, run twice, and race with cancel. A model where callbacks always succeed is hollow.
- Generic code over `F[_]` takes the typeclass operations as parameters and their laws as hypotheses.
- Model "twins" side by side when they differ: derived typeclass combinators vs `IO` overrides, `IO` vs `SyncIO`, the two `Queue` implementations, `IO` vs `PureConc`.
- Never fix Cats Effect in the model.

### 2. Differential test (before any property)

- The Lean model and the real Cats Effect v3.7.1 run the same generated programs (JSON lines).
- Use `TestControl` for deterministic runs. Compare by refinement: each real outcome must be in the set of outcomes that the model allows.
- Reach 100% agreement on at least 50,000 cases with several seeds before you state a property.
- A mismatch is a model bug until shown otherwise. Fix the model. Do not delete a generator case to get agreement.

### 3. Properties

- Sources, in order of preference: (a) Cats Effect disagreeing with itself (twins, laws checked on `IO`); (b) undisputed invariants (no lost element, finalizers run exactly once, no leaked fiber, no deadlock, no hang); (c) Scaladoc and docs sentences read in context.
- Quantify over all inputs and all schedules. Each hypothesis must be a documented precondition or a type invariant. Never assume away the interesting case ("not canceled", "callback does not throw").
- Smoke-test each statement (Plausible, and the real library) before you try to prove it.
- Known deliberate behavior is not a bug. Example: `onCancel` over an `uncancelable` boundary breaks the monad laws on purpose. Check `wiki/cats-effect/semantics.md`.

### 4. Prove or refute

- `theorem foo_proven : Foo` or `theorem foo_refuted : ¬Foo`. The theorem type must be exactly the registered property or its negation.
- Never weaken a statement to get a proof. If it is false, refute it. If the proof is hard, keep the entry `open` with a note.
- A refutation needs a bug record and a Scala reproducer that prints `REPRODUCED <id>` as its last line on v3.7.1.
- A proof can be valid and still false about the real library if the model is wrong. Before you rely on a proven statement, test that statement against the real library.
- Forbidden: `sorry`, `admit`, `native_decide`, `bv_decide`, `ofReduceBool`, new `axiom`s, `implemented_by`, `@[extern]`, `debug.skipKernelTC`, and local `notation` in specification files.
- Allowed axioms: `propext`, `Classical.choice`, `Quot.sound` only. Check with `#print axioms`.

### 5. Independent review

A different agent reviews each modelled row. The reviewer reads the source and the proofs. The reviewer does not run anything. For each row, answer:

1. **MIRROR**: Does the proposition use a Lean function that mirrors this method's body (branches, checks, loops, calls in the same order), not a hand-written specification or a bare variable? Are the citations correct?
2. **PROPERTY**: Does it state a promised behavior, quantified over all allowed inputs and schedules, with only documented preconditions as hypotheses?
3. **SETTLED**: Is it proven, or refuted with a bug record and a reproducer?

The verdict is FAITHFUL only if all answers are yes. Otherwise it is HOLLOW. When unsure, answer no.
Also apply the **wrong-function test**: if a broken function ("always error", "never run finalizers", "always take the first") also satisfies the theorem, the row is HOLLOW.
For an excluded row, check that the reason truly applies.

### 6. Bug records and triage

- One YAML file per defect: `id`, `title`, `priority`, `kind`, `area`, `files`, `functions`, `summary`, `likelihood`, `maybe_intended`, `reproducer`, `output` (v3.7.1 and `series/3.x`), `expected`, `promised_by`, `cause`, `possible_fix`, `duplicates` (with the search queries), `lean` (property and theorem).
- The bug must be reachable through the public API.
- If only an exotic input refutes a property, also state and settle the property for ordinary inputs.
- Be honest in `likelihood` and `maybe_intended`. Do not inflate priority.

### Never open bugs outside this repository

- NEVER open issues or pull requests, write comments, or add reactions in any repository other than this one (`sideeffffect/cats-effect-in-lean`). This includes `typelevel/cats-effect`. Never contact anyone.
- All bug records stay in this repository.
- Read-only `gh` commands on other repositories (`gh search`, `gh issue view`, `gh api` GET) are allowed. Record your duplicate searches.

## Git

- Commit and push all changes immediately to `origin/main`, unless the user explicitly tells you to do something different.
- This includes wiki changes.

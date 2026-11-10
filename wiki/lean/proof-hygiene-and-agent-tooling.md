# Proof hygiene and agent tooling for Lean

> Sources: lean-lsp-mcp v0.33.0, 2026-11-03; lean4-skills (cameronfreer), 2026-11-08; lean-action v1.7.1, 2026-11-06; Plausible; Vero (arXiv 2608.13522), 2026-08-13; python-formalization Audit.lean, 2026-11; AI-prover landscape notes, 2026-11-10
> Raw: [User answers Q1–Q3](../../raw/project-decisions/2026-11-10-user-answers-q1-q3.md); [CI first runs](../../raw/project-decisions/2026-11-10-ci-first-runs.md); [CI setup decision](../../raw/project-decisions/2026-11-10-ci-setup.md); [lean-lsp-mcp README](../../raw/lean-tooling/lean-lsp-mcp-readme.md); [lean-lsp-mcp tools](../../raw/lean-tooling/lean-lsp-mcp-tools.md); [lean4-skills README](../../raw/lean-tooling/lean4-skills-readme.md); [lean4-skills SKILL.md](../../raw/lean-tooling/lean4-skills-skill-md.md); [lean4-skills guardrails](../../raw/lean-tooling/lean4-skills-guardrails.md); [lean4-skills disprove](../../raw/lean-tooling/lean4-skills-disprove-command.md); [lean-action README](../../raw/lean-tooling/lean-action-readme.md); [Plausible README](../../raw/lean-tooling/plausible-readme.md); [Vero anti-cheating](../../raw/lean-tooling/2026-08-13-vero-agents-verified-repos-anti-cheating.md); [python-formalization AGENTS.md copy](../../raw/lean-tooling/python-formalization-agents-md.md); [python-formalization harness code](../../raw/lean-tooling/python-formalization-difftest-harness-code.md); [AI prover landscape](../../raw/lean-tooling/2026-11-10-ai-prover-and-search-landscape-notes.md); [Aristotle](../../raw/lean-tooling/harmonic-aristotle-product-page.md); [Gauss](../../raw/lean-tooling/math-inc-gauss-intro.md)

## Overview

Agents cheat, mostly by accident. Proof hygiene must be enforced mechanically in the build and CI, not only in reviews. This article lists the gates and the agent tools.

## Mechanical gates

- **Forbidden in proofs/specs**: `sorry`, `admit`, `native_decide`, `bv_decide`, `axiom` (new), `implemented_by`, `@[extern]`, `debug.skipKernelTC`, local `notation` in spec files (Vero: notation slipped past keyword filters).
- **Axiom allowlist**: only `propext`, `Classical.choice`, `Quot.sound`. Check with `#print axioms` / `lean_verify`; `sorryAx` and `native_decide` axioms show only there.
- **Registry audit** (python/julia `Audit.lean`): each registered theorem's type is *exactly* `prop` or `¬prop`; refuted ⇒ bug record exists; reject single-example properties.
- **Cheats that pass the axiom check** (Vero): a `Decidable` instance that asserts its own answer; `@[implemented_by]` real algorithm on a noncomputable oracle. Grep for them.
- **CI** (lean-action v1.7.1): `build-args: "--wfail"`, `axiom-audit` with allowlist, `nanoda` with `nanoda-allow-sorry: false`, `leanchecker`. Run `lake check --paranoid` on a schedule where bwrap works.
- **This repo's CI (set up 2026-11-10)**: `ci.yml` = lean-action (`--wfail`, leanchecker, axiom-audit) + sandboxed `lake check` + `scripts/check_forbidden.py` + `scripts/check_wiki.py`; `paranoid.yml` weekly = `lake check --paranoid` (runs Lean paranoid kernel, lean4lean, nanoda, con-leche, con-ron; ~4 min locally on the empty scaffold); Dependabot for actions; actions pinned by SHA. **Gotcha**: the package name `cats-effect-in-lean` is not a module name. lean-action's `leanchecker` needs `leanchecker-args: CatsEffectInLean`, and its `nanoda` input cannot be pointed at a module (lean4export panics: "import failed, trying to import module with anonymous name"), so we use the nanoda bundled in `lake check --paranoid` instead. The source grep is still needed: axiom audits cannot see `implemented_by`, `@[extern]` or `debug.*` options.

## Agent tools

- **lean-lsp-mcp** (v0.33.0): `lean_goal`, `lean_diagnostic_messages`, `lean_multi_attempt`, `lean_run_code`, `lean_verify` (axioms + scan for `implemented_by`/`debug.*`), search (local ripgrep, LeanSearch, Loogle, Lean Finder). Run `lake build` first; `LEAN_REPL=true` speeds it up; remote Loogle is rate-limited (3 req / 30 s).
- **lean4-skills** (Claude Code plugin, `/plugin marketplace add cameronfreer/lean4-skills`): prove, review, golf, checkpoint, `/lean4:disprove` (counterexample search). Rules: never change statements, standard axioms only, LSP first, no `git add -A`.
- **Plausible**: `plausible` tactic and `Testable.check` with shrinking; `deriving Arbitrary`. Use it to smoke-test a property before proving it. Deep ASTs may need custom type-directed generators (Cedar lesson).
- **Tactic order**: concrete runs `decide`/`decide_cbv`/`rfl`; arithmetic `simp`/`grind`/`omega`/`lia`; `native_decide` only in throwaway `#eval` files.
- **AI provers** (low confidence): Goedel/DeepSeek/Kimina target competition math. Harmonic Aristotle has an API and markets code verification. Math Inc Gauss is early access. julia-in-lean reports Opus-class models proved things GPT-6.1 Luna could not.

## Behavioural rules (from precedents)

- Never weaken a statement to get a proof. If false, refute it (`¬P` + reproducer). If hard, leave it `open` with a note.
- A proof can be valid and still empty: check hypotheses do not assume the interesting case (julia 128/130).
- Use the wrong-function test (python-formalization).

## `sorryAx` in the source scan (2026-11-10)

`scripts/check_forbidden.py` also forbids `\bsorryAx\b` (user answer to Q2). Before, only `sorry` was matched; a direct `sorryAx` term passed the source scan and only the axiom audits caught it.

## See Also

- [Lean v4.35.0 toolchain](toolchain-v4-35.md)
- [Agent workflow and review protocol](../methodology/agent-workflow.md)
- [python-formalization](../precedents/python-formalization.md)

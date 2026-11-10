# Julia in Lean (MilesCranmer/julia-in-lean)

> Sources: Miles Cranmer, Discourse 2026-10-25; julia-in-lean repo @ de862b5, 2026-11-07; JuliaLang/julia issues/PRs by MilesCranmerBot, collected 2026-11-10
> Raw: [Discourse thread](../../raw/julia-formalization/2026-10-25-discourse-formalizing-julia-in-lean-thread.md); [README](../../raw/julia-formalization/2026-11-07-julia-in-lean-readme.md); [ARCHITECTURE.md](../../raw/julia-formalization/2026-11-07-julia-base-architecture.md); [Coverage review prompt](../../raw/julia-formalization/2026-10-29-julia-base-coverage-review-prompt.md); [Memsafety review prompt](../../raw/julia-formalization/2026-10-29-julia-base-memsafety-review-prompt.md); [DynamicExpressions README + architecture](../../raw/julia-formalization/2026-10-25-dynamicexpressions-readme-architecture.md); [DynamicExpressions QUESTIONS.md](../../raw/julia-formalization/2026-10-25-dynamicexpressions-questions.md); [Artefact samples](../../raw/julia-formalization/2026-11-07-julia-in-lean-artefact-samples.md); [Upstream issues/PRs](../../raw/julia-formalization/julia-upstream-issues-prs-milescranmerbot.md); [Repo survey note](../../raw/julia-formalization/2026-11-10-julia-in-lean-repo-survey-note.md)

## Overview

The first of the 2026 "agent formalizes a language's standard library in Lean to find bugs" projects. Miles Cranmer used Claude Opus 5.5 and OpenAI models via Codex (≈ $5,000 API-equivalent) to model Julia Base (pinned 1.13.2 release + master commits) in Lean v4.34.1, core only. It started with a model of his own DynamicExpressions.jl. Announced 2026-10-25 as "~400 bugs"; at HEAD the registry has 8,838 entries (7,072 proven, 745 refuted, 1,021 todo) and 689 bug YAMLs. It is the direct inspiration for [python-formalization](python-formalization.md). Its agent instructions are `ARCHITECTURE.md` plus two fixed review prompts; there is no `AGENTS.md`.

## Method

- **Mirror, then specify.** One Lean definition per Julia method, line by line, same branches and check order, fixed-width wraparound (`JInt t`). Verbatim Julia source kept in comments; `source_comments.py` validates them against the pinned commit and reports source changes. One model file per Base file.
- **Exceptions as values**: `Jl α = Except JlError α`; model the exception type, message only when relevant.
- **Generic code**: user-supplied methods become parameters, required laws become hypotheses (e.g. `StrictWeak lt → …`).
- **Rule: "Never fix Julia in the model."** When model and Julia disagree on a reproducer, the model is wrong: fix the model, never the reproducer.
- **Differential testing before proofs**: exhaustive Int8/UInt8 table (656,896 rows), 236,954 Float64 ops, ~15,000 TOML docs.
- **Properties**: closed `Prop` from a docstring, the manual, or an obvious invariant; must quantify (audit counts quantified data variables and rejects worked examples). `Restating.lean` flags entries that hold by definitional unfolding (review aid).
- **Refutation**: theorem `¬prop` from a concrete counterexample via `decide`, plus `repro/<id>.jl` that prints `REPRODUCED <id>` as its last line.
- **Exotic-input rule**: if refuted only by exotic input (typemin, offset axes, custom types), add a second entry for the ordinary case. A bug on ordinary inputs is worth much more.
- **Flip on fix**: after an upstream fix, re-mirror the new source; the same statement must become provable. Never edit the statement.
- **Workflow order**: reproducer → duplicate search (`gh search`, queries recorded) → `bugs/<id>.yaml` → validate, before any further modelling.

## Bug YAML schema

`id, title, priority (P0–P3), kind (wrong-result | wrong-exception | missing-error | crash | hang | documentation | model-counterexample), area, files, functions, summary, likelihood, maybe_intended, reproducer, output{release,nightly}, reproduced, expected, promised_by, cause, possible_fix, duplicates{issues,queries}, lean{property,theorem}, covers`. Priority scale is conservative: P0 = crash/hang/memory unsafety/silent wrong result on ordinary inputs; P3 = docs contradict arguably-correct behaviour.

## Results

- 689 YAMLs: P0 6, P1 69, P2 398, P3 216. Kinds: wrong-result 355, wrong-exception 185, documentation 58, missing-error 51, crash 24, hang 8.
- Upstream (2026-11-10): 112 issues (67 open, 44 closed completed) and 122 PRs (77 merged). Maintainers asked to get simple fixes as PRs instead of issues.
- Severe finds include a 1.14 miscompile, BitArray memory corruption, Printf buffer overflows, an artifact path escape.
- Headline counts moved a lot (Oct 26: 9,227 proven; Oct 29: 5,058) as reviews and `todo` status arrived.

## Failures

- **Hollow proofs**: the first memory-safety pass claimed 130 proofs in under an hour; review rejected 128 because they assumed the index was in bounds. Coverage reviews: 2,306 FAITHFUL vs 3,859 HOLLOW rows.
- Harness false negative: output printed after `REPRODUCED` broke the check.
- "Bugs" in internal helpers no public caller reaches — withdrawn.
- Scope pressure: agents stub definitions, narrow statements, or check examples instead of quantifying.

## Controversies

- Intent: maintainers said some findings were deliberate or "not really a bug" (e.g. `LinRange` makes no float exactness promise). Risk: an agent "fixes" code it does not understand.
- Model faithfulness: "how is the link between model and implementation established?" Ideas: a `test/lean/` folder with CI; contracts next to code (Creusot, Stainless, SPARK); a semi-formal "extended docstring" layer.
- Property-based testing (Supposition.jl) found some of the same classes of bugs more cheaply.
- Exploitable findings go privately to security@julialang.org.

## See Also

- [python-formalization](python-formalization.md)
- [Community critique](community-critique.md)
- [Agent workflow and review protocol](../methodology/agent-workflow.md)
- [Lessons for Cats Effect in Lean](../methodology/lessons-for-cats-effect.md)

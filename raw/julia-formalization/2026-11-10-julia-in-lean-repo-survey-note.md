# julia-in-lean: repository survey note (own findings)

> Source: https://github.com/MilesCranmer/julia-in-lean (clone at ~/Projects/julia-in-lean, HEAD de862b5), https://github.com/JuliaLang/julia (gh API), https://discourse.julialang.org/t/140243
> Collected: 2026-11-10
> Published: Unknown

Own research note. Numbers computed from the clone on 2026-11-10 unless a source is named.

## Agent instruction files

- There is NO `AGENTS.md`, `CLAUDE.md`, or other agent prompt in the repo, in any commit (`git log --all --name-only` checked).
- The only fixed prompts are the two review rubrics: `julia-base/coverage/REVIEW_PROMPT.md` and `julia-base/memsafety/REVIEW_PROMPT.md`.
- The de-facto agent instructions are `julia-base/ARCHITECTURE.md` (modelling rules, workflow, YAML schema, priority scale) and `dynamicexpressions/ARCHITECTURE.md`.
- Commits are authored by `MilesCranmerBot` (the AI-text account). The author says: Claude Opus 5.5 and OpenAI "Daybreak Blue" via Codex; about $5,000 API-equivalent (Discourse post #1). "GPT-6.1 Luna" could not find some proofs (post #13).

## Layout (HEAD de862b5)

- Two Lean packages, Lean `v4.34.1`, core only, no Mathlib.
- `julia-base/` (main) and `dynamicexpressions/` (template; DynamicExpressions.jl 2.13.0).
- ~3,600 files total; ~1.49 M lines of `.lean`.
- `julia-base/JuliaLean/Core.lean`: `JlError`, `Jl α = Except JlError α`, `IntTy` (10 BitInteger types), `JInt t` (bounded Int + wrap), checked div/rem.
- `JuliaLean/base/<path>.lean`: one model file per Julia `base/<path>.jl` (197 files), verbatim Julia source in comments. `scripts/source_comments.py` seeds/validates/compares these comments against a Julia revision.
- `JuliaLean/Proofs/base/<path>.lean` (+ subfolders): properties and proofs per source file.
- `JuliaLean/stdlib/`, `JuliaLean/Proofs/stdlib/`: Printf, Dates, Base64, UUIDs, CRC32c, TOML, Markdown, Sockets, Serialization, Artifacts, Random, Unicode.
- `JuliaLean/Runtime/`: shared representations (strings, floats, collections, IO). No project axioms.
- `JuliaLean/CRuntime/`, `JuliaLean/src/<file>_c.lean`: C runtime/GC protocol models, separate audit `CRuntimeAudit.lean`. Counterexamples there are `kind: model-counterexample` (not reproduced on real Julia).
- `JuliaLean/Registry.lean` -> `registry.tsv` (+ `.metadata.jsonl`, `.evidence.json`).
- `Audit.lean`, `Report.lean`, `Restating.lean` (lists proven entries that hold by definitional unfolding: `DEFEQ`, `PARTIAL k/n`, `SAME-AREA-DEFEQ`; review aid only).
- `repro/<id>.jl` (740 files; 15 are `*-differential.jl`), `bugs/<id>.yaml` (689).
- `coverage/methods/*.tsv` (202), `coverage/review/*.tsv` (85), `memsafety/sites-1..6.tsv`.
- `scripts/`: `audit.sh`, `check-proof-escapes.py` (+ tests), `check_bugs.py`, `check_coverage.py`, `coverage_evidence.py` (hash-binds reviews to inputs), `check_memsafety.py`, `run-repros.sh`, `repro-target.sh`, `list_base_methods.jl`, `check-hoist.py`, `gc/` (GC stress builds).

## How Julia Base is modelled

- One Lean def per Julia method, line by line: same branches, same check order, same intermediate types; docstring cites `base/<file>.jl:<line>` on the pinned master.
- Exceptions are values: `.error .argumentError`, `.boundsError`, `.inexactError`, ... Exception TYPE is modelled; message only if a property needs it.
- Fixed-width integers with wraparound exactly where Julia wraps; never unbounded Int for Julia ints.
- Float64 modelled at bit level (differential test uses raw UInt64 words).
- Generic code: user-defined methods become parameters; theorems take the needed laws as hypotheses (e.g. `StrictWeak lt -> StrictWeak (islessM lt)`). Nothing is claimed about abstract types such as `Number` (post #6).
- DynamicExpressions: "mirror, then specify" - a mirror def follows the code, a separate simple spec (denotation) states intent; properties relate the two. "Never fix Julia in the model." `@inbounds` out-of-range = `JlError.undefinedBehavior`. User operators = arbitrary total Lean functions.
- Pinned sources: release 1.13.2 (`45b6d15e34b`), previous nightly `bbfa0ce4150`, target master `f755f49a9e4` (1.15.0-DEV).

## How the model is tested against real Julia

- Differential testing BEFORE proofs. Julia scripts (`repro/*-differential.jl`) emit lines `<i> <op> <result>` for fixed + PRNG inputs (e.g. Float64 bit patterns, all rounding modes, all 10 int types). Lean evaluates the same inputs and compares. Exceptions mapped to tokens (`inexact`, `domain`, `method`).
- Reported results: Int8/UInt8 core exhaustive on 656,896 rows; Float64 236,954 ops on both versions; TOML parser ~15,000 documents.
- Rule: disagreement means the model is wrong; fix the model, never the reproducer.
- Every refutation needs `repro/<id>.jl`, pure Julia stdlib, last line `REPRODUCED <id>`, on 1.13.2 and/or master. Memory-safety repros run a child Julia with `--check-bounds=yes`.
- Note: the exhaustive Int8 table and the Lean-side comparison drivers were not clearly located in the repo (uncertain; several `Validation.lean` / `Check.lean` files reference differential data).

## Audit / gates (build fails if)

- Duplicate id; theorem type not exactly `prop` or `¬ prop`; axioms other than `propext`, `Classical.choice`, `Quot.sound`.
- Source scan rejects `sorry`, `admit`, `native_decide`, `bv_decide`, `ofReduceBool` (ignoring strings/comments).
- Generality check: unfold to fixed depth, count universally quantified data variables; example-only props rejected (a Printf entry with 11 docstring examples was demoted to a lemma).
- Since commit 8c53f61, open entries are allowed as `todo` (printed, counted, not failing). Earlier versions required everything settled.
- "Exotic input" rule: if refuted only by exotic input (offset axes, typemin, huge sizes, custom AbstractArray), add a second entry for the ordinary case.

## Coverage and review

- Whole-Base method inventory at pinned master: 12,774 methods; 11,686 `modelled`, 312 `excluded` (`no-behaviour:`, `deprecated:`, `internal-bootstrap:`, `platform:`), 776 `todo`.
- A row counts only after an independent reviewer with the fixed `coverage/REVIEW_PROMPT.md` (MIRROR / PROPERTY / SETTLED) marks it FAITHFUL; reviews are hash-bound to inputs by `coverage_evidence.py`; any change invalidates them.
- Committed review TSVs (historical, 85 files): 2,306 FAITHFUL vs 3,859 HOLLOW rows. README: "The current checker validates no methods as independently reviewed."
- Memory safety: 1,194 unchecked-access sites (README; the Discourse post says 1,152). Current: 291 not-unchecked, 3 proven (not yet review-passed), 1 user-contract, 899 todo. First pass: 130 "proven" in < 1 h, review failed 128 -> all withdrawn.

## Registry counts over time (README headline per commit)

| Commit | Date | Entries | Proven | Refuted | Todo | Bug YAMLs | Issues filed |
|---|---|---|---|---|---|---|---|
| a8a61fc | 2026-10-25 | 910 | 510 | 400 | - | 401 | 75 |
| 1e399fc | 2026-10-26 | 9,798 | 9,227 | 571 | - | 574 | 90 |
| 8c53f61 | 2026-10-29 | 6,452 | 5,058 | 560 | 834 | 627 | 107 |
| de862b5 | 2026-11-07 | 8,838 | 7,072 | 745 | 1,021 | 689 | 107 |

- The drop from 9,227 to 5,058 proven (10-26 -> 10-29) coincides with introducing `todo`, the coverage review, and the source-organized migration. Interpretation (uncertain): many "proven" entries were demoted after review/migration.
- Git history: 9 commits, all squashed bulk dumps (e.g. ce6fc61 changed 3,157 files, +1.14 M lines). Local history is not public.

## Bug write-ups (bugs/*.yaml, 689)

- Priority: P0 6, P1 69, P2 398, P3 216.
- Kind: wrong-result 355, wrong-exception 185, documentation 58, missing-error 51, crash 24, hang 8, model-counterexample 8.
- Top areas: Ranges 40, BigNums 33, TOML 19, IntArith 18, FloatRanges 17, Show 17, Sort 17, Iterators 16, Markdown 16, Printf 16, RegexUnicode 16.
- Reproduced on: both versions 547; release only 106; nightly only 24 (regression candidates); neither 8 (C runtime model counterexamples); release-only-not-nightly 4.
- 377 YAMLs record no duplicate issue found.
- Fields: id, title, priority, kind, area, files, functions, summary, likelihood, maybe_intended, reproducer, output{release,nightly}, reproduced, expected, promised_by, cause, possible_fix, duplicates{issues,queries,search_notes}, lean{property,theorem}, optional covers, current{commit,reproduced,output,proof}.

## Upstream reporting (JuliaLang/julia, gh API 2026-11-10)

- Issues by MilesCranmerBot: 112 (#64123..#64790). 67 open, 1 reopened, 44 closed as `completed`, 0 closed as `not_planned`. Plus 2 early reports by the human account (e.g. #64121).
- Burst: 20 issues on 10-24, 70 on 10-25.
- 2026-10-25 vtjnash on #64155 / #64151: "Can you make simple fixes like this a PR instead of an issue?" -> on 10-27, 82 PRs opened.
- PRs by MilesCranmerBot: 122 total (120 in this campaign): 77 merged, 42 open, 3 closed unmerged. Many PRs batch several fixes ("fix 11 functions that assume indices start at 1", "fix 8 bugs in printing ...").
- Labels on issues include `bug` 33, `regression 1.14` 4, `GC` 4, `correctness bug ⚠` 3, `crash-on-valid` 1.
- DynamicExpressions.jl: 38 fix PRs merged (from #221); SymbolicRegression.jl: 3 fixes.
- Security-relevant findings went to security@julialang.org; two confirmed bugs are held back from the repo.

## Pushback / false positives seen in comments

- #64790 (AllocOpt/GC): oscardssmith "doesn't seem ... like a bug"; closed, then bot argued with a segfault repro and asked to reopen (now reopened). Author: "my bot didn't describe this one that well".
- #64767: Keno - missing `hasfield` method is deliberate; issue retitled to `sizeof` only.
- #64265: author self-retracted ("doesn't seem like a bug ... docstring needs updating").
- #64524: author unsure whether it is a bug.
- #64216 (`@fastmath hypot`): vtjnash "Not really a bug"; bot argued arity mismatch.
- #64218 (`iswritable(IOStream)`): adienes "is this really a bug?"; bot convinced him.
- #64194 (`String(v)` aliasing): adienes inclined to "not planned"; ends as doc/design debate.
- #64272 (`LinRange` non-monotonic): tim.holy - LinRange contract is not FP exactness; concern that "an agent who may not understand the intent of a function" breaks its purpose by "fixing" it. Fix PR #64388 still merged.
- #64225 (`tanh(Float32)` non-monotonic): adienes on Discourse: unsurprising for polynomial approximations; oscardssmith: "probably worth guaranteeing"; a user found more cases with Supposition.jl (property-based testing).
- #64779: bot corrected its own wrong regression attribution after checking older versions.

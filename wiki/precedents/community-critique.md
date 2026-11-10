# Community critique of agent-driven formalization

> Sources: Hacker News 50435105, 2026-11-10; Julia Discourse thread, 2026-10-25; discuss.python.org, 2026-10-20 and 2026-11-09; Go forum (go-in-lean), 2026-11-03; Martin Kleppmann, 2025-12-08; Leo de Moura, 2026-02-28; Kiran (lean-zip fuzzing), 2026-04-13; LessWrong, 2026-01-12; arXiv quality-audit, 2026-06-12
> Raw: [HN CPython thread](../../raw/discussions/2026-11-10-hn-formalizing-cpython.md); [Julia Discourse thread](../../raw/discussions/2026-10-25-julia-discourse-formalizing-julia-in-lean-thread.md); [discuss.python.org post](../../raw/discussions/2026-11-09-discuss-python-formalizing-cpython-in-lean.md); [CPython PR limits](../../raw/discussions/2026-10-20-discuss-python-pull-request-limits.md); [go-in-lean](../../raw/discussions/2026-11-03-golangbridge-go-in-lean.md); [Maintainer responses](../../raw/discussions/2026-11-10-maintainer-responses-to-formalization-bug-reports.md); [Kleppmann](../../raw/discussions/2025-12-08-kleppmann-ai-formal-verification-mainstream.md); [HN on Kleppmann](../../raw/discussions/2025-12-16-hn-kleppmann-ai-formal-verification-discussion.md); [de Moura essay](../../raw/discussions/2026-02-28-leo-de-moura-when-ai-writes-software-who-verifies.md); [HN on de Moura](../../raw/discussions/2026-03-03-hn-leo-de-moura-who-verifies-discussion.md); [HN de Moura interview](../../raw/discussions/2026-10-29-hn-leo-de-moura-interview-discussion.md); [lean-zip fuzzing](../../raw/discussions/2026-04-13-kiran-lean-proved-correct-then-found-bug.md); [HN on lean-zip](../../raw/discussions/2026-04-14-hn-lean-proved-correct-then-found-bug-discussion.md); [LessWrong](../../raw/discussions/2026-01-12-lesswrong-formal-methods-are-not-slopless.md); [arXiv quality audit](../../raw/discussions/2026-06-12-arxiv-formalizing-numerical-analysis-quality-audit.md); [Navier–Stokes](../../raw/discussions/2026-10-06-arxiv-navier-stokes-lost-in-translation.md)

## Overview

Public discussion is still small (HN 50435105 had 9 comments; no Reddit/Lobsters/Zulip threads found). The main debate is the 36-post Julia Discourse thread, plus general AI + formal-verification essays. Nobody disputes the bugs, because each has a reproducer on the real runtime. Doubts focus on model fidelity, spec intent, empty AI proofs and maintainer burden. A third project, **go-in-lean** (2026-11-03), copied the julia-in-lean method, added QEMU cross-architecture testing, and found accepted Go miscompilations (#82763, #82767, #82772).

## Arguments for

- Real bugs in mature, well-tested code; a real-runtime reproducer removes false positives.
- "Strong semantics and programmatically checkable interfaces find bugs", not brute-force compute (jakobnissen).
- The proof checker turns LLM hallucination into a retry loop with verifiable reward (Kleppmann; de Moura).
- Stating a property forces hidden assumptions into the open; tests and code that share a wrong assumption find nothing (de Moura).

## Recurring critiques

1. **Model fidelity**: a proof is about the model, not the implementation (pitsianis).
2. **Spec completeness**: lean-zip was "proved correct", yet fuzzing found a DoS in the unverified parser outside the proof boundary.
3. **Intent is social**: many "bugs" are intended or need a breaking fix (tim.holy on `LinRange`; Keno; vtjnash "not really a bug"). Risk: an agent "fixes" code it does not understand. Proposal: a semi-formal "extended docstring" layer between intent and model.
4. **Valid but empty proofs**: vacuous hypotheses (128/130 bounds proofs), weakened statements, restricted parameters, changed targets, extra axioms, metaprogramming backdoors (LessWrong; arXiv audit: kernel acceptance overstates quality).
5. **AI explanations of proofs are unreliable**: natural-language write-ups may not match the Lean proof (Navier–Stokes case; uncertain secondary source).
6. **Maintainer burden**: CPython limited non-core users to 3 open PRs after LLM PR floods (2026-10-20); a tool ("bugforge") bulk-filed ~90 issues that were closed as spam. Go asked for PRs/Gerrit changes, not patches in comments. Julia asked for PRs for simple fixes.
7. **Drift**: a one-time model rots. Proposals: a `test/lean/` mirror updated per PR with CI; contracts next to code (Stainless for Scala, Creusot, SPARK).
8. **Trusted base**: the Lean runtime itself had a heap overflow (`lean_alloc_sarray`).
9. **"Just a reimplementation"**: yes — formal methods give "the second mechanism", and the value is in the mismatches (somat). Critics: two implementations are costly.
10. **Abstract interfaces**: you cannot prove facts about "every `Number`". Workaround: user code as parameters, its laws as hypotheses.

## Implications for this project

- Every claimed bug needs a Scala reproducer on v3.7.1 (and a check on `series/3.x`).
- Keep a `maybe_intended` field and a QUESTIONS file with maintainer rulings; CE has deliberate, subtle semantics (e.g. #4488 "as designed").
- Maintainer burden is avoided by project decision (user, 2026-11-10): never open bugs, PRs or comments in any repository other than this one. Bug records stay in this repo. See [Agent workflow](../methodology/agent-workflow.md).

## See Also

- [python-formalization](python-formalization.md)
- [julia-in-lean](julia-in-lean.md)
- [Formalization precedents](formalization-precedents.md)
- [Lessons for Cats Effect in Lean](../methodology/lessons-for-cats-effect.md)

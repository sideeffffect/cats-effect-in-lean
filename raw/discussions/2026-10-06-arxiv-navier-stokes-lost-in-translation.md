# Navier–Stokes Lost in Translation (arXiv 2610.08144) — secondary summary

> Source: https://arxiv.org/abs/2610.08144 (seen via https://www.alphaxiv.org/abs/2610.08144 and https://aiweekly.co/alerts/paper-flags-gap-in-openais-lean-verified-navier-stokes-proof)
> Collected: 2026-11-10
> Published: 2026-10-06

NOTE: Built from search-result snippets and secondary coverage, not the full PDF. Treat details as uncertain. Authors: Alexander Bastounis, Fabian Circelli, Anders C. Hansen.

- Claim: the Lean formalization behind OpenAI's announced Navier–Stokes blow-up result does not correspond to the natural-language (NL) proof.
- Concrete discrepancy cited: for the same output derivative order, NL Lemma 8.6 uses four additional input derivatives; the Lean estimate uses five (a different/weaker estimate). This alone does not show the formal theorem is false.
- Scope note from commentary: the NL paper proves breakdown with smooth forcing, not unforced general blow-up.
- Theoretical claim: semantically faithful autoformalisation sits high in the Solvability Complexity Index hierarchy — informally "harder than any computational problem including the Halting problem".
- Discussion in the Julia thread (foobar_lv2, 2026-11-05; see 2026-10-25-julia-discourse-formalizing-julia-in-lean-thread.md #28-#29): the problem there is that the *de-formalized* NL write-up is wrong, while the formal statement was human-checked; "autoformalization ... has verifiable rewards. Deformalization has no verifiable rewards".

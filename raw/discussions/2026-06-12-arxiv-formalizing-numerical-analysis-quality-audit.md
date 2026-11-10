# Formalizing Numerical Analysis: An Agent Pipeline and Quality Audit Beyond Kernel Acceptance (arXiv 2606.14000) — abstract summary

> Source: https://arxiv.org/abs/2606.14000v1
> Collected: 2026-11-10
> Published: 2026-06-12

NOTE: Paraphrase of the abstract (fetch tool would not return it verbatim). Authors: Theodore Meek, Siyuan Ge, Di Qiu Xiang, Simon Chess, Vasily Ilin. cs.AI.

- A coding agent formalized the textbook *Numerical Methods for Ordinary Differential Equations* in Lean 4. The subject is mostly absent from Mathlib, so the agent built much of the theory from scratch.
- The authors propose a three-part quality framework beyond "it compiles": (1) semantic faithfulness, (2) reuse of Mathlib, (3) reuse across files; evaluated with LLM-as-judge methods.
- Applied to their own output and to released outputs of RepoProver and M2F, they find recurring unfaithful patterns that kernel acceptance does not reveal:
  - incomplete multi-part statements,
  - added weakening hypotheses,
  - parameter restrictions.
- Conclusion: compilation-based metrics overstate formalization quality; they offer a reproducible audit methodology.

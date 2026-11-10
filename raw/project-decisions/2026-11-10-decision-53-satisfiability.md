# Decision 53: satisfiability witness for hypotheses (orchestrator)

> Source: own decision after review batch 4 (`review/2026-11-10-review-batch-4.md`), 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

Review batch 4 found two open entries (`core.IO.bracket.releaseOnce`, `core.IO.guarantee.finalizerOnce`) HOLLOW: their hypothesis `Bracket.MarkersOnly` can never hold together with the other hypotheses, so the statements are vacuous. The smoke `#guard` tests did not check the hypothesis.

53. Every registered property with a non-trivial hypothesis set (more than `WellFormed` and lambda definitions) needs a Lean satisfiability witness: a theorem that shows one concrete input that satisfies all hypotheses together, and for which the interesting case happens (for example the finalizer marker runs). The reviewer checks that the witness exists. Smoke tests must evaluate the hypotheses, not only the conclusion.
54. Test markers (finalizer/acquire markers in invariants) are closures that capture a handle only the test harness holds, so user code cannot forge or forward them (review batch 4, fix 1).

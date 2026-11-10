# Lean: A Unified Platform for Verification, Programming, and AI (ETAPS Industry Day 2026 talk slides)

> Source: https://leodemoura.github.io/static/etaps-industry-2026/
> Collected: 2026-11-10
> Published: 2026-04-15

Author: Leonardo de Moura (Lean FRO).

[...omitted: all slides not about industrial verified-software projects. NOTE (collector): the quotes below were extracted from the slide page by a fetch tool asked for verbatim quotes; they were not compared character-by-character against the page. Treat numbers as "as stated in the talk".]

## Cedar (AWS)

- Slide "AWS and Lean": "Cedar — verified authorization policy language"
- "Cedar spec: model written in Lean."
- "Executable Lean model alongside Rust production code. Lean model ~10x smaller than Rust."
- "~100M differential random tests nightly. Lean: 5 μs/test. Rust: 7 μs/test."
- Diagram caption: "Cedar differential random testing: random inputs fed to both Lean model and Rust production, outputs compared"
- "Release gate: no Cedar version ships unless model, proofs, and differential tests are current."
- "Used by AWS Verified Permissions and AWS Verified Access."
- "Verification queries proved sound and complete against a formalized symbolic compiler."
- "Originally built with Dafny, migrated to Lean."

## SampCert (AWS)

- "SampCert (led by Jean-Baptiste Tristan): first comprehensive, mechanized foundation for executable DP implementations."
- "Performance: SampCert outperforms diffprivlib by >2x for discrete Gaussians."
- "Deployed in AWS Clean Rooms Differential Privacy, a production AWS service."

## Strata (AWS)

- "Strata: extensible platform for formalizing language syntax and semantics. Built in Lean. Open source." (https://strata-org.github.io/Strata/)

## Waimea (AWS, Trainium compiler)

- "CompCert-style verified compiler for AWS Trainium, Amazon's custom AI accelerator chip. ~200,000 lines of Lean code."
- "Lean + Claude keeps the team in sync with hardware changes."

## Veil (verified distributed protocols)

- "16 distributed protocol case studies. All 16 verified. Ivy failed on 2. 87.5% verified in under 15 seconds."
- "The Rabia finding: while porting Rabia from Ivy + Rocq to Veil, they spotted an invariant discrepancy that went undetected across two separate tools."
- "Foundational: Veil's VCG is proven sound w.r.t. the specification language semantics."

## Other verified software / AI

- Anneal (Google): "developers write Lean specifications directly in Rust doc comments."; "Designed for AI agents: Anneal demonstrated that their AI (Antigravity) can author unsafe Rust code and prove its soundness."
- "In the AI era, writing specifications is a critical skill."
- Verina benchmark (Harmonic Aristotle): "96.8% resolution rate (160/189 Lean specifications proved). Found specification bugs in the benchmarks."
- Move borrow checker: "27 working days. Estimated 5-6 months without AI." "Claude (Opus 4.5/4.6) handled proof repair, pattern propagation, routine preservation cases."

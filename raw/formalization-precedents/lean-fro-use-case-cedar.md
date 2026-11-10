# Lean Powers Secure Software at AWS: Cedar's Journey with Verified Development

> Source: https://lean-lang.org/use-cases/cedar/
> Collected: 2026-11-10
> Published: Unknown


Lean Powers Secure Software at AWS: Cedar's Journey with Verified Development
In a significant endorsement of formal verification in production software, AWS scientist Emina Torlak and former AWS scientist Kesha Hietala have shared their success using Lean to verify the AWS open-source authorization policy language, Cedar.
From Mathematical Proofs to Software Security🔗
While Lean has established itself as a powerful tool for mathematicians formalizing complex proofs, AWS's Cedar team demonstrates that Lean is equally valuable for software verification. Their approach uses Lean to create formal models of Cedar's components and prove critical correctness and security properties.
The Cedar Verification Approach🔗
Cedar is an open-source authorization policy language that enables developers to express fine-grained permissions through policies separate from application logic. The Cedar runtime includes three core components: an evaluator that determines expression values, an authorizer that applies policies to authorization decisions, and a validator that prevents evaluation errors through policy type-checking.
AWS's "verification-guided development" process creates executable formal models in Lean alongside the production Rust implementation. These Lean models are approximately 10 times smaller than the production code, making them valuable both as verification targets and as clear, mathematical documentation of Cedar's behavior.
This dual-purpose approach provides mathematical certainty through formal proofs while enabling practical validation through differential testing. AWS generates millions of random inputs and verifies that both the Lean model and Rust implementation produce identical outputs. Lean's fast execution time of only 5 microseconds per test case, compared to Rust's 7 microseconds per test case, makes this extensive testing practical. No new Cedar version is released unless its model, proofs, and differential tests are current.
Benefits for Production Software🔗
Beyond the technical benefits, Cedar demonstrates several broader advantages of using Lean for production verification:
Accessible to software engineers: Writing models and proofs in Lean follows familiar programming paradigms, lowering the barrier to formal verification.
Minimal trust requirements: Lean's small trusted computing base means developers only need to trust Lean's minimal proof-checking kernel, not the entire toolchain.
Production-ready approach: AWS has fully incorporated this verification process into Cedar's development workflow, proving that formal verification can be practical for real-world software.
Learn More🔗
If you're interested in exploring how Lean can help verify your software:
Read the current Lean FRO roadmap for the development of Lean
Read the core Lean documentation
Read the full AWS Open Source Blog post on Cedar's use of Lean
Explore Cedar's Lean models on GitHub

# Verified Foundations for Differential Privacy (SampCert)

> Source: https://arxiv.org/abs/2412.01671 (PLDI 2025, https://doi.org/10.1145/3729294); code: https://github.com/leanprover/SampCert
> Collected: 2026-11-10
> Published: 2024-12-02

[...omitted: all except abstract and short excerpts on extraction/TCB...]

## Abstract

Differential privacy (DP) has become the gold standard for privacy-preserving data analysis, but implementing it correctly has proven challenging. Prior work has focused on verifying DP at a high level, assuming either that the foundations are correct or that a perfect source of random noise is available. However, the underlying theory of differential privacy can be very complex and subtle. Flaws in basic mechanisms and random number generation have been a critical source of vulnerabilities in real-world DP systems.

In this paper, we present SampCert, the first comprehensive, mechanized foundation for executable implementations of differential privacy. SampCert is written in Lean with over 12,000 lines of proof. It offers a generic and extensible notion of DP, a framework for constructing and composing DP mechanisms, and formally verified implementations of Laplace and Gaussian sampling algorithms. SampCert provides (1) a mechanized foundation for developing the next generation of differentially private algorithms, and (2) mechanically verified primitives that can be deployed in production systems. Indeed, SampCert's verified algorithms power the DP offerings of Amazon Web Services, demonstrating its real-world impact.

SampCert's key innovations include: (1) A generic DP foundation that can be instantiated for various DP definitions (e.g., pure, concentrated, Rényi DP); (2) formally verified discrete Laplace and Gaussian sampling algorithms that avoid the pitfalls of floating-point implementations; and (3) a simple probability monad and novel proof techniques that streamline the formalization. To enable proving complex correctness properties of DP and random number generation, SampCert makes heavy use of Lean's extensive Mathlib library, leveraging theorems in Fourier analysis, measure and probability theory, number theory, and topology.

## Excerpts

Extraction and Deployment. Our simple probabilistic language enables straightforward extraction of Lean code while minimizing the trusted computing base. Each of the four operators in our probabilistic language maps directly to a simple imperative statement, enabling easy extraction that is sufficiently performant for practical deployment.

[Section 4] [...] function interface (FFI), allowing us to compile and execute our DP mechanisms while adding only 57 lines of C++ to our trusted computing base. The second involves a translation from SLang to [Python] [...] benchmarks against the samplers in diffprivlib [...] we use the Python-extracted version of our sampling algorithms.

Note (collector): SampCert is a "verify-then-extract/deploy" precedent, not a "model-vs-implementation differential testing" precedent. Its key design move is a tiny monadic DSL (SLang: pure/bind/uniformPowerOfTwo/probWhile) with a denotational semantics, so that proofs and extraction share one definition.

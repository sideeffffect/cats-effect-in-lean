# Petr4: Formal Foundations for P4 Data Planes

> Source: https://www.cs.cornell.edu/~jnfoster/papers/petr4.pdf (POPL 2021, Proc. ACM Program. Lang. 5, POPL, Article 41, https://doi.org/10.1145/3434322)
> Collected: 2026-11-10
> Published: 2021-01 (POPL 2021)

Authors: Ryan Doenges, Mina Tahmasbi Arashloo, Santiago Bautista, Alexander Chang, Newton Ni, Samwise Parkinson, Rudy Peterson, Alaia Solko-Breslin, Amanda Xu, Nate Foster.

[...omitted: core calculus, interpreter design, proofs, full bug tables (Figs. 22-23), references...]

## Abstract

P4 is a domain-specific language for programming and specifying packet-processing systems. It is based on an elegant design with high-level abstractions like parsers and match-action pipelines that can be compiled to efficient implementations in software or hardware. Unfortunately, like many industrial languages, P4 has developed without a formal foundation. The P4 Language Specification is a 160-page document with a mixture of informal prose, graphical diagrams, and pseudocode, leaving many aspects of the language semantics up to individual compilation targets. The P4 reference implementation is a complex system, running to over 40KLoC of C++ code, with support for only a few targets. Clearly neither of these artifacts is suitable for formal reasoning about P4 in general.

This paper presents a new framework, called Petr4, that puts P4 on a solid foundation. Petr4 consists of a clean-slate definitional interpreter and a core calculus that models a fragment of P4. Petr4 is not tied to any particular target: the interpreter is parameterized over an interface that collects features delegated to targets in one place, while the core calculus overapproximates target-specific behaviors using non-determinism. We have validated the interpreter against a suite of over 750 tests from the P4 reference implementation, exercising our target interface with tests for different targets. We validated the core calculus with a proof of type-preserving termination. While developing Petr4, we reported dozens of bugs in the language specification and the reference implementation, many of which have been fixed.

## Evaluation (verbatim excerpts)

Parser and typechecker. We have imported 792 test cases from p4c for the parser and typechecker. These consist of "good" tests (those the typechecker should accept) and "bad" tests (those the typechecker should reject). Currently, Petr4's parser passes all 792 of these. The typechecker, on the other hand, passes 782 of these, with 10 failures due to the following issues:
- A bug in the grammar requiring an additional "lexer hack" only recently fixed in p4c.
- The @optional annotation for arguments, which Petr4 does not support.
- Type casts that discard significant bits of bitstrings should emit a warning, but do not have to fail. p4c's suite expects them to fail.
- p4c rejects programs that shadow names [...] whereas Petr4 is more permissive. The specification says the compiler "may provide a warning if multiple resolutions are possible for the same name" for some situations but does not require it to be a type error.
- [...]

Interpreter. Of the good checker tests, 121 are accompanied by corresponding stf files used to test the correctness of p4c's back end. [...] We currently pass 95 of these stf tests with 26 failures. Most of our failures (20 tests) are P4 programs written in architectures unimplemented by Petr4 [...] We also provide 40 of our own custom stf tests accumulated during test-driven development of the interpreter that address difficult edge cases of the language we felt the p4c suite did not sufficiently exercise.

In developing Petr4, we uncovered bugs in p4c, ambiguities in the informal P416 spec, and issues with p4c arising from choices it made to resolve these ambiguities. [...] All bugs have been reported to either the P416 specification repository or the p4c repository on Github.

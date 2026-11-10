# Comprehensive Formal Verification of an OS Microkernel (seL4)

> Source: https://trustworthy.systems/publications/nicta_full_text/7371.pdf (ACM TOCS 32(1), Article 2, Feb 2014, https://doi.org/10.1145/2560537)
> Collected: 2026-11-10
> Published: 2014-02

Authors: Gerwin Klein, June Andronick, Kevin Elphinstone, Toby Murray, Thomas Sewell, Rafal Kolanski, Gernot Heiser (NICTA and UNSW).

[...omitted: proof details, binary verification, security proofs, WCET, effort numbers, references...]

## Abstract

We present an in-depth coverage of the comprehensive machine-checked formal verification of seL4, a general-purpose operating system microkernel. We discuss the kernel design we used to make its verification tractable. We then describe the functional correctness proof of the kernel's C implementation and we cover further steps that transform this result into a comprehensive formal verification of the kernel: a formally verified IPC fastpath, a proof that the binary code of the kernel correctly implements the C semantics, a proof of correct access-control enforcement, a proof of information-flow noninterference, a sound worst-case execution time analysis of the binary, and an automatic initialiser for user-level systems that connects kernel-level access-control enforcement with reasoning about system behaviour. We summarise these results and show how they integrate to form a coherent overall analysis, backed by machine-checked, end-to-end theorems.

The seL4 microkernel is currently not just the only general-purpose operating system kernel that is fully formally verified to this degree. It is also the only example of formal proof of this scale that is kept current as the requirements, design and implementation of the system evolve over almost a decade. We report on our experience in maintaining this evolving formally verified code base.

## 2.2 Haskell prototype as executable specification (verbatim excerpts)

[...] It uses the functional programming language Haskell to provide a programming language for OS developers, while at the same time providing an artefact that can be automatically translated into the theorem proving tool and reasoned about.

[...] The central artefact is the Haskell prototype of the kernel. [...] It can be translated automatically into the theorem prover Isabelle/HOL to form an executable, design-level specification of the kernel. The abstract, high-level, functional specification of the kernel can be developed manually, concurrently and semi-independently, giving further feedback into the design process.

Already in very early development stages it is possible to link the Haskell prototype with hardware simulators such as QEMU. In this link, normal user-level execution is enabled by the simulator, while traps are passed to the kernel model which computes the result of the trap. This enables the developers to run and test user-level binary programs against early kernel API versions. [...]

We restrict ourselves to a subset of Haskell that can be automatically translated into the language of the theorem prover we use. For instance, we do not make any substantial use of laziness, make only restricted use of type classes, and we prove that all functions terminate.

While the Haskell prototype is an executable model and an implementation of the final design, it is not the final production kernel. [...] we manually re-implemented the model in the C programming language. [...] Eventually, when the process finishes, both specifications and C code are linked by proof. The original Haskell prototype is not part of the proof chain.

## Functional correctness caveat (verbatim)

A cynic might say, however, that an implementation proof only shows that the implementation has no more bugs than the specification contains. This is true to an extent: specifications that do not meet users' requirements are a universal hazard for formal verification projects. The best way to reduce the risk of this hazard is to prove further properties about the specification that formally encode user-requirements—that is, to prove that the specification, and thus the implementation, meet their stated requirements.

## 7.3 Bugs Found (verbatim)

The first refinement step led to some 300 changes in the abstract specification and 200 in the executable specification. About 50% of these changes relate to bugs in the associated algorithms or design, the rest were introduced for verification convenience. [...]

By the time the second refinement started, the kernel had been used by a number of internal student projects and the x86 port was underway. Those two activities uncovered 16 defects in the implementation before verification had started in earnest, the formal verification has uncovered another 144 defects and resulted in 54 further changes to the code to aid in the proof. None of the bugs found in the C verification stage were deep in the sense that the corresponding algorithm was flawed. This is because the C code was written according to a very precise, low-level specification which was already verified in the first refinement stage.

Algorithmic bugs found in the first stage were mainly missing checks on user supplied input, subtle side effects in the middle of an operation breaking global invariants, or overly strong assumptions about what is true during execution. The bugs discovered in the second proof from executable specification to C were mainly typos, misreading the specification, or failing to update all relevant code parts on specification changes.

Simple typos also made up a surprisingly large fraction of discovered bugs in the relatively well-tested executable specification in the first refinement proof, which suggests that normal testing may not only miss hard and subtle bugs, but also a larger number of simple, obvious faults than one could expect testing would identify. [...]

Other more interesting bugs found during the C implementation proof were missing exception case checking, and different interpretations of default values in the code. For example, the interrupt controller on ARM returns 0xFF to signal that no interrupt is active which is used correctly in most parts of the code, but in one place the check was against NULL instead.

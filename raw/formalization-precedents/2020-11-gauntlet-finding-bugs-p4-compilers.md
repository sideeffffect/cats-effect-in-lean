# Gauntlet: Finding Bugs in Compilers for Programmable Packet Processing

> Source: https://www.usenix.org/system/files/osdi20-ruffy.pdf (OSDI 2020)
> Collected: 2026-11-10
> Published: 2020-11 (OSDI 2020)

Authors: Fabian Ruffy, Tao Wang, Anirudh Sivaraman (NYU).

[...omitted: generator, semantics encoding, evaluation tables, references...]

## Abstract

Programmable packet-processing devices such as programmable switches and network interface cards are becoming mainstream. These devices are configured in a domain-specific language such as P4, using a compiler to translate packet-processing programs into instructions for different targets. As networks with programmable devices become widespread, it is critical that these compilers be dependable. This paper considers the problem of finding bugs in compilers for packet processing in the context of P4-16. We introduce domain-specific techniques to induce both abnormal termination of the compiler (crash bugs) and miscompilation (semantic bugs). We apply these techniques to (1) the open-source P4 compiler (P4C) infrastructure, which serves as a common base for different P4 back ends; (2) the P4 back end for the P4 reference software switch; and (3) the P4 back end for the Barefoot Tofino switch.

Across the 3 platforms, over 8 months of bug finding, our tool Gauntlet detected 96 new and distinct bugs (62 crash and 34 semantic), which we confirmed with the respective compiler developers. 54 have been fixed (31 crash and 23 semantic); the remaining have been assigned to a developer. Our bug-finding efforts also led to 6 P4 specification changes. We have open sourced Gauntlet at p4gauntlet.github.io and it now runs within P4C's continuous integration pipeline.

## Introduction (excerpt)

[Gauntlet uses three key ideas: random program generation, translation validation, and model-based testing.] Third, we use model-based testing to generate input-output test packets for P4 programs based on the semantics we had to develop for translation validation. [...] Testing for general-purpose languages is effective at generating inputs that provide sufficient path coverage by finding inputs satisfying path conditions. But without language semantics, determining the correct output for these test inputs is hard. By creating formal semantics for P4 for translation validation, we are able to generate both input and output test packets [...]

## Background: the oracle problem (verbatim)

A key challenge in compiler bug finding is the oracle problem. Given an input program to a compiler, the expected outcome (i.e., should it accept/reject the program and what should the output be?) is unclear unless one consults an all-knowing oracle. [...] In differential testing, given two compilers, which both receive the same input program, if compiler A's output (after compiling and running the program) differs from compiler B's output, there is a bug in one of them. [...] Metamorphic testing can serve a similar role as differential testing, especially when multiple compilers are not readily available [...] different input programs that are expected to produce the same compiler output are fed to the same compiler. [...] Translation validation is a bug-finding technique that converts the program before and after a compiler optimization pass into a logical formula and checks if both programs/formulas are equivalent using a constraint solver.

## Specification changes (verbatim excerpts)

Some of our bug reports kicked off larger discussions and changes around the P4 language specification. Our bug reports and questions have led to at least 6 distinct specification changes. [...] Another prominent example was caused by ambiguity in the specification. [...] the RemoveActionParameters compiler pass moved the statement [...] after the exit statement, because the assumption was that exits called within functions ignores the copy-in/copy-out semantics. We instead interpreted exit statements to still respect copy-in/copy-out semantics and caught the discrepancy. [...] We filed this as a concern with the open-source community and our interpretation was deemed reasonable, which required a specification update. The corresponding compiler changes resulted in at least 3 new bugs, which we detected and filed.

## 7.4 Lessons Learned (verbatim excerpts)

P4C's nanopass architecture, which factors the compiler into a large number of "thin" passes, helps with bug fixing, especially for semantic bugs that were narrowed down to one pass by translation validation. [...] We also observed that almost all crash bugs were assertion violations where an invariant was violated in a particular compiler pass due to an incorrect or absent compiler transformation from a previous pass. In the absence of such assertions, these crash bugs could have easily manifested as semantic bugs that are harder to detect.

Reporting bugs. This project would not have been possible without the responsiveness and receptiveness of the P4 community. Our questions, concerns, and bug reports were answered within a day and in great detail. [...] the official binary of the Tofino compiler updates less frequently than P4C [...] Hence, we would trigger the same bugs repeatedly in our testing until a new Tofino compiler version with a bug fix was released.

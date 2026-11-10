# CakeML: A Verified Implementation of ML

> Source: https://cakeml.org/popl14.pdf (POPL 2014)
> Collected: 2026-11-10
> Published: 2014-01

Authors: Ramana Kumar, Magnus O. Myreen, Michael Norrish, Scott Owens.

[...omitted: everything except abstract...]

## Abstract

We have developed and mechanically verified an ML system called CakeML, which supports a substantial subset of Standard ML. CakeML is implemented as an interactive read-eval-print loop (REPL) in x86-64 machine code. Our correctness theorem ensures that this REPL implementation prints only those results permitted by the semantics of CakeML. Our verification effort touches on a breadth of topics including lexing, parsing, type checking, incremental and dynamic compilation, garbage collection, arbitrary-precision arithmetic, and compiler bootstrapping.

Our contributions are twofold. The first is simply in building a system that is end-to-end verified, demonstrating that each piece of such a verification effort can in practice be composed with the others, and ensuring that none of the pieces rely on any over-simplifying assumptions. The second is developing novel approaches to some of the more challenging aspects of the verification. In particular, our formally verified compiler can bootstrap itself: we apply the verified compiler to itself to produce a verified machine-code implementation of the compiler. Additionally, our compiler proof handles diverging input programs with a lightweight approach based on logical timeout exceptions. The entire development was carried out in the HOL4 theorem prover.

Note (collector): CakeML is a "verified implementation" precedent (the language is defined by its own formal semantics, written in Lem/HOL4), not a "model an existing implementation and find bugs in it" precedent. Its relevance is the technique of handling divergence with a logical clock/fuel ("logical timeout exceptions"), which a Lean model of an effect runtime will also need.

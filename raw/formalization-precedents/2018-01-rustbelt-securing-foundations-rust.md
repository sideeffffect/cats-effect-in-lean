# RustBelt: Securing the Foundations of the Rust Programming Language

> Source: https://plv.mpi-sws.org/rustbelt/popl18/paper.pdf (POPL 2018, Proc. ACM Program. Lang. 2, POPL, Article 66, https://doi.org/10.1145/3158154)
> Collected: 2026-11-10
> Published: 2018-01

Authors: Ralf Jung, Jacques-Henri Jourdan, Robbert Krebbers, Derek Dreyer (MPI-SWS / TU Delft).

[...omitted: λRust, Iris logical relation, library proofs, references...]

## Abstract

Rust is a new systems programming language that promises to overcome the seemingly fundamental tradeoff between high-level safety guarantees and low-level control over resource management. Unfortunately, none of Rust's safety claims have been formally proven, and there is good reason to question whether they actually hold. Specifically, Rust employs a strong, ownership-based type system, but then extends the expressive power of this core type system through libraries that internally use unsafe features. In this paper, we give the first formal (and machine-checked) safety proof for a language representing a realistic subset of Rust. Our proof is extensible in the sense that, for each new Rust library that uses unsafe features, we can say what verification condition it must satisfy in order for it to be deemed a safe extension to the language. We have carried out this verification for some of the most important libraries that are used throughout the Rust ecosystem.

## Introduction (verbatim excerpts)

[...] adopting a simplified memory model featuring only non-atomic and sequentially consistent atomic operations. Nevertheless, λRust is realistic enough that studying it led us to uncover a previously unknown soundness bug in Rust itself [Jung 2017].

Our core contribution is then to develop an extensible soundness proof for λRust. The basic idea is to build a semantic model of the language—in particular, a logical relation. [...]

Note (collector, from general knowledge, not verified in this session): the bug referenced as [Jung 2017] is the `MutexGuard<T>: Sync` soundness bug (Rust issue #41622), where MutexGuard was Sync whenever T was Send, allowing data races; found while proving the Mutex library sound. Uncertain detail; check the issue before citing.

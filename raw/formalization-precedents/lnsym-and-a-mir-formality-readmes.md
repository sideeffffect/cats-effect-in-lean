# LNSym README (Lean Armv8 native-code symbolic simulator)

> Source: https://github.com/leanprover/LNSym (README.md)
> Collected: 2026-11-10
> Published: Unknown (living document)

## LNSym: Native Code Symbolic Simulator in Lean
[![CI](https://github.com/leanprover/LNSym/actions/workflows/ci.yml/badge.svg)](https://github.com/leanprover/LNSym/actions/workflows/ci.yml)

LNSym is a symbolic simulator for Armv8 machine-code programs.

Please see the [LICENSE](./LICENSE) file for LNSym's licensing and
[CONTRIBUTING.md](./CONTRIBUTING.md) for external contribution
guidelines.

### Prerequisites

Install Lean4 and your preferred editor's plug-in on your machine by
following [these
instructions](https://leanprover-community.github.io/get_started.html).

### Build Instructions

Run `make` at the top-level of LNSym to fetch the Lean4 dependencies,
build this library (including the proofs), and run conformance
testing. Note that if you are not on an Aarch64 machine, conformance
testing will be skipped.

The default `make` command corresponds to the following invocation:

```make all VERBOSE=--verbose NUM_TESTS=20```

#### Other Makefile targets

`clean`: remove build outputs.

`clean_all`: `clean` plus remove Lean dependencies and
    all benchmarking and profiling data.

`specs`: [run under `all`] builds only the specifications of
native-code programs of interest.

`proofs`: [run under `all`] builds only the proofs.

`tests`: [run under `all`] builds concrete tests.

`cosim`: [run under `all`] perform conformance testing.

`awslc_elf`: perform ELF loading tests for AWS-LC.

`benchmarks`: run benchmarks for the symbolic simulator.

`profiler`: run a single round of each benchmark, with the profiler enabled

#### Makefile variables that can be passed in at the command line

`VERBOSE`: Verbose mode; prints disassembly of the instructions being
 tested. Default: on.

`NUM_TESTS`: Number of random tests/instruction class. Default: 20.

### Directory Overview

- `Arm`: Formalization of the Armv8 Aarch64 ISA
- `Specs`: Specifications of algorithms of interest
- `Proofs`: Proofs of Arm native-code programs
- `Tests`: Concrete tests of Arm native-code programs


# a-mir-formality README

> Source: https://github.com/rust-lang/a-mir-formality (README.md)
> Collected: 2026-11-10

## a-mir-formality

This repository is an early-stage experimental project that aims to be a complete, authoritative formal model of the [Rust MIR](https://rustc-dev-guide.rust-lang.org/mir/index.html).
Presuming these experiments bear fruit, the intention is to bring this model into Rust as an RFC
and develop it as an official part of the language definition.

### Quickstart guide

Like any Rust project:

* Clone
* `cargo test --all`

### Documentation
Check out [a-mir-formality book](https://rust-lang.github.io/a-mir-formality/intro.html) for an overview and introduction to `a-mir-formality`.

### Layers of formality

Formality is structured into several layers:

* **formality-macros**: Defines procedural macros like `#[term]` as well as various derives.
  These are used to generate the boilerplate code for parsing, pretty printing, folding, etc.
* **formality-core**: Language-independent foundation for formal semantics — variable binding,
  the judgment/proof system, fixed-point computation, and collections.
* **formality-rust**: The Rust-specific model. Contains `grammar/` (AST definitions),
  `check/` (semantic checking, with `check_all_crates` as the entry point),
  and `prove/` (trait solving and type normalization).

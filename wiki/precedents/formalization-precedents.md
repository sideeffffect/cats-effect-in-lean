# Formalization precedents (pre-AI era and industry)

> Sources: Cutler et al. (Cedar, FSE'24), 2024-07-01; Cedar OOPSLA, 2024-03-07; AWS / Lean FRO blogs 2024; Cedar RFC 0032, 2023-10-12; AWS authorizer ICSE'25, 2025-04; Newcombe et al., 2014; Brooker & Desai, 2025; SampCert, 2024-12; LNSym / a-mir-formality READMEs; KJS 2015; K-Java 2015; KEVM 2018; JSCert 2014; WasmCert 2018/2021; Csmith 2011; CakeML 2014; seL4 2014; RustBelt 2018; Aeneas 2022; Petr4 2021; Gauntlet 2020; Reid (ARM) 2016; Netsem 2018; SibylFS 2015; MongoDB 2020; TLA+ trace validation 2024; de Moura ETAPS 2026
> Raw: [Cedar FSE'24](../../raw/formalization-precedents/2024-07-01-how-we-built-cedar-verification-guided-approach.md); [Cedar FSE'24 (DRT section copy)](../../raw/lean-tooling/2024-07-01-how-we-built-cedar-verification-guided.md); [AWS Lean blog (copy)](../../raw/lean-tooling/aws-blog-lean-into-verified-software-development.md); [Cedar OOPSLA](../../raw/formalization-precedents/2024-03-07-cedar-oopsla-language-paper.md); [AWS Lean blog](../../raw/formalization-precedents/2024-04-08-aws-lean-into-verified-software-development.md); [Lean FRO Cedar](../../raw/formalization-precedents/lean-fro-use-case-cedar.md); [Cedar Dafny DRT](../../raw/formalization-precedents/2023-05-10-amazon-science-how-we-built-cedar-dafny-drt.md); [Cedar RFC 0032](../../raw/formalization-precedents/2023-10-12-cedar-rfc-0032-port-formalization-to-lean.md); [Cedar POPL SRC](../../raw/formalization-precedents/2024-01-popl-src-lean-formalization-of-cedar.md); [cedar-spec README](../../raw/formalization-precedents/cedar-spec-and-drt-readme.md); [AWS authorizer](../../raw/formalization-precedents/2025-04-formally-verified-cloud-scale-authorization.md); [Brooker & Desai](../../raw/formalization-precedents/2025-brooker-desai-systems-correctness-practices-at-aws.md); [Newcombe](../../raw/formalization-precedents/2014-09-29-newcombe-use-of-formal-methods-at-aws.md); [SampCert](../../raw/formalization-precedents/2024-12-02-sampcert-verified-foundations-differential-privacy.md); [LNSym / a-mir-formality](../../raw/formalization-precedents/lnsym-and-a-mir-formality-readmes.md); [de Moura ETAPS](../../raw/formalization-precedents/2026-04-15-de-moura-lean-unified-platform-etaps-industry.md); [JSCert](../../raw/formalization-precedents/2014-01-jscert-trusted-mechanised-javascript-spec.md); [KJS](../../raw/formalization-precedents/2015-06-kjs-complete-formal-semantics-javascript.md); [K-Java](../../raw/formalization-precedents/2015-01-k-java-complete-semantics-java.md); [KEVM](../../raw/formalization-precedents/2018-07-kevm-complete-formal-semantics-evm.md); [WasmCert](../../raw/formalization-precedents/2018-01-watt-mechanising-verifying-webassembly-spec.md); [Two Wasm mechanisations](../../raw/formalization-precedents/2021-11-two-mechanisations-of-webassembly-1-0.md); [Csmith](../../raw/formalization-precedents/2011-06-csmith-finding-understanding-bugs-c-compilers.md); [CakeML](../../raw/formalization-precedents/2014-01-cakeml-verified-implementation-of-ml.md); [seL4](../../raw/formalization-precedents/2014-02-sel4-comprehensive-formal-verification-microkernel.md); [RustBelt](../../raw/formalization-precedents/2018-01-rustbelt-securing-foundations-rust.md); [Aeneas](../../raw/formalization-precedents/2022-06-14-aeneas-rust-verification-functional-translation.md); [Petr4](../../raw/formalization-precedents/2021-01-petr4-formal-foundations-p4.md); [Gauntlet](../../raw/formalization-precedents/2020-11-gauntlet-finding-bugs-p4-compilers.md); [ARM (Reid)](../../raw/formalization-precedents/2016-10-reid-trustworthy-specifications-arm-v8.md); [Netsem](../../raw/formalization-precedents/2018-10-netsem-engineering-with-logic-tcp-test-oracle.md); [SibylFS](../../raw/formalization-precedents/2015-10-sibylfs-formal-spec-oracle-based-testing-posix.md); [MongoDB](../../raw/formalization-precedents/2020-05-extreme-modelling-in-practice-mongodb.md); [TLA+ trace validation](../../raw/formalization-precedents/2024-04-24-validating-traces-distributed-programs-tla.md)

## Overview

Before the 2026 agent projects, many teams built executable formal models of real languages and systems and compared them with the implementation. The common result: proofs and differential testing find bugs in the spec, the model, the tests **and** the implementation. Most early mismatches are model bugs. For concurrency, the model must be "loose" (accept a set of traces). Overall confidence 0.8 (weakest: KEVM, Ferrocene, RustBelt details).

## Cedar (AWS) — closest analogue

- Small readable **Lean** models of evaluator, authorizer, validator; ~10x smaller than the Rust code; proofs ≈ 3.4x model size. Moved from Dafny to Lean in 2023–24 (better for deep proofs, ~2x faster checking, fast runtime, small kernel).
- **Differential random testing (DRT)**: cargo-fuzz feeds the same inputs to Lean (called from Rust via FFI, ~5 µs per test, ~100M tests/night) and Rust; 6 h per target daily. Property tests cover parts with no model.
- Bugs: proofs found 4 (one non-termination found only while proving termination); DRT + PBT found 21; several were **model** bugs; one mismatch was a design flaw (string length semantics) and the feature was dropped. 9 bugs were missed (rare triggers, generators never produce malformed input, untested API).
- Lessons: **type-directed generators** (schema → data → policies), else tests hit only error paths; line coverage misled (35.5% of generated conditions were literal `true`/`false`); minimized fuzz inputs became the CI regression suite; release blocked unless model, proofs and DRT are current.

## Other AWS

- **Authorizer rewrite (Dafny)**: executable spec tested against old unit tests, then fuzzed (13 mismatches, all spec fixes), then a year of shadow-running on production traffic (7 more spec gaps, 0 tool/proof bugs). "Be sure your proofs consider the right specification."
- **TLA+ (Newcombe 2014)**: found design bugs with 35-step traces; no link from model to code then. **P / PObserve**, deterministic simulation (shuttle, turmoil) close that gap now. **Outdated claim**: Brooker & Desai 2025 say Cedar is "built in Dafny"; RFC 0032 and the 2024 papers show the model moved to Lean.
- **SampCert** (Lean, compiled to production, 57 lines trusted C++) and **LNSym** (Armv8 cosim against hardware).

## Language semantics

- **KJS** passes all 2,782 core test262 tests. Line-by-line mirroring of the standard allowed *semantic coverage*: 17 rules were never run by test262; new tests for 11 found bugs in V8, WebKit, SpiderMonkey; 6 were unreachable (flaws in the standard).
- **K-Java**: test-first, 840 tests vs JDK, about half the project time.
- **JSCert/JSRef**: two trust paths — rules read side by side with the standard, and a proven interpreter run on test262. Model and interpreter written by **different people**. Bugs found everywhere, including the test suite.
- **WasmCert**: proving type soundness found real bugs in the official spec; interpreter passes ~17,810 official tests.
- **Csmith**: 325+ compiler bugs; CompCert's proven middle end had none (bugs only in unproven parts). Lesson: verification does not replace testing; reports need small reproducers.
- **seL4**: proofs drove ~300 abstract-spec and ~200 executable-spec changes plus 144 C defects. "No more bugs than the specification contains."
- **RustBelt** found a std soundness bug (likely `MutexGuard: Sync`, unverified). **Aeneas** translates real Rust into Lean (opposite of hand-written models).
- **Petr4 / Gauntlet** (P4): dozens of spec/compiler bugs; 96 compiler bugs; 6 spec changes from ambiguities.
- **ARM (Reid)**: "testing specifications is very much a two-way street" — bugs in spec, tests, simulator, English text; some tests relied on undefined behaviour.

## Nondeterminism: the key lessons for CE

- **Netsem (TCP, HOL4)**: a nondeterministic model must be a loose spec — a relation accepting a set of traces; a checker asks if an observed trace is allowed. ~1,000 traces took 2,500 CPU-hours. Key lesson: make the implementation **log its internal choices** so checking is a total function.
- **SibylFS (POSIX)**: ~6 orders of magnitude faster by isolating nondeterminism: the model lists all possible next states and the observed return value picks one. The model is configurable for known, intended variants.
- **MongoDB 2020**: full-server trace checking failed (model too abstract; first deviation after 4 of 2,687 steps). Model-based test generation for a ~1 KLOC function succeeded (4,913 tests, 100% branch coverage, found a non-termination bug).
- **TLA+ trace validation 2024**: every mismatch was one of: implementation shortcut (real bug), spec too strict, atomicity mismatch.

## See Also

- [python-formalization](python-formalization.md)
- [julia-in-lean](julia-in-lean.md)
- [Differential testing](../methodology/differential-testing.md)
- [Lessons for Cats Effect in Lean](../methodology/lessons-for-cats-effect.md)

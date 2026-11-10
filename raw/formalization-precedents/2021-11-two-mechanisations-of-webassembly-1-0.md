# Two Mechanisations of WebAssembly 1.0 (WasmCert-Isabelle and WasmCert-Coq)

> Source: https://www.cl.cam.ac.uk/~jp622/two_wasm.pdf (FM 2021, LNCS 13047, pp. 61-79, https://doi.org/10.1007/978-3-030-90870-6_4)
> Collected: 2026-11-10
> Published: 2021-11 (FM 2021)

Authors: Conrad Watt, Xiaojia Rao, Jean Pichon-Pharabod, Martin Bodin, Philippa Gardner.

[...omitted: semantics, soundness proof, instantiation details, related work...]

## Abstract

WebAssembly (Wasm) is a new bytecode language supported by all major Web browsers, designed primarily to be an efficient compilation target for low-level languages such as C/C++ and Rust. It is unusual in that it is officially specified through a formal semantics. An initial draft specification was published in 2017, with an associated mechanised specification in Isabelle/HOL published by Watt that found bugs in the original specification, fixed before its publication. The first official W3C standard, WebAssembly 1.0, was published in 2019. Building on Watt's original mechanisation, we introduce two mechanised specifications of the WebAssembly 1.0 semantics, written in different theorem provers: WasmCert-Isabelle and WasmCert-Coq. Wasm's compact design and official formal semantics enable our mechanisations to be particularly complete and close to the published language standard. We present a high-level description of the language's updated type soundness result, referencing both mechanisations. We also describe the current state of the mechanisation of language features not previously supported: WasmCert-Isabelle includes a verified executable definition of the instantiation phase as part of an executable verified interpreter; WasmCert-Coq includes executable parsing and numeric definitions as on-going work towards a more ambitious end-to-end verified interpreter which does not require an OCaml harness like WasmCert-Isabelle.

## Section 4 (verbatim excerpt)

[...] By replacing the executable definition with our verified interpreter, we eliminate a significant amount of Watt's original unverified OCaml harness. [...]

We also validate the WasmCert-Isabelle interpreter against the official Wasm 1.0 end-to-end test suite, containing ~17,810 tests, which we pass without error. Testing the Coq-extracted interpreter end-to-end is left for future work.

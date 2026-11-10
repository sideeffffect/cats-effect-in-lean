# KEVM: A Complete Formal Semantics of the Ethereum Virtual Machine

> Source: https://doi.org/10.1109/CSF.2018.00022 (CSF 2018; abstract via Semantic Scholar API); repo README https://github.com/runtimeverification/evm-semantics
> Collected: 2026-11-10
> Published: 2018-07 (CSF 2018 / FLoC)

Authors: Everett Hildenbrandt, Manasvi Saxena, Nishant Rodrigues, Xiaoran Zhu, Philip Daian, Dwight Guth, Brandon Moore, Daejun Park, Yi Zhang, Andrei Stefanescu, Grigore Roşu.

[...omitted: full paper not accessible (IEEE closed access); only abstract and README test section kept...]

## Abstract

A developing field of interest for the distributed systems and applied cryptography communities is that of smart contracts: self-executing financial instruments that synchronize their state, often through a blockchain. One such smart contract system that has seen widespread practical adoption is Ethereum, which has grown to a market capacity of 100 billion USD and clears an excess of 500,000 daily transactions. Unfortunately, the rise of these technologies has been marred by a series of costly bugs and exploits. Increasingly, the Ethereum community has turned to formal methods and rigorous program analysis tools. This trend holds great promise due to the relative simplicity of smart contracts and bounded-time deterministic execution inherent to the Ethereum Virtual Machine (EVM). Here we present KEVM, an executable formal specification of the EVM's bytecode stack-based language built with the K Framework, designed to serve as a solid foundation for further formal analyses. We empirically evaluate the correctness and performance of KEVM using the official Ethereum test suite. To demonstrate the usability, several extensions of the semantics are presented. and two different-language implementations of the ERC20 Standard Token are verified against the ERC20 specification. These results are encouraging for the executable semantics approach to language prototyping and specification.

## README: Running Tests (verbatim)

To execute tests from the [Ethereum Test Set], the submodule needs to be fetched first.

    git submodule update --init --recursive  -- tests/ethereum-tests

The tests are run using the supplied `Makefile`.

- `make test`: All of the quick tests.
- `make test-all`: All of the quick and slow tests.
- `make test-vm`: VMTests from the [Ethereum Test Set].
- `make test-bchain`: Subset of BlockchainTests from the [Ethereum Test Set].
- `make test-proof`: Proofs from the [Verified Smart Contracts].
- `make test-interactive`: Tests of the `kevm` command.

README: "There are two backends of K available: LLVM for concrete execution and Haskell for symbolic execution."

Note (collector, unverified from memory): the CSF paper reports KEVM passing the full VMTests and GeneralStateTests of the official suite (tens of thousands of tests) with performance within roughly an order of magnitude of the reference C++ client. Exact numbers not verified in this session.

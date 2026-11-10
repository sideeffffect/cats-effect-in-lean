# Validating Traces of Distributed Programs Against TLA+ Specifications

> Source: https://arxiv.org/abs/2404.16075 (iFM 2024)
> Collected: 2026-11-10
> Published: 2024-04-24 (arXiv v1; date approximate)

Authors: Horatiu Cirstea, Markus A. Kuppe, Benjamin Loillier, Stephan Merz.

[...omitted: instrumentation API, TLA+ trace-spec operators, two-phase commit running example, references...]

## Abstract

TLA+ is a formal language for specifying systems, including distributed algorithms, that is supported by powerful verification tools. In this work we present a framework for relating traces of distributed programs to high-level specifications written in TLA+. The problem is reduced to a constrained model checking problem, realized using the TLC model checker. Our framework consists of an API for instrumenting Java programs in order to record traces of executions, of a collection of TLA+ operators that are used for relating those traces to specifications, and of scripts for running the model checker. Crucially, traces only contain updates to specification variables rather than full values, and developers may choose to trace only certain variables. We have applied our approach to several distributed programs, detecting discrepancies between the specifications and the implementations in all cases. We discuss reasons for these discrepancies, best practices for instrumenting programs, and how to interpret the verdict produced by TLC.

## 4.3 Analyzing discrepancies (verbatim)

We have used trace validation for several case studies: besides the two-phase commit protocol presented here, we experimented with a distributed key-value store ensuring snapshot isolation [...], the distributed termination detection algorithm EWD 998 [...], two existing implementations of the Raft consensus algorithm, and the Microsoft Confidential Consortium Framework. In all cases, trace validation quickly identified executions of the distributed implementations that could not be matched to the high-level specification. In the following, we identify several reasons for such discrepancies.

Implementation shortcuts. The implementation of the Two-Phase Commit protocol could use a counter to store the number (rather than the identities) of the RMs from which a "Prepared" message was received [...] if some RM resends the "Prepared" message due to a timeout, the TM might count it twice and then commit prematurely. We found this kind of implementation error to be reliably detected using trace validation.

Overly strict specification. The implementation of the token-based distributed termination detection algorithm EWD 998 allowed a node to send an ordinary (non-token) message to itself, which was ruled out in the specification. Again, trace validation quickly discovered this mismatch, which can be resolved by adapting either the specification or the implementation.

Mismatch of the grain of atomicity. Mainstream programming languages do not provide atomic transactions encapsulating several updates, so the choice of when to log an action corresponding to the TLA+ specification requires consideration. Transitions that modify shared state such as sending or receiving network messages, acquiring or releasing global locks or committing state to stable storage are natural candidates. [...]

It frequently happens that the implementation takes steps that are invisible at the level of the abstract state space. [...] The fact that TLA+ specifications are insensitive to stuttering steps is helpful in such situations.

An implementation may also combine two or more separate steps of the TLA+ specification into a single transition. [...] one may instrument the implementation such that it logs two transitions in succession. Alternatively, one may add an explicit disjunct to the next-state relation of the TLA+ specification used for trace validation, making use of the TLA+ action composition operator A ∘ B [...] Doing so is a way of explicitly documenting optimizations of the implementation with respect to the specification.

## 4.4 Experience (verbatim excerpts)

The most significant case study to which we applied trace validation occurred in the context of reverse engineering a formal specification for a Raft-inspired consensus algorithm implemented within the Confidential Consortium Framework (CCF). The starting point was a specification written after analyzing the source code, which was then corrected and amended through trace validation based on an existing test suite that exercises non-trivial system behavior. Model checking the resulting specification revealed serious violations of key safety properties. The counterexamples obtained in this way were translated into new tests, which confirmed previously unknown problems with the implementation. After addressing these issues at the specification level, corresponding updates to the implementation were made. To ensure ongoing consistency between the specification and its implementation, trace validation is now part of CCF's continuous integration pipeline.

## 4.5 Implementation aspects (excerpt)

[...] only a subset of variables needs to be included in the trace [...] Less information in the trace increases the potential degree of non-determinism in the trace specification and may lead to a combinatorial explosion during model checking. [...] TLC's default breadth-first search (BFS) ensures shortest-length counter-examples and is most informative for debugging.

## Conclusion (excerpt)

[...] Our purpose with this approach is to identify discrepancies that can be analyzed using the TLC model checker in order to determine if they are due to an error in the implementation, a restrictive specification, or an artefact due to a mismatch in the grains of atomicity. Although the technique does not provide formal correctness guarantees, mainly due to the necessary decisions on when to log an event corresponding to an atomic action, we have found it to be surprisingly effective for finding serious bugs in implementations that had previously been validated using traditional quality assurance techniques.

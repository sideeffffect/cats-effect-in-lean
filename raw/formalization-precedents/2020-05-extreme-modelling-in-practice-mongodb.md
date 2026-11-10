# eXtreme Modelling in Practice (MongoDB)

> Source: https://www.vldb.org/pvldb/vol13/p1346-davis.pdf (PVLDB 13(9): 1346-1358, 2020, https://doi.org/10.14778/3397230.3397233)
> Collected: 2026-11-10
> Published: 2020-05 (PVLDB vol. 13 no. 9; exact date uncertain)

Authors: A. Jesse Jiryu Davis, Max Hirschhorn, Judah Schvimer (MongoDB).

[...omitted: background on TLA+, tracing implementation details, TLA+ listings, references...]

## Abstract

Formal modelling is a powerful tool for developing complex systems. At MongoDB, we use TLA+ to model and verify multiple aspects of several systems. Ensuring conformance between a specification and its implementation can add value to any specification; it can avoid transcription errors, prevent bugs as a large organization rapidly develops the specified code, and even keep multiple implementations of the same specification in sync. In this paper, we explore model-based testing as a tool for ensuring specification-implementation conformance. We attempted two case studies: model-based trace-checking (MBTC) in the MongoDB Server's replication protocol and model-based test-case generation (MBTCG) in MongoDB Realm Sync's operational transformation algorithm. We found MBTC to be impractical for testing that the Server conformed to a highly abstract specification. MBTCG was highly successful for Realm Sync, however. We analyze why one technique succeeded and the other failed, and advise future implementers making similar attempts at model-based testing.

## Introduction (excerpt)

[...] software engineers in industry are often skeptical of a model's value unless it is shown to match the implementation, due to the risk of transcription bugs; that is, logic errors in the implementation of the specification.

## 4.2.2 Implementation discrepancies (verbatim excerpts)

As soon as we checked our tests' execution traces against RaftMongo.tla, we encountered violations.

Arbiters: [...] RaftMongo.tla does not model arbiters and we did not implement tracing for them; arbiters crash when tracing is enabled. It was trivial to skip tests that use arbiters, but this gave us a hint that our specification was an oversimplification of the real system, and would not be suitable for MBTC.

Initial sync: [...] Trace-checking the output of rollback fuzzer immediately reproduced a known violation of the specification [...] When we first wrote RaftMongo.tla we modelled the correct behavior. We did not have MBTC in mind, so we deliberately wrote an idealized specification with the intention to eventually bring our implementation into conformance. This violation increased our confidence in trace-checking. [...] However, it made our MBTC project nearly worthless: the violation came only 4 steps from the trace's start and left the remaining 2,683 steps unchecked.

To permit deeper trace-checking, we could 1) fix the implementation of initial sync sooner than planned, 2) avoid triggering the non-conforming behavior in testing, 3) update the specification to match the flawed implementation, or 4) post-process the traces to simulate a conformant implementation.

Term: Other discrepancies required solution 3, updating the specification. [...] RaftMongo.tla originally modelled the election term as a single global number known by all nodes. In reality, election terms are gossiped among nodes and each learns the new term at a different time. MBTC required us to make the specification more complex to match reality. [...] over the course of our research we added or changed 252 of the 345 lines of TLA+ in RaftMongo.tla, costing three weeks of effort.

Copying the oplog: In several cases we chose solution 4, post-processing the logs to simulate conformance. [...] Such an intrusive modification made us concerned that a mistake in the Python script might mask a harmful transcription bug in the MongoDB Server code.

Each discrepancy we discovered through MBTC required us to judge which of the four solutions to employ. Ideally, when an organization practices eXtreme Modelling, they resolve each MBTC failure either by fixing the implementation or, if the failure is not a bug, by updating the specification. In practice, we often concluded it was expedient to work around violations. [...] Unfortunately, our choices were based on estimates and speculation.

[State space:] The limited changes we made to RaftMongo.tla increased the state space from 42,034 states to 371,368, and model-checking time from 2 seconds to 14 minutes.

## 5 MBTCG for Realm Sync OT (verbatim excerpts)

In addition to detecting safety violations caused by transcription errors, the TLC model checker also encountered a StackOverflowError due to a case in the merge rule for the ArraySwap and ArrayMove operations leading the merge function to never terminate. This issue was found to also exist in the C++ code; the bug had faithfully been transcribed from C++ to TLA+. It was surprising to discover a bug in the C++ implementation due to the maturity of the product and the amount of randomized testing it had undergone. The discovery of this issue became the deciding factor to not support a dedicated ArraySwap operation [...]

For an initial array containing three elements and with three clients each performing a single operation, the Golang program generated 4,913 C++ test cases. [...] The 36 handwritten C++ test cases covered 18 of the 86 branches (21%) within the merge rules for the array-based operations. [...] The fuzz-transform test executable, which uses the AFL fuzzer to produce randomized inputs [...] covered 79 of 86 branches (92%) after approximately 8 million total executions. The generated C++ test cases covered all 86 branches (100%).

## 6 Conclusions (verbatim excerpts)

MBTC was impractical for our system because we lacked a close correspondence between the MongoDB Server implementation and RaftMongo.tla. [...] In the absence of a close correspondence, MBTC requires significant post-processing of traces. [...] Our trace-logging code was hampered by the Server's intra-process concurrency control. Future engineers in our situation should consider logging only those state variables the implementation can access at the moment it executes a state transition. [...] Bugs in post-processing could mask implementation bugs, so it is critical to think about what kinds of bugs the MBTC effort aims to catch and what kinds are targeted by other tests.

An avenue we did not explore is to generate traces from implementation modules running in a unit test framework, rather than an integration test of the entire multi-process system, as we did. Modules are simpler than the whole, and non-determinism can be more easily eliminated, for example by simulating the system clock. [...]

MBTCG succeeded because the specification was deliberately written with a close correspondence to the implementation, via direct transcription. The implementation under test was a self-contained function with defined inputs and output, of approximately one thousand lines of code. [...]

When MBTCG is possible, and when the state space is not too large, MBTCG is the gold standard of ensuring specification-implementation conformance. If the state space becomes too large though, or if any individual test case would take too long to run, we must start sampling the space, and MBTC can be effective. MBTC is also a good approach when the implementation's behavior is non-deterministic and cannot be forced to execute specific test sequences.

# Use of Formal Methods at Amazon Web Services

> Source: https://lamport.azurewebsites.net/tla/formal-methods-amazon.pdf (later published as "How Amazon Web Services Uses Formal Methods", CACM 58(4), April 2015)
> Collected: 2026-11-10
> Published: 2014-09-29

Authors: Chris Newcombe, Tim Rath, Fan Zhang, Bogdan Munteanu, Marc Brooker, Michael Deardeuff (Amazon.com).

[...omitted: sections on TLA+ language intro, education, alternatives, related work, references...]

## Opening (verbatim)

Since 2011, engineers at Amazon Web Services (AWS) have been using formal specification and model checking to help solve difficult design problems in critical systems. This paper describes our motivation and experience, what has worked well in our problem domain, and what has not.

[...] We use deep design reviews, code reviews, static code analysis, stress testing, fault-injection testing, and many other techniques, but we still find that subtle bugs can hide in complex concurrent fault-tolerant systems. One reason for this problem is that human intuition is poor at estimating the true probability of supposedly 'extremely rare' combinations of events in systems operating at a scale of millions of requests per second.

That human fallibility means that some of the more subtle, dangerous bugs turn out to be errors in design; the code faithfully implements the intended design, but the design fails to correctly handle a particular 'rare' scenario. We have found that testing the code is inadequate as a method to find subtle errors in design, as the number of reachable states of the code is astronomical.

## Table: applying TLA+ to components (summary)

- S3 fault-tolerant low-level network algorithm (804 lines PlusCal): Found 2 bugs. Found further bugs in proposed optimizations.
- S3 background redistribution of data (645 PlusCal): Found 1 bug, and found a bug in the first proposed fix.
- DynamoDB replication & group-membership system (939 TLA+): Found 3 bugs, some requiring traces of 35 steps.
- EBS volume management (102 PlusCal): Found 3 bugs.
- Internal distributed lock manager, lock-free data structure (223 PlusCal): Improved confidence. Failed to find a liveness bug as we did not check liveness.
- Lock manager fault tolerant replication and reconfiguration algorithm (318 TLA+): Found 1 bug. Verified an aggressive optimization.

## Side benefit (excerpt)

Engineers naturally focus on designing the 'happy case' for a system [...] Almost always, the engineer stops well short of handling 'extremely rare' combinations of events, as there are too many such scenarios to imagine. In contrast, when using formal specification we begin by precisely stating "what needs to go right?"

## First big success: DynamoDB (verbatim)

The replication and fault-tolerance mechanisms in DynamoDB were created by author T.R. To verify correctness of the production code, T.R. performed extensive fault-injection testing using a simulated network layer to control message loss, duplication, and re-ordering. The system was also stress tested for long periods on real hardware under many different workloads. We know that such testing is absolutely necessary, but can still fail to uncover subtle flaws in design. To verify the design, T.R. wrote detailed informal proofs of correctness. Those proofs did indeed find several bugs in early versions of the design. However, we have also learned that conventional informal proofs can miss very subtle problems. To achieve the highest level of confidence in the design, T.R. chose to apply TLA+.

T.R. learned TLA+ and wrote a detailed specification of these components in a couple of weeks. [...] The model checker verified that a small complicated part of the algorithm worked as expected, for a sufficiently large instance of the system to give very high confidence that it is correct. T.R. then moved on to checking the broader fault-tolerant algorithm. This time the model checker found a bug that could lead to losing data if a particular sequence of failures and recovery steps was interleaved with other processing. This was a very subtle bug; the shortest error trace exhibiting the bug contained 35 high level steps. The improbability of such compound events is not a defense against such bugs [...] The bug had passed unnoticed through extensive design reviews, code reviews, and testing, and T.R. is convinced that we would not have found it by doing more work in those conventional areas.

## What formal methods do / do not do (verbatim)

Formal methods help engineers to get the design right, which is a necessary first step toward getting the code right. If the design is broken then the code is almost certainly broken [...]

Formal methods can help engineers write better "self-diagnosing code", in the form of assertions. [...] A good system invariant captures the fundamental reason why the system works [...] Formal methods help engineers to find strong invariants, so formal methods can help to improve assertions, which help improve the quality of code.

While we would like to verify that the executable code correctly implements the high-level specification, or even generate the code from the specification, we are not aware of any such tools that can handle distributed systems as large and complex as those we are building. [...]

We have seen research on using the TLC model checker to find 'edge cases' in the design on which to test the code. This approach seems promising. However the cited paper is about hardware designs, and we have not yet tried to apply that method to software.

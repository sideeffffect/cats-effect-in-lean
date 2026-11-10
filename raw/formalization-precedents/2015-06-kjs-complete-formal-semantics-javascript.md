# KJS: A Complete Formal Semantics of JavaScript

> Source: https://fsl.cs.illinois.edu/publications/park-stefanescu-rosu-2015-pldi.pdf (PLDI 2015)
> Collected: 2026-11-10
> Published: 2015-06 (PLDI 2015)

Authors: Daejun Park, Andrei Ștefănescu, Grigore Roșu (UIUC).

[...omitted: K framework rules, symbolic execution / verification sections, tables, references...]

## Abstract

This paper presents KJS, the most complete and throughly tested formal semantics of JavaScript to date. Being executable, KJS has been tested against the ECMAScript 5.1 conformance test suite, and passes all 2,782 core language tests. Among the existing implementations of JavaScript, only Chrome V8's passes all the tests, and no other semantics passes more than 90%. In addition to a reference implementation for JavaScript, KJS also yields a simple coverage metric for a test suite: the set of semantic rules it exercises. Our semantics revealed that the ECMAScript 5.1 conformance test suite fails to cover several semantic rules. Guided by the semantics, we wrote tests to exercise those rules. The new tests revealed bugs both in production JavaScript engines (Chrome V8, Safari WebKit, Firefox SpiderMonkey) and in other semantics. KJS is symbolically executable, thus it can be used for formal analysis and verification of JavaScript programs. We verified non-trivial programs and found a known security vulnerability.

## Contributions (excerpt)

KJS closely resembles the language standard, which facilitates visual inspection, and allows to measure the semantic coverage of a test suite. We found that the ECMAScript 5.1 conformance test suite misses several semantic behaviors described in the language standard. We wrote tests for the uncovered semantics and discovered a number of bugs both in production JavaScript engines and in existing formal semantics. Measuring conformance test suite coverage has been considered infeasible, because JavaScript implementations are highly optimized and do not follow the standard document line by line.

## Finding Bugs and Improving the Test Suite (verbatim excerpts)

[...] the semantic coverage of the test suite has not been well-studied, and indeed, some behaviors have escaped untested. Using KJS, we found that despite the large number of tests, certain semantic behaviors are still not tested. For example, surprisingly, there is no test for the peculiar fall-though semantics of the default case for switch. Writing tests to cover the untested behaviors, we found bugs in all production JavaScript engines and in previous semantics.

How can we measure the semantic coverage of a conformance test suite? One possibility is to run it through several JavaScript implementations using code coverage tools, and project the result back to ECMAScript 5.1. However, this is impractical, as it is not viable to match optimized implementation code to corresponding ECMAScript 5.1 pseudo-code and filter out implementation-specific code.

Due to its one-to-one correspondence with ECMAScript 5.1, KJS provides a direct semantic coverage measure for a test suite. This way we found that there are exactly 17 semantic rules in the core semantics which are not covered by the test suite [...] We succeeded to manually write test programs that hit 11 out of 17 behaviors, thus improving the overall quality of the conformance test suite. It took two days to manually write (or show infeasibility of) the tests for the 17 cases. Finding tests for the semantics is essentially the same as finding tests for conventional programs. For each uncovered semantic rule, we examine a kind of a path condition that leads to the rule, and find a solution (i.e., a test program) that satisfies the path condition. Automatic test case generation techniques may be used to mechanize this process, but in this paper we have done all the work manually.

As seen in Table 2, the 11 new tests uncovered bugs in both production JavaScript engines and in existing semantics. Moreover, the remaining 6 semantic behaviors are infeasible, that is, they represent flaws in the language standard itself. These bugs were reported, confirmed, and fixed.

Example: Step 5.e.iv of Section 10.5 [duplicate global function declarations] is supposed to raise a TypeError exception according to the standard [...] Safari WebKit wrongly ignores the duplicate function declaration, disobeying the standard; Chrome V8 and Firefox SpiderMonkey behave correctly.

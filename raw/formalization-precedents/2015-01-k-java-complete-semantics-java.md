# K-Java: A Complete Semantics of Java

> Source: https://fsl.cs.illinois.edu/publications/bogdanas-rosu-2015-popl.pdf (POPL 2015)
> Collected: 2026-11-10
> Published: 2015-01 (POPL 2015)

Authors: Denis Bogdănaş (Alexandru Ioan Cuza University, Iaşi), Grigore Roşu (UIUC).

[...omitted: K rules, static/dynamic semantics details, model-checking applications, references...]

## Abstract (excerpt; PDF text extraction garbled the first lines)

This paper presents K-Java, a complete executable formal semantics of Java 1.4. K-Java was extensively tested with a test suite developed alongside the project, following the Test Driven Development methodology. [...]

## Introduction (verbatim excerpts)

We present K-Java, a semantics for Java which systematically defines every single feature listed in the official definition of Java 1.4, which is the Java Language Specification, 2nd edition (JLS), a 456-page 18-chapter document. Moreover, our semantics is thoroughly tested. In fact, we spent about half the time dedicated to this project to write tests, which are small Java programs exercising special cases of features or combinations of them. Specifically, we followed a Test Driven Development methodology to first develop the tests for the feature to be defined and interactions of it with previous features, and then defined the actual semantics of that feature. This way we produced a comprehensive set of 840 tests, which serves as a conformance test suite not only for our semantics, but also for testing various other Java tools. Considering that no such conformance test suite exists for Java, our tests can also be regarded as a contribution made by this paper.

## 6 Testing (verbatim excerpts)

Testing K-Java took almost half of the overall development time. Here we describe our testing efforts, which resulted in what could be the first publicly available conformance test suite for Java.

When writing our tests we followed the Test Driven Development (TDD). The main principle of TDD is to write tests before implementing the actual feature under test. It was advantageous to use TDD for K-Java for two reasons. First, K-Java has a complete and final specification—JLS. Consequently, our tests are not expected to change as a result of changes in the specification. Second, tests for K-Java are self-contained Java programs, they do not depend on any part of the system under test (K-Java) to be written.

For every test, we compared the output produced by K-Java with the output produced by JDK. When developing a new feature, we followed the following steps. First we tried to cover all corner cases of the feature under test in isolation. [...] Second, we would define the new feature in the simplest way possible to pass all the tests. Sometimes, after inspecting the implementation, we would identify some corner cases that were not captured by the tests. We would add additional tests for such cases. Thus our methodology was a combination of white-box and black-box testing. In addition to the steps above, we wrote tests for each combination of language features whenever we thought that the two features may possibly unexpectedly interact.

[...] We aimed at testing every detail specified in JLS; e.g., to test the precise order of execution of subexpressions inside an expression, we intentionally used subexpressions with side-effects by observing the correct order in which the side effects occurred.

Some features depended on other features to be properly tested. For example, in order to test the precise static type of various expressions we used method overloading. For example, if an expression e has to return type A, but a plausible erroneous semantics could also produce B, we tested the correct choice by calling f(e), where f was an overloaded method that could accept an argument of type A or B.

Eventually, we produced a test suite consisting of 840 tests.

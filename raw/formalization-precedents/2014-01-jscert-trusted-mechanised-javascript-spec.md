# A Trusted Mechanised JavaScript Specification (JSCert / JSRef)

> Source: https://www.doc.ic.ac.uk/~pg/publications/Bodin2014Trusted.pdf (POPL 2014)
> Collected: 2026-11-10
> Published: 2014-01 (POPL 2014)

Authors: Martin Bodin, Arthur Charguéraud, Daniele Filaretti, Philippa Gardner, Sergio Maffeis, Daiva Naudžiūnienė, Alan Schmitt, Gareth Smith.

[...omitted: formal rule presentation, pretty-big-step semantics details, Coq monadic interpreter details, references...]

## Abstract

JavaScript is the most widely used web language for client-side applications. Whilst the development of JavaScript was initially just led by implementation, there is now increasing momentum behind the ECMA standardisation process. The time is ripe for a formal, mechanised specification of JavaScript, to clarify ambiguities in the ECMA standards, to serve as a trusted reference for high-level language compilation and JavaScript implementations, and to provide a platform for high-assurance proofs of language properties.

We present JSCert, a formalisation of the current ECMA standard in the Coq proof assistant, and JSRef, a reference interpreter for JavaScript extracted from Coq to OCaml. We give a Coq proof that JSRef is correct with respect to JSCert and assess JSRef using test262, the ECMA conformance test suite. Our methodology ensures that JSCert is a comparatively accurate formulation of the English standard, which will only improve as time goes on. We have demonstrated that modern techniques of mechanised specification can handle the complexity of JavaScript.

## Introduction (excerpts)

[...] both JSCert and JSRef are necessary: JSCert, unlike JSRef, is well-suited for developing inductive proofs about the semantics of JavaScript; JSRef, unlike JSCert, can be used to run JavaScript programs.

Our challenge is to convince ourselves and others that JSCert is indeed an accurate formulation of the ES5 English specification. We designed JSCert to follow the structure of the ES5 English standard as much as possible. Whenever we found parts of ES5 English prose to be ambiguous, we checked the browser implementations and were active on discussion groups such as es-discuss.

We also ran JSRef on the official ECMA test suite, test262. Since JSRef is correct with respect to JSCert, failed tests meant discrepancies between ES5, JSCert, and the tests. Using this methodology, we were able to correct several bugs in JSCert and JSRef. We also discovered, and reported, a number of bugs in all the browser implementations, the ECMA standards, and test262.

Trust. For JSCert, trust arises from the 'eyeball closeness' of JSCert to ES5. We can place the English prose and the formal rules side-by-side, and compare the two: one line of ES5 pseudo-code corresponds to one or two rules in JSCert. [...] For JSRef, we have a machine-checked correctness proof that it satisfies JSCert. More precisely, we prove in Coq that, if the execution of a JavaScript program in JSRef returns a result, then there exists a reduction derivation in JSCert relating this program to this result. Because of the looseness of ES5, our interpreter cannot be proved complete. [...] We trust the extraction mechanism of Coq [...]

We also test JSRef using test262. [...] There are 2782 tests associated with the core language (chapters 8–14): we pass 1796 tests; the others fail due to for-in, calls to libraries we have not specified, or the parser. We also use the OCaml bisect tool to investigate the coverage of these tests.

As we were developing the proof of correctness and running the tests, we inevitably found bugs in JSCert and JSRef. It was necessary to go around the loop many times, fixing inaccuracies, continuing with the correctness proof and testing, and so on. [...] we cannot yet guarantee that JSCert is bug free in the sense that there may well be mismatches with ES5. A few mismatches will be due to the ambiguity of ES5. The ECMA authors have been very responsive to our queries on es-discuss and it has always been possible to reach consensus. Other mismatches, however, will be due to inaccuracies in JSCert.

## 6 Trust (excerpts)

JSCert and JSRef can therefore be challenged through two distinct paths: through the eyeball correspondence with ES5; and through the execution of tests by our reference interpreter. Having these two independent paths significantly decreases the likelihood of bugs remaining in JSCert.

As we were proving correctness, we were able to detect and correct many typos, and also a small number of more serious misinterpretations of ES5. JSCert and JSRef were intentionally developed by different researchers. Despite close interaction between researchers, there were inevitable discrepancies in interpretation [...] This proof is a cornerstone of our work, as it enables us directly to validate our JSCert specification with testing.

Running JSRef over thousands of tests has been very useful, as it allowed us to detect and fix several bugs in JSRef and JSCert. Most of these bugs were simple typos, but a few of them were more serious: e.g., converting a record to a data property instead of a data accessor.

[...] trust in JSCert and JSRef requires trust in Coq, Coq's extraction mechanism, the OCaml compiler, the Google Closure parser, our glue code for linking the parser to the extracted code of JSRef, and our glue code for binding boolean and floating-point JavaScript values to their OCaml counterparts.

An alternative approach to producing tests manually would be to generate them automatically, by using automated theorem provers to exhibit tests whose execution is able to reach a particular line of JSRef code. As these tests would be generated from JSRef, they would certainly not trigger bugs in JSRef. However, if these tests were to fail on other JavaScript virtual machines, then we would know that there is either a bug in JSRef or in the virtual machines.

## 6.3 Bugs discovered (verbatim)

[...] we looked not only at ES5, but also at the next version of ECMAScript (ES6), at several test suites, and at the behaviour of the major browsers. We spotted bugs in all of these places, obtaining confirmation from ECMA authors and JavaScript implementers that they were indeed bugs.

In ES6, we discovered three bugs, ranging from simple typos to an "informative algorithm" which did not correctly implement the behaviour it was claiming. In test262, we discovered three bugs, the most interesting being a test which contains code that seems to do nothing and whose purpose is unknown to the current maintainers. V8 and Webkit incorrectly implement enumeration in the presence of shadowing, as used by for-in. [...] All browser implementations give (different) incorrect completion values for try...catch...finally [...] In addition, we observed in V8 that dead code after a try...catch...finally block may incorrectly change the value that is returned by the block.

Finding bugs in browsers, standards and industry tests was not the main motivation for the work presented here. The bugs mentioned are simply a side effect of attempting to understand ES5 well enough to build JSCert and JSRef.

# Mechanising and Verifying the WebAssembly Specification (WasmCert-Isabelle)

> Source: https://www.cl.cam.ac.uk/~caw77/papers/mechanising-and-verifying-the-webassembly-specification.pdf (CPP 2018, https://doi.org/10.1145/3167082)
> Collected: 2026-11-10
> Published: 2018-01 (CPP'18, Jan 8-9 2018)

Author: Conrad Watt (University of Cambridge).

[...omitted: language background, formal rules, type-checker algorithm, references...]

## Abstract

WebAssembly is a new low-level language currently being implemented in all major web browsers. It is designed to become the universal compilation target for the web, obsoleting existing solutions in this area, such as asm.js and Native Client. The WebAssembly working group has incorporated formal techniques into the development of the language, but their efforts so far have focussed on pen and paper formal specification.

We present a mechanised Isabelle specification for the WebAssembly language, together with a verified executable interpreter and type checker. Moreover, we present a fully mechanised proof of the soundness of the WebAssembly type system, and detail how our work on this proof has exposed several issues with the official WebAssembly specification, influencing its development. Finally, we give a brief account of our efforts in performing differential fuzzing of our interpreter against industry implementations.

## Introduction (excerpt)

[...] mechanism by which a WebAssembly implementation interfaces with its host environment was not formally specified in the working group's original paper. Extending our mechanisation to model this feature revealed a deficiency in the WebAssembly specification that sabotaged the soundness of the type system.

We have also defined a separate verified executable interpreter and type checker. Like many verified language implementations, these artefacts require integration with an external parser and linker to run as standalone programs, which introduces an untrusted interface. We use the official reference WebAssembly interpreter, implemented in Ocaml, for this purpose. Our core proofs of correctness allow us to experimentally validate our mechanised specification using our executable interpreter, both by leveraging the official WebAssembly conformance test suite, and by conducting fuzzing experiments. [...] our work contains ~11,000 non-whitespace, non-comment lines of Isabelle code.

## Host environment (excerpt)

[...] We allow host functions to arbitrarily mutate the heap, but not the function table or the list of declared global variables. We have found that this behaviour is sufficient to pass all available WebAssembly conformance tests, and execute all WebAssembly programs encountered "in the wild" so far.

Another advantage of locales is that they force us to be explicit in the assumptions we make about the behaviour of untrusted code interfacing with our verified interpreter. For example, when carrying out code extraction for integration with the official reference interpreter, we must explicitly axiomatise our assumption that the native OCaml code we interface with has well-behaved host functions.

## 4 Soundness — spec errors found (verbatim)

In the course of conducting this proof, we identified several errors in the official specification which were acknowledged and fixed by members of the working group. In some cases, these errors meant that the type system was originally unsound.

4.1 Exception Propagation. [...] the original draft specification we based our model on did not allow the Trap value to propagate as intended, and the reduction could incorrectly become stuck before Trap reached the top of the stack, violating the progress property. We discovered this issue while attempting to prove the progress property, and were able to communicate a counterexample to the specification authors, as well as a suggested solution, which was ultimately adopted into the specification.

4.2 Return. Originally, the Return operation was simply specified as a "maximal" break. [...] we discovered that the typing rule given was incorrect, with the effect that a Return operation could occur outside a function call and still be well typed. [...] Determining the correct fix was an extended process, and we assisted a member of the working group by modelling several possible solutions.

4.3 Host Functions. Since host functions may behave in arbitrary, non-deterministic ways that fall outside the space of possible WebAssembly behaviours, they are required to preserve certain invariants on the runtime state [...] We discovered that the invariants as they were stated in the specification were too weak, so that a host function could obey them yet still cause a well-typed program to crash, in violation of the progress property. Ultimately, this section of the specification was entirely re-written to fix this problem.

## 5 Executable type checker (excerpt)

We have defined, separate from our model, an executable type checker in Isabelle, and proven it sound and complete with respect to the inductive typing relation of our mechanisation. We did not use Isabelle's tools to extract executable code from the original typing relation (a process known as animation), because we desired our type checker to match the behaviour of industry implementations by running in a single pass.

## 7 Validation and Fuzzing (verbatim)

Our executable interpreter, suitably augmented with the reference parser and linker, successfully passes all core language conformance tests available in the WebAssembly repository. Due to the soundness result we have with respect to our mechanised specification, these tests also serve to validate our model.

In addition to this, we have conducted differential testing of our executable interpreter against several major WebAssembly engines. This was done both with the purpose of validating our interpreter, and potentially discovering semantic bugs in commercial WebAssembly engines. Tests were generated using the CSmith tool, combined with the official Binaryen toolchain to convert the generated C tests into WebAssembly. [...] No errors were found either in our implementation or any commercial engine, although a crash bug was discovered within the Binaryen toolchain itself, which was reported and fixed by the developers.

## 8 Related work (excerpt)

The structure and organisation of our proofs and executable artefacts owe a great debt to the JSCert project, which mechanised the ES5 JavaScript specification. JSCert separated its specification and executable implementation in order to offer a specification which could be used to build proofs about language properties without sacrificing eyeball closeness, which its contributors argued was necessary to relate proven properties back to the original textual specification. We consider our project to have benefited significantly from following JSCert's lead in this arrangement: our work in proving WebAssembly's type soundness properties identified several important issues with the official specification which we could not have discovered without embarking on such a "deep" proof of a language property, and might not have been so immediately actionable by the official specification authors had we not maintained eyeball closeness.

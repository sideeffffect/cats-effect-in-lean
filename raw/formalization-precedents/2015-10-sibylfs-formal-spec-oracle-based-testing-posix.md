# SibylFS: formal specification and oracle-based testing for POSIX and real-world file systems

> Source: https://www.cl.cam.ac.uk/~pes20/SOSP15-paper102-submitted.pdf (SOSP 2015); project page https://sibylfs.github.io/
> Collected: 2026-11-10
> Published: 2015-10 (SOSP 2015)

Authors: Tom Ridge, David Sheets, Thomas Tuerk, Andrea Giugliano, Anil Madhavapeddy, Peter Sewell.

[...omitted: model internals, test generation details, per-filesystem results, references...]

## Abstract

Systems depend critically on the behaviour of file systems, but that behaviour differs in many details, both between implementations and between each implementation and the POSIX (and other) prose specifications. Building robust and portable software requires understanding these details and differences, but there is currently no good way to systematically describe, investigate, or test file system behaviour across this complex multi-platform interface.

In this paper we show how to characterise the envelope of allowed behaviour of file systems in a form that enables practical and highly discriminating testing. We give a mathematically rigorous model of file system behaviour, SibylFS, that specifies the range of allowed behaviours of a file system for any sequence of the system calls within our scope, and that can be used as a test oracle to decide whether an observed trace is allowed by the model, both for validating the model and for testing file systems against it. SibylFS is modular enough to not only describe POSIX, but also specific Linux, OS X and FreeBSD behaviours. We complement the model with an extensive test suite of over 21 000 tests; this can be run on a target file system and checked in less than 5 minutes, making it usable in practice. Finally, we report experimental results for around 40 configurations of many file systems, identifying many differences and some serious flaws.

## Introduction (verbatim excerpts)

Our second contribution is an extensive test suite, consisting of 21 070 automatically generated and hand-written test scripts. The fact that we have an executable test oracle greatly simplifies test suite development: we do not have to manually determine the intended outcome for each test, but rather can focus on generating tests with good coverage. Our present test suite achieves 98% coverage of the model.

[...] We have run our test suite on over 40 system configurations, to simultaneously develop the model and to identify bugs, platform conventions, and deviations. We present an overview of some of the most interesting findings, including deviations of Linux HFS+ from OS X HFS+, the effect of mount options on SSHFS/tmpfs's behaviour, a storage leak in posixovl/VFAT, and an infinite busy loop on OpenZFS for OS X.

This model has several important and unusual properties:

1. It is executable as a test oracle: given an observed trace of API calls and returns, SibylFS can efficiently compute whether it is allowed by the model or not. In conjunction with our extensive test suite (see below), this lets us validate the model, to ensure it does not overly constrain implementation behaviour, and lets us test implementations, to ensure they do not exhibit behaviour not allowed by the model.
2. To characterise the behaviour of a particular implementation, SibylFS is parameterised in various ways. It currently supports four primary modes: POSIX, Linux, OS X and FreeBSD behaviour. This variation is essential when exploring file system behaviour, as otherwise a single difference (e.g. in path resolution) might give rise to thousands of individual test-result discrepancies; we have to be able to analyse and factor out such differences to make progress.
3. Within our scope, SibylFS aims to be realistic and comprehensive: it is a model of actual file system behaviour, not of idealised or simplified file systems [...]
4. To make it completely precise and unambiguous, while still admitting the loose specification needed, the model is written in a mathematically rigorous language, the typed higher-order logic of the Lem tool. We use Lem to translate this into the theorem provers HOL4 and Isabelle/HOL [...] and into the OCaml source code used by SibylFS.
5. We take care also to make the model readable, for use as an informal reference. [...] Key choices are linked to the experimental trace data that they relate to. All this is important also for maintainability [...]

Technical challenges. There are two main challenges we have had to overcome. The first is nondeterminism: file system implementations have considerable internal nondeterminism and our model must be loose enough to accommodate that, but the model must still be clear (not complicated with implementation detail), and, crucially, trace-checking must be efficient. Previous related work modelling and checking TCP required a sophisticated higher-order logic constraint-based backtracking search, and checking around 1000 traces took 2500 CPU-hours; here, by carefully isolating nondeterminism we check 20 000 traces in about a minute on a four-core machine. [...] this per-trace performance difference (around 6 orders of magnitude) makes the difference between something on the edge of practicality and something that can be done routinely during development.

The second main challenge is that of managing complexity, in constructing an accurate, readable and concise model that synthesises the many existing sources of information and our thousands of observed real-world traces of behaviour. [...]

## 3 Technical challenge: nondeterminism (verbatim excerpts)

In writing a model to be used as a test oracle (i.e., to compute whether observed traces are allowed by the model or not), the treatment of nondeterminism is a key issue. If both the model and the implementations are entirely deterministic, at the abstraction level at which they are being observed, then one could just run the two on the same input and check they have equal output. But for real-world software that is rarely the case: implementation behaviour typically varies, both between implementations and depending on implementation-internal runtime choices, and specifications are often deliberately loose. For example, for file systems:

- Some API calls could give rise to several distinct errors, e.g. EISDIR, EEXIST or ENOTEMPTY for a rename of a file to a non-empty directory; which is actually returned is determined by the order of the checks in the file system implementation code.
- The number of bytes returned by a read may be less than the number requested, determined by the implementation internal state.
- The order in which readdir returns entries [...] will depend on the implementation [...]
- The behaviour of concurrent API calls may be determined by scheduling.

A sound specification must be loose enough to accommodate all such variation (looseness should not be confused with the question of whether a specification is precise: we want a mathematically precise model, but one that admits a range of allowable behaviours). But then checking a trace against such a specification poses an algorithmic problem, especially when there is internal nondeterminism that is not immediately observable: in general one must effectively track the set of all possible implementation states (abstracted to what can affect external observation) at every step of the trace [...]

Simple nondeterminism via possible next-state enumeration. At the top level the model consists of a type of abstract file system states and a function that, given such a state and an API event (call, return, etc.), returns a finite set of possible next states. [...] For the simple case of multiple possible API error return values, the model explicitly calculates the set of all allowed errors [...] and a next state for each, then when the real-system return value is observed we simply choose the corresponding state. [...] that blowup is resolved at the next step in the trace, when the actual number of bytes read by the real-world process becomes known. [...] The downside of [continuation-style checking] is that it makes it hard for the checker to describe, for a failing step, the set of values that would have been allowed.

Directory listing nondeterminism by hand-crafted specification. [readdir with concurrent modification: track "must" and "may" sets of entries; nondeterministically split; resolved when the next label reveals the entry actually read.]

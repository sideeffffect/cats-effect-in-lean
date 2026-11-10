# How We Built Cedar: A Verification-Guided Approach

> Source: https://arxiv.org/abs/2407.01688 (FSE Companion '24, https://doi.org/10.1145/3663529.3663854)
> Collected: 2026-11-10
> Published: 2024-07-01

Authors: Craig Disselkoen, Aaron Eline, Shaobo He, Kyle Headley, Michael Hicks, Kesha Hietala, John Kastner, Anwar Mamat, Matt McCutchen, Neha Rungta, Bhakti Shah, Emina Torlak, Andrew Wells (AWS / Univ. of Maryland / Univ. of Chicago).

[...omitted: nav chrome, figures, reference list, policy examples of Section 2...]

## Abstract

This paper presents verification-guided development (VGD), a software engineering process we used to build Cedar, a new policy language for expressive, fast, safe, and analyzable authorization. Developing a system with VGD involves writing an executable model of the system and mechanically proving properties about the model; writing production code for the system and using differential random testing (DRT) to check that the production code matches the model; and using property-based testing (PBT) to check properties of unmodeled parts of the production code. Using VGD for Cedar, we can build fast, idiomatic production code, prove our model correct, and find and fix subtle implementation bugs that evade code reviews and unit testing. While carrying out proofs, we found and fixed 4 bugs in Cedar's policy validator, and DRT and PBT helped us find and fix 21 additional bugs in various parts of Cedar.

## 1 Introduction (excerpt)

To provide assurance that the engine's authorization decisions are correct, we develop Cedar using a two-part process we call verification-guided development (VGD). First, we construct simple and readable formal models of Cedar's components. We write these models in the Lean programming language, and carry out mechanized proofs to show that they satisfy important correctness properties. Second, we use differential random testing (DRT) to show that the models match the production code, which is written in Rust. DRT involves generating millions of inputs—consisting of policies, data, and requests—and testing that the model and production code agree on the outputs. We also perform property-based testing (PBT) of the Rust code directly (in the style of QuickCheck) when there is no corresponding Lean model. We may also property-test conjectured properties on the Rust code before we prove them in Lean.

One approach would be to develop Cedar entirely in Lean, compile to C, and deploy the generated C code in production. [...] Lean is a new programming language, so it has a limited developer pool and lacks useful libraries available in mainstream languages. Debugging a failure might necessitate stepping through the generated C code [...]

Another approach would be to develop only in Rust and prove correctness of the Rust code directly, using a tool like Aeneas, Kani, Prusti, Creusot, or Verus. The main challenge here is that tools for verifying Rust code are not (yet) up to the task [...] The model consumable by one of these tools is unlikely to be as readable as the Lean model [...]

## 3 Lean models and proofs (excerpts)

We wrote models of the Cedar evaluator, authorizer, and validator in Lean, and are in the process of writing one for the symbolic compiler. The models serve as Cedar's specification, and we had two goals when writing them. First, the models should be human readable, and thus favor simplicity and understandability. Second, they should be as feature complete as possible, so that proofs about them apply to the full language, not just an abstraction, and so that the models can be used as oracles for differential testing.

Lean requires all recursive definitions to be well-founded (so functions always terminate), which complicates modeling of complex recursive structures. While Rust lets us represent Cedar values as a recursive datatype over built-in sets and maps, Lean prohibits doing so for its standard set and map datatypes because their invariants introduce circular (not well-founded) reasoning. We worked around this by developing custom set and map datatypes that replace embedded invariants with separate theorems. Pleasantly, our termination proofs turned out to not be merely tedium: Constructing them helped us uncover and fix a non-termination bug in our definition of the Cedar validator, which would have been difficult to detect through testing. We also found three other bugs while attempting to carry out the validator soundness proof.

Table 1 (LOC): Lean model total 4686, Lean proofs total 15693 (proof-to-model ~3.4:1), Rust production 20458, Rust tests 31391. The Lean models are an order of magnitude smaller than their Rust counterparts, which include optimizations, extra code to provide useful diagnostic output, and some unmodeled code. For example, our parsers are not modeled in Lean because there is currently no library support for parser generators, and it is unclear what properties we could prove about a parser model. We also did not port our unit tests to Lean because we can instead prove properties of interest.

Proved properties: (1) Forbid trumps permit; (2) Default deny; (3) Explicit allow; (4) Order independence; (5) Sound slicing; (6) Validation soundness; (7) Termination.

It takes about 3 minutes to check all proofs and compile models for execution. During differential testing, the median execution time for the Lean authorizer is 6 microseconds, compared to 10 microseconds for Rust.

## 4 Differential random testing (excerpts)

Using the cargo-fuzz fuzz testing framework, we randomly generate millions of inputs—access requests, entities, and policies—and send them to both the Lean model and the corresponding Rust production implementation. If the two versions agree on the output, then we obtain a piece of evidence that Rust production code is on par with the Lean model. If they disagree, then we have found a bug (e.g., production code incorrectly implements the specification). With each version of Cedar, we save a minimized set of corpus tests generated by cargo-fuzz to use as part of continuous integration testing.

PBT is complementary to DRT because it allows us to test properties we have yet to prove in Lean, and those of production components (such as the Cedar policy parser) for which no model exists.

### 4.1 Input generation

Naïve input generation is insufficient: If we randomly generate a policy, entity store, and request independently, policies are likely to be ill-typed and to reference non-existent entities or attributes. This would over-exercise error-handling code and fail to cover much of a component's core logic. [...] our typical input generation strategy is type directed in the style of Pałka et al.: we first generate a schema, then an entity store that conforms to the schema, and then policies and requests that access those entities in conformance with the schema. [...] well-typed policies do not exercise error handling code. Therefore we developed another generator whose policies always refer to entities, actions, and attributes in the schema, but whose conditions can be ill-typed. [...] The type-directed generator produces more complicated inputs, like set operations, than the non type-directed version, leading to deeper coverage of core logic and faster bug discovery. So we use both.

### 4.2 Properties tested (Table 2, bugs found)

- Rust and Lean authorizer parity — ABAC (type-directed): 6; ABAC (arbitrary condition): 0; RBAC (multiple condition-free policies): 4
- Rust and Lean validator parity: 6
- Parser roundtrip (pretty-print then parse = identity): 2
- Formatter roundtrip: 0
- Parser safety (random bytes): 0 [table alignment in PDF is ambiguous]
- Validation soundness (validated policies never produce type errors): 3

### 4.3 Experience

We use Amazon's Elastic Container Service (ECS) to test our properties daily on currently supported Cedar versions. We allocate 4 vCPUs and 8GB memory to fuzz each target for 6 hours. [...] it ensures that block coverage for each target saturates or grows slowly near the end of a daily run.

As one example, differential testing against the Lean model helped us find a bug in a Rust package we used for parsing IP addresses. This finding eventually motivated us to write our own IP address parser, replacing the buggy external package.

Some bugs found by differential testing even affected Cedar's language design. For example, an unreleased early version of Cedar provided a method to get the size of a string. The model and production code ended up having different implementations (using bytes vs. codepoints vs. graphemes), causing DRT to fail. We eventually dropped this feature after agreeing that it confuses users more than it benefits them. [...] All bugs found by the validation soundness property were found before we had completed a soundness proof.

Complete line coverage alone does not guarantee effective testing. [...] even when the ABAC policy generator achieves full line coverage, many of the generated inputs exercise error handling code. Furthermore, 35.5% of the when condition-expressions generated by the type-directed ABAC policy generator, for a typical DRT run, are boolean literals [...] we added a new input generator that generates expressions of various types [...] only 9.7% of Boolean-typed expressions are boolean literals.

Integration tests made from corpus tests turn out to be a valuable asset for Cedar developers: they helped us quickly catch tricky bugs when developing new features.

Limitations. Unsurprisingly, Cedar's testing framework has missed bugs, too. The most notable example is that it did not discover the non-termination bug described in Section 3.1. The reason for this is that the probability of generating inputs triggering this bug is extremely low. Our framework is also inherently unable to find bugs outside the scope of the test generators. For example, we did not discover some parser bugs triggered by malformed policies because our test generators create abstract syntax trees of Cedar policies and thus are limited to produce only syntactically correct policies.

## Appendix A: Trophy and anti-trophy cases (Table 3, bugs found; verbatim descriptions)

- The Rust implementation and definitional model computed string sizes differently
- The Rust implementation and definitional model named extension functions differently (e.g., lt vs. lessThan)
- The Rust implementation allowed octal numbers in IPv4 addresses while the definitional model did not
- The definitional model incorrectly rejected "::" when parsing IPv6 addresses
- The Rust implementation supported embedding IPv4 addresses in IPv6 addresses while the definitional model did not
- The Rust implementation required the operands of the isInRange extension function to be both IPv4 or IPv6 addresses while the definitional model did not
- Comments on records were dropped by the formatter (cedar PR 257)
- Comments could be dropped in an is expression (PR 460)
- The parser did not unescape raw strings
- The parser did not parse the pattern literals of the like operation correctly
- The parser did not parse namespaced extension function names correctly
- The parser performed constant folding incorrectly
- Pretty-printing did not consistently add parentheses to negation operations
- Pretty-printing certain function call ASTs resulted in a crash
- The Rust implementation and definitional model named extension functions differently (e.g., ipaddr vs. IPAddr)
- The Rust implementation incorrectly rejected certain policies with schemas containing unspecified entity types
- The Rust implementation incorrectly handled policies containing certain types of records (PR 165)
- The Rust implementation and definitional model disagreed on the type of resource in [] when resource has unspecified entity type (PR 615)
- The validator ignored certain entity type namespaces
- The validator did not parse extension function call arguments correctly
- The validator did not correctly typecheck certain has expressions

Table 4: Bugs missed by DRT/PBT (description — root cause)

- The Rust evaluator incorrectly implemented the in operation — DRT failed to generate inputs that trigger this bug
- The Rust evaluator accepted the string representation of an invalid decimal literal — Triggering input is too hard to generate
- The parser crashed on certain malformed policies — DRT does not methodically generate malformed policies
- The parser did not reject certain malformed policies (PR 594) — same
- The API to link a policy to a template could crash on invalid inputs (PR 203) — DRT did not test the relevant APIs
- Certain parsable policies could fail to be converted to their JSON representation (PR 601) — DRT did not test the relevant APIs
- The JSON schema parser accepted inputs with unknown attributes — DRT does not test malformed schemas
- The validator did not terminate on certain inputs — Triggering input is too hard to generate
- The validator did not typecheck template-linked policies correctly (PR 371) — DRT did not test the relevant APIs

## 5 Related work (excerpt)

Bornholt et al. apply DRT to AWS S3's ShardStore, writing a simple model in Rust that serves as a test oracle and applying stateless model checking to prove properties of this simplified code. Groce et al. use DRT as a precursor to formal methods [...]. SybilFS proposes a reference model of a POSIX file system that other implementations can use as an oracle for differential testing.

A dependability case, as proposed by Jackson, is a careful collection of different sorts of evidence showing that a software system is correct. Verification-guided development could be used to produce a dependability case: (1) evidence for good design is in the form of mechanized proofs of properties of the model, and (2) evidence of correct implementation is in the form of differential and property tests of the deployed code.

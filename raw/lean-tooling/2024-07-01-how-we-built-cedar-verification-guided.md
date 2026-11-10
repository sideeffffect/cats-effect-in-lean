# How We Built Cedar: A Verification-Guided Approach (abstract, intro, Section 4 DRT)

> Source: https://arxiv.org/html/2407.01688v1
> Collected: 2026-11-10
> Published: 2024-07-01

# How We Built Cedar: A Verification-Guided Approach
DOI: 10.1145/3663529.3663854fsecomp24industry-p88-pISBN: 979-8-4007-0658-5/24/07Conference: Companion Proceedings of the 32nd ACM International Conference on the Foundations of Software Engineering; July 15–19, 2024; Porto de Galinhas, BrazilCompanion Proceedings of the 32nd ACM International Conference on the Foundations of Software Engineering (FSE Companion ’24), July 15–19, 2024, Porto de Galinhas, BrazilCCS: Security and privacy Formal methods and theory of securityCCS: Software and its engineering Software development techniquesCCS: Security and privacy Authorization
Craig Disselkoen
Affiliation: Amazon Web Services, USA
, 
Aaron Eline
Affiliation: Amazon Web Services, USA
, 
Shaobo He
Affiliation: Amazon Web Services, USA
, 
Kyle Headley
Affiliation: Unaffiliated, USA
, 
Michael Hicks
Affiliation: Amazon Web Services, USA
Affiliation: University of Maryland, USA
, 
Kesha Hietala
Affiliation: Amazon Web Services, USA
, 
John Kastner
Affiliation: Amazon Web Services, USA
, 
Anwar Mamat
Affiliation: University of Maryland, USA
, 
Matt McCutchen
Affiliation: Unaffiliated, USA
, 
Neha Rungta
Affiliation: Amazon Web Services, USA
, 
Bhakti Shah
Affiliation: University of Chicago, USA
, 
Emina Torlak
Affiliation: Amazon Web Services, USA
and 
Andrew Wells
Affiliation: Amazon Web Services, USA
Received  2024-04-18
Abstract.
This paper presents verification-guided development (VGD), a software engineering process we used to build Cedar, a new policy language for expressive, fast, safe, and analyzable authorization.
Developing a system with VGD involves writing an executable model of the system and mechanically proving properties about the model; writing production code for the system and using differential random testing (DRT) to check that the production code matches the model; and using property-based testing (PBT) to check properties of unmodeled parts of the production code.
Using VGD for Cedar, we can build fast, idiomatic production code, prove our model correct, and find and fix subtle implementation bugs that evade code reviews and unit testing. While carrying out proofs, we found and fixed 4 bugs in Cedar’s policy validator, and DRT and PBT helped us find and fix 21 additional bugs in various parts of Cedar.
Keywords: formal methods, fuzz testing, differential testing, policy authorization language, interactive theorem proving
## 1. Introduction
Cedar (cedar, 2024; Cutler et al., 2024) is a new, open-source authorization policy language.
Developers express permissions for their applications as policies written in Cedar.
When the application needs to perform a sensitive user operation, it sends a request to the Cedar authorization engine, which allows or denies the request by evaluating the relevant policies.
Because Cedar policies are separate from application code, they can be independently authored, updated, analyzed, and audited.
Cedar’s authorization engine is part of an application’s trusted computing base (TCB), which comprises components that are critical to the application’s security.
To provide assurance that the engine’s authorization decisions are correct, we develop Cedar using a two-part process we call verification-guided development (VGD).
First, we construct simple and readable formal models of Cedar’s components.
We write these models in the Lean programming language (Moura and Ullrich, 2021), and carry out mechanized proofs to show that they satisfy important correctness properties.
Second, we use differential random testing (DRT) (McKeeman, 1998) to show that the models match the production code, which is written in Rust.
DRT involves generating millions of inputs—consisting of policies, data, and requests—and testing that the model and production code agree on the outputs.
We also perform property-based testing (PBT) of the Rust code directly (in the style of QuickCheck (Claessen and Hughes, 2000)) when there is no corresponding Lean model.
We may also property-test conjectured properties on the Rust code before we prove them in Lean.
VGD provides a practical balance of competing concerns around high assurance, ease of development, and maintainability.
To see why, consider two other processes we might have followed.
One approach would be to develop Cedar entirely in Lean, compile to C, and deploy the generated C code in production.
In addition to the formal model, we would write an optimized and full-featured implementation (which handles errors and messages more carefully, provides parsers for various formats, etc.) in Lean, and then prove the two equivalent.
A key benefit of this approach is that we would formally verify—rather than just test—the equivalence of the deployed code and model.
But there are significant downsides to writing production applications in Lean and deploying its generated C code.
Lean is a new programming language, so it has a limited developer pool and lacks useful libraries available in mainstream languages.
Debugging a failure might necessitate stepping through the generated C code and mapping it back to the Lean source, requiring expertise in C and Lean.
Doing so could be particularly difficult if the failure is due to an interaction between handwritten code and Lean-generated C code.
In addition, C is a memory-unsafe language, so a bug in the Lean compiler could lead to security issues.
Another approach would be to develop only in Rust and prove correctness of the Rust code directly, using a tool like Aeneas (Ho and Protzenko, 2022), Kani (Kani, 2024), Prusti (Astrauskas et al., 2022), Creusot (Denis et al., 2022), or Verus (Lattuada et al., 2023).
The main challenge here is that tools for verifying Rust code are not (yet) up to the task, e.g., they cannot handle much of the standard library, they support only certain code idioms, they sometimes have trouble scaling, and they are limited in the properties one can specify.
The model consumable by one of these tools is unlikely to be as readable as the Lean model, due to Rust’s low-level nature.
These limitations present challenges to guaranteeing high assurance, but also to ease of development and maintainability, because teams would likely need to wrangle code into less idiomatic forms with each release just to enable proofs.
Using VGD has proved beneficial for Cedar.
It has helped us improve Cedar’s design: While implementing the formal model and carrying out proofs of soundness of the Cedar policy validator, we found and fixed four bugs.
It has also allowed us to write fast, idiomatic Rust code with increased confidence in its correctness: Using DRT and PBT we have so far found and fixed 21 bugs in various Cedar components.
We believe VGD represents a practical approach to leveraging the benefits of formal methods while also assuring the deployed code is easy to use, develop, and maintain.
The remainder of this paper presents our experience with VGD for Cedar in detail, beginning with background on Cedar (Section 2), our Lean models of and proofs about Cedar’s components (Section 3), how we use DRT and PBT on our Rust code (Section 4), and how VGD compares to related work (Section 5).
Cedar is open source.
Our Lean models, Rust implementation, and testing setup are all available at https://github.com/cedar-policy.
## 2. The Cedar Policy Language
Cedar is a language for writing authorization policies, supporting idioms in the style of role-based access control (RBAC) (Ferraiolo and Kuhn, 1992), attribute-based access control (ABAC) (Hu et al., 2015), and their combination.
Cedar policies use a syntax resembling natural language to define who (the principal) can do what (the action) on which target (the resource) under what conditions.
To see how Cedar works, consider a simple application, TinyTodo (tinytodo, 2024), designed for managing task lists.
TinyTodo uses Cedar to control who can do what.
[...omitted: Sections 2-3 (Cedar background, Lean models and proofs) except perf note below...]
Our total proof-to-model ratio is roughly :13.4\!:\!1 (see Table 1).
Throughout development, we benefited from Lean’s extensive library of theorems and its IDE extension, which checks proofs interactively and provides instant feedback.
Our Lean proofs are fast to verify, and the models are fast to execute.
It takes about 3 minutes to check all proofs and compile models for execution.
During differential testing, the median execution time for the Lean authorizer is 6 microseconds, compared to 10 microseconds for Rust.

## 4. Differential Random Testing
The second part of the verification-guided development process is to use differential random testing (McKeeman, 1998) to increase our confidence that the behavior of our formal models matches that of our production code.
Figure 2 shows the workflow of DRT. Using the cargo-fuzz fuzz testing framework (Cargo-fuzz, 2024), we randomly generate millions of inputs—access requests, entities, and policies—and send them to both the Lean model and the corresponding Rust production implementation.
If the two versions agree on the output, then we obtain a piece of evidence that Rust production code is on par with the Lean model.
If they disagree, then we have found a bug (e.g., production code incorrectly implements the specification).
With each version of Cedar, we save a minimized set of corpus tests generated by cargo-fuzz to use as part of continuous integration testing (Section 4.3).
Using the same cargo-fuzz framework, we also perform property-based testing in the style of QuickCheck (Claessen and Hughes, 2000) to directly check properties of our production components.
PBT is complementary to DRT because it allows us to test properties we have yet to prove in Lean, and those of production components (such as the Cedar policy parser) for which no model exists.
This section discusses how we generate useful random inputs (Section 4.1), what properties we test (Section 4.2), and what we have learned in the process (Section 4.3).
Table 2. Summary of DRT and PBT test targets
Property
Input Generator
Description
# bugs found
ABAC (type-directed)
Differentially test production authorizer against its Lean model using a single ABAC policy with a mostly well-typed condition
6
Rust and Lean authorizer parity
ABAC
Differentially test production authorizer against its Lean model using a single ABAC policy with an arbitrary condition
RBAC
Differentially test production authorizer against its Lean model using multiple RBAC (condition-free) policies
0
Rust and Lean validator parity
ABAC (type-directed)
Differentially test production validator against its Lean model
4
Parser roundtrip
ABAC
Test that the composition of pretty-printing and parsing produces a policy identical to the one generated
6
Formatter roundtrip
ABAC
Test that the composition of pretty-printing, formatting, and parsing produces a policy identical to the one generated
2
Parser safety
Random bytes
Simply fuzz the Cedar parser with arbitrary inputs
0
Validation soundness
ABAC (type-directed)
Test that evaluating policies that validate does not produce type errors
3
### 4.1. Input generation
To use DRT effectively requires generating inputs that thoroughly exercise the targeted code.
Naïve input generation is insufficient: If we randomly generate a policy, entity store, and request independently, policies are likely to be ill-typed and to reference non-existent entities or attributes.
This would over-exercise error-handling code and fail to cover much of a component’s core logic.
We tackle this challenge by correlating the generation of policies, entity stores, and requests.
Specifically, our typical input generation strategy is type directed in the style of Pałka et al. (2011): we first generate a schema, then an entity store that conforms to the schema, and then policies and requests that access those entities in conformance with the schema.
This approach assures we target the core logic.
But it has the problem that well-typed policies do not exercise error handling code.
Therefore we developed another generator whose policies always refer to entities, actions, and attributes in the schema, but whose conditions can be ill-typed.
Because cargo-fuzz is a coverage-guided testing tool, leveraging libfuzzer (libFuzzer, 2024) to bias input generation toward unexecuted code, we hoped this generator would gravitate to well-typed conditions, too, and we could lean solely on it for input generation.
However, our experience proved otherwise.
The type-directed generator produces more complicated inputs, like set operations, than the non type-directed version, leading to deeper coverage of core logic and faster bug discovery.
So we use both.
### 4.2. Properties to test
The differential and other properties we test are given in Table 2.
Some properties have multiple testers with different generators.
For example, the property Rust and Lean authorizer parity is tested by two different policy generation strategies—ABAC and RBAC. The former produces a single ABAC-style policy for each run and mainly targets the evaluator since generated policies can have nontrivial conditions.
The latter generates multiple RBAC-style policies for each run and aims to exercise the authorization logic that makes a decision involving more than one policy.
### 4.3. Experience
We use Amazon’s Elastic Container Service (ECS) to test our properties daily on currently supported Cedar versions.
We allocate 4096 CPU units (4 vCPUs) and 8GB memory to fuzz each target for 6 hours.
This setup generates millions of inputs for most targets.
We do not have a particular reason for the 6 hour duration, although it ensures that block coverage for each target saturates or grows slowly near the end of a daily run.
We plan to investigate approaches to choosing an optimal fuzzing duration in the future.
As shown in Table 2, differential and property testing have uncovered 21 bugs in total.
As one example, differential testing against the Lean model helped us find a bug in a Rust package we used for parsing IP addresses.
This finding eventually motivated us to write our own IP address parser, replacing the buggy external package.
Some bugs found by differential testing even affected Cedar’s language design.
For example, an unreleased early version of Cedar provided a method to get the size of a string.
The model and production code ended up having different implementations (using bytes vs. codepoints vs. graphemes), causing DRT to fail.
We eventually dropped this feature after agreeing that it confuses users more than it benefits them.
Property testing helped us uncover subtle bugs in the Cedar policy parser, in how the formatter handles comments, and how namespace prefixes on application data (e.g., TinyTodo::List::"AliceList") are interpreted. 
All bugs found by the validation soundness property were found before we had completed a soundness proof.
Complete line coverage alone does not guarantee effective testing (Böhme et al., 2022).
The same lines of code executed with different program state can lead to very different outcomes.
Therefore it is important to test the same or similar code paths with diverse inputs, and to focus on paths of importance.
For Cedar DRT, we found that even when the ABAC policy generator achieves full line coverage, many of the generated inputs exercise error handling code.
Furthermore, 35.5% of the when condition-expressions generated by the type-directed ABAC policy generator, for a typical DRT run, are boolean literals, which means that one third of policy conditions are trivially true or false and do not trigger interesting code paths.
To address these limitations, we added a new input generator that generates expressions of various types (as opposed to just those of Boolean type, as produced by the ABAC policy generators).
For the expression generator, only 9.7% of Boolean-typed expressions are boolean literals.
Oftentimes, such Boolean-type expressions contain literals, but not boolean ones—the majority are strings (e.g., as part of == expressions) whose evaluation leads to more code coverage because string handling logic (e.g., unescaping raw strings) is non-trivial and error-prone.
Integration tests made from corpus tests turn out to be a valuable asset for Cedar developers: they helped us quickly catch tricky bugs when developing new features.
For instance, they contain subtle wildcard patterns and Cedar values that exposed bugs in the prototypes of wildcard matching and schema-based parsing.
Integration tests allowed us to fix these bugs before pushing the code, avoiding the delay for the daily DRT run to uncover them.
#### Limitations
Unsurprisingly, Cedar’s testing framework has missed bugs, too.
The most notable example is that it did not discover the non-termination bug described in Section 3.1.
The reason for this is that the probability of generating inputs triggering this bug is extremely low.
Our framework is also inherently unable to find bugs outside the scope of the test generators.
For example, we did not discover some parser bugs triggered by malformed policies because our test generators create abstract syntax trees of Cedar policies and thus are limited to produce only syntactically correct policies.
We are investigating grammar-based mutation testing (Bendrissou et al., 2023) to avoid missing this type of bug in the future.
Appendix A enumerates all the bugs found, and several missed, by DRT and PBT.
## 5. Related Work
Various communities have developed tools to increase software dependability.
The automotive industry follows the MISRA standards (MISRA Ltd, 2023).
However, these standards aim to avoid common pitfalls rather than guarantee functional correctness.
The FAA requires critical aerospace software have MCDC coverage (Kuhn et al., 2012).
This addresses functional correctness but does not guarantee it.
The highest assurance can be gained by formally verifying that deployed software meets a specification and that the specification has particular safety/security properties.
Alternatively, rather than prove software against a specification, we could develop an executable model for the specification and differentially test the code against the model, and likewise test that the model has certain properties.
Verification-guided development offers a pleasant compromise: We prove properties about a readable formal model, and rigorously test that the deployed code matches that model.
Formal methods.
A variety of software, including the CompCert optimizing C compiler (Leroy et al., 2016), the SeL4 microkernel (Heiser et al., 2020), and the EverCrypt cryptography library (Protzenko et al., 2020), have been formally verified and deployed in practice.
These systems employ the formal verification frameworks Coq (Coq Development Team, 2024), Isabelle/HOL (Nipkow et al., 2021), and F⋆ (F⋆ Development Team, 2024), respectively, which center around a domain-specific proof-oriented programming language (PPL).
The code from the PPL is either mapped to/from code written in a mainstream language, like C or OCaml, or directly extracted (compiled) to it.
Lean is similar to Coq, and in principle we could have deployed our formally verified Lean model of Cedar as extracted C code, rather than building a separate Rust version.
[...omitted: related work, appendix bug list...]

# Formally Verified Cloud-Scale Authorization

> Source: https://cdn.amazon.science/bb/40/22ac44f84f6d8eb625ac9666a00f/formally-verified-cloud-scale-authorization.pdf (ICSE 2025 research track, https://conf.researchr.org/details/icse-2025/icse-2025-research-track/119/Formally-Verified-Cloud-Scale-Authorization)
> Collected: 2026-11-10
> Published: 2025-04 (ICSE 2025; exact date uncertain)

Authors: Aleks Chakarov, Jaco Geldenhuys, Matthew Heck, Michael Hicks, ..., K. Rustan M. Leino, ..., Emina Torlak, Jean-Baptiste Tristan, ..., Michael W. Whalen, et al. (Amazon).

[...omitted: author list detail, Dafny code listings, compiler details, figures, references...]

## Abstract

All critical systems must evolve to meet the needs of a growing and diversifying user base. But supporting that evolution is challenging at increasing scale: Maintainers must find a way to ensure that each change does only what is intended, and will not inadvertently change behavior for existing users. This paper presents how we addressed this challenge for the Amazon Web Services (AWS) authorization engine, invoked 1 billion times per second, by using formal verification. Over a period of four years, we built a new authorization engine, one that behaves functionally the same as its predecessor, using the verification-aware programming language Dafny. We can now confidently deploy enhancements and optimizations while maintaining the highest assurance of both correctness and backward compatibility. We deployed the new engine in 2024 without incident and customers immediately enjoyed a threefold performance improvement. The methodology we followed to build this new engine was not an off-the-shelf application of an existing verification tool, and this paper presents several key insights: 1) Rather than prove correct the existing engine, written in Java, we found it more effective to write a new engine in Dafny, a language built for verification from the ground up, and then compile the result to Java. 2) To ensure performance, debuggability, and to gain trust from stakeholders, we needed to generate readable, idiomatic Java code, essentially a transliteration of the source Dafny. 3) To ensure that the specification matches the system's actual behavior, we performed extensive differential and shadow testing throughout the development process, ultimately comparing against 10^15 production samples prior to deployment. Our approach demonstrates how formal verification can be effectively applied to evolve critical legacy software at scale.

## Introduction (excerpt)

Third, while much focus in the formal methods community is on proof/verification technology, it is no less important to be sure your proofs consider the right specification. We used extensive systematic, differential testing to ensure the specification was accurate and complete, and thus that AuthV2 (now and in the future) exhibits no deviations from behavior established by AuthV1. In particular, we wrote the initial AuthV2 specification to be executable, and then extensively tested it against the legacy AuthV1 on synthetic and logged data. We also shadow-tested AuthV2 against AuthV1 on production authorization data, ultimately testing against 10^15 production samples prior to launch. Doing so was pivotal to ironing out last, corner-case mismatches.

## Specification validation (excerpt)

To gain confidence in the correctness of the specification, we tested the Scala model in two ways: First, we applied AuthV1's existing unit and integration tests. Second, we used junit-quickcheck to differentially test the Scala model against AuthV1.

The latter required developing a fuzzer to systematically inject arbitrary input data into the two models. The main difficulty here is randomly generating allowed policy-request pairs: because the request must match the various policy conditions to be allowed, random input data would be denied immediately and exercise only a fraction of the source code. To maximize code coverage, we hand-wrote input generators so that policies and requests match with high probability. Our generators also ensured data satisfy semantic constraints, e.g., that IP addresses contain realistic values, and that service names are realistic.

After about 3 person-months we achieved about 83% instruction coverage and 72% branch coverage, and differential testing uncovered 13 differences between the early version of the specification and AuthV1 that we were able to correct. This proved extremely valuable because it was not until later in the development cycle that verification and shadow-testing (see below) produced actionable feedback for repairing the specification.

Once the Dafny compiler and FFI models were ready, we ported the specification to Dafny, and repeated validation testing in the same way. [...] That was sufficient for testing the specification. After porting to Dafny, we refined the model further to enable verifying it in depth.

## Compiler validation (excerpt)

Additionally, we employ fuzzing and differential testing, inspired by Irfan et al., to validate that the DafnyLite compiler follows the semantics of the standard Dafny compiler. We use XDSmith to randomly generate and compile programs, ensuring their compilations are correct. The non-idiomatic compilers from the open-source distribution of Dafny serve as the ground truth in our differential testing setup. This approach helped us identify and fix multiple bugs in the DafnyLite compiler.

## VII Validation under deployment conditions (excerpts)

The third and final phase is to validate that AuthV2java matches AuthV1's behavior under deployment conditions, using extensive production data. Doing so has several benefits. First, it validates that the specification truly is accurate and complete. Second, it validates that the Dafny verifier's proofs are sound. Third, it validates that the semantics of AuthV2 were preserved by our idiomatic compilers when generating AuthV2java. Every mismatch between AuthV2 and AuthV1 can be investigated to determine the root cause and response, e.g., a change to the specification, a bugfix to a tool, etc. Fourth, the testing reveals performance under production workloads [...]

We shadow-tested throughout 2023, first comparing the two engines on only 0.1% of samples, and steadily raising the sampling rate to 100% as mismatches became less frequent. Doing so revealed corner-case correctness problems where AuthV2's specification had not modeled all the subtleties of AuthV1.

In total, shadow testing exposed 7 mismatches owing to inaccuracies or incompleteness of our specification; no issues were found with tools or proofs. As an example, one mismatch exposed a difference in how AuthV1 and AuthV2java handled Date and Time objects occurring in policies. When developing AuthV2java, we made the decision to drop millisecond resolution in Date and Time objects to simplify the specification and proofs. [...] However, AuthV1 retains millisecond-level precision and under the right circumstances this can, and did, result in different authorization results than AuthV2java. Other mismatches were related to corner cases of wildcard matching and unicode string representation. We fixed all mismatches we encountered as we found them.

We issued 8 shadow iterations of AuthV2java, each a refinement of the previous. The final iteration of AuthV2java agreed with AuthV1 on 10^15 inputs with no observed differences. At this point we launched AuthV2java as the production authorization engine and ran AuthV1 as a shadow to detect any differences that might have evaded our previous shadow testing. After a month of running AuthV1 as a shadow, and finding no differences, we turned it off completely.

Earlier phases of development used traditional testing and synthetic fuzzing inputs to compare AuthV1 and AuthV2java. Although these approaches were effective at finding issues, our concern was that we were not seeing rare, but meaningful, differences that would impact customers at a scale of 1 billions requests per second.

## Related work (excerpt)

Our work is unusual in that we developed a formally verified version of a bespoke legacy system in (highly) active operation. Most of the other work discussed above focused on verifying the implementation of a published standard, e.g., for a language compiler or a cryptographic algorithm. Thus, they had more reliable and meticulous documentation from which to develop the specification, and clearer properties to prove. For us, extensive property-based and differential testing, including against production data, was critical to ensure our specification accurately captured the expected behavior and achieved good performance.

[Comparison with Cedar:] [...] Cedar relies on the correctness of the Lean compiler, since the Lean spec is compiled to C in order to differentially test it.

# Vero: Can AI Agents Build Formally Verified Software Repositories? (abstract, reward-hacking section, Appendix D anti-cheating)

> Source: https://arxiv.org/html/2608.13522
> Collected: 2026-11-10
> Published: 2026-08-13

# Vero: Can AI Agents Build Formally Verified Software Repositories?
Zhe Ye
Hantao Lou
Yuechun Sun
Peiyang Song
Affiliation: California Institute of Technology
Zhengxu Yan
Affiliation: Stanford University
Timothe Kasriel
Affiliation: UC Berkeley
Qingyang Zhang
Affiliation: UC Berkeley
Kaiyu Yang
Affiliation: Apodex
Soonho Kong
Jingxuan He
Affiliation: UC Berkeley
Dawn Song
Affiliation: UC Berkeley
Affiliation: University of Chicago
Affiliation: Amazon Web Services
Abstract
AI agents are increasingly used for programming, but do not provide any guarantee on the correctness of generated code.
Verified code generation, in which an agent produces both an implementation and a machine-checked proof of its specification, offers a stronger path toward trustworthy AI-generated software.
Existing benchmarks in this direction either focus on individual functions or only evaluate proof generation with provided implementations.
It is still an open question whether agents can make coherent implementation and proof choices across real multi-module codebases.
To bridge this gap, we introduce Vero, the first benchmark to evaluate joint implementation and proof synthesis at the repository level.
Vero contains 43 multi-module instances sourced from real-world repositories spanning Python, Dafny, Verus, and Coq, and covering diverse domains from cryptographic protocols to distributed systems.
Each instance consists of a multi-module Lean 4 repository with predetermined API interfaces, manually curated formal specifications, and reference implementations, supporting both proof-only and code-and-proof evaluation modes.
To improve benchmark reliability, Vero also includes an audit mechanism where agents are allowed to formally prove unsatisfiability of provided specification or incorrectness of reference code, which surfaces and corrects latent code and specification errors during curation.
We evaluate frontier coding-agent configurations with Lean toolchain access.
The strongest agent fully solves only 27 of 43 instances and closes no specifications on the hardest repositories.
Vero provides a concrete testbed for measuring progress toward repository-scale verified software synthesis, where current agents still fall short.
We release the benchmark, curation pipeline, and evaluation harness at  https://github.com/sunblaze-ucb/vero.
††footnotetext: *Equal contribution.††footnotetext: †Work does not relate to position at Amazon.
## 1 Introduction
AI agents are increasingly used in software engineering tasks (Jimenez et al., 2024; Yang et al., 2024).
The correctness of agent-produced code, however, is typically assessed through unit tests and human review.
These methods catch anticipated failures but cannot rule out edge-case bugs and security vulnerabilities, which are most damaging in protocol and infrastructure software.
Formal verification offers a stronger alternative: a machine-checked proof that an implementation satisfies its specification rules out, for all inputs, every class of bug the specification captures.
Therefore, it is critical to rigorously assess whether AI agents can perform formal verification at the scale of real-world software.
Existing benchmarks for verified code generation either target individual functions (Lohn and Welleck, 2024; Sun et al., 2024; Dougherty and Mehta, 2025; Ye et al., 2025; Thakur et al., 2025; Bursuc et al., 2025) or evaluate only proof generation with a fixed implementation (Zhong and Si, 2025; Xin et al., 2026; Yang et al., 2025b; Rao et al., 2026), leaving the joint code-and-proof task unaddressed.
Repository-scale verified code generation does not reduce to scaling up function-level techniques, because code, specifications, and proofs are deeply interdependent across files: a proof for one function may depend on lemmas about lower-level utilities, and revising an implementation can invalidate proofs throughout the repository.
Agents must reason globally about the consistency of the entire codebase, rather than locally about a single function.
This is also where verified code generation matters in practice, since real-world verified software, from operating system kernels (Klein et al., 2009; Gu et al., 2016) to cryptographic protocols (Polubelova et al., 2020; Erbsen et al., 2019) and distributed systems (Hawblitzel et al., 2015), lives in repositories rather than standalone functions.
Closing this evaluation gap is essential for measuring and driving progress on agents that can produce verified software at the scale for practical impact.
To bridge this gap, we introduce Vero, the first repository-level benchmark for verified code generation in Lean 4 de Moura et al. (2015).
Vero consists of 43 benchmark instances curated from real-world repositories spanning a diverse set of source languages, including Python, Dafny (Leino, 2010), Verus (Lattuada et al., 2023), and Coq (Barras et al., 1997), and covering a range of domains and difficulty levels from foundational data structures to verified systems.
Sourcing from verification-aware languages allows us to leverage existing formal specifications and proofs as ground truth, while Python repositories expand domain coverage to widely used algorithmic and systems code.
Each instance is a Lean 4 project comprising multiple modules with their data type definitions, auxiliary definitions, API signatures, and human-curated ground-truth specifications.
In total, Vero contains 743 scored APIs and 2,705 specifications, so the 43 repositories correspond to thousands of verification obligations rather than 43 standalone tasks.
We constructed benchmark instances through a multi-stage curation pipeline where every translated definition, specification, and proof obligation is manually reviewed and validated by the authors.
The agent’s task is to fit into this scaffold by discharging two types of obligations: an implementation obligation for each API signature, and a proof obligation for each specification.
Vero supports two task modes.
In the primary code-and-proof mode, agents must discharge both obligations: synthesize implementations for every API and machine-checked Lean 4 proofs that they satisfy all specifications.
In the proof-only mode, reference implementations are additionally provided and the agent discharges only the proof obligations.
Vero is, to our knowledge, the first benchmark that evaluates agents on joint code-and-proof generation at the repository level.
A persistent challenge in constructing formal-verification benchmarks is that even carefully curated specifications and reference implementations can contain subtle errors, a problem documented across formal verification projects and benchmarks (Feng et al., 2026).
Such errors would silently penalize otherwise capable agents and treat benchmark defects as agent failures.
Vero addresses this through a novel audit mechanism.
Rather than treating such errors as unexplained agent failures, the mechanism accepts formal proofs of specification unsatisfiability or reference implementation incorrectness to flag the affected instance for curator review, and uses the formal witnesses to guide correction.
During curation, the audit mechanism surfaced several latent errors that escaped manual review, and helped guide the benchmark improvement by providing formal evidences like counter examples.
We evaluate four frontier model configurations under two coding-agent harnesses on Vero across both task modes.
Vero is frontier-resistant: the best-performing configuration fully solves only 27 of 43 instances in code-and-proof, and 10 instances resist every configuration in both modes.
Our analysis further reveals that the unsolved instances concentrate on specifications encoding cross-module invariants, protocol consistency, and custom mathematical theories, where current agents attempt local proofs of individual specifications rather than building the reusable lemma libraries that verification at this scale requires.
We further find that implementation freedom in code-and-proof cuts both ways.
Agents can sidestep hard-to-verify reference algorithms by writing simpler implementations that satisfy the same specifications.
On harder instances, however, agents fail to coordinate the two artifacts, producing rewrites that break existing proofs or introduce build errors elsewhere in the repository.
Together these findings provide concrete directions for advancing repository-scale verified code generation.
Contributions.
In summary, we make the following key contributions:
- • 
We introduce Vero, the first repository-scale benchmark for verified code generation in Lean 4, comprising 43 instances curated from real-world repositories across diverse source languages and domains, together with a semi-automated, multi-language curation pipeline that supports its construction and future extension.
- • 
We design a formal audit mechanism that accepts machine-checked proofs of specification unsatisfiability or reference implementation incorrectness, turning latent benchmark errors into actionable findings and enabling continuous quality improvement as agents grow more capable.
- • 
We conduct a comprehensive evaluation of state-of-the-art coding agents and frontier LLMs on Vero across two task modes, providing rigorous baselines and actionable insights toward scalable, automated software verification.
## 2 Background and Related Work
Existing benchmarks for verified code generation share several limitations that constrain their utility for evaluating coding agents in realistic settings.
First, most benchmarks evaluate verified code generation only at the level of individual functions.
In Lean 4, miniCodeProps (Lohn and Welleck, 2024), FVAPPS (Dougherty and Mehta, 2025), VERINA (Ye et al., 2025), and CLEVER (Thakur et al., 2025) all target standalone tasks drawn from algorithmic problem sets such as HumanEval (Chen et al., 2021), MBPP (Austin et al., 2021), and APPS (Hendrycks et al., 2021).
The same pattern holds in benchmarks for SMT-based verifiers such as Dafny (Leino, 2010) and Verus (Lattuada et al., 2023): DafnyBench (Loughridge et al., 2025), VerusBench (Yang et al., 2025a), AlgoVeri (Zhao et al., 2026), VeriCoding (Bursuc et al., 2025), VerifyThisBench (Deng et al., 2025), and VeriEquivBench (Zeng et al., 2025) all operate on individual algorithms or methods.
While these benchmarks have driven measurable progress on isolated tasks, they cannot capture the cross-module dependencies and long-horizon reasoning that real-world verified codebases require.
Vero addresses this gap by curating multi-module Lean 4 projects with type definitions, API signatures, and specifications spread across files, requiring agents to reason about the consistency of the entire repository.
Second, the few existing repository-scale benchmarks evaluate proof generation alone, leaving the joint code-and-proof task unaddressed.
RVBench (Zhong and Si, 2025) provides 755 proof completion tasks across four Verus projects; VeruSAGE-Bench (Yang et al., 2025b) contains 849 proof tasks extracted from eight Verus-verified Rust systems; and VeriSoftBench (Xin et al., 2026) packages 500 Lean 4 proof obligations from open-source formal-methods developments.
For Coq, CoqStoq (Thompson et al., 2025) offers a large corpus of repository-level theorems for proof synthesis, while case studies such as FSCQ proof generation (Qin et al., 2025) target proof completion in verified system software.
All these benchmarks provide reference implementations and evaluate only the agent’s ability to discharge proof obligations.
This setting omits a fundamental challenge of repository-scale verified code generation, since the choice of implementation directly affects which proofs are tractable and the two artifacts must be coherent across the entire repository.
Vero addresses this by supporting both proof-only and code-and-proof modes, with the latter requiring agents to jointly synthesize implementations and machine-checked proofs across the repository, exposing the implementation-proof coupling that prior repository-scale benchmarks abstract away.
To our knowledge, Vero is the first benchmark to evaluate joint code-and-proof generation at the repository level.
Third, prior benchmarks are limited in scope and face contamination risks.
A large body of Lean 4 benchmarks targets formalized mathematics rather than software, including LeanDojo (Yang et al., 2023), LeanAgent (Kumarappan et al., 2024), and APE-Bench (Xin et al., 2025), all built on the Mathlib library (Mathlib community, 2020).
Although these benchmarks have driven impressive progress in neural theorem proving, the structure of mathematical proof differs substantially from the verification of imperative software, where reasoning is coupled to executable definitions, data types, and effectful behavior.
A separate concern is the contamination of training data, since reference solutions for many widely used program sources are freely available online and may have been included in the pretraining data of evaluated models (Jain et al., 2024; Riddell et al., 2024).
Benchmarks that directly reuse such sources inherit this exposure when the underlying problems and their reference solutions remain widely accessible.
Vero addresses this by sourcing tasks from real-world repositories across multiple source languages and producing novel Lean 4 formalizations through manual curation, so that no Lean 4 ground-truth proof for any benchmark instance is directly available.
This translation from source languages to Lean 4 is itself novel curation work, providing a structural contamination guarantee that complements the diversity of domains and difficulty levels in the corpus.
Finally, prior benchmarks rarely consider evaluation protocols designed for agent-based settings.
Most existing benchmarks evaluate raw LLM outputs in single-shot or simple iterative settings, without the tool access that deployed coding agents use in practice.
In contrast, Vero evaluates frontier coding agents with full tool access.
Furthermore, prior benchmarks provide no mechanism to detect or correct errors in their own ground truth, a concern recently surfaced in formal verification benchmarks (Feng et al., 2026).
[...omitted: benchmark design, results...]
#### Preventing reward hacking.

To ensure the benchmark evaluates genuine verification work, the grader prevents both edits to benchmark content and proof-trivializing mechanisms.
First, we use explicit markers to constrain the regions agents may modify.
The grader extracts only contents from these regions and inserts them into a fresh copy of the source benchmark before grading.
Second, an axiom allowlist rejects proofs that depend on agent-introduced or untrusted axioms.
Finally, a rule-based detector and an LLM judge screen agent-introduced declarations for mechanisms that can trivialize proofs or decouple logical semantics from executable behavior, including malicious typeclass instances and noncomputable choice combined with @[implemented_by] (e.g., through Exists.choose).
We discuss these anti-cheating mechanisms in Appendix D.

[...omitted...]
## Appendix D Anti-Cheating Mechanisms
The grader must decide whether an agent has verified a repository or merely arranged for the checker to agree with it.
Vero enforces this through three independent layers, described in turn below.
Each layer is deterministic except the final judge, and each rejects submissions that a naive “does it compile” check would accept.
#### Layer 1: slot-scoped re-rendering.
An agent works in a sandbox containing the full repository, but only the interiors of !benchmark marker pairs are treated as its submission.
The grader extracts those interiors and overlays them onto a fresh copy of the pristine instance before compiling anything.
Every declaration outside a marker pair therefore reverts to the curated original, which removes an entire family of attacks at once: weakening a specification, redefining a frozen helper, relaxing a type signature, or deleting a proof obligation.
#### Layer 2: axiom allowlist.
Compilation alone does not establish that a proof is honest, because Lean admits sorry and user-declared axioms as well-typed terms.
After the build succeeds, the grader emits #print axioms for every scored theorem and classifies its dependency set.
Only the three standard axioms of Lean’s logic are accepted, namely Classical.choice, propext, and Quot.sound.
A curator may extend this set per instance through manifest.trusted_axioms, which is recorded in the released benchmark.
A theorem that depends on sorryAx grades as unfilled, and one that depends on any other axiom grades as axiom_leaked.
Neither counts as passed.
This layer is not hypothetical.
Across the corpus 368368 specification outcomes are rejected at this stage, and they concentrate in instances with large finite domains: base58 (6767), verified_bitmasks (6060), reedsolo (5353), and sortedcontainers (5252).
The dominant pattern is native_decide, which discharges a decidable goal by evaluating it in the compiler rather than in the kernel and records a dependency on Lean.ofReduceBool.
On base58, for instance, GPT-5.5 (xhigh) closes the Base58 alphabet round-trip this way:
⬇
1
theorem b58Idx_b58Char_fin (d : Fin 58) :
2
b58Idx (b58Char d.val) = some d.val := by
3
native_decide +revert
The claim is true and the tactic is legitimate Lean, but it is not a kernel-checked proof and it does not generalize beyond the finite domain it enumerates.
Twenty-eight of that cell’s 5353 specifications fail for this reason while 2525 pass, which is why the failure-reason breakdown in Figure 7(b) separates rejected shortcuts from unattempted obligations.
#### Layer 3: declaration screening.
The final layer inspects agent-introduced declarations for constructions that decouple logical semantics from executable behavior.
For typeclass instances, a rule-based prefilter raises two signals, a hollow constant body and a priority override that shadows a standard-library instance, and an LLM judge then classifies each flagged site as legit or cheat from a window of surrounding source.
When both signals fire together the site is classified as a cheat without consulting the judge.
A separate deterministic check covers the case where an agent splits the proof target from the runtime function, described last below.
Each pattern is invisible to the first two layers, because each compiles and none introduces an axiom.
We give one example of each.
Hollow body on a non-trivial typeclass.
An ordering instance whose body ignores both arguments makes every comparison reduce to True:
⬇
1
instance : LE Float := <fun _ _ => True>
Any specification phrased over <= then closes by decide regardless of what the implementation computes.
The signal is that the standard meaning of LE on Float is not constant, so a body that discards its arguments cannot be computing it.
Priority shadowing.
The same hollow body becomes more dangerous when it displaces a real instance rather than filling a gap:
⬇
1
instance (priority := 2000) : LT Float := <fun _ _ => True>
Lean resolves standard-library instances at priority around 10001000, so a declared priority of 20002000 takes precedence over Float’s genuine ordering everywhere in the repository, including inside specifications the agent never touched.
Because this pattern combines two independent signals, the prefilter classifies a hollow body together with a priority override as a cheat without consulting the judge.
Decidability laundering.
A Decidable instance may assert its own verdict instead of computing one:
⬇
1
instance : DecidableEq (Foo -> Bar) := fun _ _ => .isTrue (by sorry)
2
theorem prove_x : spec_x canonical := by decide
Here the axiom check does catch the sorry, but the variant .isTrue (by trivial) on a proposition that happens to be provable in a trivial instance, or := trivial supplied directly as a Decidable body, leaves no axiom trace while still making decide report isTrue.
Splitting the proof target from the runtime function.
The most consequential pattern does not involve typeclasses at all, so we screen it separately.
An agent can define the scored API as a noncomputable copy of the specification’s own witness oracle, and then attach a real algorithm through @[implemented_by]:
⬇
1
noncomputable def findPathCost : FindPathCostSig :=
2
fun g s t => if h : exists c, isMinWalkCost g s t c then h.choose else 0
3
@[implemented_by realBellmanFord] def findPathCost’ := findPathCost
Every optimality proof about findPathCost is then definitionally true, because the function is the specification’s answer set, while the compiled binary still runs a correct shortest-path algorithm.
We encountered this during benchmark development on dijkstar, where the submission produced no output difference from the reference across 20,44020{,}440 generated graphs and would have passed any differential test.
It is also general: the technique defeats any unique-optimum specification suite no matter how the specifications are strengthened, which is why the defense has to live in the grader.
The grader now rejects @[implemented_by] in any agent-editable Impl/ file outright, voiding the run and grading every specification impl_oracle, since the attribute has no legitimate use in an implementation slot.
Reference definitions on the proof side that are noncomputable without the attribute, such as flocq’s use of Classical.choose, are unaffected.
## Appendix E Additional Evaluation Results
### E.1 Instances Have Shared Walls, Not Random Residuals
[...omitted: remaining appendices...]

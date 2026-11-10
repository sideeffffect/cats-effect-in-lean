# go-in-lean: Exploring Go correctness with AI agents, Lean 4 and QEMU (Go Forum)

> Source: https://forum.golangbridge.org/t/go-in-lean-exploring-go-correctness-with-ai-agents-lean-4-and-qemu/42766
> Collected: 2026-11-10
> Published: 2026-11-03

Author: s-celles (Sébastien Celles). Thread had 1 post (no replies) at collection time. Repo: https://github.com/s-celles/go-in-lean

---

Hi everyone!
First, a quick introduction. I'm a physics and computer science teacher in France, not a Go expert. I wrote a little Go code a few years ago for a telemetry project involving an electric go-kart, but that's about it!
Recently, two articles caught my attention:

- Formalizing Julia in Lean and finding 400 bugs in Base, about Miles Cranmer's impressive experiment with AI-assisted formal verification.
- A LinuxFr article about AI usage within the Go team, reporting Cameron Balahan's comments about AI-generated contributions and the importance of thorough human verification.

I found the Go team's position particularly interesting. Contributors can use AI, but they remain responsible for verifying their work, and the Go team reviews submissions line by line.
That makes sense, especially for a compiler. But it also made me wonder: could AI agents help investigate the correctness of Go itself, provided their findings are independently verifiable?
So I decided to experiment!

## Introducing go-in-lean

go-in-lean is an experimental open-source project inspired by julia-in-lean.
The project is largely developed with AI coding agents, combining:

- AI agents to explore Go's source code, build formal models, generate Lean proofs, and investigate potential bugs.
- Lean 4 to verify properties of standard library functions and compiler SSA optimizations.
- Differential and metamorphic testing to compare expected behavior against actual Go implementations.
- QEMU on my personal homelab to test ARM, MIPS, RISC-V, PowerPC, s390x, and other architectures.
- Human review to validate findings before reporting them upstream.

## How is it different from julia-in-lean?

Miles Cranmer's project already uses AI agents, formal proofs, and differential testing. I'm building on that methodology, but exploring a few additional directions:

- Compiler internals: investigating SSA rewrite rules and architecture-specific optimizations, beyond standard library functions.
- Bit-precise reasoning: using Lean's BitVec and bv_decide to verify fixed-width integer operations, with explicit auditing of the additional proof assumptions.
- Cross-architecture testing: running QEMU-based fuzzing campaigns on my homelab, without needing physical hardware for every target architecture.

The QEMU part turned out to be particularly useful. Some compiler bugs only appear on specific architectures.

## Early results

The experiment has already uncovered several reproducible Go compiler miscompilations, including architecture-specific issues, reported upstream.
A few examples:

- golang/go#82763
- golang/go#82767
- golang/go#82772

Of course, proving a property of a Lean model doesn't prove the correctness of the actual Go implementation. Every suspected bug must be reproduced, and QEMU testing has its limitations.

## Why am I sharing this?

I'm interested in the methodology as much as the bugs themselves.
Can AI agents help us investigate complex software outside our primary areas of expertise, while formal methods, reproducible testing, and human review help establish confidence in the results?
I'm certainly learning a lot about Go and its compiler along the way, and I would appreciate feedback from people who know them much better than I do.
Repository: GitHub - s-celles/go-in-lean: A proof-of-concept to find correctness bugs in Go's standard library with Lean 4.
Feedback, criticism, and contributions are very welcome!

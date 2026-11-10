# Introducing Gauss, an agent for autoformalization (Math, Inc.)

> Source: https://www.math.inc/gauss
> Collected: 2026-11-10
> Published: Unknown (2025-09, per press coverage)

Introducing Gauss, an agent for autoformalization — Math, Inc.
Math, Inc.
Back Home
# Introducing Gauss, an agent for autoformalization
The Math Inc. team is excited to introduce Gauss, a first-of-its-kind autoformalization agent for assisting human expert mathematicians at formal verification. Using Gauss, we have completed a challenge set by Fields Medallist Terence Tao and Alex Kontorovich in January 2024 to formalize the strong Prime Number Theorem (PNT) in Lean (GitHub).
The translation of human mathematics into verifiable machine code has long been a grand challenge. However, the cost of doing so is prohibitive, requiring scarce human expertise. In particular, after 18 months, Tao and Kontorovich recently announced intermediate  progress in July 2025 toward their goal, obstructed by core difficulties in the field of complex analysis.
In light of such difficulties, we are pleased to announce that with Gauss, we have completed the project after three weeks of effort. Gauss can work autonomously for hours, dramatically compressing the labor previously reserved for top formalization experts. Along the way, Gauss formalized the key missing results in complex analysis, which opens up future initiatives previously considered unapproachable.
Using Gauss we produced ~25,000 lines of Lean code, comprising over 1,000 theorems and definitions. Formal proofs of this scale have historically been major milestones, often the culmination of multi-year efforts. The largest singular formalization projects in history — career-defining efforts, which can span more than a decade — are only an order of magnitude larger at up to 500,000 lines of code. Lean’s standard mathematical library, Mathlib, is an order of magnitude beyond that, at around 2,000,000 lines of code, comprising 350,000 Lean theorems and definitions, and developed by over 600 human contributors over eight years.
The Trinity environments infrastructure, developed in partnership with Morph Labs, was instrumental for this project. Scaling Lean verification environments to the scope at which Gauss operates — thousands of concurrent agents, each with its own Lean runtime, consuming multiple terabytes of cluster RAM — is an extremely complex systems engineering challenge, for which Infinibranch on Morph Cloud was critical.
Gauss offers a glimpse of how formalization will scale into the future. Currently, it relies on natural language scaffolding supplied by human mathematicians, and requires high-level expert guidance and development on that scaffolding. We anticipate future iterations of Gauss to be more capable and autonomous.
We will begin deploying our technology to make it useful to working mathematicians and proof engineers. Presently, we are in contact with a select group of mathematicians for beta testing. You can register for early access to Gauss here. Please reach out to us if you have an ambitious idea for autoformalization.
Our results represent the first steps towards formalization at an unprecedented scale. Gauss will soon dramatically compress the time to complete massive initiatives. With further algorithmic improvements, we aim to increase the sum total of formal code by 2-3 orders of magnitude in the coming 12 months. This will serve as the training ground for a new paradigm — verified superintelligence and the machine polymaths that will power it.
We gratefully acknowledge the support of DARPA’s expMath program.
Math, Inc.

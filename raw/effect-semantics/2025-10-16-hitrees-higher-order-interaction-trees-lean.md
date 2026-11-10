# HITrees: Higher-Order Interaction Trees

> Source: https://arxiv.org/abs/2510.14558
> Collected: 2026-11-10
> Published: 2025-10-16

Authors: Amir Mohammad Fadaei Ayyam, Michael Sammler

## Abstract

Recent years have witnessed the rise of compositional semantics as a foundation for formal verification of complex systems. In particular, interaction trees have emerged as a popular denotational semantics. Interaction trees achieve compositionality by providing a reusable library of effects. However, their notion of effects does not support higher-order effects, i.e., effects that take or return monadic computations. Such effects are essential to model complex semantic features like parallel composition and call/cc. We introduce Higher-Order Interaction Trees (HITrees), the first variant of interaction trees to support higher-order effects in a non-guarded type theory. HITrees accomplish this through two key techniques: first, by designing the notion of effects such that the fixpoints of effects with higher-order input can be expressed as inductive types inside the type theory; and second, using defunctionalization to encode higher-order outputs into a first-order representation. We implement HITrees in the Lean proof assistant, accompanied by a comprehensive library of effects including concurrency, recursion, and call/cc. Furthermore, we provide two interpretations of HITrees, as state transition systems and as monadic programs. To demonstrate the expressiveness of HITrees, we apply them to define the semantics of a language with parallel composition and call/cc.

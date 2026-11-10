# Choice Trees: Representing Nondeterministic, Recursive, and Impure Programs in Coq

> Source: https://arxiv.org/abs/2211.06863
> Collected: 2026-11-10
> Published: 2022-11-13

Authors: Nicolas Chappe, Paul He, Ludovic Henrio, Yannick Zakowski, Steve Zdancewic

## Abstract

This paper introduces Choice Trees (ctrees), a monad for modeling nondeterministic, recursive, and impure programs in Coq. Inspired by Xia et al.'s itrees, this novel data structure embeds computations into coinductive trees with three kind of nodes: external events, and two variants of nondeterministic branching. This apparent redundancy allows us to provide shallow embedding of denotational models with internal choice in the style of ccs, while recovering an inductive LTS view of the computation. CTrees inherit a vast collection of bisimulation and refinement tools, with respect to which we establish a rich equational theory. We connect ctrees to the itrees infrastructure by showing how a monad morphism embedding the former into the latter permits to use ctrees to implement nondeterministic effects. We demonstrate the utility of ctrees by using them to model concurrency semantics in two case studies: ccs and cooperative multithreading.

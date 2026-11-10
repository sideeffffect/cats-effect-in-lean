# cats-effect-in-lean

A formalization of [Cats Effect](https://typelevel.org/cats-effect/) in [Lean 4](https://lean-lang.org/), made to find bugs in Cats Effect.

We model the real Scala code of Cats Effect in Lean, line by line.
We test the model against the real library on many generated programs.
Then we state the properties that Cats Effect promises (its laws, its documentation, and obvious invariants) and prove or refute each one.
A refuted property becomes a bug report only when a Scala reproducer shows the bug on the real library.

The method follows two earlier projects that found hundreds of bugs this way:

- [python-formalization](https://github.com/Broyojo/python-formalization) (CPython in Lean) — [blog post](https://broyojo.com/python-formalization)
- [julia-in-lean](https://github.com/MilesCranmer/julia-in-lean) (Julia Base in Lean) — [announcement](https://discourse.julialang.org/t/formalizing-julia-in-lean-and-finding-400-bugs-in-base/140243)

Cats Effect is a concurrent runtime. That is new compared to these projects. The model must handle fibers, cancellation, masking, finalizers, and scheduling choices.

## Status

**Research phase.** No formalization yet. The research is in the [knowledge wiki](wiki/index.md). Start with [Lessons for Cats Effect in Lean](wiki/methodology/lessons-for-cats-effect.md).

## Pinned versions

| Component | Version |
|---|---|
| Cats Effect | v3.7.1 (commit `eb0cc258`, 2026-08-23), the latest stable release |
| Lean | `leanprover/lean4:v4.35.0` |

## Repository layout

| Path | Content |
|---|---|
| `AGENTS.md` | Rules for AI agents: method, review rubric, proof rules, wiki rules |
| `wiki/` | Knowledge wiki: compiled articles ([index](wiki/index.md), [log](wiki/log.md)) |
| `raw/` | Source material for the wiki (unchanged copies of papers, docs, posts) |
| `CatsEffectInLean/` | Lean library (scaffold only for now) |

## Build

```sh
lake build
```

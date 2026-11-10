# Model

Mirrors of the Cats Effect v3.7.1 Scala code (`IOFiber` run loop, scheduler, primitives). Plan: Phase 2 of `wiki/methodology/project-plan.md`.

- Mirror the Scala source line by line. Cite `<path>:<line>` at v3.7.1.
- No `partial def`. Loops use fuel; "out of fuel" is a separate result.
- Keep the model kernel-evaluable: `wiki/lean/kernel-evaluation.md`.

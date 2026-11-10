# Props

Property definitions only: `def <name> : Prop := ...`. No proofs. No local `notation`.

- Module name: `CatsEffectInLean.Props.<Area>` (for example `Props.Kernel`). The registry audit rejects a `prop` from a module outside `CatsEffectInLean.Props`.
- Quantify over all inputs and all schedules. Each hypothesis must be a documented precondition or a type invariant.
- The docstring cites the promise (law, Scaladoc, doc sentence) as `<path>:<line>` at v3.7.1.
- Register each property in `CatsEffectInLean/Registry.lean`. See `wiki/methodology/registry-and-audit.md`.

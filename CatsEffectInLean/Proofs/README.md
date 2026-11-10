# Proofs

Theorems that settle registered properties.

- Module name: `CatsEffectInLean.Proofs.<Area>`. The registry audit rejects a theorem from a module outside `CatsEffectInLean.Proofs`.
- `theorem <prop>_proven : <prop>` or `theorem <prop>_refuted : ¬ <prop>`. Write the property constant itself, not its unfolded body. The audit compares the types syntactically.
- Only the axioms `propext`, `Classical.choice`, `Quot.sound`. The audit checks this with `collectAxioms`.
- Forbidden constructs: see `AGENTS.md` and `scripts/check_forbidden.py`.

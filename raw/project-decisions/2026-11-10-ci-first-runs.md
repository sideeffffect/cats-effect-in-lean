# CI first runs: failures and fixes (own note)

> Source: GitHub Actions runs 42779557803, 42779674349, 42779596087 on sideeffffect/cats-effect-in-lean, and local runs
> Collected: 2026-11-10
> Published: 2026-11-10

1. CI run 42779557803 failed in lean-action's leanchecker step: "uncaught exception: Could not find any oleans for: «Cats-effect-in-lean»". leanchecker defaults to a module named after the package. Reproduced locally with `lake env leanchecker`; `lake env leanchecker CatsEffectInLean` passes. Fix: `leanchecker-args: "CatsEffectInLean"` (and `axiom-audit-root: "CatsEffectInLean"`).
2. CI run 42779674349 after the fix: all 3 jobs green (Wiki lint 4s, Forbidden 4s, Lean build and proof checks 2m22s). The sandboxed `lake check` passed on the GitHub ubuntu-24.04 runner after scripts/setup-bwrap-apparmor.sh ("Lean default kernel accepts the solution", "Uses axioms: Classical.choice, propext, Quot.sound").
3. Paranoid run 42779596087 failed in lean-action's nanoda step: "Detected module name: \"cats-effect-in-lean\"", then lean4export "PANIC at Option.get!" and "import failed, trying to import module with anonymous name". lean-action has no input to set that module name. Fix: drop the lean-action nanoda input; `lake check --paranoid` already runs a bundled nanoda.
4. Local `lake check --paranoid` (3m46s) runs: Lean paranoid kernel, lean4lean, nanoda ("Skipped exported but unpermitted axioms [\"sorryAx\"]" — sorryAx is exported by core but not used; the final axiom check still rejects it if used), con-leche (57,920 declarations), con-ron (57,920), Lean default kernel. All accept.

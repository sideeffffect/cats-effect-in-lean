# Local experiments on Lean v4.35.0 (research agent notes)

> Source: own experiments on this machine (scratch files outside the repo), plus `gh` API queries
> Collected: 2026-11-10
> Published: 2026-11-10

## Environment

- `~/.elan/bin/elan toolchain list` -> `leanprover/lean4:v4.35.0` (only toolchain installed).
- `lean`/`lake` are NOT on PATH in non-login bash; use `~/.elan/bin/lean` / `~/.elan/bin/lake`.
- The v4.35.0 toolchain `bin/` ships: `lean4lean`, `nanoda_bin`, `con-leche`, `con-ron`,
  `leanchecker`, `leanchecker-paranoid`, `leanexport`, `cadical`, `leantar`.

## Version / compatibility facts (gh API, 2026-11-10)

- lean4 releases: v4.35.0 = Latest (2026-10-12). v4.36.0-rc2 (2026-10-27) is the newest pre-release.
  v4.34.1 (2026-09-24) is a backport release.
- Tag `v4.35.0` exists in: mathlib4, batteries, plausible, aesop, leanprover-community/repl.
- lean-action latest: v1.7.1 (2026-11-06). lean-lsp-mcp latest: v0.33.0 (2026-11-03).
- cameronfreer/lean4-skills: 483 stars, updated 2026-11-08.
- Cats Effect latest releases: v3.7.1 (2026-08-23), v3.6.4 (2026-08-22), v3.7.0 (2026-03-08).
- Broyojo/python-formalization `lean/lean-toolchain` = `leanprover/lean4:v4.35.0`.

## Experiment 1: fuel interpreter + decide / native_decide / rfl

```lean
inductive Op where | pure (n : Nat) | bind (a : Op) (k : Nat) | loop
  deriving Repr, DecidableEq, BEq, Hashable, Inhabited

def stepFuel : Nat → Op → Option Nat
  | 0, _ => none
  | _+1, .pure n => some n
  | f+1, .bind a k => (stepFuel f a).map (· + k)
  | f+1, .loop => stepFuel f .loop
```

- `#eval stepFuel 10 .loop` -> `none` (fuel exhausted).
- `by decide` proof: `#print axioms` -> "does not depend on any axioms".
- `by native_decide` proof: `#print axioms` -> `[t2._native.native_decide.ax_1_1]`
  (one auto-generated axiom per native computation; not `Lean.ofReduceBool` any more).
- `by rfl` also works for structural fuel recursion.

## Experiment 2: partial_fixpoint interpreter (no fuel)

- `partial_fixpoint` with `(run a).map (· + k)` FAILS: "Could not prove 'run' to be monotone
  in its recursive calls: Cannot eliminate recursive call `run a` enclosed in Option.map".
- Rewriting the same branch as `do let x ← run a; return x + k` WORKS.
- Then `decide_cbv`, `simp [run]` and `grind [run]` all prove
  `run (.bind (.pure 1) 2) = some 3`; axioms = only `propext, Classical.choice, Quot.sound`.
- Lean generates `run.partial_correctness` (an induction principle for results `run o = some r`).
- `#eval run ...` works (compiled code uses the original recursion).

## Experiment 3: `partial def`

- `partial def runP ...`: `rfl`, `decide`, `unfold runP` all FAIL to prove `runP (.pure 1) = 1`.
  A `partial` function is opaque to the logic; only usable for execution (#eval / difftest exe).

## Experiment 4: `lake check` on this repo scaffold

- `lake check` fails on this machine: `bwrap: setting up uid map: Permission denied`.
  Cause: `/proc/sys/kernel/apparmor_restrict_unprivileged_userns` = 1 (Ubuntu 24.04 default).
- `lake check --inadvisably-no-sandbox` works: "Lean default kernel accepts the solution.
  Uses axioms: Classical.choice, propext, Quot.sound".
- Note: GitHub `ubuntu-24.04` runners probably have the same AppArmor restriction (UNVERIFIED).

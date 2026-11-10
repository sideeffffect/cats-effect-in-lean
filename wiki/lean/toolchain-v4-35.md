# Lean v4.35.0 toolchain facts

> Sources: Lean FRO release notes, 2026-10-12; Lean reference manual (recursive definitions, tactics); local experiments, 2026-11-10
> Raw: [lake check bwrap note](../../raw/lean-tooling/2026-11-10-lake-check-bwrap-apparmor-note.md); [v4.35.0 release notes](../../raw/lean-tooling/2026-10-12-lean-v4-35-0-release-notes.md); [v4.29–v4.34 highlights](../../raw/lean-tooling/lean-v4-29-to-v4-34-release-highlights.md); [Recursive definitions](../../raw/lean-tooling/lean-reference-recursive-definitions.md); [decide / cbv / vcgen](../../raw/lean-tooling/lean-reference-tactics-decide-cbv-vcgen.md); [Local experiments](../../raw/lean-tooling/2026-11-10-local-experiments-lean-v4-35-0.md)

## Overview

The project uses `leanprover/lean4:v4.35.0` (latest stable, 2026-10-12; v4.36.0-rc2 exists). python-formalization uses the same toolchain. Mathlib, Batteries, Plausible, Aesop and the REPL all have a `v4.35.0` tag. Prefer core Lean (both precedents used no Mathlib); add Plausible if needed.

## What matters in v4.35.0

- **`lake check`**: builds, replays through the kernel, fails on non-standard axioms. `--paranoid` also runs bundled independent kernels (lean4lean, nanoda, con-leche, con-ron, leanchecker-paranoid).
- **`lake comparator`**: checks that a solution proves exactly the statement of a challenge file.
- **`vcgen`** replaces deprecated `mvcgen` (experimental: `set_option experimental.vcgen true`).
- **`Decidable` is a structure** (Bool + proof). Write instances with `decidable_of_iff` / `decidable_of_bool`.
- **`native_decide`**: `ofReduceBool`/`trustCompiler` are removed; each use adds its own auto-generated axiom (e.g. `foo._native.native_decide.ax_1_1`) since v4.29. `#print axioms` shows it.
- `rwa` redesigned; `constructor` warns on ambiguity; `lia` takes lemma lists; `grind` handles `BitVec`/`UInt*`.

## Recursion choices for an interpreter (tested on v4.35.0)

| Style | Executable | Provable | Notes |
|---|---|---|---|
| Fuel (structural on `Nat`) | yes | yes; `decide`/`rfl` use no axioms | Fuel-out is a separate outcome, never a CE outcome. Precedents use this. |
| `partial_fixpoint` | yes | yes; `decide_cbv`, `simp [f]`, `grind [f]` work; generates `f.partial_correctness` | Recursive call must be under `do`/bind; `Option.map` around it fails the monotonicity check. |
| `partial def` | yes | **no** (opaque: `rfl`, `decide`, `unfold` fail) | Use only for the difftest `main` loop. |

## Environment gotchas (this machine)

- `lean`/`lake` are only in `~/.elan/bin`, not on PATH in non-login bash.
- `lake check` fails with `bwrap: setting up uid map: Permission denied`. Cause: Ubuntu's `kernel.apparmor_restrict_unprivileged_userns=1` gives a new user namespace no capabilities unless an AppArmor profile grants `userns`; `/usr/bin/bwrap` is not setuid and has no such profile. `unshare -Ur id` fails the same way.
- Why it matters: `lake check` builds the project inside a bwrap sandbox (read-only `/`, home hidden, only `.lake` writable, no network during build). Lean runs arbitrary code at build time (macros, `#eval`, `initialize`), so without the sandbox, agent-written code could tamper with the check. `--inadvisably-no-sandbox` works but "can compromise the result fully".
- Fixes (need sudo): an AppArmor profile granting `userns` to bwrap (narrowest; script `sudo scripts/setup-bwrap-apparmor.sh`, undo with `--remove`; profile syntax checked with `apparmor_parser -Q -K`, not yet run); setuid bwrap; disable the sysctl globally (least preferred); or run `lake check` in CI/a VM where user namespaces work. GitHub ubuntu-24.04 runners: unverified.

## Pitfalls

- Monthly releases break things (`Decidable` redefined, `rwa`, `mvcgen`). Upgrade on purpose, in one change, never casually.
- Cap memory: `moreLeanArgs = ["-M8000"]` (python-formalization). Avoid big kernel `decide`; use `decide_cbv`.
- Brittle proofs: prefer `simp`/`grind` with explicit lemma lists over long `rw` chains; generated equation names change between releases.

## See Also

- [Proof hygiene and agent tooling](proof-hygiene-and-agent-tooling.md)
- [Differential testing](../methodology/differential-testing.md)

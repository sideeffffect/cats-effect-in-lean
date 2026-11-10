# Registry and audit: implementation notes (Phase 1 steps 1, 3, 4)

> Source: own work in this repository (`CatsEffectInLean/Registry.lean`, `tools/Audit/Core.lean`, `test/AuditFixtures/`, `scripts/test_audit.sh`), Lean v4.35.0
> Collected: 2026-11-10
> Published: 2026-11-10

## What was built

- Directories: `CatsEffectInLean/{Model,Props,Proofs}/` (README only), `bugs/`, `reproducers/`, `review/`, `difftest/` (README with purpose and format).
- `CatsEffectInLean/Registry.lean`: `Status` (`open | proven | refuted`), `Entry` (`id`, `rows`, `prop : Lean.Name`, `status`, `thm : Option Name`, `bug : Option String`, `note`), `registry : List Entry := []`.
- `tools/Audit/Core.lean` (lean_lib `Audit`, srcDir `tools`): `Audit.run : Config → IO UInt32`. `tools/Audit/Main.lean` is `lake exe audit` for the real registry.
- `test/AuditFixtures/` (lean_lib `AuditFixtures`, not a default target) and `lake exe audit_fixture <case>`: one good registry and 12 fault cases.
- `scripts/test_audit.sh`: builds the fixtures, expects `good` to pass and each fault case to fail with a given message.
- CI: steps `lake exe audit` and `scripts/test_audit.sh` in the `lean` job; new job `inventory` runs `scripts/check_inventory.py`.

## Design choices

1. The registry stores `Name`s written with double backticks. Lean checks at compile time that the constant exists.
2. The audit is a compiled executable that imports the registry as code and loads the `.olean` environment with `importModules` at run time. So it needs no `evalConst` and no `unsafe`.
3. Type check is syntactic `Expr` equality (`==`) against `.const prop []` or `mkApp (.const ``Not []) (.const prop [])`. No unfolding, no `isDefEq`. Stored theorem types have no metavariables, so `instantiateMVars` is not needed. A theorem of the unfolded body is rejected (fixture `unfolded`).
4. Axioms: `Lean.collectAxioms` (run in `CoreM` with `CoreM.toIO'`) for both `prop` and `thm`. Allowed: `propext`, `Classical.choice`, `Quot.sound`.
5. Module prefix check: `prop` must come from `CatsEffectInLean.Props.*`, `thm` from `CatsEffectInLean.Proofs.*` (`Environment.getModuleIdxFor?`). This keeps proofs and helper lemmas out of property files.
6. `refuted` needs `bug` = an existing file path. `open` must have no theorem.
7. Inventory: every entry row exists in the CSV; every `modelled` row names at least one entry in the `registry` column (`;` separates several); every named entry exists and lists the row.
8. CSV parser: structural recursion on `List Char`, handles quotes, doubled quotes and CRLF. Parses 3,255 rows of the real inventory.
9. Audit code and fixtures are outside the `CatsEffectInLean` library. `lake build`, `lake check` and the lean-action axiom audit see only the library.
10. The fault case `bad_axiom` needs a declared axiom. `scripts/check_forbidden.py` forbids that in any committed `.lean` file. So the script writes `test/AuditFixtures/Generated/BadAxiom.lean` (git-ignored), builds it and deletes it on exit. The fixture names that theorem with a single backtick (no compile-time check).

## Gotchas (Lean v4.35.0)

- `String.trim` does not exist. Use `s.trimAscii` (gives a `String.Slice`; use `.toString` or `.isEmpty`).
- `lake build +Mod.Name` builds one module target.
- `ModuleIdx` is a `Nat` abbreviation; `idx.toNat` works.
- The user's global gitignore ignores `*.csv`. `.gitignore` now re-includes `test/AuditFixtures/*.csv`.
- `scripts/check_forbidden.py` matches `\bsorry\b`, so a direct `sorryAx` call is not found by the source grep. The axiom check of the audit (and `lake check`) still finds it.

## Timing (local)

- `lake exe audit` on the empty registry: 0.5 s.
- `scripts/test_audit.sh` after the build: 8 s for 13 cases.

# Registry and audit

> Sources: own work: `CatsEffectInLean/Registry.lean`, `tools/Audit/Core.lean`, `scripts/test_audit.sh`, Lean v4.35.0 (2026-11-10)
> Raw: [Decision 55: heavy proofs](../../raw/project-decisions/2026-11-10-decision-55-heavy-proofs.md); [Registry and audit notes](../../raw/project-decisions/2026-11-10-registry-audit-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md)

## Overview

The registry lists each stated property. The audit checks each entry mechanically, so a "proof" of the wrong statement cannot count. It is Phase 1 step 3 of the [project plan](project-plan.md). Progress still counts only rows that pass [independent review](agent-workflow.md).

## Registry

`CatsEffectInLean/Registry.lean` defines `registry : List Entry`. First entry (2026-11-10): `core.IO.syncStep.syncStepIdentitySyncIO`, refuted, bug CE-0001 (see [SyncIO and syncStep model](../cats-effect/syncio-and-syncstep-model.md)). `Registry.lean` imports the `Props` and `Proofs` modules that its entries name.

| Field | Meaning |
|---|---|
| `id` | Unique entry id. |
| `rows` | [Inventory](inventory.md) row ids that the entry covers. At least one. |
| `prop` | Name of `def p : Prop`, in a `CatsEffectInLean.Props.*` module. |
| `status` | `open`, `proven` or `refuted`. |
| `thm` | Theorem name. `none` for `open`; required otherwise. In a `CatsEffectInLean.Proofs.*` module. |
| `bug` | Path of the bug record (`bugs/<id>.yaml`). Required for `refuted`. |
| `note` | Free text. |

How to register a property:

```lean
-- CatsEffectInLean/Registry.lean (import the Props and Proofs modules)
def registry : List Entry := [
  { id := "kernel.MonadCancel.uncancelablePollIsIdentity"
    rows := ["laws.MonadCancelLaws.uncancelablePollIsIdentity"]
    prop := ``Props.Kernel.uncancelablePollIsIdentity
    status := .proven, thm := ``Proofs.Kernel.uncancelablePollIsIdentity_proven } ]
```

Write the entry id in the `registry` column of each row. Use `;` between several ids. Set the row to `modelled` only when the entry is `proven` or `refuted` (decision 28). The rows of an `open` entry stay `todo`, with the entry id in their `registry` column.

`rows` lists only the rows that the property truly exercises. Test: if the mirror of the row were broken ("always error"), would the theorem fail? If not, the row does not belong to the entry (decision 26, CE-0001: 27 rows cut to 5).

A property that quantifies over programs or user code has the hypothesis `WellFormed` (decision 27, [Outcome sets](../semantics/outcome-equivalence.md)). A refutation proves that its witness is well-formed.

## Audit checks

`lake exe audit` (run from the repository root). Exit code 1 on any error.

1. Entry ids are unique. Each entry names at least one row.
2. `prop` exists, is a `def`, has type `Prop`, has no universe parameters, and is in a `Props` module.
3. `proven`: the type of `thm` is exactly `prop`. `refuted`: exactly `¬ prop`. The check is syntactic `Expr` equality. It never unfolds. A theorem of the unfolded body is rejected.
4. `thm` is a `theorem` in a `Proofs` module, with no universe parameters.
5. `prop` and `thm` use only `propext`, `Classical.choice`, `Quot.sound` (`collectAxioms`).
6. `refuted`: the `bug` file exists. `open`: no theorem.
7. Each entry row exists in `inventory/inventory.csv`. Each `modelled` row names an entry. Each named entry exists and lists the row.
8. Each `modelled` row names at least one `proven` or `refuted` entry (decision 28). An `open` entry does not count as progress. Message: `status modelled, but no named registry entry is proven or refuted`.

The audit does not judge if a property is good. That is the job of the reviewer (MIRROR, PROPERTY, SETTLED, wrong-function test).

## Heavy proofs (decision 55)

Proofs that take more than about 5 minutes are in lean_lib `HeavyProofs` (not a default target). Their entries are in `CatsEffectInLean/RegistryHeavy.lean` (`registryHeavy`, same `Entry` type; `heavyModules` lists the lib roots).

- `RegistryHeavy.lean` is light and in the default target. It names heavy theorems with a single backtick and the full name, because it does not import them.
- Main CI job (`lake exe audit`): every check of `Registry.lean`. Heavy entries get every check that needs no heavy module: id, rows, `prop` (exists, `def`, `Prop`, module, axioms), status/theorem/bug consistency, bug file. Ids are unique across both registries. The inventory cross-check uses both registries; a `modelled` row that only a heavy entry settles is **deferred** (counted in the output, not accepted).
- Heavy CI job `heavy-proofs` (`scripts/check_heavy_proofs.sh`, 150 min, every push): builds the heavy modules one `lake build` per module, `lake exe audit_heavy` (both registries in full, full inventory cross-check, deferred rows included), explicit `#print axioms`, and `leanchecker` per heavy module.
- So every check of the single registry still runs on every push, in one of the two jobs. The design needs `heavy-proofs` to block merges like `lean` (QUESTIONS.md Q4).
- Paranoid: the weekly `paranoid.yml` covers only the default target. `paranoid-heavy.yml` (weekly, 350 min) exports the heavy root with `leanexport` and runs `lake check --from-export --paranoid`. Estimated about 4 h; not measured.
- Gotcha: `leanchecker M` replays only the declarations of module `M`, not its imports (root of the law: 23 s; one chunk module: about 3 min). Replay each heavy module.
- Today: one heavy entry, `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` (49-chunk certificate check, [Certificate checks](../lean/certificate-checker.md)).

## Self-test

`scripts/test_audit.sh` runs `lake exe audit_fixture <case>` on `test/AuditFixtures/`. Case `good` (one proven, one refuted, one open entry) must pass. Thirteen cases each plant one fault and must fail with the expected message (nine more `heavy_*` cases test the heavy registry: deferral in the main mode, full check, missing or wrong theorem caught only in the full mode, missing theorem field, non-`def` property, open heavy entry on a `modelled` row, duplicate id across registries): weaker statement, unfolded statement, `refuted` without `¬`, `¬ P` as `proven`, new axiom, missing theorem, `open` with a theorem, missing bug field, missing bug file, unknown row, unnamed `modelled` row, `modelled` row named only by an `open` entry (`open_modelled`), duplicate id. In the fixtures the row of the open entry is `todo`.

The new-axiom fixture is generated at test time and deleted on exit, because `check_forbidden.py` forbids `axiom` in committed `.lean` files.

## Layout and CI

- The audit (`tools/`, lean_lib `Audit`) and the fixtures (`test/`, lean_lib `AuditFixtures`) are outside the `CatsEffectInLean` library. `lake build`, `lake check` and the lean-action axiom audit do not see them.
- CI job `lean`: after `lake check`, it runs `lake exe audit` and `scripts/test_audit.sh`. CI job `inventory` runs `scripts/check_inventory.py`.

## Gotchas

- Write names with double backticks (``` ``Foo.bar ```). Then Lean rejects a wrong name at compile time.
- The source grep matches `sorry` as a word, so a direct `sorryAx` term passes `check_forbidden.py`. The audit axiom check and `lake check` find it.
- `String.trim` is not in Lean v4.35.0. Use `trimAscii`.

## See Also

- [Inventory](inventory.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Proof hygiene and agent tooling](../lean/proof-hygiene-and-agent-tooling.md)
- [Project plan](project-plan.md)

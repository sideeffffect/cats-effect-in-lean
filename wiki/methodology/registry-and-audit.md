# Registry and audit

> Sources: own work: `CatsEffectInLean/Registry.lean`, `tools/Audit/Core.lean`, `scripts/test_audit.sh`, Lean v4.35.0 (2026-11-10)
> Raw: [Registry and audit notes](../../raw/project-decisions/2026-11-10-registry-audit-notes.md)

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

Then set the inventory row to `modelled` and write the entry id in its `registry` column. Use `;` between several ids.

## Audit checks

`lake exe audit` (run from the repository root). Exit code 1 on any error.

1. Entry ids are unique. Each entry names at least one row.
2. `prop` exists, is a `def`, has type `Prop`, has no universe parameters, and is in a `Props` module.
3. `proven`: the type of `thm` is exactly `prop`. `refuted`: exactly `¬ prop`. The check is syntactic `Expr` equality. It never unfolds. A theorem of the unfolded body is rejected.
4. `thm` is a `theorem` in a `Proofs` module, with no universe parameters.
5. `prop` and `thm` use only `propext`, `Classical.choice`, `Quot.sound` (`collectAxioms`).
6. `refuted`: the `bug` file exists. `open`: no theorem.
7. Each entry row exists in `inventory/inventory.csv`. Each `modelled` row names an entry. Each named entry exists and lists the row.

The audit does not judge if a property is good. That is the job of the reviewer (MIRROR, PROPERTY, SETTLED, wrong-function test).

## Self-test

`scripts/test_audit.sh` runs `lake exe audit_fixture <case>` on `test/AuditFixtures/`. Case `good` (one proven, one refuted, one open entry) must pass. Twelve cases each plant one fault and must fail with the expected message: weaker statement, unfolded statement, `refuted` without `¬`, `¬ P` as `proven`, new axiom, missing theorem, `open` with a theorem, missing bug field, missing bug file, unknown row, unnamed `modelled` row, duplicate id.

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

# Registry and audit

> Sources: own work: `CatsEffectInLean/Registry.lean`, `tools/Audit/Core.lean`, `scripts/test_audit.sh`, Lean v4.35.0 (2026-11-10)
> Raw: [Decision 57](../../raw/project-decisions/2026-11-14-decision-57-required-heavy-checks.md); [Review batch 7 notes](../../raw/project-decisions/2026-11-14-review-batch-7-notes.md); [Decision 55: heavy proofs](../../raw/project-decisions/2026-11-10-decision-55-heavy-proofs.md); [Registry and audit notes](../../raw/project-decisions/2026-11-10-registry-audit-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md)

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
9. (Removed 2026-11-15, decision 58.) `lib-fields` required a `libNote` when a statement's `Lib` had no function fields. Decision 58 makes closure references `Val.fn` values that `WellFormed` follows structurally, so `Lib.fields` is ignored and the check protected nothing; see [decision 58 core notes](../../raw/cats-effect/2026-11-15-decision-58-core-notes.md) for the regression examples that cover the same risk.

The audit does not judge if a property is good. That is the job of the reviewer (MIRROR, PROPERTY, SETTLED, wrong-function test).

## Heavy proofs (decision 55)

Proofs that take more than about 5 minutes are in lean_lib `HeavyProofs` (not a default target). Their entries are in `CatsEffectInLean/RegistryHeavy.lean` (`registryHeavy`, same `Entry` type; `heavyModules` lists the lib roots).

- `RegistryHeavy.lean` is light and in the default target. It names heavy theorems with a single backtick and the full name, because it does not import them.
- Main CI job (`lake exe audit`): every check of `Registry.lean`. Heavy entries get every check that needs no heavy module: id, rows, `prop` (exists, `def`, `Prop`, module, axioms), status/theorem/bug consistency, bug file. Ids are unique across both registries. The inventory cross-check uses both registries; a `modelled` row that only a heavy entry settles is **deferred** (counted in the output, not accepted).
- Heavy CI jobs (decision 57, every push; [implementation note](../../raw/project-decisions/2026-11-14-decision-57-implementation-track-p.md)):
  - `heavy-plan`: the matrix = non-root heavy modules, derived from the lakefile roots (`scripts/heavy_closure.py`), no hand-written list.
  - `heavy-module` (one job per module): default-target deps outside the sandbox; heavy deps and the module one at a time in the bwrap sandbox (`scripts/sandbox.sh`: read-only file system except `.lake`, private `/tmp`, no network); after each build every other file under `.lake` and the work tree must be unchanged (`scripts/heavy_build.sh`); `leanchecker` of the module in the sandbox; upload of the module's artifacts with sha256 list.
  - `heavy-audit`: default target and `audit_heavy` first (binary copied out of `.lake`); `heavyModules` must match the lakefile roots; every non-root module must have an artifact set (else fail); artifacts installed and required byte-identical after the sandboxed builds; roots built and replayed in the sandbox; copied `audit_heavy` (both registries in full, deferred rows included); `#print axioms` of every `registryHeavy` theorem (`tools/HeavyList.lean`).
  - `heavy-proofs`: aggregate, `needs` the three, `if: always()`; the stable required check.
  - Measured: critical path about 13 min plus runner setup, against about 64 min for one job (module jobs 3 s to 6.5 min; cold default target plus `audit_heavy` 4.7 min on 4 cores).
  - Local all-in-one: `scripts/check_heavy_proofs.sh` (same steps, every module in one run).
  - Fixes 2026-11-15: lake config elaborated before the first snapshot (`lake env true`; CI run 43651882144 failed when a restored cache had an out-of-date config and the module had no default-target dependency); symlinks hashed; only listed artifact files installed; axiom check matches Lean's error prefix only; empty matrix skipped explicitly; export scope checked on every paranoid run (`tools/HeavyDecls.lean`, `scripts/check_export_scope.py`).
- Paranoid: the weekly `paranoid.yml` covers only the default target. `paranoid-heavy.yml` (weekly): `paranoid-heavy-export` builds in the sandbox and exports every derived heavy module with one sandboxed `leanexport`; `paranoid-heavy-kernel` runs one kernel per job (default, lean-paranoid, lean4lean, nanoda, con-leche, con-ron; `scripts/run_kernel.sh`, the commands of `lake check --paranoid`), 350 min each. Export scope (2026-11-14): `leanexport M` writes `M` and all its imports, `leanexport A B` the union (law: 362 MB, 61,734 declarations). Default kernel on it: 33 min; the others not measured on the heavy export.
- Gotcha: `leanchecker M` replays only the declarations of module `M`, not its imports (root of the law: 23 s; one chunk module: about 3 min). Replay each heavy module. `leanexport M`, in contrast, includes the imports.
- Review batch 7 (2026-11-14): the split keeps every check on every push, but has gaps: (1) the heavy modules build with plain `lake build`, outside the bwrap sandbox of `lake check`, so build-time code could change the audit tool or the inventory before `audit_heavy` runs; (2) the main audit passes with a deferred row, so `heavy-proofs` must be a required check (Q4); (3) `check_heavy_proofs.sh` hard-codes the module list and the `#print axioms` list (a new heavy module would not be replayed by `leanchecker`); (4) `paranoid-heavy.yml` exports only the root module, scope not verified. [Review](../../review/2026-11-14-review-batch-7.md). Fixed by track P on 2026-11-14: (1) sandboxed per-module builds with hash checks, (3) derived lists, (4) export scope verified and every module exported; (2) closed by decision 57.
- Today: one heavy entry, `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` (49-chunk certificate check, [Certificate checks](../lean/certificate-checker.md)).

Decision 57 (2026-11-14, user answer to Q4): `heavy-proofs` is a required check on `main`. The heavy work runs as parallel matrix jobs, and an aggregate job `heavy-proofs` is the stable required name. The paranoid replay is split by kernel. Source: [decision 57](../../raw/project-decisions/2026-11-14-decision-57-required-heavy-checks.md).

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

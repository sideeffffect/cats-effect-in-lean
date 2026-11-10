# Inventory

> Sources: own work: `scripts/gen_inventory.py` and `scripts/check_inventory.py` run on Cats Effect v3.7.1 (2026-11-10)
> Raw: [Inventory generator notes](../../raw/project-decisions/2026-11-10-inventory-notes.md)

## Overview

`inventory/inventory.csv` lists each item that the project must model or exclude. It is Phase 1 step 2 of the [project plan](project-plan.md). A script generates it from the Scala source at v3.7.1. Progress counts only rows that a registry entry names and that pass review (see [Agent workflow](agent-workflow.md)).

## Columns

| Column | Meaning |
|--------|---------|
| `id` | Stable id: `<area>[.<subpackage>].<Template>[.<Nested>].<member>`. Examples: `kernel.MonadCancel.uncancelable`, `core.IO.tag.FlatMap`, `core.IOFiber.runLoop.FlatMap`, `laws.MonadCancelLaws.uncancelablePollIsIdentity`. Overloads get `#2`, `#3` in source order. |
| `area` | `kernel`, `core`, `std`, `laws`, `runtime`. |
| `kind` | `method` (def or val), `constructor` (ADT case), `runloop-branch` (one `case` of an interpreter tag switch), `law`. |
| `file` | Path in the Cats Effect repository. |
| `line` | Line at tag v3.7.1 (the `def`, `case class` or `case N =>` line). |
| `status` | `todo`, `modelled`, `excluded`. |
| `reason` | Only for `excluded`. Prefix `deferred:`, `platform:`, `internal:`, `trivial:` or `no-behaviour:`, then a justification. |
| `registry` | Registry entry that models the row. Required when `status` is `modelled`. Empty now. |

## Scope

- **kernel**: all members of named classes, traits and objects in `kernel/shared` and `kernel/jvm*`. Constructors of `Outcome`, `Resource`, `Resource.ExitCase`.
- **core**: `IO` constructors in tag order (`core.IO.tag.*`), `IO` and companion members, `IO.IOAsync` (the `IO` overrides of derived combinators, which are twins), `IOFiber` members, each `IOFiber.runLoop` tag case plus the `EndFiber` early return and the fast-path sub-cases (`core.IOFiber.runLoop.Map.fast.Pure`), `SyncIO` constructors and its `runLoop` cases, `IODeferred`, `IOLocal`, `ContState`, `LiftIO`, the JVM `IO*Platform` files.
- **std**: all members of named templates in `std/shared` and `std/jvm*`, including named private implementation classes (both `Queue` implementations).
- **laws**: each `def` of each `*Laws` trait in `laws/shared`.
- **runtime**: `core/**/unsafe/**`, all `excluded` with `deferred: phase 9`.

Main exclusion rules: js/native sources (`platform:`), `private`/`protected` members (`internal:`, except `IOFiber`, `Resource.fold`, `SyncStep.interpret`), monad-transformer instances (`deferred:`), `@deprecated` shims, syntax forwarders and auxiliary constructors (`trivial:`), `toString` (`no-behaviour:`). Details and reasons are in the raw note.

## Counts (v3.7.1, 2026-11-10)

| area | todo | excluded |
|------|-----:|---------:|
| core | 489 (37 constructors, 58 run-loop branches, 394 methods) | 334 |
| kernel | 368 (10 constructors, 358 methods) | 496 |
| std | 481 | 182 |
| laws | 58 laws | 18 |
| runtime | 0 | 829 |
| **total 3,255** | **1,396** | **1,859** |

## How to regenerate

1. Check out Cats Effect at `~/Projects/cats-effect`, tag `v3.7.1`. The script refuses another commit (override: `--allow-other-commit`).
2. Run `python3 scripts/gen_inventory.py`. It prints counts by area, kind and status. Output is deterministic.
3. Run `python3 scripts/check_inventory.py`. It checks unique ids, allowed values, reason prefixes, `registry` for `modelled` rows, and (only when the checkout exists) that each file exists and each line is in range.

Do not hand-edit generated columns. To change a status, change the rules in the script, or (later) let the registry audit set `modelled`. A regeneration must keep the `status`/`registry` of modelled rows; add that merge step before the first row becomes `modelled`.

## Parser limits

- Line and brace scanner, not a Scala parser. Members of anonymous classes and local defs are not rows (about 430 defs). The abstract trait member covers them.
- Modifiers are read from the `def` line only.
- Only the `(cur0.tag: @switch) match` switches give branch rows. The `resumeTag` switch and the continuation switches in `succeeded`/`failed` do not.

## See Also

- [Project plan](project-plan.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Source layout](../cats-effect/source-layout.md)
- [Differential testing](differential-testing.md)

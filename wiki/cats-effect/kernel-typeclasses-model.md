# Kernel typeclasses model (MonadCancel, GenSpawn)

> Sources: typelevel/cats-effect source at v3.7.1 (`kernel/.../MonadCancel.scala`, `GenSpawn.scala`, `GenConcurrent.scala`, `Async.scala`, `Fiber.scala`, `Outcome.scala`, `laws/.../MonadCancelLaws.scala`, `GenSpawnLaws.scala`, `MonadCancelTests.scala`, `GenSpawnTests.scala`, `core/.../IO.scala`), read 2026-11-10; cats-core 2.13.0 sources; own Phase 4 code in `CatsEffectInLean/Kernel/`, `Props/Kernel/`, `Proofs/Kernel/`
> Raw: [Kernel derived combinators notes](../../raw/cats-effect/2026-11-10-kernel-derived-combinators-notes.md); [Enumerator and first laws notes](../../raw/lean-tooling/2026-11-10-enumerator-and-first-laws-notes.md)

## Overview

Phase 4 steps 1-2 of the [project plan](../methodology/project-plan.md). The kernel typeclasses are generic over an abstract `F : Type → Type`. The operations are a structure parameter. The laws are `Prop`s over that structure, never axioms.
Update 2026-11-10: the `IO` laws are stated over the model's first-order `IO` operations (`IOI`), not as an instance of `MonadCancelOps`. Four laws are registered (2 proven, 2 open). See [Outcome sets and `Eqv`](../semantics/outcome-equivalence.md).

## Files

- `CatsEffectInLean/Kernel/MonadCancel.lean`: `CancelScope`, `Outcome` (+ `fold`, `embed`), `Poll`, `Fiber` (+ `joinWith`, `joinWithUnit`), `MonadCancelOps`, `Cats.Default.*`, `MonadCancel.Default.*`, `UsesKernelDefaults`, `IsUncancelableMixin`.
- `CatsEffectInLean/Kernel/GenSpawn.lean`: `GenSpawnOps` (extends `MonadCancelOps`), `Outcome.embedNever`, `Fiber.joinWithNever`, `GenSpawn.Default.*`, `UsesKernelDefaults`.
- `CatsEffectInLean/Props/Kernel/MonadCancelLaws.lean`, `GenSpawnLaws.lean`: the laws and `lawsFor` (the set that the Scala test suite checks).
- `CatsEffectInLean/Proofs/Kernel/MonadCancelDefaults.lean`: lemmas, not registered.

## Design

- **Virtual dispatch.** Every method that a body or a law calls is a structure field, abstract or derived. Example: `MonadCancelOps` has `map`, `productR`, `onError`, `guarantee`, `bracketFull`. An instance gives every field. This mirrors Scala, where `IO` overrides `guarantee` and a default body calls the overridden method.
- **Default bodies** are separate defs that take the whole instance `M`: `MonadCancel.Default.guaranteeCase M`, `GenSpawn.Default.race M`, `Cats.Default.onError M`. Same calls, same nesting of `uncancelable`/`poll`/`flatMap`/`onCancel` as the Scala body. The Scala body is in the docstring.
- **"Not overridden"** is a hypothesis: `M.guarantee = MonadCancel.Default.guarantee M`. Bundles: `MonadCancelOps.UsesKernelDefaults`, `GenSpawnOps.UsesKernelDefaults`, `MonadCancelOps.IsUncancelableMixin`.
- **Type invariant** `GenSpawnOps.rootCancelScope_eq` (`final def rootCancelScope = Cancelable`).
- **Encodings.** `Either` = `Sum` (`Left` = `inl`). `PartialFunction[E, F[Unit]]` = `E → Option (F Unit)`. `Poll[F]` = structure with `apply : {A} → F A → F A`. Two-argument functions are curried. Scala `Nothing` = `Empty`.
- **Syntax.** `fa >> fb` = `flatMap(fa)(_ => fb)`, not `productR`. `*>` = `productR`. `x flatMap {..}` binds weaker than `*>`.
- **Laws.** `<->` is a parameter `Eqv : ∀ {A}, F A → F A → Prop` (Scala `IsEq` + `Eq[F[A]]`). For `IO` it will be outcome-set equivalence over all schedules.
- **IO laws.** A typed `MonadCancelOps` instance for the untyped model is not possible (universe level, `pure` for every Lean type, closures as ids). Each IO law is a separate `def` in `Props/IO/` with the same calls as the generic law, the `IOI.*` operations (`Model/IOInstance.lean`), `env` hypotheses `IOI.Lam.*` for the lambdas, and `Eqv` from `Model/Outcomes.lean`.

Not modelled: `background` (needs `Resource`), `Unique#unique`, `tailRecM`, `ap`, `redeem*`, the cats `MonadError` laws, the transformer instances, and `GenConcurrent`'s default `racePair`.

## Inventory mapping (law rows: 4 `modelled`, rest `todo`)

| Lean | Inventory rows |
|---|---|
| `MonadCancel.Default.*` | `kernel.MonadCancel.{guarantee, guaranteeCase, bracket, bracketCase, bracketFull}` |
| `MonadCancelOps` fields | `kernel.MonadCancel.{rootCancelScope, forceR, uncancelable, canceled, onCancel}` |
| `IsUncancelableMixin` | `kernel.MonadCancel.Uncancelable.{rootCancelScope, canceled, onCancel, uncancelable}` |
| `GenSpawn.Default.*` | `kernel.GenSpawn.{cancelable, raceOutcome, race, bothOutcome, both}` |
| `GenSpawnOps` fields | `kernel.GenSpawn.{rootCancelScope, start, never, cede, racePair}` |
| `Outcome`, `fold`, `embed`, `embedNever` | `kernel.Outcome.{Succeeded, Errored, Canceled, succeeded, errored, canceled, fold, embed, embedNever}` |
| `Fiber` | `kernel.Fiber.{cancel, join, joinWith, joinWithNever, joinWithUnit}` |
| `Props.Kernel.MonadCancelLaws.*` | 17 rows `laws.MonadCancelLaws.*`; 4 are `modelled` through IO entries (`canceledAssociatesLeftOverFlatMap`, `forceRCanceledShortCircuits` proven; `onCancelAssociatesOverUncancelableBoundary`, `uncancelablePollIsIdentity` open) |
| `Props.Kernel.GenSpawnLaws.*` | 16 rows `laws.GenSpawnLaws.*` (all `todo` law rows) |

`joinWithUnit` is simplified to `A = Unit` (Scala: any `A` with `Unit <:< A`).

## Twins: IO overrides of derived methods

`IO` = `core/shared/src/main/scala/cats/effect/IO.scala` at v3.7.1. `IOAsync` (`IO:1996`) is the `Async[IO]` instance.

| Method | `IOAsync` line | IO body | Differs from kernel/cats default |
|---|---|---|---|
| `guarantee` | 2023 | `IO:496-501` | yes: `onCancel(fin).onError(fin.reportError).flatTap(fin)`, no `Outcome` |
| `guaranteeCase` | 2026 | `IO:523-530` | error branch `.reportError`, not `handleError(_ => ())` |
| `bracketFull` | 2062 | `IO:1826-1830` | `IO.defer(poll(use(a)))` vs `poll(unit >> use(a))` |
| `onError` | 2032 | `IO:605-606` | `pf.applyOrElse(t, _ => IO.unit) *> raiseError(t)` vs cats `map2` |
| `handleError` | 2029 | `IO:532-533` | same shape |
| `racePair` | 2090 | `IO:1817-1820` (`RacePair` node) | vs `GenConcurrent` default `K/GenConcurrent.scala:339` |
| `map` | 2098 | `IO:579` (`IO.Map` node) | constructor, not `flatMap + pure` |
| `productR` | 2081 | `IO:903-904` | same shape |
| `productL` | 2078 | `IO:900-901` | `flatMap(a => that.as(a))` vs cats `map2` |
| `as` | 2008 | `IO:182-183` | same shape |
| `void` | 2152 | `IO:961-962` | `map(_ => ())` vs cats `as(fa, ())` |
| `attempt` | 2011 | `IO:200-201` (`IO.Attempt` node) | constructor |
| `unit` | 2020 | `IO:1720` | constant |
| `redeem`, `redeemWith` | 2154, 2157 | `IO:692`, `IO:724` | not mirrored yet |

Not overridden by `IOAsync` (the kernel default runs for `IO`): `bracket`, `bracketCase`, `cancelable`, `raceOutcome`, `race`, `bothOutcome`, `both`, `background`, `flatTap`, `map2`, `product`, `tupleLeft`, `tupleRight`, `never` (= `Async.never`, `K/Async.scala:168`).

IO-class entry points: `IO#bracket` 338 → `IO#bracketCase` 370 → `IO.bracketFull` (skips `asyncForIO`); `IO#race` 638 → `IO.race` 1788; `IO#both` 243 → `IO.both` 1732; `IO#bothOutcome` 228; `IO#raceOutcome` 641; `IO#cancelable` 449; `IO#background` 941; `IO#memoize` 944. Total: 15 `IOAsync` overrides in the table, 8 entry points.

## Findings

- `raceDerivesFromRacePairLeft/Right` (`GenSpawnLaws.scala:28-88`): the law's `results` does not wrap `racePair` in `poll`, but `race` does. The law cannot see the difference: it shows only when someone cancels the racing fiber from outside.
- The kernel `guaranteeCase` drops a finalizer error with no trace. `IO` reports it (`reportError`). The outcome is the same. Checked in the model (track G): only `Obs.reports` differs.
- `IO.bracketFull` vs the kernel `bracketFull`: they differ when a cancel is pending after acquire and `use` throws (CE-0005, [guarantee and bracket model](bracket-model.md)).
- `IO.onError` adds an `IO.unit *>` step when `pf` is not defined. Test this with the difftest before you call it a difference.
- `GenSpawnTests` has a deprecated `spawn` overload (`:33-127`) without `fiberJoinIsGuaranteeCase`.
- Lemmas (proven): if an instance keeps the default `guarantee`, `guaranteeIsGuaranteeCase` holds for each reflexive `Eqv`. With the `Uncancelable` mixin, nine `MonadCancel` laws hold the same way. So these laws test something only for an instance that overrides the method. For `IO`, `guaranteeIsGuaranteeCase` compares two different bodies (`IO:496` vs `IO:523`).

## Update 2026-11-10 (Phase 6, track R)

- Checked: every `IO` entry point of `race`, `raceOutcome`, `both`, `bothOutcome` ends in the kernel default; `IOAsync` overrides none of them. So these four have no IO-vs-kernel twin. Mirror: [race and both model](race-both-model.md).

## See Also

- [race, both and fiber leaks](race-both-model.md)
- [guarantee and bracket model, CE-0005](bracket-model.md)
- [Outcome sets, `Eqv` and the IO laws](../semantics/outcome-equivalence.md)

- [Semantics](semantics.md)
- [Source layout](source-layout.md)
- [Run-loop model](runloop-model.md)
- [Inventory](../methodology/inventory.md)
- [Registry and audit](../methodology/registry-and-audit.md)
- [Project plan](../methodology/project-plan.md)

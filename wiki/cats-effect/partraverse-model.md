# parTraverseN model

> Sources: Cats Effect v3.7.1 (`kernel/.../GenConcurrent.scala:113-251`, `MiniSemaphore.scala:17-88`, `Ref.scala:123-124`, `SyncRef.scala`, `IODeferred.scala:20-80`, `IO.scala:1593-1600`); cats-core 2.13.0 (`list.scala`, `Traverse.scala`, `FlatMap.scala`, `Parallel.scala`); own Phase 6 batch 6.3 work and scala-cli runs, 2026-11-14
> Raw: [parTraverseN notes](../../raw/cats-effect/2026-11-14-partraverse-notes.md)

## Overview

Phase 6, batch 6.3. `IO.parTraverseN(n)(ta)(f)` calls the kernel default `GenConcurrent#parTraverseN` with the `IO` operations; there is no `IO` override, so no twin. The mirror covers `List` inputs of at most 4 elements (model limit: Scala's `Set1`..`Set4`). The difftest agrees on all checked cases. Four properties are registered `open`, each with a satisfiability witness and a random-schedule smoke test.

## Files

| File | Content |
|---|---|
| `Model/ParTraverse.lean` | Mirror: closures `PT` (namespace 41), descriptors of `IO` values, `MiniSemaphore`, `SyncRef`, `IODeferred.tryGet`, cats `traverse`/`sequence`/`parTraverse_` |
| `Props/Phase6/ParTraverse.lean` | 4 statements; `ptIsLib`; the tagging harness `TL` (namespace 42) |
| `Proofs/Phase6/ParTraverseWitness.lean` | Satisfiability witnesses (decision 53), kernel-checked runs |
| `tools/PtSmoke/Main.lean` | `lake exe ptsmoke`: random schedules, hypotheses checked, wrong-function tests |

## Mirror notes

- An `IO` held as a value (the traverse result `List[F[B]]`, the `F[...]` that `modify` returns) is a descriptor `Val`; the consuming closure rebuilds the term.
- `f(a)` runs inside the child fiber (`F.unit >> f(a)`), via the user function call.
- Scala precedence: `update *> tryGet flatMap {...}` is `(update *> tryGet) flatMap {...}`. The first mirror got this wrong; the difftest with small runtime thresholds found it.
- Check of term shapes: printing the real `IO` tree by reflection (raw note).

## Properties

| Entry | Status | Claim |
|---|---|---|
| `core.IO.parTraverseN.resultOrder` | open | a success has one entry per input, in input order |
| `core.IO.parTraverseN.pureSucceeds` | open | pure `f`: every stopped run is `Succeeded(as.map(g))` |
| `core.IO.parTraverseN.errorAborts` | open | one started action raises, the rest never end: `Errored(e)` |
| `core.IO.parTraverseN.cancelAborts` | open | the same with a self-cancel: `Canceled` |

Smoke: 11,200 stopped runs, 0 violations; reversed result, dropped result and "no `cancelAll`" break the claims. Not stated yet: "at most N concurrent" (needs a test marker and the shared privacy module of decision 56) and "no leaked fiber".

## Difftest

Op `parTraverseN` (format v2). Fixed cases `partraverse.jsonl` (74). Generated cases: see the raw note and the batch report (per-op counts with the `runtime` field).

## See Also

- [Race, both and fiber leaks](race-both-model.md)
- [guarantee and bracket model](bracket-model.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)

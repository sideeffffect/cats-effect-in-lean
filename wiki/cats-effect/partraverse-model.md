# parTraverseN model

> Sources: Cats Effect v3.7.1 (`kernel/.../GenConcurrent.scala:113-249`, `MiniSemaphore.scala:17-92`, `Ref.scala:123-124`, `SyncRef.scala`, `IODeferred.scala:20-80`, `IO.scala:1593-1600`); cats-core 2.13.0 (`list.scala`, `Traverse.scala`, `FlatMap.scala`, `Parallel.scala`); own Phase 6 batch 6.3 work and scala-cli runs, 2026-11-14
> Raw: [Review batch 7 notes](../../raw/project-decisions/2026-11-14-review-batch-7-notes.md); [parTraverseN notes](../../raw/cats-effect/2026-11-14-partraverse-notes.md); [review 7 fix notes](../../raw/cats-effect/2026-11-14-partraverse-review7.md); [deep Lib and limit notes](../../raw/cats-effect/2026-11-14-partraverse-deep-lib.md)

## Overview

Phase 6, batch 6.3. `IO.parTraverseN(n)(ta)(f)` calls the kernel default `GenConcurrent#parTraverseN` with the `IO` operations; there is no `IO` override, so no twin. The mirror covers `List` inputs of any length. The supervision `Set` is `Set1`..`Set4` (insertion order) up to 4 elements and a `HashSet` from 5; the `HashSet` order comes from identity hashes, so it is an input `ho` of the mirror and the statements quantify over every permutation (review 7). The difftest agrees on all checked cases (inputs of at most 4 elements, so the `HashSet` branch is not differentially tested). Eight properties are registered `open`, each with a satisfiability witness and a random-schedule smoke test.

## Files

| File | Content |
|---|---|
| `Model/ParTraverse.lean` | Mirror: closures `PT` (namespace 41), descriptors of `IO` values, `MiniSemaphore`, `SyncRef`, `IODeferred.tryGet`, cats `traverse`/`sequence`/`parTraverse_` |
| `Props/Phase6/ParTraverse.lean` | 8 statements; `ptLibDeep`, `limLib`; the limit harness `CL` (namespace 44); `ptIsLib`; the tagging harness `TL` (namespace 42); the behaviour harness `BL` (namespace 43) |
| `Proofs/Phase6/ParTraverseWitness.lean` | Satisfiability witnesses (decision 53), kernel-checked runs |
| `tools/PtSmoke/Main.lean` | `lake exe ptsmoke`: random schedules, hypotheses checked, wrong-function tests |

## Mirror notes

- An `IO` held as a value (the traverse result `List[F[B]]`, the `F[...]` that `modify` returns) is a descriptor `Val`; the consuming closure rebuilds the term.
- `f(a)` runs inside the child fiber (`F.unit >> f(a)`), via the user function call.
- Scala precedence: `update *> tryGet flatMap {...}` is `(update *> tryGet) flatMap {...}`. The first mirror got this wrong; the difftest with small runtime thresholds found it.
- Check of term shapes: printing the real `IO` tree by reflection (raw note).
- Scala `Set`: `Set4 + new` gives a `HashSet`; `HashSet - x` stays a `HashSet`. Only `cancelAll` and the final `joinAll` read the order (`toList`). The model encodes a `HashSet` as `.right (listV xs)` and reads it as `ho xs`. Any `ho` over-approximates: a real `HashSet` order is also consistent between a set and its subsets.
- A model limit must not be a hypothesis of a statement (review 7). The first version had `as.length ≤ 4`; it is gone.

## Properties

| Entry | Status | Claim |
|---|---|---|
| `core.IO.parTraverseN.resultOrder` | open | a success has one entry per input, in input order |
| `core.IO.parTraverseN.pureSucceeds` | open | pure `f`: every stopped run is `Succeeded(as.map(g))` |
| `core.IO.parTraverseN.errorAborts` | open | one started action raises, the rest never end: `Errored(e)` |
| `core.IO.parTraverseN.cancelAborts` | open | the same with a self-cancel: `Canceled` |
| `core.IO.parTraverseN.succeedsGen` | open | behaviour table (cedes, then `pure`): `Succeeded`, input order |
| `core.IO.parTraverseN.errorAbortsGen` | open | cedes, then `pure`/`raiseError`/`never`; a raising input that gets a permit: `Errored(e)`, `e` raised by an input |
| `core.IO.parTraverseN.cancelAbortsGen` | open | the same with `canceled`: `Canceled` |

Review batch 7 (2026-11-14): all four entries HOLLOW. `resultOrder`: `f` is held as a number in `k1` and `TL.tag`, so `WellFormed` never checks `WF.captured f`; an `f` that captured the internal result `Deferred` completes it with a forged pair (false for every implementation). All four: `as.length ≤ 4` is not a documented precondition (fix: make the `HashSet` order an input). `errorAborts`/`cancelAborts`: siblings fixed to `IO.never` remove completing siblings, late errors and two errors. Many `K/GC`/`K/MS` line citations drift 2-8 lines. [Review](../../review/2026-11-14-review-batch-7.md).

| `core.IO.parTraverseN.atMostN` | open | harness counter (`HarnessPrivacy` token `Ref` 0): highest number of running actions `≤ n` |

Defect D of review 7 (`f` reaches the per-input result `Deferred` through a number field of its closure id) is closed by decision 56: statements 1-4 use `ptLibDeep`, whose `fields` are `ParTraverse.fnFields` (the `f` fields of `k1`, `k2`, `k3`, `travM2`, `elemSel`, `uncK`, `resK`, `thenStart`, `callF`; the `f` of each `srcAction` code in any closure field, so also inside `Bracket` `Src.ext`, `Race` and `Timeout` sources; `Bracket.fnFields`) and `f` of `TL.tag f`. Data number fields: the limit `n` of `k1`/`k2`, the cede count of `BL.step`, Race kind/side, Timeout durations, code tags. `PrivacyExamples` checks the forgery (plain, in a `Bracket` source, in a `Race` source): it passes `ptIsLib`, fails `ptLibDeep`. `resultOrder` is now plausible. Statements 5-7 use a harness `f` with no user code, so they need no `WellFormed` hypothesis. The behaviour table covers siblings that complete, an action that suspends first, an error in an action that starts after the first `n`, and two errors at once.

Smoke (`lake exe ptsmoke 100`, three `HashSet` orders, inputs up to 6): 55,980 stopped runs, 0 violations; reversed result, dropped result and "no `cancelAll`" break the claims. Not stated yet: "no leaked fiber". Statement 8 (`atMostN`): `f'(a) = uncancelable(poll => enter *> poll(g(a)).attempt.onCancel(exit).flatMap(x => exit *> rethrow x))`; the masked region makes enter/exit exact under cancelation. The event closures hold the token, so they are outside `limLib`. A semaphore with 1000 permits breaks it (kernel-checked `Limit.wideRun_breaks`, and ptsmoke).

## Difftest

Op `parTraverseN` (format v2). Fixed cases `partraverse.jsonl` (74, all agree). Generated cases (`difftest/py/opcount.py --seeds 31 32 33 34 --n 50000 --ops parTraverseN --boost tpl_parTraverse=6 tpl_parTraverseCancel=6`, about 25 % of cases with small `runtime` thresholds): 200,000 cases, all agree; 56,654 use `parTraverseN` (14,071 to 14,235 per seed). After the generator change (the op is appended with its own RNG, `p_par_traverse`, so the other ops keep their selftest coverage): `--seeds 41 42 43 --n 30000 --boost tpl_parTraverse=8 tpl_parTraverseCancel=8`: 90,000 cases, all agree; 52,469 use `parTraverseN` (17,475 to 17,499 per seed).

## See Also

- [Race, both and fiber leaks](race-both-model.md)
- [guarantee and bracket model](bracket-model.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)

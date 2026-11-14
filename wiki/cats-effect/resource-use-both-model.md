# Resource use, allocated, both, and CE-0020

> Sources: Cats Effect v3.7.1 (`Resource.scala:156-314`, `:388-397`, `:464-552`, `:826-993`, `:1229-1234`; `IO.scala:961-962`, `:1822`, `:2062-2064`, `:2152`, `:2161`; `SyncRef.scala:30`, `:65-73`; `GenSpawn.scala:476-498`); upstream commit `3af09e6d56` (PR #4630); own Phase 6 track Res work and scala-cli runs, 2026-11-10
> Raw: [Review batch 6 notes](../../raw/project-decisions/2026-11-14-review-batch-6-notes.md); [Track Res notes](../../raw/cats-effect/2026-11-10-track-res-resource-notes.md); [Merge with track M](../../raw/cats-effect/2026-11-10-track-res-merge-m-notes.md); [Review batch 5 fixes](../../raw/cats-effect/2026-11-10-track-res-review5-fix-notes.md)

## Overview

Phase 6, batch 6.2, track Res. The model mirrors `Resource#fold`/`use`/`use_`/`useEval`, `allocated`, the application of `rel2`, and `Resource#both`, with `F = IO`. The difftest has three new format v2 ops. One property is refuted: `Resource#both` can skip the finalizers of one side (CE-0020). Three properties are `open` with smoke tests.

## Files

| File | Content |
|---|---|
| `Model/ResourceUse.lean` | `ULam` (namespace 20), `USrc` codes, `UEnv` (`REnv` + `resOf`), `foldLoop`, `useIO`, `allocatedIO`, `applyRelX` (`rel2`), `bothRes`, fixed twin `fixedBothRes`, dispatch `UEnv.toEnv` |
| `Model/ResourceUseExamples.lean` | 6 runs by `decide +kernel` (both, LIFO, allocated + release) |
| `Props/Phase6/HarnessNames.lean` | Deep check that a value, program or user result mentions a harness name (decision 54) |
| `Props/Phase6/Resource.lean` | 4 statements, `MarkedMake`, `NoForge`, `EmitsOnly`, harness parent `HLam`, `envH`, `useOf` |
| `Proofs/Phase6/ResourceWitnessEnv.lean` | The witness environment `W` and its lemmas |
| `Proofs/Phase6/ResourceWitness.lean` | Satisfiability witnesses `use_sat`, `flat_sat` (with and without the parent) |
| `Proofs/Phase6/ResourceBoth.lean` | `bothReleasesBoth_refuted` (all hypotheses proven) |
| `Proofs/Phase6/ResourceBothFixed.lean` | `TwinChecks`: the fixed twin satisfies the conclusion on 120 schedules (kernel), v3.7.1 does not |
| `test/Phase6/ResourceSmoke.lean` | `#guard` smoke tests (about 15 min): hypotheses, forgeries, CE-0020 family, open statements, decision 41 |

## Mirror rules

- `fold` uses `F.bracketFull` = `IO.bracketFull`. So `use` puts each `Allocate` under the track G mirror, and inherits its CE-0005 order (the `use` closure is called inside `IO.defer`).
- A captured `Res` is a code; the caller gives `UEnv.resOf` (as `ioOf` of `Bracket`, `srcIO` of `Race`).
- A captured `IO` (`rel(ec)`, the `F[Unit]` of `allocated`, the sides of `F.both`) is a `USrc` code. `rel(ec)` keeps a view snapshot; the rebuild runs the same pure function on it.
- New release functions are `RelFn.user idx` with a `ULam` id. `UEnv.rx` runs them, and runs the `evalMap` lambda of `both` as a `Bind` function. The Phase 5 interpreter (`allocatedCase`, `Clo`) runs unchanged with `UEnv.rx`.
- `Ref` = `SyncRef`: `get` and `update` are one `Delay` thunk (one atomic model step).
- Limits: `fold` fuel as `allocatedCase`; nested `both` depth 8; both `rel(ec)` and `release(ec)` in one lambda see the same view.

## CE-0020

`both` stores each side's finalizers in a `Ref`. The release of `makeCase` runs `F.both(thisFin(ec), thatFin(ec))`. If one chain ends with an error (a release that raises), `GenSpawn#both` cancels the other fiber. That fiber is unmasked at the start of its chain (`F.unit >> fin(ec).guarantee(release(ec))`); if it has not started, it runs nothing. The other side's resources are never released.

- Lean: `bothReleasesBoth_refuted` (one schedule, `decide +kernel`): trace `[101, 2, 1]`, no `102`.
- Reproducer: 332 of 1,000 TestControl seeds; 306-360 of 20,000 default-runtime runs; same through `parTupled`; on 3.7.1, series/3.x and series/3.7.x.
- Fixed twin (decision 39, not CE code): run both chains with `attempt`, then re-raise. It satisfies the conclusion on the hypothesis-satisfying witness input for 120 schedules (kernel, `TwinChecks`) and 600 + 1,500 schedules (smoke `#guard`); 1,000 seeds (Scala). The reproducer prints `REPRODUCED` only if the fixed copy misses no release.
- Priority medium: a release that raises is common; the leak is silent.

## Properties

| Entry | Status | Note |
|---|---|---|
| `kernel.Resource.both.releaseOnce` | refuted | CE-0020 |
| `kernel.Resource.use.releaseOnce` | open | decision 50 parent; witness `use_sat`; smoke 3 x 4 x 2 x 900 runs |
| `kernel.Resource.flatMap.releaseOrder` | open | counts and LIFO; witness `flat_sat`; smoke 24 x 900 runs |
| `kernel.Resource.eval.preservesCancelable` | open | decision 41; exact `EqvP` for 4 programs; over-masking `Eval` breaks it |

Why open: a proof for all programs needs a state invariant over `Step`/`SchedP` (the same gap as track G's `core.IO.bracket.releaseOnce`).

Test harness (review batch 5, decisions 53-54): markers are reached by *names* (function ids, `REnv` indices, acquire/release/resource/`Bind` codes). Library closures hold ids as plain numbers, so a captured handle alone can be bypassed (forwarding through `ULam.allocFn`, `BLam.thenUse`, `Clo.makePair`). `NoForge` uses the deep check of `HarnessNames`: user code never introduces a harness name, also not inside closure fields. The parent fiber is a harness closure (`HLam`). Each statement has a Lean satisfiability witness. The first version (`UserMarkersOnly`) was HOLLOW: a forged marker made the statements false for every implementation.

**Review batch 5 (2026-11-10):** `UserMarkersOnly` is forgeable. `usesId` does not look into library closure fields, so user code can run a marker through `ULam.allocFn (.user m)` and `WellFormed` accepts it. So `use.releaseOnce` and `flatMap.releaseOrder` are false for every implementation (HOLLOW), and CE-0020 is HOLLOW as registered (the bug and its witness are real; a correct `both` also refutes the statement). Fix: harness-only markers (decision 54). `eval.preservesCancelable` is FAITHFUL as a statement. See [review batch 5](../../review/2026-11-10-review-batch-5.md).

**Review batch 6 (2026-11-14): still HOLLOW** (`use.releaseOnce`, `flatMap.releaseOrder`; CE-0020 as registered). The deep scan closes the `ULam.allocFn` forgery, but the `NoForge` escape clause ("a result may mention a name if its argument does") lets user code use a number from the runtime: `IO.sleep 6 >> IO.realTime` gives `.nat 6`, the marker id `2 * mR`, and a user function then runs the marker. Fix: `NoForge` without the escape clause (the library gives no harness name to user code). Inventory rows `fold`, `use`, `both` should be `todo` until CE-0020 passes. See [review batch 6](../../review/2026-11-14-review-batch-6.md).

Inventory: `both`, `use`, `fold` are `modelled` (the refutation uses their mirrors); `makeCase` and `evalMap` are `todo` (only their instances inside `both` are mirrored).

## Difftest (format v2)

Ops `rUse`, `rAllocated`, `rBoth` ([format](../methodology/difftest-program-format.md)). Fixed cases `cases/resuse.jsonl` (228, all agree; case `res-both-relfail-sched5-1` shows CE-0020 on both sides). `opcount.py` seeds 21-23, 240,000 cases, all agree: rUse 87,130, rAllocated 51,777, rBoth 54,462 agreeing cases. After the merge with track M the default weights are `rUse` 0.5, `rAllocated` 0.4, `tpl_resBoth` 0.5, `res_both` 2.0 (so `race` keeps its 5 % selftest minimum).

## See Also

- [Resource model and CE-0002](resource-model.md)
- [guarantee and bracket model, CE-0005](bracket-model.md)
- [race, both and fiber leaks](race-both-model.md)
- [Bug history](bug-history.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)

# Resource use, allocated, both, and CE-0020

> Sources: Cats Effect v3.7.1 (`Resource.scala:156-314`, `:388-397`, `:464-552`, `:826-993`, `:1229-1234`; `IO.scala:961-962`, `:1822`, `:2062-2064`, `:2152`, `:2161`; `SyncRef.scala:30`, `:65-73`; `GenSpawn.scala:476-498`); upstream commit `3af09e6d56` (PR #4630); own Phase 6 track Res work and scala-cli runs, 2026-11-10
> Raw: [Track Res notes](../../raw/cats-effect/2026-11-10-track-res-resource-notes.md); [Merge with track M](../../raw/cats-effect/2026-11-10-track-res-merge-m-notes.md)

## Overview

Phase 6, batch 6.2, track Res. The model mirrors `Resource#fold`/`use`/`use_`/`useEval`, `allocated`, the application of `rel2`, and `Resource#both`, with `F = IO`. The difftest has three new format v2 ops. One property is refuted: `Resource#both` can skip the finalizers of one side (CE-0020). Three properties are `open` with smoke tests.

## Files

| File | Content |
|---|---|
| `Model/ResourceUse.lean` | `ULam` (namespace 20), `USrc` codes, `UEnv` (`REnv` + `resOf`), `foldLoop`, `useIO`, `allocatedIO`, `applyRelX` (`rel2`), `bothRes`, fixed twin `fixedBothRes`, dispatch `UEnv.toEnv` |
| `Model/ResourceUseExamples.lean` | 6 runs by `decide +kernel` (both, LIFO, allocated + release) |
| `Props/Phase6/Resource.lean` | 4 statements, `UserMarkersOnly`, `MarkedMake`, `useOf`, `withParent` |
| `Proofs/Phase6/ResourceBoth.lean` | `bothReleasesBoth_refuted` and the well-formed witness |
| `test/Phase6/ResourceSmoke.lean` | `#guard` smoke tests (about 15 min): CE-0020 family, fixed twin, open statements, decision 41 |

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
- Fixed twin (decision 39, not CE code): run both chains with `attempt`, then re-raise. No violation on 2,100 schedules (Lean) and 1,000 seeds (Scala).
- Priority medium: a release that raises is common; the leak is silent.

## Properties

| Entry | Status | Note |
|---|---|---|
| `kernel.Resource.both.releaseOnce` | refuted | CE-0020 |
| `kernel.Resource.use.releaseOnce` | open | decision 50 parent; smoke 3 x 4 x 2 x 900 runs |
| `kernel.Resource.flatMap.releaseOrder` | open | counts and LIFO; smoke 32 x 900 runs |
| `kernel.Resource.eval.preservesCancelable` | open | decision 41; exact `EqvP` for 4 programs; over-masking `Eval` breaks it |

Why open: a proof for all programs needs a state invariant over `Step`/`SchedP` (the same gap as track G's `core.IO.bracket.releaseOnce`).

Hypothesis note: `UserMarkersOnly` restricts only user ids (even). `Bracket.MarkersOnly` also restricts library ids; a library closure that calls a marker function makes it false, so the track G statements that use it may be vacuous (review batch 4).

## Difftest (format v2)

Ops `rUse`, `rAllocated`, `rBoth` ([format](../methodology/difftest-program-format.md)). Fixed cases `cases/resuse.jsonl` (228, all agree; case `res-both-relfail-sched5-1` shows CE-0020 on both sides). `opcount.py` seeds 21-23, 240,000 cases, all agree: rUse 87,130, rAllocated 51,777, rBoth 54,462 agreeing cases. After the merge with track M the default weights are `rUse` 0.5, `rAllocated` 0.4, `tpl_resBoth` 0.5, `res_both` 2.0 (so `race` keeps its 5 % selftest minimum).

## See Also

- [Resource model and CE-0002](resource-model.md)
- [guarantee and bracket model, CE-0005](bracket-model.md)
- [race, both and fiber leaks](race-both-model.md)
- [Bug history](bug-history.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)

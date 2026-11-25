# Supervisor model

> Sources: Cats Effect v3.7.1 (`std/.../Supervisor.scala`, `kernel/.../Resource.scala:156-208`, `:849-920`, `kernel/.../Sync.scala:38-39`, `std/.../Dispatcher.scala:254`); cats-core 2.13.0 (`list.scala`, `Chain.scala:1190-1234`, `Parallel.scala:296-299`, `Foldable.scala:603-604`, `Traverse.scala:299-309`); own Lean, difftest and smoke runs, 2026-11-25
> Raw: [Track V notes](../../raw/cats-effect/2026-11-25-track-v-supervisor-notes.md)

## Overview

Phase 7, batch 7.2, track V. Mirror of `std.Supervisor` with `F = IO`: both state kinds, `await = true/false`, the `checkRestart` restart path. Difftest ops `supUse`, `supervise` (format v2). Seven registered statements, all `open`, each with a kernel-checked satisfiability witness and wrong-function theorem. No bug found. Codec namespaces 80 (closures), 81 (descriptors), 82 (Props harness).

## Files

| File | Content |
|---|---|
| `Std/Supervisor.lean` | Mirror: `SLam` closures, descriptors `D`, `useIO` (factory + `use`), `superviseIO`, `dispatch`/`env`; variants 1-12 (wrong functions) |
| `Props/Phase7/Supervisor.lean` | Harness (`HLam`), seven statements `supXV v` |
| `Proofs/Phase7/SupervisorWitness.lean` | Witnesses, wrong-function and battery theorems (kernel, about 4.5 min, 2.5 GB) |
| `Proofs/Phase7/SupervisorRestartWitness.lean` | Variant 11 (restart ignores its flags) breaks `noLeak`, kernel; v3.7.1 on the same input; `TwinChecks`, not in the default build (3 min, 5 GB) |
| `tools/SupSmoke/Main.lean` | `lake exe supsmoke [runs]`: random inputs and schedules, every variant |
| `difftest/src/main/scala/cats/effect/std/SupervisorShim.scala` | Access to the private entry points (`checkRestart`, `applyForConcurrent`) |
| `difftest/cases/gen_supervisor.py` | 136 fixed cases |

`Std/Supervisor.lean` is reusable (track P7D, Dispatcher): `useIO aw rs cv v f`, `superviseIO`, `supOf?`, `wrapOf?`, `env ho ioOf u`.

## Mirror notes

- `IO` is `Async`: `Supervisor[IO]` always takes `applyForAsync` (a `ConcurrentHashMap`). `applyForConcurrent` (`Ref[Map]`, `null` after the close) is mirrored as a twin (`cv = 1`).
- The `Resource` is folded by hand, as `Resource#fold` does it: `F.ref(false).flatMap(a => F.bracketFull(acq)(useK)(relK))`; `acq` = `mkState(doneR).map(a => (a, e => release(a, e)))`.
- The release cancels after an errored or canceled `use` body also when `await = true` (`SV:169-172`). Deliberate: the docs describe the success case.
- `None` path: each child has a second, internal monitor fiber (`fib.join.guarantee(fin)`); the close does not wait for it. It only runs `remove`.
- Restart path: `currentR.set(newCurrent)` comes before `canceledR.get`, and `cancel` sets `canceledR` before it reads `currentR`; so after a cancel at most one restart happens, and the `AssertionError` branch (`SV:268-269`) is unreachable in the model.
- `cancelAll` = `parUnorderedTraverse(_.cancel)` = `Chain.traverseViaChain` over `ParallelF` (`both` per element); `joinAll` = `traverse_` (`productR` fold). The map order is an input `ho` (statements: any permutation; difftest: every order of the entries a map held).
- Map cell = `pair (nat c) entries`; `c` and the entry index are ghost state (the difftest names an order with them). `null` keeps the counter.

## Codec cost (lesson)

A closure id that embeds another closure reference is about twice as long. The first restart wrapper embedded `fa`'s source; a later `supervise` source (difftest) embedded the earlier wrapper: exponential growth, 8 GB on a 4-`supervise` case. In Scala the wrapper does not capture `fa`; the mirror now does the same (`RCtx.toW`). Rule: capture only what the Scala closure captures, and keep large codes (sources, snapshots) out of values that user code holds.

## Difftest

Ops `supUse` (`aw`, `rs`, `cv`, `x`, `k`) and `supervise` (`s`, `e`), [format](../methodology/difftest-program-format.md). Generator template `tpl_sup` with its own RNG (`p_sup`). Restart cases end by fuel (`always` restarts a finished child forever) and are slow on the Lean side (about 30 ms per step): at most 2 children, no nesting, `maxSteps` 150. `IllegalStateException: supervisor already shutdown` is a library exception (`drive.py` `LIB_EXNS`, `Prog.userCodeV?`). An external cancel of a restart wrapper handle is skipped on both sides (harness rule).

- Fixed cases: 136 agree (restart cases with `maxSteps` 60; in CI `cediff` and `drive.py check` lists).
- Run 1 (55,200 cases): 12 mismatches, all with 6-8 `supervise` on one supervisor: the Scala map order (identity hashes) was outside the 120 listed orders. Harness limit, not a model bug; the generator then made at most 5 `supervise` per scenario. Review batch 16 (C2): that cap removed cases to get agreement; lifted (below).
- Run 2: `opcount.py --seeds 81 82 83 --n 18400 --boost tpl_sup=12` (12 processes, `--start`) plus 1,100 more per seed: **58,500 cases, all agree**; agreeing cases per op: `supUse` 51,137, `supervise` 51,137 (seed 81: 17,035, 82: 17,052, 83: 17,050). Model bugs found by the difftest: none (the two fixes were codec size and the variant-9 wiring). This run was before decision 67 and used the 5-`supervise` cap; it does not count for C1.
- **Decision 67 and C2 (2026-11-25).** The difftest JVM runs with `-XX:hashCode=2` (all identity hashes equal), so `ConcurrentHashMap` and Scala `HashMap` iterate small maps in insertion order. The generator bound is now 8 `supervise` per scenario (`sup_left`; above about 8 entries a `ConcurrentHashMap` bin may stop keeping insertion order, review 16 N6). Check: 222 generated cases with 6-8 `supervise`, Scala run 3 times: identical outputs; Lean with the full enumeration (every order of up to 5 entries, 121 replays per case): **222/222 agree** (25 min).
- **Difftest cost limit (not an agreement fix).** `cediff` lists every map order when every map held at most 5 entries (the full outcome set). Above 5 entries it emits only the insertion-order replay (6! = 720 replays per case cost too much). This is sound under `-XX:hashCode=2`: the insertion-order outcome is one member of the full set, so a match is a valid refinement. The model, the statements, the witnesses and the batteries keep every order (`IsOrder ho`). With this rule the 222 cases above also agree (222/222).
- **C1 run (final harness: decision 67, bound 8, fast path above 5 entries).** `opcount.py --seeds 81 82 83 --n 19500 --boost tpl_sup=12`, 6 processes (2 slices per seed, `--start`), together with track P7D's run: **58,500 cases; 58,498 agreed in the run, 2 were binned `hang`** (`g81-872`, `g82-3489`: restart-path cases, 150 steps, about 90 s each; the Lean batch timeout of `drive.run_lean` expired under load 15-17). Rerun of the 2 cases with the same binaries and no timeout: **both agree**. Mismatches: 0. Agreeing cases per op (with the 2 reruns): `supUse` 51,137, `supervise` 51,137; per seed 81: 17,035, 82: 17,052, 83: 17,050.

## Properties (`Props/Phase7/Supervisor.lean`)

Harness: `Supervisor.use(s => save s; supervise the root children; b.attempt)`, then `supervise` the late children (after the close). Child `j` = `uncancelable(poll => enter(j) *> poll(ws[j].attempt).onCancel(fin(j)) *> mark(j, 2))`, then its own children (tree `ps`). Library: the `IO.never` closures only (user code cannot name a harness source: it is a closure reference).

| Entry | Claim | Wrong variants (kernel) |
|---|---|---|
| `std.Supervisor.noLeak` | done root ⇒ no child runs user code | 7; 11 (`SupervisorRestartWitness.noLeak_v11`, twin-check job, 3 min, 5 GB) |
| `std.Supervisor.closedNoRun` | flagged ⇒ never ran; done `Succeeded` ⇒ every late child flagged | 9 |
| `std.Supervisor.runsOnce` | no restart: ≤ 1 start, ≤ 1 finalizer run per child | 4 |
| `std.Supervisor.awaitJoins` | `aw = true`, flat, pure: done `Succeeded(())`, every child status 2 | 1, 3, 5, 12 |
| `std.Supervisor.noDeadlock` | pure programs, any nesting: never blocked | 2, 6 |
| `std.Supervisor.removed` | blocked ⇒ no terminated fiber in the map | 10 |
| `std.Supervisor.cancels` | `aw = false`, sleeping children, body pure/cede: no child finished its sleep | 8 |

## Smoke (`lake exe supsmoke 100`, 6 min)

v3.7.1: 0 violations of all 7 statements, 0 hypothesis failures (100 runs per statement group; 82 done, 6 blocked). Each wrong variant breaks its statement: v1 → 4 (100 runs), v2 → 5 (100), v3 → 4 (100), v4 → 3 (93), v5 → 4 (100), v6 → 5 (100), v7 → 1 (34), v8 → 7 (93), v9 → 2 (17), v10 → 6 (11), v11 → 1 (8), v12 → 4 (40).

## Decision 63 battery

| Operation | raises | hangs | drops | doubles |
|---|---|---|---|---|
| `supervise` | `awaitJoins` (v1) | `noDeadlock` (v2) | `awaitJoins` (v3) | `runsOnce` (v4) |
| `Supervisor.apply` + `use` | `awaitJoins` (v5) | `noDeadlock` (v6) | `noLeak` (v7, the release drops) | not applicable: a second allocation gives an unreachable supervisor |

The fibers that `supervise` returns are `IOFiber`s (public path); the restart wrapper is private (`Dispatcher` only).

## See Also

- [CountDownLatch and CyclicBarrier model](latch-barrier-model.md)
- [Resource use, allocated, both](resource-use-both-model.md)
- [parTraverseN model](partraverse-model.md)
- [race, both and fiber leaks](race-both-model.md)
- [Differential testing](../methodology/differential-testing.md)
- [Agent workflow and review protocol](../methodology/agent-workflow.md)
- [Phase 7 batch 7.2 gate report](../methodology/phase7-batch2-gate-report.md) (review batch 16: gate FAIL, B1)

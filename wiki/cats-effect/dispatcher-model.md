# Dispatcher model, CE-0090 and CE-0091

> Sources: Cats Effect v3.7.1 (`std/shared/src/main/scala/cats/effect/std/Dispatcher.scala`, `Supervisor.scala`, `UnsafeUnbounded.scala`, `kernel/.../Resource.scala:156-208`, `:826-920`, `core/.../IO.scala`, `tests/shared/src/test/scala/cats/effect/std/DispatcherSuite.scala`); cats-core 2.13.0; read-only `gh` searches; own Lean, difftest, smoke and scala-cli runs, 2026-11-25
> Raw: [Track P7D notes (part 1)](../../raw/cats-effect/2026-11-25-track-p7d-dispatcher-notes.md); [Track P7D mirror notes (part 2)](../../raw/cats-effect/2026-11-25-track-p7d-mirror-notes.md); [Cpus shim](../../raw/cats-effect/2026-11-25-track-p7d-cpus-shim.md); [Identity-hash order](../../raw/cats-effect/2026-11-25-track-p7d-identity-hash.md)

## Overview

Phase 7 batch 7.2, track P7D (decision 66: after track V's `Supervisor`). Mirror of `std.Dispatcher` (`parallel`, `sequential`, `await = true/false`) on track V's `Std/Supervisor.lean`; difftest ops; eight statements: two **refuted** (CE-0090, CE-0091, heavy registry), six `open`; kernel-checked witnesses, wrong-function battery and fixed twins; smoke test. Codec namespaces 90 (closures), 91 (descriptors), 92 (harness).

## Structure (v3.7.1)

- `impl(parallel, await, cancelable)` (:246-381), acquire order: outer `Supervisor(await, checkRestart = always)`, `terminationLatch`, `doneR` (`termination`), the executor (`parallel`: `Supervisor(await)`; `sequential`: in place), the workers (each `Supervisor(false)` + `Resource.make(new Worker)(offer PoisonPill)`), then `launchAll`. Release: the reverse.
- Submission (`unsafeToFutureCancelable`, :288-372) is impure: check `doneR`, `stateR = Unstarted(promisory)`, pick a worker (`ThreadLocalRandom.nextInt(Cpus)`), `unsafeOffer` a registration. Cancel: `Unstarted → CancelRequested(latch)`, `Running(cancel) → Finalizer` registration, `CancelRequested → latch`, `Completed → Future.unit`.
- Worker loop (:411-470): `take`; `Primary` runs the executor (or completes a `CancelRequested` latch); `Finalizer` supervises the cancel; `PoisonPill` stops the worker for good.
- `sequentialCancelable` / `Executor.sequential` are `private[std]` (tests only): excluded.

## Mirror (`Std/Dispatcher.lean`)

- `Resource#fold` makes `IO` nodes only at `Eval` and `Allocate`, so `impl(...).use(f)` is a nesting of `Supervisor.useIO` (track V; its `use` function is "the rest of the fold") and `bracketFull`s for the `Resource.make`s; exact terms for `ifM`, `>>`, `*>`, `<*`, `voidError`, `redeemWith`, `IO.defer`, `cont` (raw part 2).
- Impure calls are one `IO.delay` thunk each (`submitIO`, `cancelIO`): one atomic step of the caller thread, as in the Scala difftest. `Promise` = a cell `pair forget result`; `unsafeRunAndForget`'s `onComplete` reports a failure at once (`UserEffect.report`).
- Worker choice = input list `cs`; `n` workers. Supervisor map order = input `ho`.
- Variants (not Cats Effect code): battery 1-16, 18-20; fixed twins 30 (CE-0090: `doneR` before the pill), 31 (CE-0091: the Worker finalizer waits until the worker took the pill), 32 = 30 + 31.

## Difftest

Ops `dUse`, `dSubmit`, `dForget`, `dCancel`, `dPoll` ([format](../methodology/difftest-program-format.md)); `Cpus` = 1 by `DispatcherShim` (a JVM flag `-XX:ActiveProcessorCount=1`, used for the first 114,000 cases, also moved the identity-hash order of a track V case in the self-test); template `tpl_disp` (own RNG `p_disp`; at most 3 accepted submissions and 2 cancels per scenario: Lean replay cost of the map orders, k!, not an agreement limit). Fixed cases `track_p7d_dispatcher.jsonl`: 68, all agree (the name sorts after `supervisor.jsonl`: `CasesSuite` runs all files in one JVM, and the identity-hash sequence would change track V's expected schedules). Random run (`opcount.py --seeds 91 92 93`, cases 0-36,000 each, `--boost tpl_disp=12`): see "Results".

## Properties (`Props/Phase7/Dispatcher.lean`)

Harness: `Dispatcher.use(d => body)`; the body submits tasks (mode `unsafeToFutureCancelable` or `unsafeRunAndForget`), cancels some, starts a fiber that submits more (concurrent submitter), runs a user program; after `use` the root submits the `late` tasks. Task `j` = `uncancelable(poll => enter(j) *> poll(ws[j].attempt).onCancel(fin(j)) *> mark(j, 2))`. All user programs, worker choices, `PChoice` schedules, map orders.

| Entry | Claim | Status |
|---|---|---|
| `std.Dispatcher.runsOnce` | each effect starts at most once, finalizer at most once (every state) | open |
| `std.Dispatcher.awaitDrains` | `await = true`, pure body submissions: done `Succeeded(())`, every effect ran | **refuted (CE-0091)** |
| `std.Dispatcher.noLostSubmission` | `await = true`, body + concurrent submitter: done ⇒ each submission threw or ran | **refuted (CE-0090)** |
| `std.Dispatcher.closedRejects` | a rejected submission never runs; late submissions throw | open |
| `std.Dispatcher.seqFifo` | `sequential`: start order increasing, one at a time (every state) | open |
| `std.Dispatcher.cancels` | `await = false`, sleeping effects: none finishes its sleep | open |
| `std.Dispatcher.noDeadlock` | pure effects, any cancels: never blocked | open |
| `std.Dispatcher.cancelStops` | `parallel`: a cancel after the start cancels (status 3) | open |

## Kernel runs and battery (`Proofs/Phase7/DispatcherBattery.lean`, heavy, decision 55)

34 runs (`Proofs/Phase7/DispatcherRuns/R*.lean`, generated by `tools/DispRuns/gen.py`), each checked in chunks from literal states ([kernel evaluation](../lean/kernel-evaluation.md), "Long runs in chunks"): first chunk about 2 min and 5.2-6.0 GB, later chunks ≤ 2 GB.

| Operation | raises | hangs | drops | doubles |
|---|---|---|---|---|
| `unsafeToFutureCancelable` (`unsafeToFuture`, `unsafeRunCancelable`) | `awaitDrains` (v1) | `noDeadlock` (v2) | `awaitDrains` (v3) | `runsOnce` (v4) |
| `unsafeRunAndForget` | `awaitDrains` (v9) | `noDeadlock` (v10) | `awaitDrains` (v11) | `runsOnce` (v12) |
| cancel action | `cancelStops` (v5) | `noDeadlock` (v6) | `cancelStops` (v7) | not observable: idempotent (a second cancel returns the same latch or cancels an ended fiber) |
| `Dispatcher.parallel` | `awaitDrains` (v13, on schedule `sched 14 300` where v3.7.1 meets it) | `noDeadlock` (v14) | `closedRejects` (v15: no pill, no `doneR`) | not applicable (a second allocation is unreachable) |
| `Dispatcher.sequential` | `awaitDrains` (v13) | `noDeadlock` (v14) | `noDeadlock` (v15) | not applicable |

Other wrong functions: v16 (ignores `await`) → `awaitDrains`; v18 (`sequential` overlaps) → `seqFifo`; v19 (no closed check) → `closedRejects`; v20 (always awaits) → `cancels`. Satisfiability witnesses (`*_sat`) for all eight hypothesis sets.

## CE-0090 and CE-0091

- **CE-0090** (found by reading): the workers stop at the pill, but `doneR` is set only after the executor release; a submission in that window is accepted and lost. Lean: `dispNoLostSubmission_refuted` (run R32, `sched 14 300`); twin 32 runs both effects (R33).
- **CE-0091** (found by a generated difftest case where both sides agreed): an effect submitted before the scope exits but not yet taken is dropped by `parallel(await = true)`; the worker calls `supervise` on the closed executor `Supervisor` and dies with `IllegalStateException: supervisor already shutdown`. The issue #3506 shape (closed as fixed in 3.4.9; the current test waits for the start). `sequential` drains. Lean: `dispAwaitDrains_refuted` (R15, FIFO); twin 31 (R16). Reproduced on v3.7.1, series/3.x, series/3.7.x.
- The upstream test "reject new tasks while shutting down" cannot fail (`yield fail("fail")`).
- Known, not bugs: a canceled effect never completes its `Future` (#2448); `sequential` cannot cancel queued work (#4069).

## Results

- **Difftest** (`opcount.py --seeds 91 92 93`, cases 0-38,000 per seed, `--boost tpl_disp=12`, 18 processes): 114,000 cases, 113,995 agree, 0 unsupported. Agreeing cases per op: `dUse` 99,647, `dSubmit` 90,802, `dForget` 58,584, `dCancel` 50,425, `dPoll` 77,057 (each over 3 seeds, about a third per seed). Execution coverage (sample of 885 cases with `dUse`, seed 94): a dispatched effect's marker is in the trace in 153 (17%), a poll of a completed Future in 46; the rest end earlier (the appended scenario follows a random program, which can raise, cancel or end by fuel) or lose the effect (CE-0091).
- **Mismatches (5, none a model bug):** (1) `g91-18199`: harness bug of the Scala side (`pollVal` mapped only `UserError`, while `attempt` maps `TimeoutException` too, `CodeOf`); fixed; the case agrees; the last 6,000 cases ran with the fix. (2) `g91-21111`, `g91-30579`, `g92-10716`, `g93-24799`: **harness limit** — each case has a track V `Supervisor` scenario (≥ 2 `supervise`) and a Dispatcher scenario, so two `Supervisor` maps hold ≥ 2 entries. Scala orders each map by identity hashes, independently; the Lean alternatives apply one permutation (by insertion index) to all maps (`Env.supOrder`), so some order pairs are missing. Shown: the same case gives different Scala schedules alone and inside its batch JVM (`g91-21111`, `g91-30579`; `g91-21111` agrees alone and mismatches in a 12-case batch), and with either scenario removed all 8 reduced cases agree. Fixed in the harness afterwards: `run.sh` and the golden-test JVM use `-XX:hashCode=2` (all identity hashes equal), so Scala iterates every map in insertion order in every batch; this also fixed 11 `CasesSuite` failures of `supervisor.jsonl` that were on `main`, and a self-test prefix violation (raw: identity-hash order). The generator is not capped; it only skips the Dispatcher scenario in cases with `maxSteps ≤ 5` (where it cannot run). With the final harness all 5 former mismatches agree, `g91-21111` gives the same schedule alone and in its batch, the CI-shaped run (`drive.py run --seeds 1 2 3 --n 2000`) has 6,000/6,000 agreeing cases, and a fresh sample (`opcount.py`, seeds 91-93, cases 40,000-41,000, boost 12) 3,000/3,000 (agreeing per op: `dUse` 2,514, `dSubmit` 2,271, `dForget` 1,434, `dCancel` 1,264, `dPoll` 1,958).
- **Kernel:** 34 runs, 88 chunk modules, all built: first chunks 1-2.3 min, 5.2-7.2 GB; later chunks ≤ 2 GB. Axioms of the refutations: `propext`, `Classical.choice`, `Quot.sound`.
- **Smoke** (`lake exe dispsmoke 30`, 30 runs per row, random inputs and schedules, hypotheses evaluated: 0 failures): v3.7.1 has 0 violations of the six open statements; `awaitDrains` 15/30 and `noLostSubmission` 17/30 (the bugs); fixed twins 31 and 32: 0/30. Wrong variants: `runsOnce` v4 2, v12 7; `awaitDrains` v1 26, v3/v9/v11/v13 30, v16 28; `closedRejects` v19 14 (v15 0: its runs block, see R20 for the kernel break); `seqFifo` v18 5; `cancels` v20 18; `noDeadlock` v2 25, v6 9, v10 24, v14 30, v15 15; `cancelStops` v5 15, v7 15.
- No proof of the open statements yet: a proof needs a state invariant over `Step`/`SchedP` (as the other Phase 6/7 open entries).

## See Also

- [Supervisor model](supervisor-model.md)
- [Resource use, allocated, both](resource-use-both-model.md)
- [Bug history](bug-history.md)
- [Differential testing](../methodology/differential-testing.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Agent workflow](../methodology/agent-workflow.md)

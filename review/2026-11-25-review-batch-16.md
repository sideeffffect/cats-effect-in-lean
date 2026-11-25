# Review batch 16 (2026-11-25): Phase 7 batch 7.2 gate (Supervisor, Dispatcher)

Reviewer: independent agent. It did not write the code. It read the Lean source, the registries, the witness and battery files, two kernel run files, the inventory, the bug records, the reproducers, the wiki articles and the Scala source at `v3.7.1` (`~/Projects/cats-effect`, read only, HEAD not changed). It did not run a build, Lean, a test, sbt, scala-cli or a difftest. It ran read-only `gh issue view 3506` and read-only `grep`/`awk` on the inventory.
Reviewed commit: `58ef474` (`origin/main`), on branch `docs/review-batch-16-supervisor-dispatcher`.
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 55, 58, 63 with the batch-13 battery rules, "Reviewer evidence"); decisions 64–67. When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `raw/`, `wiki/`, `inventory/`, `review/`, `bugs/`, `reproducers/` or `difftest/`. `SV` = `std/shared/src/main/scala/cats/effect/std/Supervisor.scala`, `DP` = `.../std/Dispatcher.scala`, `DS` = `tests/shared/src/test/scala/cats/effect/std/DispatcherSuite.scala`, all at `v3.7.1`.

## Summary

| Item | Result |
|---|---|
| 7 `std.Supervisor.*` entries (all open) | 7 FAITHFUL as statements |
| `std.Dispatcher.awaitDrains` (refuted, CE-0091) | FAITHFUL |
| `std.Dispatcher.noLostSubmission` (refuted, CE-0090) | **HOLLOW** (B1) |
| 6 other `std.Dispatcher.*` entries (open) | 6 FAITHFUL as statements |
| Supervisor battery | complete (N3: variant 11 smoke only) |
| Dispatcher battery | complete (N4: cancel doubles argued, not run) |
| (a) generator cap of 5 `supervise` | must be lifted now (C2) |
| (b) decision 67 | not a weaker gate (N5, N6) |
| (c) P7D difftest counts | not enough by the letter of the rule (C1) |
| (d) `LIB_EXNS` | acceptable |
| (e) atomic `unsafe*` steps | acceptable for refutations and open entries; not for a proof (C4) |
| (f) CE-0091 vs #3506 | reasoning correct (N7) |

Gate (section F): **FAIL**. One blocker (B1). 14 of 15 entries FAITHFUL.

---

## A. What I read

- `Registry.lean:911-975` (14 entries), `RegistryHeavy.lean:44-57` (2 heavy entries; `std.Dispatcher.awaitDrains` and `std.Dispatcher.noLostSubmission` are the heavy ones, so 7 + 8 = 15 entries in all).
- `Props/Phase7/Supervisor.lean` in full; `Props/Phase7/Dispatcher.lean:1-140`, `:250-551`.
- `Std/Supervisor.lean:1-128`, `:620-700`, `:860-1040` (the `supervise` chain, `add`, `remove`, `allFibers`, release, `use`). The restart branch (`:1040-1191`): constructor list and citations only (N2).
- `Std/Dispatcher.lean:1-110`, `:560-575`, `:690-760`, `:933-1000` (resource nesting, `inner`, worker choice, `Worker#run` step, `registerCancel`, `Executor.inplace`, queue take).
- `Proofs/Phase7/SupervisorWitness.lean` (theorem list); `Proofs/Phase7/DispatcherBattery.lean:1-175` and the theorem list; `DispatcherRuns/R15.lean`, `R32.lean` (`obs`).
- `SV:90-129`, `:150-409`; `DP:55-112`, `:125-470`, `:475-520`, `:608-622`; `DS:45-58`, `:639-647`.
- `bugs/CE-0090.yaml`, `bugs/CE-0091.yaml`; `reproducers/CE-0090/Repro.scala`, `reproducers/CE-0091/Repro.scala`.
- `inventory/inventory.csv` rows `std.Supervisor.*`, `std.Dispatcher.*`, `std.DispatcherPlatform.*`.
- `wiki/cats-effect/supervisor-model.md`, `wiki/cats-effect/dispatcher-model.md`; `difftest/py/drive.py:155-185`; decisions 64–67.

## B. Supervisor (track V)

### B.1 Mirror (all 7 entries)

- `supervise` (`SV:184-328`): `Std/Supervisor.lean:941-1000` follows the `for` chain in order: `F.ref(false)` (`kDone`), `F.deferred` (`kIr`), `F.unique` + `cleanup` (`kIr`, `tokPair`), `monitor(fa', fin)` (`kTok`), `state.add` (`kFib`), `insertResult.complete` (`kAdd`), `done.get.ifM(cleanup, unit)` (`kCmp`, `ifDone`), raise `IllegalStateException` if `!insertOk` (`kLast`). `fa'` = `insertResult.get.ifM(fa, F.canceled *> raise)` (`ifIns`, `SV:305-311`). The `None` monitor = `F.start(fa).flatMap(fib => F.start(fib.join.guarantee(fin)).as(fib))` (`monNone`, `SV:290-292`).
- State, `Async` kind (`cv = 0`, the one `IO` takes, `SV:136`): `add` = `put` then `doneR.get.map(!_)` (`addIO`, `putThunk`, `thenNotDone`; `SV:378-386`); `remove` = `state.remove` (`removeThunk`, `SV:376`); `allFibers` reads the values without a reset (`values`, `SV:391-401`).
- State, `Concurrent` kind (`cv = 1`): `modify` with `null` (`modAdd`, `SV:343-347`), `update` (`updRemove`, `SV:338-341`), `getAndSet(null)` (`getAndSetNull`, `SV:352-357`).
- Release (`SV:168-173`): `releaseIO` joins only for `Succeeded` and `await`; else cancels; `doneR.set(true)` first. Correct.
- `joinAll` = `traverse_` fold, `cancelAll` = `parUnorderedTraverse` via `both` (`Std/Supervisor.lean:93-99`); map order is the input `ho`, any permutation in the statements.
- MIRROR: yes for all 7 entries.

### B.2 Per entry

| Entry | MIRROR | PROPERTY | SETTLED | Verdict |
|---|---|---|---|---|
| `std.Supervisor.noLeak` (`supNoLeakV`, `Props/Phase7/Supervisor.lean:378`) | yes | yes: `SV:28-36` ("guaranteed to be terminated when the supervisor is terminated"); any `aw`, `r`, `cv`, user programs, nesting, schedules, orders | open | FAITHFUL (statement) |
| `std.Supervisor.closedNoRun` (`:386`) | yes | yes: `SV:97-98`; part 1 in every state; part 2 for `late` children when the root is `Succeeded(())` | open | FAITHFUL (statement) |
| `std.Supervisor.runsOnce` (`:397`) | yes | yes: no restart (`r = false`) is the only hypothesis; restart runs `fa` again by design | open | FAITHFUL (statement) |
| `std.Supervisor.awaitJoins` (`:405`) | yes | yes: decision 63 success claim; `SV:120-127` ("true - wait for the completion") | open | FAITHFUL (statement) |
| `std.Supervisor.noDeadlock` (`:417`) | yes | yes: pure user programs, nesting races the close | open | FAITHFUL (statement) |
| `std.Supervisor.removed` (`:425`) | yes | yes, low strength: only blocked states (N1) | open | FAITHFUL (statement) |
| `std.Supervisor.cancels` (`:437`) | yes | yes: `SV:121-127` ("false - cancel the active fibers") | open | FAITHFUL (statement) |

Checks by reading (v3.7.1 code):

- `noLeak` with `await = true`, `Async` state: a `supervise` that reads `doneR = false` did its `put` before that read, so before `doneR.set(true)` and before the `allFibers` snapshot. The snapshot holds it. A later `supervise` reads `doneR = true` and its fiber self-cancels (`SV:305-311`). So no leak. With nesting (`cKids` runs inside the supervised child) the same holds.
- `removed`: with `checkRestart = None` the removal runs in the second fiber `fib.join.guarantee(fin)` (`SV:291`), and `done.get.ifM(cleanup)` (`SV:315-319`) covers the race "child ends before `add`". In a blocked state no fiber is ready, so both have run.
- `cancels`: the body does not move the clock (`IO.pure`/`IO.cede`); the close cancels sleeping children before time can move.

Wrong-function test (`Proofs/Phase7/SupervisorWitness.lean`): `noLeak_v7` (finalizer drops), `closedNoRun_v9` (`add` ignores shutdown), `runsOnce_v4` (doubles), `awaitJoins_v1/_v3/_v5/_v12` (raises, drops, factory raises, `await = true` cancels), `noDeadlock_v2/_v6` (hangs, factory hangs), `removed_v10`, `cancels_v8`. Every entry has a kernel wrong-function theorem and a kernel witness (`*_sat`, decision 53). The safety entries (`noLeak`, `closedNoRun`, `runsOnce`, `removed`) are also met by "supervise drops"; `awaitJoins` breaks that (`awaitJoins_v3`), so the battery covers it.

### B.3 Battery (decision 63)

| Operation | raises | hangs | drops (honest) | doubles |
|---|---|---|---|---|
| `supervise` | v1 (`awaitJoins_v1`) | v2 (`noDeadlock_v2`) | v3: returns a fiber of `IO.unit`, no state = honest drop (`awaitJoins_v3`) | v4 (`runsOnce_v4`) |
| factory `apply(await)`, `apply` | v5 (`awaitJoins_v5`) | v6 (`noDeadlock_v6`) | release drops v7 (`noLeak_v7`); `await` inverted v8 (`cancels_v8`), v12 (`awaitJoins_v12`) | no meaning (a factory) |
| `State.add` / `remove` (internal) | – | – | v9 (`closedNoRun_v9`), v10 (`removed_v10`) | – |
| restart path (`private[std]`) | – | – | v11: smoke only (N3) | – |

Complete. The restart path is reachable only through `Dispatcher` (`DP:254`); the Dispatcher battery covers that use.

## C. Dispatcher (track P7D)

### C.1 Mirror (all 8 entries)

- Resource nesting (`Std/Dispatcher.lean:20-38`) matches `DP:250-287`: outer `Supervisor(await, always)`, `awaitTermination`, `termination`, executor (`Executor.parallel(await)` = `Supervisor(await)`, `DP:615-621`, or `inplace`), workers (`Worker.apply` = `Supervisor(false)` + `make(init)(offer PoisonPill)`, `DP:475-488`), `evalMap(launchAll)`. Release order = reverse. Correct.
- `inner` (`innerEff`, `:701-722`): `doneR` check first (`DP:293-295`), `stateR.set(Unstarted(promisory))`, worker choice (`DP:325-329`, an input), `Finalizer` or `Primary` offer (`DP:331-338`), `cancel _`.
- `Worker#run` step (`:933-1000`): `Primary` → `Unstarted` → `executor(action)(registerCancel)`; `Running`/`Completed` → `AssertionError`; `CancelRequested` → `latch.success` (`DP:412-456`); `Finalizer` → `supervise(action).void.voidError` (`DP:458-459`); `PoisonPill` → worker `doneR` (`DP:461-462`). `registerCancel` CAS chain (`regThunk`) follows `DP:418-447` branch by branch.
- Impure calls are one atomic step each (item (e), C4).
- MIRROR: yes for all 8 entries.

### C.2 Per entry

| Entry | MIRROR | PROPERTY | SETTLED | Verdict |
|---|---|---|---|---|
| `std.Dispatcher.runsOnce` (`dispRunsOnceV`, `Props/Phase7/Dispatcher.lean:475`) | yes | yes | open | FAITHFUL (statement) |
| `std.Dispatcher.awaitDrains` (`:482`, heavy) | yes | yes (C.3) | refuted, CE-0091 | FAITHFUL |
| `std.Dispatcher.noLostSubmission` (`:492`, heavy) | yes | **no** (B1) | refuted, but the refutation does not show the bug (B1) | **HOLLOW** |
| `std.Dispatcher.closedRejects` (`:502`) | yes | yes: `DP:130-133`, `:168-171` | open | FAITHFUL (statement) |
| `std.Dispatcher.seqFifo` (`:511`) | yes | yes: `DP:173-177` (sequential FIFO, one at a time; N9) | open | FAITHFUL (statement) |
| `std.Dispatcher.cancels` (`:519`) | yes | yes: `DP:163`, `:199` | open | FAITHFUL (statement) |
| `std.Dispatcher.noDeadlock` (`:527`) | yes | yes | open | FAITHFUL (statement) |
| `std.Dispatcher.cancelStops` (`:535`) | yes | yes: `DP:62-66`; the body waits until each task started and its cancel future completed, so the `Unstarted → CancelRequested → Running` race (`DP:422-430`) is inside the claim | open | FAITHFUL (statement) |

Wrong-function test (`DispatcherBattery.lean:79-259`): each open entry has a kernel witness (`*_sat`) and at least one kernel wrong-function theorem (table at `:43-56`).

### C.3 `std.Dispatcher.awaitDrains` (CE-0091)

1. MIRROR: yes.
2. PROPERTY: yes. Source (a) of `AGENTS.md`: Cats Effect disagrees with itself. `sequential(await = true)` drains the queue (test `DS:45-58`); `parallel(await = true)` does not. Also `DP:130-133`, `:160-163` and issue #3506 (same program shape, closed as fixed). Input: the body submits pure tasks, no cancel; `b`, `c` pure. The body's submissions all return before `use` returns, so "root done" means every task was accepted.
3. SETTLED: yes.
   - Theorem type: `dispAwaitDrains_refuted : ¬ dispAwaitDrains` (`DispatcherBattery.lean:139`), exactly the negation; registry `thm` names it (`RegistryHeavy.lean:49`).
   - Witness: R15 (`DispatcherRuns/R15.lean:27-31`): `parallel`, `await = true`, one task, FIFO, 216 micro-steps: `halt = done Succeeded(())`, `status 0 = 0`, `runs 0 = 0`. This is the bug path.
   - Fixed twin 31 (decision 39): only the `Worker` finalizer changes (wait until the worker took the pill). Same input: the task runs (`awaitDrains_twin31`, R16). Honest. The twin is checked on the refuting input only, which is what decision 39 asks.
   - Bug record: all fields (`bugs/CE-0091.yaml`). Reproducer: last `println` is `REPRODUCED CE-0091` (`reproducers/CE-0091/Repro.scala:67`) under the stated condition; `output` lists v3.7.1, series/3.x, series/3.7.x.
4. Verdict: FAITHFUL.

### C.4 B1: `std.Dispatcher.noLostSubmission` is HOLLOW

Statement (`Props/Phase7/Dispatcher.lean:492-500`): for all `ps` with `p ≤ 1`, all user programs `c`, all schedules: if the root is done, every task `j` has `rejected j = 1` or `status j = 2`.

Problem: the concurrent submitter (`ps[j] = 1`) is a fiber that the body starts and nobody joins (`HLam.tail`, `:325-326`: `.start (c.attempt >>= conc)`). The run stops when the root fiber has an outcome (`Model/Sched.lean:25-26`, `:176-178`). So the statement is false for **every** Dispatcher, also a correct one:

- `c = IO.never` (well-formed: `dispLib` allows the `IO.never` closures, `:428-443`). The concurrent fiber never submits. The root ends `Succeeded(())`. Task `j` has `rejected = 0` and `status = 0`.
- Or `c = IO.pure(())` and a schedule that never picks the concurrent fiber before the root ends.

Consequences:

1. PROPERTY: no. The statement is not a promise of Cats Effect: no implementation meets it.
2. SETTLED: no. `dispNoLostSubmission_refuted` (`DispatcherBattery.lean:158-164`) uses R32, whose kernel fact is only `done Succeeded(())`, `status 0 = 2`, `status 1 = 0`, `rejected 1 = 0` (`DispatcherRuns/R32.lean:27-31`). It does not show that task 1 was submitted. So the kernel proof does not separate the CE-0090 path from "the concurrent fiber did not run yet". The record text "effect 1 was accepted (no IllegalStateException)" (`bugs/CE-0090.yaml`, `lean.run`) is not in the kernel fact.
3. Fixed twin 32 (decision 39) is not honest evidence here: variant 32 also fails the statement with `c = IO.never`. `noLost_twin32` holds on one input and schedule only.
4. Wrong-function test: "every implementation" refutes the statement, so the refutation carries no information.

CE-0090 itself stays a valid bug candidate: the reproducer submits during the release with `allocated` and shows the lost submission on v3.7.1 (`reproducers/CE-0090/Repro.scala:42-61`, last line `:79`). Only the Lean side is HOLLOW.

Required fix (one of these; do not weaken the claim about accepted submissions):

- (preferred) The root joins the concurrent fiber after `use` returns and before the `late` tasks (harness change in `HLam.afterCells`/`lateK`). Then "root done" means every submission has returned or thrown, and the statement is meaningful.
- Or restate the conclusion for accepted tasks only: "if the submission of task `j` returned (cell 6 holds its result), then `status j = 2`". This is the CE-0090 claim exactly.

Then: re-derive R32 so that its kernel fact includes "task 1's submission returned" (cell 6 or the joined fiber), re-check twin 32 on that input, keep a satisfiability witness (`noLost_sat`), and correct `bugs/CE-0090.yaml` `lean.run`/`ordinary_inputs` (`noLost_sat` is one run, not "the statement holds for `sequential`"). Until then the registry entry must not be `refuted`: set it `open` with a note, and CE-0090 counts as a bug candidate with a reproducer only (as decision 66 did before the Lean work).

### C.5 Battery (decision 63)

| Operation | raises | hangs | drops (honest) | doubles |
|---|---|---|---|---|
| `unsafeToFutureCancelable` | v1 (`awaitDrains_v1`) | v2 (`noDeadlock_v2`) | v3: returns a future, offers nothing = honest drop (`awaitDrains_v3`) | v4 (`runsOnce_v4`) |
| `unsafeRunAndForget` | v9 (`awaitDrains_v9`) | v10 (`noDeadlock_v10`) | v11 (`awaitDrains_v11`) | v12 (`runsOnce_v12`) |
| cancel action | v5 (`cancelStops_v5`) | v6 (`noDeadlock_v6`) | v7: completed future, no change = honest drop (`cancelStops_v7`) | v8: argued not observable (N4) |
| factories `parallel(aw)`, `sequential(aw)` (+ overloads, `apply`) | v13 (`awaitDrains_v13_seq/_par`) | v14 (`noDeadlock_v14_seq/_par`) | release drops v15 (`noDeadlock_v15`, `closedRejects_v15` per registry note); `await` ignored v16, always v20; wrong executor v18 | no meaning |
| closed check | – | – | v19 (`closedRejects_v19`) | – |

`unsafeToFuture` = `unsafeToFutureCancelable(fa)._1` (`DP:72-73`) and `unsafeRunCancelable` = `._2` (`DP:79-80`) are projections; `unsafeRunAndForget` calls `unsafeToFuture` (`DP:85-89`). They need no rows of their own. Complete.

## D. Inventory

- 13 rows have registry links but status `todo`: `std.Supervisor.supervise`, `.apply`, `.apply#3`, `.State.remove`, `.State.add`, `.State.joinAll`, `.State.cancelAll`, `.SupervisorImpl.supervise`, `std.Dispatcher.unsafeRunCancelable`, `.apply`, `.parallel`, `.sequential`, `.Executor.apply`. A row is modelled through a registry entry; the status must say so (C3).
- `std.DispatcherPlatform.unsafeRunSync`, `unsafeRunTimed`, `unsafeToCompletableFuture` (`inventory/inventory.csv:2636-2638`): `todo`, no link. They are public, JVM. Not in batch 7.2 scope by decision 64 (it names `Dispatcher.scala` only). Low N8.
- Exclusions checked: `Executor.sequential` (only `private[std] sequentialCancelable`, `DP:205-207`) — correct; `applyForAsync`/`applyForConcurrent` "modelled as part of its public caller" — correct (both mirrored).

## E. Gate items (a)–(f)

**(a) Cap of 5 `supervise` per scenario.** Track V added the cap after 12 mismatches with 6–8 `supervise`: the Lean side listed only 120 (5!) orders and the Scala order was outside them (`wiki/cats-effect/supervisor-model.md:42`). That is a harness limit, not a model bug, but the cap removed generator cases to get agreement, which `AGENTS.md` forbids. With decision 67 the Scala order is the insertion order, so the Lean side needs only that order for refinement (a subset of the Lean outcome set is a stronger check, never a weaker one). The reason for the cap is gone. **Lift it** (C2). Caveat: "insertion order" holds only for small maps (N6); keep the Lean side checking all orders up to 5 and at least the insertion order above, and use a bound such as 8 `supervise` until N6 is checked.

**(b) Decision 67.** Not a weaker gate. The comparison is still refinement; the Lean model and its outcome set did not change; the flag changes only the Scala run, not Cats Effect code; reproducers run without it. Cost: the Scala side now shows one map order only. Real non-insertion orders are covered only by runs before the flag (track V run 2, 58,500 cases; P7D 114,000). Record that (N5).

**(c) P7D difftest counts.** The rule: 100 % agreement on ≥ 50,000 cases with several seeds. The main run (114,000 cases, seeds 91–93) had 5 mismatches; 1 was a Scala harness bug (`pollVal`), fixed for the last 6,000 cases only; 4 were the map-order harness limit, fixed by decision 67. With the final harness: the 5 cases, 6,000 CI-shaped cases and 3,000 fresh cases agree (`wiki/cats-effect/dispatcher-model.md:66-67`). The Lean model did not change, so the 113,995 agreeing real runs stay valid evidence, and I do not suspect the model. But no single run of ≥ 50,000 cases reached 100 % with the harness in force. Not enough by the letter. **C1**: one run of ≥ 50,000 cases over ≥ 3 seeds with the final harness, for the P7D ops and the track V ops (decision 67 also changed the Scala side of track V). Compute only.

**(d) `LIB_EXNS`.** Acceptable. The filter (`difftest/py/drive.py:159-181`) only stops `scala_problem` from calling a library exception a generator bug. The outcome comparison (`compare`, `obs`) still compares the outcome, so the Lean side must raise the same error. The mirror raises `iseErr` exactly where `SV:320-323` raises. It is library behaviour, not user code (decision 8 is about user errors).

**(e) `unsafe*` as one atomic step.** The real call has two steps that others see: the `doneR` read (`DP:293`) and the queue offer (`DP:331-338`, itself `UnsafeUnbounded.put` then a latch `getAndSet` and callback, `DP:632-637`); `cancel()` reads then CASes in a loop (`DP:341-364`); `UnsafeUnbounded.take` can throw `FailureSignal` while a `put` is half done (the mirror throws it only on an empty list, `Std/Dispatcher.lean:66-68`). One atomic step is a subset of the real interleavings. So: a refutation on it is a real schedule (and the reproducers confirm both bugs); an open statement is not harmed. A **proof** on it can be false for the real library. **C4** (not for this gate): before any Dispatcher entry becomes `proven`, split these calls into their visible steps or prove a reduction lemma. Record it in the wiki article.

**(f) CE-0091 vs issue #3506.** The reasoning is correct. Checked: workers are acquired after the executor (`DP:273-279`), so they are released first; the `Worker` finalizer only offers the pill (`DP:487`); `Executor.parallel` = `Supervisor(await)` (`DP:615-621`); `supervise` on a closed supervisor raises `IllegalStateException("supervisor already shutdown")` (`SV:320-323`); the worker's `Primary` branch calls `executor(action)` (`DP:417`). The upstream test (`DS:639-647`) waits for `latch.get` (the effect started) before it leaves the scope, then asserts non-termination: it does not cover a registration still in the queue. Issue #3506 (read-only `gh issue view`): `parallel(await = true)`, two `unsafeRunAndForget` calls, then the scope ends — the CE-0091 shape. N7: "regressed" is an inference; the reproducer did not run on 3.4.9.

## F. Gate: Phase 7 batch 7.2

### F.1 Entries

15 entries: 7 `std.Supervisor.*` (`Registry.lean`) and 8 `std.Dispatcher.*` (6 in `Registry.lean`, 2 in `RegistryHeavy.lean`). 14 FAITHFUL (13 as statements, open; 1 refuted). 1 HOLLOW (`std.Dispatcher.noLostSubmission`). Table: `wiki/methodology/phase7-batch2-gate-report.md`.

### F.2 Batteries

| Structure | Complete |
|---|---|
| Supervisor | yes (N3) |
| Dispatcher | yes (N4) |

### F.3 Verdict

**FAIL.** Blocker:

- **B1**: `std.Dispatcher.noLostSubmission` is HOLLOW: false for every implementation (unjoined concurrent submitter); the kernel refutation does not show that the lost task was submitted; twin 32 also fails it. Fix as in C.4; until then the entry is `open`, not `refuted`.

Conditions (each must be closed before PASS):

- **C1**: difftest ≥ 50,000 cases, ≥ 3 seeds, 100 % agreement, with the final harness (`-XX:hashCode=2`, the `pollVal` fix), covering the P7D and track V ops.
- **C2**: lift the 5-`supervise` cap (with the bound of N6), and include those cases in C1.
- **C3**: set the 13 linked `todo` rows (section D) to `modelled`.
- **C4** (for later proofs, not for this gate): split the atomic `unsafe*` steps or prove a reduction before any Dispatcher entry is `proven`. Record it in `wiki/cats-effect/dispatcher-model.md`.
- **C5**: CI green on the commit that closes B1 (including `heavy-proofs` with the new R32).

## G. Low notes

- N1: `supRemoved` holds only for blocked states. A stronger form ("at the end of a `supervise` call, plus one step of the cleanup fiber") is possible; not required.
- N2: I read the restart branch of `Std/Supervisor.lean` (`:1040-1191`) at the level of constructors and citations, not each body. The difftest runs restart cases (≤ 2 children, `maxSteps` 150). A later review should read it line by line before a restart-path entry is proven.
- N3: variant 11 (restart ignores `canceled`/`done`) breaks `noLeak` in smoke only, not in the kernel.
- N4: cancel "doubles" (v8) has no theorem; the registry note argues it is idempotent (`CancelRequested` returns the same future; a second `Finalizer` cancels an ended fiber). I agree by reading `DP:341-364`. Acceptable, but say "argued" in the battery table.
- N5: decision 67 article: state that non-insertion orders are covered only by the pre-flag runs (58,500 + 114,000 cases).
- N6: "all identity hashes equal ⇒ insertion order" is true for a small `ConcurrentHashMap`. With one bin and many entries the JDK treeifies the bin (`TREEIFY_THRESHOLD` 8, table ≥ 64) and a `TreeBin` puts new nodes at the head of its `first` list, so the iteration order is then no longer the insertion order. Check the bound (expected at about 9–12 entries) before you rely on it for larger maps.
- N7: CE-0091 `duplicates.related` says "regressed"; no run on 3.4.9 shows that. Say "probably regressed" or run the reproducer on 3.4.9.
- N8: `DispatcherPlatform.unsafeRunSync`/`unsafeRunTimed`/`unsafeToCompletableFuture` stay `todo`; plan them for batch 7.3 or exclude with a reason.
- N9: `seqFifo` covers both submission modes; `DP:174-176` promises the order only for `unsafeRunAndForget`. Both modes take the same path (`inner`), so the claim is true by reading. If it is ever refuted only with `unsafeToFutureCancelable`, that is not a broken promise; then add the `unsafeRunAndForget`-only form.

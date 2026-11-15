# Review batch 11b (2026-11-15): Phase 7 tracks S (`Semaphore`, `Mutex`) and L (`CountDownLatch`, `CyclicBarrier`)

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the witnesses, the smoke tools, the bug record, the reproducer, the wiki and the raw notes, and the Scala source at `v3.7.1` (`~/Projects/cats-effect`, HEAD `eb0cc258fc`, not changed). It did not run a build, Lean, a test, sbt or a difftest. It ran only read-only `gh api` GET calls (PR #4648, commit ancestry, the `Semaphore.scala` file at `v3.7.0`).
Reviewed commit: `9f8a482` (origin/main), branch `review11b`.
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 56, 58, "Reviewer evidence", "Closure references"); decisions 59-62. When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `bugs/`, `raw/`, `wiki/`, `tools/`, `test/`, `difftest/`, `reproducers/`, `inventory/` or `.github/`. `S` = `std/shared/src/main/scala/cats/effect/std/Semaphore.scala`, `LQ` = `.../std/LockQueue.scala`, `CDL` = `.../std/CountDownLatch.scala`, `CB` = `.../std/CyclicBarrier.scala`, all at `v3.7.1`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `std.Semaphore.noLostPermit` | open | FAITHFUL as a statement (weakness W1) |
| `std.Semaphore.noDeadlock` | open | **HOLLOW** (H1: a fatal error in user code refutes it for every implementation) |
| `std.Semaphore.permit.atMostK` | open | FAITHFUL as a statement (W1) |
| `std.Mutex.lock.mutualExclusion` | open | FAITHFUL as a statement |
| `std.Mutex.lock.noDeadlock` | open | **HOLLOW** (H1, same cause) |
| `std.Semaphore.count.atRest` (CE-0060) | refuted | FAITHFUL |
| `std.Semaphore.acquireN.fifo` | open | FAITHFUL as a statement (W1) |
| `std.Mutex.lock.semaphoreTwin` | open | FAITHFUL as a statement (one direction, stated; L2) |
| `std.CountDownLatch.awaitNotEarly` | open | FAITHFUL as a statement |
| `std.CountDownLatch.noLostWakeup` | open | FAITHFUL as a statement |
| `std.CountDownLatch.releaseTotal` | open | FAITHFUL as a statement |
| `std.CyclicBarrier.noEarlyTrip` | open | FAITHFUL as a statement |
| `std.CyclicBarrier.exactGenerations` | open | FAITHFUL as a statement |
| `std.CyclicBarrier.cancelNoHang` | open | FAITHFUL as a statement |
| `std.CyclicBarrier.cancelRemoved` | open | FAITHFUL as a statement (hypothesis accepted, see 2.4) |

Findings: H1 (HOLLOW, two entries). W1 (weakness: no `Semaphore` statement fails for "`acquireN(n)` always raises" with `n ≥ 2`). Low: L1 (the one `Semaphore` difftest mismatch is plausible, not shown), L2 (twin doc sentence), L3 (no recorded difftest run after the merge fix `1e84acb`), L4 (citation drift).
Forgery: none found (section 3). Gates: no case deleted, no gate lowered (section 4).

---

## 1. Track S

### 1.1 Facts checked against the source

- **Mutex has only `ConcurrentImpl` over `LockQueue` at v3.7.1: yes.** `Mutex.scala:68-74` and `:79-85` build `new ConcurrentImpl(state)` over `Ref[F, LockQueue.Cell]`; `:87-97` is the only implementation; `:92-93` `lock = LockQueue.lock(queue = state)`. No `AsyncImpl` in the file. `gh api compare 8deb2fdabe...v3.7.1`: `ahead`, `behind_by 0` (the commit "Re-implement Mutex using the shared LockQueue" is in v3.7.1).
- **PR #4648 is in v3.7.1: yes.** `gh api pulls/4648`: base `series/3.7.x`, merged 2026-08-22, merge commit `df5b2c6834`. `compare df5b2c6834...v3.7.1` and `compare 643ba33566...v3.7.1`: `ahead`, `behind_by 0`. The PR body says "2. count may transiently include them." The `count` Scaladoc at `S:47-53` is the old text.
- `v3.7.0` `cleanup` (via `gh api contents?ref=v3.7.0`): `waiting.filterNot(_ sameAs req)` and `releaseN(permitsAcquiredSoFar)`. This matches the fixed twin description.

### 1.2 Mirror (all eight entries share it)

`Model/Semaphore.lean` against `S:145-282`, line by line:

- `acquireN` (`S:179-207`): `acquireNIO` (`n == 0` → `pure`), `acqBody` → `newDeferred` → `acqGate` → `modAcq` (`:499-511`): `waiting` non-empty → enqueue with `(n, n, g)` and `State(0, …)`; else `n ≤ permits` → `State(permits - n, [])`; else `State(0, [(n, n - permits, g)])`. Same order as `S:196-203`. `await` = `dAwait` → `.onCancel (applyPoll (deferredGetOf g none)) (cleanupIO)` (`descIO`, `:457`); `cleanup` = `complete` then `wonK` (`:513-517`): `true` → `reclaim(req)`, `false` → `releaseN(n)` (`S:188-191`). Correct.
- **The new cancellation (canceled waiter stays queued): mirrored.** `modRec` (`:546-557`) removes the request only when the head has the same gate, and returns `releaseN(rq - rm)` = `releaseN(head.sunk)` (`S:171-175`); otherwise it writes the same state and returns `F.unit`. So a canceled non-head request stays in the queue, as in Scala.
- `releaseN` (`S:209-254`): `modRel` (`:519-530`): empty queue → `permits + n`; else `fulfil` (`:374`, same branches as `S:212-227`), state `(newN, waitingNow)`, effect `wake *> sweep` (`dWakeSweep`). `wakeWon` (`:532-536`): `won` → unit, else `releaseN(requested)` (`S:238-241`). `sweepSel` (`:538-542`): `Some` → `reclaim` (`S:245-247`). `wakeIO` (`:445`) is `traverseVoidDirectly` (fold with `productR`, then `void`); `sweepIO` (`:452`) is the `Option` `traverse_` with `map2Eval`. Correct.
- `count` (`:567-574`): non-empty queue → `-(sum of remaining)`, else `permits` (`S:258-263`). `available`, `tryAcquireN`, `permit` (`makeFull { poll => poll(acquire) } { _ => release }`, `S:265-266`) correct.
- `Model/Mutex.lean` against `LQ:42-109`: `acquire` = `newDeferred` → `getAndSet` (`:245`) → `loopIO` (`:209`): `EmptyCell` (`.none`) → `pure ourCell`; a cell → `onCancel(poll(get), awakeCellIO ourCell next)` then `flatMap loop` (`LQ:88-97`). `awakeCellIO` (`:205`) = `access` → `awA` (`:270`: `last == ourCell` → apply the setter, else `pure false`) → `awB` (`false` → `complete(next).void`, `true` → unit) (`LQ:53-64`). `SyncRef.access` at v3.7.1 has no "called once" flag (`kernel/jvm-native/.../SyncRef.scala:47-52`, read). `release` = `awakeCell(ourCell, EmptyCell)` (`LQ:104-105`). Correct.

MIRROR: yes for all eight entries. Citations: correct except L4.

### 1.3 Per entry

**`std.Semaphore.noLostPermit`** (`Props/Phase7/Semaphore.lean:499`).
1. MIRROR: yes. 2. PROPERTY: yes. All `u` with `WellFormed semLib`, all `k`, uses, acts, fuel, `PChoice` lists. `AllEnded` is a test-shape condition (all fibers ended), not an API precondition; it does not remove a cancel case (cancel is one of the two ways to end). Promise: `S:28-35`, `S:63-65`. 3. SETTLED: open. 4. Wrong-function: "leak", "twice" break it (`tools/SemSmoke/Main.lean`, header list and `:300-370` area). "acquireN always raises" satisfies it (W1). 5. Decision 53: `semNoLostPermit_satisfiable` (`Proofs/Phase7/SemaphoreWitness.lean`, kernel run `run1_ok`, `wfConst`, `AllEnded` proved). All hypotheses together: yes. 6. Forgery: none (section 3).
Verdict: FAITHFUL as a statement.

**`std.Semaphore.noDeadlock`** (`:509`). **HOLLOW (H1).**
The statement says: every stopped run ends `Succeeded`. The behaviour table `Base.err e` (`:430`, `BH.call` `:464`) takes any `e : Err`, also `e.kind = .fatal`. A fatal `IO.raiseError` goes to `raised` (`Model/Step.lean:815`): `Flow.fatal`. The scheduler then stops the whole run with `Summary.fatal` (`Model/Sched.lean:120`). `Summary.fatal` is a result (`Model/Outcomes.lean:87-89`), so the run is in `outcomesP`. This is real Cats Effect behaviour (`IOFiber` `onFatalFailure`; the project's own calibration `Proofs/Calibration/FatalRaise.lean` shows `fatal e` for a fatal `raiseError`). So the statement is false for v3.7.1 and also for every correct semaphore.
Counterexample (meets both hypotheses): `k := 1`, `bus := [.permit 0 (.err { code := 0, kind := .fatal })]`, `as := [.join 0]`. `AllEnded 1 [.join 0]` holds; `need = 1 ≤ 1`. The fiber runs `s.permit.use(_ => IO.raiseError(fatal))`; any schedule that runs the fiber gives `o.summary = .fatal { code := 0, kind := .fatal }`, so `∃ v, o.summary = .done (.succeeded v)` is false.
Why the smoke test did not see it: `tools/SemSmoke/Main.lean:134` uses only `.err { code := 3 }` (non-fatal).
Other checks: MIRROR yes; witness `semNoDeadlock_satisfiable` is complete; wrong functions "skip a waiter", "leak" break it.
Fix: add the hypothesis `∀ b ∈ bus, b.nonFatal` (a `Base.err e` needs `e.isNonFatal`; fatal errors shut down the runtime, `UnsafeNonFatal.scala:37-41`), or change the conclusion to "no stopped run is `blocked`, and a `Succeeded` run has `available = k + released`". Also close W1 here: let the root record the join outcomes, and claim that a use with a `.ok` base ends `Succeeded`. Add a Lean `example` for the fatal input (regression).

**`std.Semaphore.permit.atMostK`** (`:517`).
1. yes. 2. yes. "No release acts" restricts the test shape (extra releases raise the bound by design). 3. open. 4. Wrong-function: "wide" breaks it. A semaphore that never grants also satisfies it (safety); its liveness partner is `noDeadlock` (HOLLOW now; the fixed form covers it). 5. `semAtMostK_satisfiable` (two counted uses, `highest = 1 = k`). 6. Forgery: none.
Verdict: FAITHFUL as a statement.

**`std.Mutex.lock.mutualExclusion`** (`:525`).
1. yes. 2. yes (no hypothesis except `WellFormed`). 3. open. 4. "no wait" breaks it. "Always raise" satisfies it; `mutexNoDeadlock` (after fix H1) covers success, because its root ends with one more `lock.use` that must succeed. 5. `mutexMutualExclusion_satisfiable`. 6. none.
Verdict: FAITHFUL as a statement.

**`std.Mutex.lock.noDeadlock`** (`:534`). **HOLLOW (H1).**
Same cause. Counterexample: `bus := [.permit 0 (.err { code := 0, kind := .fatal })]`, `as := [.join 0]`. The hypothesis `∀ b ∈ bus, ∃ k bb, b = .permit k bb` holds with `k = 0`, `bb = .err …`. The run stops with `Summary.fatal`, not `.done (.succeeded .unit)`. Fix: as for `semNoDeadlock`.

**`std.Semaphore.count.atRest` (CE-0060)** (`:543`, `Proofs/Phase7/SemaphoreCount.lean:47`).
1. MIRROR: yes (`countK`, `modRec`, `wonK`). 2. PROPERTY: yes. **Promise check:** `S:47-53`: "Like [[available]] when permits are available but returns the number of permits callers are waiting for when there are no permits available." With `available = 0` and no live caller, the number that callers wait for is 0, so `count` must be 0 = `available`. With permits available, `count = available` directly. A canceled `acquireN` is not a caller that waits. So "`count` = `available` when every user fiber has ended" is the Scaladoc read in context (source c). 3. SETTLED: refuted. `semCountAtRest_refuted : ¬ semCountAtRest`, exactly the negation; the proof feeds `countEnded` and the kernel run `countRun` (fuel 92, default schedule) into the statement. **Public API:** yes. The input is `Semaphore[IO](0)`, two fibers `uncancelable(poll => poll(acquireN(1)) *> releaseN(1))`, cancel the second, then the first. The reproducer (`reproducers/CE-0060/Repro.scala`) uses only `Semaphore[IO](0)`, `s.acquire.start`, `count`, `available`, `cancel`; it prints `REPRODUCED CE-0060` as the last line; output recorded for v3.7.1, series/3.x and series/3.7.x (`bugs/CE-0060.yaml`).
**Fixed twin (decision 39):** `Proofs/Phase7/SemaphoreCountFixedDefs.lean` routes the `won = true` branch to an eager removal that finds the request anywhere (`waiting.find?` by gate, `filter`, `releaseN(rq - rm)`), the v3.7.0 behaviour (checked on the v3.7.0 file). When `won = true` but the request is already dequeued by a release, the twin returns unit and the `wake` branch gives the permits back (`complete` false → `releaseN(requested)`): no permit lost or doubled. `SemaphoreCountFixed.lean`: the twin meets the claim on 4 inputs × 12 schedules (`fixed_count_0..3`), v3.7.1 fails on the first (`old_count_fails`); `all_checks` is in `scripts/check_twin_checks.sh`. By reading, the twin keeps the queue free of canceled requests, so at rest the queue is empty and `count = permits = available`. Small domain (as CE-0001 in batch 3), plus the random smoke (`fixedBad`).
**`maybe_intended` is honest:** it says "Likely intended as a trade-off", quotes the PR, and says why the state is not transient without a later release. Priority `low`, kind `doc-mismatch`. Correct.
Verdict: FAITHFUL.

**`std.Semaphore.acquireN.fifo`** (`:646`).
1. yes. 2. yes. No user code, all `reqs`, `r`, schedules. The claim follows from strict FIFO (`S:58-61`) by reading: after one `releaseN(r)` the prefix with sum ≤ `r` is served, the next request takes the rest, so `count = r - sum` (also when all are served). A greedy or LIFO order blocks a join (`blocked`). 3. open. 4. "LIFO" breaks it. **"acquireN always raises" satisfies it vacuously**: the parent spins on `count` until the request is in the queue, which never happens, so no run stops (W1). 5. `semFifo_satisfiable` (`[2, 1]`, `r = 2`, result `-1`). 6. no user code.
Verdict: FAITHFUL as a statement, with W1.

**`std.Mutex.lock.semaphoreTwin`** (`:662`).
1. yes. 2. yes. **One direction: stated** in the docstring (`:659-661`: "One direction: every outcome of the mutex program is an outcome of the semaphore program") and in the registry note ("one direction"). The converse is not registered. `core` (`:655`) compares summary and user trace, not the heap (the lock state differs), so the counted `highest` is not compared; user traces still show a missing exclusion (interleaved emits). 3. open. 4. Wrong-function by reading: a mutex that always raises gives a root `Errored` that the semaphore program cannot give; a mutex without exclusion gives interleaved user traces. No Lean or smoke wrong-function check exists for this entry (advice: add one). 5. `mutexSemaphoreTwin_satisfiable`: all four hypotheses, two kernel runs with equal `core`. 6. none.
L2: the docstring says "the converse is the same claim with the roles swapped; the smoke test samples both". The converse is a different claim, and the smoke loop (`tools/SemSmoke/Main.lean:342-361`) checks only mutex ⊆ semaphore, and a miss does not count as a failure (`bad` is not increased). Fix the sentence.
Verdict: FAITHFUL as a statement.

### 1.4 W1: no `Semaphore` statement fails for "`acquireN(n)` always raises" (`n ≥ 2`)

By reading: `noLostPermit` (available unchanged), `noDeadlock` (the root does not look at join outcomes and ends `Succeeded`), `atMostK` (nobody holds), `fifo` (no run stops) all hold for an `acquireN` that raises for `n ≥ 2`. The twin catches `acquireN(1)` (through `permit`). Precedent (batches 7, 9): "always raise" alone is a weakness when a sibling statement claims success. Here no sibling does for `n ≥ 2`. Fix with H1 (success clause in `noDeadlock`).

### 1.5 Difftest (track S)

- Semaphore: 162,000 cases, seeds 61-64, 161,999 agree; Mutex: 78,000 cases, seeds 71-76, all agree; 24 fixed cases (`difftest/cases/semaphore.jsonl`) in CI (`.github/workflows/ci.yml`, both `cediff` and `drive.py check` lines). Records: `wiki/cats-effect/semaphore-mutex-model.md` (Difftest), `raw/cats-effect/2026-11-15-semaphore-mutex-track-s-notes.md`.
- The Scala side calls the real library (`difftest/.../Interp.scala:326-335`).
- **L1, the one mismatch (`g61-9094`, field `steps`):** the attribution is plausible. Review batch 9 found that `rankOrder` ranks children by `fiber id mod k`, and that ids that collide (other fibers between the children) drop some orders; a missing order can only give a false mismatch (fail-closed). This case has a `parTraverseN` over a 5-element `HashSet` whose `f` starts fibers: exactly that shape. "The same case alone agrees" supports it. But it is not shown: nobody ran the missing orders. AGENTS.md: "A mismatch is a model bug until shown otherwise", and 100% is the gate. Advice: rank by start order (not `id mod k`) in `tools/Difftest/Env.lean` `rankOrder`, rerun `g61-9094`, and record the result. Not a verdict change: the mismatch is outside the semaphore part, and the semaphore ops agree in 161,999 cases with ≥ 53,290 per op.

## 2. Track L

### 2.1 Mirror

- `Std/CountDownLatch.lean`: `apply?` (`:211`) = `State.initial(n).flatMap(state => F.ref(state).map(new …))` (`CDL:57-65`), `n < 1` → `none` (the Scala `throw` happens while the term is built). `relModify` (`:264`): `Awaiting(n, d)`, `n > 1` → `Awaiting(n-1)` + unit; else `Done` + `signal.complete(()).void`; `Done` → unit (`CDL:71-76`). `awaitSel` (`:284`): `Awaiting` → `signal.get` read at the selector step (`IODeferred.scala:71`, `get = cell.get()`, read); `Done` → unit (`CDL:78-82`). Correct.
- `Std/CyclicBarrier.lean`: `apply?` (`:219`) = `F.deferred.map(State(cap, 0, _)).flatMap(F.ref).map(…)` (`CB:65`). `modifyThunk` (`:281`): `now = a - 1`; `now == 0` → `State(cap, e + 1, gate)` + `unblock.complete(()).void`; else `State(now, e, d)` + `poll(unblock.get).onCancel(cleanup)` with the `get` snapshot of the modify step (`CB:69-85`). `flatModifyFull` = `uncancelable(poll => flatten(modify(f(poll, _))))` (`kernel/.../Ref.scala:140-141`, read). `cleanupThunk` (`:300`): same epoch → `awaiting + 1`, else unchanged (`CB:79-82`). Correct.
- Variants `v ≠ 0` are wrong functions only. The statement libraries `isLibV0` (`Props/Phase7/CountDownLatch.lean:274`, `Props/Phase7/CyclicBarrier.lean:243`) accept only variant 0. Good.

MIRROR: yes for all seven entries.

### 2.2 CountDownLatch entries

**`awaitNotEarly`** (`:329`): status 2 ⇒ `n ≤ started` in every reachable state. Quantified over `u`, `n`, user programs, `cancels`, fuel, schedules; only `AllWF`. "started" (not "completed") is right: the `n`-th `release` completes `signal` inside the call. Wrong function: variant 1, kernel (`awaitNotEarly_wrong`, `cdlAwaitNotEarly_v1_false`). Witness `awaitNotEarly_sat`. FAITHFUL as a statement.

**`noLostWakeup`** (`:336`): blocked ∧ `n ≤ started` ⇒ no status 1. In a blocked state no releaser is inside its `uncancelable` (`release` never suspends), so `n` releases ran and `signal` is complete. "Await always raises" fails it by reading: the raising awaiter keeps status 1, and a user program that waits forever makes the run blocked. Wrong function: variant 2 (`noLostWakeup_wrong`). Witness `noLostWakeup_sat` (blocked by a releaser that never ends; `nv` uses only public variant-0 closures with no captured handle). FAITHFUL as a statement.

**`releaseTotal`** (`:344`): blocked or done ⇒ `completed = started`. A fatal user error gives `Summary.fatal`, not covered by the premise, so H1 does not apply. Wrong function: variant 3. Witness `releaseTotal_sat`. FAITHFUL as a statement.

### 2.3 CyclicBarrier entries, "without cancels"

`noEarlyTrip` (`:298`) and `exactGenerations` (`:305`) fix `cancels = []`. User code holds no fiber handle, and the harness region `uncancelable(poll => mark 1 *> poll(b.await).onCancel(mark 3) *> mark 2)` holds no user code, and the preemptive scheduler has no outside cancel. So in these two statements no `await` is ever canceled. **Does this remove the interesting case?** For these two claims, no: with cancels both claims are false for every correct barrier by design (race 1 of the track L notes: a released waiter canceled before it runs counts for the trip and ends status 3, so `passed % cap ≠ 0` and `passed` can be below a full generation). **Is the cancel case covered elsewhere?** Yes: liveness with any cancels at any point by `cancelNoHang` (group A unbounded), and safety (a canceled `await` leaves the count) by `cancelRemoved`. Residual gap (documented, not a defect): safety with cancels concurrent with a trip is not claimed, because Scala allows a canceled waiter to count for a trip.

**`noEarlyTrip`**: `passed ≤ cap * (entered / cap)`. True by reading (each trip uses `cap` decrements by fibers with status ≥ 1). Variant 1 breaks it (kernel). A barrier that never trips satisfies it; `exactGenerations` and `cancelNoHang` catch that. FAITHFUL as a statement.

**`exactGenerations`**: blocked ⇒ `cap ∣ passed` ∧ `waiting < cap`. Variant 4 breaks it (kernel). "Await always raises" fails it by reading when ≥ `cap` raising awaiters keep status 1 and a user program blocks the run (for example an own barrier of capacity 2 with one `await`). FAITHFUL as a statement.

**`cancelNoHang`** (`:312`): any cancels, blocked ⇒ `waiting < cap`. **The epoch-check race:** read in `Std/CyclicBarrier.lean:300` and `CB:79-82`. Race 2 (canceled while suspended, finalizer in a later task, another fiber trips first): v3.7.1 sees the new epoch and does nothing; without the check the next generation needs `cap + 1`. `cancelNoHang_wrong` and `cbCancelNoHang_v3_false` (variant 3, schedule `race`, kernel) show the hang; `cancelNoHang_v0_race` shows v3.7.1 ends `Succeeded` on the same schedule. The analysis is correct. FAITHFUL as a statement.

### 2.4 `cancelRemoved` and its extra hypothesis `as.length < cap`

Statement (`:318`): `passed ≤ cap * ((entered - canceledIn) / cap)`.
- The hypothesis is not a Cats Effect precondition; it shapes the test program. It is needed: with `as.length ≥ cap`, race 1 gives a status-3 waiter that counted for a trip, so the bound is false for every correct barrier. The docstring says this (`Props/Phase7/CyclicBarrier.lean`, "Why the hypothesis of statement 4").
- It does **not** remove the interesting case. With fewer than `cap` group A fibers no trip happens before group B starts, and group B starts after every cancel returned (`cancelThenB`). So every canceled waiter that decremented the count must be re-incremented, or group B trips early. Variant 2 (no re-increment) breaks it on a satisfying input (`cancelRemoved_wrong`, `[p].length < 2`).
- A slow group A user program can still enter after group B started; such a fiber is not canceled (cancels finished), so the bound still holds by reading.
- Witness `cancelRemoved_sat` meets `AllWF` and the hypothesis together.
Verdict: FAITHFUL as a statement.

### 2.5 Difftest (track L)

135,000 cases, seeds 71-73, all agree, per op ≥ 56,600; 54 fixed cases `difftest/cases/latch.jsonl` in CI; 7 of 7 mutants killed (`raw/cats-effect/2026-11-15-track-l-latch-barrier-notes.md`). The Scala side calls the real `CountDownLatch[IO]`/`CyclicBarrier[IO]` (`Interp.scala`, the hunk moved by `1e84acb`). L3 below.

## 3. Forgery (the Phase 6 class)

I looked for the six Phase 6 patterns: data numbers used as names, a closure field that hides a handle, a public harness closure that reaches a marker, a decoder that turns data into a table lookup, an env fallback that gives library ids to user code, runtime numbers as ids.

- **Harness cells.** S: the counter is `Ref 0`, the first allocation (`lockRoot`); L: `Ref 0..2` (CDL) and `Ref 0` (CB). User code gets no `.ref` to them. `Val.handles (.fn i) = [.fn i]` is shallow (`Model/WellFormed.lean:108`), and `availD` (`:155-160`) makes an odd reference available only if held. So a user that holds a lock object (`semV q`, `mutexV q`, a latch, a barrier) cannot name a closure that captured the state cell.
- **Harness closures that write by number.** `HLam.mark j s` writes `Ref 2` / `Ref 0`, `HLam.incr c` takes a data number `c` (`Props/Phase7/CountDownLatch.lean:138`, `:248-253`). These are table lookups by data. They are safe only because no `HLam` is in `cdlLib`/`cbLib` (`isLibV0` accepts only `CLam`/`BLam` of variant 0). Keep it so; a later "make the harness closure public" change would open a forgery.
- **Public harness closures in track S.** `HS.newCell` and `HS.afterCell` are public (`Props/Phase7/Semaphore.lean:377`). `afterCell` builds a nested harness with its **own** new counter cell (id = heap length > 0) and its own lock; its fields are data (`Lock`, `Use`, `Act`) and `.fn g` references that must be available. `fiberAt fs i` indexes only the nested harness's own fibers. No path to `Ref 0`.
- **Dispatcher depth.** `Mutex.dispatch` uses `go u 8` and gives any id to `u.callV` at depth 0 (`Model/Mutex.lean:301` and `go`). `Bracket.isLib` accepts only `good` closures, which call `uc` only on even ids or leaves; `SL`/`ML` public operations return programs; `useOut` is not public. So user code cannot build a chain of synchronous library calls deeper than 2. No library id reaches `u`.
- **Mirror closures in `cdlLib`/`cbLib`.** All variant-0 `CLam`/`BLam` are nameable if their captured handles are available. `mkLatch 0`/`mkBarrier` on an own `Ref`, `newRef`, `flattenK` with an own `Deferred` give only own objects. Effect codes carry `.ref`, `.deferred`, `.poll` handles, so they need held handles.

Result: no forgery found.

## 4. Gates and cases

- `git show 12df25f` and `f365f4b`: in `difftest/py/selftest.py`, `.github/workflows/ci.yml`, `lakefile.lean`, `scripts/check_twin_checks.sh` every removed line is replaced by a longer list (new case files, new modules, new coverage minimums `V2S_MIN = 0.01`, `V2L_MIN = 0.015`). No case file deleted; no minimum lowered; `check_forbidden.py` not touched.
- `1e84acb` moves misplaced merge hunks in `difftest/py/gen.py` (two stray lines in `WEIGHTS`/`CONFIG`) and `Interp.scala` (the latch cases were inside the queue-kind match). It deletes no case.
- **L3:** no record shows a difftest run of the track S and L ops on the merged tree after `1e84acb` (`wiki/log.md`, both raw notes). The 162,000 / 78,000 / 135,000 runs were on the track branches. Advice: rerun a short depth run (for example 5,000 cases per seed, three seeds, boosts as before) on `main` and record it.

## 5. Low items

- L1: section 1.5. L2: section 1.3 (twin). L3: section 4.
- L4: citation drift. `docs/std/mutex.md:7-8` → the sentence is at `:6-7`. `S:38-53` covers two Scaladocs (`available` `:38-45`, `count` `:47-53`); fine. The `cbCancelRemoved` registry note says "after every cancel returned" for group B; correct.

## 6. Q5 (my view)

Keep CE-0060 as a low-priority `doc-mismatch` record with `maybe_intended: likely`, as the default says. Reasons:

1. The contract that a user reads is the Scaladoc. A trade-off that only a PR description names is not documentation. `S:47-53` still promises "the number of permits callers are waiting for".
2. The PR says "transiently". The state is not transient without a later release; with `Semaphore(0)` there may be no later release. So even the PR text does not describe the behaviour exactly.
3. AGENTS.md "known deliberate behavior is not a bug" applies to behaviour recorded in `wiki/cats-effect/semantics.md`. CE-0060 is not there; after the user answers, record the answer there.
4. The record is already honest: no lost permit, `count` only, the fix can be a Scaladoc change.

Suggestion for the user decision: keep a class "deliberate trade-off, documented only in a PR" as `doc-mismatch`, priority low, never higher.

## 7. What must change

1. H1: fix `semNoDeadlock` and `mutexNoDeadlock` (non-fatal hypothesis or "not blocked" conclusion) and add the success clause for W1. Re-review both.
2. L2: fix the twin docstring sentence; add a twin wrong-function check.
3. L1, L3: rerun and record.

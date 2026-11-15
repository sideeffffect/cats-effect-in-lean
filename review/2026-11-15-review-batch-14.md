# Review batch 14 (2026-11-15): batch 7.1 fixes after batch 13, and the Phase 7 batch 7.1 gate

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the battery files, the witnesses, the inventory, the bug record, the Scala source at `v3.7.1` and the raw notes. It did not run a build, Lean, a test, sbt or a difftest. It ran one read-only `gh run list` (CI status only).
Reviewed commit: `8325ca2` (`origin/main`), checked out as branch `review14`. Diff base: `5a360df` (the commit of batch 13; batch 13 reviewed `05eecbb`).
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 58, 63, the battery rules (a)-(c) of batch 13, "Reviewer evidence", review log); `raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md`. When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `raw/`, `wiki/`, `inventory/`, `review/`, `bugs/`, `reproducers/` or `test/`. `Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala`, `S` = `.../std/Semaphore.scala`, both at `v3.7.1`.

## Summary

| Registry entry | Status | Change | Verdict |
|---|---|---|---|
| `std.Queue.Synchronous.tryHandoff` | open | new (replaces `tryTakeHandoff`) | FAITHFUL as a statement |
| `std.Queue.{Concurrent,Async}.seqSpec` | open | battery on all classes, factory rows | FAITHFUL as statements (unchanged text) |
| other 11 queue entries | open | none in `Props` | FAITHFUL (unchanged) |
| `std.Semaphore.acquireN.fifo` | open | root reads `(available, count)` while requests wait | FAITHFUL as a statement (stronger; expected values right) |
| other 6 Semaphore/Mutex open entries, CE-0060 | open / refuted | factory and contended rows only | FAITHFUL (unchanged) |
| `std.CountDownLatch.awaitCompletes` | open | restated (H4 fix) | FAITHFUL as a statement (H4 closed) |
| `std.CyclicBarrier.awaitCompletes` | open | restated (H4 fix) | FAITHFUL as a statement (H4 closed) |
| `std.CountDownLatch.noDeadlock` | open | new | FAITHFUL as a statement |
| `std.CyclicBarrier.noDeadlock` | open | new | FAITHFUL as a statement |
| other 7 latch entries | open | mirror variants 9-12 only (`v ≠ 0`) | FAITHFUL (meaning unchanged) |

New gap (blocker for the gate):

- G2 (Semaphore battery, rule (a) of batch 13): the "drops" rows of `tryAcquire` and `tryAcquireN` use the dishonest drop (`true` with no effect, `Proofs/Phase7/SemaphoreBatteryDefs.lean:257-260`). The honest drop (answers `false`, no effect) breaks no registered Semaphore or Mutex statement. Term in B.3. By decision 63 item 4, the Semaphore battery is incomplete.

Gate (section D): **FAIL**, one blocker (G2). All 33 batch 7.1 entries are FAITHFUL as statements. The Queue, Mutex and latch batteries are complete (Queue with one low condition). CE-0060 has a complete bug record. Q5: the default stands.

---

## A. Queue (track Q)

### A.1 What I read

- `Props/Phase7/Queue.lean` diff `5a360df..8325ca2` in full (only statement 8 is new, `:583-619`).
- `Proofs/Phase7/QueueBatterySync.lean`, `QueueBatteryDefs.lean`, `QueueWitness.lean` diffs in full; `QueueBatteryDefs.lean:55-130` (variants, `battery`, `inputOf`, `runOp`).
- `Proofs/Phase7/QueueBatteryFactory.lean` in full; `QueueBatteryConcOther.lean:1-40` and the theorem count of each battery file.
- `Registry.lean:812-846`; `inventory/inventory.csv` diff.
- `Q:139-150` (`synchronous`), `Q:246-360` (`Synchronous` `offer`, `tryOffer`, `take`, `tryTake`, `size`).
- `raw/cats-effect/2026-11-15-queue-sync-trytake-handoff.md`, `raw/cats-effect/2026-11-15-queue-review13-battery.md`.

### A.2 New entry `std.Queue.Synchronous.tryHandoff` (`syncHandoff`, `Props/Phase7/Queue.lean:611`)

Statement: for every element `x` and every fuel, (a) a stopped run of `handoffRoot x` (`:605`: `synchronous`, fiber 0 `offer x`, fiber 1 `tryTake`, join `[0, 1]`) with the FIFO replay schedule (`PChoice` list `[]`) has `tryTook Some(x)`, both joins `Succeeded`, root `Succeeded(())`; (b) the same for `handoffOfferRoot x` (`:608`: fiber 0 `take`, fiber 1 `tryOffer x`) with `tryOffered (x, true)`, `took x` by fiber 0, both joins `Succeeded`, root `Succeeded(())`.

1. MIRROR: yes. Same harness (`rootIO`) and the same `Synchronous` mirror as `noLoss`/`seqSpec`. The v3.7.1 code (`Q:347-353`): with an offerer in `offerers`, `tryTake` dequeues it, completes its latch with `true` and returns `Some(value)`. `Q:274-290`: with a taker in `takers`, `tryOffer` completes the taker's latch with `(a, latch)` and returns `poll(latch.get)`; the taker answers `true` (`Q:336-338`). The model events of the witness match this (`Proofs/Phase7/QueueWitness.lean:245-248`: `offerStart 1`, `tryTook Some 1`, `offered 1`, two `Succeeded` joins; `took 1`, `tryOffered (1, true)`, two `Succeeded` joins).
2. PROPERTY: yes.
   - Promise: Scaladoc `Q:139-148` ("a single element can pass ... when there are at least one taking fiber and at least one offering fiber ... both fibers are freed"), `tryTake` "if one is available without fiber blocking", `tryOffer` "without semantically blocking" (quoted in the docstring `:585-601`).
   - **Is the FIFO replay schedule a fair, documented reading?** Yes. Over all schedules the claim cannot be observed: `tryTake` before the offerer registers correctly answers `None`, and the harness has no public way to see the registration (`Synchronous#size` is always `0`, `Q:359`). The fixed schedule is a choice of test input that selects the interesting case (partner registered first). It is not a hypothesis that removes a failure. The witness shows that on this schedule fiber 0 is registered before fiber 1 runs (`tryTook Some 1`).
   - **Does it hide a real hand-off failure on other schedules?** Not for this input, by reading. The input has no cancel. The state is one `Ref`; once the partner is in `offerers` (`takers`), the `try` operation sees it on every schedule (`flatModify`, `Q:274`, `:349`). The only other order is "`try` runs first", where `None`/`false` is correct. The remaining schedule-dependent risk is a hand-off that races with a cancel (the taker's `failCommit`, `Q:327-330`; the offerer's `cleanupF`, `Q:262-266`). No hand-off claim covers it, but `noLoss` and `noDup` cover it on all schedules with cancel plans (`synchronous ∈ ConcKeep`, batch 13 A.5). Low note N1.
   - Strength: one partner, one element, one schedule. The claim is complete for that input (answer, element, both joins, root). Accepted as the decision-63 hand-off row; it is not a linearizability statement.
3. SETTLED: open.
4. Wrong functions (kernel, `Proofs/Phase7/QueueBatterySync.lean`): `sync_tryTake_drops` (`:96`), `sync_tryOffer_false_breaks` (`:117`, the review-13 term `wSyncTryOfferFalse`, `:108`), `sync_tryOffer_drops_handoff` (`:119`); mirror `sync_tryTake_handoff_mirror` (`:94`), `sync_tryOffer_handoff_mirror` (`:115`). By reading also: a `tryTake` that answers `Some(x)` but does not free the offerer (fiber 0 never joins: run `blocked`), and one that answers another element.
   - Bool form vs Prop: `handoffB`/`handoffOfferB` (`:89-93`, `:100-105`) use `contains` and `==` for the `∈` and `=` of `syncHandoff`, element `1`, fuel 3000, schedule `[]`: one run of the statement. Checked by reading (same pattern as batch 13 A.2).
5. Decision 53: `syncHandoff_satisfiable` (`Proofs/Phase7/QueueWitness.lean:259`), both parts, from `handoffRun_ok`/`handoffOfferRun_ok` (`:250`, `:254`, kernel). No hypothesis besides the input. Complete.
6. Forgery: no user code; elements are data (batch 13 A.3).

Verdict: FAITHFUL as a statement. G1 of batch 13 is closed (`tryTake` drops and the honest `tryOffer` drop both break statement 8).

### A.3 Battery (Queue)

- Classes (L1 of batch 13 closed): `QueueBatteryConcOther.lean` (`droppingConc 2`, `circular 2`) and `QueueBatteryAsyncOther.lean` (`unbounded`, `dropping 2`) have 46 theorems each: 2 classes × (5 mirrors + 18 rows). With `QueueBatteryConc`/`QueueBatteryAsync` (23 each) every queue class has its own rows. Each row: `specOK (battery op var) k op = some false`, kernel, against `SeqSpec`; the mirror meets it on the same input.
- Factories (L2 closed): `QueueBatteryFactory.lean`, 7 kinds × (mirror, raises, hangs), kernel. `rootWith fac` replaces the factory term; `rootWith_newIO` (`QueueBatteryDefs.lean:145`) is `rfl`, so the mirror row is the real root. Factory drops/doubles: meaningless (no effect on an existing queue; reason in `QueueBatteryDefs.lean:133-137`). `mapK`, `tryTakeN`, `tryOfferN`, `unsafeBounded`, `unsafeUnbounded` are `todo` (not modelled) in the inventory, so they have no row.
- `Synchronous`: every cell kernel-checked (table in `raw/cats-effect/2026-11-15-queue-review13-battery.md`).
- **Rule (a) on the other six classes (low, condition C1).** `wrongIO .drops .tryOffer` is still `pure true` (`QueueBatteryDefs.lean:68`), the dishonest drop. Rule (a) asks for the honest drop (`false`, no effect). On the input `[tryOffer 1, size]` with capacity 2 the spec answer is `true` (room in the queue), so `SeqSpec` rejects `false` at the first event. I am sure of this by reading, but it is not kernel-checked. `tryTake` drops is already honest (`pure none`).

Verdicts: `std.Queue.Concurrent.seqSpec`, `std.Queue.Async.seqSpec` FAITHFUL (unchanged). The other 11 queue entries: no change in `Props`; verdicts of batches 11a-13 stand.

## B. Semaphore and Mutex (track S)

### B.1 What I read

- `Props/Phase7/Semaphore.lean` diff in full; `:30-60`, `:320-336`, `:485-560`, `:586-590`, `:677-718` at `8325ca2`.
- `Proofs/Phase7/SemaphoreBattery.lean` and `SemaphoreBatteryDefs.lean` diffs in full; `SemaphoreBatteryDefs.lean:250-265`; `SemaphoreBattery.lean:113-136`; `SemaphoreWitness.lean:287-291`; `SemaphoreCount.lean:30-58`.
- `S:36-98`, `S:179-265`, `S:268-277`.
- `Registry.lean:646-745`; `inventory/inventory.csv` Semaphore, Mutex, LockQueue rows.
- `bugs/CE-0060.yaml`; `reproducers/CE-0060/Repro.scala` (grep of the last line); `QUESTIONS.md`.
- `raw/cats-effect/2026-11-15-semaphore-mutex-review13.md`.

### B.2 `std.Semaphore.acquireN.fifo` (`semFifo`, `Props/Phase7/Semaphore.lean:715`)

The statement text did not change: every run of `fifoRoot reqs r` ends `Succeeded(r - Σ reqs)`. The root changed: the spin read is now `fifoRead` (`available`, then `count`), and `FL.check` (`:686-691`) goes on at `(0, -target)`, spins at `(0, -prev)`, and otherwise ends the root with `Succeeded(Left((a, c)))`.

1. **Did the meaning change?** Yes, it got stronger, and it stays true for v3.7.1 by reading.
   - Before: the spin waited for `count = -target` and ignored every other value. Now it also claims every spin value.
   - While the root spins, no permit was released (`Semaphore(0)`, `releaseN(r)` comes after the last spin). `available` is `state.permits` (`S:256`), and `acquireN` sets `permits` to `0` whenever it enqueues (`S:196-201`). So `available = 0`.
   - `count` is `-waiting.foldMap(_.remaining)` when `waiting` is not empty, else `permits` (`S:258-263`). Only `F_i` can change the state during the spin (the earlier requests wait). So `count` is `-prev` before `F_i` enqueues and `-target` after. With `n_i = 0`, `acquireN` is `F.unit` (`S:182`) and `target = prev`; the first branch matches.
   - The two reads are separate `state.get`s. Between them `F_i` can enqueue; the pair is then `(0, -target)` or `(0, -prev)`, both allowed.
   - A `Left` result can only come from a wrong read. The claim (`Succeeded (.int …)`) rejects `Left`.
2. **Is the expected count right, given PR #4648 and CE-0060?** Yes. No waiter is canceled in `fifoRoot`, so `cleanup`/`reclaim` (`S:168-177`, `:188-191`) never run and CE-0060 cannot occur. After `releaseN(r)`, `fulfil` (`S:212-225`) serves the queue in order and partly fills the first request it cannot serve. So `count = r - Σ reqs`: if `r ≥ Σ`, `waiting` is empty and `count = permits = r - Σ`; else `count = -(remaining of the rest) = r - Σ`. The final read is after the joins of the served prefix.
3. MIRROR: yes (harness change only; `fifoRead` is the Scala `s.available.flatMap(a => s.count.map(c => (a, c)))`).
4. SETTLED: open.
5. Wrong functions: `available_contended` (`SemaphoreBattery.lean:256`), `count_contended` (`:262`), kernel; `good_fifo_contended` (`:266`) on the same inputs; `contended_ok_at_rest` (`:273`) shows that only reads under contention catch them. O1 of batch 13 is closed.
6. Decision 53: `semFifo_satisfiable` (`SemaphoreWitness.lean:287`, `[2, 1]`, `r = 2`, from the kernel run `run7_ok`). Complete.

Verdict: FAITHFUL as a statement.

### B.3 Battery (Semaphore, Mutex) and G2

- Factory rows (L3 closed): `semApply_raises`/`_hangs` (`SemaphoreBattery.lean:239`, `:242`) break statement 2; `mutexApply_raises`/`_hangs` (`:247`, `:250`) break statement 5; kernel. The wrong factory replaces the library term `F.ref(...).map(...)` (`SemaphoreBatteryDefs.lean`, `repl`, `.semApply`/`.mutexApply`). Drops/doubles: meaningless, reason in the table note. `mapK`, `in`: not mirrored, reason given; both are `todo` in the inventory.
- Other rows: unchanged from batch 13 (38 rows).

**G2 (blocker).** Rule (a) of batch 13: for a try-operation the "drops" variant is the honest one. The `tryAcquire`/`tryAcquireN` "drops" rows (`SemaphoreBattery.lean:119`, `:134`) use `badOf var (tryAcquireNIO l n) (.pure (.bool true)) …` (`SemaphoreBatteryDefs.lean:257-260`): `true` without taking. The harness then releases a permit it never took, so `available = k + 1`, and statement 2 breaks. The honest drop answers `false`:

```lean
-- SemaphoreBatteryDefs.lean:257-260 with the honest drop (read only, not run)
    | some (.tryBody l n) =>
      if (op == .tryAcquire && n == 1) || (op == .tryAcquireN && 2 ≤ n) then
        { out := .prog (.flatMap (.pure (.bool false)) (HS.ifRel l n).fn) }
      else r'
```

On the input of the row (`k = 2`, `[.tryRel 1]`, `[.join 0]`): `HS.ifRel l n` on `false` is `pure ()` (`Props/Phase7/Semaphore.lean:329-332`). The fiber ends `Succeeded(())`, the join record is `Succeeded(())`, `available = 2 = k + released`. So `c2` is `true`. In general:

- Statement 2 (`:545`): `OkJoined` needs `∃ x, joinRecV i (.ocSucceeded x)` for any `x`; `tryRel` gives `()` in both branches; no permit moves. Met.
- Statement 1 (`noLostPermit`): reads only `available`. Met. User code cannot reach the harness semaphore (`:47-51`).
- Statements 3, 4, 5, 6 (CE-0060, refuted), 7, 8: no `tryRel`, no `tryAcquire*` in the harness; user code that calls `tryAcquireN` on its own semaphore gets the same wrong answer on both sides of the twin (statement 8).
- v3.7.1 answers `true` when `permits ≥ n` (`S:268-276`); the Scaladoc says "Acquires `n` permits now and returns `true`, or returns `false` immediately" (`S:77-84`). So "always `false`" is wrong and nothing rejects it.

This is the Semaphore form of G1 (batch 13). By decision 63 item 4 a missing row is a HOLLOW reason for the structure's entries. I follow the batch 13 precedent for G1: the entries stay FAITHFUL as statements (no entry claims that `tryAcquireN` succeeds; their own claims are right), and the structure's battery is **incomplete**. The gate cannot pass until G2 is closed.

Fix (suggestion): a sequential statement for `Semaphore` like the queue `SeqSpec` (one fiber, a script of `tryAcquireN`, `acquireN` (when it can be met), `releaseN`, `available`, `count`; the recorded answers and the final pair equal a spec), or a one-fiber root whose `tryRel` returns `b` with the claim `Succeeded(true)` for `n ≤ k`. Then add the honest rows (`tryAcquire`, `tryAcquireN`) with kernel breaks and `good_*` runs.

### B.4 Other track S entries

`noLostPermit`, `noDeadlock`, `atMostK`, `mutualExclusion`, `mutex noDeadlock`, `count.atRest` (CE-0060), `semaphoreTwin`: no change in `Props` other than the FIFO root (diff). Verdicts of batches 11b-13 stand.

## C. Latches (track L)

### C.1 What I read

- `Props/Phase7/CountDownLatch.lean` diff in full; `:20-64`, `:236-275`, `:329-400`.
- `Props/Phase7/CyclicBarrier.lean` diff in full.
- `Std/CountDownLatch.lean` and `Std/CyclicBarrier.lean` diffs in full (`apply?`, `:224`, `:231`).
- `Proofs/Phase7/LatchBattery.lean` diff in full.
- `Model/Run.lean:47-56` (`Summary`).
- `Registry.lean:747-890`; inventory latch rows.
- `raw/cats-effect/2026-11-15-track-l-review13-fix.md`.

### C.2 Mirror for `v = 0`

Unchanged. `apply?` (`Std/CountDownLatch.lean:224`) tests `n < 1 || v == 11`, then `v == 12`, then the old term; for `v = 0` it is the old `if n < 1 then none else …`. `Std/CyclicBarrier.lean:231` the same with `9`, `10`. Variant 12 uses `newDeferred`, `awaitingK 1`, `awaitSel`; variant 10 uses `BLam.neverK`, which is not in `cbLib` (`neverK_not_public`, batch 13 C.2). The earlier statements mean the same.

### C.3 `std.CountDownLatch.awaitCompletes` (`Props/Phase7/CountDownLatch.lean:365`), `std.CyclicBarrier.awaitCompletes` (`Props/Phase7/CyclicBarrier.lean:340`)

New form: `AllWF → 1 ≤ n → halt = some (.done oc) → oc = .succeeded .unit ∧ ∀ j, status j ≠ 1` (barrier: `1 ≤ cap`, `waiting = 0`).

1. MIRROR: yes (same harness).
2. PROPERTY: yes.
   - `1 ≤ n` / `1 ≤ cap` is the documented precondition of `apply` (`n < 1` throws `IllegalArgumentException`, cited in `apply?`'s docstring `CDL:57-60`, `CB:59-61`).
   - True for v3.7.1 by reading: the root (`prog`, `:272`; `HLam.call`, `:239-268`) allocates cells, builds the latch, starts fibers, cancels awaiters, joins all, returns `()`. `cancel` and `join` do not raise; the root ignores the join outcomes. A fatal error gives `Summary.fatal`, not `done` (`Model/Run.lean:47-51`). User programs hold no handle (`:46-53`). So a done root is `Succeeded(())`.
   - H4 closed: a raising `apply` makes the root `done (errored iaeErr)`, which the first conjunct rejects.
   - The second conjunct is the batch 13 claim ("`await` never fails"); unchanged.
3. SETTLED: open.
4. Wrong functions (kernel, against the full statement, `¬ XV v`): `CDL.await_raises_breaks`, `CDL.apply_raises_breaks` (`LatchBattery.lean:128`: root `Errored(iaeErr)`, `cases` on `.errored = .succeeded`), `CB.await_raises_breaks`, `CB.apply_raises_breaks` (`:242`).
5. Decision 53: `CDL.awaitCompletes_sat` (`:159`), `CB.awaitCompletes_sat` (`:280`): `1 ≤ n` proved, root done `Succeeded(())`, awaiter returned. Complete.

Verdicts: both FAITHFUL as statements (H4 closed).

### C.4 `std.CountDownLatch.noDeadlock` (`:373`), `std.CyclicBarrier.noDeadlock` (`Props/Phase7/CyclicBarrier.lean:348`)

`cdlNoDeadlock`: `k` awaiters and `m` releasers, all user programs `IO.pure(())`, `1 ≤ n ≤ m`, any `cancels` (awaiter indices), all schedules and fuel: `halt ≠ some .blocked`. `cbNoDeadlock`: `cap * g` awaiters with `IO.pure(())`, no group B, no cancels, `1 ≤ cap`: `halt ≠ some .blocked`.

1. MIRROR: yes (same harnesses, `run`).
2. PROPERTY: yes. **Are the hypotheses documented preconditions or a narrowing that hides the interesting case?**
   - "At least `n` releasers" (CDL) and "`cap * g` awaiters" (CB) are the conditions under which the Scaladoc promises that `await` returns (`CDL` Scaladoc quoted at `:20-27`: `await` blocks until the count reaches 0; `CB`: each trip needs `cap` fibers). They are the promise's own condition, not an extra assumption.
   - "User programs only return `()`": a user program that never returns, or a releaser that cancels itself, blocks the run for a correct latch. So some restriction is needed for a "never blocked" claim. The restriction removes only user-side behaviour. A user error is absorbed by `.attempt` (`:38-41`), so it adds nothing for the latch. User programs hold no latch handle (`:46-49`), so they cannot call latch operations on the harness latch. The latch's own interesting cases stay in the domain: CDL keeps any cancels of awaiters at any point (cancels target awaiters only, `:43`), `m > n` (releases after `Done`), and every schedule.
   - CB "no cancels": a cancel can legitimately leave a generation short, so "never blocked" is false with cancels. The cancel case is covered by `cbCancelNoHang` (a blocked run has fewer than `cap` fibers in `await`) and `cbCancelRemoved`. Accepted.
   - True for v3.7.1 by reading: CDL `release` is masked in the harness (`relUnc`), so `n` releases happen; the `n`-th completes the signal and every waiting `await` returns or was canceled. CB with `cap * g` awaiters and no cancels: every `cap`-th arrival trips.
   - Wrong-function test on the entry alone: "`await` returns at once" passes it; `awaitNotEarly`/`noEarlyTrip` catch that (sibling precedent).
3. SETTLED: open.
4. Wrong functions: `CDL.apply_hangs_breaks` (`LatchBattery.lean:136`), `CB.apply_hangs_breaks` (`:250`), kernel. `release`/`await` hangs are kernel-checked against other statements (batch 13 C.4); smoke only for `noDeadlock` (raw note).
5. Decision 53: `CDL.noDeadlock_sat` (`:166`), `CB.noDeadlock_sat` (`:286`): hypotheses hold; the awaiter waits and is released; root done. Complete.

Verdicts: both FAITHFUL as statements.

### C.5 Battery and L4

- Apply rows: raises (CDL v11, CB v9), hangs (v12, v10), kernel (C.3, C.4). Drops/doubles meaningless with a reason (`Std/CountDownLatch.lean` docstring, `LatchBattery.lean` table): the only effect of the factory is the allocation. Accepted.
- L4 closed: `v0_n1`, `v0_n2`, `v0_noRelease` (`LatchBattery.lean:174-187`), `v0_cap1`, `v0_cap2` (`:294-302`), kernel, on every battery input. On each, the conclusion of the broken statement holds for the v3.7.1 mirror (for example `n = 2`, fuel 48: status 1, not 2; `cap = 2`: blocked with `waiting = 1 < 2`).

The latch battery is complete: `release` × 4, `await` × 3 (+ doubles meaningless), `apply` × 2 (+ 2 meaningless), `mapK` not mirrored (reason, `todo` in the inventory).

## D. Gate: Phase 7 batch 7.1

### D.1 Verdict table (all 33 entries)

| # | Entry | Status | Latest verdict | Batch |
|---|---|---|---|---|
| 1 | `std.Queue.Concurrent.noLoss` | open | FAITHFUL (statement) | 11a; meaning re-checked 12, 13, 14 |
| 2 | `std.Queue.Async.noLoss` | open | FAITHFUL (statement) | 11a; 12, 13, 14 |
| 3 | `std.Queue.Concurrent.noDup` | open | FAITHFUL (statement) | 11a; 12, 13, 14 |
| 4 | `std.Queue.Async.noDup` | open | FAITHFUL (statement) | 11a; 12, 13, 14 |
| 5 | `std.Queue.Concurrent.fifo` | open | FAITHFUL (statement) | 12; 13, 14 |
| 6 | `std.Queue.Async.fifo` | open | FAITHFUL (statement) | 12; 13, 14 |
| 7 | `std.Queue.Concurrent.noDeadlock` | open | FAITHFUL (statement) | 11a; 12, 13, 14 |
| 8 | `std.Queue.Async.noDeadlock` | open | FAITHFUL (statement) | 11a; 12, 13, 14 |
| 9 | `std.Queue.Concurrent.takerLiveness` | open | FAITHFUL (statement) | 13; 14 |
| 10 | `std.Queue.Async.takerLiveness` | open | FAITHFUL (statement) | 13; 14 |
| 11 | `std.Queue.twinSeq` | open | FAITHFUL (statement, low strength) | 11a; 13, 14 |
| 12 | `std.Queue.Concurrent.seqSpec` | open | FAITHFUL (statement) | 13; 14 |
| 13 | `std.Queue.Async.seqSpec` | open | FAITHFUL (statement) | 13; 14 |
| 14 | `std.Queue.Synchronous.tryHandoff` | open | FAITHFUL (statement) | 14 |
| 15 | `std.Semaphore.noLostPermit` | open | FAITHFUL (statement) | 11b; 12, 13, 14 |
| 16 | `std.Semaphore.noDeadlock` | open | FAITHFUL (statement) | 13; 14 |
| 17 | `std.Semaphore.permit.atMostK` | open | FAITHFUL (statement) | 11b; 12, 13, 14 |
| 18 | `std.Mutex.lock.mutualExclusion` | open | FAITHFUL (statement) | 11b; 12, 13, 14 |
| 19 | `std.Mutex.lock.noDeadlock` | open | FAITHFUL (statement) | 13; 14 |
| 20 | `std.Semaphore.count.atRest` (CE-0060) | refuted | FAITHFUL | 11b; 14 (record) |
| 21 | `std.Semaphore.acquireN.fifo` | open | FAITHFUL (statement) | 14 |
| 22 | `std.Mutex.lock.semaphoreTwin` | open | FAITHFUL (statement) | 11b; 12, 13, 14 |
| 23 | `std.CountDownLatch.awaitNotEarly` | open | FAITHFUL (statement) | 11b; 13, 14 |
| 24 | `std.CountDownLatch.noLostWakeup` | open | FAITHFUL (statement) | 11b; 13, 14 |
| 25 | `std.CountDownLatch.releaseTotal` | open | FAITHFUL (statement) | 11b; 13, 14 |
| 26 | `std.CountDownLatch.awaitCompletes` | open | FAITHFUL (statement) | 14 (HOLLOW in 13) |
| 27 | `std.CountDownLatch.noDeadlock` | open | FAITHFUL (statement) | 14 |
| 28 | `std.CyclicBarrier.noEarlyTrip` | open | FAITHFUL (statement) | 11b; 13, 14 |
| 29 | `std.CyclicBarrier.exactGenerations` | open | FAITHFUL (statement) | 11b; 13, 14 |
| 30 | `std.CyclicBarrier.cancelNoHang` | open | FAITHFUL (statement) | 11b; 13, 14 |
| 31 | `std.CyclicBarrier.cancelRemoved` | open | FAITHFUL (statement) | 11b; 13, 14 |
| 32 | `std.CyclicBarrier.awaitCompletes` | open | FAITHFUL (statement) | 14 (HOLLOW in 13) |
| 33 | `std.CyclicBarrier.noDeadlock` | open | FAITHFUL (statement) | 14 |

The registry has exactly these 33 Phase 7 entries (`Registry.lean:500-890`). `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement` (`:137`, CE-0003) is a Phase 5 calibration entry, not batch 7.1.

### D.2 Battery tables (decision 63)

| Structure | Rows | Complete? |
|---|---|---|
| Queue (7 classes + `Synchronous`, 7 factory kinds) | every op × {R, H, D, 2} kernel; `size` D/2 and factory D/2 meaningless with reason; G1 closed | yes, condition C1 (honest `tryOffer` drop not kernel-checked on 6 classes; `SeqSpec` rejects it by reading) |
| Semaphore | 9 ops × 4 + 2 factory + reads (`wrongValue`, `contended`) | **no**: G2 (honest `tryAcquire`/`tryAcquireN` drop breaks nothing) |
| Mutex | `lock` × 4, `apply` × 2 (+ 2 meaningless) | yes |
| CountDownLatch | `release` × 4, `await` × 3 (+1 meaningless), `apply` × 2 (+2 meaningless), `mapK` reason | yes |
| CyclicBarrier | `await` × 4, `apply` × 2 (+2 meaningless), `mapK` reason | yes |

### D.3 Refuted entry CE-0060

- `semCountAtRest_refuted : ¬ semCountAtRest` (`Proofs/Phase7/SemaphoreCount.lean:47`): the theorem type is the negation of the registered property (`Props/Phase7/Semaphore.lean:586`); kernel run `countRun` (`:34`).
- Bug record `bugs/CE-0060.yaml`: all required fields. `output` has v3.7.1, series/3.x (`de84c01`) and series/3.7.x, each ending `REPRODUCED CE-0060`. The reproducer prints `REPRODUCED CE-0060` as its last line only when program A shows the state in every run (`reproducers/CE-0060/Repro.scala:80`). Fixed twin (`Proofs/Phase7/SemaphoreCountFixed.lean`) named. Duplicate queries recorded. `maybe_intended: likely` is honest (PR #4648 text quoted).
- Low (C4): the `status` comment still says "not reviewed yet" (`bugs/CE-0060.yaml:3`); batch 11b reviewed it FAITHFUL.

### D.4 QUESTIONS.md Q5

Q5 (`QUESTIONS.md`, "Is a trade-off that a PR names a bug?") has no "ANSWERED" mark and no user answer file. The default stands: keep CE-0060 as a low-priority record with `maybe_intended: likely`, nothing filed upstream. I agree with the default: the Scaladoc of `count` (`S:47-53`) was not changed, and the state is not transient without a later release. The gate does not need an answer: the record is honest either way.

### D.5 Gate verdict

**FAIL.** One blocker:

- B1 = G2: the Semaphore battery is incomplete (decision 63 item 4, rule (a)). Close it with a statement that rejects an honest `tryAcquire`/`tryAcquireN` drop, plus kernel rows and mirror runs.

Conditions (not blockers; do them in the same round):

- C1: honest `tryOffer` drop rows (kernel) on the six non-`Synchronous` classes.
- C2: CI green on the gate commit (`gh run list`: run 43762662916 for `8325ca2` was `pending` at review time; `7d3248b` and `5a360df` passed).
- C3: another agent re-runs `reproducers/CE-0060` on v3.7.1 and series/3.x at the gate (as in Phase 6).
- C4: `bugs/CE-0060.yaml` `status` comment.
- C5: inventory: the Semaphore, Mutex and LockQueue rows of the 7 open track S entries have an empty `registry` column (only the CE-0060 rows are linked), while the Queue and latch rows are linked. `check_inventory.py` requires links only for `modelled` rows, so this is a consistency item.

## E. Low notes

- N1 (`tryHandoff`): one schedule, one partner, no cancel. A hand-off that races with a cancel is covered only by the safety statements `noLoss`/`noDup`. Accepted.
- N2: the latch `noDeadlock` statements fix user programs to `IO.pure(())`. This does not remove a latch case (C.4), but a user program that calls latch operations through its own latches is not in these two statements (it is in the other latch statements).
- N3: no difftest was needed in this diff: the `v = 0` mirrors did not change (C.2), and the Queue and Semaphore mirrors have no diff.

## F. What must change

0. B1 (track S): G2 as in B.3; re-review.
1. C1 (track Q): honest `tryOffer` drop rows on six classes.
2. C2-C5 as in D.5.

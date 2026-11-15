# Review batch 12 (2026-11-15): re-review of the batch 11a and 11b fixes, and the parTraverseN `rankOrder` model change

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the witnesses, the wrong-function files, the difftest helpers, the raw notes and the reviews 11a and 11b. It did not run a build, Lean, a test, sbt, a difftest or `gh`.
Reviewed commit: `6299201` (`origin/main`), checked out as branch `review12`. Diff base: `9f8a482` (the commit of batches 11a and 11b).
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 56, 58, "Reviewer evidence", review log); decisions 59-62 (`raw/project-decisions/2026-11-15-phase7-start.md`). When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `difftest/`, `raw/`, `wiki/`, `inventory/`, `review/` or `tools/`. `Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala` at `v3.7.1`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `std.Queue.Concurrent.fifo` | open | FAITHFUL as a statement |
| `std.Queue.Async.fifo` | open | FAITHFUL as a statement |
| `std.Queue.Concurrent.takerLiveness` | open | **HOLLOW** (H3) |
| `std.Queue.Async.takerLiveness` | open | FAITHFUL as a statement (weakness W3) |
| `std.Queue.Concurrent.noLoss`, `.noDup`, `.noDeadlock` | open | FAITHFUL as statements (meaning unchanged; W3 applies) |
| `std.Queue.Async.noLoss`, `.noDup`, `.noDeadlock` | open | FAITHFUL as statements (meaning unchanged) |
| `std.Queue.twinSeq` | open | FAITHFUL as a statement (low strength; meaning unchanged) |
| `std.Semaphore.noDeadlock` | open | **HOLLOW** (H2) |
| `std.Mutex.lock.noDeadlock` | open | FAITHFUL as a statement (weakness W2) |
| `std.Semaphore.noLostPermit` | open | FAITHFUL as a statement (meaning unchanged; H2 applies) |
| `std.Semaphore.permit.atMostK` | open | FAITHFUL as a statement (W1 closed) |
| `std.Mutex.lock.mutualExclusion` | open | FAITHFUL as a statement |
| `std.Semaphore.count.atRest` (CE-0060) | refuted | FAITHFUL (input has no `join`; unchanged) |
| `std.Semaphore.acquireN.fifo` | open | FAITHFUL as a statement (W1 closed) |
| `std.Mutex.lock.semaphoreTwin` | open | FAITHFUL as a statement (stronger: traces now hold join records) |
| `core.IO.parTraverseN.*` (8 entries) | open | FAITHFUL as statements (stronger; still an over-approximation) |

HOLLOW reasons, one line each:

- H3 (`std.Queue.Concurrent.takerLiveness`): the root ignores the join outcome of each consumer. A `Synchronous#take` that always raises meets this statement and every other `Concurrent` queue statement; `twinSeq` does not cover `synchronous`.
- H2 (`std.Semaphore.noDeadlock`): the new conclusion ("not `blocked`" plus claims on `Succeeded` runs) allows a root that ends `Errored`. A `Semaphore#available` that always raises makes every root end `Errored`, so it meets this statement and every other `Semaphore` statement. The first form caught it.

Fixes accepted: 11a F1, L1, D1-D5 (D2 with one low remainder), 11b H1 (fatal regression), W1, L2, L4, L1 and L3 (recorded runs). No forgery found. No case deleted, no gate lowered.

Batch 7.1 (26 Phase 7 entries): **no**, not FAITHFUL everywhere. After this batch the latest verdict is HOLLOW for 2 entries (`std.Queue.Concurrent.takerLiveness`, `std.Semaphore.noDeadlock`) and FAITHFUL for the other 24 (11 track Q minus 1, 8 track S minus 1, 7 track L from batch 11b).

---

## A. Queue (track Q)

### A.1 What I read

- `Props/Phase7/Queue.lean` diff `9f8a482..6299201` in full, and `:236-330`, `:380-500` at `6299201`.
- `Std/QueueFactory.lean` diff (`isPublic`, `:149`).
- `Proofs/Phase7/QueueWrongFunction.lean` diff in full (`:41-43` `wrap`, `:148-199` new wrong functions, `:205-210` `subMultiB`, `isSublistB`, `:255-290` Fifo, `:317-350` TakerLiveness).
- `Proofs/Phase7/QueueWitness.lean` diff in full.
- `Registry.lean` diff (queue entries `:502-640`); `inventory/inventory.csv` diff; `difftest/py/gen.py` and `difftest/py/selftest.py` diffs.
- `raw/cats-effect/2026-11-15-queue-review11a-fixes.md`.

### A.2 Harness change: does it change the meaning of the 7 earlier FAITHFUL statements?

The change has three parts.

1. Events are `(tag, script index, value)` (`ev`, `Props/Phase7/Queue.lean:283`). `events` reads the new shape. `offeredOf` (tags 0, 3) and `removedOf` (tags 1, 2, 4) read the same elements as before. The script index of script `j` is `fs'.length` when it starts, so script 0 has index 0, script 1 has index 1, and so on (`QH.call`, `.startNext`). The drain uses index 0 but has its own tag 4, so `removedBy` (`:376`) keeps the drain apart (`c = none`).
2. `offer` now runs `uncancelable(poll => delay(record offerStart) *> poll(offer(x)).map(record offered))` (`:322-323`, `.offerPoll` `:329`). The new `delay` is inside the mask, before `poll`. It adds no cancel point. It adds one scheduling point of harness code. The set of queue behaviours that a schedule can reach is the same. Tag 6 is read only by `startedOf` (`:362`), which only `QuietBlock` uses.
3. `twinSeq` compares full traces. Both sides run the same harness with the same script index 0 and the same `offerStart` events. Equal traces stay equal. The witness `twinEvents` shows the new shape.

Conclusion: `noLoss`, `noDup`, `noDeadlock` (both families) and `twinSeq` mean the same as in batch 11a. Their batch 11a verdicts stand, with weakness W3 below.

### A.3 `std.Queue.Concurrent.fifo`, `std.Queue.Async.fifo`

`Fifo` (`:444`): all kinds of the family, `(allOffers scripts).Nodup`, mode `cancelAll`, all plans and schedules; for every remover `c : Option Nat` (script `i` or the drain) and every script `s`, the elements of `s` that `c` removed, in `c`'s record order, are a `Sublist` of `offersOf s`.

1. MIRROR: yes (unchanged; batch 11a section 1).
2. PROPERTY: yes.
   - The batch 11a hypothesis "at most one taking script" is gone. `Nodup` stays; batch 11a accepted it (the queue never inspects elements).
   - Per remover is the observable form of FIFO. A remover's events come from one fiber, in program order. The record runs masked right after `poll(take)` returns, so the record order of one remover is its dequeue order. Across removers, the record order is not the dequeue order, so a claim across removers would be false for a correct queue.
   - A missing record (a run that stops before the record) only removes elements from the list. A sublist of a sublist is still a sublist, so this hides no reorder that a record shows.
   - Dropping and circular kinds: a dropped element is not removed; the order of the rest is kept. So the claim holds for all kinds, as stated.
3. SETTLED: open.
4. Wrong function: `wLastIfWaiters_breaks` and `wLastIfWaitersAsync_breaks` (`Proofs/Phase7/QueueWrongFunction.lean:278`, `:286`), kernel, on `[[take, take], [take], [take], [offer 1, offer 2]]`, plan `[(1, 1)]`, mode `cancelAll`; the mirror meets the claim on the same input (`lastIfWaiters_mirror_ok` `:282`, and the `Async` twin). This is the counterexample of batch 11a. `fifoOKB` (`:255`) checks removers `0..5` and the drain; the input has 4 scripts, so it checks every remover. `isSublistB` (`:207-210`) is the usual greedy sublist test. `wLifoConc_breaks`, `wLifo_breaks` stay (input now has two `tryTake`s).
   - Other broken functions: "take always raises" removes nothing, so it meets `Fifo`. This is a safety statement; the success claim belongs to `takerLiveness` (see H3, W3).
5. Decision 53: `conc_any_satisfiable`, `async_any_satisfiable` through `SafetyWitness` (`Proofs/Phase7/QueueWitness.lean`), which now has only the hypotheses `fam k` and `Nodup`, exactly the hypotheses of `Fifo`. Kernel runs `concRun_ok`, `asyncRun_ok` with the new event shape.
6. Forgery: none. No user code; `henv` answers only queue and harness closures.

Verdict: FAITHFUL as a statement (both families).

### A.4 `std.Queue.Concurrent.takerLiveness`, `std.Queue.Async.takerLiveness`

`TakerLiveness` (`:459`): pure producers and pure consumers; the plan cancels only consumers; mode `join` over all taking scripts. Claim: `Succeeded`, or `QuietBlock` (`:455`): `blocked`, every recorded offered element removed, every started `offer` returned. The count hypothesis is gone.

1. MIRROR: yes (unchanged).
2. PROPERTY: the `QuietBlock` part is correct.
   - A correct queue can block only when a joined consumer waits on an empty queue and no producer waits. Then every offered element was removed and every started offer returned: `QuietBlock` holds. A canceled consumer that absorbed a wakeup and did not pass it on leaves an element in the queue while a consumer waits: `offeredOf ⊄ removedOf`, so the statement rejects the run. A producer that waits on a full queue while a consumer waits on an empty one (lost wakeup of an offerer) gives `startedOf ⊄ offeredOf`: rejected. So the 11a L1 gap is closed.
   - No other hypothesis. The plan restriction (only consumers) is the test shape; batch 11a accepted it.
   - Livelock: stated in the docstring and both registry notes (D5).
   - **But the root ignores the outcome of each join.** `.joinNext` (`:306-311`) runs `IO.joinOf f` and goes on with the next index; the outcome is not read. A consumer whose `take` raises ends `Errored`; the join returns; the root cancels the producers and drains; the run ends `Succeeded`. So a `take` that raises in place of waiting meets the statement. See H3 and W3.
3. SETTLED: open.
4. Wrong functions: `wNoPassOn_breaks` (`:335`), `wNoAnywayU_breaks` (`:343`), kernel, on `[[take], [take], [offer 1]]`, plan `[(1, 0)]`, join `[0, 1]`: `!liveOKB`. The mirror meets `liveOKB` on the same input (`passOn_mirror_ok` `:339`, `passOnAsync_mirror_ok`). `liveOKB` (`:317`) is the Bool form of the claim (`subMultiB` = `SubMulti`). This is the batch 11a counterexample. `wNoWake_breaks`, `wNoNotify_breaks` now use `liveOKB`.
5. Decision 53: `conc_live_satisfiable`, `async_live_satisfiable` (`Proofs/Phase7/QueueWitness.lean:159`, `:166`). `LivenessWitness` (`:102`) has both hypotheses (producer/consumer shape, plan cancels only consumers) and the exact join list, and two kernel runs: the pass-on run (`Succeeded`, takes 2 > offers 1) and a `QuietBlock` run (`quiet_of_events`). The witness now reaches a canceled woken consumer. Complete.
6. Forgery: none.

**H3 (`std.Queue.Concurrent.takerLiveness`, HOLLOW).** Rows of the entry include `std.Queue.Synchronous.take` (`Registry.lean:602`). Counterexample term (read only, not run):

```lean
open QueueConcurrent in
def wSyncTakeRaises : UserEnv := wrap fun id _ _ =>
  match QC.ofId? id with
  | some (.sTakeK _) => some { out := .throw { code := 9 } }   -- `Synchronous#take` raises
  | _ => none
```

`QC.sTakeK` is the step of `Synchronous#take` after its `Deferred` (`Std/QueueConcurrent.lean:437`, `sTakeIO`). With kind `.synchronous` and any input of the statement (for example `[[take], [offer 1]]`, plan `[]`, join `[0]`): every consumer ends `Errored`; every producer waits in `offer` until the root cancels it; the drain finds nothing; every run ends `Succeeded`. So the statement holds for every input. It also holds for `concNoLoss` (no `offer` returns, `offeredOf = []`), `concNoDup`, `concFifo`, `concNoDeadlock`. `twinSeq` has no `synchronous` pair (`twinPairs`), so no queue statement catches it. Precedent (batches 7, 9, 11b W1): "always raise" is a weakness only when a sibling statement catches it. Here none does, and this entry is the one whose job is to claim that a waiting taker gets an element.
Fix: let the root record each join outcome (as track S did, a harness tag), and claim in a `Succeeded` run that every joined consumer that the plan does not cancel has a `Succeeded` record. (Alternative: the root rethrows the outcome, `join.flatMap(_.embedNever)`, and the claim stays "`Succeeded` or `QuietBlock`".) Add `wSyncTakeRaises` as a kernel-checked wrong-function test.

**W3 (`std.Queue.Async.takerLiveness` and the safety statements).** The same gap exists in the `Async` family, but `twinSeq` catches it there: an `Async` `take` that raises gives `Errored` where the `Concurrent` side of the same factory succeeds (`twinPairs` covers `bounded` with `2 ≤ cap < 65534` and `unbounded`, which is the whole `AsyncKeep` family). So `asyncTakerLiveness` is FAITHFUL as a statement with weakness W3. The same fix closes W3.

Verdicts: `std.Queue.Concurrent.takerLiveness` HOLLOW (H3). `std.Queue.Async.takerLiveness` FAITHFUL as a statement (W3).

### A.5 D1-D5

- D1: done. `isPublic` no longer lists `.getState` and `.sizeK` (`Std/QueueFactory.lean:149`, docstring `:141-148`). So a user program under `WellFormed` with this `Lib` cannot call the `Concurrent` `size` at all; the docstring says so. Correct and safe.
- D2: done, with one remainder. The `UnsafeBounded`/`UnsafeUnbounded` `put`/`take`/`size` rows are no longer in the track Q entries (`Registry.lean` diff). The helper rows `buffer`, `sequenceBuffer`, `head`, `tail`, `LookAheadStep`, `project`, `first`, `last` are now `deferred: phase 9 (weak memory model): ...` (`inventory/inventory.csv`). Low remainder D2a: `std.Queue.UnsafeBounded.FailureSignal` (`Q:1025`) and `std.UnsafeUnbounded.FailureSignal` keep "internal: private helper; modelled as part of its public caller", but their public callers are now `todo` (`UnsafeBounded`) or modelled only by an older entry (`UnsafeUnbounded.put/take` through `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement`). For `UnsafeBounded.FailureSignal` the reason does not apply. Suggest the same `deferred: phase 9` reason.
- D3: done. `g3.names = 40000` with a comment (`difftest/py/gen.py:1771`). Reported run on the merged generator: 66,000 of 66,000 agree, 52,838 per queue op (≥ 50,000, 3 seeds). I saw no run log in the repository; the numbers are as reported.
- D4: done. `V2Q_OPS`, `V2Q_MIN = 0.03` and the check in `difftest/py/selftest.py`; `queue2` added to the golden type-check list. A new floor, nothing lowered.
- D5: done (docstring item 5, both registry notes).

## B. Semaphore and Mutex (track S)

### B.1 What I read

- `Props/Phase7/Semaphore.lean` diff in full, and `:255-300`, `:400-720` at `6299201`.
- `Proofs/Phase7/SemaphoreWitness.lean` diff in full; `Proofs/Phase7/SemaphoreCount.lean:20-55`.
- `Model/Semaphore.lean:427-428` (`availableIO`), `:560-566` (`availK`); `Model/Outcomes.lean:80-105`; `Model/Run.lean:47-60` (`Summary`).
- `Registry.lean` track S entries (`:643-735`).
- `raw/cats-effect/2026-11-15-semaphore-mutex-review11b-fixes.md`.

### B.2 The join record (W1 fix) and forgeability

- After `join i` the root runs `HS.joinRec` (`Props/Phase7/Semaphore.lean:283`), which emits `joinRecV i oc` (`:268`: `pair (nat 62) (pair (nat i) oc)`) and goes on with the rest of the acts (`:352-354`). The outcome `oc` is the join result.
- Can user code forge a record? In statements 2 and 5 the environment is `env behaved` (`:372`, `behaved` `:487`). `behaved` answers only `BH` closures; `BH.call` returns programs (cedes, then `pure`/`raiseError`/`canceled`) and no effect. In the whole file, only `HS.joinRec` emits (`grep emit`: `:354` only). `HS.joinRec` is not public (`HS.public`, `:392`: only `newCell`, `afterCell`). So nothing in statements 2 and 5 can emit a tag-62 record except the root. No forgery.
- In statements 1, 3, 4 and 8, user code can emit any value, also a fake tag-62 value. Statements 1, 3, 4 do not read records. Statement 8 compares traces of two programs with the same user code, so a user record is the same on both sides; it gives no false pass.
- `OkJoined` (`:528`): `bus[i]? = some b`, `b.succeeds`, `join i ∈ as`, `cancel i ∉ as`. `BUse.succeeds` (`:522`): `permit` with an `ok` section, `acqRel`, `tryRel`. For a correct semaphore with `need ≤ k`, such a use cannot fail: no other fiber holds its handle, only the parent cancels, and the parent does not. So the clause is true for v3.7.1 by reading. It is conservative (a `cancel` after the `join` also excludes the fiber).
- `w1_breaks` (`Proofs/Phase7/SemaphoreWitness.lean:200`), kernel: on `Semaphore(2)`, `[acqRel 2]`, `[join 0]`, the wrong function `acqRaises` ends `Succeeded` with an `Errored` record and no `Succeeded` record; the mirror records `Succeeded`. `okJoinedW` shows the input meets `OkJoined`. Correct.

### B.3 Did the join record change the other track S statements?

Every root with a `join` act now has one more harness step and one more trace value. Per statement:

- 1 `noLostPermit` (`:514`): reads `availOf v` of a `Succeeded` root. The extra step is harness code with no queue effect. Meaning unchanged.
- 3 `atMostK`, 4 `mutualExclusion`: read the counter cell (`highest`). Unchanged.
- 6 `count.atRest` (CE-0060): the refutation input `countActs = [cede, cede, cancel 1, cancel 0]` has no `join` (`Proofs/Phase7/SemaphoreCount.lean:29`). The kernel run `countRun` is on the same term as before. Unchanged.
- 7 `acquireN.fifo`: own root `fifoRoot` (namespace 64), no `HS`. Unchanged.
- 8 `semaphoreTwin` (`:703`): `core` compares `(summary, out)`; `out` now has the join records of both sides. The record holds the use outcome, which user code could already emit before (the use result is the user's own value), so the change cannot make the claim false for correct locks where it was true. It makes it stronger: a lock that changes a use outcome without a user emit now shows. The witness `run8_ok` checks `core` equal and `Succeeded` (`mutexSemaphoreTwin_satisfiable`, `:300`). L2 docstring fix: done (`:696-702`). Verdict stays FAITHFUL as a statement.

### B.4 `std.Semaphore.noDeadlock` (`:542`)

Statement: `AllEnded`, `need ≤ k`, behaviour tables. Conclusion: `o.summary ≠ .blocked`, and for a `Succeeded` root, `available = k + released` and a `Succeeded` record for every `OkJoined` use.

1. MIRROR: yes (unchanged).
2. PROPERTY: no.
   - H1 is fixed. A fatal base stops the run with `Summary.fatal`, which is not `blocked`. `fatal_regression` (`SemaphoreWitness.lean:163`) shows the 11b input meets the hypotheses, refutes the first form and is not `blocked`.
   - W1 is fixed (B.2).
   - **H2: the new conclusion allows every non-`blocked` summary.** `Summary` has `done (succeeded | errored | canceled)`, `fatal`, `uncaught`, `aborted`, `suspended`, `outOfFuel`, `blocked`, ... (`Model/Run.lean:47-60`). For a correct semaphore and these inputs, the root never ends `Errored`: its own operations (`cancel`, `join`, `releaseN`, `cede`, then `available` and `count`, `actsIO` `:272-275`) do not raise, and a join returns the outcome. So "`Succeeded` or `fatal`" is the true promise. The new form keeps only "not `blocked`". The first form (`∃ v, Succeeded v ∧ available = …`) rejected a root `Errored`; the new form does not.
   - Counterexample term (read only, not run):

     ```lean
     def availRaises (e : UserEnv) : UserEnv where
       call := e.call
       callV id a v :=
         match SL.ofId? id with
         | some .availK => { out := .throw { code := 9 } }   -- `Semaphore#available` raises
         | _ => e.callV id a v
     ```

     `SL.availK` is the map step of `available` (`Model/Semaphore.lean:428`, `:563`). Input: `k = 1`, `bus = [.permit 0 (.ok .unit)]`, `as = [.join 0]`. The fiber succeeds, the join records `Succeeded`, and the root's final `available` raises: every run ends `Errored(9)`. Not `blocked`; the `Succeeded` part is vacuous. The same holds for every input. v3.7.1 ends `Succeeded((1, 1))`.
   - Which statement catches it? `noLostPermit` and `count.atRest` are conditional on `Succeeded`; `atMostK`, `mutualExclusion` read the counter cell; `acquireN.fifo` reads `count`, not `available`; the twin uses `permit`, and user code calls the same broken `available` on both sides. So no `Semaphore` statement catches it. The first form of this entry did. The H1 fix opened this gap.
   - This entry's own conclusion is a claim about `available` ("a `Succeeded` run has `available = k + released`"), so it is the entry that must carry the success claim.
3. SETTLED: open.
4. Wrong functions on its own rows (`apply`, `acquireN`, `releaseN`, `permit`): "`acquireN` raises" and "`permit` raises" break it through `OkJoined` (a joined `acqRel`/`permit ok` records `Errored` in a `Succeeded` root). "`releaseN` raises" breaks it the same way (the `permit` finalizer raises). "`apply` raises" meets it (root `Errored`); `acquireN.fifo` and the twin catch that. "`available` raises" meets it and nothing catches it (above).
5. Decision 53: `semNoDeadlock_satisfiable` (`SemaphoreWitness.lean:123`): the hypotheses and a kernel run that ends `Succeeded((2, 2))` with two `Succeeded` records for the two `OkJoined` uses. Complete.
6. Forgery: none (B.2).

Fix: conclusion `(∃ v, o.summary = .done (.succeeded v) ∧ availOf v = some (k + released as) ∧ ∀ i, OkJoined bus as i → …) ∨ (∃ e, o.summary = .fatal e)`. This keeps fatal errors in the domain, implies "not `blocked`", and rejects a root `Errored`. (The other 11b option, a non-fatal hypothesis with the first form plus the join clause, is also sound.) Add `availRaises` as a kernel-checked wrong-function test.

Verdict: HOLLOW (H2).

`std.Semaphore.noLostPermit` keeps its meaning. "`available` raises" meets it, as it did in batch 11b; then the first form of `noDeadlock` caught it. After the H2 fix it is caught again. Verdict: FAITHFUL as a statement; H2 applies until the fix.

### B.5 `std.Mutex.lock.noDeadlock` (`:572`)

Conclusion: not `blocked`; a `Succeeded` root returns `()` and has a `Succeeded` record for every `OkJoined` use.

1. MIRROR: yes.
2. PROPERTY: yes, with weakness W2. The same form as B.4 allows a root `Errored`. Rows: `Mutex.apply`, `Mutex.lock`, `LockQueue.lock`. "`lock` always raises" (also "raises when it would wait") makes the root's final `lock.use` raise, so the root ends `Errored` and this statement holds. The twin catches it: the mutex root `Errored` is not an outcome of the `Semaphore(1)` program (`mutexSemaphoreTwin`, one direction mutex ⊆ semaphore, as batch 11b noted). "`apply` raises": the twin catches it the same way. So by the precedent this is a weakness, not HOLLOW.
3. SETTLED: open.
4. Wrong function: "lost wakeup" (`awakeCell` never completes) ends `blocked` (semsmoke, as reported; not re-read in Lean). The H1 regression applies by reading (fatal base gives `Summary.fatal`).
5. Decision 53: `mutexNoDeadlock_satisfiable` (`:261`): kernel run `Succeeded(())` with a `Succeeded` record for use 0, `OkJoined` shown. Complete.
6. Forgery: none (B.2).

Advice: use the same conclusion as the H2 fix ("`Succeeded …` or `fatal`").

Verdict: FAITHFUL as a statement (W2).

### B.6 `permit.atMostK`, `acquireN.fifo` (W1 closed)

Both statements are unchanged. W1 ("`acquireN(n ≥ 2)` always raises") is now caught by the sibling `noDeadlock` (`w1_breaks`). That sibling is HOLLOW for another reason (H2), but its `OkJoined` clause is correct and will stay in the fix. Verdicts: FAITHFUL as statements.

### B.7 Low items of 11b

- L1, L3: recorded. The merged-generator run (seeds 101-103, 51,000 cases, all agree) and the rerun of the `g61-9094` batch after the `rankOrder` fix (5,000 of 5,000) are in the raw note; no run log in the repository; as reported.
- L4: `docs/std/mutex.md:6-7` in `Model/Mutex.lean`, `Props/Phase7/Semaphore.lean`, `Registry.lean`.

## C. parTraverseN (track G): `rankOrder` model change

### C.1 What I read

`Model/ParTraverse.lean` diff in full and `:415-450`, `:535-600` at `6299201`; `Props/Phase6/ParTraverse.lean` diff in full; `Proofs/Phase6/ParTraverseWitness.lean` diff; `tools/Difftest/Env.lean` diff (`rankOrder`, `:631`); `raw/cats-effect/2026-11-15-partraverse-rankorder-fix.md`.

### C.2 The model change

- `SetSt` (`Model/ParTraverse.lean:421`): `hash`, `all` (ghost, every element the `HashSet` held, in insertion order), `xs`. `setAdd` (`:437`): at the `Set4 + new` step `all := xs ++ [x]`; later adds append to `all`; `setRemove` changes only `xs`. `setToList` (`:447`): `ho all xs` for a `HashSet`, `xs` otherwise.
- The order input is `ho : List Val → List Val → List Val`. Every statement now has `∀ ord, (∀ all xs, (ord all xs).Perm xs) → …` (`Props/Phase6/ParTraverse.lean`, statements 1-8).

### C.3 Is it still an over-approximation of Scala's order?

Yes, and a larger one than before.

- Every old order `o : List Val → List Val` with `(o xs).Perm xs` gives a new order `fun _ xs => o xs` with the new hypothesis. So the new statements imply the old ones; the set of orders only grew.
- In one real run, the identity hashes of the `(Fiber, Deferred)` pairs are fixed, so the iteration order of a `HashSet` is a function of its elements (and, for full hash collisions, of its insertion history). `all` together with `xs` holds both. So for each real run there is an `ord` that gives its orders, and that `ord` meets the `Perm` hypothesis. The new input can also express the history part, which the old one could not.
- Like the old input, `ord` need not be consistent between a set and its subsets; now it may also depend on removals. This only adds behaviours (statements get stronger, proofs harder). A false refutation from such a behaviour would fail the Scala reproducer rule.

### C.4 Can the ghost list leak into behaviour?

No. `all` is read only by `setToList` (`:447`), and its result is a permutation of `xs` under the statement hypothesis. The `grep` of `setOf`, `setVal`, `setAdd`, `setRemove`, `setToList` in `Model/ParTraverse.lean` gives only `supAdd` (`:542`), `supRemove` (`:546`), `caK` (`:574`) and `joinAllK` (`:591`); none reads `all`. Emptiness and membership use `xs`. Elements are added only by the library closure `supAdd`. The supervision `Ref` is internal (as before; the `WellFormed ptLibDeep` analysis of batches 9 and 10 did not change). Statement 8 reads the harness counter cell, not the supervision set. So the ghost list changes only the heap value of an internal cell.

### C.5 Are the 8 statements still FAITHFUL as statements?

The quantifier change is the only change in `Props/Phase6/ParTraverse.lean`. The conclusions and the other hypotheses are the same. The statements are stronger. The witnesses (`Proofs/Phase6/ParTraverseWitness.lean`) use `idOrd = fun _ xs => xs` and `revOrd = fun _ xs => xs.reverse` with `idOrd_perm`, `revOrd_perm` for the new hypothesis; the kernel runs are the same terms. The difftest `rankOrder` (`tools/Difftest/Env.lean:631`) ranks by the index in `all`; this is a function of `(all, xs)`, so it is one of the allowed orders, and the `k!` permutations give every total order of the children. The case `g61-9094` is kept as a regression case (`difftest/hashcases/partraverse_hash.jsonl`).
Weaknesses from batches 7-10 (for example "always raise" meets statement 1 alone; statements 2 and 5 cover success) are unchanged.

Verdict: the 8 `core.IO.parTraverseN.*` entries stay FAITHFUL as statements.

## D. Gates and cases

- No case file deleted (diff `9f8a482..6299201`: `difftest/hashcases/partraverse_hash.jsonl` +1 line; no deletion).
- `selftest.py`: one new floor (`V2Q_MIN`), one new golden file in the type-check list. Nothing lowered.
- No change to `scripts/check_forbidden.py` or CI gates in this diff.

## E. What must change

1. H3: record the join outcomes in the queue harness (or rethrow them) and claim `Succeeded` records for the joined, not canceled consumers in both `takerLiveness` statements; add `wSyncTakeRaises` as a wrong-function test. Re-review both `takerLiveness` entries.
2. H2: restore the success claim in `std.Semaphore.noDeadlock` ("`Succeeded …` or `fatal`"); add `availRaises` as a wrong-function test. Advice: the same form for `std.Mutex.lock.noDeadlock` (W2). Re-review both.
3. D2a: give the two `FailureSignal` rows the `deferred: phase 9` reason (or justify the current one).
4. Rule (for the wiki): a liveness statement whose root joins fibers must look at the join outcomes, and a conclusion that excludes only `blocked` must say why `Errored`/`Canceled` roots are allowed. "Not `blocked`" alone is weaker than "every stopped run is `Succeeded` or `fatal`".

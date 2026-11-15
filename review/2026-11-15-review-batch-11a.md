# Review batch 11a (2026-11-15): Phase 7 track Q (`Queue`)

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the witnesses, the wrong-function tests, the smoke tool, the difftest generator and translator, the wiki and the raw notes. It read the Scala source at `v3.7.1` in `~/Projects/cats-effect` (read only). It did not run a build, Lean, a test, sbt or `gh`.
Reviewed commit: `9f8a482` (`origin/main`), checked out as branch `review11a`. Track Q commits: `23f753e`, `90d9a61`, `285139f`, `4eac6fe`, `c22769b`, `4e35b0e`.
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 56, 58, "Reviewer evidence", "Closure references"); decisions 59-62 (`raw/project-decisions/2026-11-15-phase7-start.md`). When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `difftest/`, `raw/`, `wiki/`, `inventory/` or `tools/`. `Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala` at `v3.7.1`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `std.Queue.Concurrent.noLoss` | open | FAITHFUL as a statement |
| `std.Queue.Async.noLoss` | open | FAITHFUL as a statement |
| `std.Queue.Concurrent.noDup` | open | FAITHFUL as a statement |
| `std.Queue.Async.noDup` | open | FAITHFUL as a statement |
| `std.Queue.Concurrent.fifo` | open | HOLLOW (F1) |
| `std.Queue.Async.fifo` | open | HOLLOW (F1) |
| `std.Queue.Concurrent.noDeadlock` | open | FAITHFUL as a statement |
| `std.Queue.Async.noDeadlock` | open | FAITHFUL as a statement |
| `std.Queue.Concurrent.takerLiveness` | open | HOLLOW (L1) |
| `std.Queue.Async.takerLiveness` | open | HOLLOW (L1) |
| `std.Queue.twinSeq` | open | FAITHFUL as a statement (low strength) |

HOLLOW reasons, one line each:

- F1 (`fifo`, both families): the hypothesis "at most one script takes" is not a documented precondition. A take that takes the last element when another taker waits meets the statement and breaks FIFO.
- L1 (`takerLiveness`, both families): the hypothesis "total takes <= total offers" counts the takes of canceled consumers. So every wakeup that a canceled taker absorbs is paid for by a spare offer. A queue without the cancel pass-on (`cleanup`/`notifyNextTaker`, `notifyAnyway`) meets the statement for the unbounded kinds and for `AbstractQueue`.

No forgery found. No user code is in any statement. The mirrors are faithful. The difftest claims are consistent. Low findings: D1-D5.

---

## 1. Mirror (all entries)

### What I read

- `Std/QueueConcurrent.lean` in full (766 lines), `Std/QueueAsync.lean` in full (648 lines), `Std/QueueFactory.lean` in full (156 lines).
- `Std/Queue.lean:73-126` (`Takers`, `notifyOne`, `Takers.put`, `Takers.clear`).
- Scala at `v3.7.1`: `Q:25-1120`; `core/shared/src/main/scala/cats/effect/IODeferred.scala:55-81`; `core/shared/src/main/scala/cats/effect/IO.scala:1350-1432`; `tests/shared/src/test/scala/cats/effect/std/QueueSuite.scala:787-850`.

### Factory choice by capacity

`newIO` (`Std/QueueFactory.lean:57-70`) follows `Q:74-91`, `Q:152-167`, `Q:196-228` in order. `bounded(n)`: `1 < n < 65534` (`Short.MaxValue.toInt * 2`, `Q:78`) gives `BoundedAsyncQueue`; `n > 0` gives `BoundedQueue`; else `synchronous`. `dropping(n)`: `1 < n < 65534` gives `DroppingAsyncQueue`, else `DroppingQueue`. `circularBuffer` is always `CircularBufferQueue`. `unbounded` is `UnboundedAsyncQueue`. `unboundedForConcurrent` is `BoundedQueue(Int.MaxValue)` (`Q:101-103`, `intMax`). Correct.

The kind sets of the statements cover every class that the public API reaches: `.bounded 1` and `.boundedConc 1` give the same term; `.bounded 0` and `.synchronous` give the same term; `.dropping 1` and `.droppingConc 1` give the same term (`Std/QueueFactory.lean:58-70`). `dropping(0)` and `circularBuffer(0)` throw before an `IO` exists (`Q:236-240`); the statements require `cap >= 1` (`Props/Phase7/Queue.lean:379-393`). Correct.

### `Concurrent` family

Checked line by line, in order: `AbstractQueue#offer` (`Q:397-414`; `Std/QueueConcurrent.lean:568-580` and `onOfferNoCapacity`), `tryOffer` (`Q:416-427`), `take` (`Q:429-482`; `:603-616`, descriptors 126-128 `:469-474`), `tryTake` (`Q:484-497`; no `size - 1 < capacity` check, as in Scala), `size` (`Q:499`), `notifyNextTaker` (`Q:501-508`; `:647`), the three `onOfferNoCapacity`/`onTryOfferNoCapacity` (`Q:517-581`), `Synchronous` (`Q:246-359`), the factories (`Q:93-110`, `Q:149-150`, `Q:227`). Branch order, guards and the state written match. `require(capacity > 0)` is only in `BoundedQueue` (`Q:515`), as in the model.

`IODeferred.get` is `cell.get()` (`IODeferred.scala:71`): it reads the cell when the `get` term is built. The model builds every `get` as `IO.deferredGetOf d none`. I checked each site: in each one the `Deferred` is not yet in the shared state when Scala builds the `get` (`offerer`, `taker`, `latch` are new and the `modify` that publishes them has not committed). So `initial` is correct. `failCommit` (`Q:326`) is built inside the `modify` of `take`; the model builds it later, with `none`; this is the same value.

### `Async` family and sequential consistency

Checked: `BaseBoundedAsyncQueue#take` (`Q:615-687`, `F.cont` body with `lift(F delay {...}).flatten`), `tryTake` (`Q:689-698`), `size` (`Q:613`), `notifyOne` (`Q:746-776`), `BoundedAsyncQueue#offer` (`Q:786-854`, `F.async` = `IO.async`, `IO.scala:1416-1431`), `tryOffer` (`Q:856-867`), `UnboundedAsyncQueue` (`Q:871-988`, `asyncCheckAttempt`, `IO.scala:1353-1368`), `DroppingAsyncQueue` (`Q:990-1011`). The `Some(fin)`/`None` and `Right`/`Left` selectors (`oWaitSel`, `uWaitSel`) match `IO.async`/`asyncCheckAttempt`: `poll(get)` with `onCancel(fin)`, else a bare `get`.

Sequential consistency is stated: `Std/QueueAsync.lean:10-28` (module doc), the wiki article ("Mirror rules"), each `Async` registry note. Each Scala `F.delay`/`F.defer` thunk is exactly one model thunk; no two Scala thunks are merged and no thunk is split. The shared `var received`/`result`/`succeeded` are one model cell, written in the registration thunk and read in the later `F.defer` thunk on the same fiber (program order), so no reachable interleaving between separate thunks is hidden. What the model leaves out is inside one thunk (the CAS loops of `UnsafeBounded`, `Q:1049-1114`, and `UnsafeUnbounded`); the module doc says a proof covers only the sequentially consistent subset (`Std/QueueAsync.lean:26-28`). Correct.

### Old v1 mirror

`Std/QueueAsync.lean` imports `Std/Queue.lean` only for `Takers`, `notifyOne`, `Takers.put`, `Takers.clear` (`Std/Queue.lean:73-126`). These are data helpers. No `QLam` closure of the v1 mirror and no v1 `takeIO`/`offerIO` is used by `Props/Phase7/Queue.lean`, `Proofs/Phase7/*` or `tools/QSmoke`. So the v1 hole (user code gets the buffer `Ref`) does not reach a Phase 7 statement.

MIRROR verdict for all 11 entries: yes.

## 2. Harness and forgeability

`rootIO` (`Props/Phase7/Queue.lean:260-263`), `QH.call` (`:273-318`), `henv` (`:321-329`).

- No user code: `henv` answers queue closures and namespace-54 harness closures; every other id throws (`:321-329`). Scripts, plans, modes and elements are data.
- Elements are arbitrary `Val`s. No queue closure and no harness closure calls an element or decodes it as a program. The trace readers (`events`, `offeredOf`, `removedOf`, `:334-352`) read only the outer `pair (nat tag) x` of each emit, and each emit is built by `ev` (`:270`). An element cannot fake an event.
- The queue object is `Val.fn o` (odd). Its state cells are only in the closure value. Harness closures are odd ids in namespace 54 (`QH.id`, `:201`).
- Conclusion: there is no forgery channel in these 11 statements. Decision 56/58 rules are not needed here because no user code runs.

The atomic pattern `uncancelable(poll => poll(op).map(record))` (`:307-314`). The pattern is in the CE test "not lose data on canceled take" (`QueueSuite.scala:793-812`: `IO.uncancelable(_(take(q)).flatMap(results.set(_)))`). Inside `poll`, the operation runs with the caller's own mask, so every cancel point of `take` stays reachable: a `take` that a cancel hits after an offer woke it, or after a `Synchronous` offerer handed it `(a, latch)`, is in the statements. The pattern removes only the gap after `take` returned and before the user saw the value. A loss in that gap is the user's own fault (the value was delivered), not a queue defect. So the pattern does not remove the interesting case. Correct.

## 3. Per-entry review

### `std.Queue.Concurrent.noLoss`, `std.Queue.Async.noLoss` (open)

`NoLoss` (`Props/Phase7/Queue.lean:405-407`), kinds `ConcKeep`, `AsyncKeep` (`:379-385`).

1. MIRROR: yes (section 1).
2. PROPERTY: yes. All scripts, plans, elements, capacities, `PChoice` schedules. Only hypothesis: the kind never drops by design (`Q:184-228`). Mode `cancelAll` does not lose generality: a schedule can let every fiber finish before the root cancels it. The drain (`tryTake` until `None`) finds every element that stays in the queue. The conclusion is conditional on `Succeeded`; `noDeadlock` covers the other summaries.
3. SETTLED: open.
4. Wrong function: `wDrop_breaks`, `wDropAsync_breaks` (`Proofs/Phase7/QueueWrongFunction.lean:162-176`), kernel runs; the mirror meets the claim on the same input (`drop_mirror_ok`, `dropAsync_mirror_ok`).
5. Decision 53: `conc_satisfiable`, `async_satisfiable` (`Proofs/Phase7/QueueWitness.lean:95-103`): the hypotheses hold and the run cancels a waiting consumer; `decide +kernel`.

Verdict: FAITHFUL as a statement.

### `std.Queue.Concurrent.noDup`, `std.Queue.Async.noDup` (open)

`NoDup` (`:410-412`). All kinds, all modes.

1. MIRROR: yes. 2. PROPERTY: yes (no hypothesis other than the kind). 3. SETTLED: open.
4. Wrong function: `wDup_breaks`, `wDupAsync_breaks` (`QueueWrongFunction.lean:182-196`).
5. Decision 53: `conc_any_satisfiable`, `async_any_satisfiable` (`QueueWitness.lean:109-115`).

Verdict: FAITHFUL as a statement.

### `std.Queue.Concurrent.fifo`, `std.Queue.Async.fifo` (open)

`Fifo` (`:415-419`): `(allOffers scripts).Nodup` and `(scripts.filter takes).length <= 1`.

1. MIRROR: yes.
2. PROPERTY: no.
   - `Nodup` is acceptable: the queue never inspects elements (no Scala code compares `A` values; `filter(_ ne ...)` and `eq` compare `Deferred`s), so distinct elements lose no generality.
   - "At most one taking script" is not a documented precondition and not a type invariant. The Scaladoc promises FIFO for every use (`Q:31-33`). The hypothesis exists because `removedOf` merges the events of all fibers in record order, which is not the dequeue order. It removes every multi-consumer case.
   - Wrong function (counterexample term). `wLastIfWaiters`: in `QC.takeMod` (`Std/QueueConcurrent.lean:603`), if `st.takers` is not empty and `st.queue` is not empty, take the last element instead of the head. With at most one taking script, `st.takers` is always empty when that script runs `takeMod`: its old `Deferred` was either dequeued by an offer or removed by `cleanup`, and the root drain uses `tryTake`. So `wLastIfWaiters` behaves like the mirror on every input of the statement and meets it. It breaks FIFO with three consumers: consumers `C2 = [take, take]`, `C3 = [take]`, `C4 = [take]`, producer `[offer 1, offer 2]`, plan cancels `C3` after it is woken. Schedule: all three wait (takers `[C2, C3, C4]`); `offer 1` wakes `C2`; `offer 2` wakes `C3`; `C2` retakes with queue `[1, 2]` and takers `[C4]`, so it takes `2`; `C3` is canceled in `poll(take)` and `notifyNextTaker` wakes `C4`; `C2` takes again with takers `[]` and gets `1`. `C2` removes `2` before `1`. (Read only, not run.) The `Async` analogue: in `QA.bTakeThunk` (`Std/QueueAsync.lean:444-452`), take the last element if the takers list holds a live cell.
3. SETTLED: open.
4. Wrong function in the repo: `wLifoConc_breaks`, `wLifo_breaks` (`QueueWrongFunction.lean:202-208`): a LIFO `tryTake` in all cases. Correct but not sufficient (above).
5. Decision 53: `conc_any_satisfiable`, `async_any_satisfiable` include both hypotheses (`QueueWitness.lean:80-82`).

Fix: tag each `took`/`tryTook` event with the script index (`recK` gets the index `i`; the drain gets its own index). State: for every taking script `c` (and the drain) and every script `s`, the elements of `s` that `c` removed, in `c`'s record order, are a `Sublist` of `offersOf s`. Drop the "at most one taking script" hypothesis. Keep `Nodup`. Add the `wLastIfWaiters` run above as a kernel-checked wrong-function test.

Verdict: HOLLOW (both families).

### `std.Queue.Concurrent.noDeadlock`, `std.Queue.Async.noDeadlock` (open)

`NoDeadlock` (`:422-423`). Mode `cancelAll`; every run that stops ends `Succeeded`.

1. MIRROR: yes.
2. PROPERTY: yes. `outcomesP` gives an observation only for a halted run with a result summary (`Model/Outcomes.lean:99-106`, `:155-156`); `blocked` means no task is ready and the root has no outcome (`Model/Run.lean:57-59`). So a run that an unfair schedule never finishes gives no observation, and `blocked` is a real deadlock. A livelock is not seen (no observation); this is a known limit of `outcomesP`, not a hidden hypothesis.
3. SETTLED: open.
4. Wrong function: `wHangConc_breaks`, `wHangAsync_breaks` (`QueueWrongFunction.lean:218-232`).
5. Decision 53: `conc_any_satisfiable`, `async_any_satisfiable`.

Verdict: FAITHFUL as a statement.

### `std.Queue.Concurrent.takerLiveness`, `std.Queue.Async.takerLiveness` (open)

`TakerLiveness` (`:426-433`): pure producers and pure consumers; the plan cancels only consumers; `(scripts.map takeCount).sum <= (allOffers scripts).length`; mode `join` (all taking scripts); every run that stops ends `Succeeded`.

1. MIRROR: yes.
2. PROPERTY: no.
   - Fair schedules: handled correctly (as `noDeadlock`): an unfair schedule never makes a `blocked` observation.
   - The count hypothesis counts the takes of consumers that the plan cancels. A canceled consumer that an offer woke absorbs that wakeup. The real queues pass it on: `cleanup` dequeues and completes the next taker (`Q:456-464`), `notifyNextTaker` (`Q:467`, `Q:501-508`), `notifyAnyway` (`Q:676-680`, `Q:936-940`). Under the hypothesis, the absorbed wakeup always has a spare offer: the canceled consumer's take is counted but never completes.
   - `AbstractQueue#offer` never waits while `takers` is not empty (`Q:401-403`; `Std/QueueConcurrent.lean:568-574`), and `UnboundedAsyncQueue#offer` never waits (`Q:879-890`). So in these kinds every later offer wakes the next waiting taker. Counting argument (read only): at the end of a `blocked` run all producers are done; with `N >= T` offers the queue holds at least `1 + (canceled consumers with a pending take)` elements, while the elements that wakeups left behind are at most the number of canceled woken consumers. These two bounds contradict, so no `blocked` run exists without the pass-on.
   - Wrong function (counterexample term). `wNoPassOn`: `QC.cleanupTake o t` (`Std/QueueConcurrent.lean:639`) removes `t` and returns `dUnit`; `QC.notifyNext o` (`:647`) returns `dUnit` and does not change the state. `wNoAnywayU`: `QA.uNotify o` (`Std/QueueAsync.lean:627`) returns `()` with no effect. These meet `concTakerLiveness` (all `AbstractQueue` kinds; `Synchronous` is not changed) and `asyncTakerLiveness` (`unbounded` changed; the bounded kinds are not changed). The canonical lost wakeup (the CE issue class of #3998): scripts `[[take], [take], [offer 1]]`, plan cancels script 0 after `offer 1` woke it, join `[0, 1]`. With `wNoPassOn` or `wNoAnywayU` the run ends `blocked` (script 1 waits, element 1 is in the queue); the mirror ends `Succeeded`. But takes 2 > offers 1, so the input is outside the statement; with `[offer 1, offer 2]` the second offer wakes script 1 and the wrong function passes.
   - For `bounded(cap)` (`BoundedAsyncQueue`) the defect can show (cap 2, two canceled woken consumers fill the buffer, the third offer waits), but only for that one class.
3. SETTLED: open.
4. Wrong function in the repo: `wNoWake_breaks`, `wNoNotify_breaks` (`QueueWrongFunction.lean:236-242`): offers that never wake. Correct but they do not test the cancel pass-on.
5. Decision 53: `conc_live_satisfiable`, `async_live_satisfiable` (`QueueWitness.lean:124-134`): all four hypotheses hold; `decide +kernel`. The witness has plan `[]`, so it does not reach a canceled waiter.

Fix: drop the count hypothesis and put the condition into the conclusion. Record an `offering x` event before each `offer` (inside the outer `uncancelable`, before `poll`). Claim: every run that stops ends `Succeeded`, or it ends `blocked` and (a) every recorded `offered` element is removed (`SubMulti offeredOf removedOf`) and (b) every `offering` has its `offered`. So a run may block only when the producers are finished and all their elements are taken, which is the documented case "the queue is empty" (`Q:38`). Add the `wNoPassOn`/`wNoAnywayU` runs on `[[take], [take], [offer 1]]` as kernel-checked wrong-function tests, and a witness that reaches a canceled woken consumer.

Verdict: HOLLOW (both families).

### `std.Queue.twinSeq` (open)

`twinSeq` (`:457-459`), `SameResults` (`:452-453`), `twinPairs` (`:448-449`).

1. MIRROR: yes. The pairs are the private `Concurrent` factory and the `IO` factory with the same argument (`Q:93-110`). `cap` range `2 <= cap < 65534` is exactly where both classes exist.
2. PROPERTY: yes, low strength. One fiber (sequential use) is the stated scope; under concurrency the two families differ in fairness on purpose (`Q:449-455`), so equal outcome sets are not promised there. The equality is on summary and full trace, both directions, all schedules. The Scaladoc of `bounded`, `dropping`, `unbounded` (`Q:63-73`, `Q:152-159`, `Q:184-195`) does not depend on the family.
3. SETTLED: open.
4. Wrong function: `wLifo_twin_breaks` (`QueueWrongFunction.lean:246-248`).
5. Decision 53: `twinSeq_satisfiable` (`QueueWitness.lean:159-167`): both sides reach the same nontrivial trace (full queue, `tryOffer` false, FIFO, `size`).

Verdict: FAITHFUL as a statement (low strength: sequential only; a linearizability statement is still open, as the wiki says).

## 4. Difftest claims

- 66,000 cases = 3 seeds x 22,000 (`raw/cats-effect/2026-11-15-queue-track-q-results.md`). Per op 52,941 = 17,651 + 17,598 + 17,692. The kind counts in the note add up to 52,941 (one `qNew` per scenario). The generator appends every op at least once per scenario (`difftest/py/gen.py`, `tpl_queue2`, final steps), so equal per-op counts are expected. At least 50,000 per op over 3 seeds: yes. I did not see a run log in the repository; the numbers are as reported.
- The Lean side runs the same `QueueFactory` terms as the statements (`tools/Difftest/Translate.lean:480-493`). The Scala side uses the real factories (`difftest/src/main/scala/cats/effect/difftest/Interp.scala:337-346`).
- No other op's coverage changed: the scenario has its own RNG (`difftest-queue2:{seed}:{i}`) and is appended after the base case (`difftest/py/gen.py`, `gen_case`). The base case is unchanged.
- No case deleted: commit `23f753e` deletes no file in `difftest/cases`; `queue2.jsonl` and `queue2.expected.jsonl` are new.
- No gate lowered: track Q did not change `difftest/py/selftest.py` thresholds; CI (`90d9a61`) only adds `queue2.jsonl` to the `cediff` and `drive.py check` lists.

## 5. Low findings

- D1 (forgeability, future): `isPublic` (`Std/QueueFactory.lean:142-154`) marks `QC.getState` public. Its result is the whole `State`, with the taker and offerer `Deferred`s (`Std/QueueConcurrent.lean:630-633`). The entry closures (`offerBody`, `takeBody`, ...) also accept any `.poll` argument. If a later statement adds user code with `WellFormed`, user code can run `.delay (QC.getState o).fn`, get a taker `Deferred` and complete it (a forged wakeup). No current statement uses `isPublic`. Fix before use: make `size` one public closure that returns only the size, and mark `getState` internal.
- D2: rows `std.Queue.UnsafeBounded.put/take/size` and `std.UnsafeUnbounded.put/take/size` are in the `Async` entries, but the model is a sequentially consistent list (a specification), not a mirror of the CAS code. They must not become `modelled` through these entries. The excluded helper rows (`std.Queue.UnsafeBounded.sequenceBuffer`, `head`, `tail`, ...: "internal: ... modelled as part of its public caller", `inventory/inventory.csv:3016-3021`) do not satisfy their reason under this model. Suggest `deferred: phase 9 (weak memory model)`.
- D3: the generator was broken on `main` between `81cabbb` and `1e84acb` (merge hunks inside the `WEIGHTS` and `CONFIG` dicts). The 66,000-case run was on the track Q branch before the merges. No queue difftest run is recorded on the merged generator. Also the track L latch scenario uses the same fresh-name base `g3.names = 20000` as `tpl_queue2`; both are separate `seq` items, so this is probably harmless, but nobody checked it.
- D4: track Q added no `selftest.py` coverage floor for the `q*` ops (tracks S and L added `V2S_MIN`, `V2L_MIN`). Not a lowered gate; a missing one.
- D5: `takerLiveness` sees only `blocked`, not a livelock (no observation). State this in the wiki article.

## 6. Carried context

Decisions 59-62 apply. No bug record is in scope. No refutation, so no fixed twin is needed.

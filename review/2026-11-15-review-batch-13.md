# Review batch 13 (2026-11-15): decision-63 batteries and the changed or new entries of batch 7.1

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the battery files, the witnesses, the Scala source at `v3.7.1` and the raw notes. It did not run a build, Lean, a test, sbt, a difftest or `gh`.
Reviewed commit: `05eecbb` (`origin/main`), checked out as branch `review13`. Diff base: `6299201` (the commit of batch 12).
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 58, 63, "Reviewer evidence", review log); `raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md`. When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `raw/`, `wiki/`, `inventory/`, `review/` or `test/`. `Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala` at `v3.7.1`.

## Summary

| Registry entry | Status | Change | Verdict |
|---|---|---|---|
| `std.Queue.Concurrent.takerLiveness` | open | H3 fix (`JoinsSucceeded`) | FAITHFUL as a statement (H3 closed) |
| `std.Queue.Async.takerLiveness` | open | W3 fix (`JoinsSucceeded`) | FAITHFUL as a statement (W3 closed) |
| `std.Queue.Concurrent.seqSpec` | open | new | FAITHFUL as a statement |
| `std.Queue.Async.seqSpec` | open | new | FAITHFUL as a statement |
| `std.Queue.{Concurrent,Async}.{noLoss,noDup,fifo,noDeadlock}`, `std.Queue.twinSeq` | open | harness: join event (tag 7) | FAITHFUL as statements (meaning unchanged; `twinSeq` stronger) |
| `std.Semaphore.noDeadlock` | open | H2 fix ("`Succeeded …` or `fatal`") | FAITHFUL as a statement (H2 closed) |
| `std.Mutex.lock.noDeadlock` | open | W2 fix (same form) | FAITHFUL as a statement (W2 closed) |
| other 6 track S entries | open / refuted | none in `Props` | unchanged (FAITHFUL) |
| `std.CountDownLatch.awaitCompletes` | open | new | **HOLLOW** (H4) |
| `std.CyclicBarrier.awaitCompletes` | open | new | **HOLLOW** (H4) |
| other 7 track L entries | open | mirror variants added (`v ≠ 0` only) | FAITHFUL as statements (meaning unchanged, `X ↔ XV 0` by `Iff.rfl`); latch battery incomplete (H4) |

HOLLOW reasons, one line each:

- H4 (`std.CountDownLatch.awaitCompletes`, `std.CyclicBarrier.awaitCompletes`): the success claim reads "if the root is done", and a root that ends `Errored` is done. A `CountDownLatch.apply` (or `CyclicBarrier.apply`) that always raises `IllegalArgumentException` stops every run with a root `Errored` before any fiber starts; all statuses stay `0`, so it meets this statement and every other statement of its structure. The latch battery has no `apply` row (decision 63 item 4). Term in C.4.

Open gap (status only, track Q works on it):

- G1 (`Synchronous`): `tryTake` `drops` breaks no registered statement (`Proofs/Phase7/QueueBatterySync.lean:11-13`). New in this batch: the same gap holds for `tryOffer` with an honest drop (answers `false`, no hand-off). The battery row "`tryOffer` drops" uses the dishonest drop (answers `true`), which `SeqSpec` catches; the honest drop passes every statement. Term in A.4.

Battery tables: Queue (Concurrent 18 rows, Async 18 rows, Synchronous 17 rows plus G1), Semaphore/Mutex (38 rows), latches (11 rows plus 1 meaningless): each listed row is the named variant of the named operation, and each break is kernel-checked against the registered statement or a form proven equal to it. Missing rows: the factories (`apply`, `bounded`, ...) in all three tables. For Queue and Semaphore/Mutex a raising factory breaks `SeqSpec` / `noDeadlock` by reading (low, L2/L3). For the latches it breaks nothing (H4). Low items L1-L4 below.

Batch 7.1 (30 entries): **no**. Latest verdict HOLLOW for 2 entries (`std.CountDownLatch.awaitCompletes`, `std.CyclicBarrier.awaitCompletes`, H4), FAITHFUL for the other 28. Apart from H4, the `Synchronous` try-operation gap G1 (now `tryTake` and `tryOffer`) stays open; by decision 63 item 4 the `Concurrent` battery is not complete until G1 closes.

---

## A. Queue (track Q)

### A.1 What I read

- `Props/Phase7/Queue.lean` diff `6299201..05eecbb` in full; `:1-135`, `:210-586` at `05eecbb`.
- `Proofs/Phase7/QueueBatteryDefs.lean`, `QueueBatteryConc.lean`, `QueueBatteryAsync.lean` (as a diff to `Conc`), `QueueBatterySync.lean`, all in full.
- `Proofs/Phase7/QueueWrongFunction.lean` and `QueueWitness.lean` diffs in full.
- `Model/Outcomes.lean:80-160` (`Summary.isResult`, `obs`, `runObsP`, `outcomesP`); `Model/Run.lean:46-62`; `Model/Step.lean:160-175`, `:1095-1112`.
- `Registry.lean` diff; `inventory/inventory.csv` diff.
- `Q:140-240` (factories, Scaladoc), `Q:240-380` (`Synchronous`), `Q:380-590` (`AbstractQueue`, `DroppingQueue`, `CircularBufferQueue`).
- `raw/cats-effect/2026-11-15-queue-review12-battery.md`.

### A.2 How a battery break relates to the registered statement

- `outcomesP` (`Model/Outcomes.lean:155`) is `∃ fuel cs, runObsP … fuel cs io = some o`. `obs` gives `some` only when `Summary.isResult` holds (`:87-89`, `:100-106`), so an out-of-fuel run never counts.
- So `runObsP … e 3000 [] root = some o` is exactly an element of `runs` with environment `e`. A theorem `specOK (battery op var) k op = some false` gives such an `o` on which the claim of `SeqSpec` is false. This is a break of `SeqSpec` with `henv` replaced by the wrong environment. The same holds for `liveB`, `noDupB`, `noLossB` (`QueueBatterySync.lean:25-31`).
- The Bool forms match the Props: `specB` (`QueueBatteryDefs.lean:122`) is the conclusion of `SeqSpec` (`Props/Phase7/Queue.lean:552`); `liveB` is `TakerLiveness` with `plan = []` (`JoinsSucceeded` with no plan cancel, and `QuietBlock` with `subM` = `SubMulti`); `noDupB`, `noLossB` are `NoDup`, `NoLoss`. No lemma states the Bool-Prop equality; I checked it by reading. Accepted (same pattern as `w1_breaks`).

### A.3 H3/W3 fix: `JoinsSucceeded` and the join event

- `QH.joinNext` now continues with `QH.joinRec o fs j js` (`Props/Phase7/Queue.lean:316`), which emits `(7, j, outcome)` (`:319`) and goes on.
- `TakerLiveness` (`:475`): `(Succeeded ∧ JoinsSucceeded o.out (takers scripts) plan) ∨ QuietBlock o`. `JoinsSucceeded` (`:471`): every joined script that the plan does not cancel has a `Succeeded` join event.
- Forgery (tag 7): no. `henv` (`:343`) answers only queue and `QH` closures; any other id is `illTyped`. Elements are data in fixed positions of events (`ev tag i x`); an element cannot emit. Only `QH.joinRec` emits tag 7. The battery closures (namespace 59) emit nothing.
- True for v3.7.1, by reading: a consumer runs only `take`s, which do not raise; a run that ends `Succeeded` joined each consumer; a consumer that the plan does not cancel ends `Succeeded`. The plan restriction is conservative.
- Wrong functions: `wSyncTakeRaises_breaks` (`Proofs/Phase7/QueueWrongFunction.lean:368`), mirror `syncTake_mirror_ok` (`:372`), kernel. `liveOKB'` (`:318`) is the Bool form with plan. The earlier rows now use `liveOKB'`.
- Decision 53: `LivenessWitness` now has `JoinsSucceeded` in the pass-on run (`Proofs/Phase7/QueueWitness.lean:110`), proved by `joins_of_events` (`:152`) from the kernel event list (consumer 0 `Canceled` by the plan, consumer 1 `Succeeded`). Complete.
- Effect on the other queue statements: `offeredOf`, `removedOf`, `removedBy`, `startedOf` ignore tag 7 (`:381-410`). `noLoss`, `noDup`, `fifo`, `noDeadlock` mean the same. `twinSeq` compares full traces; both sides now also show the join outcome, so it is stronger. The extra root step is harness code with no queue effect.

Verdicts: `std.Queue.Concurrent.takerLiveness` FAITHFUL as a statement (H3 closed). `std.Queue.Async.takerLiveness` FAITHFUL as a statement (W3 closed). The other 9 queue entries keep FAITHFUL.

### A.4 New entries `std.Queue.Concurrent.seqSpec`, `std.Queue.Async.seqSpec`

`SeqSpec fam` (`Props/Phase7/Queue.lean:552`): for every kind of the family and every script `s`, every run of `rootIO k [s] [] (.join [0])` has `events = (specRun (ruleOf k) [] s).1` and summary `blocked` if the spec blocks, else `Succeeded(())`.

1. MIRROR: yes. Same harness and same mirrors as the batch 11a/12 entries. One fiber only; the root only waits on the join, then records the join, cancels (no-op), and drains (`:310-330`).
2. PROPERTY: yes.
   - Scaladoc reading: FIFO (`Q:31-33`); `bounded` blocks `offer` when full; `dropping` ignores the next `offer` when full and does not block (`Q:184-195`); `circularBuffer` drops the oldest (`Q:212-222`); `unbounded` never blocks (`Q:152-159`); `synchronous` passes an element only with a partner on each side (`Q:140-148`). `specOp` (`:513`) encodes these rules.
   - Code details that the Scaladoc leaves open match v3.7.1: dropping `tryOffer` when full answers `false` (`onTryOfferNoCapacity` `Q:558`, and the `Async` twin); circular `tryOffer` answers `true` and drops the oldest (`Q:574-578`); `Synchronous` `tryOffer` alone answers `false` (`Q:289`), `size` is `0` (`Q:359`).
   - `ruleOf` (`:501`): `unboundedConc` is `block intMax` (the `Concurrent` `unbounded` is `bounded(Int.MaxValue)`); `bounded 0` is `sync` (outside `AsyncAny` anyway).
   - Families: `ConcAny` (`:424`) and `AsyncAny` (`:428`) keep the factory preconditions (`cap ≥ 1`, `1 < cap < 65534`). No other hypothesis.
   - Trace order: script events, then `(7, 0, Succeeded(()))`, then the drain `(4, 0, a)` for the rest of the buffer, as `specRun` (`:542`). A blocked `offer` has its `offerStart` event and nothing else, as the harness records it inside the mask before `poll`.
   - "One fiber only" is a real limit: `SeqSpec` says nothing about hand-off between fibers (see G1). This is a statement for sequential use, and the entry note says so. Accepted.
3. SETTLED: open.
4. Wrong functions: the batteries (A.5). "Always the first", "LIFO" and "never removes" also break it on two-element scripts (the `take` input `[offer 1, offer 2, take, size]`).
5. Decision 53: `seqSpec_satisfiable` (`Proofs/Phase7/QueueWitness.lean:228`): a nontrivial script on `boundedConc 2` and `bounded 2` with `twinEvents_spec` (`:221`) kernel-checked. Only the non-blocked branch; the blocked branch is reached by the `hangs` rows. Complete.
6. Forgery: none (A.3).

Verdicts: both FAITHFUL as statements.

### A.5 Battery tables (Queue)

`battery op var` (`Proofs/Phase7/QueueBatteryDefs.lean:92`) replaces the `IO` of one method where the harness builds the call (`offerPoll`, `opBody`); other closures go to `henv`. Variants (`wrongIO`, `:63`): raises `E77`; hangs `ioCont` whose body only reads the continuation (`wCall` tag 0, `:80-83`); drops `pure` of `()`, `true`, `0`, `None`; doubles `offer *> offer`, `take <* take` (tags 1-3).

`Concurrent` (`boundedConc 2`) and `Async` (`bounded 2`), `QueueBatteryConc.lean:18-85`, `QueueBatteryAsync.lean` (same rows):

| op | raises | hangs | drops | doubles | mirror |
|---|---|---|---|---|---|
| `offer` `[offer 1, size]` | SeqSpec | SeqSpec | SeqSpec (size 0) | SeqSpec (size 2) | `*_offer_mirror` |
| `tryOffer` `[tryOffer 1, size]` | SeqSpec | SeqSpec | SeqSpec (size 0) | SeqSpec (size 2) | `*_tryOffer_mirror` |
| `take` `[offer 1, offer 2, take, size]` | SeqSpec | SeqSpec | SeqSpec (took 0) | SeqSpec (size 0) | `*_take_mirror` |
| `tryTake` same input | SeqSpec | SeqSpec | SeqSpec (`None`) | SeqSpec (size 0) | `*_tryTake_mirror` |
| `size` `[offer 1, size]` | SeqSpec | SeqSpec | meaningless | meaningless | `*_size_mirror` |

Check: each variant is the named variant of that method; each row is kernel (`decide +kernel`); the mirror meets the same claim on the same input. Correct.

`Synchronous` (`QueueBatterySync.lean:44-93`):

| op | raises | hangs | drops | doubles |
|---|---|---|---|---|
| `offer` (`[[take],[take],[offer 1]]`, join `[0,1]`) | TakerLiveness (`started ⊄ offered`) | TakerLiveness | TakerLiveness (`offered ⊄ removed`) | NoDup (`[1,1]`) |
| `take` (`[[take],[offer 1]]`, join `[0]`) | TakerLiveness (join `Errored`) | TakerLiveness | NoDup (took 0) | TakerLiveness (blocked before record) |
| `tryOffer` | SeqSpec `[tryOffer 1]` | SeqSpec | SeqSpec (`true` ≠ `false`) | NoDup (`[[take],[take],[tryOffer 1]]`) |
| `tryTake` | SeqSpec `[tryTake]` | SeqSpec | **G1** | NoLoss (`[[offer 1],[offer 2],[tryTake]]`, plan `[(3,2)]`) |
| `size` | SeqSpec `[size]` | SeqSpec | meaningless | meaningless |

The inputs meet the hypotheses: producers/consumers only and `takers` = the join list for `TakerLiveness`; `synchronous ∈ ConcKeep` for `NoLoss`; any mode for `NoDup`. Mirrors: `sync_*_mirror`, kernel, same inputs. Correct.

**G1 (open, status only).** Track Q records `tryTake` drops as a gap. The same root cause (no statement claims that a try-operation meets a waiting partner) also lets an honest `tryOffer` drop pass. Term (read only, not run):

```lean
open QueueBattery in
def wSyncTryOfferFalse : UserEnv :=
  let f (id : Nat) (arg : Val) (v : View) : UserResult :=
    match QH.ofId? id, arg with
    | some (.opBody o i opv), .poll m p =>
      match Op.ofVal? opv with
      | some (.tryOffer x) => { out := .prog (.map (IO.applyPoll (.pure (.bool false)) m p) (QH.recTO i x).fn) }
      | _ => henv.callV id arg v
    | _, _ => henv.callV id arg v
  { call := fun id arg refs => f id arg { refs }, callV := f }
```

On `synchronous`, v3.7.1 hands the element to a waiting taker and answers `true` (`Q:274-289`). The wrong function always answers `false`. One fiber: the spec answer is `false` (`SeqSpec` holds). `NoDup`, `NoLoss`, `Fifo`: nothing is offered. `NoDeadlock`: `cancelAll` ends `Succeeded`. `TakerLiveness`: scripts are `offer`/`take` only. `twinSeq`: no `synchronous` pair. So it passes every registered statement. The fix that closes `tryTake` drops (a hand-off claim, for example: with a joined `take` waiting and no cancel, a `tryOffer` that runs after the taker registered answers `true`) must also cover `tryOffer`. The battery row "`tryOffer` drops" should use the honest drop (`false`) for `Synchronous` (and record both forms).

### A.6 Low items (Queue)

- L1: the battery runs only on one class per family (`BoundedQueue`, `BoundedAsyncQueue`). `DroppingQueue`, `CircularBufferQueue`, `UnboundedAsyncQueue`, `DroppingAsyncQueue` have their own `offer`/`take` code (for example `UnboundedAsyncQueue.take`). `SeqSpec` covers them by the same claim (any variant on a one-fiber script changes the trace or the summary), but no break is kernel-checked for them. Suggest the same 18 rows on `.unbounded` and `.dropping 2` (and `.circular 2`, `.droppingConc 2`).
- L2: factories (`bounded`, `dropping`, `unbounded`, `synchronous`, `circularBuffer`) and `mapK` have no rows and no "meaningless" note. By reading a factory that raises or hangs breaks `SeqSpec` at once. `tryTakeN`, `tryOfferN`, `mapK` are `todo` in the inventory (not modelled), so they are outside the battery for now. Add one note line.

## B. Semaphore and Mutex (track S)

### B.1 What I read

- `Props/Phase7/Semaphore.lean` diff in full; `:363-430`, `:487-580`, `:678-692`.
- `Proofs/Phase7/SemaphoreBatteryDefs.lean`, `SemaphoreBattery.lean` in full; `SemaphoreWitness.lean` diff and `:201-209`.
- `Model/Semaphore.lean:428`, `:563-566`; `Model/Run.lean:46-62`; `Model/Step.lean:160-175`, `:1095-1112` (`uncaught` only from `.local`).
- `Registry.lean` diff (track S notes); `raw/cats-effect/2026-11-15-semaphore-mutex-review12-battery.md`.

### B.2 `std.Semaphore.noDeadlock` (`Props/Phase7/Semaphore.lean:545`)

Conclusion: `(∃ v, Succeeded v ∧ availOf v = some (k + released as) ∧ ∀ i, OkJoined … → Succeeded record) ∨ ∃ e, fatal e`.

1. MIRROR: yes (unchanged).
2. PROPERTY: yes.
   - It rejects `Errored`, `Canceled`, `blocked`, `uncaught`, `aborted`. For v3.7.1 the root never raises: its steps (`cancel`, `join`, `releaseN`, `cede`, `available`, `count`) do not raise, a join returns the outcome, `uncaught` comes only from `IO.local` (`Model/Step.lean:1108`), which the harness does not use. A fatal base gives `fatal` (kept in the domain). So this is the real promise, the batch 12 fix.
   - H2 closed: `availRaises` (`Proofs/Phase7/SemaphoreBattery.lean:231`) = `available_raises` (`:151`), kernel.
   - H1 regression: `fatal_regression` now shows the `fatal` part (`Proofs/Phase7/SemaphoreWitness.lean` diff).
3. SETTLED: open.
4. Wrong functions: the battery (B.4).
5. Decision 53: `semNoDeadlock_satisfiable` reaches the `Succeeded` part (unchanged term; it builds with the new statement, as reported; I did not build).
6. Forgery: none (batch 12 B.2; `env behaved`, only `HS.joinRec` emits tag 62).

Verdict: FAITHFUL as a statement.

### B.3 `std.Mutex.lock.noDeadlock` (`:575`)

The same form: `(Succeeded(()) ∧ join records) ∨ fatal`. W2 closed: `lock_raises` (`SemaphoreBattery.lean:172`) breaks it directly (root `Errored`). MIRROR, SETTLED, decision 53 (`mutexNoDeadlock_satisfiable`), forgery: as batch 12. Verdict: FAITHFUL as a statement.

### B.4 Battery table (Semaphore, Mutex)

Construction (`SemaphoreBatteryDefs.lean`): `wrongEnv op var u = outer op var (Mutex.env (inner (harnessed u)))` (`:225`); the statements use `env u = Mutex.env (harnessed u)` (`Props/Phase7/Semaphore.lean:372`). `outer` changes only odd-id results: the harness closures that build the call (`acqRelBody`, `constRel`, `tryBody`, `:204-221`) or the library terms of `available`, `count`, `permit`, `lock` through `rw (repl …)` (`:156-192`). `inner` adds the `WL` closures (namespace 66), which are not in `semLib`. `wrong_even` (`SemaphoreBattery.lean:199`) proves that even ids (user code) are unchanged.

Claims: `c2` (`:254`), `c5` (`:261`), `c7` (`:268`), `c4` (`:272`) are the conclusions of statements 2, 5, 7, 4; `okJoinedB` is `OkJoined`. Hypotheses: `inputs_ok` (`SemaphoreBattery.lean:219`, `AllEnded`, `need ≤ k`); `lockDrops_wf` (`:211`, the `WellFormed` hypothesis of statement 4 for the wrong environment).

| op | raises | hangs | drops | doubles | mirror |
|---|---|---|---|---|---|
| acquire | stmt 2 | stmt 2 | stmt 2 | stmt 2 | `good_acquire` |
| acquireN | stmt 2 | stmt 2 | stmt 2 | stmt 2 | `good_acquireN` |
| release | stmt 2 | stmt 2 | stmt 2 | stmt 2 | `good_release` |
| releaseN | stmt 2 | stmt 2 | stmt 2 | stmt 2 | `good_releaseN` |
| tryAcquire | stmt 2 | stmt 2 | stmt 2 | stmt 2 | `good_tryAcquire` |
| tryAcquireN | stmt 2 | stmt 2 | stmt 2 | stmt 2 | `good_tryAcquireN` |
| available | stmt 2 | stmt 2 | n/a; wrong value: stmt 2 | n/a | `good_permit` (same input) |
| count | stmt 2 | stmt 2 | n/a; wrong value: stmt 7 | n/a | `good_permit`, `good_count_fifo` |
| permit | stmt 2 | stmt 2 | stmt 2 | stmt 2 | `good_permit` |
| lock | stmt 5 | stmt 5 | stmt 4 (`sched30`) | stmt 5 | `good_lock`, `good_lock_drops` |

All 38 rows are `decide +kernel` on `runObsP` (A.2 applies: a `some` result is an element of `outcomesP`). Each variant is the named variant (drops: `acquire` takes nothing, the harness still releases; `tryAcquire` answers `true` without taking; `permit` allocates nothing; `lock` makes a cell but does not enqueue it; doubles: `2n`, `permit` takes 2, `lock` enqueues twice). Correct.

Reads (`available`, `count`): "drops" (skip the effect) and "doubles" (apply the effect twice) have no meaning for a read: a read has no effect. The note says so (decision 63 item 1 asks only for that). The extra "wrong value" row (+1) is more than the rule asks. Is +1 a fair stand-in? For a constant offset, yes: statement 2 pins `available` to `k + released` and statement 7 pins `count` to `r - Σ ns`, so any constant wrong value breaks them on some input. But see O1: a read that is wrong only under contention passes.

Low L3: `Semaphore.apply`, `Mutex.apply` (factories), `mapK`, `in` have no row and no note. By reading "`apply` raises" now breaks statement 2 (root `Errored`). Add a note line.

### B.5 Other track S entries

`noLostPermit`, `atMostK`, `mutualExclusion`, `count.atRest` (CE-0060), `acquireN.fifo`, `semaphoreTwin`: no change in `Props/Phase7/Semaphore.lean` other than statements 2 and 5 (diff). Verdicts of batch 12 stand.

**O1 (observation, not a verdict change).** No registered statement reads `available` while a fiber waits. `available` is read only by the root at the end (`Props/Phase7/Semaphore.lean:273`), after every fiber ended. A wrong `available` that is correct when nobody waits and returns `p + 1` when the waiter queue is not empty (v3.7.1 returns the free count `p`, which is `0` then) passes statements 1-7 by reading. I did not check whether user code in statement 8 can read `available`. The row `std.Semaphore.available` (entry `noLostPermit`) is therefore covered only at rest. Suggest a read of `available` in the FIFO root (as `count` is read in `fifoRoot`), or drop the row from `noLostPermit`.

## C. Latches (track L)

### C.1 What I read

- `Props/Phase7/CountDownLatch.lean` diff in full and `:20-64`, `:180-335`; `Props/Phase7/CyclicBarrier.lean` diff in full and `:28-50`, `:286-320`.
- `Std/CountDownLatch.lean` and `Std/CyclicBarrier.lean` diffs in full.
- `Proofs/Phase7/LatchBattery.lean` in full; `Proofs/Phase7/LatchWitness.lean` lines with `run [p` (grep).
- `Registry.lean` diff (two new entries); `raw/cats-effect/2026-11-15-track-l-decision63-battery.md`.

### C.2 Did the mirror change for `v = 0`?

No. `releaseIO r v` and `awaitIO r v` test `v == 4/5/6` and `v == 8/9/10` first (`Std/CountDownLatch.lean:233`, `:241`); for `v = 0` they give the old terms. `relModify` tests `v == 7` first (`:291`); for `v = 0` the old branch runs. `awaitOf` now passes `v` to `awaitIO`; for `v ∈ {0, 1, 2, 3}` the term is the old one. `CyclicBarrier`: `awaitIO` (`Std/CyclicBarrier.lean:240`) and `now` (`:301`) are unchanged for `v = 0`. `BLam.neverK` is variant 1 (`Props/Phase7/CyclicBarrier.lean:247`), so it is not in `cbLib`; `neverK_not_public` (`LatchBattery.lean:231`), kernel. `CountDownLatch` `neverIO` reuses existing closures (`newDeferred`, `awaitingK 1`, `awaitSel`). So the 7 earlier statements mean the same.

### C.3 Variant-parametric forms

`cdlXV v` and `cbXV v` are the registered statements with `run … v`. `*_iff : X ↔ XV 0 := Iff.rfl` (`LatchBattery.lean:53-56`, `:162-164`) are kernel-checked definitional equalities. I compared the text of each `V` form with the registered form (`Props/Phase7/CountDownLatch.lean:361-392`, `Props/Phase7/CyclicBarrier.lean:335-357`): the only difference is the argument `v`. Each break is a theorem `¬ XV v` that instantiates the full statement with `AllWF` proved (`allWF_p_p`, `allWF_p_nil`, `allWF_p`). This is the strongest form of all three batteries.

### C.4 Battery table (latches)

| op | variant | `v` | breaks | input | mirror on the same input |
|---|---|---|---|---|---|
| `CDL.release` | raises | 4 | releaseTotal (blocked, completed 0, started 1) | `n=1`, `[p]`, `[p]`, fuel 400 | done (`awaitCompletes_sat`); `completed = started` not kernel-checked |
| `CDL.release` | hangs | 5 | releaseTotal | same | same |
| `CDL.release` | drops | 6 | noLostWakeup (blocked, started 1, status 1) | same | done, so not blocked (kernel, `awaitCompletes_sat`) |
| `CDL.release` | doubles | 7 | awaitNotEarly (status 2, started 1, `n=2`) | `n=2`, `[p]`, `[p]`, fuel 48 | not kernel-checked |
| `CDL.await` | raises | 8 | awaitCompletes (done, status 1) | `n=1`, `[p]`, `[p]` | status 2 (kernel, `awaitCompletes_sat`) |
| `CDL.await` | hangs | 9 | noLostWakeup | same | done (kernel) |
| `CDL.await` | drops | 10 | awaitNotEarly (status 2, started 0) | `n=1`, `[p]`, `[]` | not kernel-checked |
| `CDL.await` | doubles | - | meaningless (no effect on state) | - | - |
| `CB.await` | raises | 5 | awaitCompletes (done, waiting 1) | `cap=1`, `[p]` | not kernel-checked |
| `CB.await` | hangs | 6 | exactGenerations (blocked, waiting 1) | same | not kernel-checked |
| `CB.await` | drops | 7 | noEarlyTrip (passed 1, entered 1) | `cap=2`, `[p]` | not kernel-checked |
| `CB.await` | doubles | 8 | noEarlyTrip | same | not kernel-checked |

Each variant is the named variant: raises and hangs replace the whole operation; drops returns `()` with no state change; doubles decrements by 2 (for `CDL.release`, the same state change as two `release`s; for `CB.await`, one awaiter counts twice). `CDL.await` doubles is meaningless: `await` only reads the state. `mapK` has no row, with a reason (`LatchBattery.lean:28-30`).

**Missing row: `apply` (both latches). H4.** `apply` is a public operation and a row of every latch entry (`Registry.lean` diff and `:741-805`). The table has no `apply` row and no reason. A raising `apply` breaks nothing. Term (read only, not run), as a mirror variant like the others:

```lean
-- Std/CountDownLatch.lean:220 (variant 11, not Cats Effect code): `apply` always raises
def apply? (n : Nat) (v : Nat := 0) : Option IO :=
  if n < 1 || v == 11 then none
  else some (.flatMap (.map (.delay CLam.newDeferred.fn) (CLam.awaitingK n).fn) (CLam.refK v).fn)
-- Std/CyclicBarrier.lean:230 the same with `if cap < 1 || v == 9 then none`
```

With `none` the harness closure `afterCells` throws `iaeErr` (`Props/Phase7/CountDownLatch.lean`, `HLam.call` `.afterCells`; `Props/Phase7/CyclicBarrier.lean:217-219`), so the root ends `Errored(IAE)` before any awaiter or releaser starts. In every state the status list is all `0` and `started = completed = 0`. Then, for every input: `cdlAwaitNotEarlyV 11` (no status 2), `cdlNoLostWakeupV 11` (never `blocked`), `cdlReleaseTotalV 11` (`0 = 0`), `cdlAwaitCompletesV 11` (no status 1); `cbNoEarlyTripV 9` (`0 ≤ …`), `cbExactGenerationsV 9` (never `blocked`), the two cancel statements (`waiting = canceledIn = passed = 0`; I read their text at `Props/Phase7/CyclicBarrier.lean:321-332`), `cbAwaitCompletesV 9` (`waiting = 0`). v3.7.1 raises only for `n < 1` (`CountDownLatch.scala:57-60`, `CyclicBarrier.scala:59-62`); for `n ≥ 1` the root joins every fiber, ignores the outcomes, and ends `Succeeded(())`.
This is the H2 pattern of batch 12: the success claim admits a root `Errored`. The entries whose job is the success claim are the two `awaitCompletes` entries, so they are HOLLOW. Fix: in `cdlAwaitCompletes` / `cbAwaitCompletes`, for `1 ≤ n` (`1 ≤ cap`), a done root is `Succeeded(())` and no status is 1 (for `n = 0` the root is `Errored(IAE)`, the documented precondition). Add the `apply` row (raises; hangs; drops/doubles meaningless for a factory, with the reason) and a kernel break.

Low L4: the decision-63 note asks that the real mirror passes the same input. For 6 of 11 rows I found no kernel run of the v3.7.1 mirror on that input (table). By reading, the mirror passes each (for example `cap=2`, one awaiter: blocked, `passed = 0`). The smoke (`test/Phase7/LatchSmoke.lean`, 0 violations, as reported) covers random inputs, not these. Suggest `good_*` theorems as in tracks Q and S.

### C.5 New entries `std.CountDownLatch.awaitCompletes`, `std.CyclicBarrier.awaitCompletes`

`cdlAwaitCompletes` (`Props/Phase7/CountDownLatch.lean:361`): `AllWF` → every run whose root is done has no awaiter with status 1. `cbAwaitCompletes` (`Props/Phase7/CyclicBarrier.lean:335`): the same with `waiting = 0`.

1. MIRROR: yes (same harnesses as the 7 FAITHFUL entries of batch 11b).
2. PROPERTY: no (H4).
   - The root joins every fiber, so a done root means every awaiter fiber stopped. Status 1 is set inside `uncancelable` before `poll(await)`; a cancel gives status 3 (`onCancel`), a return gives 2. So status 1 at the end means `await` raised. A fatal error in user code gives `fatal`, not `done`. User code runs before the mask (`ws[j].attempt`) and cannot write the status cell. So the claim is "`await` never fails", true for v3.7.1 by reading (`await` is `state.get` and `signal.get` or `unblock.get`).
   - It is the companion success claim of decision 63 item 3. Stronger than the item asks: any cancels and user errors. No extra hypothesis.
   - Wrong-function test on the entry alone: "`await` returns at once" passes it; `awaitNotEarly`/`noEarlyTrip` catch that (sibling precedent).
   - **But "the root is done" includes a root `Errored`.** For `n ≥ 1` the v3.7.1 root always ends `Succeeded(())` when it is done (it ignores the join outcomes; `cancel` and `join` do not raise). The statement does not claim this, so a raising `apply` meets it and every sibling (C.4, H4). This entry is the companion success claim of its structure, so it must carry that claim.
3. SETTLED: open.
4. Wrong functions: `CDL.await_raises_breaks` (`LatchBattery.lean:98`), `CB.await_raises_breaks` (`:169`), kernel, against the full statement.
5. Decision 53: `CDL.awaitCompletes_sat` (`:121`: done, status 2), `CB.awaitCompletes_sat` (`:201`: done, passed 2). The only hypothesis is `AllWF`, proved. Complete.
6. Forgery: the harness closures `mark`, `incr` are not in `cdlLib`/`cbLib`: `harness_not_public` (`:128`, `:208`) proves that no library id decodes to a harness closure (general). `forged_mark`, `forged_incr` (`:147`, `:151`, `:227`) are single examples that a program naming them is not `progOK`. The general guarantee is `harness_not_public` plus `WellFormed` (a user program may name only library ids and user ids). Accepted.

Verdicts: both HOLLOW (H4).

The other 7 latch entries: their text did not change (C.2, C.3). A raising `apply` meets them too, but their own claims are about `await`/`release` and they were FAITHFUL in batch 11b. As in batch 12 (H3 siblings), they stay FAITHFUL as statements. The latch battery is incomplete until the H4 fix adds the `apply` row (decision 63 item 4).

## D. Gates and cases

- No difftest case file and no gate changed in the diff (`git diff --stat 6299201..05eecbb`: Lean files, `Registry.lean`, `inventory/inventory.csv`, `test/Phase7/LatchSmoke.lean`).
- D2a of batch 12 done: both `FailureSignal` rows now have `deferred: phase 9 (weak memory model)` (`inventory/inventory.csv` diff).

## E. What must change

0. H4 (track L): `cdlAwaitCompletes` and `cbAwaitCompletes` must claim a `Succeeded(())` root for `n ≥ 1` / `cap ≥ 1`; add the `apply` row (raises, hangs; drops/doubles meaningless for a factory, say why) with kernel breaks and `good_*` mirror runs. Re-review both entries.
1. G1 (track Q, open): a hand-off statement for `Synchronous` try-operations; it must reject both `tryTake` drops and the honest `tryOffer` drop (`wSyncTryOfferFalse`, A.5). Record the honest drop as a battery row.
2. L1: run the queue battery on one class per implementation (`unbounded`, `dropping`, `circular`, `droppingConc`).
3. L2, L3: one note line for factories, `mapK`, `in` in each table.
4. L4: kernel `good_*` runs of the v3.7.1 mirror for the 6 latch rows without one.
5. O1 (track S): read `available` while a fiber waits in some statement, or drop the `available` row from `noLostPermit`.
6. Rules (for the wiki): (a) for a try-operation, the "drops" variant is the honest one (it answers "nothing done": `false`, `None`); a dishonest drop (`true` with no effect) is easy to catch and hides the gap. (b) The battery includes the factories: a factory that raises must break a statement; a success claim conditioned on "the root is done" must also say the root `Succeeded`.

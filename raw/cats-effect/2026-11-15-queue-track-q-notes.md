# Phase 7 track Q notes: `Queue` mirrors (both families), difftest ops, statements

> Source: own Lean work (`CatsEffectInLean/Std/QueueConcurrent.lean`, `Std/QueueAsync.lean`, `Std/QueueFactory.lean`, `Props/Phase7/Queue.lean`, `Proofs/Phase7/QueueWitness.lean`, `Proofs/Phase7/QueueWrongFunction.lean`, `tools/QSmoke/Main.lean`), difftest runs (Scala runner on CE 3.7.1), read-only `gh search issues`; sources at v3.7.1: `std/shared/src/main/scala/cats/effect/std/Queue.scala:31-1206`, `UnsafeUnbounded.scala:23-113`, `QueueSource.scala:23-80`, `kernel/jvm-native/.../SyncRef.scala:25-100`, `kernel/.../Ref.scala:123-124`, `core/.../IO.scala:1353-1431`, `:1548`, `:1996-2163`, `core/.../IOFiber.scala:225-260`, `:1210-1266`, `tests/shared/src/test/scala/cats/effect/std/QueueSuite.scala:85-130`, `:787-890`
> Collected: 2026-11-15
> Published: 2026-11-15 (own research note)

## Facts from the source

- `Queue.bounded(n)` with an `Async` instance (always for `IO`): `1 < n < 65534` gives `BoundedAsyncQueue`; `n = 1` and `n >= 65534` give the `Concurrent` `BoundedQueue`; `n = 0` gives `synchronous`. `dropping(n)`: `1 < n < 65534` gives `DroppingAsyncQueue`, else `DroppingQueue`. `circularBuffer` is always `CircularBufferQueue` (no async variant). `unbounded` gives `UnboundedAsyncQueue`. (`Queue.scala:74-228`.)
- `assertNonNegative` / `assertPositive` throw before an `IO` exists (synchronous throw at call time). So `dropping(0)` and `circularBuffer(0)` are outside the `IO` model; the difftest format rejects them.
- The private `boundedForConcurrent`, `unboundedForConcurrent` (`BoundedQueue(Int.MaxValue)`), `droppingForConcurrent` are `private[effect]`. The difftest runner is in package `cats.effect.difftest`, so it calls them directly.
- `GenConcurrent[IO]` operations: `ref` = `IO(Ref.unsafe)` (a `SyncRef`), `deferred` = `IO(new IODeferred)`, `unit` = `Pure(())`, `void`/`as` = `Map`, `productR` = `FlatMap` with a strict argument. `Ref.flatModify` = `uncancelable(_ => flatten(modify(f)))` (no `SyncRef` override). `IO#ifM` = `flatMap(if (_) t else f)`.
- `BaseBoundedAsyncQueue#take` uses `F.cont` (body `G uncancelable { poll => lift(F delay {...}).flatten }`), not `asyncCheckAttempt`. `BoundedAsyncQueue#offer` uses `F.async`; the registration calls `k(EitherUnit)` itself when its retry succeeds, then returns `None` (so the masked `get` returns at once).
- `IOFiber.succeeded` chains `uncancelableSuccessK` (`masks -= 1`) and `unmaskSuccessK` (`masks += 1`) without a run-loop iteration in between (`IOFiber.scala:1258-1264`); the cancel check is at the top of each iteration (`:242`). So a value that leaves the inner `uncancelable` of `take` inside a user `poll` reaches the user's `flatMap` with no cancel point: the documented atomic pattern `uncancelable(poll => poll(q.take).flatMap(record))` cannot lose the element at that boundary. (`mapK` adds a step there: open issue #4483.)
- `BaseBoundedAsyncQueue#tryTakeN` notifies up to `back.length + 1` offerers (`loop(i)` runs while `i >= 0`): extra wakeups only.

## Model decisions

- Queue object = closure reference `Val.fn o` (decision 58 style). Its closure value holds the class, capacity and state cells. User code that holds the queue cannot reach the state `Ref` (a `Ref` inside a library closure is not available, `WF.avail`). The v1 mirror (`Std/Queue.lean`, CE-0003) gives user code `Val.ref` of the buffer, so user code could write the buffer directly; the new mirrors do not have this hole.
- Each lambda captures `this` as a field `Val.fn o`, as Scala lambdas capture `this`.
- An `F[...]` value inside a value (result of `modify`, of a `defer` thunk) is a descriptor; `flattenK` (`x => x`) builds the term. The strict argument of `*>` is rebuilt by `thenD d` (it reads no state).
- Every `Deferred.get` in the queues is built on a `Deferred` that the same call chain just made, so it reads `initial` (`IO.deferredGetOf d none`).
- The `Async` family is modelled under sequential consistency: each `F.delay` thunk is one atomic step (the CAS loops of `UnsafeBounded` and `UnsafeUnbounded` are not modelled). Recorded as a model simplification (plan Phase 7 item 3).
- The waiter lists reuse `Std.Queue.Takers` / `notifyOne` (cells with an id; `clear()` nulls the data).

## Difftest

- New format-v2 ops `qNew {kind, cap}`, `qOffer`, `qTryOffer`, `qTake`, `qTryTake`, `qSize`. Kinds: `bounded`, `dropping`, `circularBuffer`, `synchronous`, `unbounded`, `boundedConc`, `unboundedConc`, `droppingConc`. Type `queue2` in `typecheck.py` (separate from the v1 `queue` type, whose Lean value is a buffer cell).
- Generator: `tpl_queue2`, appended by `gen_case` with its own RNG (`difftest-queue2:{seed}:{i}`, `p_queue2 = 0.08` times the weight `tpl_queue2`), so no other op changes. Each scenario uses every queue op at least once; takes are plain, atomic (`uncancelable`/`poll`) or `timeout`; children are canceled or joined.
- Fixed cases `difftest/cases/queue2.jsonl` (222 cases, `gen_v2_queue.py`): 222 agree on the first run. Golden file `queue2.expected.jsonl`.
- Generated: `opcount.py --seeds 71 72 73 --n 22000 --boost tpl_queue2=11`: see the article for the counts.
- `selftest.py` passes with the generator change (blocked + fuel 22.7 % < 25 %).

## Statements and smoke

- 11 open statements (`Props/Phase7/Queue.lean`): per family `noLoss`, `noDup`, `fifo`, `noDeadlock`, `takerLiveness`, and `twinSeq` for both. Harness namespace 54; no user code, so no `WellFormed` hypothesis.
- Witnesses (decision 53), kernel-checked: `QueueWitness` (safety: consumer canceled while it waits; liveness: a waiting taker woken; twin: same nontrivial trace on both sides).
- Wrong functions (11, kernel-checked runs in `QueueWrongFunction`, random schedules in `qsmoke wrong`): each breaks its claim, the real mirror meets it on the same input.
- `qsmoke 300 20 1`: 600 harness inputs, 11,040 stopped runs, 0 violations. Longer runs: see the article.
- No counterexample found under sequential consistency. The design keeps elements on cancel: the `Concurrent` take re-enqueues nothing (offer always enqueues; a woken taker retakes), and `notifyNextTaker`/`notifyAnyway` pass on a wakeup that a canceled waiter got.

## Duplicate searches (read-only)

- `gh search issues --repo typelevel/cats-effect "Queue"` (60 results): open #4571 (take.timeout loses elements; CE-0003), #4483 (`Queue#mapK` violates atomicity), #2887/#2888/#2889/#2891 (performance), #1618 (laws for functor instances); closed #3998 (canceling an async take makes another take hang), #3603 (`Queue.synchronous` lost item), #3587 (synchronous flake), #3187 (MPSC race). No new bug candidate to compare.

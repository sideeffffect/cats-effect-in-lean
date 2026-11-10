# Queue.take.timeout in Lean: UnboundedAsyncQueue and timeoutTo mirror, CE-0003 refuted (own note)

> Source: own work in this repository (`CatsEffectInLean/Model/Codec.lean`, `CatsEffectInLean/Std/Queue.lean`, `CatsEffectInLean/Model/Timeout.lean`, `CatsEffectInLean/Props/Calibration/QueueTimeout.lean`, `CatsEffectInLean/Proofs/Calibration/QueueTimeout.lean`), Lean v4.35.0; Scala source read at Cats Effect v3.7.1: `std/shared/src/main/scala/cats/effect/std/Queue.scala:105-106`, `:160-167`, `:871-988`; `std/shared/src/main/scala/cats/effect/std/UnsafeUnbounded.scala:23-113`; `core/shared/src/main/scala/cats/effect/IO.scala:138-139`, `:590-591`, `:644-647`, `:795-860`, `:903-904`, `:1275-1297`, `:1353-1368`, `:1418-1431`, `:1560`, `:1692-1696`, `:1996-2104`, `:2198`; `kernel/shared/src/main/scala/cats/effect/kernel/Sync.scala:61-62`, `Async.scala:168`, `GenTemporal.scala:316-323`, `Outcome.scala:73-74`; `reproducers/CE-0003/Repro.scala` run with scala-cli
> Collected: 2026-11-10
> Published: 2026-11-10

## Which queue

- `Queue.unbounded[F, A]` matches `F` on `Async` (`Queue.scala:160-167`). `IO` is `Async`, so the reproducer uses `unboundedForAsync` = `F.delay(new UnboundedAsyncQueue())` (`Queue.scala:105-106`). The `Concurrent` queue (`BoundedQueue`, `Ref` + `Deferred`) is not used by `IO`.
- `UnboundedAsyncQueue` (`Queue.scala:871-988`): `buffer` and `takers` are two `UnsafeUnbounded` lock-free lists. `take` = `F uncancelable { poll => F defer { try F.pure(buffer.take()) catch { FailureSignal => ... } } }`. On an empty buffer it makes `var received`, `var result`, a `wait = F.asyncCheckAttempt { k => F delay { takers.put(k); retry buffer.take() ... } }`, `notifyAnyway = F delay notifyOne()`, and returns `(poll(wait) *> F.defer(if (received) F.pure(result) else poll(take))).onCancel(notifyAnyway)`.
- `UnsafeUnbounded.put` returns the cell as `clear`; `clear()` nulls the data but keeps the cell; `notifyOne` skips null cells (`Queue.scala:967-969`).
- `IOAsync` does not override `defer`: `Sync.defer` = `flatMap(delay(thunk))(x => x)` (`Sync.scala:61-62`).
- `IO.never` = `asyncForIO.never` = `async(_ => pure(Some(unit)))` (`Async.scala:168`), not `async(_ => pure(None))`.

## Model choices

- Library code is user code from the run loop's view (it is written over the public API). So `Queue` and `timeoutTo` are `UserEnv` closures, not new `RtFn` cases. No existing model file changed.
- `Fn.user` has only a `Nat` id. Closures capture run-time values (`poll`, `ContState`, `Ref`, outcome). `Model/Codec.lean` encodes them without loss: bit-interleaving pairing, list encoding, and a `Val` encoding. The older examples use `tag + 100 * a`, which is lossy for ids `≥ 100`; a `∀` statement needs a lossless encoding.
- First try of a list encoding with `2^a * (2b + 1)` is a bad idea: nested codes grow as towers of 2 (an element `42` gives `2^42`, nested again `2^(2^42)`). Bit interleaving keeps the size linear in the bits.
- Queue state: `Ref` cell `q` = buffer, `q + 1` = takers (`next` cell id + cells `(id, Option ContState)`). `received`/`result` = one new `Ref` cell (`none` / `some x`).
- One user call = one atomic step. The CAS loops of `UnsafeUnbounded` become single steps. The model has fewer interleavings than a JVM with many threads, the same as `TestControl` (one thread).
- `f(EitherUnit)` in `notifyOne` = `UserEffect.invokeCb s (right unit)` (`contCallback`).
- `timeoutTo` captures its source `IO`. A `Val` cannot hold an `IO`, so the source is a code and the caller gives `srcIO : Nat → IO` (here `Std.Queue.takeIO`).
- In `f.cancel *> f.join.flatMap(...)` the argument is built eagerly: `f.join` reads `_join` in the same call as `f.cancel`. The model captures the `join` snapshot as a `Val`.

## Property

`takeTimeoutNoLostElement`: for all `xs : List Nat`, timeouts `d`, sleeps `s`, and all pick schedules (`outcomes`), program A (`Queue.unbounded`; `q.take.timeout(d).start`; `IO.sleep(s)`; offer each `x`; `consumer.cancel`; `consumer.join`; `xs.length` times `tryTake`, each result emitted) that ends `Succeeded` emitted the elements of `xs` as a permutation (from a `Succeeded` join outcome and the `Some` results).

## Result

- `#eval` exploration: the FIFO schedule (no choices) loses the element: 15 tasks, 117 micro-steps, trace `[None, Canceled]` (newest first). Task order `f0 f1 f2 f3 [advance 1: t0] t0 f0 f2 f1 f4 f5 f1 f3 f5 f1 f0`.
- Putting `pick 1` at the 7th task (`f1` before `f2`) still loses: the cancel fibers `f4`/`f5` start but do not run before `f2` completes.
- Choices `pick 0` ×6, `pick 1`, `pick 1` (`f1`, then `f4` cancels `f2` before it runs) do not lose: trace `[Some(42), Canceled]`. So the statement tells lossy and lossless runs apart.
- `cx_run` (`decide +kernel`, 200 micro-steps) is fast: the whole proof module builds in about 1 s.
- `#print axioms takeTimeoutNoLostElement_refuted`: `propext`, `Quot.sound`.
- Reproducer (`scala-cli run reproducers/CE-0003/Repro.scala`, 3.7.1): A 328/500, B 37/500, `REPRODUCED CE-0003` (same as before).
- The FIFO model schedule is not the replay of one `TestControl` seed. `TestControl` seed 0 does not lose; seed 1 does. No mapping from seeds to model schedules exists yet.

## Not done

- No difftest support for queue ops (out of scope). The `Queue` mirror is not checked by the 50,000-case difftest gate. Only the reproducer agrees with it on this one shape.
- `tryOffer`, `size`, `Concurrent` queues, bounded and dropping queues, `timeoutAndForget`, `Duration.Inf` are not modelled.

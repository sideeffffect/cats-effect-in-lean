# Queue and timeout model (CE-0003)

> Sources: Cats Effect source at v3.7.1 (`Queue.scala:105-106`, `:160-167`, `:871-988`; `UnsafeUnbounded.scala:23-113`; `IO.scala:795-860`, `:1353-1368`, `:1418-1431`, `:1996-2104`; `Sync.scala:61-62`; `Async.scala:168`; `Outcome.scala:73-74`); own Lean work and scala-cli run, 2026-11-10
> Raw: [Queue and timeout notes](../../raw/cats-effect/2026-11-10-queue-timeout-notes.md); [Calibration reproducers notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md)

## Overview

The second refuted property. `Queue.take.timeout(d)` in a fiber that another fiber cancels loses an element. The model mirrors `UnboundedAsyncQueue` (the queue that `Queue.unbounded` gives for `IO`), `IO#timeout`/`timeoutTo` and `IO.never`, on top of the existing `RacePair`, `Sleep`, `_cancel` and `_join` mirrors. The FIFO schedule of the model already loses the element. Status of the record: draft, waits for review.

## Files

| File | Content |
|---|---|
| `Model/Codec.lean` | Lossless closure ids: bit-interleaving `pair`, `encList`, `Val.enc`, decoders (structural on fuel) |
| `Std/Queue.lean` | `QLam` (15 closures), `call`, `newIO`, `offerIO`, `tryTakeIO`, `takeIO`; `UnsafeUnbounded` as `Ref` cells |
| `Model/Timeout.lean` | `TLam` (11 closures), `timeoutIO src d`, `neverIO`, `fallbackIO`; source given by `srcIO : Nat → IO` |
| `Props/Calibration/QueueTimeout.lean` | Program A, `env` (namespaces 1 queue, 2 timeout, 3 program), `takeTimeoutNoLostElement` |
| `Proofs/Calibration/QueueTimeout.lean` | `cx_run` (`decide +kernel`), `takeTimeoutNoLostElement_refuted` |

No existing model file changed. Library code is written over the public API, so it is `UserEnv` code, not a new `RtFn` case.

## Mirror rules used

- `F` = `IOAsync`: `delay` = `Delay`; `uncancelable` = `Uncancelable`; `defer` = `flatMap(delay(thunk))(x => x)` (not overridden); `asyncCheckAttempt`/`async` = `IOCont(body)`; `*>` = `flatMap(_ => that)`; `poll(fa)` = `UnmaskRunLoop`.
- A thunk that returns an `IO` returns a `Val` code; the `x => x` function builds the `IO`. One run-loop iteration, as in Scala.
- Arguments of `*>` are built eagerly. In `timeoutTo`, `f.cancel` and `f.join` read the fiber fields in the same call (snapshot captured).
- Queue state: `Ref` `q` = buffer, `q + 1` = takers. Cleared taker cells stay in the list (`clear()` nulls the data); `notifyOne` skips them.
- `var received` / `var result` = one new `Ref` cell.
- Atomicity: one user call is one step (one thread, as `TestControl`).

## Property and counterexample

- `takeTimeoutNoLostElement`: for all `xs`, `d`, `s` and pick schedules, program A (`Queue.unbounded`; `q.take.timeout(d).start`; `sleep s`; offer `xs`; `consumer.cancel`; `join`; drain with `xs.length` `tryTake` calls) that ends `Succeeded` returns each element exactly once (`List.Perm`). No hypotheses. Promise: undisputed invariant "no lost element"; support `IO.scala:800-802`.
- Witness: `xs = [42]`, `d = 1000`, `s = 1`, FIFO (empty choice list). After `offer` wakes the `take` racer and `consumer.cancel` takes over the consumer, the racer takes `42` and completes; its race callback loses against the cancel (`IOFiber.scala:711-715`); the `racePair` finalizer cancels both children; `join` = `Canceled`, `tryTake` = `None`.
- A schedule that runs the cancel fiber of the racer first gives `Some(42)`: the statement is not trivially false.

## Gotchas

- `IO.never` is `async(_ => pure(Some(unit)))` (a finalizer `IO.unit`), not `pure(None)`.
- A `2^a * (2b + 1)` list code explodes for nested codes (towers of 2). Use bit interleaving.
- The FIFO model schedule is not a `TestControl` seed. `TestControl` seed 0 does not lose, seed 1 does.

## Open points

- No difftest support for queue ops. The `Queue` mirror is checked only by this one reproducer shape, not by the 50,000-case gate.
- Not modelled: `tryOffer`, `size`, bounded/dropping/circular queues, the `Concurrent` queues, `timeoutAndForget`, `Duration.Inf`.
- Program B of the reproducer (nested `timeout`, no outside cancel) is not stated in Lean.

## See Also

- [Bug history](bug-history.md)
- [Scheduler model (multi-fiber, replay)](scheduler-model.md)
- [SyncIO and syncStep model](syncio-and-syncstep-model.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Registry and audit](../methodology/registry-and-audit.md)

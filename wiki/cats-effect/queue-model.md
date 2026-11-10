# Queue and timeout model (CE-0003)

> Sources: Cats Effect source at v3.7.1 (`Queue.scala:105-106`, `:160-167`, `:871-988`; `UnsafeUnbounded.scala:23-113`; `IO.scala:795-860`, `:1353-1368`, `:1418-1431`, `:1996-2104`; `Sync.scala:61-62`; `Async.scala:168`; `Outcome.scala:73-74`); own Lean work and scala-cli run, 2026-11-10
> Raw: [Review 2 fixes notes](../../raw/cats-effect/2026-11-10-review2-ce0001-ce0004-notes.md); [Queue and timeout notes](../../raw/cats-effect/2026-11-10-queue-timeout-notes.md); [Calibration reproducers notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md)

## Overview

The second refuted property. `Queue.take.timeout(d)` in a fiber that another fiber cancels loses an element. The model mirrors `UnboundedAsyncQueue` (the queue that `Queue.unbounded` gives for `IO`), `IO#timeout`/`timeoutTo` and `IO.never`, on top of the existing `RacePair`, `Sleep`, `_cancel` and `_join` mirrors. The FIFO schedule of the model already loses the element. Status of the record: draft, waits for review.

## Files

| File | Content |
|---|---|
| `Model/Codec.lean` | The one closure codec (decision 31): `Val ↔ Nat` bit-string code, roundtrip theorem, `cloVal ns tag fields`, `libFn` (odd id), `userFn` (even id) |
| `Std/Queue.lean` | `QLam` (15 library closures, `toVal`/`ofFields`), `call`, `newIO`, `offerIO`, `tryTakeIO`, `takeIO`; `UnsafeUnbounded` as `Ref` cells |
| `Model/Timeout.lean` | `TLam` (11 library closures), `timeoutIO src d`, `neverIO`, `fallbackIO`; source given by `srcIO : Val → IO` (`src = Val.ref q`) |
| `Props/Calibration/QueueTimeout.lean` | Program A (`PLam`, user closures with even ids), `dispatch` (odd: namespace 1 queue, 2 timeout; even: namespace 3 program), `isLib`, `takeTimeoutNoLostElement` |
| `Proofs/Calibration/QueueTimeout.lean` | `cx_run` (`decide +kernel`), `cx_wellFormed`, `takeTimeoutNoLostElement_refuted` |

No existing model file changed. Library code is written over the public API, so it is `UserEnv` code, not a new `RtFn` case.

## Mirror rules used

- `F` = `IOAsync`: `delay` = `Delay`; `uncancelable` = `Uncancelable`; `defer` = `flatMap(delay(thunk))(x => x)` (not overridden); `asyncCheckAttempt`/`async` = `IOCont(body)`; `*>` = `flatMap(_ => that)`; `poll(fa)` = `UnmaskRunLoop`.
- A thunk that returns an `IO` returns a `Val` code; the `x => x` function builds the `IO`. One run-loop iteration, as in Scala.
- Arguments of `*>` are built eagerly. In `timeoutTo`, `f.cancel` and `f.join` read the fiber fields in the same call (snapshot captured).
- Queue state: `Ref` `q` = buffer, `q + 1` = takers. Cleared taker cells stay in the list (`clear()` nulls the data); `notifyOne` skips them.
- `var received` / `var result` = one new `Ref` cell.
- Atomicity: one user call is one step (one thread, as `TestControl`).

## Property and counterexample

- Closures capture handles as handle values (`Val.ref q`, `Val.cont s`, `Val.poll m p`, `Val.fiber c`), so `WellFormed` sees them in the id.
- `takeTimeoutNoLostElement`: hypothesis `WellFormed isLib [] env (progA xs d s)` (decision 27); for all `xs`, `d`, `s` and pick schedules, program A (`Queue.unbounded`; `q.take.timeout(d).start`; `sleep s`; offer `xs`; `consumer.cancel`; `join`; drain with `xs.length` `tryTake` calls) that ends `Succeeded` returns each element exactly once (`List.Perm`). No other hypotheses. Promise: undisputed invariant "no lost element"; support `IO.scala:800-802` and the `notifyAnyway` comment `Queue.scala:936-940`. Not `Queue.scala:365-366`: that comment is about the `Synchronous` queue (review batch 2).
- Witness: `xs = [42]`, `d = 1000`, `s = 1`, FIFO (empty choice list). After `offer` wakes the `take` racer and `consumer.cancel` takes over the consumer, the racer takes `42` and completes; its race callback loses against the cancel (`IOFiber.scala:711-715`); the `racePair` finalizer cancels both children; `join` = `Canceled`, `tryTake` = `None`.
- A schedule that runs the cancel fiber of the racer first gives `Some(42)`: the statement is not trivially false.
- The witness is well-formed (`cx_wellFormed`): the start program by `decide +kernel`; each `PLam` case by `call_ok` (uses `q` and `consumer` only after it got them; reads only the outcome of `consumer`). The proof needs the codec roundtrip `natToVal_valToNat`.

## Gotchas

- `IO.never` is `async(_ => pure(Some(unit)))` (a finalizer `IO.unit`), not `pure(None)`.
- A `2^a * (2b + 1)` list code explodes for nested codes (towers of 2). Bit interleaving also grows: its bit length doubles at each nesting level. The project now uses the linear bit-string code of `Model/Codec.lean` (decision 31); the CE-0003 proof went from 0.93 s to 1.11 s.
- The FIFO model schedule is not a `TestControl` seed. `TestControl` seed 0 does not lose, seed 1 does.

## Open points

- Difftest (format v1, [differential testing](../methodology/differential-testing.md)): of the 58,957 agreeing cases, `queueNew` 9.0 %, `queueOffer` 5.8 %, `queueTake` 8.3 %, `queueTryTake` 6.1 %, `timeout` 12.5 % (`tpl_queue` is the CE-0003 shape). The fixed case `q-ce0003-a-fifo` replays the Lean FIFO schedule on the real library: `left unit`, join `canceled`. Below the 50,000-per-op level. `timeoutTo` with a user fallback is not mirrored (1,043 unsupported cases), so row `core.IO.timeoutTo` is `todo` (review batch 2).
- Fixed twin (decision 39): not done. Draft PR #4710 rewrites `IOFiber` cancelation (no finalizer stack, `onCancelGraceful`), so no small twin exists. Plan in `bugs/CE-0003.yaml` (`lean.fixed_twin`).
- Not modelled: `tryOffer`, `size`, bounded/dropping/circular queues, the `Concurrent` queues, `timeoutAndForget`, `Duration.Inf`.
- Program B of the reproducer (nested `timeout`, no outside cancel) is not stated in Lean.

## See Also

- [Bug history](bug-history.md)
- [Scheduler model (multi-fiber, replay)](scheduler-model.md)
- [SyncIO and syncStep model](syncio-and-syncstep-model.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Registry and audit](../methodology/registry-and-audit.md)

# Review batch 2: verdicts on the 7 registry entries (own note)

> Source: independent read-only review in this repository (`CatsEffectInLean/Registry.lean`, `Props/*`, `Proofs/*`, `Model/{SyncStep,SyncIO,Run,Step,Fiber,Syntax,WellFormed,Outcomes,Resource,ResourceExamples,Timeout}.lean`, `Std/Queue.lean`, `bugs/CE-000{1,2,3}.yaml`, `reproducers/CE-000{1,2,3}/Repro.scala`, `difftest/cases/*.expected.jsonl`, wiki); Cats Effect source at v3.7.1 (`IO.scala`, `IOFiber.scala`, `SyncIO.scala`, `Resource.scala`, `Queue.scala`, `AsyncLaws.scala`, `MonadCancelLaws.scala`). Full review: `review/2026-11-10-review-batch-2.md`.
> Collected: 2026-11-10
> Published: 2026-11-10

## Verdicts

- FAITHFUL: `canceledAssociatesLeftOverFlatMap.IO`, `forceRCanceledShortCircuits.IO` (proven, low strength); `onCancelAssociatesOverUncancelableBoundary.IO` (open, statement); CE-0003 `takeTimeoutNoLostElement` (refuted).
- HOLLOW: `uncancelablePollIsIdentity.IO` (open; `Eqv` sees iteration counts); CE-0001 `syncStepIdentitySyncIO`; CE-0002 `resourceEvalPreservesUncancelable`.
- Phase 5 gate: FAIL (2 of 3 refuted entries HOLLOW). All three bugs are real; the replay difftest runs each witness on the real library with the same result.

## Findings

- CE-0001: the batch-1 problem (external cancel) is fixed. New: `¬P` stays true after the fix. (1) `WellFormed` lets user code read `Val.poll m s` fields, so a body that branches on mask id 0 (`idPollVal`) refutes any `syncStep` that calls the body in `SyncIO` (model artifact). (2) `WellFormed` allows `UnmaskRunLoop(io, 0, 0)` from `idPollVal`; the counter mask model then leaves the fiber masked (`Nat` subtraction, then `UnmaskK` remasks). This is the idpoll bug in user code. (3) Real asymmetry: `IO` `Error` checks fatal (`IOFiber.scala:265-269`), `SyncIO` `Error` does not (`SyncIO.scala:257-259`); `raiseError(fatal).handleErrorWith(_ => pure(1))` is `fatal` direct and `Succeeded(1)` stepped. A separate bug candidate.
- CE-0001 `possible_fix` (re-wrap in `uncancelable`, body still gets `IdPoll`) is not complete by reading: a `poll` used after an async boundary becomes a no-op.
- CE-0002: the two sides always differ by one run-loop iteration. With a started child and the 1024-iteration auto-yield, the trace sets differ (the documented decision-29 effect), so `¬P` holds for every implementation, also fix PR #4630. The witness itself is single-fiber and sound.
- CE-0003: mirror, statement and proof are sound. The FIFO witness schedule is replayed on the real library (`q-ce0003-a-fifo`: join `Canceled`, `tryTake` `None`). Caveats: `Queue.scala:365-366` is the `Synchronous` queue comment, not `UnboundedAsyncQueue`; row `core.IO.timeoutTo` is marked `modelled` but only the `TimeoutException` fallback is mirrored.
- Stale wiki: `syncio-and-syncstep-model.md:50` and `queue-model.md:47` still say there is no difftest.

## Fixes asked

1. Decision 29 (preemption choice in `Eqv`), then re-prove CE-0002.
2. `WellFormed`: poll values opaque; no `UnmaskRunLoop _ 0 _` in user programs.
3. File the fatal `raiseError` twin difference; state CE-0001 for non-fatal errors as the ordinary-input property.
4. For each refutation, check on a bounded domain that the fixed implementation satisfies the property.

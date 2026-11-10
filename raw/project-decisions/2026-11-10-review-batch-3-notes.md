# Review batch 3: verdicts on the 9 registry entries (own note)

> Source: independent read-only review in this repository (`CatsEffectInLean/Registry.lean`, `Props/*`, `Proofs/*`, `Model/{SyncStep,SyncStepFixed,SyncIO,WellFormed,Syntax,Outcomes,SchedP,EnumP,Resource,ResourceFixed,IOInstance}.lean`, `bugs/CE-000{1..4}.yaml`, `reproducers/CE-000{1..4}/Repro.scala`, wiki, review batches 1 and 2, fix notes); Cats Effect source at v3.7.1 (`IO.scala`, `IOFiber.scala`, `SyncIO.scala`, `Resource.scala`, `Queue.scala`, `UnsafeNonFatal.scala`, `AsyncLaws.scala`, `MonadCancelLaws.scala`); `series/3.7.x` `Resource.scala` (PR #4630); read-only `gh pr diff 4700 -R typelevel/cats-effect` (head 0c6f3c05). Full review: `review/2026-11-10-review-batch-3.md`.
> Collected: 2026-11-10
> Published: 2026-11-10

## Verdicts

- FAITHFUL: the two proven `MonadCancel` laws (low strength); `onCancelAssociatesOverUncancelableBoundary` and `uncancelablePollIsIdentity` (open, statements; the second was HOLLOW in batch 2, fixed by `EqvP`); CE-0001 (with caveats); CE-0002; CE-0003 (fixed twin by reading only); CE-0004 (low strength); `fatalTwin.nonFatal` (open, statement).
- HOLLOW: none.
- Phase 5 gate: PASS.

## Findings

- CE-0002: `EqvP` removes the iteration-count artifact. The PR #4630 twin (`Model/ResourceFixed.lean`) matches `series/3.7.x` `Resource.scala:464-530` branch by branch and satisfies the statement on 9 programs, 5 with a child fiber.
- CE-0001: the PR #4700 twin (`Model/SyncStepFixed.lean`) matches the PR diff case by case. `WF.PollOpaque` excludes the batch-2 poll-id body. Limit: `IO.applyPoll` fixes `Poll.apply` to the v3.7.1 poll kinds, so the twin family uses `applyPollT` and is outside the formal domain (`PollOpaque famEnv` is false for `σ (1, 0) = (0, 5)`). The twin also uses a `Deferred` cell id as the `DeferredPoll` identity, which user code can observe. The domain has only `limit = Int.MaxValue` and no `Ref`/`Deferred`/`start`.
- CE-0003: no Lean or Scala fixed twin (rule of decision 39 not met formally); by reading, a lossless `racePair` satisfies the statement.
- CE-0004: `SyncIO#to` is `interpret(this).uncancelable` (`SyncIO.scala:193-209`), so reproducer cases B and C are not literally the Lean program (one extra `uncancelable`).
- `progOK` allows a user `IO.Local`, which is `private[effect]` (`IO.scala:2318`).

## Fixes asked

1. Make `Poll.apply` a value-dispatched model primitive; restate `PollOpaque` with it; re-run the CE-0001 twin check in the formal domain, with the exact witness and small `limit` values.
2. CE-0003: run the reproducer on a `publishLocal` of PR #4710 (Scala-side twin).
3. CE-0002: state the cancelable direction; difftest the twin against `series/3.7.x`.
4. CE-0004: add the literal Lean program as a reproducer case.
5. Record in the wiki which observation model (`EqvP`, single-fiber step-only, replay) each property uses; note that `preempt` has no difftest.

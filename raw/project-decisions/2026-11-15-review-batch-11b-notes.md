# Review batch 11b notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-11b.md`. Commit reviewed: `9f8a482` (Phase 7 tracks S and L merged). Read only; no build, test or difftest was run. Read-only `gh api` GET calls only.

## Facts checked

- Mutex at v3.7.1 has only `ConcurrentImpl` over `LockQueue.lock` (`Mutex.scala:68-97`). Commit `8deb2fdabe` ("Re-implement Mutex using the shared LockQueue") is an ancestor of v3.7.1 (`gh api compare`: ahead, behind 0).
- PR #4648 (merge commit `df5b2c6834`, base `series/3.7.x`, merged 2026-08-22) is in v3.7.1 (`compare`: ahead, behind 0). Its body lists "2. count may transiently include them."
- v3.7.0 `Semaphore` cleanup was `waiting.filterNot(_ sameAs req)` + `releaseN(permitsAcquiredSoFar)` (`gh api contents?ref=v3.7.0`).
- The `Semaphore` and `LockQueue` mirrors follow the source branch by branch, including the lazy cancellation (a canceled non-head request stays queued; `reclaim` removes only the head).

## Findings

- H1 (HOLLOW): `std.Semaphore.noDeadlock` and `std.Mutex.lock.noDeadlock` claim that every stopped run ends `Succeeded`. The behaviour table `Base.err e` allows a fatal `e`. A fatal `raiseError` stops the whole run with `Summary.fatal` (`Model/Step.lean` `raised`, `Model/Sched.lean:120`), which is real Cats Effect behaviour. So both statements are false for every implementation. Counterexample: `bus = [.permit 0 (.err { code := 0, kind := .fatal })]`, `as = [.join 0]` (`k = 1` for the semaphore). The smoke used only non-fatal errors.
- W1 (weakness): "`acquireN(n)` always raises" (`n ≥ 2`) satisfies every `Semaphore` statement (`noLostPermit`, `noDeadlock`, `atMostK`, `fifo` vacuously: its spin never ends). The twin catches only `acquireN(1)`. Fix together with H1: a success clause in `noDeadlock`.
- CE-0060: Scaladoc promise read in context, public-API input, fixed twin (eager removal, v3.7.0 behaviour) meets the claim on its small domain, `maybe_intended` honest. FAITHFUL.
- `semaphoreTwin` is one direction; this is stated in the docstring and the registry. The docstring sentence "the converse is the same claim ...; the smoke test samples both" is wrong (L2).
- Track L: all seven entries FAITHFUL as statements. "Without cancels" in `noEarlyTrip`/`exactGenerations` is needed (race 1 makes both false for every correct barrier); the cancel case is covered by `cancelNoHang` (liveness) and `cancelRemoved` (safety). `as.length < cap` restricts the test shape, not the API; it keeps the interesting case (a canceled waiter that decremented must be re-incremented). The epoch-check race analysis (race 2) is correct.
- Forgery: none found. The harness `HLam.mark`/`HLam.incr` write cells by data number; this is safe only because no `HLam` is in `cdlLib`/`cbLib`. Track S public harness closures (`HS.newCell`, `HS.afterCell`) make an own nested harness with a new cell.
- Gates: no case deleted, no minimum lowered. L1: the one Semaphore difftest mismatch matches the known `rankOrder` fail-closed gap (review batch 9), but no run shows it. L3: no recorded difftest run after the merge fix `1e84acb`.

## Q5 view

Keep CE-0060 as low `doc-mismatch` with `maybe_intended: likely`. A trade-off that only a PR names is not documentation; the Scaladoc still promises the old meaning, and the state is not transient without a later release.

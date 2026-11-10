# Calibration reproducers CE-0001..CE-0003 (Phase 5, Scala side)

> Source: own experiments with scala-cli; upstream issues typelevel/cats-effect#4687, #4627, #4571 and PRs #4630, #4700, #4710 (read-only `gh`); source checkout `~/Projects/cats-effect` at v3.7.1
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

## Setup

- Reproducers: `reproducers/CE-000N/Repro.scala`, Scala 3.3.7, `cats-effect` and `cats-effect-testkit` 3.7.1. scala-cli picked JVM 17.
- Runner: `scripts/run_reproducers.sh`. `CE_VERSION=<v>` replaces `:3.7.1` in the `//> using dep` lines of a temporary copy.
- Snapshots: worktrees of `~/Projects/cats-effect` under `~/Projects/cats-effect-wt/` (the v3.7.1 checkout HEAD is not changed). `sbt "++3.3.7" kernelJVM/publishLocal stdJVM/publishLocal coreJVM/publishLocal kernelTestkitJVM/publishLocal testkitJVM/publishLocal`.
  - `series/3.x` = `origin/series/3.x` `de84c01f76` → version `3.7.1-89-de84c01`.
  - `series/3.7.x` = `origin/series/3.7.x` `2f9420145f` → version `3.7.1-15-2f94201`.
- Gotcha: `testkit` needs `kernel-testkit` at the same version. Publish `kernelTestkitJVM` too, or resolution fails.
- Gotcha: GPG signing times out during `publishLocal`. sbt only warns; the artifacts are published unsigned.
- All runs are deterministic: `TestControl` virtual time; CE-0003 uses fixed seeds `0 until 500` (seed string = base64 of the decimal seed, as `TestContext.apply(seed)` expects). Two runs gave the same counts.

## Results

| Id | Upstream | v3.7.1 | series/3.x | series/3.7.x |
|---|---|---|---|---|
| CE-0001 | #4687 | REPRODUCED (3/3) | REPRODUCED (3/3) | REPRODUCED (3/3) |
| CE-0002 | #4627 | REPRODUCED (2/2) | REPRODUCED (2/2) | NOT REPRODUCED (0/2; fix #4630 is there) |
| CE-0003 | #4571 | REPRODUCED (328/500, 37/500 seeds) | same | same |

## Promise quotes

- CE-0001: `AsyncLaws.syncStepIdentity` (`laws/shared/src/main/scala/cats/effect/laws/AsyncLaws.scala:84-88`): `F.syncStep(fa, limit).flatMap { case Left(fa) => fa; case Right(a) => F.pure(a) } <-> fa`. Scaladoc of `IO#syncStep` (`core/shared/src/main/scala/cats/effect/IO.scala:1154-1156`): "runs the original `IO` to its completion, the `limit` number of stages, or until the first stage that cannot be expressed with `SyncIO`".
- CE-0002: Scaladoc of `Resource.eval` (`kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala:986-987`): "Lifts an applicative into a resource. The resource has a no-op release. Preserves interruptibility of `fa`." Also `IO#timeout` (`IO.scala:807`): "If the source effect is uncancelable, a `TimeoutException` will never be raised."
- CE-0003: no Scaladoc says "take is lossless under timeout". Promise = undisputed invariant "no lost element". Support: `IO#timeout` (`IO.scala:800-802`): "The resulting effect will always wait for the source effect to complete (and to complete its finalizers), and will return the source's outcome over raising a `TimeoutException`." Internal comment `std/.../Queue.scala:365-366`: "it's the taker-cancelation situation where we must take extra care to ensure atomicity."

## Findings per bug

### CE-0001 (`syncStep`)

- Three cases: `Resource.use(_ => IO.never)` release; `IO.uncancelable(_ => sleep 1 s *> set)`; `IO.never.onCancel(set)`. Direct run: flag set. After `syncStep(Int.MaxValue)` and running the `Left` remainder: flag not set.
- Cause: `IO.scala:2390-2397`, branches guarded by `G.rootCancelScope == CancelScope.Uncancelable` (true for `SyncIO`). The `Left` result is not re-wrapped.

### CE-0002 (`Resource.eval`)

- Case A (issue form): `Resource.eval(IO.uncancelable(_ => IO.sleep(100.millis))).timeout(10.millis).use_` raises `TimeoutException`; the twin `Resource.make(fa)(_ => IO.unit)` does not.
- Case B (test from PR #4630): `make(pure 42).flatMap(_ => eval(IO.uncancelable(_ => IO.canceled)))`, allocated under `poll` of an outer `uncancelable`; continuation after `allocatedCase` is skipped (outcome `Canceled`, counter 0). With `make`: counter 1.
- Path for case A: `GenTemporal.timeoutTo` (`GenTemporal.scala:99`) → `Resource#race` (`Resource.scala:320`) → `F.racePair(this.allocatedCase, ...)` → `allocatedCase` `case Eval(fa) => fa.flatMap(...)` (`Resource.scala:526`) has no mask, so the loser fiber ends `Canceled` after `fa`.
- Fix on `series/3.7.x` only (not merged forward to `series/3.x`): confirmed by the run.

### CE-0003 (`take.timeout`)

- Program A: consumer `q.take.timeout(1.second).start`; sleep 1 ms; `offer(42)`; `consumer.cancel`; lost = outcome `Canceled` and `tryTake` empty. Lost in 328/500 seeds.
- Program B (issue form, nested timeouts, then sleep 1 s so the producer finishes): lost in 37/500 seeds. Without the final sleep, the count is too high (the producer has not offered yet), so the sleep is needed for an honest count.
- Cause: `IOFiber.scala:908-951` (`RacePair`): the async finalizer cancels both children; a child that already completed has its outcome dropped. `timeoutTo` (`IO.scala:850`) runs `racePair` under `poll`.
- Upstream says the cause is general (`inner.join.onCancel(inner.cancel)`), not `Queue`. A Lean model needs `racePair`, `sleep`, the async-finalizer protocol and external cancel; the `Queue` model can be small (an unbounded queue with one taker).

## Duplicate searches (read-only)

```
gh search issues "syncStep" -R typelevel/cats-effect
gh search prs "syncStep" -R typelevel/cats-effect
gh search issues "Resource.eval cancel" -R typelevel/cats-effect
gh search issues "Resource eval" -R typelevel/cats-effect
gh search issues "Queue take timeout" -R typelevel/cats-effect
gh search issues "racePair lost" -R typelevel/cats-effect
gh search issues "lossless cancelation" -R typelevel/cats-effect
gh search issues "timeout loses" -R typelevel/cats-effect
gh api repos/typelevel/cats-effect/issues/4571/comments
gh pr view 4630 -R typelevel/cats-effect --json body
```

Only the known upstream issues match. No other duplicates.

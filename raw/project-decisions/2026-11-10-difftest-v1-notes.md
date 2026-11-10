# Difftest format v1: `syncStep`, `Resource`, `Queue`, `timeout` (own note)

> Source: own work in this repository (`difftest/src/main/scala/cats/effect/difftest/{Ast,Interp,Json,Runner}.scala`, `difftest/py/{gen,typecheck,drive,coverage,selftest}.py`, `difftest/cases/gen_v1.py`, `tools/Difftest/{Prog,Closure,Translate,Env,Replay,Main,Tests}.lean`), Lean v4.35.0, runs against Cats Effect 3.7.1 (`difftest/run.sh`); mirrors read: `CatsEffectInLean/Model/{SyncStep,Resource,Timeout}.lean`, `CatsEffectInLean/Std/Queue.lean`; Scala sources read at v3.7.1 (`IO.scala:818-860`, `:1161-1162`, `:2173-2178`, `:2340-2402`, `Resource.scala:388-389`, `:464-531`, `:826-993`, `Queue.scala:105-106`, `:160-167`, `:871-988`)
> Collected: 2026-11-10
> Published: 2026-11-10

## What was built (decision 30)

- Format v1. Both runners accept `"v":0` and `"v":1`; a v1 op in a v0 line is a decode error. The output line has the `v` of the input line.
- New ops: `syncStep` (root only), `timeout`, `timeoutTo`, `queueNew`, `queueOffer`, `queueTake`, `queueTryTake`, `allocatedCase` over the resource nodes `rPure`, `rEval`, `rMake`, `rFlatMap`. Exact terms: `wiki/methodology/difftest-program-format.md`, section "Format v1".
- Root `syncStep`: Scala runs `I(e).syncStep(limit).unsafeRunSync()` on the caller thread before the runtime starts, then `Left(io) => io`, `Right(a) => IO.pure(a)`, throw `=> IO.raiseError(t)`. This is the shape of `SyncStepObs.steppedObs` and of `IOSuite.scala:2685`. Lean runs `SyncStep.steppedRest` and starts the scheduler on the heap that it left. Reproducer CE-0001 uses `.to[IO]`; the runner uses `unsafeRunSync` as the Lean property does.
- `TimeoutException` is error code 999998 (Lean `Timeout.timeoutErr`, code 10^6 = 999998 + 2). `reportFailure` prints `TimeoutException` without the message (the model keeps no duration text).
- Lean: the closures of the three mirrors run through `Env.dispatch`. Difftest closure ids are `Codec.nsFn 3 [Clo.encode c]` (even, namespace 3). Queue ids are namespace 1 (even), timeout ids namespace 2 (odd), `Resource` ids odd (`2 * valToNat c + 1`). Timeout and `Resource` ids can both be odd, so `libClo?` gives a harness error if both decoders accept an id (never seen).
- Queue handles: a queue is a model `Ref` cell (its buffer, `Std.Queue`). The internal events `refH`/`queueH` give Scala's `Ref` and queue handle numbers; the glue renumbers.
- Resource restriction: `REnv.bind/acquire/release` take no heap view, so `tr` builds resource programs with an empty view. A case where such a program reads state at build time (`Prog.eagerReads`) is `unsupported` (`resource-reads-state`). The generator gives resource programs no fiber or `Deferred` variables, so this never happens in generated cases.
- Not mirrored: `timeoutTo` with a user fallback (`Timeout.call` `.fold` always uses `fallbackIO`). Reported as `unsupported`. Fix in the model: a fallback code in `TLam.body`/`.sel`/`.fold` and a builder `fbIO : Nat → IO`, as `srcIO`.
- Previous attempt: an earlier agent run died with this work uncommitted. Its Scala and Lean changes and `gen_v1.py` were reviewed and taken over unchanged. Generator, type checker, driver, coverage, self-test, CI and docs are new.

## Model bug found: `idpoll` (not fixed; `CatsEffectInLean/` is out of scope)

- Scala: `SyncStep.interpret` calls an `uncancelable` body with `IdPoll`, and `IdPoll(fa) = fa` (`IO.scala:2390-2394`). No `UnmaskRunLoop` is made.
- Model: `SyncStep.interpret` passes `idPollVal = poll 0 0`. The mirrors turn `poll(fa)` into `.unmaskRunLoop fa m p` without a check for mask id 0:
  - `CatsEffectInLean/Model/Timeout.lean:160` (`TLam.body`) and `:178` (`TLam.embed`, `poll(IO.canceled)`);
  - `CatsEffectInLean/Model/Resource.lean:359` (`Clo.allocK`, the `Frame` branch, `poll(continue(...))`);
  - `CatsEffectInLean/Std/Queue.lean:274` (`takeDefer`) and `:327` (`recvDefer`). Not visible in runs: after `syncStep` stops at the `wait` of `take`, no other fiber can offer.
- Effect: the rest runs on the root fiber (id 0, `masks = 0`). `counterMaskModel.pollMatches 0` is true, so the model pushes `UnmaskK`, and `masks` becomes 1 when `fa` ends. The rest of the program runs masked; in Scala it does not.
- Shrunk cases (`difftest/corpus/known-idpoll-*.json`):
  - `syncStep(timeout(canceled, 1 ms), Int.MaxValue)`: Scala `canceled`, Lean `blocked` (the `poll(IO.canceled)` of `timeoutTo` is masked, then `IO.never`).
  - `syncStep(timeout(cede, 1000 ms), 3)` with an external cancel of the root: Scala `canceled`, Lean `succeeded`.
  - `syncStep(seq[allocatedCase(rFlatMap(rMake(cede, a, cede), b, rEval(cede))), canceled], Int.MaxValue)`: Scala `canceled`, Lean `succeeded`.
- Proposed fix: one helper, for example `pollIO io m p := if m == 0 then io else .unmaskRunLoop io m p` (as `Difftest.pollTerm`), used by every mirror that applies a `poll` value from user code. The CE-0001 refutation does not use these mirrors, so it is not affected.
- Driver: `drive.py` `KNOWN_MODEL_BUGS` entry `idpoll` (root `syncStep` whose program contains `timeout`, `timeoutTo` or `allocatedCase`). Such a mismatch goes to bin `known-model-bug`. `run` fails on it unless `--allow-known-model-bugs` is given. CI gives it (seed 3 of its 3 × 2,000 cases has one `idpoll` case); the corpus check pins the known bugs. A decision for the user: a known model bug in CI could instead fail CI until the mirrors are fixed.

## Numbers (2026-11-10)

- Fixed files: `syncstep.jsonl` 28, `resource.jsonl` 17, `queue.jsonl` 18 cases. All agree except `q-timeoutTo` (unsupported). All 7 fixed files: 116 cases, 113 agree, 3 unsupported.
- Calibration witnesses agree on both sides and show the bugs: `ss-ce0001-direct` `succeeded` with `set ref 0 true` vs `ss-ce0001-stepped` `canceled` (CE-0001 case 4); `res-ce0002-c-eval-plain` `canceled` vs `-masked` `succeeded` (CE-0002 case C; the `make` twin is `succeeded`); `q-ce0003-a-fifo`: the consumer is `canceled` and `tryTake` gives `None` (CE-0003 program A, FIFO: the element is lost).
- Generated, replay, seeds 1-6 × 10,000 (`--allow-known-model-bugs`): see the table in `wiki/methodology/differential-testing.md` ("Lean vs Scala results"). Per seed (agree / unsupported / known-model-bug): 1: 9,818 / 177 / 5; 2: 9,807 / 192 / 1; 3: 9,834 / 162 / 4; 4: 9,819 / 180 / 1; 5: 9,824 / 176 / 0; 6: 9,844 / 156 / 0. Total 58,946 agree, 1,043 unsupported (all `timeoutTo`), 11 `known-model-bug` (all `idpoll`), 0 mismatch.
- Before the generator fixes, seeds 1-5 × 10,000 gave 49,095 agree, 893 unsupported (`timeoutTo`), 12 `known-model-bug`, 0 mismatch.
- Static coverage (cases that contain the op, seeds 1-6 × 10,000): `syncStep` 9.2 %, `timeout` 12.5 %, `timeoutTo` 1.7 %, `queueNew` 9.0 %, `queueOffer` 5.8 %, `queueTake` 8.3 %, `queueTryTake` 6.1 %, `allocatedCase` 17.3 %, `rPure` 5.6 %, `rEval` 10.5 %, `rMake` 12.1 %, `rFlatMap` 9.3 %.
- Run events (`coverage.py`, seed 1 × 3,000): `TimeoutException` seen 2.1 %, a `Resource` release ran 1.5 %.
- Mutation check of the v1 glue (seed 1 × 10,000, reverted): `timeout` with `ms + 1` killed (307 mismatches); `syncStep` with `limit + 1` killed weakly (5 mismatches; most stepped programs stop at an async boundary before the limit matters).

## Generator bugs found and fixed

- A binder inserted around an already generated resource rest could shadow a variable that the rest uses (`fresh` with shadowing). Seen as a `TypeErr` in seed 6. Fix: the inserted binder gets a new name. 200,000 generated cases (seeds 1-20) are well-typed after the fix.
- The self-test shrink target (largest mock mismatch) needed an external cancel of a child. The shrinker now also remaps cancel handles to 0 and folds the picks before a cancel, so the self-test case shrinks to at most 4 nodes again.

## Open points

- `timeoutTo` needs a mirror of the user fallback.
- The `idpoll` bug must be fixed in the mirrors; then the corpus entries change to `expect: agree` and the `KNOWN_MODEL_BUGS` entry goes.
- Testcontrol mode is still Scala only (decision 15).

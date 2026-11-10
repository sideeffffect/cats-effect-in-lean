# Review batch 2 (2026-11-10): the 7 registry entries

Reviewer: independent agent. It did not write the code. It read the source, the proofs, the bug records, the reproducers and the wiki. It did not run a build, Lean, a test, scala-cli or `gh`.
Rubric: `AGENTS.md` section 5 and `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test). When unsure, the answer is no.
For a refuted entry, the wrong-function test is reversed: if a CORRECT implementation also makes `¬P` true, the entry is HOLLOW.
Scala source: `~/Projects/cats-effect` at `eb0cc258` (tag `v3.7.1`). Short names: `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`, `FIB` = `.../IOFiber.scala`, `SIO` = `.../SyncIO.scala`, `RES` = `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`, `Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala`, `L/` = `laws/shared/src/main/scala/cats/effect/laws/`. Lean paths are relative to `CatsEffectInLean/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO` | proven | FAITHFUL (low strength) |
| `laws.MonadCancelLaws.forceRCanceledShortCircuits.IO` | proven | FAITHFUL (low strength) |
| `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO` | open | FAITHFUL as a statement |
| `laws.MonadCancelLaws.uncancelablePollIsIdentity.IO` | open | HOLLOW as a statement |
| `core.IO.syncStep.syncStepIdentitySyncIO` (CE-0001) | refuted | HOLLOW |
| `kernel.Resource.eval.preservesUncancelable` (CE-0002) | refuted | HOLLOW |
| `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement` (CE-0003) | refuted | FAITHFUL |

All three bugs are real: each witness matches a reproducer case, and the replay difftest runs the same witness on the real library with the same result. The two HOLLOW verdicts are about the Lean statements: a fixed implementation also makes `¬P` true, through a model artifact.

**Phase 5 gate: FAIL** (CE-0001 and CE-0002 are HOLLOW).

---

## 1. `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO` (proven)

- verdict: FAITHFUL (low strength)

1. MIRROR: yes. No change since batch 1. `Props/IO/MonadCancelLaws.lean` uses `IOI.flatMap IOI.canceled (.user k)` against `IOI.canceled`. The run is the `IOFiber` mirror. `Canceled` branch `Model/Step.lean:1027-1035` = `FIB:532-540`. Citations re-checked: `L/MonadCancelLaws.scala:94-95`, `IO:961-962` (`void`), `IO:1501` (`canceled`). Difftest: replay, 150,000 agreeing cases before format v1, 58,957 after (`wiki/methodology/differential-testing.md:77-83`).
2. PROPERTY: yes. New hypotheses `WellFormedIO` on both sides (decision 27). The proof does not use them (`Proofs/IO/MonadCancelLaws.lean:149-150` applies the `_all` twin). So the proven statement is stronger than needed.
3. SETTLED: yes. `canceledAssociatesLeftOverFlatMap_proven : canceledAssociatesLeftOverFlatMap`.
4. WRONG-FUNCTION TEST: pass, as in batch 1. A no-op `Canceled` fails it. A constant semantics passes every equational law; the difftest excludes it.

Fixes: none.

## 2. `laws.MonadCancelLaws.forceRCanceledShortCircuits.IO` (proven)

- verdict: FAITHFUL (low strength)

1. MIRROR: yes. `IOI.forceR` = `IO:452-454` (`handleError(_ => ()).productR`). `IO:532-533`, `IO:903-904` re-checked.
2. PROPERTY: yes. Only lambda definitions and `WellFormedIO` (unused by the proof, `_all` twin).
3. SETTLED: yes. `forceRCanceledShortCircuits_proven : forceRCanceledShortCircuits` (`Proofs/IO/MonadCancelLaws.lean:200`).
4. WRONG-FUNCTION TEST: pass (`forceR a b := b` fails; `handleErrorWith` that catches cancelation fails).

Fixes: none. Note: no proven law runs `fa` or a finalizer yet.

## 3. `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO` (open)

- verdict: FAITHFUL as a statement

1. MIRROR: yes (`Props/IO/MonadCancelLaws.lean`, `uncancelable(_ => onCancel(fa, fin))` against `onCancel(uncancelable(_ => fa), fin)`; `Step.lean:1037-1052` = `FIB:542-583`).
2. PROPERTY: yes. Both sides do the same number of run-loop iterations (one `OnCancel`, one `Uncancelable`), so the iteration-count artifact of `Eqv` (section "Wider concerns", item 1) does not apply. The NB comment `L/MonadCancelLaws.scala:47-60` does not withdraw the law.
3. SETTLED: open, with a proof plan. OK.
4. WRONG-FUNCTION TEST: as in batch 1 (the law mainly tests the pop order of `OnCancelK` and `UncancelableK`).

Fixes: none for the statement.

## 4. `laws.MonadCancelLaws.uncancelablePollIsIdentity.IO` (open)

- verdict: HOLLOW as a statement

1. MIRROR: yes (`IOI.Lam.pollApply`, `Step.lean:1053-1058` = `FIB:585-602`).
2. PROPERTY: no. The forged-id problem of batch 1 is gone (`WellFormedIO`). The iteration-count problem stays: the left side does 2 more iterations, and the smoke test with a well-formed program (`fa = start(emit 9) >> emit 1 >> 508 flatMaps >> emit 2`) gives different outcome sets (`wiki/semantics/outcome-equivalence.md:71-76`). So no proof is possible with the current `Eqv`, and a refutation would not be a Cats Effect bug. The registry note says this (decision 29, not done).
3. SETTLED: open. Correct not to refute.

Fixes: do decision 29 (a preemption choice at any run-loop iteration in `Eqv`) first.

---

## 5. `core.IO.syncStep.syncStepIdentitySyncIO` (CE-0001, refuted)

- mirror: yes
- property: no (domain too wide: poll values are observable, fatal errors are in scope)
- settled: yes
- wrong-function test: fail
- verdict: HOLLOW

### 1. MIRROR: yes

`SyncStep.interpret` (`Model/SyncStep.lean:79-132`) follows `IO:2348-2402` branch by branch, same order: `limit <= 0` (`:83` = `IO:2350-2351`), `stepsUntilDefer <= 0` with `G.defer` (`:85` = `IO:2352-2353`), `Pure`, `Error`, `Delay`, `RealTime`, `Monotonic`, `Map`, `FlatMap`, `Attempt`, `HandleErrorWith`, guarded `Uncancelable` (`:117-125` = `IO:2390-2394`, body called with no `try`), guarded `OnCancel` (`:128-130` = `IO:2396-2397`), default `Left(io)` (`:132` = `IO:2399`).

Spot checks (all correct):

- `IO:1161-1162` `syncStep(limit) = IO.asyncForIO.syncStep[SyncIO, A](this, limit)`.
- `IO:2173-2178` `G.map(SyncStep.interpret(fa, limit, MaxSteps))(_.map(_._1))` = `SyncStep.syncStep` (`:248-249`).
- `IO:2341` `MaxSteps = 512` (`:53`).
- `FlatMap`: the inner `limit` comes from `Right((a, limit))`, `stepsUntilDefer` is the outer one: `.flatMapSel f steps` (`:105`, `:214-225`). Correct.
- `Attempt`: `.handleError(t => (t.asLeft, limit - 1).asRight)` uses the outer `limit` (`:109`, `:227-230`). Correct.
- `SIO:590-626`: `SyncIOSync` has no `map` and no `handleError` override, so the cats-core defaults apply. `SIO:257-259`: the `Error` case has no fatal check; mirrored at `Model/SyncIO.lean:338-339`.

Difftest: format v1 has a root `syncStep` op (`wiki/methodology/difftest-program-format.md:85`), with the same harness as Lean (`unsafeRunSync()` on the caller thread, then the selected `IO`). About 9.2 % of 58,957 agreeing cases (about 5,400) are `syncStep` cases; the fixed cases `ss-ce0001-direct` and `ss-ce0001-stepped` give `succeeded` and `canceled` on the real library (`difftest/cases/syncstep.expected.jsonl`). The mutation `limit + 1` was killed only weakly (5 mismatches, `differential-testing.md:90`). Stale wiki: `wiki/cats-effect/syncio-and-syncstep-model.md:50` still says the mirror has no difftest.

### 2. PROPERTY: no

Promise: `L/AsyncLaws.scala:84-88` and the Scaladoc `IO:1154-1160` ("runs the original `IO` ... until the first stage that cannot be expressed with `SyncIO`"). The law suite checks it only with `G = F = IO`, but the public method uses `G = SyncIO`; this reading is fair.

Schedule: `steps bs` only (decision 26). The batch-1 problem (external cancel) is fixed. Partial schedules give `outOfFuel`, which is no claim (`Model/Run.lean:113-114`), so a short schedule does not make a correct `syncStep` fail.

Problems in the domain (`WellFormed`, `Model/WellFormed.lean`):

1. **Poll values are observable.** `CallOK` (`WellFormed.lean:192-197`) lets `env.callV id arg v` depend on all of `arg`, also on the fields of `Val.poll m s`. The body gets `idPollVal = Val.poll 0 0` in `interpret` (`SyncStep.lean:57`, `:120`) and `Val.poll id fib` with `id ≥ 1` in the run loop (`Step.lean:1043-1046`). A well-formed body "`if m = 0 then emit 1 else emit 2`" makes the two sides differ for every `syncStep` that calls the body in `SyncIO`. Scala code cannot do this without reflection on the `Poll` object.
2. **User code can apply `idPollVal` as `UnmaskRunLoop(io, 0, 0)`.** `progOK` allows `.unmaskRunLoop p m s` when `poll m s` is held (`WellFormed.lean:137`), also for `m = 0`. On a fiber with `masks = 0` and id 0, `pollMatches` is true (`Model/Fiber.lean`, `counterMaskModel`: `m.masks == id`), `unmask` gives `0 - 1 = 0` in `Nat`, and the pushed `UnmaskK` then sets `masks = 1`. So the fiber stays masked. Scala: `IdPoll(io) = io` (`IO:2391-2393`). The idpoll fix (`Model/Syntax.lean:379`, `IO.applyPoll`) covers only the library mirrors, not user code. This is the idpoll model bug again, inside the quantified domain. Example (by reading, not run): stepped rest `UnmaskRunLoop(IO.unit, 0, 0) *> IO.cede *> IO.canceled *> emit 1` ends `Succeeded` with trace `[1]` in the model; Scala ends `Canceled`.
3. **Fatal errors are in scope** (`WellFormed.lean:169`, `.throw _ => True`; `IO.raiseError` of an `Err` with `kind := .fatal` passes `progOK`). See section 4.
4. Minor: a throw from the `Uncancelable` body in `interpret` is modelled as `IO.raiseError(e)` (`SyncStep.lean:266-271`). In Scala, `interpret` runs when `syncStep(limit)` is called (`IO:2177`), so the throw leaves `syncStep` itself, before any `SyncIO` exists. The model can hide a law failure here (a false negative, not a false positive).

Observation (summary, `Ref` cells, emitted values) over step-only schedules is adequate for a single fiber.

### 3. SETTLED: yes

- `syncStepIdentitySyncIO_refuted : ¬ syncStepIdentitySyncIO` (`Proofs/Calibration/SyncStep.lean:193`). The type is exactly `¬ P`.
- Witness `cxFa = IO.uncancelable(_ => IO.canceled *> flag.set(true))`, `limit = Int.MaxValue`. Direct: `Succeeded(())`, `flag = true` (`direct_run`, 6 `step true`). Stepped: rest `IO.canceled.flatMap(_ => flag.set(true))` for every fuel `≥ 6` (`rest_big`), and the closed set `reach` has no state with the direct observation (`reach_obs`, `exec_mem`). Proof is sound.
- Witness well-formed: `cx_wellFormed` (`:189`). It does not use the poll value.
- `bugs/CE-0001.yaml`: all fields of `AGENTS.md` section 6 are present. Outputs for v3.7.1, `series/3.x` (de84c01) and `series/3.7.x`. Duplicates with queries. 
- Reproducer: `reproducers/CE-0001/Repro.scala:82` prints `REPRODUCED CE-0001` as the last line. Case 4 (`:43-44`) is the same program. Harness differs: the reproducer uses `syncStep(...).to[IO]` inside a started fiber (`:48-52`), so it never runs `SyncIO.unsafeRunSync` (row `core.SyncIO.unsafeRunSync`). The difftest case `ss-ce0001-stepped` uses the Lean harness and agrees, so the witness is covered. Small difference: there the `Ref` is made inside the stepped program.

### 4. WRONG-FUNCTION TEST: fail

Correct (or fixed) implementations against `¬P`:

| Implementation | `¬P` still true? | Why |
|---|---|---|
| upstream fix PR #4700 as `possible_fix` describes it (re-wrap `Left` in `uncancelable`/`onCancel`; body still called with `IdPoll`) | yes | model artifact: a well-formed body that branches on the poll id (domain problem 1) |
| drop the two guarded branches (`Uncancelable`/`OnCancel` return `Left(io)`) | yes | real CE asymmetry, exotic input: `fa = IO.raiseError(fatal).handleErrorWith(_ => IO.pure(1))`. Direct: `IO` `Error` branch calls `onFatalFailure` (`FIB:265-269`; model `Step.lean:815`) → summary `fatal`. Stepped: `SyncIO` `Error` has no fatal check (`SIO:257-259`; model `SyncIO.lean:338-339`), the `SyncIO` `handleErrorWith` catches it → `Succeeded(1)`. |
| the first row plus a fatal check in `SyncIO`, and polls opaque | no (by reading) | no other artifact found: prefix heap, clock and view are the same on both sides (`SyncStep.lean:254-255`; `CallOK` hides the fiber list). |
| `syncStep = SyncIO.pure(Left(fa))` | no | stepped run is `fa` on the same heap |

So `¬P` does not depend on CE-0001: it stays true after the CE-0001 fix. The poll-id row is a model artifact, which makes the entry HOLLOW. The fatal row is a real, separate discrepancy (a bug candidate of its own, `maybe_intended` likely).

Also (note, not part of the verdict): `possible_fix` in `bugs/CE-0001.yaml` is not a complete fix by reading. Body `poll => IO.cede *> poll(IO.canceled)`: the continuation keeps `IdPoll`, so in the re-wrapped `uncancelable` rest, `poll(IO.canceled)` is a no-op (`Succeeded`), while the direct run is `Canceled`. Check the real PR #4700 before citing it as the fix.

### Fixes

1. `WellFormed`: make poll values opaque. Add a clause that `callV` is invariant under a renaming of poll ids (or forbid user code to read `Val.poll` fields), and forbid `UnmaskRunLoop _ 0 _` in `progOK` (user code applies a poll only through the `IO.applyPoll` meaning).
2. Fatal errors: record the `SyncIO` vs `IO` fatal asymmetry as its own bug candidate. For CE-0001, state the property for non-fatal errors (`AGENTS.md` section 6: "If only an exotic input refutes a property, also state and settle the property for ordinary inputs"), and say this in the property doc.
3. Re-prove the refutation (the witness is unchanged: it uses neither the poll value nor fatal errors).
4. Optional: model a throw from `interpret` at `syncStep(limit)` call time as a separate "no `SyncIO`" result, not `IO.raiseError`.
5. Update `wiki/cats-effect/syncio-and-syncstep-model.md` (difftest now exists).

---

## 6. `kernel.Resource.eval.preservesUncancelable` (CE-0002, refuted)

- mirror: yes
- property: no (the `Eqv` observation sees iteration counts)
- settled: yes
- wrong-function test: fail
- verdict: HOLLOW

### 1. MIRROR: yes

`Resource.loop` (`Model/Resource.lean:272-287`) = `RES:480-528`, same branch order: `Allocate` → `F uncancelable { poll => resource(poll) flatMap ... }` (`RES:485-513`); `Bind` → `Frame` (`:515-516`); `Pure` with `Nil` → `(v, release).pure[F]` (`:518-521`); `Pure` with `Frame` → `loop(head(v), ...)` (`:522-523`); `Eval` → `fa.flatMap(a => continue(Resource.pure(a), stack, release))` (`:526-527`, Lean `:287`). `allocatedCase` = `loop(this, Nil, _ => F.unit)` (`RES:530`, Lean `:291`).

Spot checks (all correct): `RES:986-987` Scaladoc "Preserves interruptibility of `fa`"; `RES:992-993` `eval = Eval(fa)`; `RES:507-510` `poll(continue(...)).onCancel(rel(Canceled)).onError{...}` = Lean `:350-360` (with `IO.applyPoll`, `rel(Canceled)` built eagerly as in Scala); `IO:605-606` `onError` = `handleErrorWith(... *> raiseError)` (`Clo.onErrorH`, `Clo.raiseK`); `RES:490` `rel2` is not mirrored (returns `notMirrored`), not used by the witness.

Difftest: `allocatedCase` 17.3 %, `rEval` 10.5 % of 58,957 agreeing cases; fixed cases `res-ce0002-c-eval-plain` (`succeeded(canceled)`) and `res-ce0002-c-eval-masked` (`succeeded(succeeded)`) agree with the real library.

### 2. PROPERTY: no

Promise: "Preserves interruptibility of `fa`" (`RES:986-987`), read as: for an uncancelable `fa = IO.uncancelable(_ => g)`, `alloc <-> IO.uncancelable(_ => alloc)`. The reading is fair: upstream merged fix PR #4630 into `series/3.7.x`, and the `make` twin keeps the mask. Only the uncancelable direction is stated, and the doc says so (`Props/Calibration/ResourceEval.lean:22-24`).

Hypotheses (`:55-60`): lambda definitions, the `allocatedCase` result, and `REnv.WellFormed` on both sides. These are fine.

The problem is the observation `Eqv` (`Model/Outcomes.lean:124-125`). The two sides always differ by one run-loop iteration (the outer `Uncancelable`). With a child fiber, the auto-yield every 1024 iterations then falls at different program points, and `Eqv` compares the emitted traces. The project already found this effect for well-formed programs and classed it "not a CE bug" (`wiki/semantics/outcome-equivalence.md:71-76`, decision 29, not done). `g` may start fibers: `REnv.WellFormed` (`Model/Resource.lean:417-421`) does not forbid `start` in `g`.

Example (by reading, not run; same mechanism as the documented smoke test): `g = start(emit 9) >> emit 1 >> n flatMaps >> emit 2`, with `n` such that `emit 2` is the last iteration before the auto-yield on the left side and the first one after it on the right side. Left: trace sets `{[1, 2], [1, 2, 9]}` (the root still has iterations after `emit 2`, so the child can run). Right: `{[1, 2], [1, 9, 2]}`. So `Eqv` fails.

### 3. SETTLED: yes

- `resourceEvalPreservesUncancelable_refuted : ¬ resourceEvalPreservesUncancelable` (`Proofs/Calibration/ResourceEval.lean:163`). The type is exactly `¬ P`.
- Witness `g = IO.canceled`. Left: one observation `Canceled` for every fuel and pick list (`lhs_runs_nil`, `lhs_runs_pick`, `runs_of_nil_pick`). Right: `Succeeded((), _ => F.unit)` at fuel 8 (`rhs_succ`). Sound. Single fiber, so the witness itself does not use the artifact.
- Witness well-formed: `alloc_wellFormed`, `rhs_wellFormed`.
- `bugs/CE-0002.yaml`: all fields present; outputs for v3.7.1, `series/3.x`, and `series/3.7.x` (with the fix: `NOT REPRODUCED`). `maybe_intended: Partly`, honest.
- Reproducer: last line `REPRODUCED CE-0002` (`reproducers/CE-0002/Repro.scala:77`). Case C (`:56-62`) is the same program (`lift(IO.uncancelable(_ => IO.canceled)).allocatedCase`, plain and masked, each in its own fiber). It compares the outcome kind; Lean compares the full observation. Match.

### 4. WRONG-FUNCTION TEST: fail

| Implementation | `¬P` still true? | Why |
|---|---|---|
| fix PR #4630 (`uncancelable(poll => poll(fa).flatMap(...))`) | yes | iteration-count artifact (section 2); the witness itself agrees on both sides (`Model/ResourceExamples.lean:159-163`) |
| over-mask: `Eval` → `uncancelable(_ => fa.flatMap(...))` | yes | same artifact |
| any implementation | yes | the two sides of the statement always differ by one iteration |

So `¬P` is true for every implementation. The theorem does not show the bug; only its proof does. HOLLOW.

### Fixes

1. Do decision 29: add a preemption choice at any run-loop iteration to the replay scheduler that `Eqv` uses. The witness is single-fiber, so the refutation should carry over.
2. Alternative until then: state the property over an observation that does not see iteration counts (for example: each side alone, no child-visible effects compared, or a hypothesis that `g` starts no fiber, marked as a model limit in the doc), and keep the full statement `open`.
3. Add the twin statement for the cancelable direction ("a cancelable `fa` stays cancelable"), so an over-masking `Eval` is caught.

---

## 7. `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement` (CE-0003, refuted)

- mirror: yes
- property: yes (with a caveat on the promise)
- settled: yes
- wrong-function test: pass
- verdict: FAITHFUL

### 1. MIRROR: yes

- `Model/Timeout.lean` mirrors `IO:818-823` (`timeout` → `timeoutTo` with `IO.defer(IO.raiseError(new TimeoutException))`) and `IO:850-860` (`IO.uncancelable { poll => poll(racePair(IO.sleep(d))) flatMap { ... } }`), branch by branch (`TLam.body`, `sel`, `embed`, `thenJoin`, `fold`). Detail that is correct: `f.cancel` and `f.join` are read when the `flatMap` function runs (`*>` takes `that` by value), so `thenJoin` captures the `join` snapshot (`snapVal (v.outcome f)`); this matches `FIB:197-206` (`cancel`/`join` return the current `_cancel`/`_join` field) and `FIB:1094-1095`.
- `IO.never` = `async(_ => pure(Some(unit)))` (`IO:1560`, `IO:2198`, `IO:1418-1431`); `neverBody`/`neverUnc`/`neverSel` follow `IO:1421-1426`.
- `Std/Queue.lean` mirrors `UnboundedAsyncQueue` (`Q:871-990`). Spot checks correct: `Q:879-881` `unsafeOffer`, `Q:894` `take = F uncancelable`, `Q:936-940` `notifyAnyway`, `Q:943-944` `(poll(wait) *> F.defer(...)).onCancel(notifyAnyway)`, `Q:949` `tryTake`. All poll sites use `IO.applyPoll`.
- `RacePair` (`Model/Step.lean:459-490`) = `FIB:908-950`: `FIB:908` `case 18`, `FIB:934-935` callbacks, `FIB:937-938` `scheduleFiber`, `FIB:940-946` the `cancel` finalizer. Correct.
- Difftest: `queueNew` 9.0 %, `queueTake` 8.3 %, `queueTryTake` 6.1 %, `timeout` 12.5 % of 58,957 agreeing cases; `racePair` and `sleep` 150,000 cases before v1. The fixed case `q-ce0003-a-fifo` replays the FIFO schedule on the real library: outcome `left unit` (`tryTake` = `None`) and join outcome `canceled` (`difftest/cases/queue.expected.jsonl`). So the Lean schedule is a real schedule of Cats Effect v3.7.1. Stale wiki: `wiki/cats-effect/queue-model.md:47` still says "No difftest support for queue ops".

### 2. PROPERTY: yes (caveat)

- Promise: "no lost element", an `AGENTS.md` section 3(b) invariant. Upstream issue #4571 is open with label bug; maintainers say the gap is "how racePair and cancelation work in general" (`bugs/CE-0003.yaml`, `maybe_intended: Partly`). Honest record; acceptable for calibration.
- Citation problem: `Q:365-366` ("taker-cancelation situation where we must take extra care to ensure atomicity") is the design comment of the `Synchronous` queue (`SyncState`, `Q:374`), not of `UnboundedAsyncQueue`. It does not support this property. The `IO#timeout` Scaladoc (`IO:800-802`) is about the timeout firing, not an external cancel. So the support is the general invariant only.
- Quantifiers: all `xs`, `d`, `s`, all fuel and pick schedules. The program is fixed (program A of the reproducer). For a refutation a narrow property is fine (the general invariant implies it).
- Hypothesis `WellFormed isLib [] env (progA xs d s)` is a type invariant; it holds for every parameter value.
- Observation: `returned` reads the join outcome and the `tryTake` results from the emitted trace (`Props/Calibration/QueueTimeout.lean:208-212`). Claim only when the root ends `Succeeded`. Adequate. The cut at root completion is safe here: `join` waits for the `racePair` cancel fibers (`FIB:940-946`).

### 3. SETTLED: yes

- `takeTimeoutNoLostElement_refuted : ¬ takeTimeoutNoLostElement` (`Proofs/Calibration/QueueTimeout.lean:255`). The type is exactly `¬ P`.
- Witness: `xs = [42]`, `d = 1000`, `s = 1`, empty choice list (FIFO), 200 micro-steps → `cxObs` (`cx_run`, `decide +kernel`): join `Canceled`, `tryTake` `None`. `cx_not_perm` closes it. `cx_wellFormed` proves the hypothesis.
- `bugs/CE-0003.yaml`: all fields present; outputs for v3.7.1, `series/3.x`, `series/3.7.x`; four duplicate queries.
- Reproducer: last line `REPRODUCED CE-0003` (`reproducers/CE-0003/Repro.scala:63`). Program A (`:35-43`) is the Lean program with the same values. The reproducer uses `TestControl` seeds (328 of 500 lose), and the Lean schedule is FIFO, not a seed; the replay case `q-ce0003-a-fifo` closes this gap.

### 4. WRONG-FUNCTION TEST: pass

| Implementation | `¬P` still true? | Why |
|---|---|---|
| lossless `racePair` finalizer (hands a completed child outcome to the caller; draft PR #4710 idea) | no artifact found (by reading) | this witness then gives `Succeeded(42)`, `returned = [42]`; the property is a safety claim over all schedules, so iteration counts can only remove schedules, not add a loss |
| `tryTake` always `None` | yes | expected: a broken `tryTake` also loses; the difftest covers `tryTake` |
| `take` that drops the element on cancel | yes | expected (a real loss) |

The schedule `pick 0 ×6, pick 1, pick 1` gives `Canceled` and `Some(42)` (proof doc), so the statement can tell a lossless run from a lossy one.

### Fixes (not blocking)

1. Remove `Q:365-366` from `promised_by` and the property doc, or say that it is about the `Synchronous` queue.
2. Row `core.IO.timeoutTo` is `modelled`, but only the `TimeoutException` fallback is mirrored (`timeoutTo` with a user fallback is `unsupported` in the difftest: 1,043 cases). Note the limit in the row or in the registry entry.
3. Update `wiki/cats-effect/queue-model.md` (difftest now exists).

---

## Wider concerns

1. **`Eqv` sees iteration counts (decision 29 is open).** Any law or calibration statement whose two sides differ in run-loop iterations is false for every implementation once a program can start a fiber. This blocks `uncancelablePollIsIdentity` and makes CE-0002 HOLLOW. Do decision 29 before more `Eqv` statements.
2. **Poll values are not opaque in `WellFormed`.** User code can branch on `Val.poll m s` and can build `UnmaskRunLoop(io, 0, 0)` from `idPollVal`, which the run loop treats as a real poll (the idpoll bug in user code). Every statement over `uncancelable` bodies inherits this.
3. **Fatal errors are in every domain.** `IO` and `SyncIO` treat `raiseError(fatal)` differently (`FIB:265-269` vs `SIO:257-259`). This is a real twin difference and a bug candidate. Decide the scope of fatal errors once, in the wiki, and file the candidate.
4. **Refutation strength.** A refutation should name a property that the fix makes true. For each refuted entry, add a short check that the fixed implementation satisfies the property on a bounded domain (as `fixed_lhs`/`fixed_rhs` do for one witness), not only that the witness changes.
5. **Stale wiki.** `wiki/cats-effect/syncio-and-syncstep-model.md:50` and `wiki/cats-effect/queue-model.md:47` still say there is no difftest for these mirrors.
6. **Difftest depth for the v1 mirrors.** About 5,000 to 10,000 agreeing cases per v1 op, not 50,000 per op; the `syncStep` limit mutation was killed by 5 cases only. Add more `syncStep` cases with `uncancelable`/`onCancel` bodies and polls.
7. **Batch-1 items still open.** Divergence is not observed (`Eqv` cannot see "sometimes hangs"); the single-fiber driver never runs children (CE-0001 statement); the proven laws are low strength.

**Phase 5 gate: FAIL** — CE-0001 HOLLOW (poll-id artifact and fatal asymmetry keep `¬P` true after the fix), CE-0002 HOLLOW (iteration-count artifact keeps `¬P` true for every implementation); CE-0003 FAITHFUL.

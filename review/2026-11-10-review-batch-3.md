# Review batch 3 (2026-11-10): the 9 registry entries

Reviewer: independent agent. It did not write the code. It read the Lean source, the bug records, the reproducers, the wiki, the earlier reviews and the fix notes. It did not run a build, Lean, a test or scala-cli. It ran read-only `gh pr view` / `gh pr diff` for typelevel/cats-effect PR #4700 (head `0c6f3c05`, open) to compare the CE-0001 twin with the PR.
Rubric: `AGENTS.md` section 5 and `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test, fixed-twin check). When unsure, the answer is no.
Scala source: `~/Projects/cats-effect` at `eb0cc258` (tag `v3.7.1`); fix branch `~/Projects/cats-effect-wt/series-3.7.x` (contains PR #4630). Short names: `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`, `FIB` = `.../IOFiber.scala`, `SIO` = `.../SyncIO.scala`, `RES` = `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`, `RES37` = the same file on `series/3.7.x`, `Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala`, `L/` = `laws/shared/src/main/scala/cats/effect/laws/`, `PR4700` = the PR #4700 diff of `IO.scala`. Lean paths are relative to `CatsEffectInLean/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO` | proven | FAITHFUL (low strength) |
| `laws.MonadCancelLaws.forceRCanceledShortCircuits.IO` | proven | FAITHFUL (low strength) |
| `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO` | open | FAITHFUL as a statement |
| `laws.MonadCancelLaws.uncancelablePollIsIdentity.IO` | open | FAITHFUL as a statement |
| `core.IO.syncStep.syncStepIdentitySyncIO` (CE-0001) | refuted | FAITHFUL (with caveats) |
| `kernel.Resource.eval.preservesUncancelable` (CE-0002) | refuted | FAITHFUL |
| `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement` (CE-0003) | refuted | FAITHFUL (fixed twin by reading only) |
| `core.SyncIO.runLoop.Error.fatalTwin` (CE-0004) | refuted | FAITHFUL (low strength) |
| `core.SyncIO.runLoop.Error.fatalTwin.nonFatal` | open | FAITHFUL as a statement |

The two batch-2 HOLLOW reasons are fixed:

- CE-0002: `EqvP` (preemption at any run-loop iteration) removes the iteration-count artifact. The PR #4630 twin satisfies the statement on 9 programs `g`, also with child fibers.
- CE-0001: poll values are opaque (`WF.PollOpaque`), user code cannot build `UnmaskRunLoop _ 0 _`, fatal errors are out of the domain (`NonFatalOnly`), and fatal errors are a separate bug (CE-0004).

**Phase 5 gate: PASS** (CE-0001, CE-0002, CE-0003 are FAITHFUL). The caveats below are not blocking, but CE-0001 needs fix 1 and CE-0003 needs a real fixed twin before the results are final.

---

## 1. `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO` (proven)

- verdict: FAITHFUL (low strength)

1. MIRROR: yes. `IOI.flatMap IOI.canceled (.user k)` against `IOI.canceled` (`Props/IO/MonadCancelLaws.lean:51-56`), = `L/MonadCancelLaws.scala:94-95` (checked). `IOI.void` = `map(_ => ())` (`IO:961-962`). Run: `IOFiber` mirror under `SchedP`.
2. PROPERTY: yes. Hypotheses: the lambda definition and `WellFormedIO` on both sides. The proof does not use `WellFormedIO` (`Proofs/IO/MonadCancelLaws.lean:315-322`, `_all` twin).
3. SETTLED: yes. `canceledAssociatesLeftOverFlatMap_proven : canceledAssociatesLeftOverFlatMap` (`:321`). Both sides have one observation, `canceledObs`, by state families of 13 and 8 states (`canceledThenP`, `canceledP`). The family method closes over `preempt` and `pick m` (`tickP_pick_single`).
4. WRONG-FUNCTION: pass. A no-op `Canceled` runs `fa`; then the left side differs. As before, `fa` never runs, so the law tests only the `Canceled` branch.

## 2. `laws.MonadCancelLaws.forceRCanceledShortCircuits.IO` (proven)

- verdict: FAITHFUL (low strength)

1. MIRROR: yes. `IOI.forceR = productR (handleError fa h) k` (`Model/IOInstance.lean:109`) = `IO:452-454` (checked: `handleError(_ => ()).productR(that)`). `L/MonadCancelLaws.scala:75-76` checked.
2. PROPERTY: yes. Only lambda definitions and `WellFormedIO` (unused).
3. SETTLED: yes. `forceRCanceledShortCircuits_proven` (`:335`), family of 19 states.
4. WRONG-FUNCTION: pass (`forceR a b := b` runs `fa`; a `handleErrorWith` that catches cancelation runs `fa`).

## 3. `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO` (open)

- verdict: FAITHFUL as a statement

1. MIRROR: yes (`Props/IO/MonadCancelLaws.lean:80-86` = `L/MonadCancelLaws.scala:61-62`).
2. PROPERTY: yes. With `EqvP` the statement does not depend on iteration counts. The NB comment (`L/MonadCancelLaws.scala:47-60`) is about the monad laws, not this law.
3. SETTLED: open, with a proof plan in the note. OK.
4. WRONG-FUNCTION: a run loop that pops `OnCancelK` and `UncancelableK` in the wrong order fails it.

## 4. `laws.MonadCancelLaws.uncancelablePollIsIdentity.IO` (open)

- verdict: FAITHFUL as a statement (batch 2: HOLLOW)

1. MIRROR: yes (`IOI.Lam.pollApply`, `FIB:554-602`).
2. PROPERTY: yes now. The batch-2 problem was the iteration count. With `EqvP` the documented difference (`fa = start(emit 9) >> emit 1 >> n flatMaps >> emit 2`) goes away: the right side reaches `[1, 9, 2]` with one `preempt` (`Model/EnumPExamples.lean`, `default_rhs_preempt`); exact sets agree for `n = 0..9` with thresholds 2/4. Poll ids are opaque (`WF.PollOpaque`), so a body cannot branch on its poll.
3. SETTLED: open. Correct (no proof for all `fa`).
4. WRONG-FUNCTION: a poll that does not unmask (`poll(fa) = fa` while masked) fails it for `fa = canceled >> emit 1`.

---

## 5. `core.IO.syncStep.syncStepIdentitySyncIO` (CE-0001, refuted)

- mirror: yes
- property: yes (with one encoding limit, see 4)
- settled: yes
- wrong-function / fixed twin: pass on the bounded domain, in a changed poll encoding
- verdict: FAITHFUL (with caveats)

### 1. MIRROR: yes

`SyncStep.interpret` (`Model/SyncStep.lean:79-132`) follows `IO:2348-2402` branch by branch. I checked these citations against the source:

| Lean | Scala | OK |
|---|---|---|
| `:83` `limit ≤ 0` → `Left(io)` | `IO:2350-2351` | yes |
| `:85` `steps ≤ 0` → `G.defer(interpret(io, limit, MaxSteps))` | `IO:2352-2353` | yes |
| `:104-106` `FlatMap`: inner `limit` from `Right`, outer `steps` | `IO:2368-2372` | yes |
| `:108-110`, `:229-232` `Attempt` handler uses outer `limit - 1` | `IO:2374-2380` | yes |
| `:112-115`, `:234-242` `HandleErrorWith` handler `interpret(f(t), limit - 1, steps - 1)` | `IO:2382-2388` | yes |
| `:117-125` `Uncancelable`: body(`IdPoll`), no `try`, same `limit`/`steps` | `IO:2390-2394` | yes |
| `:128-130` `OnCancel`: finalizer dropped | `IO:2396-2397` | yes |
| `:53` `MaxSteps = 512` | `IO:2341` | yes |
| `:248-251` `G.map(interpret(...))(_.map(_._1))` | `IO:2173-2178`, `IO:1161-1162` | yes |
| `SyncIO.lean:356-360` `Error`: no fatal check | `SIO:257-259` | yes |

Clock: `SyncIO` and `IO` read the same heap clock (`SyncIO.lean:375-378`, `Step.lean:963-965`). The prefix heap has no fibers; `CallOK`/`Agree` do not fix the outcome list length, so user code cannot see the difference (`WellFormed.lean:168-172`).

Difftest: about 5,400 `syncStep` cases in format v1 and the fixed cases `ss-ce0001-direct`/`ss-ce0001-stepped` agree (`wiki/cats-effect/syncio-and-syncstep-model.md:56`). Below 50,000 per op; the `limit + 1` mutation was killed by 5 cases only.

### 2. PROPERTY: yes

Promise: `L/AsyncLaws.scala:84-88` (checked) and the Scaladoc `IO:1153-1162` (checked). The public method uses `G = SyncIO`.

Hypotheses (`Props/Calibration/SyncStep.lean:127-132`):

- `initialRefsOK`, `WellFormed` with `H0 = refHandles refs`: type invariants.
- `WF.PollOpaque` (`WellFormed.lean:316-318`): justified. For every renaming `σ` that keeps mask id 0, a user call commutes with the renaming. I checked that it excludes the batch-2 body "`if m = 0 then emit 1 else emit 2`": with `σ (1, s) = (0, 0)`, the result on `IdPoll` must be the renamed result on the real poll, so the two branches must agree. It allows `poll(fa)` through `IO.applyPoll` (identity for mask 0, `UnmaskRunLoop` for mask ≥ 1). Scala reason: `Poll` has only `apply`; only reflection or `Object` methods can tell polls apart.
- `progOK` forbids `UnmaskRunLoop _ 0 _` (`WellFormed.lean:150`). This removes the user-code idpoll bug of batch 2.
- `NonFatalOnly` (`:94-100`): a documented scope. Maintainers said in #549 that the laws hold only for non-fatal errors. The interesting case of CE-0001 (mask loss) needs no error. The fatal case is filed as CE-0004 (`AGENTS.md` section 6, ordinary inputs). Not an assumption of the interesting case away.
- `eraseObs`: compares observations up to `Poll` identity. Fair: the two runs give the body different `Poll` objects by design.

Schedules: all `steps bs` of the single-fiber driver, no external cancel (decision 26). Fine for a single-fiber law. `outOfFuel`/aborts make no claim.

Small domain over-approximation (not blocking): `progOK` allows `.local f` with a user `f` (`WellFormed.lean:144`), but `IO.Local` is `private[effect]` (`IO:2318`). For v3.7.1 both sides start with the same local state, so it does not change this result.

### 3. SETTLED: yes

- `syncStepIdentitySyncIO_refuted : ¬ syncStepIdentitySyncIO` (`Proofs/Calibration/SyncStep.lean:214`). Type exactly `¬ P`.
- Witness `IO.uncancelable(_ => IO.canceled *> flag.set(true))`, `limit = Int.MaxValue`. Direct: `Succeeded(())`, `flag = true` (`direct_run`). Stepped: rest `IO.canceled.flatMap(...)` for every fuel ≥ 6 (`rest_big`); the 10-state closed set `reach` has no state with the direct observation (`reach_obs`). Sound.
- `cx_wellFormed` (with `cx_opaque`) and `cx_nonFatal` prove both hypotheses.
- `bugs/CE-0001.yaml`: all section-6 fields; outputs for v3.7.1, `series/3.x` (de84c01) and `series/3.7.x`; duplicates with queries.
- Reproducer: last line `REPRODUCED CE-0001` (`reproducers/CE-0001/Repro.scala:82`). Case 4 (`:43-44`) is the Lean witness. The reproducer runs `syncStep(...).to[IO]` in a fiber, the Lean harness runs `unsafeRunSync()` first; the difftest case `ss-ce0001-stepped` covers the Lean harness.

### 4. WRONG-FUNCTION and FIXED TWIN

Twin mirror (`Model/SyncStepFixed.lean`) against `PR4700` (read with `gh pr diff 4700`):

| PR #4700 | Twin | OK |
|---|---|---|
| `FlatMap(Local(Unmask), _)`: `interpret(ioc, limit, steps - 1)`, `Left(rest) => Left(deferred(rest))` | `:358-365` | yes |
| `Uncancelable(Bind)`: walk `bind.rest`, `steps - 1`, rewrap | `:342-347` | yes |
| `Uncancelable(body)`: `new DeferredPoll`, `try body(d)` (non-fatal → `raiseError`), `steps - 1`, rewrap in `Uncancelable(Bind)` | `:306-316` | yes |
| `OnCancel(ioa, fin)`: `steps - 1`, `Left(rest.onCancel(fin))` | `:352-355` | yes |
| `DeferredPoll.apply = Local(Unmask).flatten`; `Unmask`: `null` → `ioc`, else `poll(ioc)` | `:207-209`, `:230-237` | yes |
| `Bind(poll) = local.getAndSet(poll).flatMap(prev => (rest.attempt <* restore).rethrow)` | `:240-258` | yes |

Implementations against `¬P`:

| Implementation | `¬P` still true? | Why |
|---|---|---|
| PR #4700 twin | no, on the 10 programs (`SyncStepTwin.fixed_twin`) | the twin agrees with the direct run, also for polls after `IO.cede` (programs 2, 5, 6, 7), an escaped poll (7) and nested regions (5) |
| re-wrap only, body keeps `IdPoll` | yes | real defect of such a fix (program 2: `poll(IO.canceled)` after `cede` becomes a no-op) |
| `syncStep = SyncIO.pure(Left(fa))` | no | the rest is `fa` on the same heap |
| v3.7.1 | yes | fails programs 1, 4, 5, 6, 10 (`v371_fails`) |

The bounded check is sound (`Proofs/Calibration/StepCheck.lean`: fuel below `F` gives no claim, fuel `m + F` the same rest by `rfl`, closed state lists, one observation). The domain is meaningful for the mask/poll behaviour. But these limits remain:

1. **Poll application is encoded in user code.** `WF.PollOpaque` and `IO.applyPoll` fix `Poll.apply` to the two v3.7.1 kinds. A `DeferredPoll` (`Val.poll 0 (d+1)`) is the identity under `IO.applyPoll`. So the twin family uses another user-code encoding (`applyPollT`), and `famEnv` is not in the formal domain: with `σ (1, 0) = (0, 5)`, closure 22 gives `deferredApply 4 canceled` on the renamed input but `canceled` as the renamed result, so `PollOpaque famEnv` is false. The registered statement with the twin plugged in is therefore false through the encoding (any well-formed user code that applies the `DeferredPoll` through `IO.applyPoll`). This is an expressiveness limit of the model, not of v3.7.1: for v3.7.1 the encoding is exact. I accept the twin check as evidence, but the formal domain should not depend on the set of `Poll` kinds (fix 1).
2. The twin takes a fresh `Deferred` cell id for each `DeferredPoll` (`SyncStepFixed.lean:307-308`). User code sees the number of `Deferred` cells (`WellFormed.lean:55-57`, `Agree`), so a later `Deferred` allocation gets another id on the stepped side. A twin artifact; the domain has no `Deferred`.
3. Domain gaps: only `limit = Int.MaxValue`, no `Ref`, `Deferred` or `start`, no run of more than 512 steps (`G.defer` path), and the exact CE-0001 witness (with the `Ref` cell) is not in the family (program 1 uses `emit`). `WellFormed` of the family is not proven.

No artifact found that makes `¬P` true for a correct implementation in a faithful encoding. Verdict FAITHFUL; confidence 0.75.

### Fixes

1. Make `Poll.apply` a model primitive that dispatches on the poll value (for example an `IO` node or a library closure `applyPoll(pollVal, io)` that each implementation interprets), and state `PollOpaque` with it. Then re-run the twin check with the formal domain (`WellFormed` proven for the family).
2. Give `DeferredPoll` an identity that is not a `Deferred` cell id (a separate counter).
3. Add to the twin family: the exact CE-0001 witness (with `cxRefs`), `limit` 1 to 3 inside a region, a program with more than 512 steps, a `Ref` write in the region.
4. Optional (batch-2 item): model a throw out of `interpret` at `syncStep(limit)` call time as a separate "no `SyncIO`" result.

---

## 6. `kernel.Resource.eval.preservesUncancelable` (CE-0002, refuted)

- mirror: yes
- property: yes
- settled: yes
- wrong-function / fixed twin: pass
- verdict: FAITHFUL (batch 2: HOLLOW)

### 1. MIRROR: yes

`Resource.loop` (`Model/Resource.lean:272-287`) = `RES:480-528` (checked: `Allocate` → `F uncancelable { poll => resource(poll) flatMap ... }`, `Bind` → `Frame`, `Pure`/`Nil`, `Pure`/`Frame`, `Eval` → `fa.flatMap(a => continue(...))` at `RES:526-527`). `allocatedCase` = `loop(this, Nil, _ => F.unit)` (`RES:530`). Scaladoc `RES:985-993` checked ("Preserves interruptibility of `fa`"; `eval = Eval(fa)`).

Twin `Model/ResourceFixed.lean` against `RES37:464-530` (read from `~/Projects/cats-effect-wt/series-3.7.x`):

| `RES37` | Twin | OK |
|---|---|---|
| `:470` one `F uncancelable { poll => ... }` around the loop | `allocatedCaseFixed` (`:183`), `FClo.body` | yes |
| `:485-486` `resource(poll) flatMap` (no inner mask) | `loopF`, `.allocate` (`:100-109`) | yes |
| `:506-509` `(poll(F.unit) >> continue(...)).onCancel(...).onError(...)`, `>>` by name | `allocK`/`thenK` (`:151-166`) | yes |
| `:524-525` `poll(fa).flatMap(a => continue(...))` | `:121-124` | yes |

Difftest: `allocatedCase` 17.3 %, `rEval` 10.5 % of 58,957 agreeing cases; fixed cases `res-ce0002-c-eval-plain`/`-masked` agree. The twin has no difftest (see fix 2).

### 2. PROPERTY: yes

Promise: "Preserves interruptibility of `fa`" (`RES:986-987`), read as `alloc <-> IO.uncancelable(_ => alloc)` for `fa = IO.uncancelable(_ => g)`. The reading is supported by upstream: PR #4630 is merged into `series/3.7.x`, its test is reproducer case B (a self-cancel inside an uncancelable `fa`, the same mechanism as the witness), and the `Resource.make(fa)(noop)` twin passes case C on v3.7.1.

Note on the reading: by this definition, `fa.map(identity)` is also "not uncancelable" for `g = IO.canceled` (the pending self-cancel is seen at the next unmasked iteration, `FIB:224-244`, `FIB:1258-1264`). So the property really says "`Resource.eval` must not add an unmasked step after `fa`". Upstream agrees that this is the fix, so it is acceptable.

Hypotheses: lambda definitions, the `allocatedCase` result, `REnv.WellFormed` on both sides. Type invariants only.

Observation `EqvP` (`Model/Outcomes.lean:156-163`): all fuel, all `PChoice` lists. `preemptRun` (`Model/SchedP.lean:62-71`) = the auto-yield of `FIB:233-238` at any iteration; the resume uses fresh counters (`FIB:1457-1461`), and the `shouldFinalize` check is at every iteration (`FIB:242`), so a preemption adds no cancelation point. No outside cancel. Sound as a model of the multi-threaded runtime (not of `TestControl`; the witness is single-fiber, so this does not matter for the refutation).

Only the uncancelable direction is stated (batch-2 fix 3 not done): an over-masking `Eval` (`uncancelable(_ => fa.flatMap(...))`) also satisfies the statement. This does not weaken the refutation.

### 3. SETTLED: yes

- `resourceEvalPreservesUncancelable_refuted : ¬ resourceEvalPreservesUncancelable` (`Proofs/Calibration/ResourceEval.lean:142-145`). Type exactly `¬ P`.
- Witness `g = IO.canceled`: exact sets `{Canceled}` and `{Succeeded((), _ => F.unit)}` (`lhs_outcomesP`, `rhs_outcomesP`, `checkNotEqvP`). `alloc_wellFormed`, `rhs_wellFormed` include `r_opaque`.
- `bugs/CE-0002.yaml`: all fields; outputs v3.7.1, `series/3.x`, `series/3.7.x` (`NOT REPRODUCED` with the fix).
- Reproducer: last line `REPRODUCED CE-0002` (`reproducers/CE-0002/Repro.scala:77`); case C (`:56-62`) is the witness.

### 4. WRONG-FUNCTION and FIXED TWIN: pass

| Implementation | `¬P` still true? | Why |
|---|---|---|
| PR #4630 twin | no, on 9 programs `g` (`ResourceEvalFixed.fixedTwin_holds`) | exact `EqvP` sets, 34 to 322 states, including 5 programs with a child fiber (the batch-2 artifact) |
| v3.7.1 | yes for the 3 self-cancel `g`, no for the other 6 (`ResourceEvalFixedOld.lean`) | the statement separates the bug from the fix |
| `Eval` → `fa.map(...)` | yes | expected: the same unmasked step as v3.7.1 |

The check method (`exploreP`, `ClosedP`, `pathsOK`, `eqvP_of_checkNotEqvP`) is sound by reading. The domain is fair: it is the set that broke batch 2, plus error and success.

### Fixes (not blocking)

1. Add the cancelable direction ("a cancelable `fa` stays cancelable"), so an over-masking `Eval` fails.
2. Difftest the twin against a `publishLocal` of `series/3.7.x` (2f94201): the fix is merged there, so the twin can be checked on the real code.
3. Add to the twin family: `g` with a poll of its own body (`IO.uncancelable(p => p(IO.canceled))`), `g = IO.never`/sleep.

---

## 7. `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement` (CE-0003, refuted)

- mirror: yes
- property: yes
- settled: yes
- wrong-function: pass by reading; fixed twin: not done
- verdict: FAITHFUL (fixed twin by reading only)

### 1. MIRROR: yes

Checked: `IO:818-823` (`timeout` → `timeoutTo` with `TimeoutException`), `IO:850-860` (`uncancelable { poll => poll(racePair(IO.sleep(d))) flatMap ... }`), `FIB:908-950` (`RacePair`: two children, callbacks, `scheduleFiber`, the `cancel` finalizer that cancels and joins both), `Q:894` (`take = F uncancelable`), `Q:936-944` (`notifyAnyway`, `(poll(wait) *> ...).onCancel(notifyAnyway)`). The model sites are as in batch 2. The citation `Q:365-366` is gone; `promised_by` now says why. Row `core.IO.timeoutTo` is no longer listed (registry note).

Difftest: fixed case `q-ce0003-a-fifo` replays the Lean FIFO schedule on the real library (join `canceled`, `tryTake` `None`).

### 2. PROPERTY: yes

"No lost element" (`AGENTS.md` 3b), for program A, all `xs`, `d`, `s`, all replay schedules (`outcomes`, `Props/Calibration/QueueTimeout.lean:220-225`). Hypothesis `WellFormed isLib [] env (progA ...)`: a type invariant. The `IO:800-802` Scaladoc supports it. Program A = reproducer program A (`reproducers/CE-0003/Repro.scala:35-43`, same order: start consumer, sleep, offer, cancel, join, drain).

### 3. SETTLED: yes

- `takeTimeoutNoLostElement_refuted : ¬ takeTimeoutNoLostElement` (`Proofs/Calibration/QueueTimeout.lean:363-365`). Type exactly `¬ P`.
- Witness `xs = [42]`, `d = 1000`, `s = 1`, empty choice list (FIFO), `cx_run` by `decide +kernel`; `cx_wellFormed` now includes `env_opaque`.
- `bugs/CE-0003.yaml`: all fields, three version outputs, four duplicate queries. Reproducer last line `REPRODUCED CE-0003` (`Repro.scala:63`).

### 4. WRONG-FUNCTION and FIXED TWIN

The new rule (fixed-twin check) is **not met formally**: there is no Lean twin and no Scala-side twin. The bug record explains why (draft PR #4710 changes `IOFiber` globally). By reading, I agree with batch 2: the statement is a safety claim over all schedules; a lossless `racePair` (the child outcome goes to the caller, or the consumer ends `Succeeded(42)`) gives `returned = [42]` on the witness schedule; the schedule `pick 0 ×6, pick 1, pick 1` shows that the statement accepts a run where the element stays in the queue. A model artifact would need a model bug in the queue, `timeout` or `racePair` mirror on another schedule; the FIFO witness itself is replayed on the real library. Confidence 0.8.

### Fixes

1. Fixed twin: run `reproducers/CE-0003` on a `publishLocal` of PR #4710 (head `f313ce86`) and record the output in the bug record (a Scala-side twin). If the PR's `racePair` change is local enough, mirror only its finalizer as a Lean twin of `Step.lean` `RacePair`.

---

## 8. `core.SyncIO.runLoop.Error.fatalTwin` (CE-0004, refuted)

- mirror: yes
- property: yes (low strength: maintainers exclude fatal errors from the laws)
- settled: yes (witness differs from the reproducer by one `.uncancelable`)
- wrong-function / fixed twin: pass
- verdict: FAITHFUL (low strength)

1. MIRROR: yes. `FIB:263-269` (`if (!UnsafeNonFatal(ex)) onFatalFailure(ex)`) = `Step.lean:813-815` (`raised`). `SIO:257-259` (no check) = `SyncIO.lean:356-360`. `UnsafeNonFatal.scala:37-41` = `Err.isNonFatal` (`Model/Val.lean:50-53`). All checked.
2. PROPERTY: yes, as a twin property (`AGENTS.md` 3a: `IO` vs `SyncIO`). The statement uses `StepIdentityFor` (direct `IO` run loop vs `SyncIO` run loop on one program), for all `e`. The law framing alone would be weak: in #549 the maintainers excluded fatal errors from the laws, and decision 38 itself takes fatal errors out of CE-0001. The twin framing and the public `SyncIO#to` split (reproducer A/B/C) carry it. `maybe_intended: Likely partly intended` and `priority: low` are honest.
3. SETTLED: yes. `raiseErrorTwin_refuted : ¬ raiseErrorTwin` (`Proofs/Calibration/FatalRaise.lean:88-89`). Bug record complete (empty `upstream` with 10 recorded queries; three version outputs). Reproducer last stdout line `REPRODUCED CE-0004`. Difference: the reproducer uses `sio.to[IO]`, which is `interpret(this).uncancelable` (`SIO:193-209`). So its programs B and C are `IO.uncancelable(_ => IO.raiseError(F).handleErrorWith(...))`, not the Lean program `IO.raiseError(F).handleErrorWith(...)`; B even goes through the CE-0001 `Uncancelable` branch. The result is the same, but the Lean witness is not literally a reproducer case.
4. WRONG-FUNCTION / FIXED TWIN: the twin (`SyncIOEnv.fixFatalRaise`) is the `possible_fix` (no upstream fix exists). It holds for `e` in {fatal 0, fatal 5, nonFatal 0, interrupted 0}; only the kind matters for this program, so the domain covers all kinds. v3.7.1 holds on the non-fatal two. A `SyncIO` that treats every error as fatal fails it. Pass.

### Fixes

1. Add a reproducer case with the literal Lean program: `IO.raiseError(new Fatal).handleErrorWith(_ => IO.pure(1)).syncStep(Int.MaxValue).unsafeRunSync()` (no runtime needed; `Right(1)`), next to case C.
2. In the property doc, name the twin source (3a) as the main promise, and the law as secondary.

## 9. `core.SyncIO.runLoop.Error.fatalTwin.nonFatal` (open)

- verdict: FAITHFUL as a statement

The ordinary-input companion of CE-0004 (`Props/Calibration/FatalRaise.lean:60-63`). Hypothesis `e.isNonFatal`: the documented scope. Proven only on {nonFatal 0, interrupted 0}. The open note (a lemma that runs do not depend on the error code) is a fair plan. A `SyncIO` that treats all errors as fatal fails it.

---

## Wider concerns

1. **`Poll.apply` lives in user code.** `IO.applyPoll` and `WF.PollOpaque` fix the meaning of `poll(io)` to the v3.7.1 poll kinds. A fix that adds a poll kind (PR #4700) cannot be expressed in the formal domain, so fixed-twin checks for `uncancelable`-related bugs must use a changed encoding. Make poll application a value-dispatched primitive.
2. **Two observation models.** The IO laws and CE-0002 use `EqvP` (preemptive, multi-fiber); CE-0001 and CE-0004 use the single-fiber driver with step-only schedules; CE-0003 uses the replay scheduler. Each choice is argued, but a reader must check three models. Record in the wiki which model each registered property uses and why.
3. **`preempt` has no difftest.** `TestControl` cannot replay a mid-task preemption. The claim "every iteration-granularity interleaving is allowed by the multi-threaded runtime" is argued (`raw/project-decisions/2026-11-10-preemptive-eqv-notes.md`), not tested. `EqvP` proofs of laws are proofs about this over-approximation. Consider a JVM stress test with many workers for one law, or a note in `wiki/semantics/outcome-equivalence.md` on this limit.
4. **Fixed-twin domains are small and hand-picked.** 10 programs (CE-0001), 9 (CE-0002), 4 errors (CE-0004), none (CE-0003). They are meaningful, but no twin family is proven `WellFormed`, and none varies `limit`, `Ref`/`Deferred` allocation or long runs. Where a fix is merged upstream (PR #4630), difftest the twin against the real fixed code.
5. **`IO.Local` in user programs.** `progOK` allows `.local f` with a user function, but `IO.Local` is `private[effect]` (`IO:2318`). User code can then read the whole `IOLocal` state, which Scala cannot. No current result depends on it; restrict it to library closures.
6. **Difftest depth for v1 mirrors** (batch-2 item 6) is unchanged: about 5,000 to 10,000 cases per v1 op.
7. **Proven laws are low strength** (batch-1/2 item): no proven law runs `fa` or a finalizer.

**Phase 5 gate: PASS** — CE-0001 FAITHFUL (with caveats: poll encoding, small twin domain), CE-0002 FAITHFUL, CE-0003 FAITHFUL (fixed twin by reading only; Scala-side twin on PR #4710 still to do).

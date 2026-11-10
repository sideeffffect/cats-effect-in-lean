# Review batch 4 (2026-11-10): 13 Phase 6 registry entries

Reviewer: independent agent. It did not write the code. It read the Lean source, the bug records, the reproducers, the wiki and the earlier reviews. It did not run a build, Lean, a test, sbt or scala-cli. It ran read-only `gh search issues` / `gh search prs` on typelevel/cats-effect (`memoize`, `bracketFull`) and read `GenConcurrent.scala` on `origin/series/3.x`.
Rubric: `AGENTS.md` section 5 and `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test, vacuous hypotheses, fixed-twin check of decision 39). When unsure, the answer is no.
Scala source: `~/Projects/cats-effect` at `eb0cc258` (tag `v3.7.1`). Short names: `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`, `IOD` = `.../IODeferred.scala`, `K/` = `kernel/shared/src/main/scala/cats/effect/kernel/`, `L/` = `laws/shared/src/main/scala/cats/effect/laws/`. Lean paths are relative to `CatsEffectInLean/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `core.IO.memoize.noStuckGet` (CE-0030) | refuted | FAITHFUL (with caveats) |
| `core.IO.bracketFull.kernelDefaultTwin` (CE-0005) | refuted | FAITHFUL (low strength) |
| `core.IO.bracketFull.kernelDefaultTwin.pureUse` | open | FAITHFUL as a statement |
| `laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO` | open | FAITHFUL as a statement |
| `core.IO.bracket.releaseOnce` | open | **HOLLOW** (hypotheses unsatisfiable) |
| `core.IO.guarantee.finalizerOnce` | open | **HOLLOW** (hypotheses unsatisfiable) |
| `core.IO.race.combNoLeak` | open | FAITHFUL as a statement |
| `core.IO.race.combCanceledNoLeak` | open | FAITHFUL as a statement |
| `core.IO.timeout.noLeak` | open | FAITHFUL as a statement |
| `core.IO.raceOutcome.isWinnerOutcome` | open | FAITHFUL as a statement |
| `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` | open | FAITHFUL as a statement (citation fix required) |
| `core.IO.memoize.getsAgree` | open | FAITHFUL as a statement |
| `core.IO.memoize.atMostOnce` | open | FAITHFUL as a statement |

Both refutations (CE-0030, CE-0005) are FAITHFUL. The two marker invariants of track G are vacuous: their hypotheses contradict each other, so the statements are trivially true and say nothing.

---

## 1. `core.IO.memoize.noStuckGet` (CE-0030, refuted)

- verdict: FAITHFUL (with caveats)

1. MIRROR: yes. `Model/Memoize.lean` follows `K/GenConcurrent.scala:43-112` closure by closure. Checked:
   - `getSel` = `state.get.flatMap { case Finished => fromEither(result).flatten; case _ => evalOrSubscribe }` (`:107-110`).
   - `evalOrSub` → `.uncancelable (fmfBody …)` = `flatModifyFull` = `F.uncancelable(poll => F.flatten(modify(f(poll, _))))` (`K/Ref.scala:140-141`, checked).
   - `modifyThunk`: the three cases in source order (`:52`, `:86`, `:91`). The `Finished` case returns `Eff.finished res` with no poll for variant 0 (`:91-92`).
   - `go` = `IO#guaranteeCase` (`IO:523-530`): `gcBody` = `poll(this).onCancel(fin(Canceled))`, `.onError` = `handleErrorWith(t => pf(t) *> raiseError(t))` (`IO:605-606`), `flatTap(a => fin(Succeeded(pure a)).as(a))`. `fin(Canceled)` is built eagerly, as in Scala.
   - `tryComplete`, `unsubscribe`: the `fiber eq deferredFiber` guard compares `Deferred` ids; `subscribers == 1` branch order is kept.
   - `fiber.get` reads the cell when it is called: correct, `IOD:71` is `def get: IO[A] = cell.get()`.
   - `series/3.x` `GenConcurrent.scala:90-92` is unchanged (read with `git show origin/series/3.x:…`).
2. PROPERTY: yes, with a strength limit. The statement says that a blocked run never has a `Finished` memo. It reads the memo cell, which is internal state. I judge this a faithful observation, not a model artifact:
   - In the Scala code, `Finished` is written only by `tryComplete`, after `fa` has ended. After that, every correct `get` path completes: the fast path (`:108`), the subscriber path (`join` of a finished `go`), and the `Finished` path of `flatModifyFull`.
   - The test harness `twoGets` starts both `get`s unmasked with `start`. So `canceled *> never` must end `Canceled`. In a masked caller a hang would be correct, but the harness has no mask.
   - User code cannot write cell 0. `WF.EffectsOK` needs the `Ref` handle, and `fa` never receives it. User code also cannot forge a `get`, because `Eff.get 0 …` captures `.ref 0`, which `progOK` rejects.
   - Limit: an implementation that never writes `Finished` satisfies the statement trivially. This statement can only catch hangs after completion. That is enough for a refutation.
3. SETTLED: yes. `memoizeNoStuckGet_refuted` (`Proofs/Phase6/MemoizeStuck.lean:85-89`). The witness is `fa = IO.canceled`, no user code, and one `preempt` after 35 micro-steps. `wit_blocked` and `wit_finished` are proved by `decide +kernel`. `fa_wf` proves `WellFormed`: the clause for even ids holds because all user calls throw. `PollOpaque` holds by `pollOpaque_of_const`. The witness is reachable through the public API: `IO.canceled.memoize`, then two `get.start`. Reproducer: `reproducers/CE-0030/Repro.scala` uses the real `_.memoize` (`ioMemoize`), a faithful copy, and a fixed copy. It prints `REPRODUCED` only if `IO#memoize` hangs in some row and the fix hangs in none. Bug record: complete. `maybe_intended: No` is justified by the fast-path/slow-path asymmetry and issue #1519. My duplicate search (`memoize`, sorted by date) found no newer issue or PR.
4. FIXED TWIN: pass on a narrow domain. Variant 1 is `poll(fromEither(result).flatten)`, the `possible_fix`. `fixed_wit` completes the run, and `MemoizeFixed.lean` has 0 blocked runs over 120 one-preemption schedules, while v3.7.1 blocks at exactly 35–37. All of this uses one `fa`. Other `fa` values are covered only by smoke (`test/Phase6/MemoizeSmoke.lean`), not in Lean.

Caveats:
- The Lean fixed-twin domain has a single `fa`. Recommended: add `fa ∈ {pure, raiseError, never, cede}` to `MemoizeFixed.lean`.
- The reproducer gets the hang on `TestControl` only with non-default `IORuntimeConfig` thresholds. The default runtime result (2,098/100,000) comes from `spikes/memoize/RealRuntime.scala`, which is not the reproducer. That is acceptable: the thresholds only move preemption points.

## 2. `core.IO.bracketFull.kernelDefaultTwin` (CE-0005, refuted)

- verdict: FAITHFUL (low strength)

1. MIRROR: yes.
   - `bfBody`/`bfK` = `IO:1826-1830`: `acquire(poll).flatMap(a => IO.defer(poll(use(a))).guaranteeCase(release(a, _)))`. `srcIO (.deferUse …)` = `Delay(deferThunk).flatMap(deferEv)`; `deferEv` calls `use(a)` and then applies the poll.
   - `dbfBody`/`dbfK` = `K/MonadCancel.scala:447-456`: `guaranteeCase(poll(unit >> use(a)))(release(a, _))`, with `guaranteeCase` dispatched to the `IOAsync` override (`IO#guaranteeCase`). That is correct for the kernel body run at `IO`.
   - The `IOAsync.bracketFull` override → `IO.bracketFull` is at `IO:2062-2064` (checked).
2. PROPERTY: yes. This is a twin (source (a)). The hypotheses are `LibEnv` and `WellFormed` of both sides. A throwing `use` is an input that Cats Effect expects: the kernel comment at `K/MonadCancel.scala:452-453` says so, and issue #1535 handled it. `maybe_intended: Partly` is honest: no document says the two bodies may differ, and PR #2126 looks like a performance rewrite.
3. SETTLED: yes. `bracketFullIsKernelDefault_refuted` uses exact `outcomesPList` sets, `{Errored(E5)}` against `{Canceled}`. `lhs_wf` and `rhs_wf` are proved. The witness uses `acquire = _ => IO.canceled`, which is legal: `acquire` runs masked. Reproducer cases A and B (the parent cancels during `acquire`) show the same split on the real `IO.bracketFull`. The kernel side is a hand copy (`kernelBF`) with `IO.unit >> use(a)`, which is faithful.
4. FIXED TWIN: pass. `fbfK` = `poll(IO.defer(use(a)))` with the identity poll inside, which is the `possible_fix`. It is `EqvP` to the kernel body on 8 programs, and v3.7.1 differs only on the witness (`BracketFullFixed.lean`).

The strength is low because the visible difference needs a `use` that throws or has a side effect when it is called. That is impure Scala, but Cats Effect supports it on purpose.

## 3. `core.IO.bracketFull.kernelDefaultTwin.pureUse` (open)

- verdict: FAITHFUL as a statement

1. MIRROR: yes (same mirrors as entry 2).
2. PROPERTY: yes. `PureFn` says only that a call to `use` has no effect and does not throw. The returned `IO` is arbitrary, and `acquire` and `release` are arbitrary. This is the ordinary-input form required by the exotic-input rule. `PureFn` still lets `use` read the heap view, which is harmless here. The hypotheses are satisfiable (smoke `twin_pure_*`).
3. SETTLED: open, with a proof plan (a simulation up to closure ids and one iteration). OK.
4. WRONG-FUNCTION: an `IO.bracketFull` without `poll` around `use`, or one that unmasks before `acquire`, gives different outcome sets. Pass.

## 4. `laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO` (open)

- verdict: FAITHFUL as a statement

1. MIRROR: yes. The law is `L/MonadCancelLaws.scala:28-29` (checked). `gBody` = `IO:496-501`: `poll(this).onCancel(fin).onError(_ => fin.reportError).flatTap(_ => fin)`. `gcBody` = `IO:523-530`. The `IOAsync` dispatch is at `IO:2023-2027`.
2. PROPERTY: yes. `k` is the law lambda `_ => fin` (`constProg`), and `fa`/`fin` are arbitrary well-formed sources. The hypotheses are satisfiable (14 `law_*` pairs).
3. SETTLED: open. OK.
4. WRONG-FUNCTION: `law_wrongFunction` (a `guarantee` that never runs `fin`) breaks it. Pass.

## 5. `core.IO.bracket.releaseOnce` (open)

- verdict: **HOLLOW** (vacuous: the hypotheses can never all hold)

The concern that another agent raised is correct. There are two independent contradictions (`Props/Phase6/Bracket.lean:143-170`, `Model/Bracket.lean:469-500`).

1. **`rel` against `MarkersOnly` clause 2.**
   - `bracketIO … use rel` builds `BLam.dropOc rel`, and `BLam.good (.dropOc rel) = userId rel`. `bfBody` is good only if `leafOK (dropOc rel).id` holds, which needs `rel` even.
   - If `rel` is odd, `bfBody` is not `isLib`. Then `progOK` of `parent (bracketIO …)` fails, so the `WellFormed` hypothesis is false.
   - If `rel` is even, the hypothesis `env.callV rel x v = { out := .prog (.flatMap (.delay (.user mR)) (.user q)) }` gives a program `p` with `usesId mR p = true`. `MarkersOnly` clause 2 (all even ids) demands `usesId mR p = false`.
2. **Library forwarders against `MarkersOnly` clause 1.**
   - `CallOK` of `rel` (a `WellFormed` clause) needs `fnOK (.user mR)`, so `mR` is even or `isLib`. A library closure can satisfy `Marker` only by forwarding to an even id, which would itself emit `R`. So `mR` is even in effect.
   - Then `BLam.thenUse mR a` is `good` for every `a`. `LibEnv` forces `env.callV (thenUse mR a).id x v = env.callV mR a v`, which has the effect `.emit R`.
   - Its id is odd, so it is not in `[mA, mR]`. Clause 1 forbids every id outside `ms` from emitting `R`.

So `bracketReleaseOnce` holds for every implementation, including "never run release". It fails the wrong-function test. The `#guard` smoke tests (`test/Phase6/BracketSmokeParent.lean`) run concrete programs and never check `MarkersOnly`, so they did not find this.

## 6. `core.IO.guarantee.finalizerOnce` (open)

- verdict: **HOLLOW** (vacuous)

1. The proof is the same as contradiction 2 of entry 5. `WellFormed (ioOf s)` with `ioOf s = flatMap (delay (user mA)) (user k)` needs `mA` even or `isLib mA`. A good `BLam` returns `ret unit` with an `emit` for every argument only by forwarding to an even user id, and that id would also emit `A` while it is outside `ms`. So `mA` is even. Then `thenUse mA a` is good, and `LibEnv` makes it emit `A`, which contradicts `MarkersOnly` clause 1.
2. A naive fix makes the statement false for a correct `guarantee`. If clause 1 checked only even ids, user code `k` could return `.flatMap (.pure ()) (BLam.thenUse mR a).fn` or `guaranteeIO (.ext s) (.ext f)`. These closures capture no handle, so `progOK` accepts them, and they run the `R` marker again. That would give a refutation where user code, not `guarantee`, runs the finalizer twice. The markers must be impossible to forge.
3. Row list: `kernel.MonadCancel.guarantee` is listed, but the statement uses only `IO#guarantee` (`guaranteeIO`). `defaultGuaranteeIO` is not used, so the row is not mirrored by this entry.

## 7–9. `core.IO.race.combNoLeak`, `core.IO.race.combCanceledNoLeak`, `core.IO.timeout.noLeak` (open)

- verdict: FAITHFUL as statements

1. MIRROR: yes.
   - The dispatch table of `Model/Race.lean` is correct. `IO#race` → `IO.race` → `asyncForIO.race` (`IO:638-639`, `:1788-1789`). `IO#raceOutcome` → `asyncForIO.raceOutcome` (`IO:641-642`). `IO#both` → `IO.both` → `asyncForIO.both` (`IO:243-244`, `:1732-1733`). `IO#bothOutcome` → `asyncForIO.bothOutcome` (`IO:228-229`). `IOAsync` has no override.
   - `raceOutcome` = `K/GenSpawn.scala:370-376` (checked).
   - `timeout` → `timeoutTo` → `race` with `sleep` (`IO:818-823`, `:850-860`).
2. PROPERTY: yes.
   - Promises: `K/GenSpawn.scala:358-360` ("The loser of the race is canceled before returning"), backpressured cancel, and `IO:800-802`.
   - The leak notion (`Model/Leak.lean`) is a real notion of a leaked fiber: the fiber has no outcome and still holds the `racePair` callback of the racing fiber `r` in slot 0. Only `done` clears that callback.
   - Wrong-function: `raceNoCancel` leaks (`RaceSmoke.noCancel_leaks`, `decide +kernel`). A race that cancels the loser without joining it (`f.cancel.start`) also leaks on some schedule, because the loser keeps its callback while its finalizers run.
   - By design, the notion does not see fibers that user code starts inside `fa`/`fb`. Cats Effect fibers are not structured, so that is correct.
   - Hypotheses: only `WellFormed` of the sides, which is satisfiable (for example `pure`).
   - The cut is at root completion (decision 33). In the decision-50 form, the parent cancels and joins.
3. SETTLED: open. Track P has proved the frame lemmas F1/F2 and lists the remaining gaps (S, F3, F4, H, C(r)). OK.

## 10. `core.IO.raceOutcome.isWinnerOutcome` (open)

- verdict: FAITHFUL as a statement

1. MIRROR: yes (`K/GenSpawn.scala:370-376`).
2. PROPERTY: yes. `Left(oc)` implies that fiber 1 (`fa`) ended with `oc`, and `Right(oc)` implies the same for fiber 2. `fiberOutcome` indexes `liveFibers` by position. That is correct, because `finish` writes `fibers.set fib.id` (`Model/Sched.lean:100-107`), so position equals id. Fibers 1 and 2 are the `racePair` children of root fiber 0. Wrong-function: a `raceOutcome` that swaps `Left` and `Right` fails it.
3. SETTLED: open. OK.

## 11. `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` (open)

- verdict: FAITHFUL as a statement (citation fix required)

1. MIRROR: yes in content. `IOI.void (.uncancelable raceBodyFn)` against `neverIO`, where `raceBodyFn` returns `Race.raceIO never canceled`. This is the law text.
   - **Citation wrong**: `Props/Phase6/Race.lean:190` cites `L/GenSpawnLaws.scala:121-122`. Those lines hold `fiberCancelationIsOutcomeCanceled`. The law is at `L/GenSpawnLaws.scala:146-147`, and the inventory row says 146.
2. PROPERTY: yes. It is a closed law, so the environment is fixed by the law text. Wrong-function: a race that inherits the outer mask into `poll(f.join)` with a cancelable join, or one that lets the `canceled` side cancel the parent, gives `Canceled` on the left side.
3. SETTLED: open, because the state space is too large for the kernel. OK.

## 12. `core.IO.memoize.getsAgree` (open)

- verdict: FAITHFUL as a statement

1. MIRROR: yes (entry 1).
2. PROPERTY: yes. Two concurrent `get`s give the same outcome when the root completes. The Scaladoc ("evaluate `fa` and cache the result") supports it. Nothing in `twoGets` cancels a `get` from outside. A self-canceled `fa` gives `Canceled` on both paths. User code cannot reach the memo cell or forge a `get` (handle check on `.ref 0`).
3. SETTLED: open. OK.
4. WRONG-FUNCTION: a `memoize` without a cache and a counting `fa` breaks it (`MemoizeSmoke`). Pass.

## 13. `core.IO.memoize.atMostOnce` (open)

- verdict: FAITHFUL as a statement

1. MIRROR: yes.
2. PROPERTY: yes. The counter is `Ref` 0, which the harness allocates first.
   - User code cannot use `TLam.incr 0`, because it captures `.ref 0`, so `progOK` fails.
   - `TLam.constFa` only re-runs the raw `fa`, which has no counter.
   - Re-evaluation needs all `get`s to be canceled before `Finished`. In `countedTwoGets` that cannot happen: a self-cancel comes only after `Finished`.
3. SETTLED: open. OK.
4. WRONG-FUNCTION: without a cache, the counter reaches 2. Pass.

## Frame lemmas (`Proofs/Lemmas/Frame.lean`)

These lemmas are stated about the real model, with no hypothesis. `sframe_tickP` and `sframe_runSchedStateP` quantify over `Sched.tickP` / `runSchedStateP` with any `cfg`, `mm`, `env`, fuel and choice list. `owner_stable` follows from the prefix relation on `owners`. `Frame` covers the `ContState` owner list (prefix), the fiber-table length and the handle counter. These are the F1/F2 facts that the leak proofs need. No registered entry uses them yet. I found no forbidden tactic in the file.

## Inventory and rows

- Only settled entries mark rows `modelled`: `core.IO.memoize` and `kernel.GenConcurrent.memoize` (CE-0030), `core.IO.bracketFull`, `core.IO.IOAsync.bracketFull` and `kernel.MonadCancel.bracketFull` (CE-0005), and `core.IO.timeout` (CE-0003). Correct.
- The rows named by the CE-0030 and CE-0005 entries are the methods they mirror. Correct.
- The registry column of `inventory/inventory.csv` is incomplete:
  - `core.IO.bracket`, `bracketCase`, `guarantee`, `guaranteeCase`, `IOAsync.guarantee`, `IOAsync.guaranteeCase`, `kernel.MonadCancel.guarantee`, `kernel.MonadCancel.bracket` and `laws.MonadCancelLaws.guaranteeIsGuaranteeCase` have an empty column, but open entries name them.
  - The `bracketFull` rows list only `kernelDefaultTwin`.
  - Not blocking (no status is wrong).
- `core.IO.guarantee.finalizerOnce` lists `kernel.MonadCancel.guarantee`, which it does not mirror (entry 6).

## Required fixes

1. Entries 5 and 6:
   - Replace `MarkersOnly` with markers that user code cannot forge or forward. For example, make the markers harness closures that capture a handle user code does not hold, such as a harness-allocated `Ref`, as `countedTwoGets` does. `WellFormed` then rejects any user program that names them, directly or through a library closure.
   - Then drop clause 1 for library ids, and drop clause 2.
   - Add a theorem that shows the hypotheses are satisfiable, with one concrete environment per statement.
2. Proposed rule: every open or proven entry with non-trivial hypotheses needs a satisfiability witness in Lean. A smoke `#guard` that does not check the hypotheses does not count.
3. Fix the citation `L/GenSpawnLaws.scala:121-122` → `:146-147` in `Props/Phase6/Race.lean`.
4. Remove `kernel.MonadCancel.guarantee` from `core.IO.guarantee.finalizerOnce`, or mirror the kernel `guarantee` in the statement. Fill in the inventory registry column.
5. Recommended (not blocking): for CE-0030, check the fixed twin in Lean on more `fa` values.

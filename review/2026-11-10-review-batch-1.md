# Review batch 1 (2026-11-10): the 5 registry entries

Reviewer: independent agent. It did not write the code. It read the source and the proofs. It did not run a build, Lean, a test, or scala-cli.
Rubric: `AGENTS.md` section 5 and `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test). When unsure, the answer is no.
Scala source: `~/Projects/cats-effect` at `eb0cc258` (tag `v3.7.1`). `FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala`, `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`, `L/` = `laws/shared/src/main/scala/cats/effect/laws/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO` | proven | FAITHFUL (low strength) |
| `laws.MonadCancelLaws.forceRCanceledShortCircuits.IO` | proven | FAITHFUL (low strength) |
| `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO` | open | FAITHFUL as a statement |
| `laws.MonadCancelLaws.uncancelablePollIsIdentity.IO` | open | HOLLOW as a statement |
| `core.IO.syncStep.syncStepIdentitySyncIO` (CE-0001) | refuted | HOLLOW |

The bug CE-0001 is real. The reproducer shows it on v3.7.1 (`bugs/CE-0001.yaml`, case 4). The HOLLOW verdict is about the Lean property: its negation is also true for a correct `syncStep`.

---

## 1. `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO`

- entry: `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap.IO`
- rows: `laws.MonadCancelLaws.canceledAssociatesLeftOverFlatMap`
- mirror: yes
- property: yes
- settled: yes
- wrong-function test: pass (for the functions of the law), with a caveat
- verdict: FAITHFUL (low strength)

### 1. MIRROR

The proposition (`CatsEffectInLean/Props/IO/MonadCancelLaws.lean:42-45`) uses `IOI.flatMap IOI.canceled (.user k)` and `IOI.canceled`, with `k` constrained to return `IOI.void fa`. These are the `IOAsync` calls. The run uses the `IOFiber` mirror (`CatsEffectInLean/Model/Step.lean`). It is not a hand-written specification.

Citation spot checks (all correct):

- `L/MonadCancelLaws.scala:94-95` is `canceledAssociatesLeftOverFlatMap` (`F.canceled >> fa.void <-> F.canceled`).
- `L/MonadCancelTests.scala:138-147`: the law is in the `Cancelable`-only suffix.
- `IO.scala:961-962` `void = map(_ => ())`; `IO.scala:2152` `IOAsync.void = ioa.void`.
- `IO.scala:1501` `canceled = Canceled`; `IO.scala:2073-2074` `IOAsync.canceled = IO.canceled`.
- `IO.scala:469` `flatMap`; `IO.scala:2101` `IOAsync.flatMap`.
- Run loop `Canceled` branch: `Step.lean:1027-1035` matches `FIB:532-540` (set `canceled`, then `isUnmasked` → `prepareFiberForCancelation`, else `succeeded((), 0)`). `prepareFiberForCancelation` with no finalizers calls `done(Canceled)` (`FIB:1150-1162`).
- `Step.lean:1120-1162` (`step`) matches the counter logic of `FIB:224-245`.

### 2. PROPERTY

- Promised: yes. The law is checked for `IO` (root scope `Cancelable`).
- Quantified over all `env`, all `fa : IO`, all ids `k`. The only hypothesis is `Lam.constProg env k (IOI.void fa)`: it defines the Scala lambda `_ => fa.void`. This is not an assumption about the interesting case.
- Observation (`Eqv`, `CatsEffectInLean/Model/Outcomes.lean:117-118`): root summary, emitted trace, `Ref` cells, reported errors, over all fuel and all `pick` schedules. External cancel is not used. For this law that is correct: the Cats Effect `Eq[IO[A]]` runs each side alone (`testkit/.../TestInstances.scala:160-161`, `199-219`). `Eqv` is stronger than that `Eq` because it also compares the trace.

### 3. SETTLED

- `canceledAssociatesLeftOverFlatMap_proven : canceledAssociatesLeftOverFlatMap` (`CatsEffectInLean/Proofs/IO/MonadCancelLaws.lean:135`). The type is the registered constant.
- The proof computes every run for each fuel (`rfl` with free `env`, `fa`, `k`). Both sides have exactly one observation: `Canceled`, empty trace, no `Ref`, no report.

### 4. WRONG-FUNCTION TEST

| Broken function | Theorem still holds? |
|---|---|
| `Canceled` branch is a no-op (`canceled := unit`) | No. The left side runs `fa.void`; with an `fa` that emits, the traces differ. |
| `Canceled` ignores `isUnmasked` (always finalize) | Yes, but the root has no mask here, so the law does not test this. Not applicable. |
| `flatMap` never calls `k` | Yes. |
| run loop gives `Canceled` for every program | Yes. |

The last two rows pass for every equational law: a constant semantics satisfies any `lhs <-> rhs`. The theorem alone does not exclude them. The replay difftest (150,000 cases, `wiki/methodology/differential-testing.md:88`) excludes them. The function that this law is about (the self-cancel check of `Canceled`) fails the test correctly. So the verdict is FAITHFUL. The strength is low: the proof never calls user code, and the content of the law is only "`fa` never runs".

### Fixes

None needed. Optional: state the twin `EqvExt` version and the Cats Effect `Eq` version (root `Outcome` only), so the strength of `Eqv` is visible.

---

## 2. `laws.MonadCancelLaws.forceRCanceledShortCircuits.IO`

- entry: `laws.MonadCancelLaws.forceRCanceledShortCircuits.IO`
- rows: `laws.MonadCancelLaws.forceRCanceledShortCircuits`
- mirror: yes
- property: yes
- settled: yes
- wrong-function test: pass (for the functions of the law), same caveat as entry 1
- verdict: FAITHFUL (low strength)

### 1. MIRROR

`IOI.forceR fa h k = productR (handleError fa h) k` (`CatsEffectInLean/Model/IOInstance.lean:109`). This is the body of `IO#forceR`.

Citation spot checks (all correct):

- `L/MonadCancelLaws.scala:75-76` `F.forceR(F.canceled)(fa) <-> F.productR(F.canceled)(fa)`.
- `IO.scala:452-454` `asInstanceOf[IO[Unit]].handleError(_ => ()).productR(that)`.
- `IO.scala:532-533` `handleError(f) = handleErrorWith(t => IO.pure(f(t)))`.
- `IO.scala:903-904` `productR(that) = flatMap(_ => that)`.
- `IO.scala:2014-2015` `IOAsync.forceR = left.forceR(right)`; `IO.scala:2081-2082` `IOAsync.productR = left.productR(right)`.
- `L/MonadCancelTests.scala:130` registers "forceR canceled short-circuits" for all instances.

### 2. PROPERTY

- Promised: yes (base law list, all root scopes).
- Quantified over all `env`, `fa`, ids `h`, `k`, `k'`. The three hypotheses only define the Scala lambdas (`t => IO.pure(())`, `_ => fa`, `_ => fa`). Distinct ids on the two sides are allowed, which is the general case.
- Observation: `Eqv`, as in entry 1.

### 3. SETTLED

- `forceRCanceledShortCircuits_proven : forceRCanceledShortCircuits` (`Proofs/IO/MonadCancelLaws.lean:178`). The type matches.
- The right side is reused from entry 1 (`canceledThen k'`). Correct: `productR canceled k'` unfolds to `flatMap canceled k'`.

### 4. WRONG-FUNCTION TEST

| Broken function | Theorem still holds? |
|---|---|
| `forceR a b := b` | No. The left side is `fa`, the right side is `Canceled`. |
| `handleErrorWith` catches cancelation (runs `h` on `Canceled`) | No. The left side then runs `fa`. |
| run loop gives `Canceled` for every program | Yes (any equational law; excluded by the difftest). |

### Fixes

None needed. Note: like entry 1, the proof does not exercise `handleErrorWith` on an error. The law `forceRDiscardsError` (still `todo`) would.

---

## 3. `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO` (open)

- entry: `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary.IO`
- rows: `laws.MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary`
- mirror: yes
- property: yes (with the `Eqv` caveat below)
- settled: no (open; judged as a statement only)
- wrong-function test: partial (the law is weak; see below)
- verdict: FAITHFUL as a statement

### 1. MIRROR

`IOI.uncancelable (.user b₁)` with `b₁` returning `IOI.onCancel fa fin`, against `IOI.onCancel (IOI.uncancelable (.user b₂)) fin` with `b₂` returning `fa` (`Props/IO/MonadCancelLaws.lean:67-71`).

Citation spot checks (all correct):

- `L/MonadCancelLaws.scala:61-62` (the law) and `:47-60` (the NB comment).
- `L/MonadCancelTests.scala:128` registers it for all instances.
- `IO.scala:590-591` `onCancel = OnCancel(this, fin)`; `IO.scala:2059-2060` `IOAsync.onCancel`.
- `IO.scala:1712-1713` `uncancelable = Uncancelable(body, event)`; `IO.scala:2095-2096` `IOAsync.uncancelable`.
- `Step.lean:1037-1052` matches `FIB:542-583`: `finalizers.push(EvalOn(fin, currentCtx))`, push `OnCancelK`; `masks += 1`, body inside `try`, push `UncancelableK`.

### 2. PROPERTY

- Promised: yes. The NB comment says the law and the monad laws together break the monad laws. It does not withdraw this law.
- No hypotheses except the lambda definitions.
- `Eqv` has no external cancel. With external cancel the two sides differ by design: on the right side a cancel that lands after `OnCancel` and before `Uncancelable` runs `fin`; the left side never runs `fin` on an external cancel. The NB comment ("cancelation is a hint") covers this. The choice of `Eqv` is documented (`Outcomes.lean:29-50`) and matches the Cats Effect `Eq`. So this is not a hidden case.
- Both sides do the same number of run-loop iterations (one `OnCancel` and one `Uncancelable` each), so the auto-yield concern of entry 4 does not apply.

### 3. SETTLED

Open. The note gives a plan (simulation). OK.

### 4. WRONG-FUNCTION TEST

| Broken function | Statement still holds? |
|---|---|
| `onCancel` drops `fin` | Yes on the two sides, but only because `fin` cannot run on either side without external cancel or self-cancel inside a mask. With `fa = canceled`, both sides pop `fin` before the cancel is seen. So the law has little power over `fin`. This is a weakness of the law, not of the statement. |
| `UncancelableK` pop does a run-loop iteration before `OnCancelK` pop | No (expected): the right side would then see the cancel with `fin` still registered and run it. |
| ignore masks (`Canceled` always finalizes) | Yes: with `fa = canceled *> emit`, both sides then cancel at the same point with `fin` registered, so both run `fin`. The law does not test masks. |

The law tests mainly the pop order of `OnCancelK` and `UncancelableK`. That is a weakness of the law, not of the statement, so the verdict stays FAITHFUL.

### Fixes

None for the statement. When the proof is done, also state the `EqvExt` version and refute it with the window described above, and mark it `maybe_intended: yes` (NB comment). That makes the scope of the law explicit.

---

## 4. `laws.MonadCancelLaws.uncancelablePollIsIdentity.IO` (open)

- entry: `laws.MonadCancelLaws.uncancelablePollIsIdentity.IO`
- rows: `laws.MonadCancelLaws.uncancelablePollIsIdentity`
- mirror: yes
- property: no
- settled: no (open)
- wrong-function test: not applicable (statement only)
- verdict: HOLLOW as a statement

### 1. MIRROR

`IOI.uncancelable (.user b)` with `Lam.pollApply env b fa`: for each `Val.poll m s` the body returns `.unmaskRunLoop fa m s` (`IOInstance.lean:133-134`). This is the `poll` of `FIB:562-567`. The run loop branch `Step.lean:1053-1058` matches `FIB:585-602` (`masks == cur.id && self eq cur.self`, then `masks -= 1`, push `UnmaskK`).

Citations correct: `L/MonadCancelLaws.scala:32-33`; `L/MonadCancelTests.scala:121`.

### 2. PROPERTY

No. Two problems make the statement false in the model for reasons that are not Cats Effect defects:

1. **Forged ids.** `fa : IO` and `env` range over all model terms. They include runtime-only terms: `.rt (.cancel 0)` (cancel the root, fiber id 0), `.unmaskRunLoop` with any id, `.contGet` with any state, `.endFiber`, and the internal `RtFn` closures (`CatsEffectInLean/Model/Syntax.lean:31-205`). The registry note says the bounded counterexample uses exactly this: a child that cancels fiber 0. Scala user code cannot get a handle to the root fiber.
2. **Iteration-count sensitivity (also for Scala-expressible programs).** The left side does 2 more run-loop iterations (`Uncancelable`, `UnmaskRunLoop`). The root yields only at `cede`, async, or auto-yield every 1024 iterations (`Step.lean:1132-1144`, `FIB:226-238`). The replay scheduler switches tasks only at these points. Example (not run, by reading): `fa = start(emit c) >> (about 1020 flatMaps) >> emit r`. On one side the auto-yield comes before `emit r`, so a `pick` can run the child first (trace `[c, r]` is possible). On the other side `emit r` comes before the yield, so only `[r, c]`. The outcome sets differ, so `Eqv` fails. On the real work-stealing runtime both orders are possible on both sides. Cats Effect does not promise iteration counts. `Outcomes.lean:40-46` already gives this reason to exclude external cancels, but the same effect applies to `pick` schedules with forked fibers.

So a refutation of this statement would not be a Cats Effect bug, and a proof is impossible. That is HOLLOW.

### 3. SETTLED

Open. Correct to keep it open. Do not refute it with the forged-id counterexample.

### Fixes

1. Restrict `fa` and `env` to Scala-expressible programs. Best option: quantify over difftest programs `p` (format v0) and use `Translate.tr p` (`tools/Difftest/Translate.lean`) and the difftest `env`. Then the domain is exactly what the difftest checks. Alternative: a `WellFormed` predicate (no `.rt`, no `.unmaskRunLoop` except through a received `Val.poll`, no `.contGet`/`.endFiber`, `cancel`/`join` only on fiber values the program received).
2. Make `Eqv` insensitive to iteration counts. Options: (a) add a scheduler choice that preempts the running fiber at any iteration (this models parallel workers); (b) compare under all `autoYieldThreshold` values (union of outcome sets); (c) for this law, observe only what the Cats Effect `Eq` observes (root `Outcome`) and state the trace version separately.
3. Until then, add an `Eqv`-on-single-fiber version (no `start`, `racePair`) and prove that one first.

---

## 5. `core.IO.syncStep.syncStepIdentitySyncIO` (CE-0001, refuted)

- entry: `core.IO.syncStep.syncStepIdentitySyncIO`
- rows: 27 rows (`core.IO.syncStep#2`, `core.IO.IOAsync.syncStep`, `core.SyncStep.MaxSteps`, `core.SyncStep.interpret#2`, `core.SyncIO.unsafeRunSync`, 11 `core.SyncIO.tag.*`, 11 `core.SyncIO.runLoop.*`)
- mirror: yes for `interpret`; not checked by difftest
- property: no
- settled: yes formally; the counterexample matches reproducer case 4
- wrong-function test: fail (a correct `syncStep` also satisfies `¬P`)
- verdict: HOLLOW

### 1. MIRROR

`SyncStep.interpret` (`CatsEffectInLean/Model/SyncStep.lean:79-132`) follows `IO.scala:2348-2402` branch by branch, in the same order: `limit <= 0`, `stepsUntilDefer <= 0` (`G.defer`), `Pure`, `Error`, `Delay`, `RealTime`, `Monotonic`, `Map`, `FlatMap`, `Attempt`, `HandleErrorWith`, `Uncancelable` (guarded), `OnCancel` (guarded), default `Left(io)`. Limits and steps are decremented in the same places. The `Uncancelable` body is called without `try`, as in Scala.

Citation spot checks (all correct):

- `IO.scala:1161-1162` `syncStep(limit) = IO.asyncForIO.syncStep[SyncIO, A](this, limit)`.
- `IO.scala:2173-2178` `G.map(SyncStep.interpret(fa, limit, MaxSteps))(_.map(_._1))`.
- `IO.scala:2341` `MaxSteps = 512`.
- `IO.scala:2390-2397` the two guarded branches.
- `SyncIO.scala:590-593` `SyncIOSync ... with MonadCancel.Uncancelable`; `kernel/.../MonadCancel.scala:599` `rootCancelScope = Uncancelable`.
- `SyncIOSync` does not override `map` or `handleError`, so the cats-core defaults (`Monad.scala:34-35`, `ApplicativeError.scala:105`) apply. Correct.
- `L/AsyncLaws.scala:84-88` `syncStepIdentity`.
- Witness: `IO.scala:138-139` `*> = productR`; `SyncRef.set = F.delay(ar.set(a))` (`kernel/jvm-native/.../SyncRef.scala:32`); `IO.ref = IO(Ref.unsafe(a))` (`IO.scala:1822`).

Gap: the `SyncIO` run loop and `interpret` are not in the difftest (`wiki/cats-effect/syncio-and-syncstep-model.md` has no difftest result; format v0 has no `syncStep` op). `AGENTS.md` step 2 requires the difftest before a property.

### 2. PROPERTY

No. The schedule `cs : List SoloChoice` includes `SoloChoice.cancel` (external cancel, `CatsEffectInLean/Model/Run.lean:38-44`). The property requires both directions over all such schedules. Then the property is false for a **correct** `syncStep`:

- Take `fa = IO.delay(flag.set(true))`, any `limit > 0`.
- Direct: the schedule `[cancel 0, step _]` cancels the parked root before `run()`. `resume` (`Step.lean:1167-1173`, `FIB:1386-1389`) gives `Canceled` with `flag = false`.
- Stepped: the `SyncIO` prefix runs the thunk on the caller thread, so `flag = true` before the root fiber exists. No stepped schedule gives `flag = false`.
- So `¬ syncStepIdentitySyncIO` holds for every `syncStep` that runs at least one effect in `SyncIO`. That is the documented purpose of `syncStep` (`IO.scala:1154-1160`).

This also contradicts the project's own rationale for `Eqv` (`Outcomes.lean:29-50`): laws are compared without external cancel. The Cats Effect law check runs each side alone.

Other points:

- The single-fiber driver (`Run.lean:11-13`): `start` works, but the child never runs. For programs with children, `suspended` (a claim) can be a wrong claim. The witness is single-fiber, so the refutation is not affected, but the statement quantifies over all `fa`.
- `idPollVal = Val.poll 0 0` (`SyncStep.lean:57`). User code can tell it apart from a real `poll`; Scala user code cannot. Not used by the witness.

### 3. SETTLED

- `syncStepIdentitySyncIO_refuted : ¬ syncStepIdentitySyncIO` (`Proofs/Calibration/SyncStep.lean:167`). The type matches.
- The witness (`cxEnv`, `cxFa`) is reproducer case 4: `IO.uncancelable(_ => IO.canceled *> flag.set(true))`, `limit = Int.MaxValue`. Direct: `Succeeded(())`, `flag = true`; stepped: `Canceled`, `flag = false`. The reproducer prints `direct=true stepped=false` and `REPRODUCED CE-0001` as the last line (`bugs/CE-0001.yaml`, outputs for v3.7.1, `series/3.x`, `series/3.7.x`).
- The proof itself does not use an external cancel on the direct side (6 × `step true`), and the stepped side is closed under all choices. So the proof would also refute the cancel-free property. But the registered theorem is the weaker `¬P`.
- Harness difference: the reproducer uses `syncStep(...).to[IO]` inside a started fiber with a later `fib.cancel` (`reproducers/CE-0001/Repro.scala:48-52`, `56-65`). The Lean side uses `unsafeRunSync()` on the caller thread and runs the rest as the root. Same program and same `flag` observation, but not the same harness. Case 4 needs no external cancel (the fiber is done before `fib.cancel`), so the difference does not change the result.

### 4. WRONG-FUNCTION TEST

For a refutation the test is reversed: would a correct function also make `¬P` true?

| Function | `¬P` still true? |
|---|---|
| fixed `syncStep` (keeps the mask, upstream PR #4700) | Yes, with the witness `IO.delay(flag.set(true))` and an external cancel (section 2). The given proof fails, but the theorem stays true. |
| `syncStep = Left(fa)` at once (identity) | No for this `P`: the stepped run is then `fa` on the same heap. |
| `syncStep` that runs the whole program and returns `Right` | Yes. |

The first row makes the entry HOLLOW.

Per-row note: the witness exercises only `limit`/`steps` checks, `Uncancelable`, `FlatMap`, the default branch of `interpret`, and the `SyncIO` `Pure`/`Map`/`FlatMap` paths. If `core.SyncIO.runLoop.Attempt`, `HandleErrorWith`, `RealTime`, `Monotonic`, `Error`, `Failure`, `Success`, or `interpret`'s `Map`/`Attempt`/`HandleErrorWith` branches were "always error", the theorem would still hold. So most of the 27 rows are not covered by this entry, even after the fix below.

### Fixes

1. Remove external cancel from the schedule quantifier (use `step` choices only), or state the property with `Eqv` from `Outcomes.lean` (multi-fiber scheduler, `pick` choices only). The existing proof should carry over: the direct schedule has no cancel, and the stepped closure covers a superset of choices.
2. Difftest `syncStep` and the `SyncIO` run loop before the property (add a `syncStep` op to the difftest format, 50,000 cases, several seeds).
3. Reduce `rows` to the rows the witness exercises (`core.IO.syncStep#2`, `core.IO.IOAsync.syncStep`, `core.SyncStep.interpret#2`, `core.SyncStep.MaxSteps`, `core.SyncIO.unsafeRunSync`). Put the other `SyncIO` rows under properties that exercise them (for example `SyncIO` monad and error laws).
4. Add a reproducer case that uses the same harness as Lean: `fa.syncStep(Int.MaxValue).unsafeRunSync()`, then run the `Left` rest under `TestControl` and print the `Outcome` and the flag.
5. Optional: use the multi-fiber scheduler, so programs with `start` are not under-modelled.

---

## Wider concerns

1. **The quantification domain is larger than Scala.** `fa : IO` and `env : UserEnv` include runtime-only terms (`.rt` closures such as `.cancel 0`, `.unmaskRunLoop` with any ids, `.contGet`, `.endFiber`), and user code can forge `Val.poll`, `Val.cont`, and fiber ids. User code also reads the full `View` (all fiber outcomes, all `Deferred` cells) without an `IO` step. Proofs over this domain are stronger (fine). A refutation that needs it is not a bug. Fix: quantify over difftest programs through `Translate.tr`, or add a `WellFormed` predicate.
2. **Untyped `Val`.** Ill-typed programs abort, and an abort is "no claim". That is sound, but it lets a statement be vacuous for some inputs. Each statement should say which inputs make claims.
3. **`Eqv` sees iteration counts.** Task switches happen only at `cede`, async, and auto-yield. Two sides with different run-loop iteration counts and a forked fiber can have different trace sets (entry 4). The real runtime runs fibers in parallel. Fix: a preemption choice at any iteration, or a union over `autoYieldThreshold`.
4. **Two observation designs.** `Eqv` (multi-fiber, `pick` only) and the CE-0001 `Obs` (single fiber, with external cancel) differ. Use one design, and use the `Ext` variant only on purpose.
5. **Divergence is not observed.** A run that does not stop gives no observation. `Eqv` cannot tell "always terminates" from "sometimes diverges" when the finite observations agree. The Cats Effect `Eq` maps a run that does not complete to `Succeeded(None)` (`TestInstances.scala:199-201`). "No hang" properties need a separate statement.
6. **Single-fiber driver.** `Solo` never runs children. Statements over all `fa` that use it can make wrong `suspended` claims.
7. **Difftest gate.** The IO replay difftest passes (150,000 cases). `SyncIO` and `syncStep` have no difftest.
8. **Open entries mark rows `modelled`.** `inventory/inventory.csv` lines 2567 and 2571 are `modelled` with open entries. They should not count as progress until settled and reviewed.
9. **Low-strength laws first.** Both proven laws are "`fa` never runs" laws. They check little of the run loop. Prefer the next laws that run `fa` and finalizers (`uncancelableFinalizers`, `canceledSequencesOnCancelInOrder`, `forceRDiscardsError`).

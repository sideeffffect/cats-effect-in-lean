# Review batch 18 (2026-11-25): `std.Dispatcher.noLostSubmission` after B2

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the kernel run files, the run generator, the bug record, the raw notes, the wiki and the Scala source at `v3.7.1` (`~/Projects/cats-effect`, read only, HEAD not changed). It did not run a build, Lean, a test, sbt or a difftest. It ran only `python3 scripts/check_wiki.py`.
Reviewed commit: `022a6a5` (local `feat/p7d-dispatcher-model`: `origin/main` + track V merge + review batch 17 + the B2 fix `59afd7f`), merged into branch `docs/review-batch-18-dispatcher`.
Rubric: `AGENTS.md` section 5 (MIRROR, PROPERTY, SETTLED, wrong-function test; when unsure, the answer is no); review batch 17 (B2).
Paths are relative to `CatsEffectInLean/` unless they start with `raw/`, `wiki/`, `review/`, `bugs/`, `tools/` or `inventory/`. `DP` = `std/shared/src/main/scala/cats/effect/std/Dispatcher.scala` at `v3.7.1`.

## Summary

| Item | Result |
|---|---|
| `std.Dispatcher.noLostSubmission` | **FAITHFUL** (B2 closed) |
| conclusion `accepted j = true → status j = 2` | honest form of `DP:130-133`; true for a correct Dispatcher on `c` = canceled / never / raises |
| `accepted` | set exactly when the submission returned, both modes (`unsafeToFutureCancelable`, `unsafeRunAndForget`) |
| `dispNoLostSubmission_refuted` | exactly `¬ dispNoLostSubmission`; uses R32's `accepted 1 = true`, `status 1 = 0` |
| twin 32 (R33), `noLost_sat` (R34) | correct (kernel) |
| wrong function "always reject / throw" | vacuous here; `awaitDrains_v1` (R02, kernel) breaks it; named in registry note and battery table |
| R10–R14 | only the harness cell 6 value changed; statements keep their meaning |
| `bugs/CE-0090.yaml` `lean` | consistent |

Blockers: none. Gate batch 7.2: **PASS** (C5 still to confirm: CI green on `022a6a5`).

---

## 1. The new conclusion

### 1.1 Statement

`Props/Phase7/Dispatcher.lean:541-548` (`dispNoLostSubmissionV`), `:593` (`dispNoLostSubmission := dispNoLostSubmissionV 0`):
for all `u ho par n wc ps ms c`, `Hyp` (`:503-505`), `∀ p ∈ ps, p ≤ 1`, all `fuel`, `cs`, `oc`: if the root is done, then for each `j < ps.length`, `accepted j = true → status j = 2`. `await = true` is fixed; tasks are `IO.pure(())`; `cn = []`; `b = IO.pure(())`.

### 1.2 Is it the promise of `DP:130-133`?

`DP:130-133`: "Once the resource scope exits, depending on the termination policy all active effects will be canceled or awaited, and attempts to submit new effects will throw an exception." With `await = true`, an effect whose submission returned is active and must be awaited; a submission that is not accepted must throw. The statement claims the first half for every accepted submission. A rejected or never-made submission claims nothing. This is the CE-0090 claim exactly (`bugs/CE-0090.yaml:78-82`, "throws, or it is accepted and then runs"). Yes.

### 1.3 True for a correct Dispatcher (by reading)

- `c = IO.canceled`: the concurrent fiber (`tail`, `:371-374`) cancels itself in `.attempt x.c` before `conc` (`:375`) submits anything. No task with `ps[j] = 1` is accepted. Body tasks (`ps[j] = 0`) are submitted inside `use` on the root fiber; a correct Dispatcher awaits them. Holds. (Twin 32 and `sequential`: task 1 `accepted = false`, raw note `raw/cats-effect/2026-11-25-track-p7d-review17-b2.md`.)
- `c = IO.never`: the root waits in `joinK` (`:329-332`) and is never done. Vacuous. Correct.
- `c` raises: `.attempt` catches the error, `conc` submits as with `c = IO.pure(())`. The submission is accepted before `doneR` is set (then a correct Dispatcher awaits it) or it throws. Holds.
- Accepted and not yet run when the root is done: the root is done only after `use` returned (release ended) and after the join; a correct release (twin 32: `doneR` before the pill, the finalizer waits for the pill) either ran the task or made the submission throw. The task wrapper is `uncancelable` (`taskIO`, `:291`), `cn = []`, and `await = true` cancels nothing, so a started pure task reaches `cDone` (status 2). Holds.

It does not assume the bug away: no hypothesis on `c`, on the schedule, or on the time of the submission.

### 1.4 Is `accepted` exact?

- `submitOf` (`:294-297`) runs `.attempt (submitIO …)`; `HLam.rej` (`:343-353`) reads the result.
- `.right v`: the submission returned. `HLam.save j v'` writes cell 6 with `v' = some ()` if `v = ()`, else `v` (`:350-352`), written by `save` (`:354`). In v3.7.1 the submit thunk returns `.pair (.ref res) cancel` for `unsafeToFutureCancelable` and `.unit` for `unsafeRunAndForget` (`Std/Dispatcher.lean:852-853`). `accepted` (`:461-465`) is true for `.pair (.ref _) _` and `.some .unit`. Both modes are covered.
- `.left (.err iseErr)`: flag only (`rejected`), cell 6 not written → `accepted = false`. Other errors and other cases: nothing written → `false`.
- Gap between the return and the `save` step: no actor can cancel the submitting fiber there. The concurrent fiber starts unmasked, but its only self-cancel point is `c`, which runs before the first submission; the root holds the fiber handle and only joins it. Body submissions run on the root fiber, which nobody cancels. The root is done only after the body and the join, so every `save` has run. So `accepted` is true exactly when the call returned without throwing.
- `unsafeRunAndForget` is `unsafeToFuture(fa).onComplete(...)` (`DP:85-89`), the same submission path. "Accepted ⇒ awaited" applies to it too. Correct to include it.
- The other readers of cell 6 (`cancels`, `:355-370`; `selStart`, `:391-398`) match only `.pair (.ref _) c`; `some ()` takes the same fall-through branch as the old `()`. No behaviour change.

Answer 1: yes.

## 2. `dispNoLostSubmission_refuted`

- Type `¬ dispNoLostSubmission` (`Proofs/Phase7/DispatcherBattery.lean:174`); registry `thm` (`RegistryHeavy.lean:55`) names it; `prop` is `dispNoLostSubmission` (`:53`). Exact.
- Proof (`:175-180`): instantiate with `u id true 1 .unit [0, 1] [0, 0] p` (`p = .pure .unit`, `DispatcherCommon.lean:23`; so the input is `x90`, `:141`), `hyp_x90`, `370`, `sched 18 300`, `h.1` (root done), `j = 1`, `h.2.2.2.2` (`accepted 1 = true`); the result `status 1 = 2` contradicts `h.2.2.1` (`status 1 = 0`).
- `ce0090_accepted_never_run` (`:164-170`) = R32 `obs` (`DispatcherRuns/R32.lean:28-33`): done `Succeeded(())`, `status 0 = 2`, `status 1 = 0`, `rejected 1 = 0`, `accepted 1 = true`. R32 is not changed by `59afd7f` (mode 0 returns a pair; the `some ()` branch is not taken).

Answer 2: yes.

## 3. Twin 32 and the witness

- `noLost_twin32` (`:185-193`) has the statement's conclusion form on the R32 input and schedule (`384`, `sched 18 300`, variant 32). R33 `obs` (`R33.lean:28-34`, `decide +kernel` in `fin`): done `Succeeded(())`, `status 0 = 2`, `accepted 0 = true`, `rejected 1 = 1`, `accepted 1 = false`. `j = 0` uses `status 0 = 2`; `j = 1` uses `accepted 1 = false`. Correct (decision 39).
- `noLost_sat` (`:150-157`) = R34 (`sequential`, FIFO, 203 steps): `Hyp`, done, `accepted 0 = true`, `status 0 = 2`, `rejected 1 = 1`, `accepted 1 = false`. A real witness: the hypotheses hold, the root is done, and the implication is not vacuous for `j = 0`. The yaml calls it one run, not a proof for `sequential`. Correct.

Answer 3: yes.

## 4. Wrong-function test (decision 63)

- "Always reject / throw": nothing is accepted, so it meets the statement vacuously. "Never return" (v2, v10) leaves the root not done: vacuous. A raising factory (v13): no `accepted`: vacuous. The statement has no "root `Succeeded`" part (decision 63 (c)), so it needs a companion.
- Companion `dispAwaitDrains` (`:531-539`): `ms` non-empty body submissions must reach status 2 with root `Succeeded(())`. Any implementation that rejects every submission leaves status 0, so it fails for `ms = [0]`. Kernel: `awaitDrains_v1` (`DispatcherBattery.lean:108-109`) from R02 (`tools/DispRuns/gen.py:29`: `sequential`, `xs0`, variant 1, done, `status 0 = 0`) via `drains_break` (`:98-106`). Also v9 (R11, forget raises), v13 (R05, R18). Variant 1 is "`unsafeToFutureCancelable` raises" (`Std/Dispatcher.lean:836`).
- Named: registry note (`RegistryHeavy.lean:57`, "its success companion is std.Dispatcher.awaitDrains … awaitDrains_v1, run R02") and battery table (`DispatcherBattery.lean:49`).
- The broken function of interest (v3.7.1 on CE-0090's schedule) fails the statement (section 2); the fixed twin meets it (section 3).

Answer 4: yes.

## 5. Runs R10–R14

`git show 59afd7f` changes `R10S1`, `R12S1`, `R13S1`, `R13S2`: each only one cell-6 element, `.unit` → `.some .unit`. R11 (v9 raises) and R14 (v10 never returns) do not reach `save`, so they did not change. All use `xs1` (`cn = []`), so `cancels` takes the `none` branch and never reads cell 6. Their `obs` read `halt`, `status`, `runs` only (`gen.py:37-41`), not `accepted`. Supported statements: `awaitDrains_v9/v11` (R11, R12), `runsOnce_v12` (R13), `noDeadlock` v10 (R14), R10 (`sequential` forget, status 2). Same meaning.

Answer 5: yes.

## 6. `bugs/CE-0090.yaml`

`lean.property`, `theorem`, `registry` unchanged and correct; `run` names the B2 restatement and R32's facts; `fixed_twin` says task 1 was not accepted; `ordinary_inputs` names R34 with "accepted and ran". `expected` (`:78-82`) already reads "throws, or accepted and then runs". Consistent.

Answer 6: yes.

## 7. Verdict

| Question | Answer |
|---|---|
| MIRROR | yes (mirror `useIO'`/`submitIO` unchanged; harness change is observation only) |
| PROPERTY | yes |
| SETTLED | yes (refuted, CE-0090 with reproducer) |
| wrong-function | passes with the `awaitDrains` companion |

`std.Dispatcher.noLostSubmission`: **FAITHFUL**. B2 closed. Review 17 N3 closed: the three rows that rest on this entry (`inventory/inventory.csv`: `unsafeToFuture`, `UnsafeAsyncQueue.unsafeOffer`, `UnsafeAsyncQueue.take`) count again.

## 8. Gate: Phase 7 batch 7.2

| Item | State |
|---|---|
| 15 entries | 15 FAITHFUL (7 Supervisor open; `awaitDrains` refuted CE-0091; `noLostSubmission` refuted CE-0090; 6 Dispatcher open) |
| Batteries | both complete |
| C1, C2 | met (review 17) |
| C3 | withdrawn (confirmed, review 17) |
| C4 | open; before any Dispatcher proof, not a gate item |
| C5 | CI green on `022a6a5` (incl. `heavy-proofs`, `TwinChecks`): not checked by this review (no run allowed) |

Gate: **PASS**, on condition C5. The orchestrator must confirm C5 before Phase 8 starts.

## 9. Notes

- N1 (low): `wiki/cats-effect/dispatcher-model.md:68` says "runs R10-R14 regenerated"; only R10, R12, R13 changed (R11, R14 never save). Fix the text.
- N2 (low): statement 3 excludes `late` submitters (`p ≤ 1`). A late accepted submission is covered by `dispClosedRejects` part 2 (late ⇒ rejected when the root is `Succeeded`). Acceptable.
- N3 (low): the statement fixes tasks to `IO.pure(())` and `b = IO.pure(())`. This is the earlier, reviewed domain (review 16); the bug lives in the submission path, not in the task body.
- N4: confidence 0.85. Sections 1.3 and 1.4 are by reading; the kernel facts in sections 2–5 are by reading the theorem files, not by a build.

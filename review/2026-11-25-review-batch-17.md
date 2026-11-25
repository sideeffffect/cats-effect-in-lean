# Review batch 17 (2026-11-25): Phase 7 batch 7.2 gate re-check (after batch 16)

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the kernel run files, the difftest tool, the generator, the bug record, the raw notes, the wiki articles and the Scala source at `v3.7.1` (`~/Projects/cats-effect`, read only, HEAD not changed). It did not run a build, Lean, a test, sbt or a difftest. It ran only `python3 scripts/check_wiki.py`.
Reviewed commit: `646d12f` (local `phase6` = `origin/main` `78fd6b3` + the track V merge), on branch `docs/review-batch-17-recheck`.
Rubric: `AGENTS.md` section 5 (MIRROR, PROPERTY, SETTLED, wrong-function test; when unsure, the answer is no); review batch 16.
Paths are relative to `CatsEffectInLean/` unless they start with `raw/`, `wiki/`, `inventory/`, `review/`, `bugs/`, `difftest/`, `tools/`, `scripts/` or `lakefile.lean`. `DP` = `std/shared/src/main/scala/cats/effect/std/Dispatcher.scala`, `SV` = `.../std/Supervisor.scala`, at `v3.7.1`.

## Summary

| Item | Result |
|---|---|
| B1 `std.Dispatcher.noLostSubmission` | **not closed**: still HOLLOW (B2, a residual of B1) |
| `ce0090_accepted_never_run` (R32) | correct: shows "accepted, not rejected, never started, root `Succeeded`" |
| `dispNoLostSubmission_refuted` type | exactly `¬ dispNoLostSubmission` |
| twin 32 (R33) | meets the conclusion on the same input and schedule (kernel) |
| `bugs/CE-0090.yaml` `lean` | consistent with R32/R33/R34 |
| runs R01–R31 | not changed (no file changed; no input with a concurrent submitter) |
| C1 difftest | **met** (N1, N2) |
| C2 generator cap / fast path | **met**: sound refinement, difftest only, acceptable cost limit |
| N3 `noLeak_v11` | **closed** |
| other 13 entries (spot-check) | no new defect |
| C3 withdrawn | **confirmed** (decision 28, audit rule) |
| C4 | stays open (before any proof) |
| C5 | orchestrator item; not checked here |

Gate: **FAIL**. One blocker (B2). 14 of 15 entries FAITHFUL.

---

## 1. B1: `std.Dispatcher.noLostSubmission`

### 1.1 What changed (commit `6e9955b`)

- `Props/Phase7/Dispatcher.lean:320-331`: when `1 ∈ ps`, `use(body)` returns the concurrent fiber (`tail` → `tailK` → `retV f`, `:365-367`, `:330-331`), the root joins it (`joinK`, `:325-327`), then makes the late submissions (`afterJoin`, `:329`). Without a concurrent submitter the program is the same as before (`:324`, `:368`).
- New observation `accepted s j` (`:454-457`): cell 6 holds the `unsafeToFutureCancelable` result of task `j`.
- Statement (`:533-541`): `aw = true`, `∀ p ∈ ps, p ≤ 1`, any `c`, any schedule; if the root is done, then for each `j`: `rejected j = 1 ∨ status j = 2`. The conclusion did **not** change.

### 1.2 The `c = IO.never` hole is closed

With `c = IO.never` the concurrent fiber never ends, the root waits in `joinK`, and the root is never done. The statement holds without content for that input. Correct.

### 1.3 B2: `c = IO.canceled` breaks the statement for every Dispatcher

- `c` is any program with `AllWF` (`:487-488`). `WF.progOK` accepts `.canceled` (`Model/WellFormed.lean:193`). So `c = IO.canceled` is in the domain.
- The concurrent fiber runs `.start (.flatMap (.attempt x.c) (HLam.conc d).fn)` (`:367`, in `tail`, `:365-368`). A new fiber starts unmasked (`Fiber.new`, `mask := mm.init`, `Model/Fiber.lean:298`; `counterMaskModel.init = {}`, `:191`). `.canceled` in an unmasked fiber cancels it (`Model/Step.lean:1028-1033`). `.attempt` does not catch a cancelation. So the fiber ends `Canceled` before it submits.
- The root joins it: `IO.joinOf t (some oc) = .pure oc.toVal` (`Model/Syntax.lean:344-346`); it does not raise. `afterJoin` → `lateK` → no late task (`p ≤ 1`) → `.pure ()`. The root is done `Succeeded(())`.
- Task `j` with `ps[j] = 1` was never submitted: `rejected j = 0` and `status j = 0`. The conclusion is false.
- This holds for every Dispatcher implementation, also for fixed twin 32: the fiber cancels itself before the dispatcher sees anything. This is the same defect class as B1 (review 16, C.4: "false for every implementation, so the refutation carries no information"). Wrong-function test: "every implementation" refutes it.
- Cats Effect does not promise anything about a submission that never happens. The statement must not ask for it. A hypothesis "`c` does not cancel" would assume away a case, so it is not the fix.

I did not run this input. The argument is by reading (confidence 0.85). The model steps are short and each one is cited above.

Fix (small; the kernel fact is already there):

- Change the conclusion to the CE-0090 claim exactly: `accepted s j = true → status s j = 2` (review 16, C.4, option 2). Keep the join (it is harmless and makes "root done" mean "every submission returned").
- `dispNoLostSubmission_refuted`: use `h.2.2.2.2` (`accepted 1 = true`) and `h.2.2.1` (`status 1 = 0`) of `ce0090_accepted_never_run`. R32 needs no new run.
- `noLost_twin32`: add `accepted 1 = false` (or `status 1 = 2`) to R33's `obs`. The `rej` branch on `IllegalStateException` writes only the flag, not cell 6 (`:339-345`), so `accepted 1 = false` is expected; the kernel must show it.
- `noLost_sat` (R34): add the same `accepted` fact.
- Update the registry note, `bugs/CE-0090.yaml` (`lean.run`, `fixed_twin`) and `wiki/cats-effect/dispatcher-model.md`.

Check of the fixed form: for a correct Dispatcher with `aw = true`, an accepted submission (it returned before the root is done: the body's ones before `use` returns, the concurrent ones before the join returns) must run to its end before the release ends (`DP:130-133`: "all active effects will be ... awaited"). Pure task, no cancel (`cn = []`), uncancelable task wrapper (`taskIO`, `:287`): status 2. So the fixed statement is true for a correct Dispatcher and false for v3.7.1 (R32). Wrong-function test: twin 32 meets it on R32's input; "always throw" also meets it, but `awaitDrains` breaks that (review 16, C.5).

### 1.4 Kernel facts and the refutation (as they are now)

- `ce0090_accepted_never_run` (`Proofs/Phase7/DispatcherBattery.lean:161-167`) = R32 `obs` (`DispatcherRuns/R32.lean:28-33`): `halt = done Succeeded(())`, `status 0 = 2`, `status 1 = 0`, `rejected 1 = 0`, `accepted 1 = true`, with `parallel`, `aw = true`, `x90 = pureInp [0, 1] [0, 0] [] p p` (`DispatcherCommon.lean:141`), `sched 18 300`, 370 steps. This is "submitted, accepted (no throw), never started, root `Succeeded`". Correct.
- `dispNoLostSubmission_refuted : ¬ dispNoLostSubmission` (`:171-178`): exactly the negated registered type (`RegistryHeavy.lean`, `thm`). The proof instantiates the statement with `x90` and R32. Valid. But the statement is HOLLOW (B2), so the refutation does not count.
- `noLost_twin32` (`:183-191`) = R33 `obs` (`R33.lean:26-29`): done `Succeeded(())`, `status 0 = 2`, `rejected 1 = 1`; so the conclusion holds for `j < 2`. Same input and schedule. Correct for decision 39.
- `noLost_sat` (`:150-154`) = R34: `sequential`, default schedule: done, `status 0 = 2`, `rejected 1 = 1`. One run, and the yaml says so.
- `bugs/CE-0090.yaml` `lean` (`property`, `theorem`, `run`, `fixed_twin`, `ordinary_inputs`): consistent with R32/R33/R34 and with review 16's request.

### 1.5 R01–R31

`git show --stat 6e9955b` changes only R32–R34 among the run files. The R01–R31 inputs are `xs0`, `xs1`, `xcn`, `xlate`, `xce`, `xsl`, `xcan` (`Proofs/Phase7/DispatcherCommon.lean:127-139`); none has `1 ∈ ps`, so `afterCells` and `tail` take the old branches (`:324`, `:368`). The runs did not change. Confirmed.

## 2. C1: difftest with the final harness

- Track P7D (`wiki/cats-effect/dispatcher-model.md:70`): `opcount.py --seeds 91 92 93`, cases 0–40,500 per seed: 121,500 cases, 121,500 agree, 0 unsupported. Per op: `dUse` 103,049, `dSubmit` 93,792, `dForget` 60,535, `dCancel` 52,132, `dPoll` 79,625; each about a third per seed.
- Track V (`raw/cats-effect/2026-11-25-track-v-supervisor-notes.md`, "C1 run"): seeds 81–83 × 19,500: 58,500 cases, 58,498 agree in the run, 2 `hang` (Lean batch timeout, restart cases `g81-872`, `g82-3489`), both agree when rerun without the timeout. Per op `supUse` and `supervise` 51,137 (17,035 / 17,052 / 17,050).
- Harness state. `git diff 211706f HEAD -- difftest tools/Difftest CatsEffectInLean/Std CatsEffectInLean/Model` is empty: the track V run used the final harness. `git diff 5e248c7 HEAD` on the same paths changes only `difftest/py/gen.py` (the `supervise` bound) and `tools/Difftest/Main.lean` (the fast path above 5 entries): the P7D run used the final model, the final Scala side (`-XX:hashCode=2`, `pollVal` fix, `DispatcherShim`), and an older Lean outcome-set selection that is also a subset of the full set. Both runs check refinement against the same model.

Verdict: **met**. Each op in scope has ≥ 50,000 agreeing cases over 3 seeds at 100 %. Two runs instead of one is acceptable: the P7D run differs from the final harness only in the track V scenario bound and a Lean-side selection that is never weaker than the full set; the track V run covers the new bound on the exact final harness.

- N1: the 2 timeouts are not mismatches and no case was deleted; the rerun used the same case and the same harness. Acceptable. The rerun output is recorded in the raw note only; keep it with the run logs if they are kept.
- N2: the per-op count of the track V C1 run (51,137) is equal to run 2 (cap 5). This is plausible (scenario choice comes before the `supervise` count), but the note does not say how many C1 cases had 6–8 `supervise` calls. The 222-case evidence for 6–8 calls is separate. Record that number at the next track V run.

## 3. C2: the 5-`supervise` cap and the fast path

- Generator (`difftest/py/gen.py:883-886`, `:909`): bound 8 (`sup_left = 8 - k`), probability 0.35. Nested children do not supervise again (`depth < 1`). Cap lifted as asked.
- Fast path (`tools/Difftest/Main.lean:76-90`): `puts ≤ 5` → every order (unchanged); `puts > 5` → `ks = 0`, only the insertion-order replay (plus the `ptMaxLen` alternatives, which are also members of the outcome set).
- Only the difftest tool uses it. `supOrder`/`rankOrder`/`supPutsMax` occur only in `tools/Difftest/*.lean` and a doc comment of `Model/ParTraverse.lean:55`. `git diff 58ef474 HEAD -- CatsEffectInLean/Model CatsEffectInLean/Std CatsEffectInLean/Props` changes only `Props/Phase7/Dispatcher.lean` (the B1 harness). The statements keep `IsOrder ho` (`Props/Phase7/Supervisor.lean:380`, `:388`, `:399`; `Props/Phase7/Dispatcher.lean:491`, `:495-497`). The witnesses use `ho = id`, one allowed order. The batteries are statements with a variant number, so they also quantify over all orders.
- Soundness: the check is "the Scala outcome is in a subset of the Lean outcome set". A pass implies refinement. The short-cut can give a false mismatch, never a false agreement. So it is a stated cost limit, not a weaker gate.
- N6 of review 16 (insertion order for larger maps). My reading of `ConcurrentHashMap.putVal`: with all hashes equal, all entries are in one bin, appended at the tail; `treeifyBin` runs only when a ninth entry is added to a bin that has 8 nodes (`binCount >= TREEIFY_THRESHOLD`), and below table size 64 it resizes instead; a resize with one hash bit keeps the list as one run. So up to 8 entries the Scala order is the insertion order. `Unique.Token` has no own `hashCode` (`kernel/shared/src/main/scala/cats/effect/kernel/Unique.scala:30`). The bound of 8 is inside the safe range, and in any case a wrong Scala order would show as a mismatch, not hide one.

Verdict: **met**.

## 4. N3: `noLeak_v11`

- `Proofs/Phase7/SupervisorRestartWitness.lean:27-34`: `theorem noLeak_v11 : ¬ supNoLeakV 11`. The type is the registered statement `supNoLeakV` (`Props/Phase7/Supervisor.lean:378-383`) with variant 11. The input satisfies the hypotheses (`isOrder_id`, `cv = 0 ≤ 1`, `allWF_of`): `aw = false`, restart on, one `IO.never` child, body `IO.cede`. Kernel facts (`decide +kernel`): root done `Errored(aeFiberErr)`, child status 1.
- Variant 11 (`Std/Supervisor.lean:1087`): `flags := if v == 11 then true else !canceled && !done`, the guard of `SV:209` (`if (!canceled && !done && restart(oc))`) without the flags. An honest wrong function (not Cats Effect code).
- `noLeak_v0_restart` (`:36-41`): v3.7.1 on the same input ends `Succeeded(())`, child status 3, user code started once. Good contrast.
- In the twin-check list: `scripts/check_twin_checks.sh` (`theorems`, `...SupervisorRestartWitness.all_checks`) and `lakefile.lean:60-61` (`TwinChecks` roots). Closed.
- Low: the module doc says "about 9 minutes"; the raw note says 188 s in `TwinChecks`. Not a defect.

## 5. Spot-check of the other 13 entries

- The B1 harness change touches only inputs with `1 ∈ ps`. Statements that allow such inputs: `dispRunsOnce` (every state; no loss), `dispClosedRejects` (part 2: late tasks after the join; the late tasks still come after `use` returns, so the claim keeps its strength). No witness or wrong-function theorem of these entries uses `x90` (section 1.5).
- Track V: no change to `Std/Supervisor.lean` or `Props/Phase7/Supervisor.lean` since review 16 except `SupervisorWitness.lean` (2 lines) and the new witness module.
- No new defect found. The review-16 verdicts stand.

## 6. C3 (withdrawn)

Confirmed. `tools/Audit/Core.lean:160-190` (decision 28): a `modelled` row needs a named `proven` or `refuted` entry; `open` entries can name `todo` rows. The 13 rows link only to open entries. Review 16's C3 was my error of rule. `todo` is correct.

- N3 (new): three rows are `modelled` only through `std.Dispatcher.noLostSubmission`: `std.Dispatcher.unsafeToFuture`, `std.Dispatcher.UnsafeAsyncQueue.unsafeOffer`, `std.Dispatcher.UnsafeAsyncQueue.take` (`inventory/inventory.csv:2806`, `:2829`, `:2830`). While that entry is HOLLOW, these rows do not count as passing review. They count again when B2 is fixed.

## 7. Gate: Phase 7 batch 7.2

### 7.1 Entries

| Entry | Verdict |
|---|---|
| 7 `std.Supervisor.*` (open) | FAITHFUL (statement), unchanged |
| `std.Dispatcher.awaitDrains` (refuted, CE-0091) | FAITHFUL, unchanged |
| `std.Dispatcher.noLostSubmission` (refuted, CE-0090) | **HOLLOW** (B2) |
| 6 other `std.Dispatcher.*` (open) | FAITHFUL (statement), unchanged |

### 7.2 Verdict

**FAIL.** Blocker:

- **B2** (residual of B1): `dispNoLostSubmission` is still false for every Dispatcher: with `c = IO.canceled` the concurrent submitter cancels itself before it submits, the root joins it and ends `Succeeded(())`, and the never-submitted task has `rejected = 0` and `status = 0`. Fix: conclusion `accepted j = true → status j = 2`; refutation from the existing kernel fact of R32; add `accepted 1 = false` to R33 and R34 `obs`. Then re-check (a short one: only this entry).

Conditions:

- C1: met.
- C2: met.
- C3: withdrawn (confirmed).
- C4: open, before any Dispatcher proof (recorded in `wiki/cats-effect/dispatcher-model.md:68`).
- C5: CI green on the commit that closes B2 (including `heavy-proofs` and `TwinChecks`).

## 8. Notes

- N1: track V C1 timeouts: acceptable (section 2).
- N2: record the number of 6–8-`supervise` cases in a track V C1-style run (section 2).
- N3: three inventory rows rest only on the HOLLOW entry (section 6).
- N4: Rule for harness statements (extends the review-16 rule): if a "root done" claim reads the effects of a user-started fiber, the conclusion must be about events that happened (here "accepted"), not about events that the user program can stop.

# Review batch 7 (2026-11-14): `parTraverseN` (batch 6.3, track G) and the heavy-proof split (decision 55, track P)

Reviewer: independent agent. It did not write the code. It read the Lean source, the witnesses, the smoke test, the registry, the inventory, the difftest generator and self-test diffs, the audit tool, the CI scripts and workflows, the wiki and review batch 6. It did not run a build, Lean, a test, sbt, scala-cli or `gh`.
Reviewed commit: `5132899` (`origin/main` `543528b` plus the batch 6.3 merge).
Rubric: `AGENTS.md` section 5 and `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test, vacuous hypotheses, satisfiability witness (decision 53), harness privacy (decision 56), reviewer evidence rule). When unsure, the answer is no.
Scala source: `~/Projects/cats-effect` at `eb0cc258` (tag `v3.7.1`, read only, HEAD not changed). Short names: `K/GC` = `kernel/shared/src/main/scala/cats/effect/kernel/GenConcurrent.scala`, `K/MS` = `kernel/.../MiniSemaphore.scala`, `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`. cats-core 2.13.0 from the coursier sources jar. Lean paths are relative to `CatsEffectInLean/` unless they start with `tools/`, `scripts/`, `difftest/` or `.github/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `core.IO.parTraverseN.resultOrder` | open | **HOLLOW** (false for every implementation: user `f` captures an internal `Deferred` through a number field) |
| `core.IO.parTraverseN.pureSucceeds` | open | **HOLLOW** (only defect: the `as.length ≤ 4` model limit is not a documented precondition; low severity) |
| `core.IO.parTraverseN.errorAborts` | open | **HOLLOW** (limit; and every other action is fixed to `IO.never`) |
| `core.IO.parTraverseN.cancelAborts` | open | **HOLLOW** (same as `errorAborts`) |
| `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` | proven (heavy) | **FAITHFUL** (low strength: `race = never` also satisfies the law; one doc citation wrong) |

Heavy-proof split (decision 55): the main + heavy pair runs every old check on every push, with **four gaps** (section "CI split"). The largest: the heavy modules are built **outside the bwrap sandbox** that the old single gate used (`lake check`).

Good work in batch 6.3, for the record: the mirror body is faithful to v3.7.1 branch by branch (one Scala precedence trap found and fixed); the difftest calls the real `IO.parTraverseN` (`difftest/src/main/scala/cats/effect/difftest/Interp.scala`, new case `ParTraverseN`); all four satisfiability witnesses are kernel-checked and complete; the smoke test has three wrong-function checks; the generator change did not lower a self-test gate and deleted no case.

---

## Mirror check (shared by the four `parTraverseN` entries)

Files: `Model/ParTraverse.lean:1-630`; Scala `K/GC:145-249`, `K/MS:41-92`, `IO:977-980`, `:1593-1594`, `:1822`, `:1824`, `:1996-2031`, `IODeferred.scala:62-79`; cats `instances/list.scala:121-174`, `Traverse.scala:289-309`.

Body, line by line. Each item: Scala, then model. All match.

- `F.deferred flatMap preempt` (`K/GC:150`) = `parTraverseNIO` (`:310-311`). `F.ref(Set())` (`K/GC:151`) = `k1` (`:428-432`). `MiniSemaphore[F](n)` = `F.ref(State(Queue(), n)).map(...)` (`K/MS:60`) = `k2` + `semK` (`:433-439`).
- `results.flatMap(_.sequence).onCancel(cancelAllAndJoin)` (`K/GC:245`) = `k3` (`:440-445`).
- `ta traverse` with a `StackSafeMonad` (`IO:1996`): `if (fa.isEmpty) G.pure(Nil)` else `map(traverseDirectly(fa)(f))(_.toList)` (`list.scala:121-125`); `traverseDirectly` = `foldLeft(pure(Chain.empty))((accG, a) => map2(accG, f(a))(_ :+ _))` (`Traverse.scala:289-297`) = `traverseIO` (`:347-350`) and `travM2`/`snoc` (`:446-447`). `f(a)` is pure construction, so the model's late call is not observable.
- The element lambda (`K/GC:172-176`) = `elemSel` (`:450-455`), same three cases, same order. `F.uncancelable { poll => F.deferred flatMap result => ... }` (`K/GC:177-178`) = `uncK`/`resK` (`:456-465`).
- `action = poll(sem.acquire) *> (F.unit >> f(a)).guaranteeCase{...}.void.voidError.start` (`K/GC:182-220`) = `resK` + `thenStart` (`:460-469`). `guaranteeCase` is `IO#guaranteeCase` (`IOAsync` override, `IO:2026`); `voidError` resolves through `IOAsync.handleError` (`IO:2029`) to `handleErrorWith(_ => pure(()))` = `unitH`. Same behavior; the model cites `IO:977-980` (the `IO` method), which is the same result by another path.
- Finalizer (`K/GC:183-216`) = `finK`, `compSucc`, `ifErr`, `ifCan`, `plCancelAll`, `plStartCancelAll`, `thenRelease` (`:471-497`). Same three outcome cases, same `ifM` branches, `<* cancelAll(Some(e))` vs `<* cancelAll(None).start`, then `sem.release`.
- `action flatMap { fiber => (supervision.update(_ + ...) *> preempt.tryGet) flatMap {...} }` (`K/GC:222-238`) = `fibK`, `supAdd`, `thenAfter`, `selAfter`, `finRes` (`:500-527`). The precedence note (`:123-125`) is right: `*>` binds tighter than alphanumeric `flatMap`.
- `result.get` is `cell.get()`, a snapshot of the cell at construction time (`IODeferred.scala:71`). The model passes this snapshot (`dResultGet ... snap`, `:522`; `srcResGet`, `:393-394`). Correct.
- `cancelAll` (`K/GC:154-164`) = `cancelAllIO` + `caK` + `runHalf` + `parLeaf` (`:332`, `:354-369`, `:541-544`); the `parTraverse_` tree matches `list.scala:144-174`. `cancelAllAndJoin` (`K/GC:166-168`) = `cancelAllAndJoinIO`, `ifCA`, `thenJoinAll`, `joinAllK`, `constJoin` (`:335-336`, `:550-572`); `traverse_` with a `StackSafeMonad` = `traverseVoidDirectly` (`Traverse.scala:299-309`).
- `acquire` (`K/MS:62-75`) = `acquireIO`, `acqBody`, `acqWait`, `modAcq`, `flattenK`, `dAcqWait` (`:323`, `:573-587`, `:381-382`). `release` = `state.flatModify` = `F.uncancelable(_ => F.flatten(modify(f)))` (`Ref.scala:123-124`) = `releaseIO`, `relBody`, `modRel`, `dGrant`, `wonK` (`:326`, `:588-598`).
- `F.never` = `Async.never` = `async(_ => pure(Some(unit)))` (`Async.scala:168`; `IOAsync` has no override) = `Timeout.neverIO` (`Model/Timeout.lean:147-148`). Correct.
- `Set1`..`Set4`: `setAdd` keeps insertion order and ignores a present element (`:411-412`); a fifth element stops with `setLimitCode` (`:510`).

MIRROR answer: **yes**, with one required fix: many line citations are wrong at v3.7.1 (they drift 2 to 8 lines after `K/GC:196`, and 3 to 4 lines in `K/MS`). Examples: `ifErr` cites `K/GC:196-200`, the code is at `:197-203`; `ifCan` `:203-209` → `:205-213`; `thenRelease` `:214` → `:216`; `fibK` `:220-222` → `:222-225`; `selAfter` `:222-232` → `:225-237`; `finRes` `:228-231` → `:234-237`; `embedK` `:227` → `:233`; `seqK` `:237` → `:245`; the method is `K/GC:145-249`, not `:145-251`; `acquire` `K/MS:59-72` → `:62-75`; `release` `:74-83` → `:77-86`; `modAcq` `:64-69` → `:67-73`; `dAcqWait` `:66` → `:70`; `semK` `:56` → `:60`. Batch 4 treated a wrong citation as a fix, not as HOLLOW; this review does the same.

## Difftest and generator

- The op calls the real `IO.parTraverseN(n)(xs)(a => run(f, ...))` (`difftest/src/main/scala/cats/effect/difftest/Interp.scala`, case `Prog.ParTraverseN`); the Lean side translates it to `parTraverseNIO` (`tools/Difftest/Translate.lean`, case `.parTraverseN`). In the difftest, `f` is any generated program (it can suspend, raise or cancel: `difftest/py/gen.py`, `g_par_traverse`). That domain is much wider than statements 3 and 4.
- No case deleted: `git diff --diff-filter=D 543528b 5132899` lists no file; under `difftest/cases/` only three new files (`partraverse.jsonl`, `partraverse.expected.jsonl`, `gen_v2_partraverse.py`).
- No self-test gate lowered: the `selftest.py` diff only adds `V2PT_OPS`/`V2PT_MIN = 0.02`, one more golden file, and one more coverage check. No existing constant changed. `gen.py`: the `parTraverseN` part is appended to about 8 % of cases with its own RNG (`random.Random(f"difftest-partraverse:{seed}:{i}")`), so the earlier parts of each case are unchanged; `composite_opts` did not change. Claim confirmed by reading.
- Not checked by this review (needs a run): the counts in `wiki/cats-effect/partraverse-model.md` (200,000 and 90,000 cases, all agree).
- Cosmetic: the comment of `p_runtime` moved to the `p_par_traverse` line (`gen.py`, `CONFIG`).

## Shared defect C: the `as.length ≤ 4` model limit

All four statements have `as.length ≤ 4` (`Props/Phase6/ParTraverse.lean:104`, `:112`, `:121`, `:130`). Reason given: Scala keeps the supervision `Set` as `Set1`..`Set4` up to 4 elements and as a `HashSet` (identity-hash order) above (`:25-27`).

- Does it remove the interesting case? **No.** With 4 elements there are `n < length` cases, a semaphore queue, several siblings to cancel and the `cancelAllAndJoin` join loop. The set order matters only to the order of `cancelAll`'s parallel cancels and of the joins.
- Is it a documented precondition or a type invariant? **No.** `parTraverseN` takes any `T[_]: Traverse`. So under the rubric (`AGENTS.md` section 3: "Each hypothesis must be a documented precondition or a type invariant") the PROPERTY answer is no.
- Fix (cheap relative to the rest): make the `HashSet` order an input. For example, `setAdd` above 4 elements inserts at a position chosen by an oracle `ord : List Val → Val → Nat` that the statements quantify over (all orders), or by a `PChoice`. Then drop `as.length ≤ 4`. The difftest can keep lists of at most 4 elements plus some of 5-6 (refinement: the real order must be one of the allowed orders).

## 1. `core.IO.parTraverseN.resultOrder` (open)

Statement: `parTraverseNOrder` (`Props/Phase6/ParTraverse.lean:102-107`).

### Defect D: user `f` captures an internal `Deferred` that `WellFormed` never checks

`WellFormed` (`Model/WellFormed.lean:332-335`) checks the start program with `progOK` against `H0 = []`, and each even id with `CallOK`. `CallOK` lets a user function use the handles that its closure captured (`WF.captured id`, `Model/WellFormed.lean:113-116`, `:207-212`). That is sound only if some check showed that these captured handles were held when the closure was made: `fnOK` does this for a `.user id` in a checked program (`Model/WellFormed.lean:135-137`).

Here `f` never occurs as `.user f` in a checked program. It is a number:

- the root holds `(TL.tag f).id` as `.nat` in the `k1` closure (`Model/ParTraverse.lean:196`, `:311`); `WF.captured` of `k1` is the handles of `[.nat n, as, .nat _]` = the handles of `as`;
- `TL.tag f` holds `f` as `.nat f` (`Props/Phase6/ParTraverse.lean:69`).

So nothing checks `WF.captured f`. This is the batch 6 defect A pattern (a closure id in a number field hides its handles), now in track G `parTraverseN`. The recommended "deep `captured`" fix of batch 6 is not in `WF.captured` at this commit (`Model/WellFormed.lean:113-116` is shallow).

Concrete counterexample (for the v3.7.1 mirror, so for every correct implementation):

- `as = [.nat 0]`, `n = 1`. Let `r` be the id of the element's result `Deferred` (`uncK` allocates it, `Model/ParTraverse.lean:458`). Before the first `start`, only the root fiber runs, so `r` is a fixed number of the default-schedule run.
- `f = 2 * valToNat (.deferred r)` (even; `WF.captured f = [.deferred r]`, `Model/WellFormed.lean:363` `captured_userFn`).
- `u.callV f _ _ = { out := .prog (.map (.delay (.rt (.deferredComplete r (.ocSucceeded (.pair (.nat 9) .unit))))) (.rt .voidK)) }`; every other even id throws.
- Hypotheses: `1 ≤ n`, length 1, `f` even. `progOK` of the root holds (no handle in `as`). `CallOK f`: the result does not read the heap, so `Agree` is trivial; `ResultOK`: `rtOK` needs `mem (.deferred r)` (`Model/WellFormed.lean:129`), which holds because `.deferred r ∈ captured f`; `.voidK` is allowed (`:131`). `PollOpaque`: no `Poll` anywhere, so `rnId σ f = f` and `rnResult` is the identity. So `WellFormed ptIsLib [] (env (tagged u)) (parTraverseNIO 1 [.nat 0] (TL.tag f).id)` holds.
- Run (default schedule): the child fiber runs `f(0)`, which completes `r` with `Succeeded((9, ()))`. Then the finalizer's `result.complete(oc)` returns `false` (`compSucc`, `:478-482`; `IODeferred.scala:62-69`). `sequence` reads `r` and gives `(9, ())`. The root ends `Succeeded([(9, ())])`, and `fstOf` gives `[9] ≠ [0]`.

So `parTraverseNOrder` is false in the model for the mirror itself; it cannot be proven. In Scala, `f` cannot get the internal `result` Deferred, so this input is outside the Scala domain. Statements 2-4 do not have this defect: their hypothesis fixes `f`'s result (no effect), and no other user code runs.

The smoke test does not find it: it checks only `progOK` of the root (`tools/PtSmoke/Main.lean:87`) and uses a fixed, handle-free user table (`:36-51`). Decision 53 asks that smoke tests evaluate the hypotheses; `CallOK` is not decidable, so the smoke cannot see a forging `f`.

### Rubric

1. MIRROR: yes (see the mirror check; citation fixes needed).
2. PROPERTY: no. Defect D (the domain is larger than Scala; the statement is false for every implementation) and defect C. Also: the statement is conditional on success, so "always raise an error" satisfies it alone. `pureSucceeds` closes that gap only for pure `f`.
3. SETTLED: open.
4. SATISFIABILITY: yes. `parTraverseNOrder_satisfiable` (`Proofs/Phase6/ParTraverseWitness.lean:88-97`): its type contains all hypotheses together; `orderRun_ok` is `decide +kernel` (`:84-86`).
5. WRONG-FUNCTION: a reversed result breaks it (`tools/PtSmoke/Main.lean:138-141`). "Always raise" does not.

### Fix

- Add the hypothesis that `f` captures no handle that the scope does not hold: `∀ h ∈ WF.captured f, h ∈ ([] : List Handle)` (the same check that `fnOK` makes for a `.user f` in a program). Or, better and shared (decision 56): make `WF.captured` (or `ptIsLib`/`progOK`) follow `.nat` fields that name closures, so that `k1`'s field `f` and `TL.tag`'s field are checked.
- Add the counterexample above as a Lean regression `example` that `WellFormed` now rejects (decision 56).
- Optional, to pass the wrong-function test alone: add a liveness clause for `f` that always succeeds (for example `f(a) = IO.sleep(k a) *> IO.pure(g a)`, which also forces completions out of input order), or register `resultOrder` and `pureSucceeds` as one conjunction.

## 2. `core.IO.parTraverseN.pureSucceeds` (open)

Statement: `parTraverseNPureSucceeds` (`Props/Phase6/ParTraverse.lean:110-116`).

1. MIRROR: yes.
2. PROPERTY: no, only because of defect C. Otherwise yes: all `n ≥ 1`, all `g`, all schedules (`outcomesP` includes `blocked`, `Model/Outcomes.lean:14`, `:86-89`, so a deadlock breaks the claim). Pure `f` is an ordinary input (`AGENTS.md`: the ordinary case of an exotic property). Completion order still varies, because the children run in parallel under all `PChoice` schedules.
3. SETTLED: open.
4. SATISFIABILITY: yes. `parTraverseNPureSucceeds_satisfiable` (`ParTraverseWitness.lean:111-120`, `n = 1`, two inputs, so the semaphore queue is used); `pureRun_ok` `decide +kernel` (`:104-106`).
5. WRONG-FUNCTION: a dropped result breaks it (`tools/PtSmoke/Main.lean:142-144`); "always raise" breaks it. "Ignore `n`" (unbounded parallelism) satisfies it (see "Coverage gap").

Fix: defect C only. After that, this entry is FAITHFUL as a statement.

## 3. `core.IO.parTraverseN.errorAborts` (open)

Statement: `parTraverseNErrorAborts` (`Props/Phase6/ParTraverse.lean:119-125`). Hypothesis: `f(a0) = IO.raiseError(e)` and **every other** `f(a) = IO.never` (`:122`); `a0 ∈ as.take n`.

Judgement of "the rest never end":

- What it keeps: it is the sharpest test of "immediately abort" (`K/GC:137`). If the error does not cancel the siblings, the root waits for a never-ending result and the run ends `blocked`, which breaks the claim. The smoke test shows this: without `cancelAll` the claim breaks (`tools/PtSmoke/Main.lean:53-60`, `:145-148`). Given never-ending siblings, `a0 ∈ as.take n` is necessary (a later `a0` never gets a permit), so that hypothesis is not an extra loss.
- What it removes: (a) siblings that complete. Then the success branch of the finalizer with a completed `preempt` (`K/GC:185-195`, `compSucc`) is never reached in the domain; (b) an error in an action that starts later, after earlier actions completed and released their permits (the semaphore hand-over path `K/MS:80-83` followed by an abort); (c) two actions that raise (`K/GC:138-139`: "one of them will be nondeterministically selected"); (d) siblings that run finalizers or uncancelable regions; (e) `f(a0)` that raises after it suspends (`IO.sleep(k) *> IO.raiseError(e)`). `AGENTS.md` (section 1): user code "can raise, suspend, run twice, and race with cancel". Here all user code is fixed to two constants. So **yes, it removes part of the interesting case**.

1. MIRROR: yes.
2. PROPERTY: no. Defect C, and the narrow user-code domain above.
3. SETTLED: open.
4. SATISFIABILITY: yes. `parTraverseNErrorAborts_satisfiable` (`ParTraverseWitness.lean:197-207`): all hypotheses together, `e.kind = .nonFatal` by `rfl`; the run (`errRun_ok`, `:191-195`) has a never-ending sibling that must be canceled.
5. WRONG-FUNCTION: "no `cancelAll` on error" breaks it (smoke, above). A sequential traverse breaks it (with `as = [x, a0]`, `x` never ends). "Ignore `n`" satisfies it.

Fix: let each sibling be any program from a family that cannot raise or self-cancel but can end, suspend or never end, for example `kind : Val → Option Nat` with `none` = `IO.never` and `some k` = `IO.sleep(k) *> IO.pure(g a)`; let `f(a0)` be `IO.sleep(k0) *> IO.raiseError(e)`. Replace `a0 ∈ as.take n` by the reachability condition "fewer than `n` never-ending siblings come before `a0`". For (c), add a statement with a set of raising inputs: the outcome is `Errored(e')` with `e'` one of their errors.

## 4. `core.IO.parTraverseN.cancelAborts` (open)

Statement: `parTraverseNCancelAborts` (`Props/Phase6/ParTraverse.lean:128-134`). Same shape as entry 3 with `f(a0) = IO.canceled`.

1. MIRROR: yes.
2. PROPERTY: no (defect C; the same narrow domain as entry 3; the `Some(None)` case of `compSucc`, `K/GC:190-191`, is unreachable in the domain).
3. SETTLED: open.
4. SATISFIABILITY: yes. `parTraverseNCancelAborts_satisfiable` (`ParTraverseWitness.lean:215-224`), `canRun_ok` (`:209-213`).
5. WRONG-FUNCTION: "no `cancelAll` on cancel" breaks it (`tools/PtSmoke/Main.lean:149-150`).

Fix: the same as entry 3, with `IO.sleep(k0) *> IO.canceled` for `a0`.

## Coverage gap (not a verdict)

No statement checks the concurrency limit: "The first ''n'' actions will be started first" (`K/GC:134-136`). An implementation that ignores `n` satisfies all four statements. The wiki says this is not stated yet and needs a test marker (`wiki/cats-effect/partraverse-model.md`, "Not stated yet"). With decision 56 that marker must be private by construction. Until then, `core.IO.parTraverseN` and `kernel.GenConcurrent.parTraverseN` must stay `todo` (they are `todo` now: `inventory/inventory.csv:1137`, `:1871`; the four entries only name them).

## 5. `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` (proven, heavy registry)

Statement: `Props/Phase6/Race.lean:211-216`: `EqvP {} counterMaskModel lawEnv (IOI.void (.uncancelable raceBodyFn)) Timeout.neverIO`. Scala: `GenSpawnLaws.scala:146-147`. Theorem: `Proofs/Phase6/RaceLaw.lean:47-50`; registry: `RegistryHeavy.lean:32-42`.

1. MIRROR: yes. The law text is `F.uncancelable(_ => F.race(F.never[Unit], F.canceled)).void <-> F.never[Unit]`; the lambda is the fixed user closure `raceBodyFn` (`Race.lean:200-209`) that returns `Race.raceIO src0 src1` with sides `Timeout.neverIO` and `.canceled`. Not changed since batch 4 (which checked the `race` mirror). Fix: the module doc of `Proofs/Phase6/RaceLaw.lean:7` still cites `GenSpawnLaws.scala:121-122`; the law is at `:146-147` (the `Props` file is already correct, `Race.lean:190`).
2. PROPERTY: yes. Closed law, no input; `EqvP` compares the full observation sets over all `PChoice` schedules (`Model/Outcomes.lean:155-162`). The kernel twin `Props/Kernel/GenSpawnLaws.lean:153-156` states the same law generically.
3. SETTLED: yes. `lhs_exact` (`RaceLaw.lean:40-45`) chains `edgesUpTo_zero` and 49 `edgesUpTo_chunk` steps (`Proofs/Lemmas/CertP.lean:274-299`) to `certExact_of_edgesUpTo` (`:301-312`) with `lhs_succ_length`; `rhs_exact`, `rhs_obs`, `lhs_obs` are `decide +kernel`. `outcomesP_iff_of_certObsOnly` (`CertP.lean:317-329`) then gives `outcomesP lhs o ↔ o = blockedEmpty` and the same for the right side, so `EqvP` follows. The certificate is untrusted data; a wrong one makes a check `false`, not a wrong theorem (`CertP.lean:20-24`, `:229-262`). (`lhs_chunk_0` is used twice; the `edgesUpTo_zero` use only supplies the state list, so this is harmless.) The registry names the theorem with a single backtick (`RegistryHeavy.lean:36`); `audit_heavy` checks the exact type and the axioms (`tools/Audit/Core.lean:138-149`).
4. WRONG-FUNCTION: no Lean file tests a wrong `race` for this law (searched: `Props/Kernel/GenSpawnLaws.lean`, `Props/Phase6/Race.lean`, `Proofs/Phase6/RaceLaw*.lean`). By reading: a `race` that ran its children under the outer mask would make `F.canceled` a no-op, the race would return `Right(())`, and the left side would end `Succeeded`, not `blocked`. But `race = never` also satisfies the law. That is a weakness of the law itself, not of this entry. Low strength, as for the other proven laws (batches 1-3).

Verdict: FAITHFUL (low strength). The inventory row `laws.GenSpawnLaws.uncancelableRaceNotInherited` is `modelled` and names only this entry (`inventory/inventory.csv:2555`); `core.IO.race` and `kernel.GenSpawn.race` stay `todo` (`:1052`, `:1918`). Correct.

---

## CI split (decision 55): is main + heavy at least as strong as the old single gate?

Files: `lakefile.lean:66-77`, `RegistryHeavy.lean:1-45`, `tools/Audit/{Core,Main,MainHeavy}.lean`, `scripts/check_heavy_proofs.sh:1-57`, `.github/workflows/ci.yml:17-66`, `:133-150`, `.github/workflows/paranoid-heavy.yml:1-42`, `.github/workflows/paranoid.yml:1-39`, `scripts/test_audit.sh:73-93`, `QUESTIONS.md:25-30`.

What holds:

- Every registry check runs on every push in one of the two jobs. Main: `checkEntry` with `full := false` for heavy entries skips only the theorem lookup; `prop`, status/theorem/bug consistency and ids still run (`Core.lean:116-158`, `:211-212`); ids are unique across both registries (`:207-208`). Heavy: `verifyHeavy := true` imports `heavyModules` and checks heavy theorems in full, and the inventory cross-check uses no deferral (`MainHeavy.lean:25-33`, `Core.lean:221`).
- The main audit never counts a deferred row as settled: `settled` excludes deferred ids (`Core.lean:183`); a deferred row only adds to `nDeferred` (`:186`). A `modelled` row named only by an `open` heavy entry still fails in the main job (`heavy_open_modelled_main`, `test_audit.sh:92`).
- Fail-closed for drift between `lakefile.lean` roots and `heavyModules`: if a heavy theorem is not in an imported module, `audit_heavy` reports "does not exist" (`Core.lean:141`).
- The heavy script stops on any error (`set -euo pipefail`, `check_heavy_proofs.sh:15`; `out=$(...)` propagates the exit status). Axioms: `audit_heavy` runs `collectAxioms` on every heavy theorem (`Core.lean:149`), transitively; the explicit `#print axioms` (`:35-47`) is a second check.
- `leanchecker` per module: the hard-coded list (`:19-24`) is today the full non-default closure of `RaceLaw` (`RaceLawCertLhs`, `RaceLawCertRhs`, `RaceLawDefs`, `RaceLawChunks0..9`, `RaceLaw`); the other imports (`Proofs.Lemmas.CertP`, `Props.Phase6.Race`) are in the default target (`CatsEffectInLean.lean:74`) and the main `lake check` replays them.

Gaps:

1. **No sandbox for the heavy build (regression).** The old single gate built every proof inside `lake check`'s bwrap sandbox (`ci.yml:40-51`). The wiki gives the reason: Lean runs arbitrary code at build time, and without the sandbox agent-written code could tamper with the check (`wiki/lean/toolchain-v4-35.md:31`). The heavy job builds with plain `lake build` (`check_heavy_proofs.sh:26-30`), and then builds `audit_heavy` from `tools/` and runs it in the same workspace. Build-time code in a heavy module can rewrite `tools/Audit/Core.lean`, `inventory/inventory.csv` or the script's later inputs before they are used. `leanchecker` replays the `.olean` declarations, so a forged proof term is still caught; but the audit verdict (exact type, inventory) is not protected. `paranoid-heavy.yml:34-35` also builds without the sandbox. Fix: build the heavy modules with `lake check`-style sandboxing (`bwrap` with only `.lake` writable, as `lake check` does), or build `audit_heavy` and copy the inputs to a read-only place **before** the heavy modules build, then run the audit from that copy.
2. **The main audit passes with a deferred row** (by design: `heavy_missing_thm_main` passes, `test_audit.sh:87`). So "never accepted by the main audit alone" holds only if `heavy-proofs` is a required status check. That is open (`QUESTIONS.md:25-30`, Q4); today the default is agent discipline. With direct pushes to `main` no check blocks anything, so the old gate and the new pair are equal there; for pull requests, the pair is weaker until Q4 is answered.
3. **Hard-coded module and theorem lists in the heavy script.** `mods` (`check_heavy_proofs.sh:19-24`) and the `#print axioms` file (`:38-41`) name the `RaceLaw` family and one theorem. A new heavy root or helper module would be built (`lake build HeavyProofs`, `:30`) and audited (`audit_heavy` covers its axioms), but **not replayed by `leanchecker`**, not built one module at a time, and not in the explicit axiom check. Fix: derive the module list from the import closure of `heavyModules` minus the default-target closure (a small Lean exe or `lake` query), generate the `#print axioms` lines from `registryHeavy`, and fail if a `.lean` file in that closure is missing from the list.
4. **`paranoid-heavy.yml` coverage is not shown.** It exports only `CatsEffectInLean.Proofs.Phase6.RaceLaw` (`paranoid-heavy.yml:40`). The wiki notes that `leanchecker M` replays only module `M` (`wiki/methodology/registry-and-audit.md:65`). If `leanexport M` has the same scope, the weekly paranoid run replays only the 52-line root, not the 49 chunks. The run time is not measured (`QUESTIONS.md:28`). The reviewer cannot confirm the export scope by reading. Fix: export every module of the heavy closure (or show that `leanexport` includes the imports), and record the export size and declaration count of the first run.

Minor:

- The explicit axiom grep (`check_heavy_proofs.sh:44`) parses `[...]` on one line. If Lean wraps a long axiom list over lines, `bad` is empty. `audit_heavy` still catches it, so this is not a gap today.
- `test_audit.sh` has no `heavy_bad_axiom_full` case. The axiom code path is shared with the main entries (`Core.lean:149`), so the risk is low.

Answer: **yes for the checks themselves** (every check runs on every push, a deferred row is never counted as settled by the main job, the heavy script fails on any error and checks the axioms of every registered heavy theorem through the audit, and `leanchecker` covers every heavy declaration today). **No for the trust boundary** (gap 1: no sandbox) and **not proven for the future** (gap 3: hard-coded lists) and for the weekly paranoid run (gap 4).

## Required fixes

1. Track G, entry 1 (defect D): check `f`'s captured handles (hypothesis, or a deep `captured` in the shared privacy module of decision 56); add the forging `f` above as a Lean regression `example`.
2. Track G, all entries (defect C): make the `HashSet` order an input (oracle or choice) and drop `as.length ≤ 4`; or, if the team keeps the limit, record it as a model limit in `AGENTS.md`-level rules first (a user decision, not an agent decision).
3. Track G, entries 3-4: widen the sibling and `a0` programs as described; add the "multiple errors" statement.
4. Track G: fix the `K/GC` and `K/MS` citations listed in the mirror check; fix `Proofs/Phase6/RaceLaw.lean:7`.
5. Track G (coverage): state "at most `n` actions run at once" after the privacy module exists.
6. Track P: sandbox the heavy build (gap 1); derive the module and theorem lists (gap 3); widen or verify the paranoid export (gap 4); keep Q4 open until the user answers.

## Confidence

- Defect D makes `parTraverseNOrder` false for the mirror: 0.85 (read `WellFormed`, `captured`, `fnOK`, `rtOK`, `k1`, `TL.tag`, `compSucc`, `IODeferred.complete`; not run; the exact id `r` was not computed, only its existence).
- The mirror matches v3.7.1 branch by branch: 0.85 (all bodies read; cats-core helpers read in the 2.13.0 sources jar).
- Defect C and the entry 3-4 domain judgement: 0.8 (rubric reading; the limit does not remove the interesting case).
- Race law FAITHFUL: 0.85 (statement, root proof, `CertP` soundness lemmas read; chunk modules and `EnumP.outcomesP_sub_closed` not read line by line).
- CI gap 1 (no sandbox): 0.9. Gap 4 (export scope): 0.5 (not checked by reading).

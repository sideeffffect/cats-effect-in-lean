# Review batch 6 (2026-11-14): re-review of 5 Phase 6 entries (tracks G and Res)

Reviewer: independent agent. It did not write the code. It read the Lean source, the proofs, the smoke tests, the bug record, the reproducer, the registry, the inventory, the wiki, the raw fix notes and review batches 4 and 5. It did not run a build, Lean, a test, sbt or scala-cli. It did not run `gh`.
Reviewed commit: `b12aa58` (`origin/main`).
Rubric: `AGENTS.md` section 5 and `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test, vacuous hypotheses, fixed-twin check (decision 39), satisfiability witness (decision 53), harness-only markers (decision 54), reviewer evidence rule). When unsure, the answer is no.
Scala source: `~/Projects/cats-effect` at `eb0cc258` (tag `v3.7.1`, read only). Short names: `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`, `RES` = `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`, `MC` = `kernel/.../MonadCancel.scala`. Lean paths are relative to `CatsEffectInLean/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `core.IO.bracket.releaseOnce` | open | **HOLLOW** (forgeable marker: false for every implementation) |
| `core.IO.guarantee.finalizerOnce` | open | **HOLLOW** (same defect) |
| `kernel.Resource.both.releaseOnce` (CE-0020) | refuted | **HOLLOW as registered** (forgeable names: a correct `both` also refutes it). The bug is real; the witness is genuine. |
| `kernel.Resource.use.releaseOnce` | open | **HOLLOW** (forgeable names: false for every implementation) |
| `kernel.Resource.flatMap.releaseOrder` | open | **HOLLOW** (same defect) |

Not re-reviewed (statement not changed since batches 4 and 5; checked with `git diff 567db50 HEAD` and `git diff 2c9c077 HEAD` on the two `Props` files, and no `Model/` change since `2c9c077`): `core.IO.bracketFull.kernelDefaultTwin.pureUse`, `laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO`, `kernel.Resource.eval.preservesCancelable`. Their new satisfiability witnesses (`Proofs/Phase6/BracketWitness.lean:126-136`, `:197-209`) have types that contain all hypotheses of the statement together. Good.

Progress since batches 4 and 5 is real: the hypotheses are now satisfiable (kernel-checked witnesses), the batch-4 contradiction is gone, and the batch-5 forgery through `ULam.allocFn` is closed by the deep name scan. But both new harnesses still have a forgery path. Each is a new path, not the old one:

- Track G: the counter handle hides inside a **number** field of a `Bracket` closure. `WellFormed` sees only top-level handles.
- Track Res: the `NoForge` escape clause ("a user result may mention a harness name if its argument does") lets user code use a **number that the runtime gives it** (the clock of `IO.realTime`) as a marker id.

---

## Shared defect A (track G): a `Bracket` leaf hides the counter handle in a number

Files: `Props/Phase6/Bracket.lean:172-231`, `Model/Bracket.lean:224-233`, `:270-288`, `:349-363`, `:457`, `:465-509`, `Model/WellFormed.lean:113-116`, `:135-136`.

The harness protects the counters with handles: an external source code `srcAcq c = .pair (.ref c) (.nat 0)` holds the handle `.ref c`, so a user program that names `BLam.constThis (Src.ext (srcAcq 0)).toVal` directly must hold `Ref` 0 (`Props/Phase6/Bracket.lean:172-176`). That part is correct.

But `WF.captured id` reads only the handles in the closure value of `id` (`Model/WellFormed.lean:113-116`, `Val.handles` at `:97-105`). A closure field that is the **id of another closure** is a plain `Val.nat`. Its handles are not seen. `Bracket.BLam.good` accepts a `Bracket` leaf (`constThis`, `constFin`) as a function field with no check on what the leaf captures (`Model/Bracket.lean:469-473`, `:490`).

Concrete forgery (any `bracket` implementation):

- Let `T = (BLam.constThis (Src.ext (srcAcq 0)).toVal).id`. `T` is odd and holds `.ref 0`, but user code never names it directly.
- User function `rel` (even id) returns `.flatMap (.pure .unit) (BLam.thenUse T .unit).fn`.
- `WellFormed`: the `thenUse` closure value is `cloVal 7 25 [.nat T, .unit]` (`Model/Bracket.lean:233`). It holds no handle, so `captured = []`. `BLam.good (.thenUse T _) = fnOK T` (`:490`), and `fnOK T = leafOK T = true` because `BLam.ofId? T = some (.constThis _)` (`:469-473`). So `isLib` is true (`:502-505`) and `WF.fnOK` accepts it (`Model/WellFormed.lean:136`). `CallOK` and `PollOpaque` hold for a constant result with no handle and no poll.
- Run: `henv` sends the `thenUse` id to `Bracket.call` with no `good` check (`Props/Phase6/Bracket.lean:221-227`). `.thenUse` calls `callFn` on `T` (`Model/Bracket.lean:457`), `callLeaf` runs `constThis` as `srcIO (hioOf a0) src` (`:353`), and `hioOf a0 (srcAcq 0) = .flatMap a0 (HLam.markA 0).fn` (`Props/Phase6/Bracket.lean:181`). This bumps counter 0 a second time.
- Take the witness of `bracketReleaseOnce_satisfiable` (`Proofs/Phase6/BracketWitness.lean:98-106`) and change only `rel` to this function. Release runs uncancelable, so in every run where acquire completed and release ran (also the witness run shape): `count o 0 = 2`, `count o 1 = 1`. The root ends `done`. So `count o 1 = count o 0` is false for the v3.7.1 mirror and for every correct `bracket`.

`guaranteeFinalizerOnce`: the same with `q` returning `.flatMap (.pure .unit) (BLam.thenUse (BLam.constThis (Src.ext (srcFa 0 6)).toVal).id .unit).fn` and user id 6 = `_ => IO.unit`. The forged program runs `IO.delay(markThunk 0) *> IO.unit` (`Props/Phase6/Bracket.lean:182`). In a run where `fa` started, `count o 0 = 2 > 1 = count o 1`. (With `srcFin 1 6` instead, `count o 1 = 2 > 1`.) Other vectors: `constFin` leaves, and `gcBody src k` / `relA rel a` with a leaf in the function field.

The doc comment says a good `BLam` "takes only user functions or `Bracket` leaves as function fields ... a marker is neither" (`Props/Phase6/Bracket.lean:99-100`). That is true, but a `Bracket` leaf is itself a carrier of the counter source code. This is the "library closures storing ids as numbers" path that the track Res note describes (`raw/cats-effect/2026-11-10-track-res-review5-fix-notes.md`, "A handle in the marker's own id does not stop forwarding"); track G did not apply it to its own leaves.

## Shared defect B (track Res): the `NoForge` escape clause and runtime numbers

Files: `Props/Phase6/Resource.lean:136-167`, `Props/Phase6/HarnessNames.lean:36-57`, `Model/Step.lean:964-966`, `Model/Step.lean:531`, `Model/Sched.lean:164`.

`NoForge` clause 1 (`Props/Phase6/Resource.lean:162-163`): a user result mentions a harness name only if its argument does. The intent is "user code may pass on what it got". But the deep scan treats every number as a possible name (`HarnessNames.lean:17-20`), and the runtime gives user code numbers that user code controls: `IO.realTime` and `IO.monotonic` return `.nat clock` (`Model/Step.lean:964-966`), and `IO.sleep d` moves the clock to `clock + d` (`Model/Step.lean:531`, `Model/Sched.lean:164`). In Scala a `FiniteDuration` is not a function; in the model a number is also a function id. So a number from the clock can be the harness name `.nat (2 * mR)`, and the escape clause then lets user code return a program that runs the marker.

Concrete forgery for `useReleaseOnce` (any `use` implementation). Start from the witness environment `WU` (`Proofs/Phase6/ResourceWitness.lean:65-90`, `ResourceWitnessEnv.lean:33-60`: `mA = 1`, `mR = 3`, marker R has program id 6, `badUse = names (.nat 20) 0 0 1 3`, which contains `.nat 6`). Change only:

- user index 5 (id 10, not used by `WU` with `failA = false`): `_ => IO.realTime`;
- user index 6 (id 12, the release rest `q`): on argument `.nat 6` return `.prog (.delay (.user 6))`; on any other argument return `.prog (.pure .unit)` (as before);
- `a0 = .flatMap (.flatMap (.sleep 6) (.user 10)) (.user 12)`, so `acquire 0 = .map a0 (uid 1)`.

Check of the hypotheses:

- `MarkedMake`: `mentionsIO badUse a0 = false`, because `.sleep` gives `false` and ids 10 and 12 are clean. Ids 10 and 12 are proved clean for `badBoth ⊇ badUse` in `ResourceBoth.lean:73-79` (`q = 5`, `q = 6`), and `mentionsV` is monotone in `bad`. `mentionsV bad (.nat 12) = false` is unchanged.
- `NoForge` clause 1: id 10 returns `.realTime`, which mentions nothing. Id 12 returns a program that mentions `.nat 6` only on argument `.nat 6`, and `.nat 6 ∈ badUse`, so `mentionsV badUse (.nat 6) = true`. Clauses 2-5 are as in `use_noForge`.
- `EmitsOnly`: ids 10 and 12 emit nothing. `A ≠ R`. `mentionsV bad (.nat 14) = false` unchanged.
- `WellFormed`: id 12's result names the even id 6 (no captured handle, see Confidence; id 6 is already in the `PollOpaque` list of `env_opaque`, `ResourceWitnessEnv.lean:110`). Its result depends only on its argument, and a poll renaming does not change `.nat 6`.
- Run (no parent): acquire runs `sleep 6`; the clock jumps to 6; `realTime` gives `.nat 6`; id 12 runs marker R (emit R); `map (uid 1)` emits A; `f` returns `IO.unit`; release emits R. The root ends `Succeeded`. `count R = 2 ≠ 1 = count A`.

So `useReleaseOnce` is false for every implementation. The same edit works for `flatMapReleaseOrder` (`badFlat` contains `.nat 6`) and for `BothReleasesBothFor impl` for every `impl`, including `fixedBothRes` (`badBoth` contains `.nat 6`). The escape clauses of `NoForge` clauses 2 and 4 (`Bind` results and other release programs) have the same hole: a user resource whose acquire is `IO.realTime` gives its release the argument `.nat 6`.

Secondary path (not needed for the verdict, lower confidence): a resource code `c = .unit` is allowed. Then `.unit ∈ bad`, every argument `unit` "mentions" a name, and clause 1 lets `f` return the marker directly. Also, at the depth bound `scanV` answers "mentions" (`HarnessNames.lean:49-51`); on the argument side of the escape clause this conservative answer helps a forgery, it does not stop it.

---

## 1. `core.IO.bracket.releaseOnce` (open)

- verdict: **HOLLOW** (defect A: false for every implementation)

1. MIRROR: yes. `bracketIO` → `bracketCaseIO` → `bracketFullIO` (`Model/Bracket.lean:295-301`) = `IO:338-339`, `:370-371`, `:1826-1830` (checked). The bodies of `call` for `bfBody`, `bfK`, `deferEv`, `gcBody`, `gcOnError`, `gcTap` follow `IO:1828-1829` and `IO:523-530` (checked; reviewed in batch 4). Row note: `kernel.MonadCancel.bracket` (`MC:397-398` → `bracketCase` `:423-425` → `bracketFull(_ => acquire)`) has the same body as `IO#bracket` at `IO`, so the row is covered in substance; it is not a separate Lean term.
2. PROPERTY: no.
   - The claim is right: release runs exactly once iff acquire completed (`count o 1 = count o 0`), in a child that the parent cancels at any point (decision 50). The harness `relW` bumps the counter when release starts, before `rel(a)` (`Props/Phase6/Bracket.lean:208`), so a throwing or hanging `rel` is covered. A `.fatal` throw ends the run with summary `fatal`, not `done` (`Model/Sched.lean:120`), so it is not counted. Good.
   - Hypotheses: `use`, `rel` even (the user-id encoding: a type invariant); `WellFormed isLib [] (henv a0 u) a0` (decision 27, a type invariant; it checks every even id globally, `Model/WellFormed.lean:332-335`). These remove no interesting case.
   - But the marker is forgeable (defect A). The statement cannot be proved for a correct `bracket`.
3. SETTLED: open. OK as a status, but no proof can exist for the current statement.
4. SATISFIABILITY (decision 53): yes. `bracketReleaseOnce_satisfiable` (`Proofs/Phase6/BracketWitness.lean:98-106`) is kernel-checked (`relRun`, `decide +kernel`, `:84-85`). Its type contains all three hypotheses together and a run with `done (succeeded ocCanceled)`, counters `1, 1`: the interesting case (cancel after acquire).
5. WRONG-FUNCTION: `childOf` `g = 2` (no release) breaks the claim on `(.pure (.nat 5), 2, 4)` (`test/Phase6/BracketSmokeParent.lean:65-66`, `#guard`, compiled). Pass in spirit; moot while defect A is open.

## 2. `core.IO.guarantee.finalizerOnce` (open)

- verdict: **HOLLOW** (defect A)

1. MIRROR: yes. `guaranteeIO` = `Uncancelable(gBody)` (`Model/Bracket.lean:289`), `gBody`/`gOnError`/`gTap` = `IO:496-501` (checked). The row list is now only `core.IO.guarantee` (batch-4 fix 4 done, `Registry.lean:277-278`).
2. PROPERTY: no. The claim (`count o 1 ≤ 1 ∧ count o 0 ≤ count o 1`: at most once, and it runs if `fa` started) is right, and `a0 = IO.unit` is irrelevant to `guarantee`. But defect A makes it false for every implementation.
3. SETTLED: open.
4. SATISFIABILITY: yes. `guaranteeFinalizerOnce_satisfiable` (`BracketWitness.lean:110-118`, `finRun` `:87-88`, kernel), counters `1, 1`, child canceled.
5. WRONG-FUNCTION: `g = 3` (no finalizer) breaks it (`BracketSmokeParent.lean:70-71`). Moot while defect A is open.

## 3. `kernel.Resource.both.releaseOnce` (CE-0020, refuted)

- verdict: **HOLLOW as registered**; the bug is real, the witness is genuine.

1. MIRROR: yes. No `Model/` change since batch 5, which checked `foldLoop`, `useIO`, `bothRes`, `evalMapRes`, `updateThunk`, `bothRel` against `RES:156-208`, `:286-314`. I re-read `RES:156-176`, `:205-208`, `:248-257`, `:286-314`: the citations are correct.
2. PROPERTY: no, as registered. The promise (`RES:248-257`; each acquired resource released once) and the witness (two `make`, a raising release, `use(_ => IO.unit)`) are sound. But defect B makes `¬ BothReleasesBothFor fixedBothRes` true as well, so the statement does not separate v3.7.1 from a fix (decision 39; batch-2 and batch-5 precedent).
3. SETTLED: yes for the theorem. `bothReleasesBoth_refuted` (`Proofs/Phase6/ResourceBoth.lean:96-102`) has the type `¬ bothReleasesBoth`. The run is kernel-checked (`run_witness`, `:52-55`, trace `[RA, B, A]`, `Errored(boom)`). All hypotheses are proved: `markedA`, `markedB` (`:73-79`), `emits` (`:81-84`), `both_noForge` (`:57-71`), `prog_wf` (`:86-87`), `Nodup` and `mentionsV (.nat 14)` by `decide +kernel` (`:100`). This is also the satisfiability witness. Bug record `bugs/CE-0020.yaml:100-105` names the property, theorem and twin. The reproducer now prints `REPRODUCED` only if the fixed copy misses no release (`reproducers/CE-0020/Repro.scala:118-119`; batch-5 recommendation 6 done).
4. FIXED TWIN: `ResourceBothFixed.fixed_satisfies` and `old_violates` (`Proofs/Phase6/ResourceBothFixed.lean:71-94`), kernel (`decide +kernel` in `fixed_0`..`fixed_11`, `:47-69`), in `lean_lib TwinChecks` (`lakefile.lean:47-57`). The domain is honestly described (`:6-11`, `:18-19`): one input (the witness environment), 120 schedules "FIFO for `k` choices, then `pick d`", `60 ≤ k < 120`, `d ∈ {1, 2}`, fuel 6000; "Not checked: all schedules". The registry note and the bug record say the same. Good. But this checks the conclusion on one input; with defect B the statement is false for the twin on another input.
5. INVENTORY: `kernel.Resource.fold`, `use`, `both` are still `modelled` with this entry (`inventory/inventory.csv:2257`, `:2258`, `:2264`). Batch 5 asked to set them to `todo` until this entry passes review (only `makeCase` and `evalMap` went back, `:2274`, `:2296`). The registry `rows` still lists `kernel.Resource.makeCase` and `kernel.Resource.evalMap` (`Registry.lean:327-328`), which are not mirrored in general.

## 4. `kernel.Resource.use.releaseOnce` (open)

- verdict: **HOLLOW** (defect B: false for every implementation)

1. MIRROR: yes (`useIO`, `foldLoop`, `IO.bracketFull`; no `Model/` change).
2. PROPERTY: no, because of defect B. The other parts are good: the parent is now a harness closure (`Props/Phase6/Resource.lean:69-117`, `isLibH`), so no user-code `PollOpaque` case is needed; `MarkedMake`, `EmitsOnly` and `names` describe the harness only.
3. SETTLED: open.
4. SATISFIABILITY: yes. `use_sat` (`Proofs/Phase6/ResourceWitness.lean:65-90`) for both values of `viaParent`; its type contains every hypothesis of `useReleaseOnce` for one instance, plus a run that ends with `count A = 1`, `count RA = 1`. Kernel-checked.
5. WRONG-FUNCTION: not re-checked by me in Lean; moot while defect B is open.

## 5. `kernel.Resource.flatMap.releaseOrder` (open)

- verdict: **HOLLOW** (defect B)

1. MIRROR: yes (`Res.flatMap` = `Bind`; `fold` nests `bracketFull`).
2. PROPERTY: no (defect B). The `Before o.out RA RB` part is right (`out` is newest first). The hypothesis `∀ x, U.r.bind k x = .ok (Res.make acqB relB)` describes the harness `flatMap` function; good.
3. SETTLED: open.
4. SATISFIABILITY: yes. `flat_sat` (`ResourceWitness.lean:112-139`), both `viaParent`, kernel; the run has trace `[RA, RB, B, A]` (LIFO).

## Required fixes

1. Track G (defect A). Make the capability check see handles inside closure fields. Options:
   - A deep `captured`: when a closure field is a number that decodes to a closure (`Codec.cloOfId`), add that closure's captured handles, recursively. This is also more faithful to Scala: a closure that captures a closure that captured a `Ref` holds the `Ref`. Change it in `Bracket.isLib`/`leafOK` (local), or in `WF.captured` (global; then re-check every proof that uses `WellFormed`).
   - Or a deep scan as in track Res: a hypothesis that no user result mentions `.ref 0` or `.ref 1` (`HarnessNames.mentionsR [.ref 0, .ref 1]`), with **no** escape clause.
   - Then add a Lean check that the forgery above is rejected (as `MemoizeSat.forged_*` does for track M).
2. Track Res (defect B). Remove the escape clause from `NoForge` clauses 1, 2 and 4: user results, user `Bind` results and other release programs never mention a harness name. The library never gives a harness name to user code in these programs (the module doc says so, `Props/Phase6/Resource.lean:29-31`), so the clause buys nothing. The existing proofs carry over: `userR_clean` already proves that no user result mentions a name (`ResourceWitnessEnv.lean:90-94`). Document that the conservative scan now excludes user code that returns some data numbers (a smaller domain, not a forgery).
   - Alternative: give runtime data numbers (clock) a type that the scan does not treat as an id. That is a larger model change.
3. After 1 and 2: re-prove `bothReleasesBoth_refuted`, `use_sat`, `flat_sat`, and the track G witnesses (they use no forgery, so they should carry over), and add a smoke or Lean check that the two forgeries of this review are rejected.
4. Inventory: set `kernel.Resource.fold`, `use`, `both` to `todo` until CE-0020 passes review; remove `kernel.Resource.makeCase` and `kernel.Resource.evalMap` from the CE-0020 `rows` (or add general mirrors).

## Confidence

- Defect A satisfies all hypotheses of entries 1 and 2: 0.9 (read `Bracket.good`/`leafOK`/`call`, `WF.captured`/`fnOK`, `henv`; not run).
- Defect B satisfies all hypotheses of entries 3-5: 0.85 (read `NoForge`, `scanAux`, `Step` clock, `Sched` timers, the witness environment; not run; the one unproved detail is that `WF.captured 6` is empty: `cloOfId 6 = natToVal 3`, a code of 2 bits, which cannot hold a handle value).
- CE-0020 is a real, public, non-duplicate defect: 0.9 (unchanged from batch 5).

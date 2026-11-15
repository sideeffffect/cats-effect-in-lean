# Review batch 8 (2026-11-15): harness privacy (decision 56), `parTraverseN` (track G), heavy CI matrix (decision 57, track P)

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the witnesses, the probe checks, the smoke test, the audit tool, the CI scripts and workflows, and the wiki. It did not run a build, Lean, a test, sbt or `gh`.
Reviewed commits: `cf362d7` (track Res round 6, with track G `fe38330` and `origin/main` `cd23dac`), checked out as branch `review8`; track P `bd1483c` (read with `git show`, not checked out).
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 56, "Reviewer evidence"); decision 57. When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `tools/`, `scripts/`, `bugs/`, `reproducers/` or `.github/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `core.IO.bracket.releaseOnce` | open | **HOLLOW** (F1: a `Src.ext` code hides a counter event id in a number field; the probe used another `ioOf`) |
| `core.IO.guarantee.finalizerOnce` | open | **HOLLOW** (F1) |
| `kernel.Resource.both.releaseOnce` (CE-0020) | refuted | **FAITHFUL** |
| `kernel.Resource.use.releaseOnce` | open | **HOLLOW** (scope S1; no forgery found) |
| `kernel.Resource.flatMap.releaseOrder` | open | **HOLLOW** (scope S1; no forgery found) |
| `core.IO.parTraverseN.resultOrder` | open | **HOLLOW** (F2: defect D of batch 7 is still open through `Timeout` `fold` with a `.some` fallback source) |
| `core.IO.parTraverseN.pureSucceeds` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.errorAborts` | open | FAITHFUL as a statement (special case of `errorAbortsGen`) |
| `core.IO.parTraverseN.cancelAborts` | open | FAITHFUL as a statement (special case of `cancelAbortsGen`) |
| `core.IO.parTraverseN.succeedsGen` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.errorAbortsGen` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.cancelAbortsGen` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.atMostN` | open | **HOLLOW** (F3: user code writes the semaphore state `Ref` through the F2 path; also S1) |

CI (track P, `bd1483c`): the pair main + heavy is at least as strong as the old single gate. Batch 7 gaps 1, 3 and 4 are closed in the scripts. Six small residuals remain (section "CI").

Privacy design: **not converged**. The token construction (`HarnessPrivacy.tokFreeV`) held against every attack that I tried. The `Lib.fields` lists did not: two new forgeries (F1, F2) pass the deep `WellFormed`, and both pass a probe lemma that is kernel-checked. Section "Design view" gives the reason and a proposal.

---

## Scope A: harness privacy

### What holds

- `HarnessPrivacy.tokFreeV` (`Props/Phase6/HarnessPrivacy.lean:57-73`) decodes **every** number leaf as a possible closure id, recursively, to depth `WF.capDepth = 64`, and answers "not free" at the bound. So a token name in a returned value, in a `Ref` write (`tokFreeEff`, `:98-102`), in an allocation, in a callback value or in a program term is rejected. "Function ids returned inside values or stored in a `Ref`" is closed for the **token** by `UserPrivate` (`:113-114`) and by `Private` (`Props/Phase6/Resource.lean:193-198`). I found no path for user code to name `markA`/`markT` of the `Resource` harness or `CL.enter`/`CL.exit` of the `parTraverseN` harness.
- Depth bound: at the bound `capturedD` gives `none` (`Model/WellFormed.lean:144-153`), `capOK` rejects, `captured` gives `[]` (`:156`), `freeD` gives `false` (`HarnessPrivacy.lean:67-69`). Each choice makes a hypothesis stricter, not weaker. Safe.
- The coercion `Nat → Bool` to `Lib` (`Model/WellFormed.lean:124`) elaborates to `Lib.idFree`, and the audit check `lib-fields` finds `Lib.idFree` and `Lib.mk _ (fun _ => [])` in the transitive definitions of `prop` (`tools/Audit/Core.lean`, `usesFieldlessLib`). Fixtures: explicit, literal, through a definition (`test/AuditFixtures/Props.lean`). There is no fixture for the coercion itself (minor).
- `memoLib` (`Props/Phase6/Memoize.lean:172`) is `Lib.idFree` by declaration, with a `libNote`. By reading, its sources are `.nat 0` (`fa`) and `.ref c` (`srcIO`, `:119-122`), and `Timeout` number fields are durations (`Model/Timeout.lean:107-118`). So no closure id is in a number field: the claim holds. `raceLib` (`Props/Phase6/Race.lean:123`): sources are `.nat 0`/`.nat 1` (`:67-70`); the claim holds. `queueLib`: not read in depth (out of scope). `limLib` is not id-free; it has fields (`Props/Phase6/ParTraverse.lean:380-386`).

### F1 (new forgery): `Bracket` external source with a harness id in a number field

`Bracket.Src.fnIds` (`Model/Bracket.lean:510-513`) gives `[]` for an external source `Src.ext s`; so `fnFields` of `constThis (Src.ext s)` is `[]` (`:526`, `:530-536`). The design assumes that `s` is data. But the statements run the mirror with `ioOf = hioOf` (`Props/Phase6/Bracket.lean:180-184`), and `hioOf` reads two number fields of `s` as **function ids**:

```lean
| .pair (.ref c) (.pair (.nat 1) (.nat k)) => .flatMap (.delay (HLam.markThunk c).fn) (.user k)
| .pair (.ref c) (.pair (.nat 2) (.nat q)) => .flatMap (.delay (HLam.markThunk c).fn) (.user q)
```

Counterexample for `bracketReleaseOnce` (`Props/Phase6/Bracket.lean:247-252`):

- `allocF` (even, captures nothing): effect `allocRef (.nat 0)`, result `.ret (.ref v.refs.length)`. `mkF` (even, captures nothing): on `.ref r` it returns the program `.flatMap (.pure .unit) (BLam.constThis (Src.ext (.pair (.ref r) (.pair (.nat 1) (.nat (HLam.markA 1).id))))).toVal).fn`; on any other argument `.prog (.pure .unit)`. `a0 = .flatMap (.delay (.user allocF)) (.user mkF)`. `use`, `rel` return `IO.unit`.
- `WellFormed lib [] (henv a0 u) a0`: `progOK` of `a0` holds (two even ids without handles). `CallOK allocF`: the result reads only `refs.length`, which `Agree` fixes; the new cell is held after `allocRef`. `CallOK mkF`: `fnOK` of the `constThis` id: `isLib` holds (`constThis` is good, `Model/Bracket.lean:494`); `capOK`: the captured handles are the handles of the closure value, `[.ref r]`, plus nothing from `fields`; `.ref r` is in the argument. `PollOpaque`: no `Poll` in any result. So all hypotheses hold.
- Run: the child's acquire is `a0.flatMap(markA 0)`, masked. `a0` allocates cell `r ≥ 2`, then the `constThis` closure runs `srcIO hioOf` (`Model/Bracket.lean:320-322`, `:428`): `IO.delay(markThunk r)` bumps the user cell `r`; then `.user (HLam.markA 1).id` runs `HLam.call (.markA 1)`, which bumps **counter 1** (release) and returns `IO.pure`. Then `markA 0` bumps counter 0, `use` runs, the release bumps counter 1 again. In every run where the child starts, the end state is `count 1 = 2`, `count 0 = 1`. The conclusion `count o 1 = count o 0` is false for the v3.7.1 mirror, so for every implementation.
- `guaranteeFinalizerOnce` (`:257-262`): the same construction inside the body `k` (code `.nat 2`, or `.nat 1`) bumps counter 1 twice: `count o 1 ≤ 1` is false.

Why the earlier checks miss it:

- `PrivacyExamples` (`Proofs/Phase6/PrivacyExamples.lean`, section `TrackG`) tests only codes whose `.ref c` is the counter (`srcAcq 0`, `srcFa 0 6`). Here the bumped cell is the user's own cell `r`; the harness id sits in the other field.
- `LibFieldsBracket.check` runs `Bracket.call recUC (fun s => .pure s)` (`Proofs/Phase6/LibFieldsBracket.lean:38-39`): `ioOf` is `pure`, not `hioOf`. So `fields_complete` is true, but it says nothing about the environment of the statements. The registry notes of both entries say that the deep `Lib` rejects the forgery class; the probe lemma does not imply that.
- The `Resource` harness is safe from the same trick only because `Private` decodes every number: `tokFreeV` would decode `(HLam.markT …).id` inside the source code and find the token.

Fix (either): (a) use the token construction for the `Bracket` statements too: add `UserPrivate (henv a0 u) [.ref 0, .ref 1]` and `tokFreeIO a0`; or (b) make `Bracket.lib.fields` statement-specific (decode the number leaves of `Src.ext` codes that `hioOf` reads) and run `LibFieldsBracket` with `hioOf`. Add F1 to `PrivacyExamples` as a regression example.

### F2 (defect D of batch 7, still open): `Timeout.fold` with a `.some` fallback

`ptIsLib` admits every `Timeout.TLam` that parses (`Props/Phase6/ParTraverse.lean:73-78`; `Model/Timeout.lean:121-133`: `5, [fb, .nat d] => some (.fold fb d)`, `fb` any value). `TLam.fold fb d` on `.ocCanceled` runs `fallbackOf srcIO fb d` (`Model/Timeout.lean:206-209`), and `fallbackOf` runs `srcIO c` for `fb = .some c` (`:155-158`). In the `parTraverseN` environment `srcIO = ParTraverse.ioOf`, which turns `srcAction f a` into `PT.callF f a` and calls `f` (`Model/ParTraverse.lean:387-391`). But `srcFnIds` looks only at a code itself or under `.left` (`:417-423`), not under `.some`. So `ptFields` of `TLam.fold (.some (srcAction f x)) d` is `[]`, and the handles that `f` captured are not checked.

Counterexample for `parTraverseNOrder` (`:135-140`): `as = [.nat 0]`, `n = 1`; `fForge = 2 * valToNat (.deferred r)` with `r` the result `Deferred` of the element (a fixed id of the default run); `fForge` completes `r` with `(9, ())` (the batch 7 program). The traversed `f` returns `.flatMap (.pure .ocCanceled) (TLam.fold (.some (srcAction fForge (.nat 0))) 3).fn`. `CallOK f` holds (the `fold` closure value holds no handle; `fields` gives nothing). `CallOK fForge` holds (`captured fForge = [.deferred r]`). The run gives `Succeeded([(9, ())])`, `fstOf` gives `[9] ≠ [0]`. The batch 7 analysis of the run applies unchanged.

Why the probe misses it: `LibFieldsParTraverse.others` samples only `TLam.body` and `TLam.sel` (`Proofs/Phase6/LibFieldsParTraverse.lean:48-58`); there is no `fold`, `thenJoin` or `embed` sample and no coverage lemma for `TLam`, `RLam` or `BLam` in this file (only `covers` for `PT`). `ResourceUse` does it right: `srcCodeIds` walks every position, `.some` too (`Model/ResourceUse.lean`, `srcCodeIds`), and `LibFieldsResourceUse` has `covers_tlam`.

Fix: decode `.some` (better: every position, as `srcCodeIds` does) in `srcFnIds`; add `fold`/`thenJoin`/`embed` samples with `.some` sources and coverage lemmas for `TLam`, `RLam`, `BLam`; add F2 to `PrivacyExamples`.

### F3: the semaphore state of statement 8

`UserPrivate` protects only the token `.ref 0` (`Props/Phase6/ParTraverse.lean:388`). Other internal cells are protected only by `WellFormed limLib`, whose `fields` are `ptFields` plus `CL.fnIds` (`:380-386`). So F2 works here too: `g` returns the `TLam.fold (.some (srcAction fForge …))` program, and `fForge = 2 * valToNat (.ref q)` (the `MiniSemaphore` state `Ref`, `k2`) writes `(Queue(), 1000)` into `q`. `UserPrivate` holds for both results: no token, and the decoded `fold` value names only `.ref q`. With `n = 1`, `as = [1, 2]`, `g = _ => IO.cede *> IO.pure(_)` and a schedule where the first child writes `q` before the root's second `acquire`, the second action starts while the first is at its `cede`: `highest = 2 > 1`. So `parTraverseNAtMostN` is false for the mirror. Confidence 0.75 (not run; the schedule exists because `PChoice` can preempt at any iteration).

### S1 (scope): `UserPrivate` and `Private` exclude ordinary Scala user code

`UserPrivate` quantifies over **all** arguments (`HarnessPrivacy.lean:113-114`). For any token name `t`, `x => IO.pure(x)` returns `.prog (.pure t)` on argument `t`, and `tokFreeV` rejects it. So every user function that copies a number from its argument into its result is outside the domain. Examples: `make(acq)(rel).use(a => IO.pure(a))`, a release `a => IO.println(a)`, `g = a => IO.pure(a)` in statement 8.

- Decision 56 item 6 allows only "user code cannot name a harness token". Item 3 says runtime numbers are user data. In this model a number is both data and a closure name, so the two items conflict, and the implementation took the strict reading.
- It is not a documented precondition or a type invariant of Scala (`AGENTS.md` section 3): in Scala an `Int` can never be a closure.
- It probably does not hide a release-once bug (release accounting does not depend on value flow). It is the same kind of defect as the `as.length ≤ 4` limit of batch 7 (defect C): a model limit that needs a user decision.
- For a refutation (CE-0020) a narrower domain makes the result stronger, so S1 does not affect CE-0020.

### S2 (domain larger than Scala): `REnv` programs of other codes are not checked

The Phase 6 `Resource` statements check `a0` and the non-harness `acquire`, `release`, `bind` and `resOf` results only with `tokFree*` (`Props/Phase6/Resource.lean:183-198`), not with `progOK`. Phase 5 has this check (`Model/Resource.lean:438-442`, `REnv.WellFormed`). So these programs can hold `EndFiber`, forged polls, and fiber/`Deferred` runtime closures without a held handle. I did not find a run of `use`/`flatMap` where this breaks release accounting (`make.use` allocates no internal cell). It is a risk for the open entries and for any later `Resource` statement. Fix: add the Phase 5 clauses (with `libH`) to `Private` or as a separate hypothesis.

### Probe lemmas: what they imply

| Lemma | Implies | Does not imply |
|---|---|---|
| `LibFieldsBracket.fields_complete` | `Bracket.call` itself uses only listed fields, with `ioOf = pure`, view `{}`, the `args` shapes | anything about `hioOf` or `PT.ioOf` (F1) |
| `LibFieldsParTraverse.fields_complete` | the `PT` constructors (all, `covers`) and the sampled `Bracket`/`Race`/`Timeout` shapes, with the real dispatcher | `TLam.fold`/`thenJoin`/`embed`, `.some` sources (F2); no coverage lemma for the other families |
| `LibFieldsResourceUse.fields_complete` | all five families with coverage lemmas and the real dispatcher | `REnv` lookups (`probeU` fixes them to `pure`; S2) |

Shared limits (stated in `Model/LibProbe.lean`, confirmed): every call runs in the view `{}`, so branches that depend on heap contents are not reached; number leaves below 256 are skipped (`headerNat`, `:62`; samples use probes for function fields, so this is safe for the samples I read); an output closure that keeps a probe in an unlisted field passes the test of that call (`progOK` sees no handle), and is caught only if that closure family has its own sample with the same shape and a reaching argument.

### Witnesses (decision 53) against the deep hypotheses

- CE-0020: `bothReleasesBoth_refuted` (`Proofs/Phase6/ResourceBoth.lean:76-82`) applies the statement to `wellFormed _ _ _ _`, which proves `WellFormed libH […] harness` (`Proofs/Phase6/ResourceWitnessEnv.lean:116-118`) with `libH.fields = ResourceUse.fnFields` (deep), and to `both_private` (`ResourceBoth.lean:56`, `Private` in full). The theorem type is `¬ bothReleasesBoth`. Meets the deep hypotheses.
- CE-0030: `memoLib` is `Lib.idFree`; for this library deep and shallow agree (see "What holds"), so the witness meets the deep hypothesis.

---

## Entries, scope A

### `core.IO.bracket.releaseOnce` (open), `core.IO.guarantee.finalizerOnce` (open)

1. MIRROR: yes (the `Bracket` mirror is unchanged since batch 6).
2. PROPERTY: **no**. F1: the statements are false for every implementation.
3. SETTLED: open.
4. Wrong-function: by reading of the batch 6 smoke (`test/Phase6/BracketSmokeParent.lean`), a bracket without release breaks it; not re-opened in this batch.
5. Decision 53: the witnesses exist (`PrivacyExamples` names `BracketWitness.bracketReleaseOnce_satisfiable`, `guaranteeFinalizerOnce_satisfiable`).

Verdict: HOLLOW.

### `kernel.Resource.both.releaseOnce` (refuted, CE-0020)

1. MIRROR: yes (mirror reviewed in batches 5-6; this round adds only the `Timeout` dispatch in `uDisp` and `isLib`, `Model/ResourceUse.lean`, which corrects a model bug that the probe found).
2. PROPERTY: yes (documented Scaladoc invariant, `Resource.scala:248-257`; S1 narrows the domain, which only makes a refutation stronger).
3. SETTLED: yes. Theorem `¬ bothReleasesBoth`; witness meets all hypotheses (above); run `decide +kernel` (`ResourceBoth.lean:51-54`, `run_witness`); bug record `bugs/CE-0020.yaml` with outputs on v3.7.1, `series/3.x`, `series/3.7.x`, each ending `REPRODUCED CE-0020`; the reproducer prints `REPRODUCED` only if the fixed copy misses no release (`reproducers/CE-0020/Repro.scala`, last lines).
4. Fixed twin (decision 39): `ResourceBothFixed.fixed_0..` (`Proofs/Phase6/ResourceBothFixed.lean:48-66`), 120 schedules, kernel-checked. S2 means a correct `both` might also be refuted with a non-Scala `a0`; I did not find such a run (a non-Scala `b0` that ends its fiber gives `blocked`, which the statement excludes).

Verdict: FAITHFUL.

### `kernel.Resource.use.releaseOnce`, `kernel.Resource.flatMap.releaseOrder` (open)

1. MIRROR: yes.
2. PROPERTY: **no** (S1: the hypothesis `Private` removes ordinary Scala user code; not a documented precondition). No forgery found. S2 is an open risk.
3. SETTLED: open.
4. Decision 53: `ResourceWitness.use_sat`, `flat_sat` (named in `PrivacyExamples`).

Verdict: HOLLOW (scope). If the user accepts S1 as a documented model limit, both become FAITHFUL as statements.

## Scope B: `parTraverseN`

### Shared

- MIRROR: yes for the body (batch 7 checked it branch by branch; this round changes only function fields and the set encoding). Set encoding (`Model/ParTraverse.lean:443-462`): `Set1`..`Set4` keep insertion order; a fifth element makes a `HashSet`; `-` keeps a `HashSet`. I did not open the Scala 2.13 `Set.scala` source in this batch; the encoding matches the documented behavior.
- HashSet order as an input: `ord : List Val → List Val` with `(ord xs).Perm xs`, quantified universally. This is a correct over-approximation: the real order is a function of the element set, so every real order is allowed. It can only make an open statement false for a non-bug reason (an order that no `HashSet` gives). For these claims the order affects only the order of parallel cancels in `runHalf` and of the sequential joins; outcomes do not depend on it. Safe.
- Difftest: inputs have at most 4 elements (`difftest/py/gen.py:107`, `g_par_traverse`, `:789-798`; `wiki/cats-effect/partraverse-model.md:8`). So the `HashSet` branch and `ord` are not differentially tested, but every statement now quantifies over all lengths. `AGENTS.md` section 2 asks for agreement before a property. Required fix: add cases with 5-6 elements and compare by refinement over all orders.
- `outcomesP` keeps only result summaries (`Model/Outcomes.lean:86-89`, `:99-106`): out of fuel and task limit are not results, `blocked` is. So "every run that stops" includes deadlocks. Correct.

### Statements 5-7: the behaviour harness

`behaved bh` (`Props/Phase6/ParTraverse.lean`, `BL`, `stepIO`, `behCall`) gives `f(a) = IO.cede` `k` times, then `pure`, `raiseError`, `canceled` or `never`. Judgement: a fair extra statement. It is Scala code without handles, so it needs no `WellFormed`; cedes plus `PChoice` give every interleaving; `never` is the async `IO.never`. It does not hide anything that statements 1-4 cover. It does not cover: finalizers or `uncancelable` regions inside `f`, `f` that starts fibers, and suspension that ends (async with a callback). These are not in any `parTraverseN` statement now; a later statement could add an `uncancelable(_ => never)` base (expected hang) and an `onCancel` base.

### `core.IO.parTraverseN.resultOrder` (open)

1. MIRROR: yes. 2. PROPERTY: **no** (F2: false for every implementation). Also, as batch 7 noted, "always raise" satisfies it alone. 3. SETTLED: open. 4. Wrong-function: a reversed result breaks it (`tools/PtSmoke/Main.lean:249-252`). 5. Decision 53: `parTraverseNOrder_satisfiable` (`Proofs/Phase6/ParTraverseWitness.lean:100`).

Verdict: HOLLOW.

### `core.IO.parTraverseN.pureSucceeds` (open)

1. MIRROR: yes. 2. PROPERTY: yes (defect C of batch 7 is fixed by `ord`; `f` pure is an ordinary input; no other user code is reachable, so F2 does not apply). 3. SETTLED: open. 4. Wrong-function: a dropped result breaks it (`tools/PtSmoke/Main.lean:255-257`); "ignore `n`" satisfies it, and `atMostN` is meant to catch that. 5. Decision 53: `parTraverseNPureSucceeds_satisfiable` (`ParTraverseWitness.lean:123`).

Verdict: FAITHFUL as a statement.

### `core.IO.parTraverseN.errorAborts`, `cancelAborts` (open)

1. MIRROR: yes. 2. PROPERTY: yes as the sharpest special case. The narrow domain of batch 7 is now covered by `errorAbortsGen`/`cancelAbortsGen`; with `bh a0 = (0, err e)` and `never` for the others, statement 6 implies statement 3 (only `a0` raises, and `a0 ∈ as.take n` gives `nevers < n`). 3. SETTLED: open. 4. Wrong-function: no `cancelAll` breaks them (`tools/PtSmoke/Main.lean:260-262`). 5. Decision 53: `ParTraverseWitness.lean:212`, `:230`.

Verdict: FAITHFUL as a statement. Advice: record them as corollaries of 6 and 7, or merge.

### `core.IO.parTraverseN.succeedsGen`, `errorAbortsGen`, `cancelAbortsGen` (open)

1. MIRROR: yes. 2. PROPERTY: yes. The permit condition `nevers bh (as.take i) < n` is the exact reachability condition (an earlier error also aborts, and the conclusion allows any raised error). Statement 7 excludes errors, so `Canceled` is the only result. 3. SETTLED: open. 4. Wrong-function: no `cancelAll` on the random tables breaks 6 and 7 (`tools/PtSmoke/Main.lean:268-270`); for 5 I found no separate check; by reading, the conclusion fixes the exact list, so a dropped or reversed result breaks it. 5. Decision 53: `ParTraverseWitness.lean:255` (5 inputs, `List.reverse` order: the `HashSet` branch), `:280`, `:300`.

Verdict: FAITHFUL as statements.

### `core.IO.parTraverseN.atMostN` (open)

1. MIRROR: yes. Counter token: `enter`/`exit` run inside `uncancelable`, `exit` also `onCancel` of the polled body (`CL.call`, `Props/Phase6/ParTraverse.lean:341-367`); every closure that holds the cell holds `.ref c`, so `tokFreeV` finds the token. Correct as a counter.
2. PROPERTY: **no**. F3 (false for every implementation) and S1.
3. SETTLED: open.
4. Wrong-function: 1000 permits gives 2 > 1 (`Limit.wideRun_breaks`, `ParTraverseWitness.lean:392`, kernel).
5. Decision 53: `Limit.parTraverseNAtMostN_satisfiable` (`:357`).

Verdict: HOLLOW.

## Scope C: CI (track P, `bd1483c`)

Files: `.github/workflows/ci.yml` (jobs `heavy-plan`, `heavy-module`, `heavy-audit`, `heavy-proofs`), `.github/workflows/paranoid-heavy.yml`, `scripts/{sandbox,heavy_build,check_heavy_module,check_heavy_proofs,run_kernel}.sh`, `scripts/heavy_closure.py`, `tools/HeavyList.lean`.

What holds:

- Aggregate: `heavy-proofs` has `needs: [heavy-plan, heavy-module, heavy-audit]`, `if: always()`, and three `test … = success` lines (`ci.yml:210-224`). Skipped, cancelled or failed needs all fail it. Fail-closed.
- Sandbox (batch 7 gap 1): `sandbox.sh` binds `/` read-only, a private `/tmp`, the repository read-only, only `.lake` writable, no network, own PID namespace, `--die-with-parent` (`scripts/sandbox.sh:16-27`). `heavy_build.sh` hashes every file under `.lake` except the module's own artifacts before and after each sandboxed build and compares the git work tree (`:24-50`).
- Derived lists (gap 3): matrix from `heavy_closure.py --from-lakefile --matrix`; `check_heavy_proofs.sh` derives roots and theorems from `tools/HeavyList.lean` and fails if the lakefile roots differ from `heavyModules` (`heavy_closure.py:93-94`). The audit job fails if a non-root module has no artifact set (`check_heavy_proofs.sh:64-68`).
- Every heavy module is replayed by `leanchecker` once: non-root modules in their matrix job (`check_heavy_module.sh:32`), roots in the audit job (`check_heavy_proofs.sh:60-63`, `:104-108`). Default-target modules stay with the main job.
- Artifacts: each module job uploads only its own artifact files with a `sha256` list computed outside the sandbox after the build (`check_heavy_module.sh:34-47`). The audit job checks the lists, installs, and fails if the root build rebuilt or changed an installed file (`check_heavy_proofs.sh:67`, `:76-79`). The artifact is the file that `leanchecker` replayed. And a forged `.olean` still has to pass the kernel replay, so the artifact path does not weaken soundness.
- `audit_heavy` is copied out of `.lake` before any heavy build (`:42-44`).
- Paranoid (gap 4): one export of the whole heavy closure, then one job per kernel (`paranoid-heavy.yml:22-78`, `run_kernel.sh`). The export scope ("M and all its imports") is stated in a comment (`paranoid-heavy.yml:7-9`). By the evidence rule a comment is not evidence; I could not check it by reading.

Residuals (none makes the pair weaker than the old gate):

1. **Default-target code is built outside the sandbox in every heavy job** (`check_heavy_module.sh:26`, `check_heavy_proofs.sh:42`, `:48`). Its build-time code can change `~/.elan/bin` (fake `lake`/`leanchecker`) or the running scripts. The main job has the same exposure (`lean-action` builds before `lake check`), so this is not a regression; the sandbox protects only against heavy-module code.
2. **Symlinks**: `manifest` hashes only `-type f` (`heavy_build.sh:28`). A sandboxed build can add a symlink under `.lake` (for example a later module's artifact path) and the check does not see it. Kernel replay still guards soundness. Fix: hash symlinks and their targets too (`-type f -o -type l`, `readlink`).
3. `cp -a "$artifacts_in/build/." .lake/build/` installs every file in the merged artifact directory, also files not in a `sha256` list (`check_heavy_proofs.sh:70`). Today only the trusted script writes there. Fix: install only listed files.
4. The axiom check fails on any `error` in the output (`:95`), so a heavy theorem whose name contains `error` (for example `…errorAborts…`) gives a false failure. Fail-closed, but it will block. Fix: match Lean's error prefix.
5. An empty matrix (all heavy modules are roots) makes `heavy-module` fail (`fromJSON('[]')`), so `heavy-proofs` fails. Fail-closed; today there are chunk modules.
6. Branch protection (decision 57 item 4) is not shown in the repository; I did not query GitHub.

Answer: **yes**, main + heavy is at least as strong as the old single gate; batch 7 gaps 1, 3 and 4 are closed (gap 4 only by a comment). Gap 2 of batch 7 is answered by decision 57 if branch protection is in place (residual 6).

## Design view: has the privacy approach converged?

No. There are two mechanisms, and they behave differently:

- **Token construction** (`tokFreeV`, `UserPrivate`, `Private`): decodes every number in every position. No forgery of a token in batches 7-8. Cost: S1 (absolute, so value-copying user code is excluded).
- **`Lib.fields` lists plus probes**: one hand-written list per library and per environment. Batch 8 found two holes that pass kernel-checked probe lemmas: the list was right for `Bracket.call` but not for the statement's `ioOf` (F1), and a nested position (`.some`) was not decoded and not sampled (F2, F3). `ResourceUse` (`srcCodeIds`, any depth, coverage lemmas, real dispatcher) is the only list without a hole that I found.

Root cause: a `Val.nat` is both data and a closure name. Every list must guess which numbers an environment will read as closures, and the guess depends on code outside the library (`ioOf`, `srcIO`).

Proposal, in order of cost:

1. Now: make `WF.captured` decode **every** number leaf, recursively and at any depth, as `tokFreeV` does (collect handles instead of tokens). Drop `Lib.fields` and the probes. This closes F1-F3 and the whole "unlisted field" class by construction. It shrinks the domain only for data numbers that happen to decode to a closure with a handle (the same kind of loss as S1).
2. Now: give every marker statement the token construction (`Bracket` entries too); add the Phase 5 `REnv.WellFormed` clauses to the `Resource` statements (S2).
3. Later (user decision): separate closure references from data in `Val` (for example a `Val.fn id` constructor, with `Fn` fields typed as such in the codecs). Then a data number can never be a closure name, the decoding in 1 is not needed, and S1 goes away: `UserPrivate` can become relative ("a result names only tokens that the inputs named").

## Required fixes

1. Track G: F1 (Bracket statements), regression example.
2. Track G: F2 and F3 (`srcFnIds` under `.some` or at any depth; `TLam`/`RLam`/`BLam` samples and coverage lemmas), regression examples.
3. Track Res: S2 (`REnv.WellFormed` clauses in `Private`).
4. User decision: accept S1 as a documented model limit, or adopt proposal 3.
5. Track G: difftest cases with 5-6 inputs (refinement over orders).
6. Track P: residuals 2-4 (small); show branch protection (residual 6).

## Confidence

- F1 makes both `Bracket` statements false: 0.85 (all hypotheses checked by reading; not run).
- F2 reopens defect D for `resultOrder`: 0.8. F3 for `atMostN`: 0.75 (schedule existence argued, not run).
- S1 is a real domain restriction: 0.95; that it hides no release-once bug: 0.6.
- CE-0020 FAITHFUL: 0.85. Statements 2-7 FAITHFUL as statements: 0.75.
- CI pair at least as strong as the old gate: 0.85.

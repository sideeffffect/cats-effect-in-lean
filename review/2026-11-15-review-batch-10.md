# Review batch 10 (2026-11-15): R1 fix (`Resource`), `Race`/`Memoize` source references, Phase 6 gate

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the witnesses, the regression examples, the bug records and the wiki. It did not run a build, Lean, a test, sbt or `gh`.
Reviewed commit: `1dfe6ce`, checked out as branch `review10`. Diff base for "what changed": `1ea6ef3` (batch 9). For entries last reviewed in batches 4-5, also `567db50` (batch 4).
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 56, 58, "Reviewer evidence", "Fixed-twin check for refutations"). When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `bugs/`, `raw/`, `wiki/`, `inventory/`, `tools/` or `.github/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `kernel.Resource.both.releaseOnce` (CE-0020) | refuted | FAITHFUL |
| `kernel.Resource.use.releaseOnce` | open | FAITHFUL as a statement |
| `kernel.Resource.flatMap.releaseOrder` | open | FAITHFUL as a statement |
| `core.IO.race.combNoLeak` | open | FAITHFUL as a statement |
| `core.IO.race.combCanceledNoLeak` | open | FAITHFUL as a statement |
| `core.IO.timeout.noLeak` | open | FAITHFUL as a statement |
| `core.IO.raceOutcome.isWinnerOutcome` | open | FAITHFUL as a statement |
| `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` (heavy) | proven | FAITHFUL (low strength, as batch 7; statement unchanged) |
| `core.IO.memoize.noStuckGet` (CE-0030) | refuted | FAITHFUL |
| `core.IO.memoize.getsAgree` | open | FAITHFUL as a statement |
| `core.IO.memoize.atMostOnce` | open | FAITHFUL as a statement |

Light re-check (diff since the last review only; verdict carried): `core.IO.bracketFull.kernelDefaultTwin` (CE-0005), `.pureUse`, `laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO` (batch 4), `kernel.Resource.eval.preservesCancelable` (batch 5). See "Carried verdicts".

New findings: none that changes a verdict. Low: D1 (a registry claim about `Memoize` is false, no claim breaks), D2 (no recorded difftest run after the R1 encoding change), D3 (stale text), D4 (CE-0020 inventory rows still `todo`).

---

## 1. R1 fix: `REnv` table entries as references

### What I read

- `Model/Resource.lean`: module doc (new paragraph on references), `RelFn.toVal`/`ofVal` (`:156-170`), `ioRelease` (`:173`), `stackToVal`/`stackOfVal` (`:179-186`), `allocFnToVal`/`allocFnOfVal` (`:188-195`), `Clo.makePair` (`:230`), `applyPair` (`:389-392`), `Res.ok` (`:423-428`).
- `Model/WellFormed.lean`: `cloHandles` (`:138-141`), `availD`/`avail`/`subA`/`capOK` (`:155-171`), the W1 change (`:285-344`) and its lemmas.
- `Props/Phase6/Resource.lean` in full (`resOK` `:177-182`, `MarkedMake` `:188-194`, `Private` `:201-205`, statements `:211-251`).
- `Model/ResourceUse.lean`: `USrc` (`:309-326`), `OnRel` (`:135-151`), `isLib`/`publicLib` (`:770-779`).
- `Proofs/Phase6/PrivacyExamples.lean:135-150`, `ResourceWitnessEnv.lean:40-128`, `ResourceWitness.lean:1-105`, `ResourceBoth.lean` in full, `ResourceWrongFunction.lean` in full, `bugs/CE-0020.yaml`.

### Is R1 closed? Yes, by reading

1. Every table index in a value is now `.fn k` (diff of `Model/Resource.lean`): `RelFn.const`, `ioRelease`, stack frames, `AllocFn.make`, `Clo.makePair`, `applyPair`. No decoder of these types accepts `.nat k` any more.
2. `avail (.fn k)` for an odd `k` is "held only" (`Model/WellFormed.lean:155-161`). `MarkedMake` now requires `acq` and `rel` odd (`Props/Phase6/Resource.lean:189`); `flatMapReleaseOrder` requires the harness `Bind` entry `k` odd (`:244`).
3. So the batch 9 term `forge relA` with the harness `relA` is rejected: the `constThis` closure value captures `.fn relA`, `capOK` needs it available, and it is not held. Regression: `example : WF.progOK libH (fun _ => false) (forge (code 1)) = false` (`Proofs/Phase6/PrivacyExamples.lean:147`), with `code_odd` (`ResourceWitnessEnv.lean:44`). The honest form with an own even entry is accepted (`:150`).
4. Even entries remain nameable by user code (if `cloHandles k` is available). They are all outside the harness lists (those are odd), so `Private` restricts every one of them (`:202-205`): closed acquire programs, release programs and `Bind` results that hold only the handles of their argument. So an even entry is "user code that the user could write", which is correct.
5. `Private` dropped the hand-written `Res.idx` exclusion. This is now done by `resOK` (`:177-182`), which checks the references of `make` and `bind` with `subA`/`avail`. No escape clause.

Attacks I tried (all rejected by reading):

| Attack | Why it fails |
|---|---|
| `forge relA` of batch 9 (harness `relA`) | odd reference, not held (`PrivacyExamples.lean:147`). |
| `ULam.allocFn (.make acq rel)`, `Clo.makePair rel`, `applyPair` with a built argument | `ULam`/`Clo` are not in `publicLib` (`Model/ResourceUse.lean:778-779`); and their values capture `.fn acq`/`.fn rel` (odd, not held). |
| `USrc.fold c …` with the harness code `c` | `c` holds the token `.ref 0` (`MarkedMake` `:194`), not available. |
| A non-harness code `c'` that maps to `Res.make acq rel` | `Private` clause 4: `resOK` with `c'.handles` needs `.fn acq` in `c'`; then user code cannot build `c'` (it does not hold `.fn acq`). |
| A user `Bind` (even) that returns `Res.make acq rel` | `Private` clause 1 (`resOK` with the argument's handles). |
| A value from the library that holds `.fn rel` | I found none that reaches user code: `use` gives `f` only `a`; `both` keeps the finalizers in its own `Ref` (`OnRel.store`), which user code never holds; `allocated` is not in these statements. |
| Collision: an odd table index equal to an odd closure id that user code holds | User code holds no odd closure reference as a value here (public closures are named in function position only, batch 9 M2). |

Conclusion: R1 is closed for the three `Resource` statements. Confidence 0.8.

### W1 fix

`hasPoll`/`rnVal` now follow `Val.fn` through `cloOfId` (`Model/WellFormed.lean:328-344`), with `hasPollF`/`rnValF` and fuel `pollFuel = 4096` (`:285-314`). `rnRef` keeps the parity (`2 * valToNat … + k % 2`, `:322-326`), so a renamed reference stays a user or a library reference. The lemmas `rnVal_of_hasPoll_false` and `hasPoll_rnVal` cover the new case. Effect: the stricter case of batch 9 (user code that returns a closure that captured a received poll) now passes, and the possible gap (user code that reads the mask id inside a received reference) is closed up to the fuel. Residual (very low): a poll more than 4,096 constructors deep inside a referenced value is not renamed; I found no producer of such a value. A table index `.fn k` is renamed only if `cloOfId k` holds a poll; the harness codes do not (`code i` decodes to `cloVal 21 60 [.ref 0, .nat i]`).

### `kernel.Resource.both.releaseOnce` (refuted, CE-0020)

1. MIRROR: yes. Only the encoding of table references changed. `cloCall` logic is the same apart from the `applyPair` pattern (`Model/Resource.lean:389-392`).
2. PROPERTY: yes. Quantifiers unchanged (`Props/Phase6/Resource.lean:211-219`). R1 is closed (above). The hypotheses are `MarkedMake` (×2), `Private`, `WellFormed`; no hypothesis restricts the interesting case.
3. SETTLED: yes. `bothReleasesBoth_refuted : ¬ bothReleasesBoth` (`Proofs/Phase6/ResourceBoth.lean:75-82`) applies the statement to `markedA`, `markedB` (now with `code_odd`, `ResourceWitnessEnv.lean:117-129`), `both_private`, `wellFormed` (for every body, `ResourceWitnessEnv.lean:108-110`) and the kernel run `run_witness` (log `[tagA, tagB, tagRA]`, `Errored boom`).
4. Fixed twin (decision 39): `fixedBothRes` satisfies the conclusion on the witness input for 120 schedules (`Proofs/Phase6/ResourceBothFixed.lean`, cited in `bugs/CE-0020.yaml`, `lean.fixed_twin`; module not re-read in this batch, unchanged since batch 9). The "correct implementation also refutes" defect of batches 5, 6 and 9 is gone with R1.
5. Bug record: `bugs/CE-0020.yaml` has `reproducer`, `output` for v3.7.1, series/3.x and series/3.7.x (each ends with `REPRODUCED CE-0020`), `lean.property`/`lean.theorem` equal to the registry entry. The `hypotheses` text now names the R1 change.

Verdict: FAITHFUL.

### `kernel.Resource.use.releaseOnce` (open)

1. MIRROR: yes. 2. PROPERTY: yes (R1 closed; S1 and S2 closed in batch 9). 3. SETTLED: open.
4. Wrong-function: `noReleaseUse_breaks` (`Proofs/Phase6/ResourceWrongFunction.lean:29-36`): `acquire.flatMap(f)` on the witness input; kernel run, log `[tagA]`, so `count RA = 0 ≠ 1`. The hypotheses `MarkedMake`/`Private` do not depend on the body, and `wellFormed` holds for every body, so the broken body meets all hypotheses.
5. Decision 53: `use_sat` (`Proofs/Phase6/ResourceWitness.lean:55-70`), with and without the parent, kernel runs.

Verdict: FAITHFUL as a statement.

### `kernel.Resource.flatMap.releaseOrder` (open)

1. MIRROR: yes. 2. PROPERTY: yes. 3. SETTLED: open.
4. Wrong-function: `fifo_breaks` (`ResourceWrongFunction.lean:41-56`): log `[tagB, tagA, tagRA, tagRB]`, `RB` not before `RA`. Caveat: the "FIFO" implementation is modelled by the reversed nesting `make(B).flatMap(_ => make(A))` with an extra `Bind` entry `code 5` in a new `UEnv` (`WR`), not by a broken `flatMap` with the same input. It shows that the order clause is not trivially true. It is weaker than a broken mirror, but sufficient for the wrong-function test.
5. Decision 53: `flat_sat` (`ResourceWitness.lean:91-105`), now with `code_odd 4`.

Verdict: FAITHFUL as a statement.

---

## 2. `Race` source references (`src0 = .fn 1`, `src1 = .fn 3`)

### Mirror and statements

- `Model/Race.lean`, `Model/Timeout.lean`: no change since batch 4 (`git diff 567db50 1dfe6ce` lists no change).
- `Props/Phase6/Race.lean`: `srcId0 = 1`, `srcId1 = 3` (`:71-72`), `src0 = .fn srcId0` (`:75`), `srcIO` compares with `src0`/`src1`, else a fatal error (`:79-80`). Statements unchanged (`combNoLeak` `:193`, and the next three). Hypotheses: only `WellFormed raceLib [] (env fa fb u) fa` and `… fb`.

### Are the ids 1 and 3 sound? Yes

- No closure id is smaller than 64. Every `encVal` starts with the 5-bit tag (`Model/Codec.lean:94`, `:108-120`), and `ofBits` adds a sentinel bit (`:201-203`), so `valToNat v ≥ 32` for every `Val` (`:206`: "Never `0`"). A closure id is `2 * valToNat c` or `2 * valToNat c + 1` (`:374-377`), so it is at least 64.
- `cloOfId 1 = natToVal 0` and `cloOfId 3 = natToVal 1` (`:383`). `bitsLE` gives `[]` and `[true]` (`:50-52`); after `dropLast` both are `[]`, and `decVal` of `[]` is `none` (`:158-163`, `readLE 5 []` = `none`). So no dispatcher decodes 1 or 3, `cloHandles` is `[]`, `hasPollRef`/`rnRef` leave them unchanged.
- `avail (.fn 1)` is "held only" (odd). User code never holds it: `fa`/`fb` start with `H0 = []`, and no `Race`/`Timeout` closure passes its source value to a user function (the sides run as fibers; results go to library closures).
- Collision with a table index: the `Race` statements have no `REnv`. In the `Resource` statements, `Race` sources are `USrc` codes (`srcU`), not `src0`/`src1`.
- Regressions: `forged_race_sources`, `forged_timeout_source` (rejected), `old_codes_not_sides` (`Proofs/Phase6/RaceWitness.lean:327-339`).

### The heavy law statement is unchanged

- Registered: `RegistryHeavy.lean`, prop ``Props.Phase6.Race.uncancelableRaceNotInherited``, theorem `RaceLaw.uncancelableRaceNotInherited_proven` (`Proofs/Phase6/RaceLaw.lean:57`, type `uncancelableRaceNotInherited`).
- `uncancelableRaceNotInherited := EqvP {} counterMaskModel lawEnv raceNotInheritedLhs Timeout.neverIO` (`Props/Phase6/Race.lean:256-257`): text unchanged.
- `lawEnv` (`:244-250`) now uses `Race.raceIO (.nat 0) (.nat 1)` and `lawEnvOf` (`:173-175`) with `lawDispatch` (`:161-171`) and `lawSrcIO` (`:85-88`). At `1ea6ef3`, `lawEnv` used `Race.raceIO src0 src1` with `src0 = .nat 0`, `src1 = .nat 1` and `env` with `srcIO` = `.nat 0 => fa | .nat 1 => fb | _ => error` (`git show 1ea6ef3:…/Race.lean:67-70`, `:209-215`). `lawSrcIO` is that same function, and `lawDispatch` has the same branch order as `dispatch` (`:144-155`). So `lawEnv` is the same function as before; only the names differ.
- The certificate modules did not change (`git log` of `RaceLaw*.lean`: last change `bc85ddd`). The kernel re-check after the change is in `wiki/log.md` (last entry: `RaceLawChunks4` built at 8.29 GiB "after the change"). I did not run it.

### Verdicts

- `combNoLeak`, `combCanceledNoLeak`, `timeoutNoLeak`, `raceOutcomeIsWinnerOutcome`: 1. MIRROR yes (unchanged). 2. PROPERTY yes (quantifiers unchanged; the change removes a re-run of `fa` by number, which broke no claim, as the track G note says; it does not exclude any Scala program). 3. SETTLED open. 4. Wrong-function: `noCancel_leaks` (`RaceWitness.lean:317`). FAITHFUL as statements.
- `uncancelableRaceNotInherited.IO`: FAITHFUL (low strength, as batch 7: `race = never` also satisfies it).

---

## 3. `Memoize` source reference (`faSrc = .fn 1`), CE-0030

### What changed

- `faSrc = .fn 1` (`Props/Phase6/Memoize.lean:131`); `srcIO` matches `.fn 1` and `.ref c` (`:134-137`); `isLib` is the mirror only, no `TLam` (`:181`); `twoGets` uses `faSrc` (`:214`). Statements unchanged (`:238-253`).
- `Model/Memoize.lean`: no change since batch 4. `MemoizeFixed.lean` was split into `MemoizeFixedParts/` for memory (same checks: for example `fam_old_canceled_a`, positions 0-59 give `[35, 36, 37]`).
- Regressions `forged_source`, `old_code_not_fa`, `forged_constFa`, `honest_fa` (`Proofs/Phase6/MemoizeSat.lean:110-121`).
- The ids: same argument as for `Race` (`.fn 1` is no closure id; held only).

### D1 (low, documentation): user code can still run `fa` outside the tested `memoize`

The registry notes of the three memoize entries and the track G note say: "user code cannot run `fa` outside the tested memoize". That is false. `srcIO fa (.ref c)` runs `c.update(_ + 1) *> fa` for any cell `c` (`:136`), and the `Timeout` and `Memoize` closures are public with a free source field (`Model/Memoize.lean:518-525`). User code that owns a cell can name this source:

```lean
-- user closures (even ids): u0 = the thunk `Ref.unsafe(0)`, u1 = `r => <timeout with source r>`
-- u0: { effects := [.allocRef (.nat 0)], out := .ret (.ref v.refs.length) }
-- u1 on (.ref k): { out := .prog (Timeout.timeoutIO (.ref k) 1) }
def faRerun (u0 u1 : Nat) : IO := .flatMap (.delay (.user u0)) (.user u1)
-- srcIO fa (.ref k) = incr k *> fa: `fa` runs again, on the user's own cell k
```

This is not a forgery. Scala can write the same program (`def fa: IO[Unit] = IO.ref(0).flatMap(r => (r.update(_ + 1) *> fa).timeout(1.nano))`). The counter of `memoizeAtMostOnce` is cell 0, allocated first (`countedTwoGets`, `:217-218`), so the user cell is never cell 0. No claim breaks. The same holds for `Bracket` (`srcAcq c = .pair (.ref c) (.nat 0)`, `Props/Phase6/Bracket.lean:174`: an own cell re-runs `a0` with `markA` on the own cell). Fix: correct the sentence ("user code can run `fa` again only as Scala can, through its own cells; the counted source needs the counter handle").

### Verdicts

- `memoize.noStuckGet` (CE-0030): 1. MIRROR yes (unchanged). 2. PROPERTY yes (all `WellFormed fa`, all schedules). 3. SETTLED: `memoizeNoStuckGet_refuted` (`Proofs/Phase6/MemoizeStuck.lean:85-88`) applies the statement to `fa = IO.canceled` with `fa_wf` (`:72`) and the kernel runs `wit_blocked`, `wit_finished` (`:47`, `:49`), now on `twoGets` with `faSrc`. Fixed twin: unchanged family, split for memory. Bug record `bugs/CE-0030.yaml`: reproducer, output for v3.7.1, series/3.x, series/3.7.x, each ends `REPRODUCED CE-0030`. FAITHFUL.
- `memoize.getsAgree`, `memoize.atMostOnce`: statements and witnesses unchanged in meaning; D1 does not affect them. FAITHFUL as statements.

---

## 4. Carried verdicts (diff checked only)

- `bracketFull.kernelDefaultTwin` (CE-0005), `.pureUse`, `guaranteeIsGuaranteeCase.IO`: since batch 4 the statements changed only `isLib` → `lib` (`Props/Phase6/Bracket.lean:52-83`, `git diff 567db50`), and the `BLam` function fields became `.fn` (decision 58; batch 9 read the `call` logic as unchanged). These are `EqvP` twins and laws over an arbitrary `env`/`ioOf`; no harness, so privacy does not apply. Proof diff of `BracketFullTwin.lean`: `isLib` → `lib` only. Bug record `bugs/CE-0005.yaml`: reproducer, output for v3.7.1, series/3.x, series/3.7.x, `REPRODUCED CE-0005`. Batch 4 verdicts stand: FAITHFUL (low strength), FAITHFUL as statements.
- `eval.preservesCancelable` (batch 5): uses `Res.evalOf fa` only; the R1 change of `Res.ok` touches `make` and `bind`, not `eval` (`Model/Resource.lean:423-428`). Batch 5 verdict stands.

## 5. Remaining number-named tables (all `Model/*.lean`)

I searched every `.nat <variable>` pattern in `Model/` (`grep`) and read each hit.

| Location | Field | Name of something? |
|---|---|---|
| `Model/Race.lean:120-147` | `Kind`, `side` | Selector of a fixed lambda shape, not a capability. |
| `Model/Timeout.lean:108-128` | `d` | Duration. |
| `Model/Memoize.lean:131`, `:195-303` | `n` (subscriber count), `variant` | Count; `variant` picks the v3.7.1 or the fixed `memoize` (both are code that user code may run; not a capability). |
| `Model/ParTraverse.lean:196-248`, `:442-617` | `n`, permits `k` | Counts. |
| `Model/ResourceUse.lean:146-150`, `:231`, `:257` | `side` | Selector 0/1. |
| `Model/Step.lean:370-379`, `:534-538` | callback id `h`, timer id `t` | Run-time ids inside `Fn.rt` closures, which `progOK` rejects except a fixed list (`Model/WellFormed.lean` module doc). Phase 2 code, not Phase 6. |
| `Model/ResourceFixed.lean:56`, `:60` | `FClo.body k` (`FEnv.res` index), `thenK … (.nat h)` (`Bind` index) | **Yes, number-named table entries**, now also inconsistent with `stackToVal` (`.fn`). Phase 5 twin of CE-0002, checked only on nine closed programs (`Proofs/Calibration/ResourceEvalFixedFamily.lean`), so no user code can use them. Not a Phase 6 risk. |
| `Model/SyncStepFixed.lean:60-65` | `.user id => .left (.nat id)` | A closure id as a number. Phase 5 twin of CE-0001 (known caveat, batch 3). Not Phase 6. |

Handle-gated codes (structural, Scala-expressible): `Memoize` `.ref c`, `Bracket` `srcAcq`/`srcFa`/`srcFin` (D1). `Resource` codes (`UEnv.resOf`) are keyed by `Val`; harness codes hold the token; other codes are restricted by `Private`.

I found no forgeable reference in a Phase 6 model.

## 6. Other findings

- D2 (medium-low, process): the R1 change edits the `Resource` mirror encoding (`Model/Resource.lean`). The last recorded `opcount.py` runs for `rUse`/`rAllocated`/`rBoth` (seeds 51-53, 61-64) are from the decision 58 core, before R1 (`raw/cats-effect/2026-11-15-decision-58-core-notes.md:39-42`). CI runs the fixed cases `resuse.jsonl`, `resource.jsonl` and 3 × 2,000 random cases on each push (`.github/workflows/ci.yml:119-121`); I did not check the CI status. Advice: one `opcount.py` run with the `Resource` ops boosted, recorded in the wiki.
- D3 (low): stale text. `bugs/CE-0005.yaml:3` and `bugs/CE-0030.yaml:3` still say "waits for review" (reviewed FAITHFUL in batch 4). The `memoLib` doc (`Props/Phase6/Memoize.lean:183-187`) and the `Memoize` registry notes (D1). `Model/ResourceFixed.lean` uses `.nat h` in `thenK` but `.fn` in `stackToVal`.
- D4 (low, inventory): `kernel.Resource.both`, `kernel.Resource.use`, `kernel.Resource.fold` are `todo` with an empty `registry` column (`inventory/inventory.csv`), but CE-0020 names them and is now FAITHFUL. Batch 5 said `both`/`use`/`fold` are mirrored ("yes, when entry 1 is fixed"); `makeCase` is not. After this review, the rows can become `modelled` through CE-0020.

## Confidence

- R1 closed for the three `Resource` statements: 0.8.
- Ids 1 and 3 never collide with a closure id: 0.9 (by reading the codec).
- The heavy law statement is unchanged in meaning: 0.9.
- `Memoize` entries FAITHFUL (D1 does not break a claim): 0.8.

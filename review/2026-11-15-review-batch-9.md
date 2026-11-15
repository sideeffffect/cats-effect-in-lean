# Review batch 9 (2026-11-15): decision 58 core (`Val.fn`, `WF.avail`), `Bracket`, `Resource`, `parTraverseN` entries

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the witnesses, the smoke files, the difftest driver and decoder, and the wiki. It did not run a build, Lean, a test, sbt or `gh`.
Reviewed commit: `1ea6ef3` (decision 58 core of track Res, with the `parTraverseN` adaptation of track G), checked out as branch `review9`. Diff base for "what changed": `7c45611`.
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 39, 53, 54, 56, 58, "Reviewer evidence", "Fixed-twin check for refutations"). When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `tools/`, `difftest/`, `test/`, `scripts/`, `bugs/`, `raw/` or `.github/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `core.IO.bracket.releaseOnce` | open | FAITHFUL as a statement |
| `core.IO.guarantee.finalizerOnce` | open | FAITHFUL as a statement |
| `kernel.Resource.both.releaseOnce` (CE-0020) | refuted | **HOLLOW** as registered (R1: a correct `both` also refutes it; bug and witness are real) |
| `kernel.Resource.use.releaseOnce` | open | **HOLLOW** (R1: false for every implementation) |
| `kernel.Resource.flatMap.releaseOrder` | open | **HOLLOW** (R1: false for every implementation) |
| `core.IO.parTraverseN.resultOrder` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.pureSucceeds` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.errorAborts` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.cancelAborts` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.succeedsGen` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.errorAbortsGen` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.cancelAbortsGen` | open | FAITHFUL as a statement |
| `core.IO.parTraverseN.atMostN` | open | FAITHFUL as a statement |

Privacy problem: **closed for closures, not closed for `Resource`.** `WF.avail` is sound for closure references: I found no way for user code to name a library or harness closure that it does not hold. But the `Resource` mirror keeps a second kind of name as a data number: an `REnv` table index (`RelFn.const k a`, `Model/Resource.lean:151`). A `Bracket` closure that is public in `libH` rebuilds an external source with `srcU`, and `srcU` applies `RelFn.const k` to `U.r.release k` (`Model/ResourceUse.lean:373`, `:445-451`, `:511-521`). So user code with no handle runs the harness release program and logs a release tag (R1, below).

---

## Scope A: the decision 58 core

### What I read

- `Model/Val.lean:115-119` (`Val.fn`); `Model/Codec.lean` (tag 21 in `encVal`/`decVal`, `readLE_tag` now `t < 22`, `libFn`/`userFn`/`cloOfId` `:374-383`); `tools/Difftest/Closure.lean` (`valTokens` `[21, i]`, `valOfTokens?` case `21, i :: r`).
- `Model/WellFormed.lean` in full (`Handle.fn` `:95`, `Val.handles` `:99-108`, `Lib` `:114-122`, `cloHandles`/`captured` `:139-145`, `availD`/`avail`/`subA` `:156-168`, `fnOK` `:187-189`, `progOK` `:192-206`, `OutOK`/`EffectsOK` `:234-256`, `CallOK` `:265-269`, `PollOpaque` `:374-376`, lemmas `:404-649`).
- Every dispatcher that decodes a closure id: `grep` for `cloOfId`/`isLibId` in `Model/` and `Props/Phase6/`. All library dispatchers test `isLibId` first (`Model/Bracket.lean:277-282`, `Model/ResourceUse.lean:275`, `:730`, `:745`, `Model/ParTraverse.lean:300`, `Props/Phase6/*.lean`). `Model/BracketExamples.lean:60` decodes without a parity test, but it is example user code (even ids).

### Is `WF.avail` sound for closures? Yes, by reading

The argument has three parts. I checked each.

1. **An even id has only the power of its captured handles.** `WellFormed` requires `CallOK` for every even id, every argument and every view (`Model/WellFormed.lean:392`). The held set is `AvailP (Reach v (H0 ++ arg.handles ++ captured lib id))` (`:267`). `captured` is the handles of the closure value, `Handle.fn` included (`:139-145`). So an even closure that captured a forged value can do more only if someone can name it.
2. **Naming an even id needs its captured handles to be available.** `fnOK (.user id)` for an even id needs `capOK`, so `subA` of the captured handles (`:188`). `avail` of `.fn k` for an even `k` recurses into `cloHandles k` (`:161`); for an odd `k` it is "held only" (`avail_fn_odd`, `:459-463`). Other handles are "held only" (`avail_iff_of_not_fn`, `:449-455`). At depth 0 the rule is "held only" (`:157`), which is stricter.
3. **An odd id runs mirrored library code, and naming it needs `lib.ok` plus available captured handles, or a held reference.** Even ids never reach a library dispatcher, because every dispatcher tests `isLibId`. An even id whose closure value equals a harness closure value runs as user code (`u.callV`), so it gets no harness power.

Attacks that I tried (all rejected by reading):

| Attack | Why it fails |
|---|---|
| Own even closure that captures `.fn markT…` (odd, harness) | `avail` of the odd reference is "held only" (`:161`, `:459-463`). |
| Own even closure that captures `.ref 0` (token) | `.ref 0` is "held only" (`avail_ref`, `:481`). |
| Return `.fn odd` in a value, write it to a `Ref`, allocate it | `OutOK .ret` and every effect use `R h` with `R = AvailP …` (`:235`, `:246-253`): odd reference only if reachable. |
| `IO.pure(.fn odd)` in a returned program | `progOK (.pure v)` uses `subA` (`:193`). |
| A data number that equals a closure id (`.nat markT.id`) | `Val.handles` ignores `.nat` (`:108`). No mirror that I opened reads a `.nat` as a closure id after this change (`HLam.ofFields`, `BLam.ofFields`, `PT.ofFields`, `TL.ofId?`, `CL.ofFields`, `OnOut.ofVal`, `RelFn.ofVal`, `allocFnOfVal`, `hioOf`, `ParTraverse.ioOf` all match `.fn`). |
| `Bind` result or `Ref` content that holds a harness reference | `Reach` reaches it only through a held `Ref`, `Deferred` or fiber (`:210-217`). The harness cells and harness closures are never given to user code (checked for `Props/Phase6/Bracket.lean:199-212`, `Props/Phase6/Resource.lean:126-134`, `Props/Phase6/ParTraverse.lean:121-133`, `:348-369`). |
| Depth: a chain of 65 nested own closures | At depth 0 `availD` is "held only" (`:157`): the chain is rejected, not accepted. |
| Codec: `cloOfId k = none` for an even `k` | `cloHandles` is `[]`, so the closure is available, but it is user code with `captured = []` in `CallOK`. No power. |
| Codec: an odd id whose value equals a public closure with chosen fields | Same as "public API with these arguments". Its fields must be available (`capOK`). |

### Is `WF.avail` too strict? Mostly no

- S1 is gone. `idEnv_callOK` (`Proofs/Phase6/PrivacyExamples.lean:136-142`): `x => IO.pure(x)` passes `CallOK` on every argument, also an argument that holds a token or a harness reference.
- Passing a reference through and storing it pass (`Reach` includes the argument and the contents of held cells).
- Minor strictness M1: after `allocRef`, the new cell joins `R` only as `h = .ref nr` (`Model/WellFormed.lean:253`), not inside `AvailP`. So `.ret (.fn k)` with `k` capturing the new cell is rejected, but the same closure in a returned program is accepted (`progOK` uses `avail (memOf R)`). Scala `IO { val r = Ref.unsafe(0); () => r.get }` is outside the domain. Small. It cannot hide a release bug that I can see.
- Minor strictness M2: a public library closure (`lib.ok`) is allowed in function position (`fnOK`) but not as a value (`.pure (.fn odd)`, `subA`). I found no statement that needs it.

### W1 (low risk): `PollOpaque` does not look inside closure references

`hasPoll` and `rnVal` do not descend into `Val.fn k` (`Model/WellFormed.lean:285-299`). `rnId` renames polls only in the top closure value (`:308-311`), not in nested references. Effects:

- Stricter: user code that returns or builds a value that holds `.fn k`, with `k` capturing a `Poll`, fails `PollOpaque` (the left side changes, the right side does not). Example: `poll => () => poll(fa)` returned as a value.
- Possible gap: user code that **receives** a `.fn k` whose closure captured a poll can decode `k` and branch on the mask id; `PollOpaque` cannot see this, because the input reference is not renamed. I found no path where a `.fn` with a captured poll reaches user code (the code that builds such a value fails `PollOpaque` itself, and the library closures that capture polls, for example `BLam.bfK`, `ULam` sources, are used in function position). Not a demonstrated hole.

Fix (small): make `hasPoll`/`rnVal` rename inside `Val.fn k` the way `rnId` does.

### R1 (new forgery): an `REnv` table index in a `Resource` source code

Decision 58 makes closure names capabilities. The `Resource` mirror has a second kind of name: indices into the user tables of `REnv` (`acquire`, `release`, `bind`, `Model/Resource.lean:260-268`). Three encodings keep them as data numbers: `RelFn.const k a` → `.pair (.nat 1) (.pair (.nat k) a)` (`Model/Resource.lean:151`, `:157`), `AllocFn.make a r` (`:183`), stack frames (`:174`). A `USrc` source code is pure data (`Model/ResourceUse.lean:309-332`), and `srcU` rebuilds it (`:511-521`): `srcRel` applies `applyRelX`, and `applyRelX r v (.const k a) = ([], r.release k a)` (`:373`, `:445-451`). In the `Resource` statements `srcU U` is the `ioOf` of every `Bracket` closure (`resDisp`, `:755-758`) and the `srcIO` of `Race` and `Timeout` (`uDisp`, `:738-753`). `BLam` closures are public in `libH` (`publicLib`, `:778-779`; `libH`, `Props/Phase6/Resource.lean:152-153`).

Forgery term (no handle anywhere):

```lean
open CatsEffectInLean.Model CatsEffectInLean.Model.Resource CatsEffectInLean.Model.ResourceUse

/-- `rel(ec)` with `rel = RelFn.const relA ()`: the harness release entry, named by number. -/
def forgeSrc (relA : Nat) : Val := (USrc.relApp (RelFn.const relA .unit).toVal .unit .unit).toVal

/-- `IO.unit.flatMap(_ => <external source forgeSrc>)` with the public `Bracket` leaf `_ => this`. -/
def forge (relA : Nat) : IO :=
  .flatMap (.pure .unit) (Bracket.BLam.constThis (Bracket.Src.ext (forgeSrc relA)).toVal).fn

-- expected today (by reading): WF.progOK Props.Phase6.Resource.libH (fun _ => false) (forge relA) = true
```

Counterexample for `useReleaseOnce` (`Props/Phase6/Resource.lean:231-237`):

- `U.resOf c = some (Res.make acq rel)` for `c = .ref 0` (so `Handle.ref logCell ∈ c.handles`), `none` otherwise. `U.r.acquire acq = .flatMap a0 (HLam.markA 0 tagA).fn` with `a0 = forge rel`; `U.r.acquire k = .pure .unit` for `k ≠ acq`. `U.r.release rel a = .ok (.flatMap (.delay (HLam.markT 0 tagRA).fn) (uid 0))`; `U.r.release k a = .ok (.pure .unit)` otherwise. `U.r.bind _ _ = .ok (Res.pure .unit)`. `U.r.user.callV _ _ _ = { out := .prog (.pure .unit) }`. `f = 14`, `viaParent = false`.
- `MarkedMake` (`:192-197`): all five parts hold. `progOK libH (fun _ => false) a0`: `.pure .unit` passes; `fnOK` of the `constThis` id: `libH.ok` is true (`BLam.ofId?` is `some`), and the closure value `cloVal 7 16 [.left (forgeSrc rel)]` holds no handle, so `capOK` is true.
- `Private` (`:204-210`): the bind results have no handle and no index; the other acquire and release programs are `.pure .unit`; codes other than `c` give `none`.
- `WellFormed libH [] (envH U body) harness`: the harness root passes; every even id returns a constant handle-free program (`CallOK`, `PollOpaque` as in `WF.pollOpaque_of_const`).
- Run (no parent, any schedule that completes): the acquire runs `a0`; `constThis` runs `srcIO (srcU U)` (`Model/Bracket.lean:320-322`, `:428`), so `srcU U (forgeSrc rel)` = `U.r.release rel ()`: `markT` appends `tagRA`. Then `markA` appends `tagA`, `use` runs, the real release appends `tagRA`. Log `[tagRA, tagA, tagRA]`: `count tagRA = 2 ≠ 1 = count tagA`. The conclusion fails for the v3.7.1 mirror. It fails the same way for every implementation that runs the acquire.
- The same `a0` (or the same program returned by `f`) breaks `flatMapReleaseOrder` (`:245-256`) and `BothReleasesBothFor impl` for **every** `impl` (`:216-224`), also `fixedBothRes`.

Why the earlier checks miss it:

- `Private` restricts `Res.idx` only in `bind` results and in `resOf` of other codes (`:205-210`). It does not look at programs, and a `RelFn.const` index inside a `USrc` code is not a `Res`.
- `WF.avail` follows `Val.fn` only. `RelFn.user id` is a reference (`tagged 2 (.fn id)`), so the `ULam` release closures are safe; `RelFn.const k` is not.
- `PrivacyExamples` tests the batch 5, 6 and 8 shapes. No example has a `USrc` code.
- The batch 8 token construction (`tokFreeV`) would not catch it either: `relA` decodes to an arbitrary value, not to the token. So R1 is an old hole that no review found, not a regression of decision 58.

Fix (either): (a) make every `REnv` table reference a capability: encode `RelFn.const k a`, `AllocFn.make a r` and the stack frames with `Val.fn` of a library closure that is in no `Lib` (so it is available only if held), as decision 58 did for closures; or (b) make `USrc` codes library closure references (odd `Val.fn` ids, not public), so user code holds a source only when the library gives it (for example the `F[Unit]` of `allocated`). Add `forge` to `PrivacyExamples` as a regression example (`progOK … = false`). A hand-written "no harness index in any source" clause is the pattern that decision 58 removed; avoid it.

Confidence: 0.85 (every step checked by reading, not run).

### The removal of the audit check `lib-fields`

- `Lib.fields` is ignored: `captured` does not use `lib` (`Model/WellFormed.lean:145`); `Bracket.lib`, `ResourceUse.lib` set only `ok` (`Model/Bracket.lean:513`, `Model/ResourceUse.lean:783-786`). `grep` for `.fields`, `libNote`, `lib-fields`, `LibProbe`: no use left except two stale doc comments (`Model/WellFormed.lean:383` still describes `lib.fields` as live; `Props/Phase6/HarnessPrivacy.lean:24`).
- No statement uses `HarnessPrivacy` (`UserPrivate`, `tokFree*`): `grep` finds them only in the module itself, its import in `CatsEffectInLean.lean:67`, and a registry note. The witnesses dropped `userPrivate`/`lPrivate` (`Proofs/Phase6/ResourceBoth.lean:55-56`, `ParTraverseWitness.lean` diff). The module is now dead code; remove it and its import.
- Is the removal a weaker gate? **No** for what the check did: it required a `libNote` when a `Lib` had no fields, and fields no longer change `WellFormed`. The four fixtures tested only that check (`scripts/test_audit.sh` diff). Decision 58 item 2 (user answer) authorizes the removal.
- But the reason in the core notes is too strong: "covered by construction, for every library and every environment" (`raw/cats-effect/2026-11-15-decision-58-core-notes.md`) is false for `REnv` indices (R1). The `lib-fields` check would not have caught R1 either.
- Regression examples present and of the right form: batch 5 `ULam.allocFn` (`PrivacyExamples.lean:45-49`), the event closure by name and by run-time number (`:51-66`), batch 6 `thenUse leafAcq` (`:78-82`), batch 8 F1 with an own cell and the honest form (`:87-98`), F2/F3 (`:109-128`, with the even looser `Lib` "every odd id"), `ParTraversePrivacy.lean:36-74` (defect D at the root, `TL.tag` not nameable, `Bracket`/`Race` sources, `fold` under `.some`, `CL.enter`/`CL.body`, honest functions accepted).

---

## Scope B: entries

### `core.IO.bracket.releaseOnce`, `core.IO.guarantee.finalizerOnce` (open)

1. MIRROR: yes. Only the encoding changed: every function field of `BLam` and `Src` is `.fn` (`Model/Bracket.lean`, diff of `BLam.toVal`/`ofFields`/`Src.toVal`); `call` is unchanged (`:340-472`).
2. PROPERTY: yes. Quantifiers unchanged (`Props/Phase6/Bracket.lean:247-262`: all `u`, `a0`, user `use`/`rel`, all schedules). F1 is closed: `hioOf` reads `.fn k` (`:180-184`), and the `constThis` closure value holds that reference, so `capOK` needs it available: an odd harness id is "held only" (regression `PrivacyExamples.lean:87-98`). The counters are `Ref` 0 and 1, allocated first; user code never receives them, nor a harness closure (`HLam.call`, `:199-212`: `use` and `rel` get only `a`). `Bracket.lib` is `Bracket.isLib` only (`Model/Bracket.lean:503-513`), so no `REnv` index exists in this environment. I found no forgery.
3. SETTLED: open.
4. Wrong-function: `test/Phase6/BracketSmokeParent.lean:65-66` (bracket without release) and `:70-71` (guarantee without finalizer) break the claims (`#guard breaks`, broken bodies `childOf` g = 2, 3, `Props/Phase6/Bracket.lean:186-194`).
5. Decision 53: `BracketWitness.bracketReleaseOnce_satisfiable` and `guaranteeFinalizerOnce_satisfiable` (`Proofs/Phase6/BracketWitness.lean:98-120`): kernel-checked runs (`decide +kernel`), the conclusion conjoins `WellFormed lib [] …` with the statement's `lib` and both parity hypotheses. Implies all hypotheses.

Verdict: FAITHFUL as statements.

### `kernel.Resource.both.releaseOnce` (refuted, CE-0020)

1. MIRROR: yes. `Bracket`, `Resource`, `ResourceUse` changed only the encoding of function fields (`RelFn.user`, `AllocFn.user`, `OnOut.user` hold `.fn`; `fnIndex`, `Model/Resource.lean:257`).
2. PROPERTY: the quantifiers are unchanged (`Props/Phase6/Resource.lean:216-224`). S1 is gone (`UserPrivate` dropped). S2 is fixed: `Private` now has the Phase 5 clauses with `libH` (`:204-210`). **But** R1: the hypotheses admit `a0 = forge relA`, so `BothReleasesBothFor impl` is false for every `impl`, also the fixed twin `fixedBothRes`.
3. SETTLED: yes as a theorem. `bothReleasesBoth_refuted : ¬ bothReleasesBoth` (`Proofs/Phase6/ResourceBoth.lean:75-82`) applies the statement to `markedA`, `markedB`, `both_private` and `wellFormed` (all hypotheses) and to the kernel-checked run `run_witness` (`:50-53`, log `[tagA, tagB, tagRA]`, `Errored boom`). Bug record `bugs/CE-0020.yaml` (one line changed in this diff). The witness is honest Scala code.
4. Fixed twin (decision 39): `ResourceBothFixed.fixed_satisfies` (`Proofs/Phase6/ResourceBothFixed.lean`, 120 schedules on the witness input, parts `Fixed_0..11`, `Old`). It separates v3.7.1 from the fix **on the witness input**. It does not show that the fix satisfies the statement, and by R1 the fix does not.
5. Rule "Fixed-twin check for refutations" (`wiki/methodology/agent-workflow.md`): "A refutation is HOLLOW when a correct implementation also refutes the statement." Batches 5 and 6 judged CE-0020 HOLLOW as registered for the same reason (a forgery).

Verdict: HOLLOW as registered. The bug is real (reproducer outputs in `bugs/CE-0020.yaml`, read in batch 8), and the witness meets the hypotheses. After the R1 fix the same witness should re-settle it without change (it uses no `RelFn.const` in user code).

### `kernel.Resource.use.releaseOnce`, `kernel.Resource.flatMap.releaseOrder` (open)

1. MIRROR: yes.
2. PROPERTY: **no**. R1: false for every implementation. S1 gone, S2 fixed (the hypotheses as stated are the right ones apart from R1).
3. SETTLED: open.
4. Wrong-function: I found no "release never runs" variant for these two in `test/Phase6/ResourceSmoke.lean` (`:109-110` checks `checkUse`/`checkFlat` only for holding). Advice: add one.
5. Decision 53: `ResourceWitness.use_sat` (`Proofs/Phase6/ResourceWitness.lean:55-70`) and `flat_sat` (`:91`): `MarkedMake ∧ Private ∧ WellFormed ∧ ∃ o …` with kernel-checked runs. Implies all hypotheses.

Verdict: HOLLOW.

### `parTraverseN`: shared

- MIRROR: yes. Only `f` fields became `.fn` (`Model/ParTraverse.lean` diff of `PT.toVal`/`ofFields`, `srcAction`, `ioOf` `:387-399`). No other number field names anything: `n` is a count; `srcPar` states hold `.fiber`/`.deferred` handles (`parLeaf`, `:354-357`); descriptors hold handles (`descIO`, `:372-384`).
- Privacy: no `REnv`-like table in this environment. F2 and F3 are closed by `WF.avail` (`ParTraversePrivacy.lean:60-66`).
- The new root of statement 1 (`orderRoot = IO.unit.flatMap(TL.start n as f)`, `Props/Phase6/ParTraverse.lean:136-137`; `TL.start` runs `parTraverseNIO n (listOf as) (TL.tag f).id`, `:132`). **It does not change the claim.** The outcome of `pure(()).flatMap(_ => p)` is the outcome of `p`; the extra step only adds interleaving points where nothing else runs. The domain is the same: before, the root named `PT.k1` with `.fn (TL.tag f)`, and `TL.tag` is not `lib.ok`, so no root passed `progOK` at all; now the root names the public `TL.start` with `.fn f` and `as`, so `f` and `as` must be handle-free (with `H0 = []`), which is what the old design meant. `TL.start` being public lets user code start more tagged traversals; that cannot touch the outer result `Deferred`s. The witness uses the new root (`ParTraverseWitness.lean:93-110`).

### `core.IO.parTraverseN.resultOrder` (open)

1. MIRROR: yes. 2. PROPERTY: yes. Quantifiers unchanged (`:145-150`: all `ord` permutations, `u`, `n ≥ 1`, `as`, even `f`). Defect D and F2 closed. Weakness kept from batches 7-8: "always raise" satisfies it alone; statements 2 and 5 cover success. 3. SETTLED: open. 4. Wrong-function: a reversed result breaks it (`tools/PtSmoke/Main.lean:271-274`, root `orderRoot`). 5. Decision 53: `parTraverseNOrder_satisfiable` (`ParTraverseWitness.lean:100-110`, `WellFormed ptLibDeep … (orderRoot …)`, kernel run).

Verdict: FAITHFUL as a statement.

### `core.IO.parTraverseN.pureSucceeds`, `errorAborts`, `cancelAborts`, `succeedsGen`, `errorAbortsGen`, `cancelAbortsGen` (open)

1. MIRROR: yes. 2. PROPERTY: yes. Statements are unchanged in this diff except the `Lib` (`:152-177`, `:242-268`). The behaviour of `f` is fixed, so no other user code is reachable; privacy does not apply. 3. SETTLED: open. 4. Wrong-function: dropped result (`tools/PtSmoke/Main.lean:275-278`), no `cancelAll` (batch 8 citation, same file; the wrong-function block starts at `:271`). 5. Decision 53: `ParTraverseWitness.lean:123` and later theorems (witness proofs adapted only in `simp` sets; `neverCapD` now states `cloHandles neverId = []`, `:153`).

Verdict: FAITHFUL as statements. Advice from batch 8 stands: record 3 and 4 as corollaries of 6 and 7.

### `core.IO.parTraverseN.atMostN` (open)

1. MIRROR: yes. Counter harness unchanged (`:348-369`).
2. PROPERTY: yes. `UserPrivate` dropped (S1 gone, `:404-410`). F3 rejected (`ParTraversePrivacy.lean:64`, `:74`). `CL.newCell` and `CL.afterCell` are public (`:381-388`): user code can make a new cell and run a nested counted traversal on it, but it cannot pass `.ref 0` to `afterCell` (no program it can build returns `.ref 0`), so `highest` on cell 0 is not affected. I found no forgery.
3. SETTLED: open.
4. Wrong-function: `Limit.wideRun_breaks` (1000 permits, kernel; `ParTraverseWitness.lean:381`).
5. Decision 53: `Limit.parTraverseNAtMostN_satisfiable` (`ParTraverseWitness.lean:347-355`): `WellFormed limLib …` and a kernel run with `highest = 1`; no `UserPrivate` conjunct, which matches the statement.

Verdict: FAITHFUL as a statement.

---

## The `HashSet` difftest (`alternatives`)

Files: `tools/Difftest/Main.lean` (diff: `k ≥ 5` gives `alternatives`), `tools/Difftest/Replay.lean` (`replayFieldsH`, `perms`, `replayAlternatives`), `tools/Difftest/Env.lean:547-559` (`rankOrder`, `ptMaxLen`), `difftest/py/drive.py` (`compare`, `cmd_check` `:493-506`), `difftest/cases/gen_v2_partraverse.py`, `difftest/py/gen.py`, `.github/workflows/ci.yml` (diff).

- **Acceptance is a correct refinement check.** Each alternative is a full model run with one `HashSet` order `rankOrder k perm`, which is a permutation (`mergeSort`), so it is a behaviour that the statements allow (`(ord xs).Perm xs`). Scala runs one real order. The driver accepts only if **one candidate matches on every compared field** (`bad` is computed per candidate over all fields; no mixing of fields across candidates). That is "the real result is in the model's set".
- Coverage: `rankOrder` ranks children by `fiber id mod k`. If children have consecutive fiber ids, all `k!` orders are present. If ids collide mod `k` (other fibers between the children), ties keep insertion order and some orders are missing. A missing order can only cause a false mismatch (fail-closed), never a false agreement.
- One fixed order per case is used for every set state; the statements allow any function. That is narrower than the statements, which is correct for a difftest of the model against one real run.
- No gate weakened: cases under 5 inputs are compared as before; `cases/partraverse.jsonl` is unchanged (the generator only appends a second file); the 32 hash cases run through Scala on every CI run (`drive.py check`), with no golden file because the Scala order can change between JVM runs; `known_model_bug` handling is unchanged. The random generator now picks 5 inputs (weight 2 of 14).
- Residual: with up to 120 candidates, a wrong model has more chances to match by luck. Only `pth-raise-parent-n5` has more than one distinct candidate (core notes); acceptable.

## Other notes

- Stale docs: `Model/WellFormed.lean:383` (`lib.fields` live), `Props/Phase6/HarnessPrivacy.lean` (dead module, still imported at `CatsEffectInLean.lean:67`), `Bracket.fnFields` and `ResourceUse.fnFields` stubs.
- Codec: tag 21 is added in `encVal`, `decVal` and the difftest tokens; `readLE_tag` covers `t < 22`. I did not re-read the roundtrip proof; the build proves it.

## Required fixes

1. Track Res: R1. Make `REnv` table references (or `USrc` codes) capabilities; add `forge` as a regression example; re-check CE-0020, `use.releaseOnce`, `flatMap.releaseOrder`.
2. Track Res: correct the claim "covered by construction, for every library and every environment" in the core notes and the wiki.
3. Any track: check the other environments for data codes that name a table entry or a program (for example `Race` sources `.nat 0`/`.nat 1` that name `fa`/`fb`, `Props/Phase6/Race.lean`; out of scope here).
4. Small: W1 (`rnVal`/`hasPoll` inside `Val.fn`), M1 (`allocRef` inside `AvailP`), remove `HarnessPrivacy` and the stale docs; add a wrong-function check for `use.releaseOnce`/`flatMap.releaseOrder`.

## Confidence

- `WF.avail` is sound for closure references: 0.8.
- R1 makes the three `Resource` statements false for every implementation: 0.85.
- `Bracket` entries FAITHFUL as statements: 0.75. `parTraverseN` statements FAITHFUL: 0.75.
- The `alternatives` acceptance is a correct refinement check: 0.85.

# Fixes after review batch 1 (decisions 26, 27, 28, 31)

> Source: own Lean work in this repository (`CatsEffectInLean/Model/Codec.lean`, `Model/WellFormed.lean`, `Props/*`, `Proofs/*`, `Registry.lean`, `tools/Audit/Core.lean`), Lean v4.35.0; scala-cli run of `reproducers/CE-0001` on Cats Effect 3.7.1
> Collected: 2026-11-10
> Published: 2026-11-10

Findings came from `review/2026-11-10-review-batch-1.md`. Decisions are in `raw/project-decisions/2026-11-10-phase0-decisions.md`.

## Decision 31: one closure codec

- Kept the `Val` bit-string code (Elias gamma for `Nat` fields, 5-bit tags, sentinel bit). Its code length is linear in the size of the value.
- Dropped the bit-interleave code (`pair`, `encList`). Its bit length doubles at each nesting level, so nested closure values (Resource stacks, queue closures) get very large numbers.
- New: `natToVal_valToNat : natToVal (valToNat v) = some v` (a general proof, not only examples). About 130 lines. Hard parts: `bitsLE` gives `l ++ [true]` with `valLE l + 2 ^ l.length = m`; `countZeros` on `replicate k false ++ true :: r`; `decVal` by induction on `Val` with fuel `(encVal v).length`.
- One id convention: library closure `2 * valToNat c + 1` (`libFn`), user closure `2 * valToNat c` (`userFn`). Closure value `cloVal ns tag fields`. Queue, Timeout and the CE-0003 program closures now capture handles as handle values (`Val.ref q`, `Val.poll m p`, `Val.cont s`, `Val.fiber c`).
- Timing (module, `lake env lean`): QueueTimeout proof 0.93 s before, 1.11 s after. ResourceEval 0.62 s before, 0.60 s after. Full `lake build --wfail` about 24 s, no change.
- Gotcha: small ids can decode to a closure value. Example: id `218` (`109` after `/ 2`) decodes to `Val.fiber 0`. So `WellFormed` rejects a user id `218` in a start program, because it "captures" fiber 0. Use `userFn (cloVal ...)` for test ids.

## Decision 27: `WellFormed`

- `Handle`: fiber, ref, deferred, poll, cont. `Val.handles` collects them.
- A user call holds: the handles of its argument, of its closure value (`captured id`), of the program scope `H0`, and all that it reaches through held `Ref`, `Deferred` and fiber outcomes (`Reach`, an inductive predicate; no fuel).
- `progOK lib mem p` (Bool): handles in `pure` values are held; `UnmaskRunLoop` needs a held poll; `Get` needs a held cont; `EndFiber` never; user ids even; odd ids only if `lib id` and the captures are held; `Fn.rt` only `cancel`, `join`, `deferredDefer`, `deferredFlatten`, `deferredComplete`, `voidK` with held handles.
- `CallOK`: view independence outside the held set (lengths of `refs` and `deferreds` stay visible: the model gives a new cell the id `length`); effects and output use held handles; new cells are held after allocation.
- `WellFormed lib H0 env p := progOK lib (H0.contains ·) p ∧ ∀ even id, ∀ arg v, CallOK ...`. The first part is decidable (`decide +kernel`). The second part is a `∀` over all arguments and views, so each witness needs a short proof, not `decide`.
- For `CallOK`, `progOK` takes `memOf R` (classical `decide` of the predicate). Proofs use the simp lemma `memOf_eq`.
- Witness proofs: CE-0001 (cases on the id; user ids renumbered to `0, 2, 4`; `H0 = refHandles refs`), CE-0002 (`REnv.WellFormed`: also `acquire`, `release`, `bind`), CE-0003 (one lemma per `PLam` case; needs `natToVal_valToNat`, `cloVal_of_ofCloVal`, `plam_ofFields_inv`).
- The proven IO laws keep twins `*_all` without `WellFormed`.

## Decision 26: CE-0001

- Schedules are now `steps bs` (only `step` choices). The proof did not change in substance: the direct run has no cancel, and the stepped closure set covers all choices.
- Rows cut to 5: `core.IO.syncStep#2`, `core.IO.IOAsync.syncStep`, `core.SyncStep.MaxSteps`, `core.SyncStep.interpret#2`, `core.SyncIO.unsafeRunSync`. The 22 `core.SyncIO.tag.*` and `core.SyncIO.runLoop.*` rows went back to `todo`.
- `scripts/run_reproducers.sh CE-0001` on 3.7.1: 4 / 4 cases differ, last line `REPRODUCED CE-0001`.

## Decision 28: audit

- New audit error: `inventory row <id>: status modelled, but no named registry entry is proven or refuted`.
- New self-test case `open_modelled`. The fixture inventories keep the open entry's row as `todo`.
- `inventory.csv`: the rows of the two open MonadCancel entries went back to `todo`. Modelled rows: 47 before this work, 25 after task 3, 23 after task 4.

## `uncancelablePollIsIdentity` smoke test with well-formed programs

- Old counterexample (child cancels fiber 0) is not well-formed (forged id).
- Well-formed `fa = start(emit 9) >> emit 1 >> n flatMaps >> emit 2`, alphabet `picks 3`, depth 3, fuel 1300, `n = 500..515`: the outcome sets differ only at `n = 508`. Left side: traces `[1, 2]` and `[1, 9, 2]`; right side: `[1, 2]` only. The forged version differs at the same `n` in this program shape (the old note had `509` for a shape with one more iteration).
- Cause: the left side has 2 more run-loop iterations, so its auto-yield comes before `emit 2` and the child can run. The run stops when the root completes, so the right side never shows `9`.
- So the counterexample does not need forged ids. It is the iteration-count effect of decision 29. The entry stays `open`; `Eqv` needs a preemption choice before a proof.

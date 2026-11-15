# Decision 58 core: closure references as `Val.fn` (track Res, 2026-11-15)

Own work. Decision 58 (user answer): closure references get their own `Val` constructor.

## Core (commit 8bbef2d)

- `Val.fn id`: a closure reference (even id: user closure; odd: library closure). Codec tag 21 (`encVal`/`decVal`, roundtrip theorem unchanged in form). Difftest token 21 (`tools/Difftest/Closure.lean`).
- `Handle.fn id`; `Val.handles` collects references, so every handle check covers them.
- **The structural rule** (`WF.availD`/`avail`, `Model/WellFormed.lean`): a handle is available if it is held, or if it is a reference to a user closure (even id) whose captured handles are all available (user code makes new closures only through its own even ids, which carry their own captured values). An odd (library) reference, a token cell, any other handle: only if held. Lemmas: `avail_fn_odd` (odd reference available iff held), `avail_fn_even_captured`, `avail_of_mem`, per-handle simp lemmas.
- Clause 5: `CallOK` holds user code to `AvailP (Reach v (H0 ++ arg.handles ++ captured id))`. Programs: `fnOK (.user id) = held (.fn id) ∨ ((even ∨ lib.ok) ∧ capOK)`; `progOK (.pure v)` uses `subA`.
- `captured` = the handles of the closure value (no field lists, no depth recursion). `Lib.fields` is ignored (kept only until track G drops it).
- Proof helpers: `WF.callOK_of_reach` (a proof with `Reach` gives `CallOK`), `progOK_mono`, `resultOK_mono`, `fnOK_userFn_of`, `fnOK_libFn_of`.

## Mirrors and statements of track Res

- `Bracket`, `Resource`, `ResourceUse`: every function field is `.fn`. `RelFn.user id`, `AllocFn.user id` hold the closure id; `Resource.fnIndex id` (even: `id / 2`; odd: `id`) is the `REnv.user` index. `OnOut.user f` holds `.fn f`.
- `ResourceUse.publicLib` (Bracket, Race, Timeout closures) is the `ok` of `libH`: the interpreter's own lambdas (`ULam`, `Clo`) are internal.
- Resource statements: `UserPrivate` dropped (S1 gone: user code may pass any value through). `Private` = the Phase 5 `REnv.WellFormed` clauses with `libH` for every non-harness entry (review batch 8, S2): closed acquire programs, release programs and `Bind` results with only their argument's handles, resources of codes with only the code's handles, and no non-harness entry names a harness table entry (`Res.idx`). `MarkedMake`: the resource code holds the token (`Handle.ref 0 ∈ c.handles`).
- `Bracket` harness (F1): `srcFa`, `srcFin`, `HLam.afterCells`/`relW`/`relCall` use `.fn`.
- Witnesses re-proven: CE-0020 (`run_witness` still `[A, B, RA]`, `Errored boom`), `use_sat`, `flat_sat`.

## Why removing the audit check `lib-fields` is not a weaker gate

The check `lib-fields` (decision 56) required a `libNote` for every registered statement whose `Lib` had no `fields`, because then `WF.captured` did not look into number fields that name closures. Decision 58 removes that mechanism: closure references are `Val.fn` values, `Val.handles` collects them at every depth, and the rule `WF.avail` accepts a reference only if it is held or is an own user closure with available captured handles. `Lib.fields` is ignored by `WellFormed`, so a check that it is filled in protects nothing. The risk it guarded (a closure named by number in a field, with unchecked captured handles) is now covered by construction, for every library and every environment (also `ioOf`/`srcIO` of the statements, which the probe lemmas missed: review batch 8, F1/F2). Regression examples that show this (`Proofs/Phase6/PrivacyExamples.lean`):

- Batch 5: `ULam.allocFn (.user markT)` in a user program is rejected.
- Batch 6 (track G): `BLam.thenUse leafAcq` (a leaf that captured the counter) is rejected.
- Batch 8 F1: `constThis (Src.ext (.pair (.ref 2) (.pair (.nat 1) (.fn (markA 1).id))))` is rejected with only `Ref` 2 held; the same with an own closure `.fn 14` is accepted.
- Batch 8 F2/F3: `TLam.fold (.some (srcAction fForge 0)) 3` with `fForge` capturing a `Deferred` or the semaphore `Ref` is rejected (reference found under `.some`); an honest `f` is accepted.
- Batch 6 (track Res): a run-time number names nothing (`fnOK libH (.user markT.id) = false`; `.nat markT.id` is data).
- S1: `idEnv_callOK`: `x => IO.pure(x)` passes `CallOK` on every argument.

The four self-test fixtures `fieldless_lib*` tested only that removed check.

## Removed

`Model/LibProbe.lean`, `Proofs/Phase6/LibFields*.lean` (probe lemmas), audit check `lib-fields`, `Entry.libNote` (13 notes), fixtures `fieldless_lib*`. `Props/Phase6/HarnessPrivacy.lean` stays until track G drops `UserPrivate` from statement 8.

## Difftest after the change (2026-11-15)

- All ops, `opcount.py --seeds 51 52 53 --n 20000` (ops rUse rAllocated rBoth bracket bracketCase bracketFull guarantee race both memoize parTraverseN): 60,000 cases, all agree, 0 unsupported.
- Resource ops boosted, `--seeds 61 62 63 --n 60000 --boost rUse=40 rAllocated=40 tpl_resBoth=40 res_both=10`: 180,000 cases, all agree; plus seed 64, 15,000 cases, all agree. Agreeing cases over seeds 61-64: rUse 117,382, rAllocated 87,564, rBoth 52,386.
- Smoke `test/Phase6/ResourceSmoke.lean` (CE-0020 600 + 1,500 schedules, the open statements on 900 schedules, decision 41): passes (27 min).

## Twin modules split for memory (2026-11-15)

Every `TwinChecks` module now peaks under 8 GB (`/usr/bin/time -v`, local), with the same inputs, schedules and conclusions:

- CE-0002 `Fixed_childCancel` (13.0 GB) and `Old_childCancel` (10.7 GB): `checkEqvP` = exact outcome set of each side and the comparison, three modules each in `ResourceEvalFixedParts/ChildCancel/` (5.3-7.6 GB, 26-41 s); the old theorem names are proven from them.
- `BracketSmoke` (12.5 GB): one module per check in `BracketSmokeParts/` (`Elab.async false`); `law_8_8` (12.5 GB alone) in three parts (`Half/`, 6.5-7.2 GB).
- `MemoizeFixed` (10.0 GB, 23 min): one module per check; each 120-schedule list in two halves of 60 (`range_split`), each grid in two halves by `a` (`grid_split`); `MemoizeFixedParts/Half/` (4.1-5.3 GB, 20-26 s).
- `scripts/check_twin_checks.sh` builds sub-part directories before their combining modules, one module at a time.

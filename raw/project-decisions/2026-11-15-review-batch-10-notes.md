# Review batch 10 notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-10.md`. Draft gate report: `wiki/methodology/phase6-gate-report.md`. Commit reviewed: `1dfe6ce` (R1 fix of track Res; `Race`/`Memoize` source references of track G). Read only; nothing was run.

## Findings

- R1 is closed. Every `REnv` table index in a value is `Val.fn k` (`RelFn.const`, `ioRelease`, stack frames, `AllocFn.make`, `Clo.makePair`, `applyPair`). Harness entries are odd, so `WF.avail` gives them to user code only if held. `Private` lost its hand-written `Res.idx` clause; `resOK` checks the references. The batch 9 `forge` term is a regression example (rejected with the harness entry, accepted with an own even entry).
- Wrong-function tests now exist for `use.releaseOnce` (use without release) and `flatMap.releaseOrder` (reversed nesting). Both are kernel runs on the witness input; `wellFormed` holds for every body.
- W1 is closed: `hasPoll`/`rnVal` follow `Val.fn` (fuel 4,096, parity kept).
- `Race` sides `.fn 1`/`.fn 3` and `Memoize` `faSrc = .fn 1` are sound. No `Val` has a code below 32 (5 tag bits plus a sentinel), so every closure id is at least 64; `cloOfId 1` and `cloOfId 3` are `none`.
- The heavy law `uncancelableRaceNotInherited` is unchanged in meaning: `lawSrcIO`/`lawDispatch` are the old `srcIO`/`dispatch`.
- D1 (low): user code can still run `fa` outside the tested `memoize` through its own cell (`srcIO fa (.ref k)`); this is Scala-expressible recursion, no claim breaks, but a registry sentence says the opposite.
- D2: no recorded `opcount.py` run of the `Resource` ops after the R1 encoding change (CI fixed cases only).
- D4: CE-0020 rows (`kernel.Resource.both`/`use`/`fold`) are still `todo`.
- Remaining number-named tables: only in the Phase 5 twins `ResourceFixed`, `SyncStepFixed` (closed programs; no risk).

## Verdicts

- FAITHFUL: CE-0020, CE-0030, the heavy race law (low strength).
- FAITHFUL as statements: `Resource.use.releaseOnce`, `Resource.flatMap.releaseOrder`, four race/timeout entries, `memoize.getsAgree`, `memoize.atMostOnce`.
- Carried after a diff check: CE-0005, `pureUse`, `guaranteeIsGuaranteeCase` (batch 4), `eval.preservesCancelable` (batch 5).

## Gate

All 25 Phase 6 entries have a latest verdict FAITHFUL. 3 refutations have bug records with `REPRODUCED` on v3.7.1, series/3.x and series/3.7.x. Gate: PASS, with conditions (CI green on `1dfe6ce`, reproducer re-run confirms, one `Resource` difftest run after R1).

## Lesson

The capability rule must cover every name, not only closure ids. After decision 58 and R1, the only names left in Phase 6 models are handles and references. Start Phase 7 models with `Val.fn` for every function, program code and table entry.

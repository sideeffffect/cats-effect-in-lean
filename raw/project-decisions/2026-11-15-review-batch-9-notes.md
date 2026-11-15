# Review batch 9 notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-9.md`. Commit reviewed: `1ea6ef3` (decision 58 core, track Res; `parTraverseN` adaptation, track G). Read only; nothing was run.

## Findings

- `WF.avail` (decision 58) is sound for closure references, by reading. An even id has only the power of its captured handles (`CallOK` for every even id). Naming an even id needs its captured handles available. An odd reference is available only if held. Every library dispatcher tests `isLibId` first. Tried: own closures with chosen captured values, returned or stored references, `Bind` results, data numbers, depth 65, codec tricks. All rejected.
- Not too strict: `x => IO.pure(x)` passes (`idEnv_callOK`); passing and storing references passes. Minor strictness: a closure that captures a cell allocated in the same call cannot be returned with `.ret` (the new cell joins `R` outside `AvailP`); a public library closure cannot be a value.
- R1 (new forgery): the `Resource` mirror keeps `REnv` table indices as data numbers (`RelFn.const k a`, `AllocFn.make a r`, stack frames). A `USrc` source code is data; `srcU` applies `RelFn.const k` as `U.r.release k`. A public `Bracket` leaf `constThis (Src.ext (USrc.relApp (RelFn.const relA ()) () ()))` holds no handle, so user code (or `a0`) runs the harness release program and logs `tagRA`. The three `Resource` statements are false for every implementation, also the CE-0020 fixed twin. Old hole; not found by batches 5-8; the batch 8 token construction would not catch it either.
- W1 (low risk): `hasPoll`/`rnVal` do not look inside `Val.fn`, so `PollOpaque` cannot see a poll captured by a referenced closure. No path found where such a reference reaches user code.
- `lib-fields` removal: not a weaker gate (fields no longer change `WellFormed`; user decision 58 item 2). But the core-notes claim "covered by construction, for every library and every environment" is false (R1).
- `HarnessPrivacy` is no longer used by any statement; it is dead code.
- `orderRoot`/`TL.start` (statement 1 of `parTraverseN`) does not change the claim: one extra `pure(()).flatMap` step before the traversal.
- `alternatives` in the `HashSet` difftest: correct refinement (each candidate is a model run with one permutation order; the Scala run must match one candidate on all fields). Missing orders (fiber id collisions mod k) can only cause a false mismatch.

## Verdicts

- FAITHFUL as statements: `bracket.releaseOnce`, `guarantee.finalizerOnce`, all 8 `parTraverseN` entries.
- HOLLOW: CE-0020 as registered (a correct `both` also refutes it through R1; bug and witness real), `Resource.use.releaseOnce`, `Resource.flatMap.releaseOrder` (R1).

## Lesson

Decision 58 closed one kind of name (closure ids). Any other name that a mirror reads from data (a table index, a program code) is the same risk. Check every decoder that turns data into a program or a table lookup, not only closure ids.

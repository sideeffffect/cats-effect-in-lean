# Decision 56: harness privacy must be shown by construction or by proof (2026-11-14)

Source: orchestrator decision after review batch 6 (`review/2026-11-14-review-batch-6.md`).

## Facts

- Review batches 4, 5 and 6 each found a new way for user code to forge a test marker:
  - batch 4: the hypotheses could not hold together;
  - batch 5: a marker id forwarded through `ULam.allocFn`;
  - batch 6: a `Ref` handle hidden in a closure id stored in a number field (`BLam.thenUse`, track G), and a marker id produced as a clock value (`IO.sleep 6 >> IO.realTime`) plus the `NoForge` escape clause (track Res).
- Each fix closed the known forgeries only. Three rounds of "patch the found forgery" did not converge.

## Decision

1. One shared module owns harness privacy for all Phase 6 tracks. Owner: track Res. Track G and later tracks reuse it.
2. Non-forgeability must hold by construction (harness tokens that user code cannot build, because no reachable value encodes them) or by a kernel-checked lemma (the privacy predicate is preserved by every step of user code). A list of known forgeries is not enough.
3. No escape clauses. Numbers that the runtime gives to user code (clock, counters, sizes) are user data.
4. Each forgery from batches 4–6 becomes a Lean `example` that shows the hypothesis rejects it (regression).
5. If `WellFormed.captured` does not see handles inside closure ids stored in number fields, that is a soundness gap of `WellFormed` for all entries. Fix it in `WellFormed` and re-check every proof that uses it.
6. The quantifiers stay the same: all user code, all schedules. A fix must not shrink the user code that the statement covers beyond "user code cannot name a harness token".

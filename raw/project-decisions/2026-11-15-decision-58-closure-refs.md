# Decision 58: closure references get their own Val constructor (2026-11-15)

## User answer

Question (after review batch 8): user code still forges test markers, because a plain number (`Val.nat`) is both data and a closure name. Options: separate closure refs; strict decoding only; strict now, redesign later.
Answer: "Separate closure refs (Recommended)".

## Facts at the time

- Review batches 4–8 each found a new marker forgery. Batch 8 found two that pass the deep `WellFormed` check and the kernel-checked `Lib.fields` probe lemmas (F1: `Src.ext` data read as a function id by `hioOf`; F2/F3: `ParTraverse.srcFnIds` does not look under `.some`).
- Root cause (review batch 8): `Val.nat` is both data and a closure name, so every hand-written list of "id fields" can miss one.
- The token construction in `HarnessPrivacy` (decode every number at any depth) held against every attack in batch 8.
- Scope limit S1: `UserPrivate`/`Private` exclude ordinary code such as `a => IO.pure(a)`.

## Decision

1. Add a separate `Val` constructor for closure references. Data numbers never name a closure.
2. `WellFormed` then follows closure references structurally. `Lib.fields`, the probe lemmas and the strict number decoding are no longer needed; remove them when the new form is proven.
3. Harness markers use closure references and handles that user code cannot build. S1 must go away: user code may pass any value through, as long as it does not build a harness reference.
4. Every closure id, kernel witness, the codec and the difftest decoder change. The difftest must reach 100% agreement again (≥ 50,000 cases, several seeds) before any statement is re-settled.
5. The Phase 6 gate waits for this change.
6. Never weaken a statement to make it fit the new form. The quantifiers stay: all user code, all schedules.

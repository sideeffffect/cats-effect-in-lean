# Review batch 18 notes (2026-11-25)

Source: review/2026-11-25-review-batch-18.md (independent reviewer; reading only, ran only `python3 scripts/check_wiki.py`). Reviewed commit `022a6a5` (B2 fix `59afd7f`). Do not edit.

- Entry `std.Dispatcher.noLostSubmission`: FAITHFUL. B2 closed.
- Conclusion `accepted j = true → status j = 2` is the `DP:130-133` promise for `await = true` (an accepted effect is awaited; a non-accepted submission claims nothing). It matches `bugs/CE-0090.yaml` `expected`.
- Inputs by reading: `c = IO.canceled` → no concurrent submission accepted, body tasks awaited: holds; `c = IO.never` → root never done: vacuous; `c` raises → `.attempt` catches, submissions as usual: holds for a correct Dispatcher.
- `accepted` is exact: `rej` saves the result of every returned submission (pair for `unsafeToFutureCancelable`, `some ()` for `unsafeRunAndForget`); an `IllegalStateException` sets only the flag. Nobody can cancel the submitter between the return and the save (the only self-cancel point `c` runs before the first submission; the root only joins). `unsafeRunAndForget` uses the same path (`DP:85-89`).
- Refutation: exact negation; uses `accepted 1 = true` and `status 1 = 0` of R32. Twin 32 (R33) and witness R34 are correct kernel facts.
- Wrong function "always reject / throw": vacuous for this statement; `dispAwaitDrains` breaks it (any total rejecter leaves status 0 for `ms = [0]`; kernel `awaitDrains_v1`, R02). Named in the registry note and battery table.
- R10, R12, R13 changed only cell 6 (`()` → `some ()`); R11, R14 did not change; their observations do not read cell 6. Same meaning.
- Gate batch 7.2: PASS, on condition C5 (CI green on `022a6a5`, incl. `heavy-proofs`, `TwinChecks`), not checked by the reviewer.
- Low notes: the wiki says "R10-R14 regenerated" (only R10, R12, R13 changed); `late` submitters are excluded from statement 3 (covered by `dispClosedRejects`); task and body fixed to `IO.pure(())` (earlier reviewed domain).
- Rule: a conclusion "every accepted X happened" needs (a) an observation that is set exactly when X was accepted, for every submission kind, and (b) a success companion that breaks "accept nothing".

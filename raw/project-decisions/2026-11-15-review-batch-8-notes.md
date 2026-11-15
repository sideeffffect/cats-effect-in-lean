# Review batch 8: harness privacy, parTraverseN, heavy CI matrix (own note)

> Source: independent read-only review of commit `cf362d7` (track Res round 6 with track G `fe38330`) and track P commit `bd1483c`: `Model/WellFormed.lean`, `Model/LibProbe.lean`, `Props/Phase6/{HarnessPrivacy,Bracket,Resource,ParTraverse,Memoize,Race}.lean`, `Model/{Bracket,ParTraverse,Timeout,ResourceUse,Resource}.lean`, `Proofs/Phase6/{LibFields*,PrivacyExamples,ResourceBoth,ResourceBothFixed,ResourceWitnessEnv,ParTraverseWitness}.lean`, `tools/PtSmoke/Main.lean`, `tools/Audit/Core.lean`, `bugs/CE-0020.yaml`, `.github/workflows/{ci,paranoid-heavy}.yml` and the heavy scripts at `bd1483c`. Full review: `review/2026-11-15-review-batch-8.md`.
> Collected: 2026-11-15
> Published: 2026-11-15

## Verdicts

- HOLLOW: `core.IO.bracket.releaseOnce`, `core.IO.guarantee.finalizerOnce` (F1). A user `constThis (Src.ext (.pair (.ref r) (.pair (.nat 1) (.nat (HLam.markA 1).id))))` passes the deep `WellFormed`: `Src.fnIds` of an external source is `[]`, but `hioOf` reads the `.nat k` field as a function id. It bumps counter 1 outside the harness position. `LibFieldsBracket` runs with `ioOf = pure`, so its lemma does not cover `hioOf`.
- HOLLOW: `core.IO.parTraverseN.resultOrder` (F2, batch 7 defect D still open). `ParTraverse.srcFnIds` does not look under `.some`; `Timeout.fold (.some src)` runs `srcIO src`. No `fold` sample in `LibFieldsParTraverse`, no coverage lemma for `TLam`/`RLam`/`BLam` there.
- HOLLOW: `core.IO.parTraverseN.atMostN` (F3). Same path; user code writes the `MiniSemaphore` state `Ref` (not a token), so more than `n` actions run.
- HOLLOW (scope, S1): `kernel.Resource.use.releaseOnce`, `flatMap.releaseOrder`. `UserPrivate`/`Private` quantify over all arguments, so `a => IO.pure(a)` is excluded. Not a documented precondition. Same class as batch 7 defect C: needs a user decision.
- FAITHFUL: CE-0020 (witness meets the deep hypotheses and `Private`; reproducer and kernel fixed twin).
- FAITHFUL as statements: `parTraverseN` `pureSucceeds`, `errorAborts`, `cancelAborts`, `succeedsGen`, `errorAbortsGen`, `cancelAbortsGen`. The `HashSet` order input over-approximates correctly; the behaviour harness of 5-7 is a fair extra statement.

## Other findings

- S2: the Phase 6 `Resource` statements check `a0` and non-harness `REnv` programs only with `tokFree*`, not with `progOK` (Phase 5 `REnv.WellFormed` has it).
- Difftest of `parTraverseN` stops at 4 inputs; the `HashSet` branch is not differentially tested.
- The token construction (`tokFreeV`: decode every number, any depth) had no hole. `ResourceUse.srcCodeIds` (any depth) also had none. The hand-written lists of `Bracket` and `ParTraverse` had holes.
- CI (`bd1483c`): main + heavy at least as strong as the old gate. Residuals: default-target build unsandboxed in heavy jobs (as in main), manifest ignores symlinks, unlisted artifact files installed, `grep -qi error` false failure on theorem names, empty matrix fails, branch protection not shown.

## Design advice

Decode every number leaf in `WF.captured` (as `tokFreeV` does) and drop `Lib.fields` and the probes; use the token construction for every marker statement; later (user decision) separate closure references from data numbers in `Val`, which also removes S1.

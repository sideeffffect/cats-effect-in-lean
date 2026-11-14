# Decision 55: heavy proofs in a separate lib, registry and CI job (orchestrator)

> Source: orchestrator decision after track P round 2 (law `uncancelableRaceNotInherited` proven by a certificate check: +30 min `lake build`, +38 min `lake check`; the CI `lean` job has `timeout-minutes: 60`), 2026-11-10; implementation by track P
> Collected: 2026-11-10
> Published: 2026-11-10

55. Proofs that take more than about 5 minutes go to a separate lean_lib `HeavyProofs` (not a default target), with their own registry module `CatsEffectInLean/RegistryHeavy.lean` (same `Entry` type). They are checked in a separate CI job on every push and pull request, with its own timeout. No gate gets weaker: every check of the old single registry still runs on every push, in one of the two jobs.

## Implementation (track P)

- `lakefile.lean`: `lean_lib HeavyProofs` (roots `CatsEffectInLean.Proofs.Phase6.RaceLaw`), `lean_exe audit_heavy` (`tools/Audit/MainHeavy.lean`).
- `CatsEffectInLean/RegistryHeavy.lean` is light (in the default target): it imports only `Registry.lean`. Heavy theorems are named with a single backtick (no compile-time check); `heavyModules` lists the heavy roots.
- `Audit.Config` has `heavy` and `verifyHeavy`.
  - Main job (`lake exe audit`, `verifyHeavy := false`): all checks of `Registry.lean`; for heavy entries every check that needs no heavy module (id, rows, `prop` exists/`def`/`Prop`/module/axioms, status-theorem-bug consistency, bug file); ids unique across both registries; inventory cross-check over both registries, except that a `modelled` row settled only by a heavy entry is deferred (counted and printed, not accepted).
  - Heavy job (`scripts/check_heavy_proofs.sh`): builds the heavy modules one `lake build` per module in import order; `lake exe audit_heavy` (`verifyHeavy := true`, imports the heavy modules) audits both registries in full and runs the full inventory cross-check (deferred rows included); explicit `#print axioms` check; kernel replay with `leanchecker` of every heavy module, one process each (`leanchecker M` replays only the declarations of `M`: the law root alone takes 23 s, one chunk module about 3 min).
- Self-test (`scripts/test_audit.sh`): nine new fixture cases (`heavy_*`): deferral in the main mode, full check, missing/wrong theorem caught only in the full mode, missing theorem field, non-`def` property, open heavy entry on a `modelled` row, duplicate id across registries.
- CI: new job `heavy-proofs` in `ci.yml` (150 min). New scheduled workflow `paranoid-heavy.yml` (weekly, 350 min): `leanexport` of the heavy root and `lake check --from-export --paranoid`. The weekly `paranoid.yml` (180 min) does not see the heavy lib; six kernels over the heavy lib are estimated at about 4 h, so they do not fit into 180 min.
- Open points for the user: QUESTIONS.md Q4 (make `heavy-proofs` a required check; paranoid run may not fit 350 min).

## Measurements (local, 16 cores)

- Heavy build (49 chunks in 10 chained modules): about 30 min, peak RSS 8.3 GB per Lean process.
- Kernel replay: see the CI timings in the track P report (one chunk module: about 3 min, 7.5 GB).
- Default build after the move: the law modules are gone from `lake build` and `lake check`.

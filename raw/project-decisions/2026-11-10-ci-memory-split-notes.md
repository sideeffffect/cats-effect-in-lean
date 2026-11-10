# CI cancelled by memory: CE-0002 fixed-twin checks split out (orchestrator)

> Source: own measurements, 2026-11-10 (`/usr/bin/time` on each module; GitHub Actions run of f24d38c)
> Collected: 2026-11-10
> Published: 2026-11-10

- CI run of f24d38c: job "Lean build and proof checks" ended with exit code 143 (SIGTERM) after 6 minutes inside `lake build`. The likely cause is memory: the hosted runner has 16 GB.
- Measured peak memory per module (one Lean process each):
  - `Proofs/Calibration/ResourceEvalFixed.lean` (9 checks): 13.0 GB, 192 s.
  - `Proofs/Calibration/ResourceEvalFixedOld.lean` (9 checks): 10.7 GB, 140 s.
  - After a split into one check per file: `Fixed_childCancel` alone 13.0 GB, `Old_childCancel` 10.7 GB, `Fixed_childJoin` 8.8 GB, `Old_childJoin` 7.2 GB; the rest below 4 GB. So one `decide +kernel` for the `childCancel` program needs 13 GB. Splitting files cannot lower that.
  - All other modules of the library: at most 4.0 GB (`Model/EnumPExamples.lean`).
- Fix: the CE-0002 fixed-twin checks are not a registered property (the registered refutation does not import them). They moved to `lean_lib TwinChecks`, outside the default target. A separate CI job `twin-checks` runs `scripts/check_twin_checks.sh`: it builds one module per Lean process, then checks the axioms of `fixedTwin_holds`, `v371_fails`, `v371_fails_more`. No proof was dropped. Local run: 343 s, peak 13.0 GB.
- Risk: 13 GB on a 16 GB runner is tight. If the job fails by memory, the next step is a cheaper check (for example `decide_cbv`, or a smaller bound for that one program, recorded as such), not removal.
- Also: the CI comment that said known model bugs are "printed only" was stale after decision 32 and is corrected.

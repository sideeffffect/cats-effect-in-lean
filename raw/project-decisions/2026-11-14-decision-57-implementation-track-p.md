# Decision 57 implementation: heavy CI matrix and paranoid by kernel (own note, track P)

> Source: own work (`.github/workflows/ci.yml`, `.github/workflows/paranoid-heavy.yml`, `scripts/heavy_closure.py`, `scripts/heavy_build.sh`, `scripts/check_heavy_module.sh`, `scripts/check_heavy_proofs.sh`, `scripts/run_kernel.sh`, `scripts/sandbox.sh`, `tools/HeavyList.lean`, `tools/CertGen/mk_racelaw_chunks.py`); measurements on this machine (16 cores; "4 cores" = `taskset -c 8-11`), Lean v4.35.0
> Collected: 2026-11-14
> Published: 2026-11-14

## CI jobs (`ci.yml`; other job names unchanged)

| Job id | Name | What |
|---|---|---|
| `heavy-plan` | Heavy proofs plan | `scripts/heavy_closure.py --from-lakefile --matrix`: JSON list of the non-root heavy modules (import closure of the lakefile roots minus the default target) |
| `heavy-module` | Heavy module (<M>) | matrix over that list: default-target deps outside the sandbox, heavy deps and M one at a time in the sandbox (`scripts/heavy_build.sh`: each build may change only its own artifacts; work tree unchanged), `leanchecker M` in the sandbox, upload of M's artifacts with a sha256 list |
| `heavy-audit` | Heavy proofs audit (roots, audit_heavy, axioms) | `HEAVY_ARTIFACTS_IN=… scripts/check_heavy_proofs.sh`: default target and `audit_heavy` first (binary copied out of `.lake`), `heavyModules` vs lakefile roots, an artifact set for every non-root module (else fail), artifacts installed and required byte-identical after the sandboxed builds, roots built and replayed in the sandbox, copied `audit_heavy`, `#print axioms` |
| `heavy-proofs` | heavy-proofs | aggregate, `needs` the three, `if: always()`, fails unless all succeeded: the stable required check |

- Chunk modules no longer import each other (each imports only `RaceLawDefs`; `RaceLaw` imports all ten), so the matrix jobs are independent.
- Trust: each heavy module is built and replayed in its own job; a later build in the same job cannot change an earlier module's artifacts (per-module hash check over all of `.lake`); the audit job uses exactly the replayed artifacts (sha256 check after its own sandboxed builds).

## Measurements

- Cold default-target dependencies of a chunk module (4 cores): 10 s. Cold rest of the default target plus `audit_heavy` (4 cores): 283 s.
- `heavy-module` jobs (warm default target, one after another): CertLhs 3 s, CertRhs 3 s, Defs 6 s, Chunks0–9: 370, 355, 375, 392, 362, 348, 341, 349, 336, 273 s (build plus replay; max 6.5 min).
- `heavy-audit` with the artifacts installed (default target already built, 4 cores): 56 s; the downloaded artifacts were used without a rebuild.
- Critical path of the split (plus runner setup per stage): about 0.2 + 6.7 + (4.7 + 0.9) ≈ 13 min. One job on one runner: 4.7 + about 58 (sum of the module jobs) + 1 ≈ 64 min. The split saves about 50 min, so it stays.
- Negative test: a missing artifact set (`Chunks4`) makes `heavy-audit` fail ("no artifacts … (matrix job missing)").

## Paranoid (`paranoid-heavy.yml`)

- `paranoid-heavy-export`: sandboxed build (SKIP_REPLAY=1) and one sandboxed `leanexport` of every derived heavy module; artifact `heavy-export`.
- `paranoid-heavy-kernel`: matrix `[default, lean-paranoid, lean4lean, nanoda, con-leche, con-ron]`, 350 min each, `scripts/run_kernel.sh` (same commands as `lake check --paranoid`: `bundledKernels`, `runExternalKernel` in `Lake/CLI/Check.lean`; nanoda gets the same config file; `LEAN_ABORT_ON_PANIC=1`; sandboxed).
- `run_kernel.sh` checked on the `CatsEffectInLean.Basic` export (345 MB): default 77 s, lean-paranoid 76 s, nanoda 16 s, con-leche 19 s, con-ron 10 s, lean4lean 84 s; all exit 0.
- Default kernel on the full heavy export (362 MB, 61,734 declarations): 33 min. The other kernels on the heavy export are not measured.

# Orchestrator notes: Phase 6 batch merges

> Source: own findings while merging tracks G, R, D, P, M, Res, 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

- Parallel tracks that add difftest ops touch the same 13-16 files (Scala `Ast`/`Json`/`Interp`, Lean `Prog`/`Closure`/`Env`/`Translate`, `gen.py`, `selftest.py`, `typecheck.py`, `ci.yml`, registry, wiki). Two tracks (G, R) each made their own "format v2". A text merge gave 16 conflicts that need meaning, not line union.
- What worked: the orchestrator merges the first finished branch and pushes it; then it asks the next agent to merge `origin/main` into its own branch (it knows its own code), run all checks, and report. The orchestrator then fast-forwards. Track M did this before its report: its merge was a fast-forward.
- Rule for briefs: an agent merges `origin/main` into its branch just before its final report. Give each track its own bug-id range and closure-codec namespace range (P: CE-0010+, Res: CE-0020+/ns 20-29, M: CE-0030+/ns 30-39).
- Two orchestrator merge errors, both caught by the checks before a push: (1) a union of two conflict hunks in `selftest.py` dropped the line that defines `rt` (NameError); (2) a union of two `Registry.lean` blocks lost the comma between list entries (build error). A shell pipe `| tail` hid a non-zero exit code once; read exit codes directly.
- Generator weights interact with the per-op minimums of `selftest.py` (N = 400): a new op with a high weight pushes other ops under their minimum. Fix only the new track's weights; never lower a minimum.
- Heavy `decide +kernel` modules (> 3 min or > 8 GB) go to `lean_lib TwinChecks` and `scripts/check_twin_checks.sh` (decision 45). `check_twin_checks.sh` counts the axiom reports; each track that adds a module raises the count.

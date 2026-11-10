# Orchestrator notes: merge of Phase 0 spikes and inventory

> Source: own findings while merging agent branches, 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

- `~/.gitignore_global` line 253 ignores `*.csv`. `git add -A` in the inventory agent's worktree skipped `inventory/inventory.csv` without a message. Fix: `!inventory/*.csv` in the repository `.gitignore`.
- The inventory agent also committed `scripts/__pycache__/*.pyc`. Fix: `__pycache__/` in `.gitignore`.
- Agents that may not edit `wiki/index.md` cannot pass `check_wiki.py` alone when they add an article. The orchestrator adds the index lines at merge time.
- Two agents both appended a See Also line to `wiki/semantics/modeling-approaches.md`. The merge conflict was trivial (keep both).

## CI red from d0e2d9a to 83288c2 (found and fixed 2026-11-10)

- Symptom: CI job "Difftest runner (Scala)", step `selftest.py`: `Error: Could not find or load main class cats.effect.difftest.Main`.
- Cause: `difftest/run.sh` cached `sbt ... export Runtime/fullClasspath | tail -n 1`. sbt prints an `ESC[0J` terminal escape after the class path line, so the cache held only the escape. Local runs passed because an older, good cache file existed in `difftest/target/`.
- Fix: strip ANSI escapes, select the line that ends in `.jar` or `/classes`, fail if empty. Verified in a clean clone.
- Lesson: a local pass with build caches does not prove CI passes. Before a push that changes CI or harness scripts, run the new steps in a clean clone. After each push, check `gh run list` before the next merge.

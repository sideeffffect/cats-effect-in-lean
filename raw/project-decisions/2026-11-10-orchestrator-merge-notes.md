# Orchestrator notes: merge of Phase 0 spikes and inventory

> Source: own findings while merging agent branches, 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

- `~/.gitignore_global` line 253 ignores `*.csv`. `git add -A` in the inventory agent's worktree skipped `inventory/inventory.csv` without a message. Fix: `!inventory/*.csv` in the repository `.gitignore`.
- The inventory agent also committed `scripts/__pycache__/*.pyc`. Fix: `__pycache__/` in `.gitignore`.
- Agents that may not edit `wiki/index.md` cannot pass `check_wiki.py` alone when they add an article. The orchestrator adds the index lines at merge time.
- Two agents both appended a See Also line to `wiki/semantics/modeling-approaches.md`. The merge conflict was trivial (keep both).

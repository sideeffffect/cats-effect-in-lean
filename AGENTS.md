# AGENTS.md

Rules for all AI agents that work in this repository.

## Knowledge wiki (MANDATORY)

This repository has an LLM wiki (Karpathy pattern). The wiki is the long-term memory of this project. You MUST use it and grow it in every session.

### Structure

- `raw/` — Source material (articles, papers, docs, notes, research output). Do not change files in `raw/` after you add them.
- `wiki/<topic>/<article>.md` — Compiled knowledge articles. One level of topic directories only.
- `wiki/index.md` — Index of all articles: link, summary, and Updated date, grouped by topic.
- `wiki/log.md` — Append-only log of all wiki operations.

Use the `karpathy-llm-wiki` skill for the exact formats and workflows (ingest, query, archive, lint). If the skill is not available, follow the structure above.

### 1. Learn from the wiki first

- At the start of each task, read `wiki/index.md`.
- Read all articles that relate to the task before you plan, design, or write code.
- Prefer facts from the wiki to your training knowledge. If the wiki and other evidence disagree, find out which is correct and fix the wiki.

### 2. Add all new knowledge to the wiki

Record each new item in the wiki in the same session that you find it. Do not wait for the end of the task. This includes:

- New facts about Lean 4, Cats Effect, effect systems, or the libraries we use.
- Findings from debugging, experiments, and proofs (what worked, what failed, and why).
- Research results, web sources, papers, and documentation that you read.
- Design decisions and their reasons.
- Gotchas, workarounds, and toolchain behavior.

Procedure:

1. Save the source material to `raw/<topic>/` (for your own findings, write a short note there as the source).
2. Merge the knowledge into an existing article, or make a new article.
3. Update related articles and their See Also links.
4. Update `wiki/index.md` and append to `wiki/log.md`.

### 3. Maintain and lint the wiki

- Run a wiki lint at the end of each task that changed the wiki, and at least once per session.
- Fix broken links, missing index entries, and missing cross-references.
- Mark contradictions and outdated claims. Correct them when you have evidence.
- Keep articles short, factual, and current. Merge duplicates.

## Git

- Commit and push all changes immediately to `origin/main`, unless the user explicitly tells you to do something different.
- This includes wiki changes.

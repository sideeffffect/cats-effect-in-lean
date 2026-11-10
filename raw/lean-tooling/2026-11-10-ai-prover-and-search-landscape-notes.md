# AI provers and Lean search tools: landscape notes (from web search results)

> Source: web search result summaries (2026-11-10); primary URLs listed per item
> Collected: 2026-11-10
> Published: Unknown (mixed; see each item)

These are notes from search-result summaries, not full-text reads. Treat numbers as reported by the authors.

## Open-weight provers (whole-proof generation, mostly competition math)

- Goedel-Prover-V2 (ICLR 2026). 32B: 88.0% miniF2F pass@32 (90.4% with self-correction). 8B: 84.6%
  pass@32, beats DeepSeek-Prover-V2-671B. PutnamBench: 86 problems at pass@184.
  https://arxiv.org/abs/2508.03613 ; https://proceedings.iclr.cc/paper_files/paper/2026/hash/13e8be77982beb73d7ed0bbf122f9f3c-Abstract-Conference.html
- DeepSeek-Prover-V2-671B: 82.4% miniF2F pass@32; up to 88.9% at pass@8192; PutnamBench 49/658.
  https://arxiv.org/abs/2504.21801
- Kimina-Prover (72B) preview: 80.7% miniF2F at pass@8192. (Project Numina also maintains
  `lean-explore`, see below.)
- LongCat-Flash-Prover (2026) catalogs 9 cheating patterns found with AST consistency checks.
  https://arxiv.org/pdf/2603.21065
- Relevance to this project: LOW. These models target math-competition statements over Mathlib,
  not program semantics / interpreter models. General coding agents (Claude, GPT) with
  lean-lsp-mcp are the practical tool for software-model proofs.

## Commercial agents

- Harmonic Aristotle: Lean 4 prover agent. API with API key; Python SDK/CLI `aristotlelib`;
  accepts Lean files with `sorry` holes, English or LaTeX. Community MCP wrappers:
  `gleachkr/aristotle-mcp`, `septract/lean-aristotle-mcp`. Product page (2026) now markets
  code verification: deterministic compiler of (C) code to Lean using separation logic;
  results are Proved (with assumptions), Refuted (with runnable counterexample), or Unresolved.
  https://aristotle.harmonic.fun/
- Math, Inc. Gauss: autoformalization agent. Strong PNT (~25k lines, 3 weeks, 2025);
  sphere packing dim 8 and 24 (2026, reported 200k+ lines). Needs human natural-language
  scaffolding. Early access only. https://www.math.inc/gauss ; https://arxiv.org/html/2604.23468v3

## Search tools (all reachable from lean-lsp-mcp)

- LeanSearch (natural language -> Mathlib), Loogle (type-pattern search; remote rate limit
  3 req/30 s, local mode available), Lean Finder, Lean Hammer premise search.
- LeanExplore (arXiv 2506.11085, Justin Asher, 2025-06): hybrid search over Batteries, Init,
  Lean, Mathlib, PhysLean, Std (embeddings + BM25+ + PageRank). PyPI `lean-explore` 1.x has
  CLI, local backend and MCP server. https://arxiv.org/abs/2506.11085 ; https://pypi.org/project/lean-explore/

## Anti-cheating references

- Vero (arXiv 2608.13522, 2026-08): 3 layers: slot re-rendering, axiom allowlist, declaration
  screening (malicious Decidable instances, `@[implemented_by]` oracles). native_decide was the
  dominant axiom-leak pattern.
- SafeVerify and Comparator (now `lake comparator` in v4.35.0): check that the submitted theorem
  has the identical statement and uses only allowed axioms.
- Research-swarm case study (arXiv 2609.04170): keyword-based anti-cheat filters were bypassed by
  local `notation` commands that rewrote statements into tautologies.
- LessWrong "Don't trust Lean4 alone": https://www.lesswrong.com/posts/jgmmMa7AqJNausrqx/don-t-trust-lean4-alone

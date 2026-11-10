# Phase 6 start: work plan and decisions (orchestrator)

> Source: own decisions after the user approved the Phase 5 gate and said "start the next phase", 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

User message (verbatim): "start the next phase"

Decisions:

47. Phase 6 runs in batches. Each batch has parallel agents, one track per agent, each in its own git worktree and branch. The orchestrator merges the branches, runs the pre-push checks, and pushes to `main`.
48. Batch 6.1 tracks:
    - **G** (`guarantee*`, `bracket*`): mirrors of `IO#guarantee` (`IO.scala:496`), `IO#guaranteeCase` (`:523`), `IO#bracket`/`bracketCase` (`:338`, `:370`), `IO.bracketFull` (`:1826`) and the kernel defaults as twins; difftest ops; properties.
    - **R** (`race`, `both`, `raceOutcome`, `bothOutcome`): mirrors of `IO.race` (`:1788`), `IO.both` (`:1732`), the `IO#` entry points and the `GenSpawn` defaults as twins; a fiber-leak observation; difftest ops; properties, also "no leaked fiber after `timeout`".
    - **D** (difftest depth): format-v1 ops to at least 50,000 agreeing cases each over at least 3 seeds (Phase 5 gate caveat 4).
49. Batch 6.2: `Resource` (`use`, `allocated`, `both`, `flatMap` finalizer order, the cancelable direction of CE-0002 from decision 41). It needs the `IO#guarantee` mirror from track G. Also `memoize`. Batch 6.3: `parTraverseN`. Then review batch 4 of all new entries.
50. Cancel inside a property comes from a fiber of the program (for example a parent that cancels a started child). The harness has no outside canceller (decision 22). "Release runs when the use is canceled" is stated with such a program fiber.
51. New difftest ops form format v2. Each op mirrors one Scala API call. The Scala runner, the Lean decoder and the generator get the op in the same change.
52. Shared files (`Registry.lean`, `CatsEffectInLean.lean`, `inventory/inventory.csv`, difftest sources, `wiki/index.md`, `wiki/log.md`): agents add at the end of the relevant block. The orchestrator resolves merge conflicts.

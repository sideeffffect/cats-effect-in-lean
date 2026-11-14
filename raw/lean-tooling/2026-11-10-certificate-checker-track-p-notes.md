# Certificate checker for closed state sets; law uncancelableRaceNotInherited proven (own note, Phase 6 track P round 2)

> Source: own work in this repository (`CatsEffectInLean/Proofs/Lemmas/CertP.lean`, `CatsEffectInLean/Proofs/Lemmas/Frame.lean`, `CatsEffectInLean/Proofs/Phase6/RaceLaw*.lean`, `tools/CertGen/Gen.lean`, `tools/CertGen/RaceLaw.lean`), Lean v4.35.0, measured on this machine (16 cores, 125 GB)
> Collected: 2026-11-10
> Published: 2026-11-10

## Why

`checkEqvP`/`exactP` (`Model/EnumP.lean`) search and remove duplicates with list membership in the kernel: about n²/2 state comparisons. For the left side of `GenSpawnLaws.uncancelableRaceNotInherited` (4,441 states) this does not finish (8 min timeout in track R).

## Design

- Untrusted generator (`tools/CertGen/Gen.lean`, run with `lake env lean --run`): breadth-first search in interpreted code with a `HashMap` on `hash Sched.key` and full `==` on collisions. 4,441 states in about 2 s.
- Certificate: (1) a spanning tree as instructions (`0` = pop, `1` = preempt child, `n + 2` = pick-n child), written in depth-first order of the BFS tree (depth 57 for the law, 11 for `never`); (2) for each listed state the list index of each `succsP` successor.
- Kernel checker (`CertP`): `certGo` replays the tree from `Sched.init` (each child is `tickP` of a non-halted parent, so every listed state is reachable: `certStates_reach`, `reach_run`); `certClosed` checks every edge with one `Sched.fastEq` against `L[j]?`. Soundness: `closedP_of_certClosed` → `ClosedP` → `outcomesP_sub_closed`; reachability gives the other direction (`outcomesP_iff_of_cert`). A wrong certificate makes the check `false`.
- Chunks: `certChunk io is succ a n` checks the edges of states `a .. a+n-1`; `EdgesUpTo` composes chunks of any size (`edgesUpTo_zero`, `edgesUpTo_chunk`, `certExact_of_edgesUpTo`).

## Measurements (`decide +kernel`, law left side)

- Replaying the tree (all 4,441 states, only `halt` forced): 21 s, 3.7 GB.
- Edge check of 100 states, extra on top of the replay: 0.5 GB (states 0–99) up to 5.9 GB (states 4000–4099); 25–68 s per declaration. The comparison (`fastEq`) costs almost nothing (8.47 GB vs 8.26 GB without it); the cost is computing the successors of the later, larger states.
- One declaration for all edges: 18.6 GB peak and a recursion-depth error in the final `match` over 15 cases (replaced by the `EdgesUpTo` chain).
- A DFS spanning tree (depth in the thousands) and the BFS tree (depth 57) cost about the same.
- Memory is per declaration (a file with 15 chunks peaked at the largest chunk, not the sum).
- `decide_cbv` on a chunk fails at once with "maximum recursion depth" (also with `maxRecDepth 10000000`).
- Final layout: 49 chunks sized from the profile (up to 250 states early, about 50 late; a single 500-state chunk at the start needed 8.85 GB, so the profile underestimates early chunks), 5 per module, modules chained by imports so that `lake` builds them one after another.

- CI cost: `lake build` of the chunk chain about 30 min (peak RSS 8.3 GB per process, module `RaceLawChunks4`); `lake check` about 38 min (leanchecker peak about 7.4 GB).

## Other results of the round

- F1b proven (`Frame.result_stable`): a `ContState` cell with `.result v` keeps it in every later state ("first callback result wins"). Added as a fourth `Frame`/`SFrame` field (`Sticky`).
- Leak/winner entries: still open; gap unchanged (S, F3, F4, P1/P2, H, C(r)).

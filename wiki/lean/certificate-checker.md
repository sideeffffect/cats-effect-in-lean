# Certificate checks of closed state sets (`CertP`)

> Sources: own Phase 6 track P work, 2026-11-10 (`CatsEffectInLean/Proofs/Lemmas/CertP.lean`, `tools/CertGen/`, `CatsEffectInLean/Proofs/Phase6/RaceLaw*.lean`); Lean v4.35.0
> Raw: [Certificate checker notes](../../raw/lean-tooling/2026-11-10-certificate-checker-track-p-notes.md)

## Overview

`checkEqvP`/`exactP` remove duplicate states with list membership in the kernel (about n²/2 comparisons). That works up to a few hundred states. `CertP` moves the search out of the trusted base: an untrusted generator writes a certificate, and the kernel checks it in linear time. Use it for any exact outcome set of the preemptive scheduler with more than about 500 states.

## How to use

1. Write a small generator file like `tools/CertGen/RaceLaw.lean`: call `CertGen.writeCert cfg mm env io path header ns`. It writes `instrs : List Nat` and `succ : List (List Nat)` as Lean source.
2. Run it: `tools/CertGen/Gen.lean` must be compiled to an `.olean` on `LEAN_PATH`, then `lake env lean --run <generator>` (script in the raw note). The BFS takes seconds.
3. In a proof module: `certExact cfg mm env io (instrs.map decodeInstr) succ = true` (chunked for large sets), and `certObsOnly ... o₀ = true` or `certObs` for the observations.
4. `outcomesP_iff_of_cert` gives `outcomesP io o ↔ o ∈ certObs ...`; `outcomesP_iff_of_certObsOnly` gives `outcomesP io o ↔ o = o₀`. Two of these give `EqvP`.

## Soundness

- The tree instructions are replayed from `Sched.init`: each listed state is `tickP` of a non-halted listed parent, so it is reachable (`certStates_reach`, `reach_run`). The first listed state is the start state.
- `certClosed` checks every successor of every non-halted listed state against the listed state at the given index (`Sched.fastEq`). This gives `ClosedP` (`closedP_of_certClosed`) and so `outcomesP_sub_closed`.
- A wrong certificate makes the check `false`. The generator is not trusted.

## Cost and chunks

- The kernel caches every term it evaluates, per declaration. Replaying 4,441 states costs 21 s / 3.7 GB; the edges of 100 states add 0.5–6 GB (more for later, larger states). The state comparison is cheap; computing the successors is the cost.
- So split the edge check: `certChunk io is succ a n` (states `a .. a+n-1`), composed by `edgesUpTo_zero`, `edgesUpTo_chunk`, `certExact_of_edgesUpTo`. Chunks may have any size.
- Memory is per declaration. Put several chunks in one module, and chain the modules by imports so that `lake` does not run them in parallel.
- Size chunks from a profile (100 states at a few offsets). The law `uncancelableRaceNotInherited` uses 49 chunks (up to 250 states early, about 50 late; each declaration at most about 7.5 GB).
- `decide_cbv` on a chunk fails at once with a recursion-depth error; use `decide +kernel`.
- The tree shape (DFS tree vs BFS tree) does not change the cost much.
- CI cost of the law (measured 2026-11-10): `lake build` of the 10 chained chunk modules about 30 min (about 3 min each, peak RSS 8.3 GB per process); `lake check` (leanchecker replay) about 38 min, peak about 7.4 GB. The orchestrator may want to move these modules to a scheduled job.

## Results

- `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO`: proven (`Proofs/Phase6/RaceLaw.lean`).

## See Also

- [Kernel evaluation of the model](kernel-evaluation.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)
- [Race no-leak invariant and frame lemmas](../semantics/race-invariant.md)
- [race, both and fiber leaks](../cats-effect/race-both-model.md)

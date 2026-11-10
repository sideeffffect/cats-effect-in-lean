# Kernel evaluation of the model

> Sources: own spike `spikes/kernel_eval/` (toy fiber interpreter), Lean v4.35.0, 2026-11-10; Lean reference manual (decide, cbv, decide_cbv); Lean source `Lean/Meta/Tactic/Cbv/Main.lean`, `Lean/Meta/Sym/Simp/SimpM.lean` at v4.35.0
> Raw: [Kernel-eval spike notes](../../raw/lean-tooling/2026-11-10-kernel-eval-spike-notes.md); [decide / cbv / vcgen](../../raw/lean-tooling/lean-reference-tactics-decide-cbv-vcgen.md); [Local experiments](../../raw/lean-tooling/2026-11-10-local-experiments-lean-v4-35-0.md)

## Overview

Refutations must be checked without `native_decide`. Phase 0 step 3 built a toy fiber interpreter (fuel, structural recursion, explicit scheduler) and measured kernel-checked evaluation.

Answer (confidence 0.85): **yes, refutations can be checked by brute evaluation.** A refutation needs one concrete schedule. Its check costs almost nothing: a 5,000-step run checks in about 6 s with `decide +kernel`. For "all schedules up to depth k" proofs, use `decide_cbv` on a `Bool` checker plus one soundness lemma. `decide_cbv` memoizes equal states, so its cost grows with the number of distinct states, not with the number of schedules.

## Tactics compared (v4.35.0)

| Tactic | How it evaluates | Best for |
|---|---|---|
| `decide +kernel` | Kernel reduction only, once | One concrete run (fastest, least memory) |
| `decide`, `rfl` | Elaborator `whnf` first, then kernel | Same results, 1.5–2.5× slower than `+kernel` |
| `decide_cbv` | Call-by-value rewriting with equation lemmas; hash-consed cache; proof checked by the kernel | Enumeration of schedules; well-founded definitions |

All four give only standard axioms. The toy needed only `propext` (and `Quot.sound` for the soundness lemma).

## Size limits (60 s, 8 GB)

| Task | Tactic | Limit found |
|---|---|---|
| One schedule, 2–3 fibers | `decide +kernel` | ≥ 5,400 steps in 6 s / 1.1 GB. Needs `set_option maxRecDepth 100000`. |
| One schedule | `decide_cbv` | 4,815 steps in 48 s / 2.8 GB. Needs `set_option cbv.maxSteps` (the default 100,000 passed 783 steps and failed at 2,415). |
| All schedules, plain kernel | `decide +kernel` | About 65,000 paths: depth 16 with 2 choices (33 s / 6 GB), depth 8 with 4 choices (19 s / 3.9 GB). Doubles per extra step. |
| All schedules, memoized | `decide_cbv` | About 15,000–25,000 distinct (depth, state) pairs. 2 fibers: depth 100 (1.3e30 paths) in 11 s. 3 fibers: depth 20 in 20 s; depth 30 (48,319 pairs) takes 158 s / 7 GB. |
| Find a witness by search | `decide +kernel` on a DFS | Depth 15, 4 choices: 3.4 s. Gives a `Bool`, not an `∃`. |

The toy states are small. Real `IOFiber` states are larger, so expect lower limits. Measure again on the Phase 2 model.

## Proof shapes that work

1. **Concrete run**: `summary (run code 51 sched init) = some v := by decide +kernel`.
2. **Refutation**: `theorem p_refuted : ¬ P := by intro h; have := h witnessSched (by decide) (by decide); revert this; decide +kernel`. Find the witness with `#eval` of a search function, then paste the list into the proof.
3. **Bounded ∀ schedules**: a `Bool` checker `forallSched k s` (structural on `k`), one generic lemma `forallSched_sound : forallSched k s = true → ∀ l, l.length ≤ k → (∀ c ∈ l, c ∈ cs) → P (exec l s)`, and `decide_cbv` for the checker. The lemma is 15 lines and is written once. So **enumeration needs one soundness lemma per checker**, not a proof per property.

Unbounded properties (all schedules, all depths, liveness) still need proofs by lemmas. Kernel evaluation only covers bounded statements.

## Design rules for a kernel-evaluable model

- **Recursion**: `step` is not recursive (one transition per call). Loops (`run`, checkers) are structural on a `Nat` fuel or depth, or on the schedule list. No `partial def`. No well-founded recursion: `decide` fails on it, and `decide +kernel` worked at 783 steps but failed at 4,815.
- **Data**: plain inductives and structures with derived `DecidableEq`. `Nat` for ids, tags, fiber ids, continuation ids. `List` for stacks and fiber tables. `Array`, `Fin`, `String` reduce but give no speed-up and add proof terms. No `Float`, no `HashMap`, no `IO`/`ST`.
- **User code**: a structure of functions (`Code`) passed as a parameter works with kernel reduction. First-order ids (`Nat`) for continuations keep `Prog` decidable.
- **Program builders**: avoid id collisions in continuation tables (the toy reserves id ranges).
- **Options in proof files**: `maxRecDepth` for long runs; `cbv.maxSteps` for `decide_cbv`. Do not change `maxHeartbeats` globally in the library; set it per declaration if needed.
- **Avoid in checkers**: explicit deduplication by `DecidableEq` (slow in the kernel); `decide_cbv` does the sharing for free.
- **Out of fuel** stays a separate `Result` case; checkers must treat it as "no claim", never as a CE outcome.

## Open points

- `decide_cbv` memory grows with state size (7 GB at 48,000 three-fiber states). Large real states may need a compact state encoding or symmetry reduction.
- `lake check` replays the kernel check; `decide_cbv` proofs are large terms. Measure `lake check` time on Phase 2 proofs.

## See Also

- [Lean v4.35.0 toolchain](toolchain-v4-35.md)
- [Proof hygiene and agent tooling](proof-hygiene-and-agent-tooling.md)
- [Modeling approaches for CE3 in Lean](../semantics/modeling-approaches.md)
- [Project plan](../methodology/project-plan.md)

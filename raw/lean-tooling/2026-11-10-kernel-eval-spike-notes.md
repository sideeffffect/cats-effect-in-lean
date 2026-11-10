# Kernel-evaluation spike: toy fiber interpreter (own measurements)

> Source: own experiments, `spikes/kernel_eval/` in this repository (toy model `KernelEval/Toy.lean`, driver `bench.py`), Lean `v4.35.0`
> Collected: 2026-11-10
> Published: 2026-11-10

## Setup

- Machine: 16 cores, 125 GB RAM (other agents ran in parallel; up to 4 Lean processes at once).
- Each case: one Lean file with one theorem, run as `/usr/bin/time lake env lean -M8000 -DmaxHeartbeats=0 FILE`, with `set_option maxRecDepth 100000` and `set_option cbv.maxSteps 100000000`. Timeout 120–180 s.
- Times include about 0.47 s of Lean start-up and `import KernelEval` (baseline file with no theorem: 0.47 s, 786 MB max RSS). RSS below 820 MB is the baseline.
- Toy model: untyped `Val` (unit, nat, bool), `Prog` with `pure`, `raiseError`, `delay` (user function id), `flatMap` (continuation id, continuation stack), `uncancelable` (mask counter), `onCancel` (finalizer list), `cede`, `start`, `join`, `cancel`, one `Ref` cell. `step : State → Choice → State` is not recursive. `run : Nat → List Choice → State → Result` is structural on fuel; `Result` has `done`, `outOfFuel`, `schedEnd`. `Choice = {fib : Nat, obs : Bool}` (`obs` = observe a pending cancel now).
- User code (`kont`, `user`) is a `Code` structure of functions, passed as a parameter. Kernel reduction handles function fields without problems.
- Buggy variant (`bug = true`): when a cancel is observed, the mask is not raised and the finalizer list is not cleared, so a second observation runs the finalizer again.

## Tactics available in v4.35.0

- `decide` (elaborator `whnf`, then kernel re-check), `decide +kernel` (kernel only), `rfl`, `decide_cbv` (call-by-value rewriting with equation lemmas; proof checked by the kernel). All four exist and are not on the forbidden list.
- `decide_cbv` has a step limit: option `cbv.maxSteps`, default 100,000. Over it: "`simp` failed: maximum number of steps exceeded". Raise it with `set_option cbv.maxSteps N`.
- `decide_cbv` is built on `Lean.Meta.Sym.Simp`, which hash-conses terms and caches results by pointer (`Sym/Simp/SimpM.lean`). Effect: equal subterms (for example the same state at the same depth) are evaluated once. Plain kernel reduction has no such sharing for our checker and explores every schedule.

## Measurements: one schedule (round-robin), `summary (run ...) = some (.nat X)`

| Fibers | Steps | `decide +kernel` | `decide` | `rfl` | `decide_cbv` |
|---|---|---|---|---|---|
| 2 | 39 | 0.48 s | 0.50 s | 0.50 s | 0.74 s |
| 2 | 111 | 0.52 s | 0.58 s | 0.58 s | 1.07 s |
| 2 | 399 | 0.73 s | 0.94 s | 0.92 s | 2.87 s |
| 2 | 783 | 1.01 s | 1.45 s | 1.44 s | 5.8 s |
| 2 | 2,415 | 2.38 s | 3.93 s | 3.88 s | 21.8 s / 1.6 GB (default `cbv.maxSteps` fails) |
| 2 | 4,815 | 5.67 s / 1.0 GB | 8.79 s | 8.74 s | 47.5 s / 2.8 GB |
| 3 | 121 | 0.54 s | 0.62 s | 0.59 s | 1.13 s |
| 3 | 751 | 0.99 s | 1.39 s | 1.37 s | 4.9 s |
| 3 | 5,431 | 5.95 s / 1.1 GB | 9.80 s | 9.27 s | 53.3 s / 2.9 GB |

All results: axioms `[propext]` only.

## Measurements: all schedules up to depth k (`forallSched ... k init = true`)

Program `cancelProg 4` (main starts a child with `onCancel`, cedes, cancels it, joins). Property: finalizer ran at most once, checked at every state.

| Branching (choices) | Depth k | Paths (b^k) | `decide +kernel` | `decide` | `decide_cbv` |
|---|---|---|---|---|---|
| 2 (fiber 0/1) | 8 | 256 | 0.60 s | 0.72 s | 0.73 s |
| 2 | 12 | 4,096 | 2.57 s | 5.09 s | 1.13 s |
| 2 | 14 | 16,384 | 8.2 s / 1.9 GB | 18.6 s | 1.18 s |
| 2 | 16 | 65,536 | 33.3 s / 6.0 GB | 84 s / 6.0 GB | 1.30 s |
| 2 | 18 | 262,144 | >120 s | >120 s | 1.55 s |
| 2 | 60 | 1.2e18 | — | — | 5.7 s |
| 2 | 100 | 1.3e30 | — | — | 10.8 s / 1.1 GB |
| 4 (fiber × obs) | 6 | 4,096 | 1.53 s | 3.03 s | 0.67 s |
| 4 | 8 | 65,536 | 19.0 s / 3.9 GB | 47.9 s / 3.9 GB | 0.84 s |
| 4 | 10 | 1,048,576 | >120 s | >120 s | 1.03 s |
| 4 | 30 | 1.2e18 | — | — | 4.7 s |
| 4 | 60 | 1.3e36 | — | — | 11.5 s / 1.1 GB |

`forallSchedCut` (stop a path when all fibers are done) gave the same times as `forallSched` within 10% (depth 16: 35.9 s vs 33.3 s). The cut saves little, because few paths finish within these depths.

Three fibers (`threeChains 3`, 3 choices, property `Ref ≤ 9`), `decide_cbv`:

| Depth | Distinct (depth, state) pairs | Time | Max RSS |
|---|---|---|---|
| 12 | 561 | 1.70 s | 0.8 GB |
| 20 | 6,391 | 19.8 s | 1.6 GB |
| 30 | 48,319 | 157.7 s | 7.0 GB |
| 40 | — | >180 s | — |

Distinct (depth, state) pairs for `cancelProg 4`: 703 (k=16), 2,775 (k=30), 7,515 (k=60), 13,835 (k=100). The same counts for 2 and 4 choices (the `obs` bit changes nothing when no cancel is pending).

Breadth-first variant with explicit deduplication (`forallLevels`, `dedup` by derived `DecidableEq`): kernel 6.8 s at depth 16 (2 choices), 8.5 s at depth 12 (3 fibers), >120 s at depth 30. `decide_cbv` on it hit `cbv.maxSteps` (default). Explicit dedup in the kernel is slower than letting `decide_cbv` memoize.

## Measurements: refutation witnesses (buggy toy)

| Statement | Tactic | Time |
|---|---|---|
| `∃ cs, finRuns (exec code true cs init) = 2` with the 15-step witness given | `decide`, `decide +kernel`, `rfl` | 0.47–0.48 s (no cost above baseline) |
| same | `decide_cbv` | 0.65 s |
| `(findSched ... 15 init).isSome = true` (kernel DFS search, 4 choices) | `decide +kernel` | 3.4 s / 0.94 GB |
| same | `decide_cbv` | 29.5 s / 5.8 GB |

The search finds the witness without help, but a `Bool` search result is not a `∃ cs, ...` proof. To get the `Prop`, either give the witness list (found by `#eval`) or prove a small soundness lemma for the search function.

## Representation probes (`KernelEval/Repr.lean`)

- Well-founded recursion (`termination_by`): plain `decide` fails (definition irreducible; "reduction got stuck at ... .beq 6"). `decide +kernel` works at 51 and 783 steps but fails at 4,815 steps ("failed to reduce to true or false"), where the structural version takes 5.7 s. `decide_cbv` works (uses equation lemmas). Fragile: avoid.
- `exec` (structural on the schedule list) at 4,815 steps without `set_option maxRecDepth`: "(kernel) deep recursion detected". With `maxRecDepth 100000` it works.
- `String` literal equality, `Array.set!`/`a[i]!` on 200 elements, `Fin` equality: all reduce with `decide +kernel`. No benefit over `Nat`/`List` in the kernel; extra proof terms.
- The toy definitions `step`, `run` depend on `propext` (in proof positions, from compiled matches). It does not block reduction. Derived `DecidableEq` instances depend on no axioms.

## Proof shapes checked (`KernelEval/Witnesses.lean`, 4 s total build)

- `twoChains3_run`: concrete 51-step run, `decide +kernel`. Axioms `[propext]`.
- `finAtMostOnce_buggy_refuted : ¬ FinAtMostOnce true choices2 15 (cancelProg 4)`: instantiate with the witness schedule, then `decide +kernel`. Axioms `[propext]`.
- `forallSched_sound`: generic soundness lemma (induction on depth, 15 lines). Axioms `[propext, Quot.sound]`.
- `finAtMostOnce_correct_proven : FinAtMostOnce false choices2 30 (cancelProg 4)` (all 4^30 schedules of length ≤ 30): `decide_cbv` on the checker + the soundness lemma. Axioms `[propext, Quot.sound]`.
- `scripts/check_forbidden.py` scans `spikes/` (it uses `rglob("*.lean")` from the repository root): OK, 9 files.

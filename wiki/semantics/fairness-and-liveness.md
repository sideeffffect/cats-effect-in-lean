# Fairness and liveness in the CE3 model

> Sources: liveness spike 2026-11-10 (`spikes/liveness/Liveness.lean`); Cats Effect v3.7.1 source (`IOFiber`, `IORuntimeConfig`, `WorkerThread`, `TestContext`); Marlow et al. 2001; dejafu (Walker & Runciman 2015, README)
> Raw: [Liveness spike notes](../../raw/effect-semantics/2026-11-10-liveness-spike-notes.md); [Marlow 2001](../../raw/effect-semantics/2001-06-marlow-asynchronous-exceptions-in-haskell.md); [dejafu paper](../../raw/effect-semantics/2015-09-dejafu-concurrency-testing-library-haskell.md); [dejafu README](../../raw/effect-semantics/dejafu-readme.md); [IOFiber excerpts](../../raw/effect-semantics/ce3-iofiber-runloop-masking-excerpts.md)

## Overview

The user decided: safety **and** liveness from the start. Safety properties quantify over all schedules. Liveness properties quantify over **fair** schedules only.
A schedule is an infinite stream of choices. Fairness is a predicate on the schedule alone. Picking a fiber that cannot run is a stutter.
The spike proves all three statement shapes on a 2-fiber toy (no `sorry`, axioms `propext` and `Quot.sound` only). Recommendation confidence: 0.8.

## Recommended definitions (Phase 2)

```lean
abbrev FiberId := Nat
structure Choice where
  fiber : FiberId
  observeCancel : Bool      -- a pending cancel is seen at this step
abbrev Schedule := Nat → Choice

-- Each fiber id is picked infinitely often at an observing step.
def Fair (s : Schedule) : Prop :=
  ∀ (i : FiberId) (n : Nat), ∃ m, n ≤ m ∧ s m = ⟨i, true⟩

-- Liveness: every fair run finishes within some finite number of steps.
def Terminates (p : Prog) : Prop :=
  ∀ s, Fair s → ∃ n, (run s p n).isDone
```

- Step semantics: picking a finished, suspended or not-yet-started fiber changes nothing (stutter). With this rule the schedule-only `Fair` covers weak fairness: the adversary can still pick a fiber only when it cannot progress.
- The step checks `shouldFinalize` (`canceled ∧ masks = 0 ∧ observeCancel`) **before** the instruction, as `IOFiber.runLoop` does.
- Keep `FiberFair` (fiber picked infinitely often, any `observeCancel`) as a weaker helper; `Fair → FiberFair`.
- `BoundedFair B` (each window of `B` choices has an observing pick of each fiber) implies `Fair`. Do **not** use it as the main hypothesis: CE does not promise it.
- For a difftest under `TestControl` (one thread), use `observeCancel = true` at every step. `false` only models JVM visibility delay.

## What Cats Effect guarantees (v3.7.1)

- `shouldFinalize()` runs on every run-loop iteration, before the instruction (`IOFiber.scala:242-244`, `1172-1176`).
- `canceled` is a plain `var` (`IOFiber.scala:102`). A read barrier runs every `cancelationCheckThreshold` iterations (default 512, `IORuntimeConfigCompanionPlatform.scala:26-28`; loop at `IOFiber.scala:224-230`). So an unmasked running fiber sees a cancel within 512 of its own steps.
- Auto-yield every `autoYieldThreshold` iterations (default 1024; `IOFiber.scala:231-239`). With FIFO-like queues this gives weak fiber fairness, if every user thunk returns.
- A suspended, unmasked fiber is finalized by the canceller itself (`IOFiber.scala:142-160`). It needs no scheduler turn.
- Nothing bounds the steps of other fibers. No global bounded fairness.
- `TestControl`/`TestContext`: random tie-break `id + rnd` per task (`TestContext.scala:65-76`, `312-329`). Fair with probability 1 only. Hypothesis (0.65, untested): a task behind a `cede` spin loop has an unbounded expected wait.

## Prior art

- **Marlow 2001**: nondeterministic relation; a thread *may* receive an exception; no fairness assumption. Safety semantics only.
- **dejafu**: schedule bounding (preemption bound 2, fair bound 5 on `yield` counts). Runs past a bound are aborted. It finds bugs; it does not prove liveness.
- **GHC**: preemption only at allocation points; a non-allocating loop is not preemptible. Same limit as a CE `delay` thunk that never returns.
- **Intended CE behaviour**: an endless loop inside `uncancelable` never observes cancel, and its `cancel` never returns. Not a bug.

## Proof techniques (from the spike)

- **Per-fiber ranking + induction on the rank.** Fairness gives the next index where the fiber steps. Frame lemmas (other fibers do not touch this fiber; outcomes are stable) are most of the work.
- **Finite reachable set + `decide`.** List the reachable states, check closure under all choices by `decide`, then induct on `n`. Instant for 3–7 states. It caught a wrong claim (cancel can win before `uncancelable` starts).
- **Lasso refutation.** Prefix + cycle that returns to the same state, covers every fiber with `observeCancel = true`, and is not done. A generic lemma turns it into a fair non-terminating schedule. Side conditions are closed, so `decide` checks them.
- **Bounded preemption** (dejafu view): finite enumeration for safety and for finding lasso candidates. It cannot prove liveness.
- Gotchas: a `let` at the head of a `def` blocks `split`; `simp` rewrites structure literals and breaks later `rw`. Details in the raw note.

## Liveness properties realistic for Phase 4

- Finite closed programs (no `never`, no blocked `async`, no spin wait, finite user code) terminate under `Fair`.
- `cancel` of a fiber whose masked regions are finite returns (backpressure rule) under `Fair`.
- A fiber that keeps reaching unmasked cancelable points observes a pending cancel.
- `join` of a finished fiber returns; `Deferred.complete` then `get` wakes the waiter.
- Refute liveness with lassos only; check that the cycle is realistic for the JVM (observing steps at least every 512 steps of a fiber).
- Keep `open`: unbounded fiber creation (multiset ranking), time (`sleep`), the real work-stealing pool.

## See Also

- [Modeling approaches for CE3 in Lean](modeling-approaches.md)
- [Semantics of CE3](../cats-effect/semantics.md)
- [Project plan](../methodology/project-plan.md)
- [Differential testing](../methodology/differential-testing.md)

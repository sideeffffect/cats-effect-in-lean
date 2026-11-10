# Liveness spike: fairness, termination and cancel observation (Phase 0, step 4)

> Source: own spike `spikes/liveness/Liveness.lean` (Lean 4 v4.35.0, core only); Cats Effect v3.7.1 source in `~/Projects/cats-effect` (tag `v3.7.1`); raw notes on dejafu and Marlow 2001 in this directory
> Collected: 2026-11-10
> Published: 2026-11-10

## What Cats Effect v3.7.1 gives (source, path:line at v3.7.1)

- Defaults on the JVM: `cancelationCheckThreshold = 512`, `autoYieldThreshold = 2 * 512 = 1024`. Both can be set by system properties. `core/jvm/src/main/scala/cats/effect/unsafe/IORuntimeConfigCompanionPlatform.scala:26-32`.
- Constraints: `autoYieldThreshold > 1`, `cancelationCheckThreshold > 0`, auto-yield is a multiple of the check threshold. `core/shared/src/main/scala/cats/effect/unsafe/IORuntimeConfig.scala:33-39`.
- Run loop counters: each `cancelationCheckThreshold` iterations the fiber does `readBarrier()`; it subtracts from the auto-cede budget; when the budget is 0 or less it reschedules itself (`resumeTag = AutoCedeR`, `rescheduleFiber`). `core/shared/src/main/scala/cats/effect/IOFiber.scala:224-240`.
- `shouldFinalize()` is checked on **every** iteration, before the instruction. `IOFiber.scala:242-244`. Definition: `canceled && masks == 0`. `IOFiber.scala:1172-1176`.
- `canceled` is a plain `var` (not volatile). `IOFiber.scala:102`. Visibility from another thread comes from `readBarrier()` = `suspended.get()`. `IOFiber.scala:1379-1382`. So on the JVM a running, unmasked fiber observes an external cancel after at most 512 of its own iterations (plus barriers at resume points). On one thread (TestControl) it observes it at the next iteration.
- External cancel: `canceled = true`; if the target is suspended (`resume()` succeeds) and unmasked, the **canceller** takes over the run loop and runs the finalizers. `IOFiber.scala:142-160`. A suspended fiber does not need a scheduler turn to observe cancel.
- `cedeR` restarts the loop with fresh counters. `IOFiber.scala:1453-1454`.
- `IO.cede` Scaladoc: "IO itself will automatically introduce fairness boundaries" (auto-yield). Long thunks inside `delay` degrade fairness; "this problem is somewhat fundamental". `core/shared/src/main/scala/cats/effect/IO.scala:1520-1541`.
- Work-stealing pool: a worker checks the external queue every `ExternalWorkTicks = 32` ticks and polls every `PollingTicks = 64` ticks. `core/jvm/src/main/java/cats/effect/unsafe/WorkStealingThreadPoolConstants.java:47-53`; `core/jvm-native/src/main/scala/cats/effect/unsafe/WorkerThread.scala:829-830`.
- TestControl uses `TestContext` (`testkit/shared/src/main/scala/cats/effect/testkit/TestControl.scala:366-367`). Each task gets a random `rnd` at `execute` (`kernel-testkit/shared/src/main/scala/cats/effect/kernel/testkit/TestContext.scala:65-76`). Order: `runsAt`, then `id + rnd` (`TestContext.scala:312-329`). The Scaladoc says the random factor "simulate[s] nondeterminism" (`TestContext.scala:145-147`).

## Conclusions on CE fairness (own analysis)

- CE promises no formal fairness. In practice: auto-yield every 1024 iterations plus FIFO-like queues give **weak fairness of fibers** (each runnable fiber runs again eventually), provided every user thunk returns. A thunk that never returns is outside any step model.
- Cancel observation is **bounded per fiber** on the JVM (512 own iterations) and immediate on one thread. Nothing bounds the number of steps of *other* fibers in between, so a global bounded fairness is not promised.
- In a CE model, "enabled" is persistent: a fiber that is in a queue stays there until it runs; a suspended fiber is resumed by an enqueue. So weak and strong fairness agree for runnable fibers. Busy-wait loops (`ref.get` + `cede`) are always runnable.
- TestControl (hypothesis, confidence 0.65, not tested): the tie-break key `id + rnd` is fixed per task, and every re-enqueue gets a fresh random key. A task with a large key is overtaken by each new task with probability close to 1. Starvation has probability 0, but for a uniform key the expected wait of a task behind a `cede` spin loop is unbounded (integral of `1/(1-u)`). Difftests of spin-wait programs can take very long under some seeds.

## dejafu, Marlow 2001 and GHC

- dejafu (training knowledge, confidence 0.7; the raw README only says "Testing of potentially nonterminating programs" and that bounds "can be configured, or even disabled"): systematic testing with schedule bounding. Defaults: preemption bound 2 and fair bound 5. The fair bound limits the difference in `yield`/`threadDelay` counts between threads. It makes spin loops with `yield` finite. Runs that pass a bound are aborted, not reported as bugs. Older versions also had a length bound. dejafu reports deadlock; it does not prove liveness.
- Marlow et al. 2001: the semantics is a nondeterministic transition relation. (Receive) says a runnable thread in an unblocked context *may* receive the exception; a stuck thread may be interrupted in any context. The raw text has no fairness condition (no hit for "fair"). So an exception in flight can stay forever: the semantics is about safety only. (ThrowTo) lets the caller continue at once (GHC later made `throwTo` synchronous; CE `cancel` waits for finalizers, stronger).
- GHC runtime (training knowledge, confidence 0.8): preemption only at heap-check (allocation) points; a non-allocating loop cannot be preempted and cannot receive an async exception (`-fno-omit-yields` helps). This is the same limit as a CE `delay` thunk that never returns.
- For CE: an endless loop inside `uncancelable` never observes cancel. This is intended (masking rule). It is not a liveness bug. The `cancel` call then never returns (backpressure).

## The toy (spikes/liveness/Liveness.lean)

- 2 fibers, one shared flag. Instructions: `work`, `cede`, `setFlag`, `spin` (busy wait on the flag), `mask`, `unmask`, `loop` (`IO.cede.foreverM`), `cancel j` (no backpressure wait).
- `Choice = {fiber : Fin 2, observe : Bool}`; `Schedule = Nat → Choice`. The step checks `canceled ∧ masks = 0 ∧ observe` first (mirrors `shouldFinalize()` before the instruction), then runs the instruction. Picking a finished or blocked fiber is a stutter.
- `FiberFair s := ∀ i n, ∃ m ≥ n, (s m).fiber = i`. `Fair s := ∀ i n, ∃ m ≥ n, s m = ⟨i, true⟩` (implies `FiberFair`). `BoundedFair B s` (window of `B`) implies `Fair`.
- `Terminates st := ∀ s, Fair s → ∃ n, (exec s st n).done`. `TerminatesAlways` drops `Fair`.

## Proven (no sorry; axioms only propext, Quot.sound; file checks in about 1 s)

1. `simple_terminates`: any 2 fibers without `loop`/`spin` (any masks and cancel flags) finish under every `FiberFair` schedule. `twoFinite_terminates` is an instance.
2. `spinWait_terminates` and `spinWait_not_terminatesAlways`: the busy-wait program terminates under `Fair`; the unfair schedule `fun _ => ⟨0, true⟩` keeps it in the start state forever (`alwaysZero_spinWait_stuck`, `alwaysZero_not_fiberFair`).
3. `cancelLoop_observes_cancel`, `cancelLoop_terminates`: a fiber in `IO.cede.foreverM`, cancelled by the other fiber, ends as `canceled` under `Fair`. `cancelLoop_fiberFair_not_enough`: under `FiberFair` alone (never observe) it runs forever. `maskedLoop_never_finishes`: a fiber already inside `uncancelable` never finishes under any schedule.
4. `lasso_not_terminates`: a prefix plus a cycle that returns to the same state, covers every fiber with `observe = true`, and is not done, refutes `Terminates`. The side conditions of a concrete lasso are closed and checked by `decide` (`maskedLoop_not_terminates_lasso`: prefix 4, cycle 2).

## Proof techniques: what worked, what hurt

- **Per-fiber ranking function** (remaining instructions + 1, 0 when finished) + **induction on the rank**; fairness gives the next index `m ≥ n` where the fiber steps. A global rank (sum) was harder: other fibers' steps must be shown non-increasing for every fiber separately anyway.
- Frame lemmas are the bulk of the work: a step of fiber `j` does not change code, masks or outcome of fiber `i ≠ j`; outcome is stable; the flag only grows.
- **Finite reachable set + `decide`**: list the reachable states, prove closure under all 4 choices by `decide`, then induction on `n`. Very cheap (3–7 states, instant). It also caught a wrong claim: a fiber with code `[mask, loop]` *can* be cancelled before it enters the mask. This matches CE (cancel before `uncancelable` starts wins).
- Lasso certificates are a good shape for liveness refutations: finite, `decide`-checkable, and the infinite fair schedule is built by a generic lemma.
- Gotchas: a `let` at the start of a `def` blocks `split` after `unfold`; put the body in a helper with the fiber as an explicit argument. `simp [hn]` rewrites `fb.outcome` to `none` inside structure literals, and later `rw` with a lemma stated on `{fb with ...}` fails; state the helper instance with `outcome := none`. Without Mathlib, `Fin 2` case splits need a small `fin2_cases` lemma.
- Effort: about 650 lines, about 1 hour including fixes. Pain is medium for a 2-fiber toy. With a real `IOFiber` state, the frame lemmas grow with the number of fields; plan generic `get`/`set` lemmas for the fiber map first.

## Bounded preemption (dejafu view) for finite checking

- Finite schedules with at most `P` preemptions (switching away from a fiber that is still runnable) are good for safety bug search and for small outcome sets. They cannot prove liveness. They can find lasso candidates: a repeated state on a path whose cycle covers every fiber.

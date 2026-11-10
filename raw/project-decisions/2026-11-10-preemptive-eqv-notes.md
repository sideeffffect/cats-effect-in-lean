# Preemptive `EqvP`, CE-0002 re-proof and fixed-twin check (decisions 29, 36, 39)

> Source: own Lean work in this repository (`CatsEffectInLean/Model/SchedP.lean`, `Model/Outcomes.lean`, `Model/EnumP.lean`, `Model/EnumPExamples.lean`, `Model/ResourceFixed.lean`, `Proofs/Calibration/ResourceEval*.lean`, `Props/IO/MonadCancelLaws.lean`, `Proofs/IO/MonadCancelLaws.lean`), Lean v4.35.0; Cats Effect v3.7.1 `IOFiber.scala:211-240`; `series/3.7.x` commit `2f94201` `Resource.scala:464-530` (fix PR #4630); replay difftest runs
> Collected: 2026-11-10
> Published: 2026-11-10

Review batch 2 found CE-0002 HOLLOW: the outer `IO.uncancelable` of the right side adds one run-loop iteration, and the replay `Eqv` sees iteration counts through the auto-yield position (every 1024 iterations). So `¬P` was true for every implementation. Decision 36 (= 29): add a preemption choice at any run-loop iteration.

## Preemptive scheduler

- New choice type `PChoice`: `pick n` and `preempt`. One choice per micro-step (one run-loop iteration, or one task start). Default after the list: `pick 0`.
- `preempt` while a task runs: the same effect as the auto-yield of `IOFiber.scala:233-238` at this point: `resumeTag = AutoCedeR`, `resumeIO = _cur0`, enqueue the fiber, end the task. A pending outside cancel becomes visible (`Loop.flush`; a thread switch is a barrier). At `EndFiber` and between tasks: no effect. Reason for `EndFiber`: the fiber may be suspended on an async callback; to enqueue it there would run it twice.
- `pick n` calls the unchanged `Sched.tick` with replay choice `pick (n mod max 1 size)` and no task limit. Then `Sched.norm` resets the task count and the schedule log (not observed).
- `Sched.tick`, `runSchedState`, `Step.lean` did not change. The replay difftest never generates `preempt`. Replay difftest after the change: seeds 1 2 3, 2,000 cases each: 5,884 agree, 0 mismatch, 116 unsupported (`timeoutTo`).

## Why this matches the real runtime

- The default JVM `IORuntime` runs fibers on a work-stealing pool with many worker threads. Two fibers run in parallel, so the steps of one fiber can come between any two run-loop iterations of the other.
- The auto-yield (`IOFiber.scala:224-240`) is a fairness device. Its position is a runtime setting (`autoYieldThreshold`, default 1024; `cancelationCheckThreshold` 512). It is not a Cats Effect promise (decision 29).
- `TestControl` and our replay `ExecutionContext` run one thread: other fibers run only at task boundaries (`wiki/cats-effect/testcontrol.md`: "Mid-task preemption and mid-task cancel observation exist only on the multi-thread runtime"). So the replay scheduler is a sub-model. `EqvP` adds the interleavings of the multi-thread runtime at run-loop-iteration granularity.
- A preempted fiber resumes with fresh counters (`autoCedeR` → `runLoop(io, cancelationCheckThreshold, autoYieldThreshold)`, `IOFiber.scala:1457-1461`). This moves later auto-yields. That only removes forced task boundaries; every schedule that the forced boundary allows is still possible with an explicit `preempt`.

## Exact outcome sets

- Without task count and log, a terminating program has a finite state space under the preemptive scheduler, also with unbounded fuel and lists.
- `exploreP`: breadth-first search from `Sched.init`, with the choice list of each state. `ClosedP`: each successor (`preempt`, `pick i` for each ready task) is in the list. `runSchedStateP_mem`: then every run stays in the list. `pathsOK`: each result state is the result of its recorded list. So `outcomesP` is exactly the observations of the list (`outcomesP_iff_of_exactP`), and `checkEqvP` / `checkNotEqvP` decide `EqvP` with `decide +kernel`.
- Cost: kernel memory. One `decide` over 9 programs x 2 sides (up to 322 states each) ran out of memory at `-M 8000`. Fixes: a cheap key (`Sched.key`: counters, list lengths, per-fiber tags) compared before the full `DecidableEq` (`Sched.fastEq`), and one declaration per check. Largest single side: about 30 s.
- For free variables (the IO law proofs) `decide` does not work. `runSchedStateP_family`: a family of states named by choice lists (`famSt`), with a successor table from `exploreTable` (`#eval` on a closed instance), checked by `rfl` per state. With one fiber, `pick m` acts as `pick 0` (`tickP_pick_single`; prove `ready.length ≤ 1` with `Nat.le_of_ble_eq_true rfl`, not `decide`, because `decide` rejects free variables).

## CE-0002

- Statement: same promise and hypotheses; `<->` is now `EqvP`.
- Witness `g = IO.canceled` (case C). Exact sets: left `{Canceled}` (26 states), right `{Succeeded((), _ => F.unit)}` (34 states).
- Fixed twin (decision 39): `Model/ResourceFixed.lean` mirrors `allocatedCase` of PR #4630 (`series/3.7.x` `2f94201`, `Resource.scala:464-530`): one `F uncancelable { poll => ... }` around the loop; `Allocate` → `resource(poll) flatMap`; `Frame` → `(poll(F.unit) >> continue(head(b), tail, rel2)).onCancel(...).onError(...)` (`>>` is by name); `Eval` → `poll(fa).flatMap(...)`. New closure type `FClo` (tags 20-23). The body names `this : Res` by an index into `FEnv.res`, because a `Val` cannot hold a `Res`.
- Domain: 9 programs `g`: `canceled`, `emit 1`, `raiseError`, `canceled >> emit 1`, `start(emit 9) >> emit 1`, `start(emit 9).flatMap(_.cancel)`, `start(emit 9).flatMap(_.join)`, `start(emit 9) >> canceled`, `start(emit 9) >> emit 1 >> emit 2`. All schedules with preemption, all fuel (exact sets, 34 to 322 states).
- Result: the fixed twin satisfies the equation for all 9. v3.7.1 fails it for exactly the 3 programs with a self-cancel and satisfies it for the other 6. So the statement is no longer true for every implementation.

## IO laws

- All 4 IO law props now use `EqvP` (`IOEqv`).
- `canceledAssociatesLeftOverFlatMap` and `forceRCanceledShortCircuits`: re-proven under `EqvP` with state families (13, 8 and 19 states). The old `Eqv` proofs stay as lemmas `*_eqv`.
- `uncancelablePollIsIdentity`, `fa n = start(emit 9) >> emit 1 >> n flatMaps >> emit 2`:
  - Default thresholds: the replay enumeration (picks 3, depth 3, fuel 1300) differs only at `n = 509` with this construction (the earlier notes said 508 with a different `flatMap` nesting). The left side alone has trace `[1, 9, 2]`. With one `preempt` after micro-step 514 (and many other points), the right side gives the same observation.
  - Small thresholds (2/4): the replay enumeration differs for `n = 0, 1, 3, 4, ...`; the exact `EqvP` sets are equal for `n = 0..9` (`#eval`), kernel-checked for `n = 0..3`.
  - So the difference disappears with preemption. The law stays `open`: a proof for all `fa` needs a simulation between the two runs (the left side has an extra `Uncancelable`/`UnmaskRunLoop` pair and two extra iterations); this is not done.
- `onCancelAssociatesOverUncancelableBoundary`: restated with `EqvP`, still `open`.

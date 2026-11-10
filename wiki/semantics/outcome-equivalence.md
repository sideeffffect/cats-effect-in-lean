# Outcome sets, `Eqv`/`EqvP`, the enumerators and the IO laws

> Sources: own Phase 2 step 10 and Phase 4 work (`CatsEffectInLean/Model/Outcomes.lean`, `SchedP.lean`, `Enum.lean`, `EnumP.lean`, `IOInstance.lean`, `EnumExamples.lean`, `EnumPExamples.lean`, `Props/IO/MonadCancelLaws.lean`, `Proofs/IO/MonadCancelLaws.lean`), Lean v4.35.0, 2026-11-10; Cats Effect v3.7.1 (`IO.scala`, `MonadCancelLaws.scala`, `MonadCancelTests.scala`, `testkit/.../TestInstances.scala`); scala-cli smoke test on CE 3.7.1 with `TestControl`
> Raw: [Review 2 fixes notes](../../raw/cats-effect/2026-11-10-review2-ce0001-ce0004-notes.md); [Enumerator and first laws notes](../../raw/lean-tooling/2026-11-10-enumerator-and-first-laws-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md); [Preemptive EqvP notes](../../raw/project-decisions/2026-11-10-preemptive-eqv-notes.md)

## Overview

This article defines what `lhs <-> rhs` means for `IO` in the model, how to compute outcome sets, and which `IO` laws are settled.
The registered `<->` is `EqvP` (decisions 29, 36): all schedules with a preemption at any run-loop iteration. The replay `Eqv` stays as a sub-model.
Two `MonadCancel` laws for `IO` are proven (under `EqvP`). Two are `open`. None is refuted. All four have the hypothesis `WellFormedIO` on both sides. Open entries do not make their inventory rows `modelled` (decision 28).

## Observation and `Eqv`

```lean
structure Obs where
  summary : Summary      -- root outcome, or blocked / fatal / uncaught / aborted
  out : List Val         -- user emit trace (finalizer order, effects), newest first
  refs : List Val        -- final Ref cells
  reports : List Err     -- errors reported to the ExecutionContext

def outcomes cfg mm env (io : IO) (o : Obs) : Prop :=
  ∃ fuel cs, (∀ c ∈ cs, c.isPick = true) ∧ runObs cfg mm env fuel cs io = some o
def Eqv cfg mm env (p q : IO) : Prop := ∀ o, outcomes cfg mm env p o ↔ outcomes cfg mm env q o
```

- Unbounded: all fuel values, all choice lists. `outOfFuel` and `taskLimit` give no observation.
- Observed: the outcome, the emit trace, the final `Ref` cells, the reported errors. So finalizer runs and their order count.
- Not observed: fiber ids, `ContState` ids, handles, task counts, outcome callbacks. They are internal names.
- `Eqv` uses pick choices only: no cancel from the test harness. Reasons: (1) CE checks a law with `eqIOA`, which runs each side alone (`TestInstances.scala:160-161`, `199-219`); (2) an outside cancel lands at a task boundary, and the auto-yield (every 1024 iterations) makes the iteration count observable. Self-cancel and cancel between fibers of the program stay in.
- `outcomesExt`/`EqvExt` also allow `RChoice.cancel`. Not used by registered laws yet.
- The IO laws use `cfg := {}` (512/1024 thresholds) and `counterMaskModel` (the `IOFiber` mirror).
- Problem of `Eqv`: it sees run-loop iteration counts through the auto-yield position (section "Finding" below). So the registered properties use `EqvP`.

## `EqvP`: preemption at any run-loop iteration (decisions 29, 36)

```lean
inductive PChoice | pick (n : Nat) | preempt
def outcomesP cfg mm env (io : IO) (o : Obs) : Prop :=
  ∃ fuel (cs : List PChoice), runObsP cfg mm env fuel cs io = some o
def EqvP cfg mm env (p q : IO) : Prop := ∀ o, outcomesP cfg mm env p o ↔ outcomesP cfg mm env q o
```

- Scheduler: `CatsEffectInLean/Model/SchedP.lean`. One choice per micro-step; `pick 0` after the list.
- `preempt` while a task runs ends the task between two iterations and enqueues the fiber: the same effect as an auto-yield at that point (`IOFiber.scala:233-238`: `resumeTag = AutoCedeR; resumeIO = _cur0; rescheduleFiber`). No effect at `EndFiber` (the fiber may be suspended on a callback) and between tasks.
- `pick n` = `Sched.tick` with replay choice `pick (n mod max 1 size)`, no task limit, and `Sched.norm` (task count and schedule log reset; `Obs` does not see them).
- `Sched.tick`, `runSchedState`, `Step.lean` are unchanged. The replay difftest never generates `preempt`; it gives the same results as before (seeds 1-3 x 2,000: 5,884 agree, 0 mismatch, 116 unsupported).
- Why this is the real runtime: the default JVM `IORuntime` runs fibers on a work-stealing pool with many worker threads, in parallel. So another fiber's steps can come between any two run-loop iterations. The auto-yield (`IOFiber.scala:224-240`, every `autoYieldThreshold` = 1024 iterations) is a fairness device; its position is a runtime setting, not a promise (decision 29). `TestControl` and the replay EC run one thread; there other fibers run only at task boundaries ([TestControl](../cats-effect/testcontrol.md)). So the replay scheduler is a sub-model of `EqvP`.
- A preempted fiber resumes with fresh counters (`autoCedeR`, `IOFiber.scala:1457-1461`). This moves later auto-yields. That only removes forced boundaries; an explicit `preempt` can put each one back.
- Same `Obs`, same root-completion cut (decision 33), no outside cancel (decision 22).

## Exact outcome sets (`EnumP.lean`)

Without task count and log, a terminating program has a finite state space under `EqvP`, also with unbounded fuel and lists. So the outcome set can be computed exactly, not only bounded.

- `exploreP`: breadth-first search from `Sched.init`; it records the choice list of each state.
- `ClosedP S`: each successor of each state that can go on (`preempt`, `pick i` for each ready task, `succsP`) is in `S`. `runSchedStateP_mem`: every run from a state of a closed `S` stays in `S`.
- `pathsOK`: each result state is the result of its recorded list.
- `outcomesP_iff_of_exactP`: closed + start state + paths ⇒ `outcomesP io o ↔ o ∈ obsList L`. `checkEqvP`/`checkNotEqvP` then decide `EqvP` by `decide +kernel`. If the search bound is too small, the check is `false`, never a wrong `true`.
- Free variables (`decide` rejects them): `runSchedStateP_family` with a family of states named by choice lists (`famSt`) and a successor table from `exploreTable` (`#eval` on a closed instance). Each step is `rfl`. With one fiber, `pick m` acts as `pick 0` (`tickP_pick_single`; prove `ready.length ≤ 1` by `Nat.le_of_ble_eq_true rfl`).
- Cost: kernel memory. 9 programs x 2 sides (up to 322 states) in one `decide` exceed 8 GB. `Sched.fastEq` (a cheap `Sched.key` before the full comparison) and one declaration per check fix it; largest side about 30 s.

## `WellFormed`: the domain of all properties (decision 27)

`CatsEffectInLean/Model/WellFormed.lean`. A type invariant on a start program `p` and user code `env`: they are a program that Scala can write. Every registered property that quantifies over programs or user code has it as a hypothesis. Each refutation proves that its witness is well-formed.

- A `Handle` (fiber, `Ref`, `Deferred`, poll, `ContState`) is a capability. Scala code gets one only as a value.
- A user call holds the handles of its argument, of its closure value (`captured id`, from the closure codec), of the program scope `H0`, and what it reaches through held cells (`Reach`).
- `progOK` (decidable): no forged fiber, poll or `ContState` id; no `EndFiber`; user ids even; odd ids only for library closures (`lib id`) with held captures; `Fn.rt` only for public operations (`cancel`, `join`, `Deferred` get/complete, `void`). `UnmaskRunLoop(p, m, s)` only with `m ≠ 0` (decision 37): user code makes it only by applying a real poll (`IO.applyPoll`); `IdPoll` (`m = 0`) is the identity.
- `CallOK` (for each even id, argument and heap view): the result depends only on held cells (and on the cell counts); effects and output use held handles; new cells are held.
- `PollOpaque env` (clause 6, decision 37): poll values are opaque to user code. For every renaming `σ` of poll handles that keeps mask id 0, a call on renamed inputs (closure id with its captured values, argument, view) gives the renamed result (`rnId`, `rnVal`, `rnView`, `rnResult`; `rnIO` maps `UnmaskRunLoop(p, m, s)` to `IO.applyPoll (rnIO p) (σ m s)`). So user code cannot branch on a mask id or tell `IdPoll` from the run loop's poll. Scala: `Poll` is a trait with only `apply`; the two implementations are anonymous private classes; only reflection or `Object` methods could tell them apart. Helper for constant user code: `WF.pollOpaque_of_const`.
- `WellFormed lib H0 env p := progOK lib (H0.contains ·) p ∧ (∀ even id, ∀ arg v, CallOK lib H0 env id arg v) ∧ PollOpaque env`. `WellFormedIO env p` is the plain-`IO` case (`lib = false`, `H0 = []`).
- Clause 6 broke the CE-0002 witness proof (`ResourceEval.lean`, `r_wellFormed` needs the third conjunct); a tested patch is in the [review 2 notes](../../raw/cats-effect/2026-11-10-review2-ce0001-ce0004-notes.md).
- The start-program part is `decide +kernel`. The user-code part is a `∀`, so a witness needs a short proof.
- Gotcha: a small id can decode to a closure value with a handle (id `218` decodes to `fiber 0`). Build test ids with `Codec.userFn (cloVal ...)`.
- The two proven laws do not use the hypothesis. Their twins `*_all` state them without it.

## Bounded enumerator

- `choiceLists alpha d`: all choice lists of length ≤ `d` over `alpha`. `enumObs`/`enumResults` run each one. A list is used only at task boundaries; after its end the scheduler picks index 0.
- Lemmas: `enumObs_sound` (each result comes from a list in the bound), `enumObs_complete` (each list in the bound gives a listed result), `enumResults_outcomes` (pick-only alphabet: each listed observation is in `outcomes`). The bounded set is a lower bound of `outcomes`, not the full set.
- `enumAgree p q`: a smoke test of `Eqv` in the bound.
- Cost (two fibers, `picks 3`, ~40 steps per run): `decide +kernel` 45 ms per run (depth 5 = 364 runs in 16 s); `decide_cbv` about ×2 per depth (depth 6 in 14 s / 2 GB; depth 7 times out). A state-level DFS that shares prefixes is not built yet.

## IO operations (`IOI`)

- `F[A]` ↦ `Model.IO`; `A` is erased (untyped `Val`). `E` ↦ `Err`.
- Each `IOAsync` method is its `IO.scala` body: `flatMap` = `FlatMap` node (`IO:469`), `void` = `map(_ => ())` (`IO:961`), `forceR` = `handleError(_ => ()).productR(that)` (`IO:452-454`), `uncancelable` = `Uncancelable` node (`IO:1712`), and so on.
- A Scala lambda is a `Fn.user id`. The law takes a hypothesis `IOI.Lam.*` that `env` runs `id` as that lambda (`constProg`, `constVal`, `pollApply`). `env` is free on all other ids.
- A typed instance of `Kernel.MonadCancelOps` is not possible: `pure : {A : Type} → A → F A` needs an injection of every Lean type into `Val`; a typed embedding lives in `Type 1`; closures need ids that encode run-time values. So each IO law is its own `Prop` with the same calls as the generic law.

## Law status (IO, `MonadCancel`, `<->` = `EqvP`)

| Law | Status | Why |
|---|---|---|
| `canceledAssociatesLeftOverFlatMap` | proven | `fa` never runs; both sides: `Canceled`, empty trace. Proof: state families (13 and 8 states) with `rfl` per step. The old `Eqv` proof stays as `_eqv`. |
| `forceRCanceledShortCircuits` | proven | Same shape (19 states); `forceR` = `handleError(_ => ()).productR`. |
| `onCancelAssociatesOverUncancelableBoundary` | open | Believed true. The NB comment is about the monad laws, not this law. Needs a simulation proof. |
| `uncancelablePollIsIdentity` | open | The iteration-count difference is gone under `EqvP` (smoke tests below). A proof for all `fa` needs a simulation; not done. |
| other 13 laws | not stated for IO | |

Wrong-function test: `canceled := unit` breaks the first law (`EnumExamples.canceledLeft_wrongFunction_differs`); `forceR a b := b` breaks the second.

## Finding: auto-yield makes iteration counts observable

`uncancelable(poll => poll(fa))` runs two more iterations than `fa`. With `fa = emit 1 >> 509 flatMaps >> emit 2` and a cancel at the first auto-yield, the left side can end `Canceled` with trace `[1]`; the right side cannot. The model finds this at exactly `n = 509`. Real CE 3.7.1 under `TestControl` (20 seeds) shows the same, at the same `n`.
In `Eqv` that canceller was a child that names fiber 0, a forged id. `WellFormedIO` now excludes it.
The effect stays without forged ids (re-run 2026-11-10): with `fa = start(emit 9) >> emit 1 >> n flatMaps >> emit 2` (picks 3, depth 3, fuel 1300), the sets differ only at `n = 508`. The left side also has the trace `[1, 9, 2]`: its auto-yield comes before `emit 2`, so the child runs. The run stops when the root completes, so the right side never shows `9`.
Decision 29/36 (done): `EqvP`. Smoke tests (`Model/EnumPExamples.lean`), with `fa n = start(emit 9) >> emit 1 >> n flatMaps >> emit 2` built as left-nested `flatMap`s:
- Default thresholds: the replay enumeration (picks 3, depth 3, fuel 1300) differs only at `n = 509` (508 in the older construction). The left side alone has `[1, 9, 2]`. With one `preempt` after micro-step 514, the right side gives the same observation (`default_rhs_preempt`).
- Thresholds 2/4: the replay enumeration differs for most `n` (`replay_differs_0`, `_1`); the exact `EqvP` sets agree for `n = 0..9` (`#eval`), kernel-checked for `n = 0..3` (`eqvP_0` .. `eqvP_3`).

## See Also

- [Kernel typeclasses model](../cats-effect/kernel-typeclasses-model.md)
- [Scheduler model](../cats-effect/scheduler-model.md)
- [TestControl and schedule replay](../cats-effect/testcontrol.md)
- [Resource model and CE-0002](../cats-effect/resource-model.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Fairness and liveness](fairness-and-liveness.md)
- [Semantics of CE3](../cats-effect/semantics.md)
- [Registry and audit](../methodology/registry-and-audit.md)

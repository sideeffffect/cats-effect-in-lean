# Outcome sets, `Eqv`, the bounded enumerator and the IO laws

> Sources: own Phase 2 step 10 and Phase 4 work (`CatsEffectInLean/Model/Outcomes.lean`, `Enum.lean`, `IOInstance.lean`, `EnumExamples.lean`, `Props/IO/MonadCancelLaws.lean`, `Proofs/IO/MonadCancelLaws.lean`), Lean v4.35.0, 2026-11-10; Cats Effect v3.7.1 (`IO.scala`, `MonadCancelLaws.scala`, `MonadCancelTests.scala`, `testkit/.../TestInstances.scala`); scala-cli smoke test on CE 3.7.1 with `TestControl`
> Raw: [Enumerator and first laws notes](../../raw/lean-tooling/2026-11-10-enumerator-and-first-laws-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md)

## Overview

This article defines what `lhs <-> rhs` means for `IO` in the model, how to enumerate outcomes in a bound, and which `IO` laws are settled.
Two `MonadCancel` laws for `IO` are proven. Two are `open`. None is refuted. All four have the hypothesis `WellFormedIO` on both sides. Open entries do not make their inventory rows `modelled` (decision 28).

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

## `WellFormed`: the domain of all properties (decision 27)

`CatsEffectInLean/Model/WellFormed.lean`. A type invariant on a start program `p` and user code `env`: they are a program that Scala can write. Every registered property that quantifies over programs or user code has it as a hypothesis. Each refutation proves that its witness is well-formed.

- A `Handle` (fiber, `Ref`, `Deferred`, poll, `ContState`) is a capability. Scala code gets one only as a value.
- A user call holds the handles of its argument, of its closure value (`captured id`, from the closure codec), of the program scope `H0`, and what it reaches through held cells (`Reach`).
- `progOK` (decidable): no forged fiber, poll or `ContState` id; no `EndFiber`; user ids even; odd ids only for library closures (`lib id`) with held captures; `Fn.rt` only for public operations (`cancel`, `join`, `Deferred` get/complete, `void`).
- `CallOK` (for each even id, argument and heap view): the result depends only on held cells (and on the cell counts); effects and output use held handles; new cells are held.
- `WellFormed lib H0 env p := progOK lib (H0.contains ·) p ∧ ∀ even id, ∀ arg v, CallOK lib H0 env id arg v`. `WellFormedIO env p` is the plain-`IO` case (`lib = false`, `H0 = []`).
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

## Law status (IO, `MonadCancel`)

| Law | Status | Why |
|---|---|---|
| `canceledAssociatesLeftOverFlatMap` | proven | `fa` never runs; both sides: `Canceled`, empty trace. Proof by `rfl` on each run. |
| `forceRCanceledShortCircuits` | proven | Same shape; `forceR` = `handleError(_ => ()).productR`. |
| `onCancelAssociatesOverUncancelableBoundary` | open | Believed true. The NB comment is about the monad laws, not this law. Needs a simulation proof. |
| `uncancelablePollIsIdentity` | open | Bounded difference in the model also for well-formed programs (see below). Cause: `Eqv` sees iteration counts. Not a CE bug. |
| other 13 laws | not stated for IO | |

Wrong-function test: `canceled := unit` breaks the first law (`EnumExamples.canceledLeft_wrongFunction_differs`); `forceR a b := b` breaks the second.

## Finding: auto-yield makes iteration counts observable

`uncancelable(poll => poll(fa))` runs two more iterations than `fa`. With `fa = emit 1 >> 509 flatMaps >> emit 2` and a cancel at the first auto-yield, the left side can end `Canceled` with trace `[1]`; the right side cannot. The model finds this at exactly `n = 509`. Real CE 3.7.1 under `TestControl` (20 seeds) shows the same, at the same `n`.
In `Eqv` that canceller was a child that names fiber 0, a forged id. `WellFormedIO` now excludes it.
The effect stays without forged ids (re-run 2026-11-10): with `fa = start(emit 9) >> emit 1 >> n flatMaps >> emit 2` (picks 3, depth 3, fuel 1300), the sets differ only at `n = 508`. The left side also has the trace `[1, 9, 2]`: its auto-yield comes before `emit 2`, so the child runs. The run stops when the root completes, so the right side never shows `9`.
Decision 29: add a preemption choice at any run-loop iteration to `Eqv` (the real runtime runs fibers in parallel). Not done yet; until then the entry stays `open`.

## See Also

- [Kernel typeclasses model](../cats-effect/kernel-typeclasses-model.md)
- [Scheduler model](../cats-effect/scheduler-model.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Fairness and liveness](fairness-and-liveness.md)
- [Semantics of CE3](../cats-effect/semantics.md)
- [Registry and audit](../methodology/registry-and-audit.md)

# Race no-leak invariant and frame lemmas

> Sources: own Phase 6 track P work, 2026-11-10 (`CatsEffectInLean/Proofs/Lemmas/Frame.lean`; reads of `Model/Step.lean`, `Model/Sched.lean`, `Model/SchedP.lean`, `Model/Race.lean`, `Model/Leak.lean`, `Model/WellFormed.lean`); Lean v4.35.0
> Raw: [Race invariant track P notes](../../raw/cats-effect/2026-11-10-race-invariant-track-p-notes.md); [Certificate checker notes](../../raw/lean-tooling/2026-11-10-certificate-checker-track-p-notes.md)

## Overview

Of the five track R entries, the closed law `uncancelableRaceNotInherited` is proven (certificate check, [Certificate checks](../lean/certificate-checker.md)). The four leak/winner entries (no leak for `race`/`raceOutcome`/`both`/`bothOutcome`/`timeout`, winner outcome of `raceOutcome`) are still `open`.
A read of the mirror finds no counterexample. The statements are believed true.
This article states the invariant that a proof needs, what is proven, and the exact gap.

## Target invariant

`NL(r)`: every live race child of the racing fiber `r` (`raceChildOf`) exists only while `r` has no outcome. At root completion `r` has an outcome (direct form: `r = 0` is the root; parent form: the parent joined `r = 1`), so `liveRaceChildren s r = []`.

NL is not inductive alone. It rests on these parts. Each must hold after every `tickP` micro-step of every fiber.

| Part | Content | Status |
|---|---|---|
| F1 | `ContState` table only grows; the owner fiber of a cell never changes | proven |
| F1b | a cell with `.result v` keeps it ("first result wins") | proven (`result_stable`) |
| F2 | fiber table only grows; `Heap.handles` never goes down | proven |
| S | runtime grammar: every term in a fiber state is user-grade (`WF.progOK`) or an internal runtime chain of that fiber | open |
| F3 | slot-0 callbacks only from `Fiber.new`, removed only by `done` | open (needs S, F2) |
| F4 | outcomes are stable; a done fiber has `doneR`, `suspended = false` | open (needs P1) |
| P1, P2 | cancel-takeover and join protocols | open (needs S) |
| H | user code never reaches `.cont s` of a cell of `r` (nor `.fiber 0` in the direct form) | open (needs S, F1, `WellFormed` clauses 4–5) |
| C(r) | phase table of `r`'s control per combinator kind, `timeout`, parent form | open (needs all above) |

Facts about `racePair` that C(r) uses: the register step makes the children with callbacks `raceLeft s B` / `raceRight s A` on `r`'s own cell `s`; only `r`'s `contGet`/`contGetFin` and the children's `done` write `s` (H excludes user callbacks); the first result wins (`contCallback` on `.result _` is a no-op); the `racePair` finalizer joins one canceller per child; `cancel` returns only after the target is done.

## Proven: frame lemmas (`Proofs/Lemmas/Frame.lean`)

- `Frame x y` for one `Exec` transition: owner list is a prefix, fiber count and handle counter do not go down, results stay (`Sticky`).
- One lemma per function of the run loop: `contCallback`, `rtCall` (33 runtime closures), `applyEffects`, `callUser`, `tryUser`, `tryUser2`, `done`, `prepareFiberForCancelation`, `cancelationLoopSuccessK`, `succeeded`/`failed` (`frame_unwind`), `contGet`, `dispatch` (all tags), `step`, `resume`.
- Scheduler: `SFrame` on the live heap and live fiber table; `sframe_tickP`, `sframe_runSchedStateP`, `owner_stable` (the owner of a cell is the same in every later state), `result_stable` (a result stays).
- No hypothesis: holds for all user code, all `Config`, all mask models, all schedules. Axioms `propext`, `Quot.sound`. Build about 11 s, peak RSS about 0.84 GB.

## The closed law

- Proven (`Proofs/Phase6/RaceLaw.lean`): left side `uncancelable(_ => race(never, canceled)).void` has exactly 4,441 states (closed), right side 45; both outcome sets are `{blocked, empty trace, no refs, no reports}`. Kernel check of an untrusted certificate in 49 chunks ([Certificate checks](../lean/certificate-checker.md)).

## Next steps (in order)

1. S, by the same per-function scheme as `Frame.lean`.
2. F3, F4 with P1/P2.
3. H from S, F1 and `CallOK`.
4. C(r) phase tables; one lemma per (phase, step of `r`), frame lemmas for other fibers.
5. Derive the four leak/winner entries.

## See Also

- [race, both and fiber leaks](../cats-effect/race-both-model.md)
- [Outcome sets, Eqv and the IO laws](outcome-equivalence.md)
- [Fairness and liveness](fairness-and-liveness.md)
- [Run-loop model](../cats-effect/runloop-model.md)
- [Scheduler model](../cats-effect/scheduler-model.md)
- [Lean v4.35.0 toolchain](../lean/toolchain-v4-35.md)
- [Certificate checks of closed state sets](../lean/certificate-checker.md)

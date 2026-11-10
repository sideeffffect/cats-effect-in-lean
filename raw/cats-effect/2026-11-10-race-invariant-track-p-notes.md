# Race no-leak invariant: design, proven frame lemmas, remaining gap (own note, Phase 6 track P)

> Source: own work in this repository (`CatsEffectInLean/Proofs/Lemmas/Frame.lean`; reads of `Model/Step.lean`, `Model/Sched.lean`, `Model/SchedP.lean`, `Model/Race.lean`, `Model/Leak.lean`, `Model/WellFormed.lean`, `Props/Phase6/Race.lean`), Lean v4.35.0; compiled `#eval` of `exploreP` in a scratch file (not committed)
> Collected: 2026-11-10
> Published: 2026-11-10

## Task

Settle the five `open` entries of track R: `core.IO.race.combNoLeak`, `core.IO.race.combCanceledNoLeak`, `core.IO.timeout.noLeak`, `core.IO.raceOutcome.isWinnerOutcome`, `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO`.
Result: none settled. Facts F1 and F2 below are proven for all runs. All five entries stay `open`.

## Is a statement false? (checked first)

No. A read of the mirror finds no path where the racing fiber `r` gets an outcome while a `racePair` child lives:

- `r` gets past `poll(get)` only after a race callback wrote the `ContState` `s` (child done), or through cancelation, which runs the `racePair` finalizer. The finalizer starts one canceller per child and joins both cancellers. `cancel` is backpressured: the canceller ends only after the target is done (`rtCall .cancel`: takeover + `cancelerCb` in the target's `done` step, or `join.void`).
- After the winner callback, every kernel default runs `f.cancel` (and `both`/`bothOutcome` join `f`) before `r` ends. All of this is inside the outer `uncancelable`; `poll(canceled)` runs only after `f.cancel` returned.
- Direct form: nobody holds the fiber handle of fiber 0, so `r = 0` is never canceled from outside.
- Parent form: fiber 1 is canceled at any point. Before the `racePair` register step it has no children. Between register and `poll(get)` it is masked (masks 2 → 1 → 0 only at `UnmaskRunLoop`), and the finalizer is pushed (`OnCancel`) before the unmask.

So the statements are believed true. No bug candidate. No statement bug found.

## Invariant design

Notation: `r` = racing fiber (0 direct, 1 parent form), `s` = its `racePair` `ContState`, `A`, `B` = children (ids `fibers.length` and `+1` at register time).

The no-leak statement at root completion follows from the stronger state invariant

> **NL(r)**: every live race child of `r` (`raceChildOf`) exists only while `r` has no outcome.

NL is not inductive alone. It needs these parts, each preserved by every micro-step (`pick` = `Sched.tick`, `preempt` = `Sched.preemptRun`) of every fiber:

| Part | Statement | Needs | Status |
|---|---|---|---|
| F1 | `ContState` table only grows; `ContState.fiber` of a cell never changes | — | **proven** (`owner_stable`) |
| F2 | fiber table only grows; `Heap.handles` never goes down | — | **proven** (`sframe_runSchedStateP`) |
| S | runtime grammar: each `IO`/`Fn` in a fiber state (`Loop.cur`, `resumeIO`, `finalizers`, `objectState` fns, `cancelCb`) is user-grade (`WF.progOK` with the library closures) or one of the internal runtime shapes in its own fiber (the `racePair*`, `cancelAsync*`, `join*`, `deferred*`, `sleep*`, `contGetFin`, `monitorDeregister` chains, each with the `ContState` that this fiber made) | `WellFormed` clauses 1–3, `Race.call`/`Timeout.call`/`PLam.call` outputs | open |
| F3 | slot-0 callbacks are made only by `Fiber.new` (`racePairRegister`, root) and removed only by `done`; `joinClear h` has `h ≥ 1` | F2, S | open |
| F4 | outcome is stable; a fiber with an outcome has `resumeTag = doneR`, `suspended = false`, empty stacks | P1 | open |
| H | handle secrecy: `.cont s'` for a cell `s'` owned by `r`, and (direct form) `.fiber 0`, occur in no value that user code can reach (refs, deferreds, outcomes, user-fiber stacks and terms, closure captures) | F1, S, `WellFormed` clauses 4–5 (`CallOK`: `Reach`, `ResultOK`) | open |
| P1 | takeover protocol: if a fiber's control is at `ioCont(cancelAsync t)`, `uncancelable(cancelAsyncUnc t s)` or `flatMap(delay(cancelAsyncK t s), getK s)`, then `t` has no outcome, `suspended = false`, `t` is not ready and not running | S | open |
| P2 | join protocol: a `(h, .join s)` callback on fiber `t` has `s` owned by a fiber suspended in (or about to enter) `contGet s` under `joinSel` | S, F1 | open |
| C(r) | control invariant of `r`: a finite phase table per `Race.Kind` (and `timeoutIO`, and the parent form with its finalizer path), each phase a shape of `Loop.cur`/`resumeIO`, `conts`, `objectState`, `finalizers`, mask, and the value of `s`, with the facts on `A`/`B` that the phase needs | S, H, P1, P2, F1–F4 | open |

NL follows from C(r) + F4: in every phase in which `r` can call `done`, both children have outcomes; F4 keeps them.

### Facts about `racePair` and `ContState` that C(r) uses

1. `racePairRegister a b s` makes `A`, `B` with slot-0 callbacks `raceLeft s idB` / `raceRight s idA`; `s` is the cell that `r`'s own `ioCont` made in the same chain (`racePairBody` → `racePairUnc` → `flatMap(delay(racePairRegister), racePairSel)`; `FlatMap` over `Delay` runs register and select in one iteration).
2. Only three writers touch `s`: `r`'s `contGet s` (initial → waiting), `r`'s finalizer `contGetFin s` (waiting → initial), and `contCallback s` from the `done` of `A` or `B` (`runOutcomeCb`). H excludes user `invokeCb`/`deferCb` on `s` (`WellFormed` clause 5: a callback call needs a held `ContState`).
3. A callback on a cell with a result is a no-op (`contCallback`, `.result _`). So `s` holds the first child's result: `Left((ocA, B))` or `Right((A, ocB))`, with `oc = child.outcome.toVal` at that step (this is `raceOutcomeIsWinnerOutcome`; F4 keeps the outcome).
4. `racePairSel` builds the finalizer `start(cancelOf A) >>= racePairCancelB >>= racePairJoinA >>= racePairJoinB` with the outcomes read in that iteration; `cancelOf t (some _) = pure ()`.
5. The canceller fibers have no callbacks and no handle outside the finalizer (only `racePairJoinA/B` name them).
6. `poll` is the mask id of the inner `uncancelable`; `UnmaskRunLoop` unmasks only on `masks == id` (`counterMaskModel`).

### Where `WellFormed` enters

- Clause 1–3 (`progOK`): user programs contain no internal `Fn.rt` (`rtOK` allows only `cancel`, `join`, `deferred*`, `voidK`), no `contGet`/`unmaskRunLoop` without a held handle, no `EndFiber`. This gives S for user terms.
- Clause 4–5 (`CallOK`): effects `invokeCb`/`deferCb`/`writeRef` and output values use held handles only; held = `Reach` from argument, captures and `H0 = []`. With S this gives H by induction: a user fiber never receives `.cont s` for a cell of `r`.
- The parent closures (`PLam`, even ids) are also covered by the `∀ even id` part of `WellFormed`.

## Proven (Lean, `CatsEffectInLean/Proofs/Lemmas/Frame.lean`)

- `Frame x y` (one `Exec` transition): `owners` prefix, `fibers.length ≤`, `heap.handles ≤`.
- Per function: `frame_contCallback`, `frame_rtCall` (all 33 runtime closures), `frame_applyEffects`, `frame_callUser`, `frame_tryUser`, `frame_tryUser2`, `frame_done`, `frame_prepare`, `frame_cancelationLoopSuccessK`, `frame_unwind` (mutual `succeeded`/`failed`, induction on `conts`), `frame_contGet`, `frame_dispatch` (all `IO` tags), `frame_step`, `frame_resume`.
- Scheduler: `SFrame` on the live heap/fiber table; `sframe_runTask`, `sframe_tick`, `sframe_preemptRun`, `sframe_tickP`, `sframe_runSchedStateP`, `owner_stable`.
- Axioms: `propext`, `Quot.sound`. Build: about 11 s, peak RSS about 0.84 GB (`lake build --wfail`).

## Proof-engineering notes (Lean v4.35.0)

- `Frame.of_eq rfl rfl rfl` inside `.trans` fails when the middle state is not known yet (elaboration order). Use `refine Frame.trans ?_ (lemma ...)` and close the rest by fields.
- A macro `repeat (first ...) <;> closer` parses as `repeat ((first ...) <;> closer)`. Write `(repeat (first ...)) <;> closer`.
- `apply frame_fib_right` on `Frame x x` succeeds by structure eta and loops under `repeat`. Only peel a `{ y with fib := _ }` together with the lemma that produces `y`.
- `by` blocks inside a term under `first | exact ... | ...` do not make the alternative fail (error recovery logs the error). Use tactic-level `refine ... ?_ <;> simp <;> done`.
- `simp only [stepEx]` unfolds before `stepEx_freshLoop` can fire; run the two in separate passes.
- `SFrame s (x).runTask cfg ...` parses `cfg` as a further argument of `SFrame`; wrap the application in parentheses.

## The closed law (`uncancelableRaceNotInherited`)

- Compiled `exploreP` (bound 30,000, `lawEnv`, default `Config`, `counterMaskModel`): left side 4,441 states, closed, 11 states with `halt`; right side (`never`) 45 states. `exactP` is `true` on both. Both outcome sets are exactly `{blocked, out = [], refs = [], reports = []}`. This is compiled-code evidence (`#eval`), not a kernel proof. The earlier note saw 994 states after 800 expansions.
- The kernel cannot check this with `checkEqvP`: `exploreP` dedups with list membership (about 10^7 state comparisons). A proof needs either a certificate checker (state table + successor indices, one `decide` per chunk) or a quotient by the run-loop counters (`cancelIters`, `autoCedeIters`), with a lemma that the counters do not matter below the thresholds. Neither exists.

## Remaining gap (exact)

0. F1b (easy, unconditional): a cell with `.result v` keeps `.result v` (writers: `contCallback` writes only `initial`/`waiting` cells, `contGetFin` only `waiting`, `contGet` only `initial`). Extend `Frame` with this field; the call sites already have the `value` case in context. This is fact 3 ("first result wins").
1. S: define `RtGrammar` on `IO`/`Fn`/`ObjEntry`/`Fiber`/`Loop`, prove it for `Fiber.new` of user programs and preserved by `dispatch` (every tag), `succeeded`/`failed` (every `ContK`), `rtCall` (every `RtFn`), `contCallback`, `done`, `resume`, `preemptRun`. Same per-function scheme as `Frame.lean`.
2. F3 and F4 (with P1, P2) on top of S.
3. H on top of S + F1 and `WellFormed` (`CallOK` gives one call; H needs the reach set of every user fiber over time).
4. C(r): phase tables for the four kinds, `timeoutIO`, and the parent form; one lemma per (phase, step of `r`) by `decide`/`simp` on the concrete control, plus frame lemmas for the steps of other fibers (from S, H, P1, P2).
5. Derive `combNoLeak`, `combCanceledNoLeak`, `timeoutNoLeak` from NL, and `raceOutcomeIsWinnerOutcome` from fact 3 + F4.
6. Law: certificate checker or counter quotient (above).

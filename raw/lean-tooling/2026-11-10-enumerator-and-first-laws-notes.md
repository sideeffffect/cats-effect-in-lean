# Enumerator, outcome-set equivalence and first IO laws (own notes)

> Source: own work in this repository: `CatsEffectInLean/Model/Outcomes.lean`, `Enum.lean`, `IOInstance.lean`, `EnumExamples.lean`, `Props/IO/MonadCancelLaws.lean`, `Proofs/IO/MonadCancelLaws.lean`; Lean v4.35.0; Cats Effect 3.7.1 (scala-cli + `TestControl.executeEmbed`)
> Collected: 2026-11-10
> Published: 2026-11-10

## What was built

- `Obs` = summary + `Heap.out` + `Heap.refs` + reported errors. `Sched.obs` gives `none` for `outOfFuel`/`taskLimit`.
- `runObs cfg mm env fuel cs io` = `runSchedState` with task limit = fuel.
- `outcomes io o` = `∃ fuel cs, cs pick-only ∧ runObs fuel cs io = some o`. `Eqv p q` = `∀ o, outcomes p o ↔ outcomes q o`. `outcomesExt`/`EqvExt` allow `RChoice.cancel` too.
- `choiceLists alpha d` (all lists of length ≤ d), `enumObs`, `enumResults`, `enumMatches`, `enumAgree`. Lemmas: `mem_choiceLists`, `enumObs_sound`, `enumObs_complete`, `enumResults_sound`, `enumResults_complete`, `enumResults_outcomes` (pick-only alphabet → member of `outcomes`), `enumMatches_sound`.
- `IOI.*`: IO operations as model constructors with IO.scala line citations; `IOI.Lam.constProg`, `constVal`, `pollApply` = hypotheses that `env` runs an id as a given Scala lambda.

## Typed instance of `Kernel.MonadCancelOps` is not possible (confidence 0.9)

- `pure : {A : Type} → A → F A` with untyped `Val` needs an injection `A → Val` for every Lean type. `Val` is countable, so no injection exists for `Nat → Nat`.
- A typed HOAS family `Tm : Type → Type` with `flatMap : Tm B → (B → Tm A) → Tm A` quantifies over `B : Type` in a constructor: `Type 1`.
- The first-order syntax (`Fn.user id`) needs ids that encode run-time values for nested closures.
- So the IO laws are separate `Prop`s over `IOI.*` with `env` hypotheses, same calls and nesting as the generic law.

## Enumerator cost (two-fibers program, `picks 3`, fuel 400, ~40 micro-steps per run)

| depth | lists | distinct obs | decide +kernel | decide_cbv |
|---|---|---|---|---|
| 2 | 13 | 2 | 0.5 s | |
| 3 | 40 | 4 | 1.9 s | 2.3 s + 1.5 s check |
| 4 | 121 | 6 | 5.5 s | 2.9 s + 1.6 s |
| 5 | 364 | 6 | 16.4 s | 4.2 s + 3.0 s |
| 6 | 1,093 | 6 | | 7.8 s + 6.1 s, 2.0 GB |
| 7 | 3,280 | 6 | | heartbeat timeout (200,000) at 19 s |

- `decide +kernel`: about 45 ms per run, ×3 per depth.
- `decide_cbv`: about ×2 per depth. The plain enumeration re-runs each list from the start, so `cbv` cannot share run prefixes. A state-level DFS would share them (not built).

## Proof technique for `fa` never runs

- `rfl` (elaborator defeq, then kernel) evaluates `runObs` with free `env`, free ids and a free choice tail. User code is never called, so nothing blocks.
- Symbolic fuel works as `f + N` with `N` one more than the halting tick: `runSchedState` matches the fuel before it checks `halt`, so `runSchedState mt f cs s` with a free `f` is stuck.
- `pick n` with a free `n`: `n % 1` does not reduce. Lemma `tick_init_pick` (simp with `Nat.mod_one`, `Fiber.new`) rewrites it to `pick 0`.
- `forceR` runs (7 ticks) need `set_option maxHeartbeats 1000000 in` for the `f + 7` case.
- Proof file: 16 s, 840 MB. Full `lake build --wfail`: 18 s wall, 850 MB. `lake check`: 75 s, 630 MB. `lake exe audit`: 4 s, 1.65 GB.

## Smoke tests (bounded, model)

- 11 `fa` (pure, emit, canceled, error, cede, start child, forged root cancel, forged poll id 1) × 4 laws, `picks 3` depth 4 and `picks 2 + cancel 0/1` depth 4: all agree.
- `uncancelablePollIsIdentity` with `fa = start(cancel fiber 0) >> emit 1 >> n × flatMap(pure) >> emit 2`: the sets differ only for `n = 509`. Left side has `Canceled` with trace `[1]`; right side not. Cause: two more run-loop iterations (Uncancelable, UnmaskRunLoop) move the first auto-yield (1024 iterations) before `emit 2`.

## Smoke tests (real Cats Effect 3.7.1, TestControl, 20 seeds)

Program: `body.start.flatMap(f => IO.cede >> f.cancel >> f.join)`, `fa = emit 1 >> pad(n) >> emit 2`, `pad(n) = IO.unit.flatMap(_ => pad(n-1))`.

- `IO.canceled >> emit.void` and `IO.canceled`: both `Canceled()`, trace empty. `IO.canceled.forceR(emit)` and `IO.canceled.productR(emit)`: same.
- `IO.uncancelable(poll => poll(fa))` vs `fa` in that context: the sets differ only at `n = 509` (left side also has `Canceled()` with trace `[1]`). Same `n` as the model. So the model's auto-yield position matches CE exactly.

## Findings

1. `onCancelAssociatesOverUncancelableBoundary` is not "deliberately violated". The NB comment (`MonadCancelLaws.scala:47-60`) says the law makes the set of laws violate the monad laws. The CE suite checks this law for IO, and the bounded model checks agree.
2. Under outside cancel, any law whose sides differ in run-loop iteration count is distinguishable through the auto-yield position. This is real CE behaviour (TestControl), not a law in CE's sense (`eqIOA` runs each side alone).
3. The model `env` can name any fiber id (`IO.cancelOf 0`), so `Eqv` (pick-only) still sees outside-cancel effects. Scala code cannot get the root fiber handle.

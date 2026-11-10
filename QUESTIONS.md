# Questions for the user

Only non-obvious questions that agents cannot decide alone. Each entry: date, question, context, the default that agents use until you answer.

## Q1 (2026-11-10): Monad-transformer instances in scope?

- Question: Should the `Async`/`Sync`/`MonadCancel` instances for monad transformers (`OptionT`, `EitherT`, `Kleisli`, `StateT`, `WriterT`, `IorT`) be in scope before Phase 9?
- Context: the inventory has 306 rows for them. Historically they had real cancellation bugs (masks and `poll` threading through `F`). They add a large model surface.
- Default until you answer: `excluded` with reason `deferred:`. We revisit after Phase 7.

## Q2 (2026-11-10): Add `sorryAx` to the forbidden-pattern list?

- Question: `scripts/check_forbidden.py` matches `\bsorry\b` only. A direct `sorryAx` term passes the source scan. May agents add `sorryAx` (a stricter gate)?
- Context: the axiom audit (`lake exe audit`, lean-action axiom-audit, `lake check`) already rejects `sorryAx`. AGENTS.md says only you change the forbidden list.
- Default until you answer: no change. The axiom audits cover it.

## Q3 (2026-11-10): In which context are the laws judged?

- Question: Should a law `lhs <-> rhs` hold (a) only when the program runs alone, as CE's own law tests run it, or (b) also when another fiber can cancel it at any time?
- Context: with (b), laws whose two sides take a different number of run-loop steps can fail. The auto-yield every 1024 steps comes at a different place, and a cancel can land there. The model found this for `uncancelablePollIsIdentity` at exactly 509 inner `flatMap`s. Real CE 3.7.1 under `TestControl` shows the same. With (b) many laws fail for this one reason.
- Second part: model user code can name any fiber id (for example the root fiber). Scala code can only use handles it received. We plan to restrict model programs to received handles (a type invariant).
- Review batch 1 adds: even without an outside cancel, a forked child's emits can interleave differently when the auto-yield position moves.
- Default until you answer: (a) for law rows, plus the handle restriction, plus a preemption choice at any run-loop iteration in `Eqv` (decision 29), so the auto-yield position is not observable. The auto-yield effect becomes one Phase 8 finding with `maybe_intended: likely`.

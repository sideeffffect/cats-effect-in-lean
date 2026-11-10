# Questions for the user

Only non-obvious questions that agents cannot decide alone. Each entry: date, question, context, the default that agents use until you answer.

## Q1 (2026-11-10): Monad-transformer instances in scope?

- Question: Should the `Async`/`Sync`/`MonadCancel` instances for monad transformers (`OptionT`, `EitherT`, `Kleisli`, `StateT`, `WriterT`, `IorT`) be in scope before Phase 9?
- Context: the inventory has 306 rows for them. Historically they had real cancellation bugs (masks and `poll` threading through `F`). They add a large model surface.
- Default until you answer: `excluded` with reason `deferred:`. We revisit after Phase 7.

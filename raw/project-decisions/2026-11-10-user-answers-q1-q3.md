# User answers to Q1–Q3

> Source: user message in a Claude Code session, 2026-11-10 (answers to `QUESTIONS.md`)
> Collected: 2026-11-10
> Published: 2026-11-10

- Q1 (monad transformers in scope?): "no, ignore monad transformers (OptionT, EitherT, Kleisli, StateT, WriterT, IorT)".
- Q2 (add `sorryAx` to the forbidden-pattern list?): "yes, add it to the forbidden-pattern list".
- Q3 (law context): "only when the program runs alone, as CE's own law tests run it".
- Q3 second part (handles): "only use handles it received. Indeed, fiber handles should be un-forgeable, so code can't just get a handle to an existing fiber from thin air. That also means that code can cancel only those fibers it created itself or to which it received handles".

Applied by the orchestrator the same day:
- Q1: the 306 transformer rows changed from `deferred:` to `out-of-scope:` (new reason prefix in `scripts/check_inventory.py`, same text in `scripts/gen_inventory.py`). They never come back in Phase 9.
- Q2: `\bsorryAx\b` added to `scripts/check_forbidden.py`. This is a stricter gate.
- Q3: matches the default already in use. Laws use `EqvP` with no outside canceller. `EqvP` still lets the program's own fibers interleave at any run-loop iteration; that is scheduling inside the program, not an outside cancel.
- Q3 handles: matches `WellFormed` (decisions 22, 27, 37): fiber, `Ref`, `Deferred`, poll and `ContState` handles are capabilities. User code can cancel or join only fibers it started or whose handle it received.

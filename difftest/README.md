# Differential testing

The Lean model and the real Cats Effect run the same generated programs. Method: `wiki/methodology/differential-testing.md`.

Planned content (Phase 3 of `wiki/methodology/project-plan.md`):

- `difftest/` — sbt project. Cats Effect `3.7.1`, and a second build against `series/3.x`. It runs each program under `TestControl` and prints one JSON line for each case.
- Lean side — `lake exe cediff`. It reads the same cases and checks each real outcome against the model.
- `difftest/corpus/` — shrunk cases that once disagreed. CI runs them as a regression corpus.

## Format

JSON lines (one case per line). Each case has the program AST, the seed (or the logged schedule), and the observed outcome and trace. The AST schema is shared by Scala and Lean. Define it in Phase 3 and document it here.

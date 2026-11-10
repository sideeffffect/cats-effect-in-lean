# Differential testing

The Lean model and the real Cats Effect run the same generated programs. Method: `wiki/methodology/differential-testing.md`. Program format: `wiki/methodology/difftest-program-format.md`.

## Contents

- `src/`, `build.sbt`, `run.sh` — Scala runner (Cats Effect 3.7.1). It reads JSON-line cases and prints one result line for each case.
- `cases/` — hand-written golden cases. `sbt -batch test` checks them.
- `py/` — generator, driver and shrinker (Python 3, stdlib only):
  - `gen.py` — seeded, type-directed generator of v0 cases (weight table `WEIGHTS`, knobs `CONFIG`).
  - `typecheck.py` — scope and type checker. Each generated case must pass it (decision 8).
  - `drive.py` — subcommands `run`, `scala-check`, `shrink`, `corpus`.
  - `mock_lean.py` — a fake Lean side with planted faults, for the self-test only.
  - `selftest.py` — fast self-test (about 15 s). CI runs it after `sbt -batch test`.
- `corpus/` — shrunk cases that once disagreed (regression corpus). It is made when the first mismatch is saved.

## Commands

```sh
python3 difftest/py/gen.py --seed 1 --n 100                 # cases on stdout
python3 difftest/py/drive.py scala-check --seeds 1 2 3 --n 10000
python3 difftest/py/drive.py run --seeds 1 2 3 --n 10000 --lean "lake exe cediff" --shrink
python3 difftest/py/drive.py corpus [--lean "lake exe cediff"]
python3 difftest/py/selftest.py
```

## Corpus entry format

One file `corpus/<case id>.json` for each shrunk mismatch:

| key | meaning |
|-----|---------|
| `case` | the shrunk test case (a v0 input line) |
| `scala` | Scala `outcome` and `trace` when the entry was saved |
| `lean` | Lean output when the entry was saved |
| `field` | first field that differed: `outcome`, `trace`, `schedule`, or `refinement` |
| `expect` | `agree` (default: the model must be fixed) or `mismatch` (accepted difference) |
| `triage` | `untriaged`, `model-bug`, `harness-bug`, `model-simplification`, `intended-ce-behaviour`, `underspecified`, `ce-bug` |
| `note` | free text: the reason for the triage |
| `found` | date, original case id, original and shrunk size |

`drive.py corpus` fails if the Scala result changed, or (with `--lean`) if the Lean result is not `expect`.

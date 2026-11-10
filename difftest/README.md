# Differential testing

The Lean model and the real Cats Effect run the same generated programs. Method: `wiki/methodology/differential-testing.md`. Program format: `wiki/methodology/difftest-program-format.md`.

## Contents

- `src/`, `build.sbt`, `run.sh` — Scala runner (Cats Effect 3.7.1). It reads JSON-line cases and prints one result line for each case.
- `cases/` — hand-written golden cases. `sbt -batch test` checks them. Format v1 files: `syncstep.jsonl`, `resource.jsonl`, `queue.jsonl` (made by `cases/gen_v1.py`; they hold the calibration witnesses of CE-0001, CE-0002 and CE-0003). `preempt.jsonl` (made by `cases/gen_preempt.py`): small `runtime` thresholds (auto-yield after every few iterations) and `timeoutTo`.
- `py/` — generator, driver and shrinker (Python 3, stdlib only):
  - `gen.py` — seeded, type-directed generator of v1 cases (weight table `WEIGHTS`, knobs `CONFIG`).
  - `typecheck.py` — scope and type checker. Each generated case must pass it (decision 8).
  - `drive.py` — subcommands `run`, `check`, `scala-check`, `shrink`, `corpus`.
  - `mock_lean.py` — a fake Lean side with planted faults, for the self-test only.
  - `selftest.py` — fast self-test (about 15 s). CI runs it after `sbt -batch test`.
- `corpus/` — shrunk cases that disagreed (regression corpus). `known-*.json`: known model bugs in `CatsEffectInLean/` (`drive.py` `KNOWN_MODEL_BUGS`).

## Commands

```sh
python3 difftest/py/gen.py --seed 1 --n 100                 # cases on stdout
python3 difftest/py/drive.py scala-check --seeds 1 2 3 --n 10000
python3 difftest/py/drive.py run --seeds 1 2 3 --n 10000 --lean "lake exe cediff" --shrink
python3 difftest/py/drive.py check --lean "lake exe cediff" difftest/cases/basic.jsonl difftest/cases/sched.jsonl
python3 difftest/py/drive.py run --seeds 1 2 3 4 5 --n 10000 --modes replay --lean "lake exe cediff" --allow-known-model-bugs
python3 difftest/py/drive.py run --seeds 101 102 103 --n 100000 --modes replay --lean "lake exe cediff" --min-v1-agree 50000  # v1 depth
python3 difftest/py/drive.py corpus [--lean "lake exe cediff"]
python3 difftest/py/selftest.py
```

## Corpus entry format

One file `corpus/<case id>.json` for each shrunk mismatch:

| key | meaning |
|-----|---------|
| `case` | the shrunk test case (a v0 or v1 input line) |
| `scala` | Scala `outcome` and `trace` when the entry was saved |
| `lean` | Lean output when the entry was saved |
| `field` | first field that differed: `outcome`, `trace`, `schedule`, or `refinement` |
| `expect` | `agree` (default: the model must be fixed), `mismatch` (accepted difference), or `known-model-bug` (a mismatch of a known model bug; the entry fails when the model is fixed) |
| `triage` | `untriaged`, `model-bug`, `harness-bug`, `model-simplification`, `intended-ce-behaviour`, `underspecified`, `ce-bug` |
| `known_bug` | id in `drive.py` `KNOWN_MODEL_BUGS` (empty if none) |
| `note` | free text: the reason for the triage |
| `found` | date, original case id, original and shrunk size |

`drive.py corpus` fails if the Scala result changed, or (with `--lean`) if the Lean result is not `expect`.

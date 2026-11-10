# python-formalization README.md and CONTRIBUTING.md (verbatim)

> Source: https://github.com/Broyojo/python-formalization/blob/main/README.md
> Collected: 2026-11-10
> Published: 2026-11-09

````markdown
# python-formalization

A Lean 4 model of CPython 3.15.2, written by AI agents, tested against the real interpreter, and reviewed function by function. Along the way it found hundreds of bugs in CPython.

**Write-up:** [broyojo.com/python-formalization](https://broyojo.com/python-formalization/)

<!-- stats:start -->
| | |
|---|---|
| Lean code | 613,318 lines in 1,539 files |
| Theorems and lemmas | 18,898, all checked on every build |
| Top-level properties | 3,834 proven, 588 refuted, 94 open |
| Functions reviewed faithful | 4,071 of 26,004 in scope (15.7%) |
| Bug records | 418 that reproduce on 3.15.2, each with a reproducer |
<!-- stats:end -->

## How it works

Every function, bytecode instruction and grammar rule in the CPython 3.15.2 source tree is a row in an inventory (`coverage/methods/`). Each row goes through four steps:

1. **Mirror.** An agent writes a Lean model that follows the C or Python source line by line: same branch order, same error messages, same integer overflow. Each step cites the 3.15.2 source. Python callbacks are modelled as code that can raise, change state and re-enter.
2. **Differential test.** The model and the real `python3` run side by side on generated inputs (`difftest/`) until they agree on at least 50,000 cases across several seeds.
3. **Prove or refute.** Properties are stated over all inputs and proved in Lean. A false statement is refuted with a counterexample, never weakened. The build rejects `sorry`, `native_decide` and new axioms.
4. **Review.** A separate agent that did not write the model checks it against the source, runs each property on the real interpreter, and asks whether a broken implementation would also satisfy the theorem. Only rows marked `FAITHFUL` in `coverage/review/` count as covered.

When a refuted property turns out to be CPython's fault, it becomes a bug record in `bugs/`: a reproducer that prints `REPRODUCED` on 3.15.2, the cause with line numbers, a duplicate search of the CPython tracker, and a priority.

## Layout

```
lean/PyLean/<Area>/        models and proofs, one directory per area of CPython
lean/PyLean/Registry.lean  one entry per property: source citation, status, theorem
lean/Audit.lean            checks every registry theorem and the axioms it uses
lean/DiffMain.lean         `pydiff`, the Lean side of the differential tests
difftest/                  case generators and the harness that compares Lean with CPython
coverage/methods/          the inventory: one row per function with its status
coverage/review/           independent review verdicts (FAITHFUL / HOLLOW) per row
bugs/                      one YAML record per finding; FINDINGS.md lists them
reports/                   triage of bug records and draft upstream issues
site/                      generator for the write-up (docs/index.html)
AGENTS.md                  instructions the modelling agents follow
coverage/REVIEW_PROMPT.md  instructions the reviewing agents follow
```

## Running it

You need the Lean toolchain pinned in `lean/lean-toolchain` (Lean 4.35.0, installed by `elan`) and a CPython 3.15.2 build on `PATH` as `python3`. A full build is large: plan for a machine with 64 GB of RAM or more.

```sh
cd lean && lake build && lake env lean Audit.lean      # build every model and proof, then audit
python3 difftest/rangeslice_diff.py --cases 50000       # one area's model against CPython
python3 scripts/check_bugs.py                           # every bug record still reproduces
python3 scripts/check_coverage.py                       # coverage totals from the inventory
```

We ran heavy jobs on a build machine on our own Kubernetes cluster. `sky/builder.yaml` sets it up with SkyPilot, and `scripts/r <command>` syncs the checkout and runs the command there.

## Doing this for another project

Nothing here is specific to Python. To apply the method to another language, library or format:

- Start from `AGENTS.md` and `coverage/REVIEW_PROMPT.md`, and replace the CPython specifics.
- Build an inventory of every function in one pinned version (`scripts/list_python_functions.py` is ours).
- Keep coverage counted only through independent review (`scripts/check_coverage.py`).

The write-up's last sections list the practices that mattered most.

## Contributing

Help is welcome. Most of CPython is still unmodelled, and the method needs more reviewers as much as more models. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Citation

```bibtex
@misc{andrews2026formalizing,
  author       = {Andrews, David and Zhang, Chao},
  title        = {Formalizing {CPython}: A Lean Model of {CPython} 3.15.2},
  year         = {2026},
  howpublished = {\url{https://broyojo.com/python-formalization/}},
  note         = {Code: \url{https://github.com/Broyojo/python-formalization}}
}
```

## License

Apache License 2.0 (see `LICENSE`). Excerpts of CPython quoted in the models remain under the PSF License; see `NOTICE`.

## Credits

**Authors:** [David Andrews](https://broyojo.com/) and [Chao Zhang](https://chaozhang.org/).

Built by David Andrews using Opus 5.5. Inspired by Miles Cranmer's [julia-in-lean](https://github.com/MilesCranmer/julia-in-lean).
````

## CONTRIBUTING.md (https://github.com/Broyojo/python-formalization/blob/main/CONTRIBUTING.md, 2026-11-05)

````markdown
# Contributing

Help is welcome, whether you run your own agents or write Lean by hand. About 16% of the in-scope functions of CPython 3.15.2 are modelled and reviewed so far; the rest is open.

## Ways to help

- **Model a file.** Rows marked `todo` in `coverage/methods/<file>.tsv` are unclaimed. `python3 scripts/check_coverage.py` shows totals per area. Follow `AGENTS.md`: mirror the source line by line, difftest against CPython 3.15.2 until it agrees on at least 50,000 cases, then prove or refute properties.
- **Review.** Run a review of any file with `coverage/REVIEW_PROMPT.md` and record verdicts in `coverage/review/`. A well-argued HOLLOW verdict is as useful as a new model.
- **Check a bug record.** If a record in `bugs/` is wrong, no longer reproduces, or is already known upstream, open an issue here with the evidence.
- **Apply the method elsewhere.** If you formalize another language or library this way, open an issue and we'll link it.

## Before you start

- For a whole file or area, open an issue first so two people don't model the same thing.
- One pinned version only: CPython 3.15.2. Cite its line numbers.
- Pull requests must pass `lake build` and `lake env lean Audit.lean` from `lean/` (a full build needs about 64 GB of RAM), and the difftest for the area you touched.
- No `sorry`, `admit`, `native_decide`, `bv_decide`, new axioms, `implemented_by` or `@[extern]`.
- Coverage counts only rows an independent review marks `FAITHFUL`. Never weaken a statement to get a proof; refute it instead.
- Nothing from this project goes to the CPython tracker without a human reading it first. If you find a CPython bug, add a record under `bugs/` and say so in your pull request.

By contributing you agree that your contributions are licensed under the Apache License 2.0 (see `LICENSE`).
````

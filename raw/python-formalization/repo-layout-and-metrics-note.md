# python-formalization: repo layout, workflow, metrics (research note)

> Source: https://github.com/Broyojo/python-formalization (cloned to ~/Projects/python-formalization, HEAD = 2026-11-09 "Add citation")
> Collected: 2026-11-10
> Published: Unknown

Own note, written from the clone. Numbers come from scripts run on the clone on 2026-11-10.

## Identity

- Authors: David Andrews (Broyojo) and Chao Zhang (owns the Kubernetes cluster). Built with Claude Opus 5.5; Codex (GPT-6.1 Sol) did the final technical review of the issue drafts (per Discourse post / prelaunch_review.md).
- Inspired by Miles Cranmer's julia-in-lean. AGENTS.md and REVIEW_PROMPT.md say "adapted from julia-in-lean".
- Target: CPython 3.15.2 only (started on 3.14.7, re-pinned on 2026-11-01 with scripts/repin.py). Bugs are also re-checked on CPython main (commit ef1fce0).
- Toolchain: leanprover/lean4:v4.35.0 (same as cats-effect-in-lean). No Mathlib dependency (lake-manifest has no packages besides the lib; lakefile.toml only defines lib `PyLean` and exe `pydiff`). `moreLeanArgs = ["-M8000"]` caps per-file memory.
- License: Apache-2.0; CPython excerpts stay PSF.

## Git history

- 2,389 commits, all by one git author (Broyojo); 1,911 have `Co-Authored-By: Claude Opus 5.5`. 513 merge commits. Only 3 distinct `Claude-Session:` URLs appear (orchestrator sessions; work fanned out to subagents in git worktrees, branch names `worktree-agent-<hex>`).
- Timeline: 2026-10-29 (50), 10-31 (23), 11-01 (548), 11-02 (209), 11-03 (586), 11-04 (936), 11-05 (15), 11-09 (22, launch). So ~2,300 commits in 4 days of parallel agent work.
- Commit subject prefixes: `Coverage:`/`coverage:` (~300), `review:`/`Review` (~240; 493 subjects mention review), per-module prefixes (`textlibs:`, `Grammar:`, `Decimal:`, `Bytecode:` ...), `Update coverage:` (118, from update_coverage.sh).
- AGENTS.md evolved through 16 revisions (3.2 KB -> 14.4 KB). Key turn: commit 1d474a8a (10-31) "breadth-first brief" -> a4fb471c (11-01) "Record the csv and functools reviews, and rewrite the coverage rules" after review found <50% of rows faithful (21% in functools.py). c9037c81 added the "wrong-function test".

## Layout

```
AGENTS.md                    modelling-agent playbook
coverage/REVIEW_PROMPT.md    reviewer-agent prompt
coverage/methods/*.tsv       inventory: 1,053 files, 33,585 rows (one per function/opcode/grammar rule)
                             columns: file line endline name signature status(todo|modelled|excluded) entry note
coverage/review/*.tsv        84 review files; verdict FAITHFUL/HOLLOW + mirror/property/settled + reason
coverage/review/archive-3.14.7/  reviews invalidated by the re-pin
coverage/registry.tsv        export of all registry entries (from lean/Report.lean)
coverage/repin-3.15.2.tsv, gone-in-3.15.txt, difftest-migrating.txt   version-migration worklists
lean/PyLean/<Area>.lean      per-area registry (`def entries : List Entry`)
lean/PyLean/<Area>/Model.lean, Diff.lean, *.lean   model, difftest handler, proofs
lean/PyLean/Core.lean        PyExc inductive + `abbrev Py α := Except PyExc α`, ssize bounds
lean/PyLean/Registry.lean    Entry {id, pyFile, pyFns, statement, source, status, prop, thm, bug, notes}
lean/Audit.lean              checks each thm's type is exactly prop / ¬prop; axioms ⊆ {propext, Classical.choice, Quot.sound}; refuted ⇒ bug id
lean/DiffMain.lean           `pydiff` exe: JSON lines in, JSON results out
difftest/*_diff.py           41 generators (55,874 lines of Python) using difftest/common.py
bugs/*.yaml                  436 records (418 reproduce on 3.15.2; 18 "gone in 3.15")
reports/                     triage.tsv, drafts/{single,group}, issue_text, file_issues.py, check_drafts.py, prelaunch review, LAUNCH.md
scripts/                     r (remote exec), merge_*.sh, audit.sh, check_coverage.py, check_bugs.py, repin.py, recite.py, fix_bare_citations.py, list_python_functions.py, gen_findings.py
sky/                         SkyPilot builder.yaml (64 CPU / 512 GB pod on own k8s) + watchdog.sh
site/, docs/                 generator of the blog page (all numbers generated from the repo)
```

Areas (Lean dirs): Accel, Binary64, Bytecode, BytesObj, CoreLibs, Datetime, Decimal, DictSet, Fractions, Ipaddress, Itertools, JsonMod, ListSort, LongObj, MathInt, Pickle, PyGrammar (PEG rules), PyIO, RangeSlice, Sequences, StrSearch, TextLibs, TypeObj, UnicodeObj.

## Sizes

- 613,318 lines of Lean in 1,539-1,543 files; 18,898 theorem/lemma declarations.
- Registry: 4,516 properties: 3,834 proven, 588 refuted, 94 open (audit at launch).
- Coverage (check_coverage.py on HEAD): 33,585 rows; 4,780 modelled, 7,581 excluded, 21,224 todo; 5,322 FAITHFUL / 295 HOLLOW review verdicts; "18.4% of in-scope rows modelled, 20.5% reviewed faithful; 849 registry entries cover no row; 295 rows withdrawn by review". The blog/README say 4,071 of 26,004 in scope (15.7%). The difference is probably that the script counts reviewed excluded rows as faithful (uncertain).
- Per area (rows / faithful): Grammar 278/278; Objects 3,914/1,509; Modules 8,150/1,179; Lib 16,253/1,371; Python 4,313/440; Parser 677/545.

## How CPython maps to Lean

- Mirror source line by line (same branch and check order, same error message strings), cite `Objects/x.c:NN`. Citations that fell into code changed by the re-pin are tagged `@3.14.7:NN`.
- Python exceptions -> `Py α = Except PyExc α`; message compared exactly by the difftest unless the model message starts with `~`.
- Loops use explicit fuel; `PyExc.modelFuel` is never a Python outcome.
- C ints: Lean `Int` with explicit wrap/overflow helpers (`uadd`, `usub`, `toU`, `ssize`). Floats: own exact IEEE-754 model `Binary64.F64` (Lean `Float` unusable in proofs).
- C/Python "twins" (`_pydatetime` vs `_datetime`, `_pydecimal`, `_pyio`, heapq/bisect accelerators) modelled side by side; "C == Py" properties.
- Generic code modelled over abstract element types with explicit assumptions (e.g. "`__lt__` is a strict weak order").
- Callbacks/iterators/`__eq__`/`__index__` modelled as fallible and re-entrant (Py-valued, can mutate state). Required after review found success-path-only models hollow.
- Scope limits: classes by identity; GC traversal, tp_clear, tp_dealloc excluded (no heap/finalization model); free-threaded build excluded; multithreading out of scope.

## Differential testing

- `difftest/<key>_diff.py` supplies `gen_case(rng)` and `run_python(case)`; `common.main` batches cases as JSON lines to the `pydiff` Lean executable and compares results (values as JSON; exceptions by class name and message).
- Rule: 100% agreement on >= 50,000 cases over several seeds before any property is stated. A mismatch is a model bug until proven otherwise; a C-vs-Python twin mismatch is a finding.
- audit.sh reruns all difftests at 20,000 cases in parallel after merges, plus every bug reproducer.

## Proof rules / audit

- Forbidden: sorry, admit, native_decide, bv_decide, ofReduceBool, implemented_by, @[extern], new axioms (grep in audit.sh + axiom check in Audit.lean).
- Every property is `theorem x_proven : P` or `theorem x_refuted : ¬P`; refuted requires `bugs/<id>.yaml` whose reproducer prints `REPRODUCED <id>` on 3.15.2.
- "Never weaken a statement to get a proof. If it is false, refute it." Hard ones stay `.open` with a note.

## Coverage loop

1. `scripts/list_python_functions.py` parses the pinned CPython tree (never runs it) into coverage/methods/*.tsv (the denominator).
2. Module agent writes model + difftest + properties, lists every covered function in `pyFns`.
3. Merge gate (`merge_module.sh`): branch may only touch its own module paths, difftest, bugs/<key>-*, coverage tsvs; review verdicts on main always win conflicts ("an author must never overwrite an independent review"). Merges serialized with a `.git/merge.lock` dir; full audit on the pod.
4. `update_coverage.sh`: export registry via Report.lean, `check_coverage.py --prefill` settles todo rows on a unique name match.
5. Independent reviewer agent runs REVIEW_PROMPT.md per file (read-only, no execution), writes FAITHFUL/HOLLOW per row. HOLLOW rows are withdrawn to todo. Re-review rounds per file (e.g. Lib/enum.py 9 rounds, setobject.c 7).
6. Only FAITHFUL rows count.

## Bug reporting pipeline

- bugs/<module>-<slug>.yaml with fields: id, title, priority (P1-P5), kind, module, files, functions, summary, likelihood, maybe_intended, reproducer, expected, observed (3.15.2 and main), promised_by, cause (line numbers), possible_fix, duplicates {issues, related, queries, bugforge}, lean {property, theorem}.
- Agents are read-only on GitHub (search only; record every query). Dup check also against bugforge-results (an October 2026 automated tool whose bulk filing got closed as spam: gh-158748, gh-158786).
- reports/triage.tsv assigns a proposed action: ask-in-group 71, link-existing 50, check-main 37, file-alone 33, skip 18, group:<module> ~225.
- reports/make_drafts.py builds drafts; check_drafts.py reruns every code block on 3.15.2 and main; Codex did a prelaunch technical review (41 approved); a human files. At launch 6 single issues filed (gh-161688..161693), rest held pending maintainer feedback on Discourse.

## Bug statistics (bugs/*.yaml, 436 records)

- Priority: P1 19, P2 29, P3 120, P4 210, P5 58.
- Kind (free-text, normalized by blog): twin mismatch/divergence/disagreement ~129; wrong-result 44; memory-safety 27; crash 25 (+7 crash-on-valid-input); wrong-exception 20; doc-mismatch 18; sibling-mismatch 13; missing-validation 12; hang 6; regression 6; validation-order 5.
- Module: corelibs 88, textlibs 60, datetime 52, pyio 22, typeobj 20, bytesobj 20, pygrammar 19, bytecode 18, pickle 17, unicode 15+2, sequences 15, itertools 14, json 11, decimal 11, accel 10.
- Likelihood self-rating: Low 236, Very low 95, Moderate 28, Medium 9.
- Keyword counts in records: use-after-free 35, segfault 47, re-entrancy 33, `__eq__` 33, `__hash__` 28, `__index__` 22, "overflow" 87, "NUL" 84, twin/_py* 237.
- 26 records do not reproduce on main (fixed or changed upstream); ~28 mention 3.15 regressions / new-in-3.15 code.

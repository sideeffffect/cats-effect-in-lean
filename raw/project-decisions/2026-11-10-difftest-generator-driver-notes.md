# Difftest generator and driver (Phase 3 steps 3 and 5): build notes (own note)

> Source: own work in this repository (`difftest/py/`), run on 2026-11-10 against Cats Effect 3.7.1 (Scala runner v0)
> Collected: 2026-11-10
> Published: 2026-11-10

## What was built

- `difftest/py/typecheck.py`: scope and type checker for v0 programs. First-order unification. Types: unit, bool, nat, pair, either, outcome, fiber, ref, deferred. User function signatures as in the format table. `refModify` accepts only fn 3 (raise, nat state), 4 (dup), 5 (incOld, nat state). Async `ok` values are literals, all of one type.
- `difftest/py/gen.py`: seeded, type-directed generator. `Gen.prog(T, env, size, ctx)` makes a program of type T. Case i of seed s uses `random.Random("difftest-v0:s:i")`, so it does not depend on N. Each case passes `check_prog` (assert).
  - Weight table `WEIGHTS` (one weight per op, plus templates). `handle_boost` 2.5 multiplies productions that use a fiber, ref or deferred in scope. `fn_raise` 0.4 is the weight of user function 3 in `delay`/`map`.
  - Templates: `tpl_escapedPoll` (`bind f = uncancelable(p => start(child that uses p))`; child shapes: `poll(p, …)`, `onCancel(…, fin = poll(p, …))`, `guaranteeCase(…, fin = seq(poll(p, …), …))`, free), `tpl_cancelChild` (start, 0-2 cedes, cancel, maybe join), `tpl_finStack` (1-3 layers of onCancel/guaranteeCase around a core with a suspend or cancel point; finalizers raise, suspend, or use an outer poll; sometimes an async with a finalizer), `tpl_race` (racePair + case + split, so the loser fiber is in scope), `tpl_handoff` (Deferred), `tpl_ref` (Ref updates in parent and child).
  - Inside finalizers the poll weight is ×3. Inside the escaped-poll child it is ×3.
  - Size: 20% 1-5 nodes, 50% 6-20, 30% 21-40. Root type: nat, unit, bool, either, outcome, pair.
  - Schedule per case (`CONFIG`): 80% get a choice list (1-24 picks, mostly 0/1). 50% get 1-3 `{"cancel":h}` choices: h is the root, a child handle, or an unknown handle (skip path); the position is mostly early (step 1-3), because most programs end after few steps. 3% get `maxSteps` 1-5 (fuel).
- `difftest/py/drive.py`: subcommands `run`, `scala-check`, `shrink`, `corpus`. It calls `difftest/run.sh FILE` in chunks of 5,000 cases. A chunk that times out is split in halves until the hanging case is found (bin `hang`).
  - Bins: `agree`, `unsupported` (Lean prints `"outcome":"unsupported"`), `inconclusive`, `mismatch`, `harness`, `generator-bug` (Scala decode error, or a non-UserError error such as `TypeError` in the output), `hang`.
  - Replay compare: outcome, then trace, then schedule if Lean prints one. The first differing field is the mismatch detail.
  - Testcontrol compare (proposed Lean contract): Lean prints `"outcomes":[{"outcome","trace"}…]` and `"complete":bool`. Scala pair in the set → agree; not in the set and complete → mismatch; else inconclusive. Scala `inconclusive` (step cap) → inconclusive (decision 4).
  - Shrinker: greedy delta debugging. Candidates: replace a node with a child, with `raise 0`, `never`, `pure unit`, `pure 0`, `canceled`, `cede`; drop a `seq` element, an async callback, an async finalizer, a tag; later → sync; drop choice chunks (halves, quarters, …, single); picks → 0; drop `maxSteps`. Only well-typed candidates. A candidate is kept only if its measure (nodes, choices, pick sum, JSON length) is strictly smaller and the mismatch keeps the same field. All candidates of one round run in one Scala batch and one Lean batch.
  - First version had a bug: it accepted candidates that were not smaller, so it cycled (`raise` ↔ `never`) for 200 rounds (175 s). Fix: strict measure decrease.
- `difftest/py/mock_lean.py`: fake Lean side for the self-test. It copies the Scala result, drops the first `fin onCancel` event (planted fault), and reports `racePair` programs as unsupported.
- `difftest/py/selftest.py`: about 15 s. CI job `difftest` runs it after `sbt -batch test`.

## Numbers (3 seeds × 10,000 cases, `drive.py scala-check --seeds 1 2 3 --n 10000`)

- Total wall time 49.9 s. Per seed: generation about 2.4 s, 10,000 replay runs about 2.7 s (about 3,700 cases/s including JVM start), 4,000 testcontrol runs about 1.4 s, 18,000 replay schedule variants about 5.2 s.
- Generator bugs (decode error, `TypeError`, other non-UserError, hang): **0** of 30,000 replay + 12,000 testcontrol + 54,000 variant runs.
- Replay determinism: each case twice, byte-identical output: **30,000 / 30,000**. Testcontrol determinism: **12,000 / 12,000**.
- Replay outcomes per seed: succeeded about 41.5%, errored 23%, blocked 18.5%, canceled 16%, fuel 0.75%.
- Testcontrol vs replay (cases without external cancel and without small maxSteps; first 2,000 per seed; testcontrol seeds 1 and 2; replay FIFO + 8 random choice lists): TestControl outcome in the replay outcome set 3994, 3991, 3993 of 4000; outcome and trace in the set 3871, 3872, 3893 of 4000. All 18 outcome misses of an earlier identical run were found with 400 more random schedules. Of 60 trace misses (seed 1), 57 were found with 400 more schedules; the 3 rest have large schedule spaces (up to 86 distinct traces); one checked by hand (`g1-1838`) was found with 1,500 schedules. Conclusion: no sign that the scripted EC can do less than TestControl. The misses are sampling gaps.

## Coverage histogram (30,000 replay cases; % of cases)

Static ops: async 61.5, delay 55.8, pure 54.5, bind 52.9, seq 51.7, raise 40.7, onCancel 40.0, guaranteeCase 39.0, uncancelable 35.8, start 34.3, cede 31.3, canceled 27.2, poll 25.9, never 21.4, cancel 20.6, map 16.3, handleErrorWith 15.9, sleep 13.2, case 11.8, split 11.6, join 9.0, refModify 8.5, refNew 7.9, deferredNew 7.6, racePair 6.9, deferredGet 6.5, refSet 5.9, deferredComplete 5.6, refGet 5.1, attempt 3.7.

Static patterns: external cancel choice 39.8; async with 0/1/2/3 callbacks 26.1/38.1/28.7/11.3; async with finalizer 23.9; cancel child 20.6; start inside uncancelable 17.3; escaped poll (poll inside a start child) 15.6; onCancel finalizer that can raise 15.6; guaranteeCase finalizer that can raise 15.2; poll in finalizer (outer poll) 15.0; async finalizer that can raise 8.5; nested uncancelable 5.8.

Dynamic (from trace and schedule log): asyncReg 40.5; cb 30.4; pending tasks or timers at the end 27.7; choice among more than 1 ready task 16.3; callback task run 14.9; external cancel of root applied 12.4; fin guaranteeCase oc=succeeded 10.4, oc=errored 5.4, oc=canceled 4.2; reportFailure calls 6.2; fin onCancel 4.1; cancel skipped (unknown handle) 3.9; complete ok=true 3.2; time advance 2.7; ref set 2.7; external cancel of a child applied 1.9; fin async 0.9; canceler task in the ready list 0.8; complete ok=false 0.3.

Weak spots: async finalizer runs (0.9%), external cancel of a child (1.9%), `complete` that returns false (0.3%). An external cancel acts only between tasks, and most programs end in the first task.

## Observations about CE (Scala runs alone)

- No `TypeError`, no hang, no nondeterminism.
- `reportFailure` is called in 6.2% of cases. Example `g1-53`: a `guaranteeCase` finalizer raises after the body already failed; CE reports the finalizer error and keeps the first error as the outcome. This is documented `guaranteeCase` behaviour, not a finding.
- 27.7% of runs end with pending tasks or timers (for example a later callback of an async that already completed, or a loser fiber). This is a leak signal only for programs without `never`/async-without-callback; not analysed yet.

## Design decisions

- Lean testcontrol output contract ("outcomes" + "complete") is a proposal; the Lean author can change it, then change `drive.compare`.
- Corpus: one JSON file per shrunk mismatch in `difftest/corpus/`, with `expect` (`agree` by default) and `triage` (6 bins + `untriaged`). `drive.py corpus` fails when the Scala result changes or the Lean result is not `expect`.

# Review batch 16 notes (2026-11-25)

Own notes of the independent reviewer. Full review: `review/2026-11-25-review-batch-16.md`. Commit reviewed: `58ef474` (`origin/main`). Read only; no build, test, scala-cli or difftest. Read-only `gh issue view 3506 -R typelevel/cats-effect` and read-only `grep`/`awk` on the inventory.

## Scope

Phase 7 batch 7.2 gate: 7 `std.Supervisor.*` entries (track V) and 8 `std.Dispatcher.*` entries (track P7D, 2 of them heavy and refuted), the batteries, CE-0090, CE-0091, gate items (a)–(f).

## Findings

- Supervisor: 7/7 FAITHFUL as statements. Mirror of `supervise` (`SV:184-328`), both state kinds, release (`SV:168-173`) checked step by step. Restart branch read at constructor level only. Battery complete; variant 11 smoke only.
- Dispatcher: 7/8 FAITHFUL (6 open as statements, `awaitDrains` refuted). Mirror of the resource nesting, `inner`, `Worker#run`, `registerCancel` checked. Battery complete; cancel "doubles" argued, not run.
- `std.Dispatcher.noLostSubmission` HOLLOW (B1). The concurrent submitter is an unjoined fiber; the run stops when the root has an outcome (`Model/Sched.lean:25-26`). With `c = IO.never` the statement fails for every Dispatcher. The kernel fact of R32 does not show that task 1 was submitted, so the refutation does not separate CE-0090 from "the fiber did not run yet". Twin 32 also fails the statement. Fix: join the concurrent fiber before the root ends, or claim only for accepted submissions; re-derive R32 with the "submitted" fact. CE-0090 stays a bug candidate with a reproducer.
- CE-0091 FAITHFUL: theorem type exact; R15 is the bug path; twin 31 honest; record complete; reproducer last line `REPRODUCED CE-0091`. Reasoning vs #3506 correct: the upstream test `DS:639-647` waits until the effect started.
- 13 inventory rows are linked from the registry but still `todo`.

## Gate items

- (a) Lift the 5-`supervise` cap: decision 67 removes its reason; the Lean side needs only the insertion order for refinement.
- (b) Decision 67 is not a weaker gate (refinement unchanged; only the Scala run changes). Cost: non-insertion orders are covered only by pre-flag runs.
- (c) P7D: no single run ≥ 50,000 cases at 100 % with the final harness. Model unchanged, so the evidence is good, but the rule is not met by the letter: condition C1.
- (d) `LIB_EXNS` acceptable: it only affects the generator-bug check; the outcome is still compared.
- (e) Atomic `unsafe*` steps: fine for refutations and open entries; must be split or justified before a proof.
- (f) CE-0091 reasoning correct.

## Gate

FAIL: B1. Conditions C1 (difftest 50,000 with the final harness), C2 (lift cap), C3 (inventory status), C4 (atomic steps, before proofs), C5 (CI on the fix commit).

## Lessons

- A harness fiber that nobody joins makes "when the root is done" claims false for every implementation. Join every harness fiber whose effects the claim reads, or condition the claim on what that fiber did.
- A refutation's kernel fact must contain the bug's distinguishing event (here: "the submission returned"), not only the bad end state.
- `-XX:hashCode=2` gives insertion order only for small `ConcurrentHashMap`s: a treeified bin puts new nodes first.

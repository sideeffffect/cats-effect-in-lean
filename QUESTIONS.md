# Questions for the user

Only non-obvious questions that agents cannot decide alone. Answers: `raw/project-decisions/2026-11-10-user-answers-q1-q3.md`. Each entry: date, question, context, the default that agents use until you answer.

## Q1 (2026-11-10): Monad-transformer instances in scope? — ANSWERED: no, ignore them

- Question: Should the `Async`/`Sync`/`MonadCancel` instances for monad transformers (`OptionT`, `EitherT`, `Kleisli`, `StateT`, `WriterT`, `IorT`) be in scope before Phase 9?
- Context: the inventory has 306 rows for them. Historically they had real cancellation bugs (masks and `poll` threading through `F`). They add a large model surface.
- **Answer (user, 2026-11-14):** "Yes. But if you think it's a good idea, feel free to split it into a separate check. Maybe even multiple checks, if parallelism would help here." Decision 57: `heavy-proofs` becomes a required check. The heavy work and the paranoid replay are split into parallel matrix jobs, with one aggregate job `heavy-proofs` as the stable required name. See `raw/project-decisions/2026-11-14-decision-57-required-heavy-checks.md`.
- Default until you answer: `excluded` with reason `deferred:`. We revisit after Phase 7.

## Q2 (2026-11-10): Add `sorryAx` to the forbidden-pattern list? — ANSWERED: yes (done)

- Question: `scripts/check_forbidden.py` matches `\bsorry\b` only. A direct `sorryAx` term passes the source scan. May agents add `sorryAx` (a stricter gate)?
- Context: the axiom audit (`lake exe audit`, lean-action axiom-audit, `lake check`) already rejects `sorryAx`. AGENTS.md says only you change the forbidden list.
- Default until you answer: no change. The axiom audits cover it.

## Q3 (2026-11-10): In which context are the laws judged? — ANSWERED: (a) alone; handles only if received

- Question: Should a law `lhs <-> rhs` hold (a) only when the program runs alone, as CE's own law tests run it, or (b) also when another fiber can cancel it at any time?
- Context: with (b), laws whose two sides take a different number of run-loop steps can fail. The auto-yield every 1024 steps comes at a different place, and a cancel can land there. The model found this for `uncancelablePollIsIdentity` at exactly 509 inner `flatMap`s. Real CE 3.7.1 under `TestControl` shows the same. With (b) many laws fail for this one reason.
- Second part: model user code can name any fiber id (for example the root fiber). Scala code can only use handles it received. We plan to restrict model programs to received handles (a type invariant).
- Review batch 1 adds: even without an outside cancel, a forked child's emits can interleave differently when the auto-yield position moves.
- Default until you answer: (a) for law rows, plus the handle restriction, plus a preemption choice at any run-loop iteration in `Eqv` (decision 29), so the auto-yield position is not observable. The auto-yield effect becomes one Phase 8 finding with `maybe_intended: likely`.

## Q4 (2026-11-10): Heavy proofs job (decision 55): required check, and paranoid coverage?

- Question 1: Should the CI job `heavy-proofs` be a required status check for `main` (branch protection)? The main `lean` job defers to it the inventory rows that only a heavy entry settles (today one row: `laws.GenSpawnLaws.uncancelableRaceNotInherited`), and the theorem checks of heavy entries. The two jobs together run every check of the old single registry; but if `heavy-proofs` is not required, a red heavy job would not block a merge, and that would be weaker than before.
- Question 2: The scheduled `paranoid-heavy.yml` replays the heavy proofs through six kernels (`lake check --from-export --paranoid`). One default-kernel replay takes about 38 min locally, so six kernels may need about 4 h or more; the job timeout is 350 min (GitHub-hosted maximum 360). The export file size is not measured yet. If it does not fit: run it on a self-hosted runner, split it by kernel, or accept only the default-kernel replay (in `heavy-proofs`) for heavy proofs?
- Context: decision 55 (`raw/project-decisions/2026-11-10-decision-55-heavy-proofs.md`). The law entry is out of the default build either way.
- Default until you answer: agents treat a red `heavy-proofs` job like a red `lean` job (no merge to `main`); `paranoid-heavy.yml` stays scheduled as is, and its first result decides.

## Q5 (2026-11-15): Is a trade-off that a PR names a bug? (CE-0060, `Semaphore#count`)

- Question: PR #4648 (in v3.7.1) made the cancelation of `Semaphore#acquireN` O(1). Its description says "count may transiently include [canceled waiters]". The Scaladoc of `count` was not changed ("returns the number of permits callers are waiting for"). Track S refuted "`count` = `available` when every user fiber has ended": with `Semaphore(0)` and two canceled waiters, `count` stays -1 until the next release, which may never come. Should such a documented-in-a-PR trade-off stay a bug record?
- Context: no permit is lost; only `count` is wrong. `bugs/CE-0060.yaml` has priority low and `maybe_intended: likely`. AGENTS.md: "Known deliberate behavior is not a bug".
- Default until you answer: keep CE-0060 as a low-priority record with `maybe_intended: likely`, because the state is not transient without a later release and the Scaladoc still promises the old meaning. Nothing is filed upstream.

## Q6 (2026-11-25): Track P7D (Dispatcher): finish the Lean mirror after track V, in a new session?

- Question: Track P7D found and reproduced CE-0090 (a parallel `Dispatcher` loses a submission made while its release runs; v3.7.1 and series/3.x). The Lean mirror, difftest ops, properties, witnesses and battery are not written yet. Should the track go on in a later session, after track V's `Supervisor` mirror is on `main`?
- Context: an exact replay difftest of `Dispatcher` needs an exact mirror of `Supervisor` (both `checkRestart` paths); a stand-in would not match the Scala schedules. The mirror is large (Supervisor, Resource release order, worker loop, `cont`-based queue, Promise/Future). You asked to limit quota use. `bugs/CE-0090.yaml` has `lean.status: pending`.
- Default until you answer: CE-0090 stays a draft record with a reproducer and no Lean property. The Dispatcher mirror starts after track V lands, with the plan in `wiki/cats-effect/dispatcher-model.md`. Nothing is filed upstream.

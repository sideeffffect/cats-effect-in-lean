# Decision 57: heavy proofs are a required check, split into parallel jobs (2026-11-14)

## User answer to Q4

"Yes. But if you think it's a good idea, feel free to split it into a separate check. Maybe even multiple checks, if parallelism would help here."

## Facts at the time

- `main` had no branch protection and no rulesets (`gh api .../branches/main/protection` gave 404). No CI job was a required check.
- Agents push directly to `main` after local checks (AGENTS.md "Git").
- The heavy job (decision 55) took 61 min with a cold build and 28–31 min warm, on one runner. Each heavy chunk module builds and replays on its own after the common base.

## Decision

1. Split the heavy work into a matrix of parallel jobs: one job per heavy module group (build plus `leanchecker` replay), and one job for `audit_heavy` and the axiom checks.
2. One aggregate job named `heavy-proofs` needs all matrix jobs and fails if any of them fails. It is the stable name for the required check, so the matrix can change without a change in branch protection.
3. Split `paranoid-heavy.yml` by kernel (one matrix job per kernel), so each job fits in the 360 min GitHub-hosted limit. This answers Q4 question 2.
4. After the split is green on `main`, protect `main` with these required checks: every job of `ci.yml`, including `heavy-proofs`. Admins can still push directly (`enforce_admins: false`), so the direct-push workflow keeps working, but a red required check shows on the commit and blocks pull-request merges.
5. Agents still treat any red required check as a blocker before the next push.

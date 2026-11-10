# Status check of open Cats Effect bugs #4687, #4627, #4571, #4483, #4697

> Source: https://github.com/typelevel/cats-effect/issues (read-only `gh` queries) and local checkout `~/Projects/cats-effect` after `git fetch origin`
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note; issue dates below)

Phase 0 step 1 of the project plan. Read-only queries only. Nothing was written outside this repository.

## Branch facts (after fetch, 2026-11-10)

- `origin/series/3.x` head: `de84c01f76` (Merge PR #4690, flake.lock update).
- `origin/series/3.7.x` head: `2f9420145f` (Merge PR #4630, fix for #4627).
- Latest release: v3.7.1 (2026-08-23). No release after it.
- Fixes go to `series/3.7.x` first. Maintainers merge `series/3.7.x` forward into `series/3.x` from time to time (example: PR #4669 "Merge changes from 3.7.1 into series/3.x").
- `origin/series/3.x..origin/series/3.7.x` has 9 commits. The #4627 fix is one of them.

## Per bug

### #4687 — `IO#syncStep` drops `uncancelable` and `onCancel` from the returned `IO`

- State: open. Label `:beetle: bug`. Created 2026-09-18.
- PRs: #4686 (open, base `series/3.7.x`, pending tests), #4700 (open, base `series/3.7.x`, fix "Keep uncancelable and onCancel on the syncStep remainder").
- Fix merged: no. Not on `series/3.x`, not on `series/3.7.x`, not in a release.
- Present at v3.7.1: yes.
- Code at v3.7.1: `core/shared/src/main/scala/cats/effect/IO.scala:2340` (`object SyncStep`), `:2390` (`case IO.Uncancelable` when `G.rootCancelScope == Uncancelable`), `:2396` (`case IO.OnCancel`). Entry: `IO.scala:1161` (`syncStep(limit)`).
- Downstream: evolution-gaming/cats-helper#425 and kafka-flow#936/#937 reference it.

### #4627 — `Resource.eval` extra cancellation point

- State: open (not auto-closed, because the fix PR targets a non-default branch). Created 2026-06-28.
- PR: #4630 "Fix #4627 resource early cancelation" (reardonj). MERGED 2026-10-12 into `series/3.7.x`. Merge commit `2f9420145f49e0e2eed57c24d58cf8c513a6c964`. Changes `kernel/.../Resource.scala` and `ResourceSuite.scala`.
- On `series/3.7.x`: yes. On `series/3.x`: no (not yet merged forward). In a release: no (expected in a future 3.7.2).
- Present at v3.7.1: yes (`git merge-base --is-ancestor 2f94201 v3.7.1` → exit 1).
- Code at v3.7.1: `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala:464` (`allocatedCase`); `:485` (`case Allocate` opens its own `F.uncancelable`); `:508` (`poll(continue(head(b), tail, rel2))`); `:526` (`case Eval(fa)` runs outside any `uncancelable`). The fix moves the whole loop under one `F.uncancelable { poll => ... }` and replaces `poll(continue(...))` by `(poll(F.unit) >> continue(...))`.
- Related: typelevel/keypool#708/#709 (same pattern, fixed in keypool), PR #4710 (draft "Lossless cancelation").

### #4571 — `Queue.take.timeout(...)` loses elements on cancelation

- State: open. Created 2026-03-19.
- PRs: #4641 "Lossless cancelation and joinOrCancel" (closed, not merged, base `series/3.x`); #4710 "Lossless cancelation" (open, draft, base `series/3.7.x`). Issue #4620 "Add `Fiber#joinOrCancel`" (open) is related.
- Fix merged: no. Present at v3.7.1: yes.
- Cause (durban, djspiewak in comments): not `Queue`-specific. It is how `racePair` behaves. Minimal form: `ioa.start.flatMap(inner => inner.join.onCancel(inner.cancel)).start.flatMap(outer => outer.cancel *> outer.join)` loses the inner result if `outer` is canceled after `inner` completes.
- Code at v3.7.1: `core/shared/src/main/scala/cats/effect/IOFiber.scala:909` (`RacePair` run-loop branch); `IO.scala:818`/`:825` (`timeout`); `kernel/.../GenTemporal.scala:131`.

### #4483 — `Queue#mapK` violates atomicity guarantees

- State: open. Created 2025-09-05.
- PRs: none found (timeline has no cross-reference).
- Fix merged: no. Present at v3.7.1: yes.
- Code at v3.7.1: `std/shared/src/main/scala/cats/effect/std/Queue.scala:51`–`58`. `mapK` wraps each op as `f(self.op)` with no `uncancelable`/`poll` handling.

### #4697 — `Resource#allocate` that fails produces `reportFailure` under timeout

- State: open. Created 2026-10-06. Reported on 3.7.1.
- PR: #4712 "Avoid spurious Resource timeout error reports" (open, base `series/3.x`).
- Fix merged: no. Present at v3.7.1: yes.
- Maintainer comment: likely a `Resource` variant of #2962 (see also #3085). `Resource`'s `Concurrent` does not override `racePair` to use the effect's own implementation.
- Code at v3.7.1: `kernel/.../Resource.scala:1455` (`GenConcurrent[Resource[F, *], Throwable]` instance, no `racePair` override), `:1464` (`start`).
- Note: may be judged "known / unfixable in general" like #2962. Weak calibration target.

## Other bug issues filed since 2026-08-23

`gh search issues --label ":beetle: bug" --created ">=2026-08-23"` returns only #4697, #4687, #4674.

- #4674 (open, 2026-08-27): `LocalQueue.enqueueBatch` spins forever on a dangling steal tag. Open PRs: #4688 (stop searching for work when stolen timers filled the local queue), #4696 (unlabelled issue-like PR text "Timer callbacks may overflow internal worker queues, leading to a busy loop deadlock"). Runtime code; needs a memory/scheduler model (Phase 9).
- Older open bugs with recent PR activity: #4644 (TracingPlatform UB on Wasm; workaround PR #4691; platform-only, not a target), #4505 (`OutOfMemoryError` not propagated from `CompletableFuture`; PR #4678 open).

## Commands run (all read-only)

```
gh issue view <n> -R typelevel/cats-effect --json state,title,closedAt,createdAt,labels
gh api repos/typelevel/cats-effect/issues/<n> --jq '[.state,.state_reason,.title,.created_at,.closed_at,...]'
gh api "repos/typelevel/cats-effect/issues/<n>/timeline?per_page=100" --jq '.[] | select(.event=="cross-referenced") | ...'
gh api repos/typelevel/cats-effect/issues/<n>/comments --jq '.[].body'
gh pr view <p> -R typelevel/cats-effect --json state,baseRefName,mergedAt,mergeCommit,author,createdAt,isDraft,title
gh release list -R typelevel/cats-effect --limit 6
gh search issues -R typelevel/cats-effect --label ":beetle: bug" --created ">=2026-08-23" --sort created
gh issue list -R typelevel/cats-effect --state open --search "created:>=2026-08-23 sort:created-desc"
gh pr list -R typelevel/cats-effect --state all --search "created:>=2026-08-23 sort:created-desc"
git -C ~/Projects/cats-effect fetch origin
git -C ~/Projects/cats-effect branch -r --contains 2f9420145f49e0e2eed57c24d58cf8c513a6c964   # -> origin/series/3.7.x only
git -C ~/Projects/cats-effect tag --contains 2f9420145f49e0e2eed57c24d58cf8c513a6c964         # -> (none)
git -C ~/Projects/cats-effect merge-base --is-ancestor 2f94201 v3.7.1                          # -> exit 1
git -C ~/Projects/cats-effect log --oneline origin/series/3.x..origin/series/3.7.x             # -> 9 commits
git -C ~/Projects/cats-effect diff v3.7.1 2f94201 -- kernel/.../Resource.scala
git grep -n <symbol> v3.7.1 -- <files>
```

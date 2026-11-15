# Review batch 15 (2026-11-15): re-check of the Phase 7 batch 7.1 gate

Reviewer: independent agent. It did not write the code. It read the Lean source, the registry, the battery files, the witnesses, the inventory, the bug record and the Scala source at `v3.7.1` (`~/Projects/cats-effect`, read only). It did not run a build, Lean, a test, sbt or a difftest. It ran one read-only `gh run list` (CI status) and one read-only Python check of the inventory `registry` column against `Registry.lean` (no file changed).
Reviewed commit: `1339812` (`origin/main`), checked out as branch `review15`. Diff base: `8325ca2` (the commit of batch 14).
Rubric: `AGENTS.md` section 5; `wiki/methodology/agent-workflow.md` (decisions 53, 58, 63, battery rules (a)-(c) of batch 13, "Reviewer evidence"); `review/2026-11-15-review-batch-14.md` (B1 = G2, C1-C5). When unsure, the answer is no.
Paths are relative to `CatsEffectInLean/` unless they start with `raw/`, `wiki/`, `inventory/`, `review/`, `bugs/` or `reproducers/`. `S` = `std/shared/src/main/scala/cats/effect/std/Semaphore.scala`, `M` = `.../std/Mutex.scala`, both at `v3.7.1`.

## Summary

| Item | Result |
|---|---|
| `std.Semaphore.seqSpec` (new, statement 9) | FAITHFUL as a statement (open) |
| `std.Mutex.lock.seqSpec` (new, statement 10) | FAITHFUL as a statement (open) |
| B1 = G2 (honest `tryAcquire`/`tryAcquireN` drop) | closed (kernel rows + mirror runs) |
| Rule (a) on all other Semaphore/Mutex operations | no unbroken honest drop found |
| C1 (12 honest queue rows) | closed |
| C2 (CI on the gate commit) | open: run `43770796431` for `1339812` is `pending` |
| C3 (independent CE-0060 re-run) | another agent does it; not seen at review time |
| C4 (CE-0060 `status` comment) | closed |
| C5 (inventory `registry` column, track S) | closed |
| Other 33 batch 7.1 entries | no change in `Props`; verdicts of batch 14 stand |

Gate (section E): **PASS**, with two open conditions (C2, C3). 35 of 35 entries FAITHFUL as statements. All five batteries complete.

---

## A. What I read

- `git diff 8325ca2..1339812` of `Props/Phase7/Semaphore.lean` (`:741-918`, statements 9 and 10), `Proofs/Phase7/SemaphoreWitness.lean` (`:323-370`), `Proofs/Phase7/SemaphoreBattery.lean`, `Proofs/Phase7/SemaphoreBatteryDefs.lean`, `Proofs/Phase7/QueueBatteryDefs.lean`, `Registry.lean`, in full.
- `Proofs/Phase7/SemaphoreBatteryDefs.lean:1-60`, `:170-300` (`Op`, `Var`, `badOf`, `repl`, `rw`, `outer`, `wrongSeq`, `c9`).
- `Proofs/Phase7/QueueBatteryHonest.lean` in full; `QueueBatteryDefs.lean:100-139` (`battery`, `inputOf`, `specB`, `runOp`, `specOK`).
- `Model/Semaphore.lean:415-445` (`releaseNIO`, `tryAcquireNIO`, `availableIO`, `countIO`, `permitUseIO`), `:555-590` (`availK`, `countK`, `modTry`); `Model/Mutex.lean:218-219` (`lockUseIO`).
- `Model/Outcomes.lean:75-160` (`Obs`, `Summary.isResult`, `Sched.obs`, `outcomesP`); `Model/Run.lean:47-66` (`Summary`); `Model/SchedP.lean:45-50` (`PChoice`: `pick`, `preempt`; no cancel).
- `S:28-117` (Scaladoc), `S:179-277` (`acquireN`, `releaseN`, `available`, `count`, `permit`, `tryAcquireN`); `M:24-60`.
- `bugs/CE-0060.yaml:1-8`; `inventory/inventory.csv` rows of `std.Semaphore.*`, `std.Mutex.*`, `std.LockQueue.*`.
- `raw/cats-effect/2026-11-15-semaphore-mutex-review14.md`, `raw/cats-effect/2026-11-15-queue-review14-honest-drops.md`.

## B. B1: the sequential specifications

### B.1 `std.Semaphore.seqSpec` (`semSeqSpec`, `Props/Phase7/Semaphore.lean:906`)

Statement: for all `k`, every script `ops` without `lock`/`lockNested`, every observation `o ∈ outcomesP (semSeqRoot k ops)`: `o.out.reverse = (semSpec k ops).1` and `o.summary` is `blocked` if the spec blocks, else `done (Succeeded ())`.

1. MIRROR: yes. The root is `Semaphore.newIO k` (the factory mirror) followed by the harness closure `SQ.go`. Each operation is the library term: `acquireNIO`, `releaseNIO`, `tryAcquireNIO`, `availableIO`, `countIO`, `permitUseIO` (`sopIO`, `:839-847`). `SQ.record` emits `(tag, answer)` after each operation and runs the rest (`:853-862`). The harness is not a hand-written semaphore.
2. PROPERTY: yes.
   - **Is `semSpec` a faithful reading of the Scaladoc?**
     - `acquireN(n)`: takes `n` when `n ≤ p`, else the fiber blocks: `S:31-34`, `S:58` ("semantically blocks until all requested permits are available"). With one fiber nothing releases, so it blocks for ever. `n = 0` succeeds (`0 ≤ p`; code `S:182`).
     - `releaseN(n)`: adds `n` (`S:31-32`, `S:93`).
     - `tryAcquireN(n)`: `true` and take `n` exactly when `n ≤ p`, else `false` and no change. `S:79-80` alone ("Acquires `n` permits now and returns `true`, or returns `false` immediately") does not say when. `S:41-43` does: use `tryAcquire*` "to attempt an acquire, returning immediately if the current count is not high enough to satisfy the request". So `false` only when the count is too low. `n = 0` is `true` (code `S:270`). Low note N1: cite `S:41-43` in the docstring and registry note.
     - `available` = `p` (`S:39`); `count` = `p` when nobody waits (`S:50`). In a one-fiber script nobody waits while a read runs (the fiber that would wait is the reader). `count` is a `Long`; the spec value `.int p` equals the mirror (`countK`, `Model/Semaphore.lean:567-571`, empty queue).
     - `permit.use(_ => available)`: one permit held during `use`, given back after (`S:105-109`); the inner read is `p - 1`; blocks when `p = 0` (`acquire` inside `poll`, `S:266`).
     - v3.7.1 code agrees (`S:195-203`, `:229-233`, `:256-263`, `:268-276`).
   - **Does it read every answer?** Yes. Every operation is followed by `SQ.record`, which emits `(tag, x)` with the answer `x` (`()` for `acquireN`/`releaseN`). The claim is equality of the whole list, in order, so a missing, extra or wrong answer breaks it. `Obs.out` holds only user-emitted values (`Model/Outcomes.lean:78`); the witness shows that the library emits nothing on this root (B.3).
   - **Is "blocked exactly where the spec blocks" right?** Yes. `semSpec` returns `([], true)` at the first `acq n` with `n > p` or `permit` with `p = 0`, and drops the rest of the script: the fiber never comes back. `Summary.blocked` is "no task is ready and the root has no outcome" (`Model/Run.lean:57-59`). The other cases end `done (Succeeded ())`. A wrong operation that raises gives `done (Errored _)`; one that hangs where the spec does not block gives `blocked` against `done`; one that does not block where the spec blocks gives `done` against `blocked`. All break the claim.
   - **Fuel and schedules.** `outcomesP` keeps only result summaries (`Sched.obs` returns `none` for `outOfFuel`/`taskLimit`, `Model/Outcomes.lean:99-106`). `PChoice` has no cancel (`Model/SchedP.lean:45-50`), so "all schedules" adds only preemption of the one fiber. The statement is true for v3.7.1 by reading.
   - Hypothesis: `op ≠ lock ∧ op ≠ lockNested`. These are `Mutex` operations, not in the `Semaphore` API. A type restriction, not an assumption that hides a case.
   - Strength: no concurrency, no user code. This is by design: it is the success claim that reads the answers. The concurrent claims are statements 1-8.
3. SETTLED: open.
4. Wrong functions (kernel, `Proofs/Phase7/SemaphoreBattery.lean:287-300`): `tryAcquire_honestDrop` (`Semaphore(1)`, `[tryAcq 1, avail]`), `tryAcquireN_honestDrop` (`Semaphore(2)`, `[tryAcq 2, avail]`): `c9 = false`; `good_honestDrop_inputs`: the mirror gives `c9 = true` on the same inputs.
   - The honest drop is built by `repl` (`SemaphoreBatteryDefs.lean:184-188`): `.delay (.user t)` with `SL.ofId? t = some (.modTry _ n)` becomes `.pure (.bool false)`. `tryAcquireNIO s n` for `n ≥ 1` is exactly `.delay (SL.modTry s n).fn` (`Model/Semaphore.lean:424-425`). So the wrong term answers `false` and never runs `state.modify`: no effect. This is rule (a). The kernel rows give `false` and the mirror rows `true`, so the replacement fired.
   - `c9` (`SemaphoreBatteryDefs.lean:293-295`) is the conclusion of `semSeqSpec` with `==` for `=`. `Val` and `Summary` derive `DecidableEq`, so `==` is exact. The run is `runObsP … 3000 []`, an element of `outcomesP` by definition.
   - By reading also: `tryAcquireN` that answers `true` without taking (`[tryAcq 1, avail]` gives `avail 1`, spec `0`), a `releaseN` that gives nothing (`[rel 1, avail]`), an `available`/`count` that returns a constant (`[avail]` for two values of `k`).
5. Decision 53: `semSeqSpec_satisfiable` (`SemaphoreWitness.lean:333`): `k = 1`, `ops9 = [tryAcq 1, tryAcq 1, avail, count, rel 1, permit, acq 1, acq 1]`; the first two spec answers are `true`, `false`; the spec blocks; the kernel run `run9_ok` (`:327`) gives the spec list and `blocked`. Complete: it reaches both answers of `tryAcquireN`, `permit`, and the block.

Verdict: FAITHFUL as a statement.

### B.2 `std.Mutex.lock.seqSpec` (`mutexSeqSpec`, `Props/Phase7/Semaphore.lean:914`)

Statement: every script of `lock` (`m.lock.use(_ => IO.unit)`) and `lockNested` (`m.lock.use(_ => m.lock.use(_ => IO.unit))`): the answers are `(7, ())` for each `lock` before the first `lockNested`, and the run is `blocked` at the first `lockNested`, else `Succeeded(())`.

1. MIRROR: yes. `Mutex.newIO` and `lockUseIO` (`Model/Mutex.lean:218-219`: `bracketFull` with `ML.acq`, the `LockQueue` mirror).
2. PROPERTY: yes.
   - **Is the nested deadlock documented?** Yes. `M:41-42`: "'''Note''': This lock is not reentrant, thus this `mutex.lock.surround(mutex.lock.use_)` will deadlock." `lockNested` is that program: the outer `use` holds the lock while the inner `use` waits for it.
   - `lock` on a free lock succeeds: `M:27-28` (access for one fiber at a time) and `M:52-53` (acquire, hold for the lifetime, release). After each `lock` the lock is free again, so every later `lock` succeeds.
   - Claim reads every answer (the same `SQ.record`). A `lock` that raises, hangs or never releases (the next `lock` hangs) breaks it; a reentrant lock (nested succeeds) breaks it.
   - `Mutex` has no try-operation (`M:49-60`: `lock`, `mapK`), so rule (a) has nothing more to check.
3. SETTLED: open.
4. Wrong functions: none new for this entry. The `lock` rows (raises, hangs, drops, doubles) break statements 4, 5 and 8 (batch 13, unchanged). The entry is the sequential success claim.
5. Decision 53: `mutexSeqSpec_satisfiable` (`SemaphoreWitness.lean:357`), `ops10 = [lock, lock, lockNested]`, kernel run `run10_ok` (`:352`): two answers, then `blocked`. Complete.

Verdict: FAITHFUL as a statement.

### B.3 Rule (a) for every Semaphore and Mutex operation

Question: is there still an "honest drop" (a fixed plausible answer with no effect) that breaks no statement?

| Operation | Honest drop | Breaks |
|---|---|---|
| `acquire`, `acquireN` | return `()`, take nothing | existing `drops` rows (batch 13); also stmt 9 (`[acq 1, avail]`, by reading) |
| `release`, `releaseN` | return `()`, give nothing | existing `drops` rows; also stmt 9 (`[rel 1, avail]`, by reading) |
| `tryAcquire`, `tryAcquireN` | `false`, no effect | stmt 9, kernel (`tryAcquire_honestDrop`, `tryAcquireN_honestDrop`) |
| `available`, `count` | constant | `wrongValue`/`contended` rows (kernel); a constant is caught by stmt 9 on `[avail]`/`[count]` with two values of `k` (by reading) |
| `permit` | `use` without a permit | existing `drops` row (the `Allocate` step takes nothing) |
| `lock` | `use` without the lock | existing `drops` row |
| `Semaphore.apply`, `Mutex.apply` | no meaning (factory) | `raises`/`hangs` rows |
| `tryPermit` | `Resource.pure(false)` | not mirrored (`inventory/inventory.csv:3151`, `todo`, no registry link) |

Result: no unbroken honest drop among the mirrored operations. B1 = G2 is closed.

Low note N2: `tryPermit` (`S:116-117`) is a public try-operation. It is not mirrored and it is `todo`. The battery table (`SemaphoreBattery.lean:31-37`) names `mapK` and `in` as not mirrored, but not `tryPermit`. Add it with its reason (it is `Resource.make(tryAcquire)(release.whenA(_))`, so its answer is the `tryAcquire` answer). When it is mirrored, it needs its own honest-drop row.

Low note N3: the claim "585 scripts of length ≤ 3 × `k ∈ {0, 1, 2}`" (registry note) is an evaluation, not kernel. That is acceptable as smoke. I did not re-run it.

## C. C1: the 12 honest queue rows

`Proofs/Phase7/QueueBatteryHonest.lean:20-54`: 6 classes (`boundedConc 2`, `droppingConc 2`, `circular 2`, `bounded 2`, `unbounded`, `dropping 2`) × {`tryOffer`, `tryTake`}, each `specOK (battery op .dropsHonest) k op = some false` by `decide +kernel`.

- The variant (`QueueBatteryDefs.lean:75-76`): `tryOffer` → `.pure (.bool false)`, `tryTake` → `.pure .none`. No effect. This is rule (a).
- Inputs (`inputOf`, `:122-127`): `[tryOffer 1, size]` on an empty queue (capacity 2 or unbounded): the spec answer is `true`, the drop answers `false`. `[offer 1, offer 2, tryTake, size]`: the spec answer is `Some 1`, the drop `None`. So the break is at the answer, not only at `size`.
- `specOK` runs `runObsP … 3000 []` and checks `specB` (`:130-139`), the `SeqSpec` claim as a `Bool` (accepted in batch 13 A.2).
- `Synchronous`: `sync_tryOffer_false_breaks` and `sync_tryTake_drops` (batch 14 A.2).

C1 closed. The Queue battery is complete without conditions.

## D. C2-C5

- C2 (CI): `gh run list --workflow CI`: `43770796431` for `1339812` `pending` (2026-11-15T22:42Z); `43767264494` for `a7f57ad` `in_progress`; `a8eb464` `success`; `8325ca2` `cancelled`. **Open.**
- C3 (independent re-run of `reproducers/CE-0060`): track S re-ran it (2026-11-15T21:33Z, v3.7.1 and series/3.x `de84c01`, `REPRODUCED CE-0060`; `raw/cats-effect/2026-11-15-semaphore-mutex-review14.md:30-32`). That is not independent. The coordinator gave the independent re-run to another agent; I did not see its result. **Open.**
- C4: `bugs/CE-0060.yaml:3` now names reviews 11b, 13 and 14 and Q5 (default kept). Closed.
- C5: I compared the `rows` of the 10 `std.Semaphore.*`/`std.Mutex.*` registry entries with the `registry` column of `inventory/inventory.csv` in both directions (read-only script): 0 differences. Example: `inventory/inventory.csv:3146` (`std.Semaphore.tryAcquireN`) lists `std.Semaphore.noLostPermit;std.Semaphore.seqSpec`. Closed.

## E. Gate: Phase 7 batch 7.1

### E.1 Entries

The registry has 36 ids under `std.Queue`, `std.Semaphore`, `std.Mutex`, `std.CountDownLatch`, `std.CyclicBarrier`; one is the Phase 5 calibration entry `std.Queue.UnboundedAsyncQueue.take.timeout.noLostElement` (`Registry.lean:137`). So batch 7.1 has 35 entries: the 33 of batch 14 and the 2 new ones. All 35 are FAITHFUL as statements (34 open) or FAITHFUL (CE-0060, refuted). Table: `wiki/methodology/phase7-batch1-gate-report.md`.

### E.2 Batteries

| Structure | Complete |
|---|---|
| Queue | yes (C1 closed) |
| Semaphore | yes (B1 closed; N2: name `tryPermit` as not mirrored) |
| Mutex | yes |
| CountDownLatch | yes (batch 14) |
| CyclicBarrier | yes (batch 14) |

### E.3 Verdict

**PASS.** No blocker. Open conditions:

- C2: CI must be green on the gate commit (`1339812` or a later commit that contains it).
- C3: the independent re-run of `reproducers/CE-0060` on v3.7.1 and series/3.x must print `REPRODUCED CE-0060` as its last line.

If C2 or C3 fails, the gate is FAIL again. Low notes N1-N3 do not block.

## F. Low notes

- N1: the docstring (`Props/Phase7/Semaphore.lean:746-748`) and the registry note cite only `S:79-80` for "`tryAcquireN` is `true` exactly when `n ≤ available`". The sentence that fixes the condition is `S:41-43`. Add it.
- N2: `tryPermit` is missing from the "not mirrored" list of the Semaphore battery table (B.3).
- N3: the 585-script check of statement 9 is evaluation only (smoke).

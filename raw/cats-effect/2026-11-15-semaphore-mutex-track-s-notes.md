# Phase 7 track S: Semaphore and Mutex (notes, 2026-11-15)

Own work of track S (Phase 7, batch 7.1). Source: Cats Effect v3.7.1 checkout
(`~/Projects/cats-effect`, eb0cc258fc), cats-core 2.13.0 sources (coursier cache), `gh` read-only
queries, own Lean and scala-cli runs.

## Source facts

- `std/Semaphore.scala` has one implementation (`impl`, `:145-282`). `Semaphore.in` uses the same
  class with `Ref.in`. `MapKSemaphore` only maps with a natural transformation.
- The cancelation path of `acquireN` changed in PR #4648 ("O(1) cancelation for Semaphore and
  MiniSemaphore", merged 2026-08-22 into series/3.7.x, commit 643ba33566, in v3.7.1; fixes #4434).
  Before: `cleanup` removed the request with `waiting.filterNot(_ sameAs req)` (O(n)). After: the
  canceled fiber completes its gate (`won`) and calls `reclaim(req)`, which removes only the head;
  `releaseN` wakes canceled requests (`complete` false → `releaseN(requested)`) and sweeps a
  canceled head after a partial fill. The PR description lists the trade-offs: "1. Canceled waiters
  linger in the queue until a release reaches them. 2. count may transiently include them. 3. Each
  such waiter costs one extra release pass."
- `std/Mutex.scala` at v3.7.1 has only `ConcurrentImpl` over `LockQueue.lock`
  (`std/LockQueue.scala`, a CLH queue lock with `Deferred` cells; commit 8deb2fdabe "Re-implement
  Mutex using the shared LockQueue"; `LockQueue` got its own file in 27ef12ebdb). The `AsyncImpl`
  of earlier versions is gone. So the Mutex twin at v3.7.1 is `Semaphore(1).permit`
  (`docs/std/mutex.md:7-8`: "Basically, it's a Semaphore with a single available permit").
- `SyncRef.access` at v3.7.1 (`kernel/jvm-native/.../SyncRef.scala:47-52`) has no "called once"
  flag: the setter is `F.delay(ar.compareAndSet(snapshot, a))`.
- cats-core 2.13.0: `Queue#traverse_` with a `StackSafeMonad` is `Traverse.traverseVoidDirectly`
  (`cats/instances/queue.scala:136-138`, `cats/Traverse.scala:299-309`); `Option#traverse_` is the
  `Foldable` default with `map2Eval` (`cats/Foldable.scala:591-596`); `IOAsync.map2Eval` is
  `fa.flatMap(a => fb.value.map(b => f(a, b)))` (`IO.scala:2165-2171`).
- `Resource.makeFull(acq)(rel).use(f)` = `IO.bracketFull(resource)(...)(...)` through `fold`;
  `Mutex.lock` = `makeFull(acquire)(release).void` adds one `Bind` frame (pure).

## Model

- `CatsEffectInLean/Model/Semaphore.lean` (closures `SL`, namespace 60) and
  `CatsEffectInLean/Model/Mutex.lean` (closures `ML`, namespace 61). The lock objects are
  references (`Val.fn`) to `SL.obj q` / `ML.obj q`, so user code that holds a lock cannot reach its
  state `Ref` (decision 58). Public operations for user code: `SL.op*`, `ML.op*` (`_ => s.op(...)`).
- First difftest run: 2,000 cases, all agree (no model bug found).
- Mutation checks (1,500 cases each): `reclaim` that never gives back the sunk permits → 5
  mismatches; a canceled mutex waiter that hands `EmptyCell` instead of its predecessor's cell → 10
  mismatches.

## Difftest (format v2 ops of track S)

`semNew`, `semAcquireN`, `semReleaseN`, `semTryAcquireN`, `semAvailable`, `semCount`, `semPermit`,
`mutexNew`, `mutexLock`. Generator: `gen_case` appends a `tpl_sem` or `tpl_mutex` scenario with its
own RNG (`p_sem` 0.08), as batch 6.3 did for `parTraverseN`.

- Semaphore: `opcount.py --seeds 61 62 63 --n 50000 --boost tpl_sem=20 tpl_mutex=0` and seed 64
  (`--n 12000`): 162,000 cases, 161,999 agree, 1 mismatch (below). Agreeing cases per op:
  semNew 147,285; semAcquireN 80,535; semReleaseN 114,483; semTryAcquireN 53,290; semAvailable
  147,285; semCount 147,285; semPermit 100,897. About 25 % of cases have small runtime thresholds.
- Mutex: seeds 71-73 (`--n 18000 --boost tpl_sem=0 tpl_mutex=20`) and 74-76 (`--n 8000
  --boost tpl_mutex=40`): 78,000 cases, all agree; mutexNew and mutexLock 51,304 each.
- Fixed cases: `difftest/cases/semaphore.jsonl` (24 cases, `gen_semaphore.py`), all agree;
  golden file `semaphore.expected.jsonl`.
- The 1 mismatch (`g61-9094`, field `steps`) is not in the semaphore part. The case also has a
  `parTraverseN` over 5 inputs (a `HashSet`) whose `f` starts `memoGet` fibers. The Scala run in a
  batch of 5,000 cases gave steps 360 with a schedule that none of the 12 Lean `alternatives`
  has; the same case alone gives 356 and agrees. The `alternatives` come from `rankOrder`, which
  assumes that the k children of a traversal have consecutive fiber ids; here the children start
  fibers of their own, so not all child orders are listed. Triage: harness gap of the
  `parTraverseN` refinement (batch 6.3), not the Semaphore mirror. Reported to the orchestrator.

## Properties and results

Harness (namespace 62): counter cell `Ref` 0, the lock, one fiber per `Use` (`permit g`,
`acqRel n`, `tryRel n`, `counted g`), parent `Act`s (`cancel i`, `join i`, `release n`, `cede`).
Behaviour tables (namespace 63) for the liveness statements. FIFO harness (namespace 64).

- 7 open statements with kernel-checked satisfiability witnesses
  (`Proofs/Phase7/SemaphoreWitness.lean`, about 80 s, 4.8 GB).
- `semsmoke` (random `PChoice` schedules, preemption 0-50 %): 0 violations of statements 1-5 and 7;
  wrong functions break their claims ('leak', 'twice', 'skip', 'LIFO', 'no wait', 'lost wakeup',
  'wide'); a forging `g` that captured the state `Ref` is rejected by `WellFormed` and breaks
  statement 1 when run.
- Statement 6 (`count` = `available` when every user fiber has ended) is refuted: CE-0060.
  Witness `Semaphore(0)`, two `acquire`s, cancel the second, then the first: `(available, count) =
  (0, -1)`, default schedule, fuel 92 (`decide +kernel`, about 7 s). The random smoke did not find
  it (60 random inputs, also with `need > k`): it needs two waiters that both enqueue, then the
  non-head canceled first, and no later release. With `need ≤ k` and all fibers ended a later
  release always sweeps the canceled request.
- `lake exe semsmoke 40` (about 35 min): 60 inputs per statement (48 for FIFO), 13,920 stopped runs,
  0 violations of statements 1-5 and 7; twin sampling: every sampled `Mutex` (outcome, trace) was
  also sampled for `Semaphore(1)`; fixed twin: 0 runs break statements 2 or 6; forgery rejected
  and breaks statement 1 in 40 runs; wrong functions break their claims (leak 9, twice 160, skip
  91, LIFO 160, no wait 95, lost wakeup 85, wide 78 runs).
- Fixed twin (eager removal, as v3.7.0): 4 inputs x 12 one-preemption schedules, kernel, 68 s,
  3 GB (`Proofs/Phase7/SemaphoreCountFixed.lean`, `TwinChecks`). A first version with 4 x 120
  schedules in one `decide` took 28 GB and timed out: split per input.
- Reproducer `reproducers/CE-0060/Repro.scala`: `REPRODUCED` on v3.7.1, series/3.x
  (3.7.1-89-de84c01 = head de84c01, unchanged on 2026-11-15) and series/3.7.x (3.7.1-15-2f94201):
  A: 100/100 TestControl seeds, 200/200 default-runtime runs give `count = -1`, `available = 0`; B:
  with the permit held, `count = -1` until the release, then 1.
- Duplicate search (2026-11-15): `gh search issues 'Semaphore count' / 'Semaphore cancel' /
  'Semaphore canceled waiter' / 'Semaphore reclaim' / 'Mutex cancel' / 'LockQueue'`: no result;
  `gh search issues 'Semaphore'`: 40 results, none about this; `gh search prs 'Semaphore'`: #4648
  is the only change to this code.

## Gotchas

- Lean: a variable named `ns` clashes with the opened `Semaphore.ns`/`Mutex.ns` in a pattern
  ("ambiguous pattern"). Use another name.
- Lean: a structure instance that continues on the next line with less indentation than `{` does
  not parse (`expected '}'`).
- `decide +kernel` over many runs in one declaration grows memory fast (28 GB for 480 runs of
  about 100 steps); one declaration per input keeps it at 3 GB.
- The worktree guard of the agent harness rejects some heredoc commands as "too complex"; write a
  script file and run it.

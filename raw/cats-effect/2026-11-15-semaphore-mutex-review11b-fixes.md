# Track S: fixes for review batch 11b (notes, 2026-11-15)

Own work after `review/2026-11-15-review-batch-11b.md` (13 of 15 track S and L entries FAITHFUL,
CE-0060 FAITHFUL). Corrects and extends `2026-11-15-semaphore-mutex-track-s-notes.md` (that note is
kept unchanged).

## H1: `noDeadlock` statements were HOLLOW

- `std.Semaphore.noDeadlock`, `std.Mutex.lock.noDeadlock` claimed "every stopped run ends
  `Succeeded`". `Base.err e` took any `Err`, also a fatal one. A fatal `IO.raiseError` stops the
  whole run with `Summary.fatal` (`Model/Sched.lean:120`; real `IOFiber` calls `onFatalFailure`),
  for every implementation. Counterexample: `k = 1`, `[.permit 0 (.err fatal)]`, `[.join 0]`.
- Fix (chosen of the two options in the review): the conclusion is "`o.summary ≠ .blocked`" plus
  claims on `Succeeded` runs. Fatal errors stay in the domain (a non-fatal hypothesis would have
  been sound too, but "not blocked" keeps more inputs and is the real promise).
- Regression: `Proofs/Phase7/SemaphoreWitness.lean` `fatalRun_ok` (the run ends `fatal`, kernel),
  `fatal_regression` (the input meets the hypotheses; the old conclusion fails; the run is not
  `blocked`).
- The random smoke (`semsmoke`) behaviour tables now include a fatal base.

## W1: "`acquireN(n ≥ 2)` always raises" satisfied every Semaphore statement

- Fix: after `join i` the harness writes `joinRecV i oc` (`pair (nat 62) (pair (nat i) oc)`) into
  the trace (`HS.joinRec`). Statement 2 now also claims: in a `Succeeded` run, every joined, never
  canceled use whose own code succeeds (`permit` with an `ok` section, `acqRel`, `tryRel`;
  `OkJoined`) has a `Succeeded` record. Statement 5 the same for the mutex.
- Only statements 2 and 5 read the records; they have no user code, so nothing can forge a record.
  In the twin (statement 8) both sides write the same records, so the comparison is stronger.
- Wrong-function check: `w1_breaks` (kernel): on `Semaphore(2)`, `[acqRel 2]`, `[join 0]`, the wrong
  function ends `Succeeded((2, 2))` with the record `Errored(E9)` and no `Succeeded` record; v3.7.1
  records `Succeeded(())`. `semsmoke` "acquireN raises" breaks statement 2 too.

## Low items

- L2: the docstring of `mutexSemaphoreTwin` said "the converse is the same claim with the roles
  swapped; the smoke test samples both". Wrong: the converse is a different claim (not registered),
  and the smoke loop samples only mutex ⊆ semaphore; a miss is printed, not counted. Fixed.
- L4: `docs/std/mutex.md:7-8` → `:6-7` (Props, Registry, `Model/Mutex.lean`, wiki article).
- Witnesses re-proved for statements 2, 5 and 8 (the root of every statement with a `join` act
  changed: the join record). All other witnesses build unchanged.

## Difftest on the merged generator (after 1e84acb)

`opcount.py --seeds 101 102 103 --n 17000 --boost tpl_sem=20 tpl_mutex=20` on the tree that merged
origin/main at 8f462f4 (tracks Q and L, the gen.py/Interp.scala merge fix 1e84acb). The `cediff`
binary does not depend on the statement changes above. Result: 51,000 cases (17,000 per seed), all agree, 0 unsupported. Agreeing cases per op: semNew 28,793;
semAcquireN 15,846; semReleaseN 22,456; semTryAcquireN 10,485; semAvailable 28,793; semCount
28,793; semPermit 19,698; mutexNew 17,502; mutexLock 17,502. (A first start of seeds 101 and 102
failed before any case: three parallel `run.sh` calls rebuilt the sbt class path at once, "Address
already in use"; rerun after the cache existed.) The `parTraverseN` `rankOrder` fix of track G (b838472) came later and is merged (9ca98d6).
After it, the batch of `g61-9094` (seed 61, cases 5000-9999, `--boost tpl_sem=20 tpl_mutex=0`,
regenerated with the merged generator, so the programs also have the track Q/L parts) gives 5,000
of 5,000 agree, `g61-9094` included. Track G keeps the original case as a regression case.

## Note for track L (item 6 of the coordinator; track L owns the file)

The latch harness closures `HLam.mark j s` (writes `Ref 2` / `Ref 0`) and `HLam.incr c` (a data
number `c`) in `Props/Phase7/CountDownLatch.lean` (and the barrier twin) are table lookups by data.
They are safe only because no `HLam` is in `cdlLib`/`cbLib` (`isLibV0` accepts only `CLam`/`BLam`
of variant 0). They must stay out of these libraries; making them public would open a forgery
(user code could write the harness cells). Track S does the same: only `HS.newCell` and
`HS.afterCell` (no handle) are public in `semLib`.

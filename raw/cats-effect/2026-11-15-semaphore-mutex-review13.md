# Track S: review batch 13 items (notes, 2026-11-15)

Own work after `review/2026-11-15-review-batch-13.md` (all 8 Semaphore/Mutex entries FAITHFUL, H2/W2
closed). Two low items.

## L3: factory rows

- New battery operations `semApply` (`Semaphore[IO](k)`: the term `F.ref(...).map(impl.semaphore)`)
  and `mutexApply` (`Mutex[IO]`). Kernel rows: `semApply_raises`, `semApply_hangs` (break
  `std.Semaphore.noDeadlock`: root `Errored` / `blocked`), `mutexApply_raises`, `mutexApply_hangs`
  (break `std.Mutex.lock.noDeadlock`).
- drops/doubles: a factory has no effect besides making the object; no meaning.
- `mapK`, `in`: not mirrored. `MapKSemaphore`/`TransformedMutex` only apply a natural transformation
  to each operation; `in` builds the same `impl`/`ConcurrentImpl` with `Ref.in`. No row.

## O1: reads under contention

- Before: `available` was read only by the root at the end (every fiber ended), and `count` only in
  the FIFO spin, whose exit condition was `count = -target`. A read wrong only while the queue is not
  empty passed (the spin would loop forever, so no run stopped).
- Now: the FIFO spin reads `(available, count)` (`fifoRead`). At every spin step requests wait (no
  permit was released yet, `Semaphore(0)`), so the Scaladoc (`Semaphore.scala:38-53`) promises
  `available = 0` and `count = -(n_1 + ... + n_{i-1})` (before `F_i` enqueued) or
  `-(n_1 + ... + n_i)` (after). No waiter is canceled in this root, so CE-0060 does not apply. Any
  other pair ends the root `Succeeded(Left((available, count)))`, which the claim
  (`Succeeded(r - sum)`) rejects. The statement text is unchanged; the root is stronger.
- Wrong variant "contended": `available` returns `permits + 1`, `count` returns one less, only while
  the waiter queue is not empty (closures `WL.availCont`, `WL.countCont`). Kernel rows:
  `available_contended` (`[1, 1]`, `r = 2`), `count_contended` (`[1]`, `r = 1`); v3.7.1 meets the
  claim on the same inputs (`good_fifo_contended`); both variants meet it at rest
  (`contended_ok_at_rest`, `fifoRoot [] 1`), so only the reads under contention catch them.
- `semFifo_satisfiable` re-proved with the new root (`[2, 1]`, `r = 2`, result `-1`).
- Battery: 46 rows (38 + 4 factory + 2 contended + `count_wrongValue` kept; `good_*` extra).

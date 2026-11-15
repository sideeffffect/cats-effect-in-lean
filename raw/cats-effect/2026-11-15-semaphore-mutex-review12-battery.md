# Track S: review batch 12 fixes and the decision-63 battery (notes, 2026-11-15)

Own work after `review/2026-11-15-review-batch-12.md` (H2 HOLLOW on `std.Semaphore.noDeadlock`, W2 on
`std.Mutex.lock.noDeadlock`) and decision 63 (`raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md`).

## H2 and W2

- The 11b form ("`o.summary ≠ .blocked`" plus claims on `Succeeded` runs) admitted every other
  summary, also a root `Errored`. An `available` that always raises makes every root end `Errored(9)`
  and met every `Semaphore` statement (my 11b fix opened this gap).
- New form of both statements: `(∃ v, Succeeded v ∧ claims) ∨ (∃ e, fatal e)`. For a correct
  semaphore or mutex the root never raises (its own steps do not raise; a join returns the outcome),
  so this is the real promise. Fatal errors stay in the domain.
- `fatal_regression` (H1 input) now shows the `fatal` part holds. `availRaises` (=
  `available_raises`) is the kernel-checked H2 wrong function.
- Witnesses: `semNoDeadlock_satisfiable` and `mutexNoDeadlock_satisfiable` reach the `Succeeded`
  part; they build unchanged with the new statements. `semsmoke` uses the new claims.

## Decision-63 battery

`Proofs/Phase7/SemaphoreBatteryDefs.lean` (wrong functions, closures `WL`, namespace 66) and
`Proofs/Phase7/SemaphoreBattery.lean` (38 `decide +kernel` rows, about 2 min, 2.9 GB; in the
default build). A wrong function replaces one public op as the test program calls it: for
`acquire`/`acquireN`/`release`/`releaseN`/`tryAcquire`/`tryAcquireN` the harness closure that builds
the call (`HS.acqRelBody`, `HS.constRel`, `HS.tryBody`) builds the wrong term; for `available`,
`count`, `permit`, `lock` the library term is replaced wherever a closure returns it. Variants:
raises = `raiseError(E9)` (non-fatal); hangs = `IO.never` (an `IOCont` that is never called back);
drops = no effect; doubles = effect twice (`n` → `2n`; `permit` takes 2; `lock` enqueues itself
twice and waits for itself).

Inputs (default schedule, fuel 3000): `acquire`, `release`: `Semaphore(1)`, `[acqRel 1]`, `[join 0]`;
`acquireN`, `releaseN`: `Semaphore(2)`, `[acqRel 2]`; `tryAcquire`: `Semaphore(2)`, `[tryRel 1]`;
`tryAcquireN`: `Semaphore(4)`, `[tryRel 2]`; `available`, `count`, `permit`: `Semaphore(1)`,
`[permit 0 (ok ())]`; `count` wrong value: FIFO root, no requests, `r = 1`; `lock`: `Mutex`,
`[permit 0 (ok ())]`; `lock` drops: `Mutex`, two counted uses with `cu`, one preemption at step 30.

| op | raises | hangs | drops | doubles |
|---|---|---|---|---|
| acquire (`acquireN(1)`) | noDeadlock (join `Errored`) | noDeadlock (`blocked`) | noDeadlock (available 2 ≠ 1) | noDeadlock (`blocked`: needs 2 of 1) |
| acquireN (`n = 2`) | noDeadlock (join `Errored`) | noDeadlock (`blocked`) | noDeadlock (available 4 ≠ 2) | noDeadlock (`blocked`: needs 4 of 2) |
| release (`releaseN(1)`) | noDeadlock (join `Errored`) | noDeadlock (`blocked`) | noDeadlock (available 0 ≠ 1) | noDeadlock (available 2 ≠ 1) |
| releaseN (`n = 2`) | noDeadlock (join `Errored`) | noDeadlock (`blocked`) | noDeadlock (available 0 ≠ 2) | noDeadlock (available 4 ≠ 2) |
| tryAcquire | noDeadlock (join `Errored`) | noDeadlock (`blocked`) | noDeadlock (`true` without taking: available 3 ≠ 2) | noDeadlock (takes 2: available 1 ≠ 2) |
| tryAcquireN (`n = 2`) | noDeadlock (join `Errored`) | noDeadlock (`blocked`) | noDeadlock (available 6 ≠ 4) | noDeadlock (available 2 ≠ 4) |
| available | noDeadlock (root `Errored`, = `availRaises`) | noDeadlock (`blocked`) | n/a: a read has no effect; checked "wrong value" (+1): noDeadlock (available 2 ≠ 1) | n/a: a read has no effect |
| count | noDeadlock (root `Errored`) | noDeadlock (`blocked`) | n/a: a read has no effect; checked "wrong value" (+1): acquireN.fifo (count 2 ≠ 1) | n/a: a read has no effect |
| permit | noDeadlock (join `Errored`) | noDeadlock (`blocked`) | noDeadlock (available 2 ≠ 1) | noDeadlock (`blocked`: needs 2 of 1) |
| lock | lock.noDeadlock (root `Errored`) | lock.noDeadlock (`blocked`) | lock.mutualExclusion (highest 2) | lock.noDeadlock (`blocked`: waits for itself) |

`acquire`, `release`, `tryAcquire` are the aliases `acquireN(1)`, `releaseN(1)`, `tryAcquireN(1)`
(`Semaphore.scala:76`, `:103`, `:90`); the battery treats them as separate operations by `n`. Each
input also runs on the v3.7.1 mirror and meets the statement (`good_*`, kernel). The `lock` drops
row needs the `WellFormed` hypothesis of `mutualExclusion`: `lockDrops_wf` proves it for the wrong
environment (the wrong function changes only odd-id library closures).

A bug found while building it: the first `lock` drops function returned `.ret` from a `flatMap`
function (the model aborts `illTyped`); fixed to a `map`. Lesson: a wrong function must still be a
well-typed program, or the run aborts and proves nothing.

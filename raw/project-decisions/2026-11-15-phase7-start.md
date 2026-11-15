# Phase 7 start: std structures (2026-11-15)

Source: orchestrator decisions after the Phase 6 gate (`wiki/methodology/phase6-gate-report.md`). Plan: `wiki/methodology/project-plan.md`, "Phase 7 — std structures".

## Decisions

59. Tracks for the first Phase 7 batch (7.1), in parallel worktrees:
    - **Q (Queue):** `std/Queue.scala` both implementation families as twins: the `Concurrent` queues (`BoundedQueue`, `DroppingQueue`, `CircularBufferQueue`, `synchronous`) and the `Async` lock-free queues (`BoundedAsyncQueue`, `UnboundedAsyncQueue`, `UnsafeUnbounded`). The lock-free queues are modelled under sequential consistency first; record this as a model simplification (plan item 3). Codec namespaces 50–59, bug ids CE-0050+.
    - **S (Semaphore, Mutex):** `std/Semaphore.scala`, `std/Mutex.scala` (both `ConcurrentImpl` and `AsyncImpl` as twins), `std/internal` helpers they call. Codec namespaces 60–69, bug ids CE-0060+.
    - **L (latches):** `std/CountDownLatch.scala`, `std/CyclicBarrier.scala`. Codec namespaces 70–79, bug ids CE-0070+.
    Later batches: `Supervisor` → `Dispatcher` → `Hotswap`, `AtomicCell`, `Dequeue`, `PQueue`, `MapRef`.
60. Rules carried from Phase 6 and binding from the start:
    - Every closure, table entry and source code that user code could name is a `Val.fn` reference (decision 58). Plain numbers are data only. Harness markers are odd references or handles that user code never holds.
    - Each non-trivial hypothesis set gets a kernel-checked satisfiability witness (decision 53). Each refutation gets a fixed twin (decision 39) and a Scala reproducer on v3.7.1 and series/3.x.
    - Wrong-function test for each property ("drop an element", "never wake a waiter", "release twice").
    - Twin and heavy modules stay under about 8 GB peak and about 5 min each; CI runs them as matrices (`twin-checks`, `heavy-proofs` are required checks).
    - Difftest first (format v2, new ops added with their own random stream as track G did for `parTraverseN`, so no other op's coverage changes): 100% agreement on ≥ 50,000 cases over ≥ 3 seeds per new op before any property.
61. Shared files (decision 52 still applies): each track adds its own modules; shared files (`CatsEffectInLean.lean`, `Registry.lean`, `inventory.csv`, `gen.py`, `Prog.lean`, `ci.yml`, wiki index and log) get append-only edits; the orchestrator merges. Each track merges `origin/main` before it reports.
62. Properties to state first (plan item 2): no lost and no duplicated element or permit under any cancel interleaving; no lost wakeup; FIFO where the Scaladoc promises it; linearizability against a sequential spec; no deadlock; liveness of waiters under fair schedules where the condition holds; finalizers once; no leaked fiber.

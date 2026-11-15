# Decision 63: standard wrong-function battery per structure (2026-11-15)

Source: orchestrator decision after review batches 11b (W1) and 12 (H2, H3).

## Facts

- Three findings in a row had the same shape: an operation that always raises (or always errors the root) satisfied every registered statement of its structure:
  - W1 (batch 11b): `Semaphore.acquireN(n ≥ 2)` always raises;
  - H2 (batch 12): `Semaphore.available` always raises after the "not blocked" restatement;
  - H3 (batch 12): `Queue.synchronous` `take` always raises.
- Each was found by a reviewer, one at a time. Statements about safety ("nothing lost", "not blocked") are true for an implementation that does nothing useful.

## Decision

1. For every structure, the registered statements together must reject a standard battery of wrong functions, one per public operation:
   - **raises:** the operation always raises a non-fatal error;
   - **hangs:** the operation never returns (`never`);
   - **drops:** the operation returns but skips its effect (no element added, no permit released, no count decremented);
   - **doubles:** the operation applies its effect twice.
   Where a variant is meaningless for an operation, say why in the notes.
2. Each battery member must break at least one registered statement of that structure, kernel-checked on one input (as `w1_breaks`). Record the table: operation × variant → breaking statement.
3. A "not blocked" or "nothing lost" statement needs a companion success claim: in a run without cancels and without user errors, every joined operation whose precondition holds ends `Succeeded`.
4. Reviewers check the table. A missing row is a HOLLOW reason for the structure's entries.

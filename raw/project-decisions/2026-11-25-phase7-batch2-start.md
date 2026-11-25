# Phase 7 batch 7.2 start (2026-11-25)

Source: orchestrator decision after the batch 7.1 gate passed (`raw/project-decisions/2026-11-25-phase7-batch1-gate-passed.md`).

64. Batch 7.2 has 2 tracks only (token budget), in parallel worktrees:
    - **V (Supervisor):** `std/Supervisor.scala` (both `await = true` and `await = false`, and the `checkRestart` restart path). Codec namespaces 80–89, bug ids CE-0080+.
    - **P7D (Dispatcher):** `std/Dispatcher.scala` (`parallel` and `sequential`, `await = true/false`). Codec namespaces 90–99, bug ids CE-0090+.
    `Hotswap`, `AtomicCell`, `Dequeue`, `PQueue`, `MapRef` go to batch 7.3.
65. Decisions 58, 60–63 apply from the start: `Val.fn` references, satisfiability witnesses, a complete wrong-function battery (each public operation and factory × raises, hangs, drops, doubles; honest drops), difftest ≥ 50,000 cases over ≥ 3 seeds per new op before a property.

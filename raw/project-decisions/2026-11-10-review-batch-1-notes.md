# Review batch 1: verdicts on the first 5 registry entries (own note)

> Source: independent read-only review in this repository (`CatsEffectInLean/Registry.lean`, `Props/IO/MonadCancelLaws.lean`, `Proofs/IO/MonadCancelLaws.lean`, `Props/Calibration/SyncStep.lean`, `Proofs/Calibration/SyncStep.lean`, `Model/{Step,Outcomes,IOInstance,SyncStep,Run,Syntax}.lean`, `bugs/CE-0001.yaml`, `reproducers/CE-0001/Repro.scala`); Cats Effect source at v3.7.1 (`IO.scala`, `IOFiber.scala`, `SyncIO.scala`, `MonadCancelLaws.scala`, `MonadCancelTests.scala`, `AsyncLaws.scala`, `TestInstances.scala`). Full review: `review/2026-11-10-review-batch-1.md`.
> Collected: 2026-11-10
> Published: 2026-11-10

## Verdicts

| Entry | Status | Verdict |
|---|---|---|
| `canceledAssociatesLeftOverFlatMap.IO` | proven | FAITHFUL (low strength: `fa` never runs) |
| `forceRCanceledShortCircuits.IO` | proven | FAITHFUL (low strength) |
| `onCancelAssociatesOverUncancelableBoundary.IO` | open | FAITHFUL as a statement |
| `uncancelablePollIsIdentity.IO` | open | HOLLOW as a statement |
| `syncStepIdentitySyncIO` (CE-0001) | refuted | HOLLOW (the bug itself is real) |

## Main findings

- CE-0001 property quantifies over schedules with external cancel (`SoloChoice.cancel`). Then a correct `syncStep` also refutes it: `fa = IO.delay(flag.set(true))`, direct run canceled before start gives `flag = false`; the stepped run always has `flag = true` (the `SyncIO` prefix ran). Fix: cancel-free schedules (or `Eqv`). The existing proof should carry over.
- `uncancelablePollIsIdentity`: the two sides differ by 2 run-loop iterations. Task switches happen only at `cede`, async, and auto-yield, so with a forked fiber the trace sets can differ. Also, the domain includes forged ids (child cancels fiber 0). Neither is a Cats Effect defect.
- Citations: all spot-checked citations were correct.

## Wider concerns

1. The quantification domain (`fa : IO`, `env`) is larger than Scala (runtime-only terms, forged fiber/poll/cont ids, full `View`). Fix: quantify over difftest programs via `Translate.tr`, or a `WellFormed` predicate.
2. `Eqv` sees run-loop iteration counts (auto-yield placement).
3. Two observation designs (`Eqv` vs CE-0001 `Obs`).
4. Divergence gives no observation.
5. Single-fiber driver never runs children.
6. `SyncIO` and `syncStep` have no difftest.
7. Open entries already mark inventory rows `modelled`.
8. CE-0001 lists 27 rows; the witness exercises only a few of them.

# Decision 66: Dispatcher mirror after the Supervisor mirror (2026-11-25)

- Track P7D found CE-0090 (parallel `Dispatcher` loses a submission made during release) and reproduced it on v3.7.1, series/3.x `de84c01` and series/3.7.x. `lean.status: pending`.
- An exact-replay difftest of `Dispatcher` needs an exact `Supervisor` mirror. Track V writes it now.
- Decision (orchestrator; Q6 is sequencing, not a user decision): the Dispatcher mirror, difftest ops, properties, witnesses and battery start after track V's `Supervisor` module is on `main`. CE-0090 counts as a bug candidate with a reproducer only; it gets no `refuted` registry entry until the Lean refutation and a fixed twin exist. Batch 7.2 does not pass its gate without the Dispatcher entries.
- Track P7D's `check_twin_checks.sh` exit 1 (output lost) is unexplained; the branch changes no Lean, difftest or CI file. CI on the merge commit decides.

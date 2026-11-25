# Decision 67: deterministic identity hashes in the difftest JVM (2026-11-25)

- Problem: `Supervisor` keeps its children in a `ConcurrentHashMap`. Its iteration order comes from identity hashes, which by default depend on the earlier cases in the same JVM. CI run `45558902125` on `7070a40` failed: "Difftest runner (Scala)", 11 `supervisor.jsonl` cases. The orchestrator pushed `7070a40` without a local Scala runner test (process miss: run the Scala `test` step before each push that touches difftest files).
- Fix (track P7D): `difftest/run.sh` and the forked test JVM use `-XX:+UnlockExperimentalVMOptions -XX:hashCode=2` (all identity hashes equal; map order follows insertion order). `supervisor.expected.jsonl` regenerated (7 lines); all other golden files are byte-identical.
- Why this is not a weaker gate: the comparison is still refinement (each Scala outcome must be in the Lean outcome set). The Lean model still allows every map order (up to 5 entries). The flag only makes the Scala side reproducible. It does not change Cats Effect code.
- Cost: the Scala side now shows one map order only. Other orders stay covered by the Lean outcome set, not by Scala runs. Bug reproducers do not use the flag.
- Review item: with this flag, track V's cap of 5 `supervise` calls per scenario may no longer be needed.

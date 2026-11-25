# Track P7D: identity-hash order of the `Supervisor` map in the difftest (2026-11-25)

Source: own runs. Do not edit.

- `Supervisor[IO]` keeps its fibers in a `ConcurrentHashMap[Unique.Token, Fiber]`; `Unique.Token`
  has the default identity `hashCode`. HotSpot's default identity hash (`hashCode=5`) is a
  per-thread xorshift sequence, so the iteration order of `joinAll`/`cancelAll` depends on how many
  identity hashes the thread made before, i.e. on the earlier cases of the same JVM batch.
- Effects seen: (1) `CasesSuite` (`sbt test`) fails 11 `supervisor.jsonl` cases on `origin/main`
  (7070a40) and 9-11 on the P7D branch (the golden file was made by `run.sh` on that file alone);
  (2) `selftest.py` coverage run: a prefix violation in `g20261110-314` (a track V scenario, no
  Dispatcher op) once the Dispatcher template is on (`p_disp = 0`: none); (3) four random cases with
  both a `Supervisor` and a `Dispatcher` scenario disagree (two maps; the Lean alternatives use one
  permutation for all maps); `g91-21111` agrees alone and disagrees inside a batch.
- Fix: `run.sh` and the golden-test JVM (`build.sbt`: `Test / fork`, `Test / javaOptions`) run with
  `-XX:+UnlockExperimentalVMOptions -XX:hashCode=2` (every identity hash is 1). The map then
  iterates in insertion order in every batch and JVM; the Lean alternatives include the insertion
  order. With it: every golden file byte-identical except `supervisor.expected.jsonl` (7 lines,
  regenerated); `sbt test` 1173/1173; `selftest.py` passes (no prefix violation; blocked + fuel
  24.8%); fixed-case agreement 1179 agree + 2 unsupported (as before).
- The self-test bound "blocked + fuel < 25%" was at 25.0% with the Dispatcher template: one case
  with `maxSteps = 4` (`p_small_maxsteps`) turned from `succeeded` into `fuel`. The template is now
  not appended to cases with `maxSteps ≤ 5` (it cannot run there).
- Not tried: a per-map permutation on the Lean side (needs a map id in track V's `ho`).

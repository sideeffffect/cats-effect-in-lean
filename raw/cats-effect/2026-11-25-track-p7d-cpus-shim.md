# Track P7D: `Cpus` shim instead of a JVM flag (2026-11-25)

Source: own runs. Do not edit.

- The difftest first ran the Scala JVM with `-XX:ActiveProcessorCount=1` (`run.sh`) so that
  `Dispatcher` has one worker. The self-test (`selftest.py`, coverage, seed 20261110, 600 cases)
  then failed: 2 prefix violations, both in case `g20261110-314` (a track V `Supervisor` scenario,
  no Dispatcher op). With `p_disp = 0` still 2; without the flag 0. The flag changes the JVM (GC,
  compiler threads), so the identity-hash order of the `Supervisor` map differs between the full
  run's batch and the prefix runs' batch.
- Fix: `difftest/src/main/scala/cats/effect/std/DispatcherShim.scala` sets the
  `static final int cats$effect$std$Dispatcher$$$Cpus` (from `javap -p` of `Dispatcher$.class`) to
  1 with `sun.misc.Unsafe` right after class initialization, before any Dispatcher code runs; `dUse`
  checks the value. `run.sh` is again as on `main`. The 68 fixed cases give byte-identical Scala
  output with the flag and with the shim.
- The 114,000-case random run of part 2 ran with the flag; the Dispatcher ops behave the same
  (Cpus = 1 either way); the CI-shaped run (`drive.py run --seeds 1 2 3 --n 2000`) and the fixed
  cases were rerun with the shim.

# CE-0060 independent re-run by track L (batch 7.1 gate, condition C3), 2026-11-15

Source: own run.

- `scripts/run_reproducers.sh CE-0060` (scala-cli) on Cats Effect v3.7.1: last line
  `REPRODUCED CE-0060`, exit 0. Output identical to track S's record.
- series/3.x: head `de84c01f76b2f42fcee9d43aba66c82992add103` (checked with `gh api` on
  2026-11-15). Own snapshot, independent of track S's `3.7.1-89-de84c01`: the GitHub tarball of
  that commit in a scratch directory, published locally as `3.7.1-trackL-de84c01`
  (`++3.3.7 kernelJVM/publishLocal stdJVM/publishLocal coreJVM/publishLocal
  kernelTestkitJVM/publishLocal testkitJVM/publishLocal`, version set explicitly). Last line
  `REPRODUCED CE-0060`, exit 0, same output. `~/Projects/cats-effect` was not touched.
- The reproducer has no fixed copy (only `reproducers/CE-0060/Repro.scala`).
- Gotcha: the Cats Effect build (sbt-typelevel) fails without a repository ("not a git
  repository"). A tarball build needs a local repository with one commit and a tag `v3.7.1`;
  then `set ThisBuild / version := ...` gives a distinct version.
- Output recorded in `bugs/CE-0060.yaml`, keys `v3.7.1-rerun-trackL`, `series/3.x-rerun-trackL`.

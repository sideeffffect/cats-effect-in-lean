# Reproducers

One Scala program for each bug record: `reproducers/<bug-id>/Repro.scala`, run with `scala-cli`.

- Pin Cats Effect `3.7.1` with `//> using dep` directives (`cats-effect` and, if needed, `cats-effect-testkit`). Write the version exactly as `:3.7.1` at the end of the line, so that `scripts/run_reproducers.sh` can replace it.
- Use Scala 3 (`//> using scala 3.3.7`) and only the public API.
- Make the run deterministic. Use `TestControl` (virtual time). For a race, search a fixed range of `TestControl` seeds and print how many seeds show the bug.
- The last line of output must be `REPRODUCED <bug-id>` when the bug shows, and `NOT REPRODUCED <bug-id>` when it does not.
- On v3.7.1 the last line must be `REPRODUCED <bug-id>`.
- Also run it on the latest `series/3.x` and `series/3.7.x` (decision 1 in `raw/project-decisions/2026-11-10-phase0-decisions.md`). Record all outputs in the bug record (field `output`).

## Run

```
scripts/run_reproducers.sh                       # all, on 3.7.1; exit 1 if one does not print REPRODUCED
scripts/run_reproducers.sh CE-0002               # one id
CE_VERSION=<version> scripts/run_reproducers.sh  # other version, for example a publishLocal snapshot
```

## Snapshots of `series/3.x` and `series/3.7.x`

Build them in a separate worktree of `~/Projects/cats-effect`. Do not change the HEAD of the v3.7.1 checkout.

```
git -C ~/Projects/cats-effect fetch origin
git -C ~/Projects/cats-effect worktree add --detach ~/Projects/cats-effect-wt/series-3.x origin/series/3.x
cd ~/Projects/cats-effect-wt/series-3.x
sbt "++3.3.7" kernelJVM/publishLocal stdJVM/publishLocal coreJVM/publishLocal \
    kernelTestkitJVM/publishLocal testkitJVM/publishLocal
```

The version is the git-derived sbt `version`, for example `3.7.1-89-de84c01`. `scala-cli` finds it in `~/.ivy2/local`.

The script is not in CI yet: the first `scala-cli` run downloads a JVM, Scala and Cats Effect.

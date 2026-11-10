# Pinned Cats Effect version: v3.7.1

> Sources: typelevel/cats-effect GitHub releases, 2026-08-23; build.sbt at v3.7.1
> Raw: [v3.7.1 release notes](../../raw/cats-effect/2026-08-23-cats-effect-v3-7-1-release-notes.md); [v3.7.0 release notes](../../raw/cats-effect/2026-03-08-cats-effect-v3-7-0-release-notes.md); [v3.6.4 release notes](../../raw/cats-effect/2026-08-22-cats-effect-v3-6-4-release-notes.md)

## Overview

The project formalizes **Cats Effect v3.7.1** and only that version. It is the latest stable release as of 2026-11-10 (GitHub "Latest"; verified with `gh release list` on 2026-11-10). Decision: stick to it until the user decides to re-pin.

## Facts

| Item | Value |
|---|---|
| Tag | `v3.7.1` |
| Commit | `eb0cc258fc732fc37f22f117c2e81d5554d67024` |
| Published | 2026-08-23 |
| Scala | 2.12.20, 2.13.18, 3.3.4 |
| Platforms | JVM, Scala.js 1, Scala Native 0.5 |
| cats | 2.13.0 |
| Branch | `series/3.x` (default); no 4.x branch or milestone exists |
| Local checkout | `~/Projects/cats-effect`, detached at `v3.7.1` |

Other releases: v3.6.4 (2026-08-22, last 3.6.x), v3.7.0 (2026-03-08, Scala Native multithreading + work-stealing pool on Native), v3.7.0-RC1 (2025-07-30, latest pre-release). Open milestones: v3.8.0, v3.7.next, v3.6.next.

## Rules that follow from the pin

- Cite source as `path:line` at tag v3.7.1.
- A bug counts if it reproduces on v3.7.1. Also check `series/3.x` HEAD before filing, to catch already-fixed bugs (python-formalization and julia-in-lean both check release + main).
- Known open bugs that reproduce on v3.7.1 (e.g. #4687, #4674, #4571) are good calibration targets: a faithful model must be able to refute the corresponding property.
- A future re-pin needs a worklist like python-formalization's `repin.py`: reset changed rows to `todo`, archive old reviews.

## See Also

- [Source layout](source-layout.md)
- [Semantics of CE3](semantics.md)
- [Bug history](bug-history.md)

# Cats Effect v3.7.1 release notes (latest stable as of 2026-11-10)

> Source: https://github.com/typelevel/cats-effect/releases/tag/v3.7.1
> Collected: 2026-11-10
> Published: 2026-08-23

Release metadata (collected via `gh release list`, `git`, Maven Central):
- Tag: v3.7.1. Commit: eb0cc258fc732fc37f22f117c2e81d5554d67024 ("Merge pull request #4663 from typelevel/release/3.6.4-major", commit date 2026-08-23 13:15:05 -0500). GitHub release published 2026-08-23T19:19:52Z, marked "Latest".
- build.sbt at tag: Scala212 = "2.12.20", Scala213 = "2.13.18", Scala3 = "3.3.4"; crossScalaVersions = Seq(Scala3, Scala212, Scala213). Platforms: JVM, Scala.js 1 (sjs1), Scala Native 0.5 (native0.5). CatsVersion = "2.13.0".
- Maven Central: cats-effect_2.12, _2.13, _3, _sjs1_3, _native0.5_3 all have 3.7.1 POMs (HTTP 200).
- Previous stable: v3.6.4 (2026-08-22, maintenance on 3.6.x), v3.7.0 (2026-03-08). Latest pre-release: v3.7.0-RC1 (2025-07-30). No newer tag than v3.7.1 exists as of 2026-11-10.
- Branches: default branch series/3.x (head de84c01f 2026-09-28); series/3.7.x exists. No series/4.x branch. GitHub milestones open: v3.8.0 (18 open / 2 closed), v3.7.next, v3.6.next. No 4.x milestone.

---

This is the sixty-first release in the Cats Effect 3.x lineage. It is fully binary compatible with every 3.x release and fully source-compatible with the 3.7.x lineage.

## What's Changed
### Enhancements
* Rewrote `parTraverseN` and `parTraverseN_` for better performance by @djspiewak in https://github.com/typelevel/cats-effect/pull/4451
* Derive MaxEvents from PollingTicks in Epoll and Kqueue polling systems by @antoniojimeneznieto in https://github.com/typelevel/cats-effect/pull/4603
* O(1) cancelation for Semaphore and MiniSemaphore by @stasimus in https://github.com/typelevel/cats-effect/pull/4648
### Bug Fixes
* Fix memory leak in `Supervisor` internal state by @durban in https://github.com/typelevel/cats-effect/pull/4500
* Fix scaladoc links in IOApp by @durban in https://github.com/typelevel/cats-effect/pull/4562
* Workaround #4524 by synchronizing tasks set by @armanbilge in https://github.com/typelevel/cats-effect/pull/4569
* Fix issue #4489 by @durban in https://github.com/typelevel/cats-effect/pull/4625
* Fix `Ticker` @implicitNotFound message to reference testkit-available API by @mvanhorn in https://github.com/typelevel/cats-effect/pull/4592
* Fix ownsPoller and ownsTimers for blocking threads by @durban in https://github.com/typelevel/cats-effect/pull/4631
### Documentation
* Update weaver with typelevel org by @lenguyenthanh in https://github.com/typelevel/cats-effect/pull/4476
* Add FAQ on imports by @mtomko in https://github.com/typelevel/cats-effect/pull/4534
* Mention system property in docs that enable blocked thread detection by @rochala in https://github.com/typelevel/cats-effect/pull/4582
* Fix MonadCancel scaladoc by @reardonj in https://github.com/typelevel/cats-effect/pull/4629
### Behind the Scenes
* Switch to `windows-2022` runner tag by @samspills in https://github.com/typelevel/cats-effect/pull/4470
* Actually run JVM `IOApp` tests in CI by @armanbilge in https://github.com/typelevel/cats-effect/pull/4518
* Updated site script for scastie API changes by @djspiewak in https://github.com/typelevel/cats-effect/pull/4567
* Removed CirrusCI by @djspiewak in https://github.com/typelevel/cats-effect/pull/4660

## New Contributors
* @rochala made their first contribution in https://github.com/typelevel/cats-effect/pull/4582
* @mvanhorn made their first contribution in https://github.com/typelevel/cats-effect/pull/4592
* @stasimus made their first contribution in https://github.com/typelevel/cats-effect/pull/4648

**Full Changelog**: https://github.com/typelevel/cats-effect/compare/v3.7.0...v3.7.1

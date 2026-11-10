# Cats Effect v3.6.4 release notes

> Source: https://github.com/typelevel/cats-effect/releases/tag/v3.6.4
> Collected: 2026-11-10
> Published: 2026-08-22

This is the sixtieth release in the Cats Effect 3.x lineage. It is fully binary compatible with every 3.x release and fully source-compatible with the 3.6.x lineage. Barring critical security vulnerabilities, this will be our last release in the 3.6.x lineage, which also means this will be our last release targeting Scala Native 0.4.x.

> [!WARNING]
> Please note that Cats Effect 3.6.x is targeting Scala Native 0.4.x, which means it does not at present support native multithreading. This was a very intentional choice meant to give us an opportunity to break binary compatibility *only on Scala Native* if necessary when upgrading to Scala Native 0.5 and as we discover the impacts of the integrated runtime on the downstream ecosystem. It also reduces risk since Native multithreading in the runtime is a significant lift and we want to make sure we isolate that change from the already significant changes in 3.6.0. This functionality has already merged into the development branch and we plan to release it in 3.7.0 as soon as possible.

## What's Changed

The most significant change in this release is a fix for a resource leak arising from timeouts on `Resource`s. This was commonly experienced in applications built on top of Http4s and could have a number of negative consequences. An additional significant change is a full rewrite of `parTraverseN` and `parTraverseN_`, eliminating a class of pathological performance degradation when a traversal errors or is canceled. We have more work to do on this function, but that will be released in the 3.7.x line.

### Enhancements
* Implement PollerMetrics for EpollSystem by @antoniojimeneznieto in https://github.com/typelevel/cats-effect/pull/4335
* Implement PollerMetrics for KqueueSystem by @antoniojimeneznieto in https://github.com/typelevel/cats-effect/pull/4336
* Rewrote `parTraverseN` and `parTraverseN_` for better performance by @djspiewak in https://github.com/typelevel/cats-effect/pull/4451

### Bug Fixes
* Fix memory leak in `Supervisor` internal state by @durban in https://github.com/typelevel/cats-effect/pull/4500
* Fix scaladoc links in IOApp by @durban in https://github.com/typelevel/cats-effect/pull/4562
* Fix issue #4489 by @durban in https://github.com/typelevel/cats-effect/pull/4625

### Documentation
* Update weaver with typelevel org by @lenguyenthanh in https://github.com/typelevel/cats-effect/pull/4476
* Add FAQ on imports by @mtomko in https://github.com/typelevel/cats-effect/pull/4534

### Behind the Scenes
* Switch to `windows-2022` runner tag by @samspills in https://github.com/typelevel/cats-effect/pull/4470
* Actually run JVM `IOApp` tests in CI by @armanbilge in https://github.com/typelevel/cats-effect/pull/4518

**Full Changelog**: https://github.com/typelevel/cats-effect/compare/v3.6.3...v3.6.4

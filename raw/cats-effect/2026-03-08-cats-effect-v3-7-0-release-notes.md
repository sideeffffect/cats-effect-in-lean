# Cats Effect v3.7.0 release notes

> Source: https://github.com/typelevel/cats-effect/releases/tag/v3.7.0
> Collected: 2026-11-10
> Published: 2026-03-08

This is the fifty-ninth release in the Cats Effect 3.x lineage. It is fully binary compatible with every 3.x release and fully source-compatible with the 3.7.x lineage.

## What's Changed

This is a relatively smaller minor release jump relative to 3.6.x since it contains a major and long-anticipated enhancement: support for Scala Native 0.5, including full multithreading on LLVM! This has been a very long time coming, and we've been planning how to provide this support and planting the seeds for several years now. As noted in previous release notes, the integrated runtime released in 3.6.0 provides the basic building blocks for true, practically usable multithreaded asynchronous I/O on LLVM, and this release finally brings all of those pieces to fruition.

Full support has been implemented for `epoll` and `kqueue`, and we intend to extend this support to `io_uring` in the future. These polling systems have been significantly upgraded and enhanced since 3.6.x in order to support the same sort of thread coordination that has been present on the JVM from the beginning.

Of course, the largest piece of this is the `WorkStealingThreadPool` itself. This was ported from JVM-only to cross-build entirely on both JVM and LLVM targets. Surprisingly, almost no changes were required to make this possible! **It is a testament to the thought and effort which went into Scala Native 0.5 that this port was dramatically smoother and less complex than anyone could have reasonably predicted.** While we did run into a few minor issues with Scala Native, only one major problem with its multithreading support was encountered, and it only applies in a very niche scenario which was easily worked around.

We really cannot stress enough how impressed we are with Scala Center and Virtus' work on this front. Scala Native 0.5 is quite the triumph, and Cats Effect 3.7 is the proof. Going forward, you should essentially expect rough parity between scheduling functionality on JVM and LLVM, with JavaScript now being the unusual one (due to its single-threaded nature).

As an aside, it's worth noting that this parity holds despite the fact that Scala Native actually implements subtly different memory publication semantics than the JVM in some very specific circumstances. The Cats Effect concurrency state model (i.e. `Ref`/`Deferred`) is such that these semantic differences are entirely invisible in userspace, while the performance benefits are present regardless. This is one example of the careful planning and coordination which went into this release spanning across many people and multiple projects.

The one area in which Cats Effect on Scala Native meaningfully lags behind the JVM is fiber tracing. This functionality *should* exist on LLVM, but it appears that the APIs do not work correctly at runtime. It is expected that these bugs will be resolved in a future Scala Native release, at which point we'll be able to enable the functionality in Cats Effect.

### Enhancements
* Add `SecureRandom` instance to `SyncIO` companion by @qxrein in https://github.com/typelevel/cats-effect/pull/4324
* Add `realTimeZonedDateTime` to `Clock` JVM extensions by @mmienko in https://github.com/typelevel/cats-effect/pull/4316
* Add support for Native multithreaded execution by @durban in https://github.com/typelevel/cats-effect/pull/4201
* `blocking` and `interruptible` on Scala Native by @djspiewak in https://github.com/typelevel/cats-effect/pull/4378
* Add `IOLocal#asLocal[F[_]]:Local[F,A]` by @NthPortal in https://github.com/typelevel/cats-effect/pull/4438
* Add `awaitEvent` to expose the full featureset of kqueue by @rahulrangers in https://github.com/typelevel/cats-effect/pull/4423
* Add IORuntime#liveFiberSnapshot by @iRevive in https://github.com/typelevel/cats-effect/pull/4444
* Add a TestConsole by @morgen-peschke in https://github.com/typelevel/cats-effect/pull/4394
* Add NonEmptyHotswap by @morgen-peschke in https://github.com/typelevel/cats-effect/pull/4267
* Add `KeyedMutex` by @BalmungSan in https://github.com/typelevel/cats-effect/pull/4065
* Implement PollerMetrics for EpollSystem by @antoniojimeneznieto in https://github.com/typelevel/cats-effect/pull/4335
* Implement PollerMetrics for KqueueSystem by @antoniojimeneznieto in https://github.com/typelevel/cats-effect/pull/4336
* Add `AtomicMap` by @BalmungSan in https://github.com/typelevel/cats-effect/pull/4424
* Sync `SyncIO.realTime*` methods with `Clock` implementation by @satorg in https://github.com/typelevel/cats-effect/pull/4522
* Add derivation of `LiftIO` from `LiftValue` by @NthPortal in https://github.com/typelevel/cats-effect/pull/4481
* SecureRandom.javaSecuritySecureRandom for two effect types by @dpevunov-cp in https://github.com/typelevel/cats-effect/pull/4338
* Add `Lift{Value,Kind}` instances for `Resource` by @NthPortal in https://github.com/typelevel/cats-effect/pull/4478
### Bug Fixes
* Don't expose private WSTP type in method signature by @armanbilge in https://github.com/typelevel/cats-effect/pull/4290
* Fix wstp shutdown interrupt (3.x edition) by @djspiewak in https://github.com/typelevel/cats-effect/pull/4344
* Make `IOFiber#{_join,_cancel}` volatile on Native by @durban in https://github.com/typelevel/cats-effect/pull/4400
* Removed `IORuntimeBuilder#addPoller` on Scala.js by @djspiewak in https://github.com/typelevel/cats-effect/pull/4419
* Use _exit instead of System.exit in fatal cases by @djspiewak in https://github.com/typelevel/cats-effect/pull/4428
* Make the heap in `TimerHeap` volatile on native by @armanbilge in https://github.com/typelevel/cats-effect/pull/4443
### Documentation
* docs: provide an example on how to collect fiber dump programmatically by @iRevive in https://github.com/typelevel/cats-effect/pull/4399
* code snippet typo in faq.md by @combinatorist in https://github.com/typelevel/cats-effect/pull/4395
* Fix typo in documentation of function tryOfferN of QueueSink and PQueueSink. by @nmichael44 in https://github.com/typelevel/cats-effect/pull/4384
* Change tutorial CopyFile object name by @davidsalter in https://github.com/typelevel/cats-effect/pull/4458
* Fix identity in Ref documentation by @reardonj in https://github.com/typelevel/cats-effect/pull/4466
* Clarify how `MapRef` can be total by @mtomko in https://github.com/typelevel/cats-effect/pull/4475
* Update weaver-test organization in docs by @zainab-ali in https://github.com/typelevel/cats-effect/pull/4499
* Tweak fiber names in `IOLocal` doc by @japgolly in https://github.com/typelevel/cats-effect/pull/4551
### Behind the Scenes
* Update scalafmt-core to 3.8.4 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4235
* Update sbt-scalafix to 0.14.0 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4237
* Update sbt-typelevel to 0.7.6 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4243
* Update scalafmt-core to 3.8.5 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4242
* Update scala-library to 2.13.16 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4239
* Update scalafmt-core to 3.8.6 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4251
* Update sbt-scalajs, scalajs-compiler, ... to 1.18.2 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4249
* Update sbt-typelevel to 0.7.7 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4252
* Revert documentation format changes by @mzuehlke in https://github.com/typelevel/cats-effect/pull/4246
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4258
* Update scala3-library, ... to 3.3.5 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4261
* Update sbt-mdoc to 2.6.3 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4265
* Update scalafmt-core to 3.9.1 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4278
* Update sbt-scalafix to 0.14.2 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4275
* Update sbt-mdoc to 2.6.4 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4272
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4281
* Backport v3.6.0-RC2 changes by @djspiewak in https://github.com/typelevel/cats-effect/pull/4282
* Replace specs2 with munit by @iRevive in https://github.com/typelevel/cats-effect/pull/4216
* Update scalafmt-core to 3.9.2 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4284
* Update sbt, scripted-plugin to 1.10.8 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4285
* Update sbt, scripted-plugin to 1.10.9 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4286
* Update sbt, scripted-plugin to 1.10.10 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4288
* Update scalafmt-core to 3.9.3 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4294
* Update scalafmt-core to 3.9.4 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4297
* Update sbt-mdoc to 2.6.5 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4304
* Update sbt, scripted-plugin to 1.10.11 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4303
* Merge changes from 3.6.0 into series/3.x by @djspiewak in https://github.com/typelevel/cats-effect/pull/4312
* fix: Nix development Enviroment & Readme Fix by @qxrein in https://github.com/typelevel/cats-effect/pull/4298
* Replace deprecated commands in build.sbt by @iRevive in https://github.com/typelevel/cats-effect/pull/4339
* Update cats-core, cats-free, ... to 2.13.0 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4356
* Merge changes from 3.6.1 into series/3.x by @armanbilge in https://github.com/typelevel/cats-effect/pull/4364
* Update sbt-scalafix to 0.14.3 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4403
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4327
* Update sbt, scripted-plugin to 1.11.0 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4413
* Update sbt, scripted-plugin to 1.11.1 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4416
* Update sbt-typelevel to 0.8.0 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4417
* Update sbt, scripted-plugin to 1.11.2 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4420
* Update sbt, scripted-plugin to 1.11.3 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4427
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4414
* Merge changes from 3.6.2 into series/3.x by @djspiewak in https://github.com/typelevel/cats-effect/pull/4436
* Update versions for 3.6.3 by @djspiewak in https://github.com/typelevel/cats-effect/pull/4452
* Merge changes from 3.6.3 into series/3.x by @djspiewak in https://github.com/typelevel/cats-effect/pull/4453
* Update sbt-mdoc to 2.7.2 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4441
* Backport more recent changes from series/3.6.x by @djspiewak in https://github.com/typelevel/cats-effect/pull/4459
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4461
* Update sbt, scripted-plugin to 1.11.4 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4467
* Update cats-mtl, cats-mtl-laws to 1.6.0 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4472
* Update sbt, scripted-plugin to 1.11.5 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4477
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4480
* Update sbt, scripted-plugin to 1.11.6 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4485
* Update scalacheck to 1.19.0 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4484
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4491
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4521
* Update sbt, scripted-plugin to 1.11.7 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4496
* scala-native 0.5.9 by @durban in https://github.com/typelevel/cats-effect/pull/4510
* scala 3.3.7 by @durban in https://github.com/typelevel/cats-effect/pull/4519
* Update scalafmt-core to 3.9.10 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4536
* Update sbt-jmh to 0.4.8 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4492
* Update sbt-typelevel to 0.8.4 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4533
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4537
* Update auxlib, clib, javalib, nativelib, ... to 0.5.10 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4545
* Update scalafmt-core to 3.10.4 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4544
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4547
* flake.lock: Update by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4558
* Update sbt-typelevel to 0.8.5 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4555
* Update scalafmt-core to 3.10.7 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4552
* Upgrade all the things (take 3?) by @djspiewak in https://github.com/typelevel/cats-effect/pull/4563
* Update scala-library to 2.13.18 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4528
* Update sbt-mdoc to 2.8.2 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4535
* Update sbt-scalajs, scalajs-compiler, ... to 1.20.2 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4542
* Update sbt-scalafix to 0.14.6 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4557
* Update scala-library to 2.12.21 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4530
* Update munit-scalacheck to 1.2.0 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4486
* Update sbt, scripted-plugin to 1.12.5 in series/3.x by @typelevel-steward[bot] in https://github.com/typelevel/cats-effect/pull/4559
### Uncategorized
* Revert "fix: Nix development Enviroment & Readme Fix" by @djspiewak in https://github.com/typelevel/cats-effect/pull/4376
* Fix source compatibility with Scala 3.6 by @mbovel in https://github.com/typelevel/cats-effect/pull/4381
* SN 0.5.6 -> 0.5.7 -> 0.5.8 by @durban in https://github.com/typelevel/cats-effect/pull/4362

## New Contributors
* @mmienko made their first contribution in https://github.com/typelevel/cats-effect/pull/4316
* @mbovel made their first contribution in https://github.com/typelevel/cats-effect/pull/4381
* @combinatorist made their first contribution in https://github.com/typelevel/cats-effect/pull/4395
* @nmichael44 made their first contribution in https://github.com/typelevel/cats-effect/pull/4384
* @NthPortal made their first contribution in https://github.com/typelevel/cats-effect/pull/4438
* @morgen-peschke made their first contribution in https://github.com/typelevel/cats-effect/pull/4394
* @davidsalter made their first contribution in https://github.com/typelevel/cats-effect/pull/4458
* @reardonj made their first contribution in https://github.com/typelevel/cats-effect/pull/4466
* @zainab-ali made their first contribution in https://github.com/typelevel/cats-effect/pull/4499
* @dpevunov-cp made their first contribution in https://github.com/typelevel/cats-effect/pull/4338
* @japgolly made their first contribution in https://github.com/typelevel/cats-effect/pull/4551

**Full Changelog**: https://github.com/typelevel/cats-effect/compare/v3.6.3...v3.7.0

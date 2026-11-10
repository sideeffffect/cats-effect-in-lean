# Kernel derived combinators, laws and IO twins (research note)

> Source: https://github.com/typelevel/cats-effect/tree/v3.7.1 (local checkout ~/Projects/cats-effect at v3.7.1): `kernel/shared/src/main/scala/cats/effect/kernel/{MonadCancel,GenSpawn,GenConcurrent,Async,Fiber,Outcome,Poll,CancelScope}.scala`, `laws/shared/src/main/scala/cats/effect/laws/{MonadCancelLaws,GenSpawnLaws,MonadCancelTests,GenSpawnTests}.scala`, `core/shared/src/main/scala/cats/effect/IO.scala`; cats-core 2.13.0 sources jar (`cats/{Functor,Apply,FlatMap,Monad,Applicative,ApplicativeError}.scala`, `cats/syntax/flatMap.scala`); own Lean code `CatsEffectInLean/Kernel/*.lean`, `Props/Kernel/*.lean`, `Proofs/Kernel/MonadCancelDefaults.lean`
> Collected: 2026-11-10
> Published: 2026-08-23

Own notes, written for Phase 4 steps 1-2. `K` = `kernel/shared/src/main/scala/cats/effect/kernel`. `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`. All at v3.7.1.

## Versions

- CE v3.7.1 uses cats 2.13.0 (`build.sbt:323`).

## Derived bodies (kernel)

- `K/MonadCancel.scala:344-345` guarantee = `guaranteeCase(fa)(_ => fin)`.
- `K/MonadCancel.scala:365-372` guaranteeCase = `uncancelable { poll => onCancel(poll(fa), fin(canceled)); onError(...) { case e => handleError(fin(errored(e)))(_ => ()) }; flatTap(handled)(a => fin(succeeded(pure(a)))) }`.
- `K/MonadCancel.scala:397-398` bracket = `bracketCase(acquire)(use)((a, _) => release(a))`.
- `K/MonadCancel.scala:423-425` bracketCase = `bracketFull(_ => acquire)(use)(release)`.
- `K/MonadCancel.scala:447-455` bracketFull = `uncancelable { poll => acquire(poll).flatMap { a => guaranteeCase(poll(unit >> use(a)))(release(a, _)) } }`.
- `K/MonadCancel.scala:593-610` mixin `Uncancelable`: root scope Uncancelable, `canceled = unit`, `onCancel(fa, fin) = fa`, `uncancelable(body) = body(IdPoll)`.
- `K/GenSpawn.scala:176` `final def rootCancelScope = Cancelable`.
- `K/GenSpawn.scala:216-217` background = `Resource.make(start(fa))(_.cancel)(this).map(_.join)`.
- `K/GenSpawn.scala:264-271` cancelable, `370-376` raceOutcome, `401-427` race, `442-448` bothOutcome, `474-500` both.
- `K/GenConcurrent.scala:339` overrides the abstract `racePair` with a `Deferred`-based body.
- `K/Async.scala:168` overrides `never` = `async(_ => pure(Some(unit)))`. `IO.never` is `_never = asyncForIO.never` (`IO:1560`, `IO:2198`).
- `K/Outcome.scala:73-74` embed = `fold(onCancel, F.raiseError, identity)`. `K/Fiber.scala:63-86` joinWith, joinWithNever, joinWithUnit.

## cats default bodies used by the kernel bodies (cats 2.13.0)

- `Monad.scala:34` map = `flatMap(fa)(a => pure(f(a)))`; `Applicative.scala:68` unit = `pure(())`.
- `Functor.scala:143` as = `map(fa)(_ => b)`; `102` void = `as(fa, ())`; `157` tupleLeft; `171` tupleRight.
- `FlatMap.scala:107` product, `113` map2, `119` productR = `flatMap(fa)(_ => fb)`, `172` flatTap = `flatMap(fa)(a => as(f(a), a))`.
- `ApplicativeError.scala:105` handleError, `135` attempt, `261` onError = `handleErrorWith(fa)(e => pf.andThen(map2(_, raiseError(e))((_, b) => b)).applyOrElse(e, raiseError))`.
- Syntax `fa >> fb` = `F.flatMap(fa)(_ => fb)` (`cats/syntax/flatMap.scala:54`), not `productR`. `*>` = `productR` (`Apply.scala:141`).

## IOAsync overrides (`IO:1996`, `private final class IOAsync`)

as 2008, attempt 2011, unit 2020, guarantee 2023, guaranteeCase 2026, handleError 2029, onError 2032, bracketFull 2062, productL 2078, productR 2081, replicateA 2084, racePair 2090, map 2098, void 2152, redeem 2154, redeemWith 2157, map2Eval 2165. Not overridden (kernel default used for IO): bracket, bracketCase, cancelable, raceOutcome, race, bothOutcome, both, background, flatTap, map2, product, tupleLeft, tupleRight, never.

## IO bodies that differ from the kernel default

- `IO:496-501` guarantee: `uncancelable { poll => poll(this).onCancel(fin).onError { case _ => fin.reportError }.flatTap(_ => fin) }`.
- `IO:523-530` guaranteeCase: same shape as kernel, but the error branch is `finalizer(errored(e)).reportError`, not `handleError(...)(_ => ())`. Both drop the finalizer error from the outcome; IO also reports it.
- `IO:605-606` onError: `handleErrorWith(t => pf.applyOrElse(t, _ => IO.unit) *> IO.raiseError(t))`. cats: when `pf` is not defined, `raiseError(e)` directly, with no `IO.unit *>` step.
- `IO:1826-1830` bracketFull: `IO.defer(poll(use(a))).guaranteeCase(release(a, _))`. Kernel: `guaranteeCase(poll(unit >> use(a)))(...)`. IO calls `use(a)` outside `poll` (masked); kernel calls it inside `poll`. Only the construction of the `use(a)` value differs, not its run.
- `IO:452-454` forceR (abstract in kernel): `handleError(_ => ()).productR(that)`.
- `IO:338-372` IO#bracket → IO#bracketCase → `IO.bracketFull`: this chain does not go through `asyncForIO`.
- Entry points that call the kernel default through `asyncForIO`: `IO#race` 638 → `IO.race` 1788; `IO#both` 243 → `IO.both` 1732; `IO#bothOutcome` 228; `IO#raceOutcome` 641; `IO#cancelable` 449 (`Spawn[IO]`); `IO#background` 941; `IO#memoize` 944 (`Concurrent[IO]`).

## Laws

- `MonadCancelLaws.scala:28-103`: 17 laws. `MonadCancelTests.scala:120-152` checks 12 for all, then 3 for root `Cancelable` or 2 for root `Uncancelable`.
- `GenSpawnLaws.scala:28-158`: 16 laws checked by `GenSpawnTests.spawn` (`:195-216`); 2 deprecated (`raceCanceledIdentityLeft/Right`); 2 commented out (`raceLeftCedeYields`, `raceRightCedeYields`). A deprecated `spawn` overload (`:33-127`) omits `fiberJoinIsGuaranteeCase`.
- `raceDerivesFromRacePairLeft/Right`: the `results` term does NOT wrap `racePair` in `poll`. `race` (`K/GenSpawn.scala:403`) does. The difference shows only under external cancel of the racing fiber.
- Where Scala infers `Nothing` (`F.never >> fa`, `forceR(F.never)`, `forceR(F.raiseError(e))`), the Lean laws use `Empty`.

## Lean results

- All kernel defs and law props compile without `sorry`. `lake build --wfail` passes.
- Proven (not registered): `guaranteeIsGuaranteeCase` holds for every instance that keeps the default `guarantee` and every reflexive Eqv. Nine laws hold for every instance with the `Uncancelable` mixin (SyncIO-like): pollIsIdentity, ignoredPollEliminatesNesting, pollInverseNest, eliminatesOnCancel, onCancelAssociates, onCancelImpliesUncancelable, uncancelableFinalizers, uncancelableIdentity, canceledUnitIdentity. Axioms: none or `Quot.sound`.

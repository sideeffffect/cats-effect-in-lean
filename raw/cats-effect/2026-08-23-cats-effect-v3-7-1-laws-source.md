# Cats Effect v3.7.1 laws module: law definitions (verbatim source)

> Source: https://github.com/typelevel/cats-effect/tree/v3.7.1/laws/shared/src/main/scala/cats/effect/laws
> Collected: 2026-11-10
> Published: 2026-08-23

Verbatim copy of the *Laws.scala files at tag v3.7.1 (commit eb0cc258fc732fc37f22f117c2e81d5554d67024), license headers removed. Plus MonadCancelTests.scala lines 100-170 to show which laws depend on rootCancelScope. `<->` builds IsEq (lhs, rhs), checked with discipline/ScalaCheck. Note: there is NO GenConcurrentLaws file; GenConcurrent (Ref/Deferred) has no algebraic laws.

## MonadCancelLaws.scala

```scala
package cats.effect
package laws

import cats.effect.kernel.MonadCancel
import cats.laws.MonadErrorLaws
import cats.syntax.all._

trait MonadCancelLaws[F[_], E] extends MonadErrorLaws[F, E] {

  implicit val F: MonadCancel[F, E]

  def guaranteeIsGuaranteeCase[A](fa: F[A], fin: F[Unit]) =
    F.guarantee(fa, fin) <-> F.guaranteeCase(fa)(_ => fin)

  // note that this implies the nested case as well
  def uncancelablePollIsIdentity[A](fa: F[A]) =
    F.uncancelable(_(fa)) <-> fa

  def uncancelableIgnoredPollEliminatesNesting[A](fa: F[A]) =
    F.uncancelable(_ => F.uncancelable(_ => fa)) <-> F.uncancelable(_ => fa)

  // this law shows that inverted polls do not apply
  def uncancelablePollInverseNestIsUncancelable[A](fa: F[A]) =
    F.uncancelable(op => F.uncancelable(ip => op(ip(fa)))) <-> F.uncancelable(_ => fa)

  // TODO F.uncancelable(p => F.canceled >> p(fa) >> fb) <-> F.uncancelable(p => p(F.canceled >> fa) >> fb)

  def uncancelableEliminatesOnCancel[A](fa: F[A], fin: F[Unit]) =
    F.uncancelable(_ => F.onCancel(fa, fin)) <-> F.uncancelable(_ => fa)

  /*
   * NB: This is effectively in violation of the monad laws, since
   * we consider finalizers to associate over the boundary here, but
   * we do NOT consider them to right-associate over map or flatMap.
   * This simply stems from the fact that cancelation is fundamentally
   * uncomposable, and it's better to pick a semantic for uncancelable
   * which allows regional composition, since this avoids "gaps" in
   * otherwise-safe code.
   *
   * The argument is that cancelation is a *hint* not a mandate. This
   * holds for self-cancelation just as much as external-cancelation.
   * Thus, laws about where the cancelation is visible are always going
   * to be a bit off.
   */
  def onCancelAssociatesOverUncancelableBoundary[A](fa: F[A], fin: F[Unit]) =
    F.uncancelable(_ => F.onCancel(fa, fin)) <-> F.onCancel(F.uncancelable(_ => fa), fin)

  def onCancelImpliesUncancelable[A](fa: F[A], fin1: F[Unit], fin2: F[Unit]) =
    F.onCancel(F.onCancel(fa, F.uncancelable(_ => fin1)), fin2) <-> F.onCancel(
      F.onCancel(fa, fin1),
      fin2)

  def forceRDiscardsPure[A, B](a: A, fa: F[B]) =
    F.forceR(F.pure(a))(fa) <-> fa

  def forceRDiscardsError[A](e: E, fa: F[A]) =
    F.forceR(F.raiseError(e))(fa) <-> fa

  def forceRCanceledShortCircuits[A](fa: F[A]) =
    F.forceR(F.canceled)(fa) <-> F.productR(F.canceled)(fa)

  def forceRAssociativity[A, B, C](fa: F[A], fb: F[B], fc: F[C]) =
    F.forceR(fa)(F.forceR(fb)(fc)) <-> F.forceR(F.forceR(fa)(fb))(fc)

  def uncancelableFinalizers[A](fin: F[Unit]) =
    F.onCancel(F.canceled, F.uncancelable(_ => fin)) <-> F.onCancel(F.canceled, fin)

  // only for root = Cancelable

  def canceledSequencesOnCancelInOrder(fin1: F[Unit], fin2: F[Unit]) =
    F.onCancel(F.onCancel(F.canceled, fin1), fin2) <->
      F.forceR(F.uncancelable(_ => F.forceR(fin1)(fin2)))(F.canceled)

  def uncancelableCanceledAssociatesRightOverFlatMapAttempt[A](fa: F[A]) =
    (F.uncancelable(_ => F.canceled >> fa).attempt >> F.unit) <->
      F.forceR(F.uncancelable(_ => fa))(F.canceled)

  def canceledAssociatesLeftOverFlatMap[A](fa: F[A]) =
    F.canceled >> fa.void <-> F.canceled

  // only for root = Uncancelable

  def uncancelableIdentity[A](fa: F[A]) =
    F.uncancelable(_ => fa) <-> fa

  def canceledUnitIdentity =
    F.canceled <-> F.unit
}

object MonadCancelLaws {
  def apply[F[_], E](implicit F0: MonadCancel[F, E]): MonadCancelLaws[F, E] =
    new MonadCancelLaws[F, E] { val F = F0 }
}
```

## GenSpawnLaws.scala

```scala
package cats.effect
package laws

import cats.effect.kernel.{GenSpawn, Outcome}
import cats.syntax.all._

trait GenSpawnLaws[F[_], E] extends MonadCancelLaws[F, E] with UniqueLaws[F] {

  implicit val F: GenSpawn[F, E]

  // we need to phrase this in terms of never because we can't *evaluate* laws which rely on nondetermnistic substitutability
  def raceDerivesFromRacePairLeft[A, B](fa: F[A]) = {
    val results: F[Either[A, B]] = F uncancelable { poll =>
      F.flatMap(F.racePair(fa, F.never[B])) {
        case Left((oc, f)) =>
          oc match {
            case Outcome.Succeeded(fa) => F.productR(f.cancel)(F.map(fa)(Left(_)))
            case Outcome.Errored(ea) => F.productR(f.cancel)(F.raiseError(ea))
            case Outcome.Canceled() =>
              F.flatMap(f.cancel *> f.join) {
                case Outcome.Succeeded(fb) => F.map(fb)(Right(_))
                case Outcome.Errored(eb) => F.raiseError(eb)
                case Outcome.Canceled() => F.productR(poll(F.canceled))(F.never)
              }
          }
        case Right((f, oc)) =>
          oc match {
            case Outcome.Succeeded(fb) => F.productR(f.cancel)(F.map(fb)(Right(_)))
            case Outcome.Errored(eb) => F.productR(f.cancel)(F.raiseError(eb))
            case Outcome.Canceled() =>
              F.flatMap(f.cancel *> f.join) {
                case Outcome.Succeeded(fa) => F.map(fa)(Left(_))
                case Outcome.Errored(ea) => F.raiseError(ea)
                case Outcome.Canceled() => F.productR(poll(F.canceled))(F.never)
              }
          }
      }
    }

    F.race(fa, F.never[B]) <-> results
  }

  def raceDerivesFromRacePairRight[A, B](fb: F[B]) = {
    val results: F[Either[A, B]] = F uncancelable { poll =>
      F.flatMap(F.racePair(F.never[A], fb)) {
        case Left((oc, f)) =>
          oc match {
            case Outcome.Succeeded(fa) => F.productR(f.cancel)(F.map(fa)(Left(_)))
            case Outcome.Errored(ea) => F.productR(f.cancel)(F.raiseError(ea))
            case Outcome.Canceled() =>
              F.flatMap(f.cancel *> f.join) {
                case Outcome.Succeeded(fb) => F.map(fb)(Right(_))
                case Outcome.Errored(eb) => F.raiseError(eb)
                case Outcome.Canceled() => F.productR(poll(F.canceled))(F.never)
              }
          }
        case Right((f, oc)) =>
          oc match {
            case Outcome.Succeeded(fb) => F.productR(f.cancel)(F.map(fb)(Right(_)))
            case Outcome.Errored(eb) => F.productR(f.cancel)(F.raiseError(eb))
            case Outcome.Canceled() =>
              F.flatMap(f.cancel *> f.join) {
                case Outcome.Succeeded(fa) => F.map(fa)(Left(_))
                case Outcome.Errored(ea) => F.raiseError(ea)
                case Outcome.Canceled() => F.productR(poll(F.canceled))(F.never)
              }
          }
      }
    }

    F.race(F.never[A], fb) <-> results
  }

  @deprecated("law is no longer applicable (or correct)", "3.5.0")
  def raceCanceledIdentityLeft[A](fa: F[A]) =
    F.race(F.canceled, fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_))) <-> fa.map(
      _.asRight[Unit])

  @deprecated("law is no longer applicable (or correct)", "3.5.0")
  def raceCanceledIdentityRight[A](fa: F[A]) =
    F.race(fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_)), F.canceled) <-> fa.map(
      _.asLeft[Unit])

  def raceNeverNoncanceledIdentityLeft[A](fa: F[A]) =
    F.race(F.never[Unit], fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_))) <->
      fa.flatMap(r => F.pure(r.asRight[Unit])).handleErrorWith(F.raiseError(_))

  def raceNeverNoncanceledIdentityRight[A](fa: F[A]) =
    F.race(fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_)), F.never[Unit]) <->
      fa.flatMap(r => F.pure(r.asLeft[Unit])).handleErrorWith(F.raiseError(_))

  // I really like these laws, since they relate cede to timing, but they're definitely nondeterministic
  /*def raceLeftCedeYields[A](a: A) =
    F.race(F.cede, F.pure(a)) <-> F.pure(Right(a))*/

  /*def raceRightCedeYields[A](a: A) =
    F.race(F.pure(a), F.cede) <-> F.pure(Left(a))*/

  def fiberPureIsOutcomeCompletedPure[A](a: A) =
    F.start(F.pure(a)).flatMap(_.join) <-> F.pure(Outcome.Succeeded(F.pure(a)))

  def fiberErrorIsOutcomeErrored(e: E) =
    F.start(F.raiseError[Unit](e)).flatMap(_.join) <-> F.pure(Outcome.Errored(e))

  def fiberCancelationIsOutcomeCanceled =
    F.start(F.never[Unit]).flatMap(f => f.cancel >> f.join) <-> F.pure(Outcome.Canceled())

  def fiberCanceledIsOutcomeCanceled =
    F.start(F.canceled).flatMap(_.join) <-> F.pure(Outcome.Canceled())

  def fiberNeverIsNever =
    F.start(F.never[Unit]).flatMap(_.join) <-> F.never[Outcome[F, E, Unit]]

  def fiberStartOfNeverIsUnit =
    F.start(F.never[Unit]).void <-> F.unit

  def fiberJoinIsGuaranteeCase[A](fa0: F[A], f: Outcome[F, E, A] => F[Unit]) = {
    // the semantics of cancelation create boundary conditions we must avoid
    val fa = fa0.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_))

    F.start(fa)
      .flatMap(_.join)
      .flatMap(oc => F.guarantee(oc.embed(F.canceled >> F.never[A]), f(oc))) <->
      F.guaranteeCase(fa)(f)
  }

  def neverDominatesOverFlatMap[A](fa: F[A]) =
    F.never >> fa <-> F.never[A]

  def uncancelableRaceNotInherited =
    F.uncancelable(_ => F.race(F.never[Unit], F.canceled)).void <-> F.never[Unit]

  def uncancelableCancelCancels =
    F.start(F.never[Unit]).flatMap(f => F.uncancelable(_ => f.cancel) >> f.join) <-> F.pure(
      Outcome.Canceled())

  def uncancelableStartIsCancelable =
    F.uncancelable(_ => F.start(F.never[Unit]).flatMap(f => f.cancel >> f.join)) <-> F.pure(
      Outcome.Canceled())

  def forceRNeverIsNever[A](fa: F[A]) =
    F.forceR(F.never)(fa) <-> F.never
}

object GenSpawnLaws {
  def apply[F[_], E](implicit F0: GenSpawn[F, E]): GenSpawnLaws[F, E] =
    new GenSpawnLaws[F, E] { val F = F0 }
}
```

## GenTemporalLaws.scala

```scala
package cats.effect
package laws

import cats.effect.kernel.GenTemporal
import cats.syntax.all._

import scala.concurrent.duration.FiniteDuration

trait GenTemporalLaws[F[_], E] extends GenSpawnLaws[F, E] with ClockLaws[F] {

  implicit val F: GenTemporal[F, E]

  def monotonicSleepSumIdentity(delta: FiniteDuration) =
    F.sleep(delta) >> F.monotonic <-> F.monotonic.map(delta + _)

  def sleepRaceMinimum(d1: FiniteDuration, d2: FiniteDuration) =
    F.race(F.sleep(d1), F.sleep(d2)) >> F.monotonic <-> F.monotonic.map(d1.min(d2) + _)

  def startSleepMaximum(d1: FiniteDuration, d2: FiniteDuration) =
    F.start(F.sleep(d1)).flatMap(f => F.sleep(d2) >> f.join) >> F.monotonic <-> F
      .monotonic
      .map(d1.max(d2) + _)
}

object GenTemporalLaws {
  def apply[F[_], E](implicit F0: GenTemporal[F, E]): GenTemporalLaws[F, E] =
    new GenTemporalLaws[F, E] { val F = F0 }
}
```

## SyncLaws.scala

```scala
package cats.effect
package laws

import cats.effect.kernel.Sync
import cats.syntax.all._

trait SyncLaws[F[_]]
    extends MonadCancelLaws[F, Throwable]
    with ClockLaws[F]
    with UniqueLaws[F] {

  implicit val F: Sync[F]

  def suspendValueIsPure[A](a: A, hint: Sync.Type) =
    F.suspend(hint)(a) <-> F.pure(a)

  def suspendThrowIsRaiseError[A](e: Throwable, hint: Sync.Type) =
    F.suspend[A](hint)(throw e) <-> F.raiseError(e)

  def unsequencedSuspendIsNoop[A](a: A, f: A => A, hint: Sync.Type) = {
    val isWith = F delay {
      var cur = a
      val _ = F.suspend(hint) { cur = f(cur) }
      F.delay(cur)
    }

    val isWithout = F delay {
      var cur = a
      cur = a // no-op to confuse the compiler
      F.delay(cur)
    }

    isWith.flatten <-> isWithout.flatten
  }

  def repeatedSuspendNotMemoized[A](a: A, f: A => A, hint: Sync.Type) = {
    val isWith = F delay {
      var cur = a

      val changeF = F.suspend(hint) {
        cur = f(cur)
        cur
      }

      changeF >> changeF
    }

    val isWithout = F delay {
      var cur = a

      F.suspend(hint) {
        cur = f(f(cur))
        cur
      }
    }

    isWith.flatten <-> isWithout.flatten
  }
}

object SyncLaws {
  def apply[F[_]](implicit F0: Sync[F]): SyncLaws[F] =
    new SyncLaws[F] { val F = F0 }
}
```

## AsyncLaws.scala

```scala
package cats.effect
package laws

import cats.effect.kernel.Async
import cats.syntax.all._

import scala.concurrent.ExecutionContext
import scala.util.{Left, Right}

trait AsyncLaws[F[_]] extends GenTemporalLaws[F, Throwable] with SyncLaws[F] {
  implicit val F: Async[F]

  // format: off
  def asyncCheckAttemptImmediateIsPure[A](a: A) =
    (F.asyncCheckAttempt[A](_ => F.pure(Right(a))) <* F.unit) <-> (F.pure(a))
  // format: on

  // format: off
  def asyncCheckAttemptSuspendedRightIsAsyncRight[A](a: A, fu: F[Unit]) =
    (F.asyncCheckAttempt[A](k => F.delay(k(Right(a))) >> fu.as(Left(None))) <* F.unit) <-> (F.async[A](k => F.delay(k(Right(a))) >> fu.as(None)) <* F.unit)
  // format: on

  // format: off
  def asyncCheckAttemptSuspendedLeftIsAsyncLeft[A](e: Throwable, fu: F[Unit]) =
    (F.asyncCheckAttempt[A](k => F.delay(k(Left(e))) >> fu.as(Left(None))) <* F.unit) <-> (F.async[A](k => F.delay(k(Left(e))) >> fu.as(None)) <* F.unit)
  // format: on

  // format: off
  def asyncRightIsUncancelableSequencedPure[A](a: A, fu: F[Unit]) =
    (F.async[A](k => F.delay(k(Right(a))) >> fu.as(None)) <* F.unit) <-> (F.uncancelable(_ => fu) >> F.pure(a))
  // format: on

  // format: off
  def asyncLeftIsUncancelableSequencedRaiseError[A](e: Throwable, fu: F[Unit]) =
    (F.async[A](k => F.delay(k(Left(e))) >> fu.as(None)) <* F.unit) <-> (F.uncancelable(_ => fu) >> F.raiseError(e))
  // format: on

  def asyncRepeatedCallbackIgnored[A](a: A) =
    F.async[A](k => F.delay(k(Right(a))) >> F.delay(k(Right(a))).as(None)) <-> F.pure(a)

  def asyncCancelTokenIsUnsequencedOnCompletion[A](a: A, fu: F[Unit]) =
    F.async[A](k => F.delay(k(Right(a))) >> F.pure(Some(fu))) <-> F.pure(a)

  def asyncCancelTokenIsUnsequencedOnError[A](e: Throwable, fu: F[Unit]) =
    F.async[A](k => F.delay(k(Left(e))) >> F.pure(Some(fu))) <-> F.raiseError(e)

  def neverIsDerivedFromAsync[A] =
    F.never[A] <-> F.async[A](_ => F.pure(Some(F.unit)))

  def executionContextCommutativity[A](fa: F[A]) =
    (fa *> F.executionContext) <-> (F.executionContext <* fa)

  def evalOnLocalPure(ec: ExecutionContext) =
    F.evalOn(F.executionContext, ec) <-> F.evalOn(F.pure(ec), ec)

  def evalOnPureIdentity[A](a: A, ec: ExecutionContext) =
    F.evalOn(F.pure(a), ec) <-> F.pure(a)

  def evalOnRaiseErrorIdentity(e: Throwable, ec: ExecutionContext) =
    F.evalOn(F.raiseError[Unit](e), ec) <-> F.raiseError[Unit](e)

  def evalOnCanceledIdentity(ec: ExecutionContext) =
    F.evalOn(F.canceled, ec) <-> F.canceled

  def evalOnNeverIdentity(ec: ExecutionContext) =
    F.evalOn(F.never[Unit], ec) <-> F.never[Unit]

  def syncStepIdentity[A](fa: F[A], limit: Int) =
    F.syncStep(fa, limit).flatMap {
      case Left(fa) => fa
      case Right(a) => F.pure(a)
    } <-> fa
}

object AsyncLaws {
  def apply[F[_]](implicit F0: Async[F]): AsyncLaws[F] =
    new AsyncLaws[F] { val F = F0 }
}
```

## ClockLaws.scala

```scala
package cats.effect
package laws

import cats.Applicative
import cats.effect.kernel.Clock
import cats.syntax.all._

trait ClockLaws[F[_]] {

  implicit val F: Clock[F]
  private implicit def app: Applicative[F] = F.applicative

  def monotonicity = (F.monotonic, F.monotonic).mapN(_ <= _)
}

object ClockLaws {
  def apply[F[_]](implicit F0: Clock[F]): ClockLaws[F] =
    new ClockLaws[F] { val F = F0 }
}
```

## UniqueLaws.scala

```scala
package cats.effect
package laws

import cats.Applicative
import cats.effect.kernel.Unique
import cats.syntax.all._

trait UniqueLaws[F[_]] {

  implicit val F: Unique[F]
  private implicit def app: Applicative[F] = F.applicative

  def uniqueness = (F.unique, F.unique).mapN(_ =!= _)
}

object UniqueLaws {
  def apply[F[_]](implicit F0: Unique[F]): UniqueLaws[F] =
    new UniqueLaws[F] { val F = F0 }
}
```

## IsEq.scala

```scala
package cats.effect.laws

import cats.{Applicative, Eq, Group, Order}
import cats.syntax.all._

import org.scalacheck.Prop
import org.scalacheck.util.Pretty

sealed trait IsEq[A] {

  def toPropTolerant[F[_], B](
      implicit ev: A =:= F[B],
      F: Applicative[F],
      ord: Order[F[B]],
      g: Group[B],
      tolerance: Tolerance[B],
      pp: A => Pretty): Prop =
    this match {
      case IsEq.Assert(lhs0, rhs0) =>
        val lhs = ev(lhs0)
        val rhs = ev(rhs0)

        if (lhs <= rhs && (rhs, lhs).mapN(_ |-| _) <= tolerance.value.pure[F]) {
          Prop.proved
        } else if (lhs > rhs && (lhs, rhs).mapN(_ |-| _) <= tolerance.value.pure[F]) {
          Prop.proved
        } else {
          Prop.falsified :| {
            val exp = Pretty.pretty[A](rhs0, Pretty.Params(0))
            val act = Pretty.pretty[A](lhs0, Pretty.Params(0))
            s"Expected: $exp ± ${tolerance.value}\n" + s"Received: $act"
          }
        }
    }

  def toProp(implicit A: Eq[A], pp: A => Pretty): Prop =
    this match {
      case IsEq.Assert(lhs, rhs) =>
        try {
          cats.laws.discipline.catsLawsIsEqToProp(cats.laws.IsEq(lhs, rhs))
        } catch {
          case soe: StackOverflowError =>
            soe.printStackTrace()
            throw soe
        }
    }
}

private[laws] trait IsEqLowPriorityImplicits {
  implicit def toProp[A: Eq](isEq: IsEq[A])(implicit pp: A => Pretty): Prop =
    isEq.toProp
}

object IsEq extends IsEqLowPriorityImplicits {

  implicit def toPropTolerant[F[_], A](isEq: IsEq[F[A]])(
      implicit F: Applicative[F],
      ord: Order[F[A]],
      g: Group[A],
      tolerance: Tolerance[A],
      pp: F[A] => Pretty): Prop =
    isEq.toPropTolerant

  def apply[A](lhs: A, rhs: A): IsEq[A] =
    Assert(lhs, rhs)

  final case class Assert[A](lhs: A, rhs: A) extends IsEq[A]
}
```

## MonadCancelTests.scala (lines 100-170)

```scala
      CogenC: Cogen[C],
      CogenE: Cogen[E],
      EqFA: Eq[F[A]],
      EqFB: Eq[F[B]],
      EqFC: Eq[F[C]],
      EqFU: Eq[F[Unit]],
      EqE: Eq[E],
      EqFEitherEU: Eq[F[Either[E, Unit]]],
      EqFEitherEA: Eq[F[Either[E, A]]],
      EqFABC: Eq[F[(A, B, C)]],
      EqFInt: Eq[F[Int]],
      iso: Isomorphisms[F]): RuleSet = {

    new RuleSet {
      val name = "monadCancel"
      val bases: Seq[(String, Laws#RuleSet)] = Nil
      val parents = Seq(monadError[A, B, C])

      val props = {
        val common: Seq[(String, Prop)] = Seq(
          "guarantee is guaranteeCase" -> forAll(laws.guaranteeIsGuaranteeCase[A] _),
          "uncancelable poll is identity" -> forAll(laws.uncancelablePollIsIdentity[A] _),
          "uncancelable ignored poll eliminates nesting" -> forAll(
            laws.uncancelableIgnoredPollEliminatesNesting[A] _),
          "uncancelable poll inverse nest is uncancelable" -> forAll(
            laws.uncancelablePollInverseNestIsUncancelable[A] _),
          "uncancelable eliminates onCancel" -> forAll(
            laws.uncancelableEliminatesOnCancel[A] _),
          "onCancel associates over uncancelable boundary" -> forAll(
            laws.onCancelAssociatesOverUncancelableBoundary[A] _),
          "onCancel implies uncancelable" -> forAll(laws.onCancelImpliesUncancelable[A] _),
          "forceR discards pure" -> forAll(laws.forceRDiscardsPure[A, B] _),
          "forceR discards error" -> forAll(laws.forceRDiscardsError[A] _),
          "forceR canceled short-circuits" -> forAll(laws.forceRCanceledShortCircuits[A] _),
          "forceR associativity" -> forAll(laws.forceRAssociativity[A, B, C] _),
          "uncancelable finalizers" -> forAll(laws.uncancelableFinalizers[A] _)
        )

        val suffix: Seq[(String, Prop)] = laws.F.rootCancelScope match {
          case CancelScope.Cancelable =>
            Seq(
              "canceled sequences onCancel in order" -> forAll(
                laws.canceledSequencesOnCancelInOrder _),
              "uncancelable canceled associates right over flatMap attempt" -> forAll(
                laws.uncancelableCanceledAssociatesRightOverFlatMapAttempt[A] _),
              "canceled associates left over flatMap" -> forAll(
                laws.canceledAssociatesLeftOverFlatMap[A] _)
            )

          case CancelScope.Uncancelable =>
            Seq(
              "uncancelable identity" -> forAll(laws.uncancelableIdentity[A] _),
              "canceled is unit" -> laws.canceledUnitIdentity)
        }

        common ++ suffix
      }
    }
  }
}

object MonadCancelTests {
  def apply[F[_], E](implicit F0: MonadCancel[F, E]): MonadCancelTests[F, E] =
    new MonadCancelTests[F, E] {
      val laws = MonadCancelLaws[F, E]
    }
}
```

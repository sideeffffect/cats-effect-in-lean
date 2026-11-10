# Cats Effect 3 Async, Sync, GenTemporal, Clock and Unique laws (series/3.x)

> Source: https://github.com/typelevel/cats-effect/blob/series/3.x/laws/shared/src/main/scala/cats/effect/laws/
> Collected: 2026-11-10
> Published: Unknown

## AsyncLaws.scala

```scala
/*
 * Copyright 2020-2025 Typelevel
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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

## SyncLaws.scala

```scala
/*
 * Copyright 2020-2025 Typelevel
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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

## GenTemporalLaws.scala

```scala
/*
 * Copyright 2020-2025 Typelevel
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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

## ClockLaws.scala

```scala
/*
 * Copyright 2020-2025 Typelevel
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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
/*
 * Copyright 2020-2025 Typelevel
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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


# Cats Effect kernel sources: MonadCancel, GenSpawn, Fiber (scaladoc = normative semantics)

> Source: https://github.com/typelevel/cats-effect/blob/series/3.x/kernel/shared/src/main/scala/cats/effect/kernel/
> Collected: 2026-11-10
> Published: Unknown

## kernel/MonadCancel.scala (type-level scaladoc and trait header)

```scala
/**
 * A typeclass that characterizes monads which support safe cancelation, masking, and
 * finalization. [[MonadCancel]] extends the capabilities of [[cats.MonadError]], so an instance
 * of this typeclass must also provide a lawful instance for [[cats.MonadError]].
 *
 * ==Fibers==
 *
 * A fiber is a sequence of effects which are bound together by [[flatMap]]. The execution of a
 * fiber of an effect `F[E, A]` terminates with one of three outcomes, which are encoded by the
 * datatype [[Outcome]]:
 *
 *   1. [[Outcome.Succeeded]]: indicates success with a value of type `A`
 *   1. [[Outcome.Errored]]: indicates failure with a value of type `E`
 *   1. [[Outcome.Canceled]]: indicates abnormal termination
 *
 * Additionally, a fiber may never produce an outcome, in which case it is said to be
 * non-terminating.
 *
 * ==Cancelation==
 *
 * Cancelation refers to the act of requesting that the execution of a fiber be abnormally
 * terminated. A fiber is canceled when it observes a cancelation request before it completes.
 * [[MonadCancel]] exposes a means of self-cancelation, with which a fiber can request that its
 * own execution be terminated. Self-cancelation is achieved via
 * [[MonadCancel!.canceled canceled]].
 *
 * Cancelation is vaguely similar to the short-circuiting behavior introduced by
 * [[cats.MonadError]], but there are several key differences:
 *
 *   1. Cancelation is effective; if it is observed it must be respected, and it cannot be
 *      reversed. In contrast, [[cats.MonadError.handleError handleError]] exposes the ability
 *      to catch and recover from errors, and then proceed with normal execution.
 *   1. Cancelation can be masked via [[MonadCancel!.uncancelable]]. Masking is discussed in the
 *      next section.
 *   1. [[GenSpawn]] introduces external cancelation, another cancelation mechanism by which
 *      fibers can be canceled by external parties.
 *
 * ==Masking==
 *
 * Masking allows a fiber to suppress the observation of cancelation until the fiber is
 * unmasked, which is achieved via [[MonadCancel!.uncancelable uncancelable]]. If a fiber would
 * be canceled while it is masked, the cancelation is suppressed for as long as the fiber
 * remains masked. Once the fiber reaches a completely unmasked state, it will be canceled if it
 * has not already completed.
 *
 * While a fiber is masked, it may optionally unmask by "polling", rendering itself cancelable
 * again.
 *
 * {{{
 *
 *   F.uncancelable { poll =>
 *     // can only be canceled immediately before `fb` is executed, or between combinators in `fb`.
 *     fa *> poll(fb) *> fc
 *   }
 *
 * }}}
 *
 * These semantics allow users to precisely mark what regions of code are cancelable within a
 * larger code block.
 *
 * ==Cancelation Boundaries==
 *
 * A cancelation boundary is a boundary where the cancelation status of a fiber ''may'' be
 * checked and hence canceled. Cancelation is advisory. It does not have to be checked at every
 * boundary, so it is possible for a fiber to complete after cancelation has been requested, but
 * before it is observed.
 *
 * In general they are introduced before each of the combinators from the Cats/Cats Effect
 * hierarchy (`map`, `flatMap`, `handleErrorWith`, `attempt`, etc). Typeclasses which extend
 * `MonadCancel` may introduce additional cancelation boundaries with their combinators.
 * Importantly, there will never be a cancelation boundary after a combinator, as this would
 * allow cancelation between the end of a poll and the next action, losing the result of the
 * polled operation.
 *
 * Outside `uncancelable` cancelation may be observed at any cancelation boundary:
 *
 * {{{
 *   /* boundary */
 *   fa
 *     .flatMap(f)
 *     /* boundary */
 *     .handleErrorWith(g)
 *     /* boundary */
 *     .map(h)
 * }}}
 *
 * If cancelation of the fiber above is requested then the cancelation status may be checked and
 * the execution terminated before each combinator is executed, or it may not be observed at all
 * before the fiber completes.
 *
 * Inside `uncancelable`, the observation of cancelation at boundaries outside of `poll` is
 * suppressed. This is the definition of masking as above.
 *
 * {{{
 *   /* boundary */
 *   F.uncancelable( poll =>
 *     fa
 *       .flatMap(f)
 *       .poll(/* boundary */g)
 *       .handleErrorWith(h)
 *       .map(i)
 *   )
 * }}}
 *
 * The only points above where cancelation can be observed are:
 *
 *   1. before the `uncancelable` block
 *   1. the boundary before `g` is executed inside `poll`
 *   1. between any combinators that `g` is composed of.
 *
 * Since uncancelable regions compose, if `uncancelable` is called within `g`, the observation
 * of cancelation will again be suppressed until after that block. Cancelation will ''not'' be
 * observed ''after'' `g` completes
 *
 * ==Finalization==
 *
 * Finalization refers to the act of running finalizers in response to a cancelation. Finalizers
 * are those effects whose evaluation is guaranteed in the event of cancelation. After a fiber
 * has completed finalization, it terminates with an outcome of `Canceled`.
 *
 * Finalizers can be registered to a fiber for the duration of some effect via
 * [[MonadCancel!.onCancel onCancel]]. If a fiber is canceled while running that effect, the
 * registered finalizer is guaranteed to be run before terminating.
 *
 * ==Bracket pattern==
 *
 * The aforementioned concepts work together to unlock a powerful pattern for safely interacting
 * with effectful lifecycles: the bracket pattern. This is analogous to the
 * try-with-resources/finally construct in Java.
 *
 * A lifecycle refers to a pair of actions, which are called the acquisition action and the
 * release action respectively. The relationship between these two actions is that if the former
 * completes successfully, then the latter is guaranteed to be run eventually, even in the
 * presence of errors and cancelation. While the lifecycle is active, other work can be
 * performed, but this invariant is always respected.
 *
 * The bracket pattern is an invaluable tool for safely handling resource lifecycles. Imagine an
 * application that opens network connections to a database server to do work. If a task in the
 * application is canceled while it holds an open database connection, the connection would
 * never be released or returned to a pool, causing a resource leak.
 *
 * To illustrate the compositional nature of [[MonadCancel]] and its combinators, the
 * implementation of [[MonadCancel!.bracket bracket]] is shown below:
 *
 * {{{
 *
 *   def bracket[A, B](acquire: F[A])(use: A => F[B])(release: A => F[Unit]): F[B] =
 *     uncancelable { poll =>
 *       flatMap(acquire) { a =>
 *         val finalized = onCancel(poll(use(a)), release(a).uncancelable)
 *         val handled = onError(finalized) { case e => void(attempt(release(a).uncancelable)) }
 *         flatMap(handled)(b => as(attempt(release(a).uncancelable), b))
 *       }
 *     }
 *
 * }}}
 *
 * See [[MonadCancel!.bracketCase bracketCase]] and [[MonadCancel!.bracketFull bracketFull]] for
 * other variants of the bracket pattern. If more specialized behavior is necessary, it is
 * recommended to use [[MonadCancel!.uncancelable uncancelable]] and
 * [[MonadCancel!.onCancel onCancel]] directly.
 *
 * ==Law Violations==
 *
 * Because cancelation may be checked before each combinator, `MonadCancel` introduces a subtle
 * violation of identity functor law that `fa.map(identity) <-> fa`. For example, in:
 *
 * {{{
 *   F.uncancelable(_ => fa).onCancel(fin)  <-!-> F.uncancelable(_ => fa).map(identity).onCancel(fin)
 * }}}
 *
 * cancelation may be observed before the execution of `map` on the right-hand side, causing the
 * `onCancel` combinator to never be registered. The monad right identity law, and other similar
 * laws that allow the insertion of a combinator are similarly violated. The justification is
 * that cancelation is a hint rather than a mandate and so enshrining its behaviour in laws will
 * always be awkward.
 */
trait MonadCancel[F[_], E] extends MonadError[F, E] {
```

[...omitted: method bodies and per-method scaladoc of MonadCancel.scala...]

## kernel/GenSpawn.scala (type-level scaladoc and trait header)

```scala
/**
 * A typeclass that characterizes monads which support spawning and racing of fibers.
 * [[GenSpawn]] extends the capabilities of [[MonadCancel]], so an instance of this typeclass
 * must also provide a lawful instance for [[MonadCancel]].
 *
 * This documentation builds upon concepts introduced in the [[MonadCancel]] documentation.
 *
 * ==Concurrency==
 *
 * [[GenSpawn]] introduces a notion of concurrency that enables fibers to safely interact with
 * each other via three special functions. [[GenSpawn!.start start]] spawns a fiber that
 * executes concurrently with the spawning fiber. [[Fiber!.join join]] semantically blocks the
 * joining fiber until the joinee fiber terminates, after which the [[Outcome]] of the joinee is
 * returned. [[Fiber!.cancel cancel]] requests a fiber to abnormally terminate, and semantically
 * blocks the canceller until the cancellee has completed finalization.
 *
 * Just like threads, fibers can execute concurrently with respect to each other. This means
 * that the effects of independent fibers may be interleaved nondeterministically. This mode of
 * concurrency reaps benefits for modular program design; fibers that are described separately
 * can execute simultaneously without requiring programmers to explicitly yield back to the
 * runtime system.
 *
 * The interleaving of effects is illustrated in the following program:
 *
 * {{{
 *
 *   for {
 *     fa <- (println("A1") *> println("A2")).start
 *     fb <- (println("B1") *> println("B2")).start
 *   } yield ()
 *
 * }}}
 *
 * In this program, two fibers A and B are spawned concurrently. There are six possible
 * executions, each of which exhibits a different ordering of effects. The observed output of
 * each execution is shown below:
 *
 *   1. A1, A2, B1, B2
 *   1. A1, B1, A2, B2
 *   1. A1, B1, B2, A2
 *   1. B1, B2, A1, A2
 *   1. B1, A1, B2, A2
 *   1. B1, A1, A2, B2
 *
 * Notice how every execution preserves sequential consistency of the effects within each fiber:
 * `A1` always prints before `A2`, and `B1` always prints before `B2`. However, there are no
 * guarantees around how the effects of both fibers will be ordered with respect to each other;
 * it is entirely nondeterministic.
 *
 * ==Cancelation==
 *
 * [[MonadCancel]] introduces a simple means of cancelation, particularly self-cancelation,
 * where a fiber can request the abnormal termination of its own execution. This is achieved by
 * calling [[MonadCancel!.canceled canceled]].
 *
 * [[GenSpawn]] expands on the cancelation model described by [[MonadCancel]] by introducing a
 * means of external cancelation. With external cancelation, a fiber can request the abnormal
 * termination of another fiber by calling [[Fiber!.cancel]].
 *
 * The cancelation model dictates that external cancelation behaves identically to
 * self-cancelation. To guarantee consistent behavior between the two, the following semantics
 * are shared:
 *
 *   1. Masking: if a fiber is canceled while it is masked, cancelation is suppressed until it
 *      reaches a completely unmasked state. See [[MonadCancel]] documentation for more details.
 *   1. Backpressure: [[Fiber!.cancel cancel]] semantically blocks all callers until
 *      finalization is complete.
 *   1. Idempotency: once a fiber's cancelation has been requested, subsequent cancelations have
 *      no effect on cancelation status.
 *   1. Terminal: Cancelation of a fiber that has terminated immediately returns.
 *
 * External cancelation contrasts with self-cancelation in one aspect: the former may require
 * synchronization between multiple threads to communicate a cancelation request. As a result,
 * cancelation may not be immediately observed by a fiber. Implementations are free to decide
 * how and when this synchronization takes place.
 *
 * ==Cancelation safety==
 *
 * A function or effect is considered to be cancelation-safe if it can be run in the absence of
 * masking without violating effectful lifecycles or leaking resources. These functions require
 * extra attention and care from users to ensure safe usage.
 *
 * [[start]] and [[racePair]] are both considered to be cancelation-unsafe effects because they
 * return a [[Fiber]], which is a resource that has a lifecycle.
 *
 * {{{
 *
 *   // Start a fiber that continuously prints "A".
 *   // After 10 seconds, cancel the fiber.
 *   F.start(F.delay(println("A")).foreverM).flatMap { fiber =>
 *     F.sleep(10.seconds) *> fiber.cancel
 *   }
 *
 * }}}
 *
 * In the above example, imagine the spawning fiber is canceled after it starts the printing
 * fiber, but before the latter is canceled. In this situation, the printing fiber is not
 * canceled and will continue executing forever, contending with other fibers for system
 * resources. Fiber leaks like this typically happen because some fiber that holds a reference
 * to a child fiber is canceled before the child terminates; like threads, fibers will not
 * automatically be cleaned up.
 *
 * Resource leaks like this are unfavorable when writing applications. In the case of [[start]]
 * and [[racePair]], it is recommended not to use these methods; instead, use [[background]] and
 * [[race]] respectively.
 *
 * The following example depicts a safer version of the [[start]] example above:
 *
 * {{{
 *
 *   // Starts a fiber that continuously prints "A".
 *   // After 10 seconds, the resource scope exits so the fiber is canceled.
 *   F.background(F.delay(println("A")).foreverM).use { _ =>
 *     F.sleep(10.seconds)
 *   }
 *
 * }}}
 *
 * ==Scheduling==
 *
 * Fibers are commonly referred to as ''lightweight threads'' or ''green threads''. This alludes
 * to the nature by which fibers are scheduled by runtime systems: many fibers are multiplexed
 * onto one or more native threads.
 *
 * For applications running on the JVM, the scheduler typically manages a thread pool onto which
 * fibers are scheduled. These fibers are executed simultaneously by the threads in the pool,
 * achieving both concurrency and parallelism. For applications running on JavaScript platforms,
 * all compute is restricted to a single worker thread, so multiple fibers must share that
 * worker thread (dictated by fairness properties), achieving concurrency without parallelism.
 *
 * [[cede]] is a special function that interacts directly with the underlying scheduler. It is a
 * means of cooperative multitasking by which a fiber signals to the runtime system that it
 * intends to pause execution and resume at some later time at the discretion of the scheduler.
 * This is in contrast to preemptive multitasking, in which threads of control are forcibly
 * yielded after a well-defined time slice.
 *
 * Preemptive and cooperative multitasking are both features of runtime systems that influence
 * the fairness and throughput properties of an application. These modes of scheduling are not
 * necessarily mutually exclusive: a runtime system may incorporate a blend of the two, where
 * fibers can explicitly yield back to the scheduler, but the runtime preempts a fiber if it has
 * not yielded for some time.
 *
 * For more details on schedulers, see the following resources:
 *
 *   1. https://gist.github.com/djspiewak/3ac3f3f55a780e8ab6fa2ca87160ca40
 *   1. https://gist.github.com/djspiewak/46b543800958cf61af6efa8e072bfd5c
 */
trait GenSpawn[F[_], E] extends MonadCancel[F, E] with Unique[F] {
```

[...omitted: method bodies and per-method scaladoc of GenSpawn.scala...]

## kernel/Fiber.scala (trait)

```scala
trait Fiber[F[_], E, A] extends Serializable {

  /**
   * Requests the cancelation of the fiber bound to this `Fiber` handle and awaits its
   * finalization.
   *
   * [[cancel]] semantically blocks the caller until finalization of the cancellee has
   * completed. This means that if the cancellee is currently masked, [[cancel]] will block
   * until it is unmasked and finalized.
   *
   * Cancelation is idempotent, so repeated calls to [[cancel]] simply block until finalization
   * is complete. If [[cancel]] is called after finalization is complete, it will return
   * immediately.
   *
   * [[cancel]] is uncancelable; a fiber that is canceling another fiber is masked from
   * cancelation.
   *
   * @see
   *   [[GenSpawn]] documentation for more details on cancelation
   */
  def cancel: F[Unit]

  /**
   * Awaits the completion of the fiber bound to this [[Fiber]] and returns its [[Outcome]] once
   * it completes.
   */
  def join: F[Outcome[F, E, A]]

  /**
   * Awaits the completion of the bound fiber and returns its result once it completes.
   *
   * If the fiber completes with [[Outcome.Succeeded]], the successful value is returned. If the
   * fiber completes with [[Outcome.Errored]], the error is raised. If the fiber completes with
   * [[Outcome.Canceled]], `onCancel` is run.
   */
  def joinWith(onCancel: F[A])(implicit F: MonadCancel[F, E]): F[A] =
    join.flatMap(_.embed(onCancel))

  /**
   * Awaits the completion of the bound fiber and returns its result once it completes.
   *
   * If the fiber completes with [[Outcome.Succeeded]], the successful value is returned. If the
   * fiber completes with [[Outcome.Errored]], the error is raised. If the fiber completes with
   * [[Outcome.Canceled]], the caller is indefinitely suspended without termination.
   */
  def joinWithNever(implicit F: GenSpawn[F, E]): F[A] =
    joinWith(F.never)

  /**
   * Awaits the completion of the bound fiber and returns its result once it completes.
   *
   * If the fiber completes with [[Outcome.Succeeded]], the successful value is returned. If the
   * fiber completes with [[Outcome.Errored]], the error is raised. If the fiber completes with
   * [[Outcome.Canceled]], the result is ignored.
   */
  def joinWithUnit(implicit F: MonadCancel[F, E], ev: Unit <:< A): F[A] = {
    val _ = ev
    joinWith(F.unit.asInstanceOf[F[A]])
  }
}
```

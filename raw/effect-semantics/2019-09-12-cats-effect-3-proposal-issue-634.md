# Cats Effect 3.0 Proposal (GitHub issue #634, D. Spiewak; historical design doc)

> Source: https://github.com/typelevel/cats-effect/issues/634
> Collected: 2026-11-10
> Published: 2019-09-12

*(moved from https://gist.github.com/djspiewak/fb7851cc4f804f851e70d15ba7c94bb1)*

*If you're someone for whom code speaks louder than words, here's a branch to ponder: https://github.com/typelevel/cats-effect/tree/ce3*

The following is a proposal for Cats Effect 3, collaboratively devised over the last few months by several of the maintainers and contributors to the library. I will frequently use first-person in this document (because I'm lazy), which is posted under my name (ditto), but it really was a joint effort. As with any joint effort, there has definitely been some healthy debate about several of the concepts in this proposal. For reference, these are the things we're the least sure about:

- `Concurrent` now takes two type parameters, and thus is somewhat less ergonomic
- `Region` has been added, along with some complex associated machinery
  + One component of that machinery is the `Safe.Case` type
- Several existing laws are retained (such as `Sync` being stack-safe)
- `ExecutionContext` appears in the API
- `ExitCase` is a really terrible name (the names in general need some polishing)

None of this is final! At all! Really. Now is the time for questions and debate and concerns and bike-shedding. Put forward your own ideas. Find fundamental problems with what we've done! The sky's the limit!

## Preamble

Before diving into the exact changes that we're proposing, I want to briefly talk about Cats Effect, what it is and where it fits in the ecosystem. Cats Effect is really two things at once:

- A set of abstractions for characterizing functional effectful runtimes in Scala
- A baseline, practical implementation of those abstractions

Both of these elements of the project are extremely important, though the success of the former in the ecosystem and in end-user applications has rendered the latter *less* important than it was at the conception of the project. Note that, from an ecosystem strategic standpoint, this implies that Cats Effect has three primary stakeholders:

- **Runtime Systems**. Otherwise known as "concrete datatypes". These are the *implementors* of the Cats Effect abstractions. The current (known) major members of this category are Monix and ZIO, in addition to Cats Effect itself, though technically monad transformers mean that there are an infinite number of inductive concrete types.
- **Middleware**. These are things like http4s, Doobie, Monix, and many many others. Basically any Scala code which uses Cats Effect and *doesn't* include a `main` function.
- **End Users**. Most of this code is closed-source, but there are some bits and pieces which are public, such as [quasar](https://github.com/slamdata/quasar). These are projects which are delivered to customers, deployed on servers, etc. They always include a `main`, or at least something like `IOApp`.

All three of these stakeholder categories exert equal pull on Cats Effect's design and future, though not all are concerned with the same things equally. Runtime Systems are almost entirely concerned with Cats Effect's abstractions and laws, for example, while End Users are concerned with functionality (one aspect of the abstractions, but often more relevantly the practical concrete `IO`) and syntax. Middleware often cares about both equally, although Middleware will often pull in exactly the opposite direction from Runtime Systems (desiring *more* functionality within a cleaner model which the runtime must find a way to implement). Sometimes, in order to satisfy the needs of one stakeholder, we need to compromise the desires of the other two. This is an unfortunate consequence of being pulled between so many worlds.

There's another aspect of this, as well, which is that Cats Effect really defines what it means to *be* a functional effectful runtime in Scala. Its abstractions are the language of effects on the JVM, and thus it both enables and constrains the Scala FP design space as a whole. This role in the ecosystem is not taken lightly, nor with ego. It means that every design decision made in Cats Effect has profound consequences for every single line of practical functional code written in Scala for years to come, and thus should be undertaken with commensurate care. (note that this is distinct from Cats, which does occupy a more keystone position in the ecosystem but has far fewer design *decisions* to make; after all, how many ways are there to define `Functor`?)

All of this is to try to lay down a clear and self-conscious vision of what Cats Effect *is*, where it fits in the ecosystem, and what its goals and constraints are. I've seen a lot of people discussing various ideas about what Cats Effect is and what it should do, based on their own biases and perspectives. This is what we, the maintainers and creators of Cats Effect, define it to be. These are the points which have shaped Cats Effect 3.

## `evalOn` and `async`

In the original work designing Cats Effect, I really wanted to keep `Async#async` from auto-shifting. The reason being that it was, in my experience, not at all uncommon to want to retain the continuation of an asynchronous effect on its calling pool, and the performance hit and contention from the enforced context shift is not something to ignore. This design decision led to a large number of other design outcomes, including `shift`, the shifting (no pun intended) semantics of `IO.fromFuture`, and more.

In retrospect, I think this was a mistake. While the use-cases that I had in mind certainly exist, they are vastly far in the minority compared to the more common use-case of wanting to take a continuation off of the calling pool as quickly as possible. More importantly, John De Goes makes an excellent point about local reasoning and `evalOn`. If `shift` is eliminated *and* `async` auto-shifts when in an `evalOn` continuation scope, then it is possible to lexically reason about thread pools. This is incredibly powerful, and it eliminates a very large class of common and hard-to-detect errors.

Even at the time, this was a slightly odd design. Monix has had auto-shifting `async` and lexical `evalOn` from the very start (predating Cats Effect entirely). I still believe that non-shifting `async` is useful, but I think it should be classified as what it is: unsafe. My proposal would be to eliminate `shift`, enforce auto-shifting semantics on `async`, promote `evalOn` as a first-class solution to the problem, and encourage implementing datatypes (such as `cats.effect.IO`) to optionally add their own `unsafeAsync` function, which captures a continuation without shifting. I believe Monix `Task` already has something like this, so the concept is relatively proven.

These semantics are already present in Monix and ZIO, and CE3 codifies them into law in the abstractions. To that end, it also will result in some very noticeable changes to the `cats.effect.IO` datatype, in order to comply with the new (safer) semantics.

To that end, the `Async` typeclass in Cats Effect 3 adds a pair of functions for accessing and manipulating the scoped executor:

```scala
trait Async[F[_]] extends ... {
  // returns an optional cancelation token
  def async[A](k: (Either[Throwable, A] => Unit) => F[Option[F[Unit]]]): F[A]

  // evalOn(executionContext, ec) <-> pure(ec)
  def evalOn[A](fa: F[A], ec: ExecutionContext): F[A]
  def executionContext: F[ExecutionContext]
}
```

You'll also note that `async` is actually `asyncF`. This is simply because `Async` implies `Sync`, meaning that you can always wrap your callback registrar in `delay` to lift it into `F`. This type signature is strictly more general than the existing one, since it provides a mechanism by which callbacks may be registered themselves through asynchronous actions without blocking a thread. The performance cost of the added `delay` is meaningful, but in our experience it is exceedingly rare to have repeated calls to `async` in the hot path, and in the event that you *are* doing things in the hot path, you probably shouldn't be working through a typeclass abstraction anyway.

The pair of functions, `evalOn` and `executionContext`, provide the mechanism for accessing the `MonadReader` (for the `ExecutionContext`) constraint on `F`. `evalOn` takes an effect and ensures that all *synchronous* actions within that effect, save for anything further-nested in an inner `evalOn`, will be evaluated on the specified `ExecutionContext`. The dual of this is the `executionContext` function, which produces the currently-dominant `ExecutionContext` within `F`. This is useful for interoperating with APIs which require direct access to an `ExecutionContext`, such as `Future`.

## Abstraction, `Concurrent`, and Parametricity

In the very beginning, Cats Effect was based on the principle that concrete effects (like `IO`) should be *atomic* and should represent a fully opaque, runnable action. This concept actually comes from Paul Chiusano, who used it as a foundational idea in his original design of fs2 (the rewrite of scalaz-stream). Semantics such as preemption (cancellation) and concurrency were intended to be handled at a higher level in the stack, by frameworks defining a richer (and thus, more error-prone) calculus.

To that end, early versions of Cats Effect really only needed to characterize a few things:

- Error handling
- Synchronous construction
- Asynchronous construction
- Safe execution

That last point, btw, is where `runAsync` came from.

Given the requirements were exclusively limited to the above, a hierarchy like the following (which was implemented in Cats Effect 0.1) makes a lot of sense:

<img src="https://docs.google.com/drawings/d/e/2PACX-1vSEqx1a11-ybl8EFgVL_lVG4zC_A4hBlTGhwQ7YhIIV15KVM7bXw6SZYPD1_Q8_F_OFGaUQPi8Gh93j/pub?w=684&amp;h=717">

The above is sufficient if we assume that base effects are atomic and the core runtime does not define things like cancellation or concurrency, but unfortunately it turns out that this design principle is problematic when applied to the broader ecosystem. My favorite example of this comes from fs2:

```scala
// given an fa: F[A]
val s: Stream[F, A] = Stream.eval(fa) ++ Stream.eval(fa)
val fa2: F[A] = s.compile.lastOrError
```

Even without knowing fs2's API, it seems relatively clear from the types that `fa2` and `fa *> fa` should be more or less equivalent. Or at the very least, should behave pretty much identically. Unfortunately, this wasn't *quite* the case with early versions of Cats Effect.

The reason for this is the atomicity design. As intended, fs2 defines a mechanism and semantics for concurrent preemption of running streams. This means that, within the confines of fs2, the stream `s` could be safely interrupted by some concurrent mechanism (i.e. another stream), all resources and such would be properly handled, and evaluation would be terminated as soon as possible preventing leakage of CPU resources on wasted work. This worked fine within fs2 itself, but as soon as you compiled back to the underlying effect type, all those semantics would be lost.

More specifically, assume `Stream.eval(fa2)`. This should be exactly the same as `s`, but it *wasn't* because `s` could be interrupted at the `++` boundary, while `Stream.eval(fa2)` couldn't be interrupted at all, and the `fa2` would run to completion. Concurrency and cancellation are linked together (due to the need to safely define what it means to handle errors in `race`), and omitting them from Cats Effect, which is *the definition of the runtime*, meant that all middleware needed to encode these semantics via captured side-effects in user space. This was safe, in a sense, but not composable.

To that end, `Concurrent`, `Fiber`, and `Bracket` were all added to the Cats Effect hierarchy, characterizing preemption and resource safety as part of the core calculus itself. These were much newer APIs than `Sync`, `Async` and friends (which had been vetted for over 5 years in Scalaz), but they had some precedent in Haskell's async libraries, in Monix, and in ZIO. Unfortunately, at the time the natural place to add `Concurrent` was *under* `Async` (meaning that all `Concurrent` types are also `Async`, and thus also `Sync`). This was a somewhat reasonable design, but it introduces a really annoying problem, which is that it is impossible to have a `Concurrent[F]` without *also* having `Sync[F]` and `Async[F]`. This is annoying precisely because of the power that those two typeclasses offer.

<img src="https://docs.google.com/drawings/d/e/2PACX-1vTzjkBvfqUnktT9ygUm2xbI5f7ynMsrrIwRZu-_QMhF8eZllGjCKbuQ_JJwuV6jY_ywZkCVIiHdgjha/pub?w=682&amp;h=1046">

`Sync` is defined by a single function, `delay`, which takes a thunk `=> A` as a parameter and wraps it up in an `F[A]`. In other words, it *captures side-effects*. `Async` is analogous, except for callbacks. This isn't news, and it's exactly what `Sync`/`Async` were designed to do, but unfortunately it means that, in theory, any function which takes these constraints can itself do *anything*. Consider the following type signature:

```scala
def foo[F[_]: Sync, A](a: A): F[A] = ???
```

What can this function do? What implementation can we swap in for the `???`? There's almost no way to tell. `Sync` does give us *some* reasoning power: `foo` cannot involve asynchrony without blocking a thread, for example. Just to drive the point home, here's another function, `bar`, which takes an `Applicative`:

```scala
def bar[F[_]: Applicative, A](a: A): F[A] = ???
```

There's only one implementation for this function: `a.pure[F]`. You really can't do anything else. Well, I mean you *can* (e.g. `unit[F] *> a.pure[F]`), but it's all equivalent to `a.pure[F]`. By contrast, `foo` may be `a.pure[F]`, or it could be `Sync[F] delay { println("hey there!"); a }`, or an infinite number of other things!

This is unfortunate, as reasoning is reduced considerably whenever these constraints are present, but unfortunately `Concurrent` inheriting from `Async` means that any time we want to talk about concurrency, we also have to talk about... literally everything (i.e. the space of all possible side-effects). This is too much, and the only way to resolve it is to flip things around, putting `Concurrent` at the top of the hierarchy and moving `Sync` and `Async` down below. (diagrams at the end)

Moving `Concurrent` to the top of the hierarchy (well, under `Bracket`) allows us to discuss concurrency in a *pure* fashion, without bringing in the messiness of capturing side-effects. It allows us to write functions which have access to considerable power, including forking and cancelation, but do not have access to *unlimited* power. Even more excitingly, it allows us to write laws not in terms of captured `var`s, but in terms of true substitutable equivalences. This in turn implies that we can define concrete implementations of `Concurrent` which are *weaker* than `IO` itself! This makes it possible to build tooling around `Concurrent` which allow for rich and deterministic testing of things like race conditions, cancellation, and other concurrent logic. This is very, very, very exciting.

As a brief aside, it's worth noting that there is still value in writing type signatures like `foo`'s. Even though it's difficult to reason about the body of `foo`, due to the power of `Sync`, the generic signature gives us the flexibility to instantiate `F` with different types. Not just different concrete runtimes (like Monix or ZIO), but different composable types on top of those runtimes, such as monad transformers. This expressive power has proven immensely useful in both the middleware and end user ecosystems of Cats Effect 1.

### Fixing `Fiber`

In current Cats Effect, `Fiber` has the following definition:

```scala
trait Fiber[F[_], A] {
  def cancel: F[Unit]
  def join: F[A]
}
```

This is nice and simple, but it hides a subtle pitfall. What is the result of the following?

```scala
for {
  f <- fa.start
  _ <- f.cancel
  a <- f.join
} yield a
```

Should it throw an error? Should it just… hang? Should it depend on whether or not `fa` completed evaluation before the `cancel` (say, if `fa` is really really fast to evaluate)? What makes the most sense here?

The types don't really give us anything to work with, and the semantics are equally obtuse and surprising. In Cats Effect 3, the goal is to do better, and we can do this by generalizing `Fiber` very slightly:

```scala
trait Fiber[F[_], E, A] {
  def cancel: F[Unit]
  def join: F[ExitCase[E, A]]
}
```

Same basic signature, but now `join` returns an `ExitCase`. If you're familiar with `ExitCase` in Cats Effect 1, you'll notice that this is a slightly different type: specifically, it now includes the result type, `A`. This is intentional, as `ExitCase` *itself* has been generalized to the following:

```scala
sealed trait ExitCase[+E, +A]

object ExitCase {
  final case class Completed[+A](a: A) extends ExitCase[Nothing, A]
  final case class Errored[+E](e: E) extends ExitCase[E, Nothing]
  case object Canceled extends ExitCase[Nothing, Nothing]
}
```

In a very real sense, `ExitCase` is the *algebra* of an effect: it may produce a value as a result, or it may error, or some outside fiber may cancel it. Thus, producing this type from `join` gives users the power to do whatever they want with the results.

However, surfacing cancellation as a value in this fashion yields some surprising consequences for certain use-cases. For example, one might want to `join` on a `Fiber`, then evaluate some logic in the event that the fiber is canceled, and then forward that cancellation on to the outer fiber (think: some sort of cleanup logic surrounding preemption). The signature of `join` allows us to do *half* of this, but critically it doesn't allow us to cancel the enclosing `Fiber` in which we `join`ed.

This is a bit weird, if you think about it. The first two of the `ExitCase` cases have corresponding *constructors* which can build effects that produce to those results:

- `Completed` ==> `pure`
- `Errored` ==> `raiseError`

So, what about `Canceled`? We certainly can't create a cancellation "value" simply by creating a fiber, canceling it, and then `join`ing on it, because that would just result in `ExitCase.Canceled.pure[F]`! This is also the problem with the previously described concrete use-case.

To resolve this, we introduce a new constructor, `canceled`, on `Concurrent`, which allows us to create an `F[A]` (for any `A`) which is already canceled.

Note that, unlike `raiseError`, there is no way to "eliminate" cancellation within a fiber. If someone cancels you, you're done. Your finalizers will run (anything you've bracketed), but that's all. *Other* fibers which are `join`ing on you can observe the cancellation and respond accordingly, but you yourself are done. This is consistent with the intended semantics of concurrent preemption.

As an added nicety (and something which hints that we're on the right track), the `Concurrent` laws are much easier to define (and more comprehensive) when `canceled` is a value that can just be constructed directly.

### Cancelability

By default, all three major concrete Cats Effect datatypes define their `flatMap` function (and all lawfully-equivalent combinators, such as `map`) to be cancellation points. This means that they serve as a sort of "safe point" in the computation chain where some external fiber may preempt evaluation, aborting the sequence. As a simple example using `IO`:

```scala
val ioa = IO(computeA())
val iob = IO(computeB())

(ioa *> iob).start.flatMap(_.cancel)
```

In the above, it is very likely that `computeA()` is run, but also quite likely that `computeB()` will *not* be run. This is because, conceptually speaking, the cancellation status of the fiber is "checked" by the `*>` operation. We can't cancel `computeA()` while it is running, since it is some sort of opaque side-effect that could be doing anything, but once it finishes we can check for the cancel signal before we move on to `computeB()`, and so that's exactly what we do. In other words, cancellation isn't really magic, it arises naturally from the fact that we're in control of our sequential composition.

This is the so-called "auto-cancelable model". The *default* is that `flatMap` is cancelable, and thus it is possible to cut off wasteful computation as early as possible in the event that something else has preempted it. This is in contrast to the "continual model", which is what was implemented by Monix prior to the introduction of cancellation into Cats Effect. In the continual model, `flatMap` is *not* a safe point, and chains of sequential actions cannot be interrupted by default. There are some significant advantages to this model, in that you have a guarantee that potentially-dependent sequential effects are going to run, regardless of what's happening in other fibers, but it also can result in wasting time on computations which will ultimately be ignored, and even can give rise to deadlocks.

These two models hint at a fundamental tension: the auto-cancelable model gives us better efficiency and avoids deadlocks in case of preemption, while the continual model provides better safety guarantees.

Ultimately, both models are necessary to some degree. There will always be critical regions of your program which must be evaluated in an "all or nothing" fashion, without permitting interruption between actions. However, in order to avoid leaking resources, particularly in looping chains (infinite fibers), cancelation must be respected. Cats Effect 1 addresses this issue by effectively assuming that all sequential chains are cancelable by default, while providing an "escape hatch" in the form of the `uncancelable` function.

`uncancelable` takes an action, `F[A]`, and produces that same action with the added guarantee that cancelation will be ignored within that running action. Thus, if any component of `F[A]` is run, then *all* of it will be run. This function is implemented in terms of `bracket`, which is reasonable since resource acquisition (the first parameter of the `bracket` function) should generally be assumed to be a critical region, and atomicity is the desired default. Unfortunately, this gives rise to *another* problem, which is that it becomes impossible to safely acquire a semaphore (or any similar pattern) in Cats Effect. For example:

```scala
bracket(sem.acquire)(_ => useTheSemaphore)(_ => sem.release)
```

This seems quite reasonable at face value. We acquire the semaphore, use it, and then release it with the guarantee that the release will *always* run, even if our fiber is canceled. Unfortunately, there's a bit of a trap here, which is that the `sem.acquire` action is *itself* uncancelable! This means that if the semaphore is known to be unavailable, it's impossible for an outside fiber to cancel the acquisition, freeing up the resources of *this* fiber.

This problem was discussed at some length earlier this year in [the Cats Effect gitter room](https://gitter.im/typelevel/cats-effect?at=5c5f1a2fef98455ea4096756). In this discussion, Fabio Labella proposes that there is no "right answer" when choosing between the auto-cancelable and continual models. Neither is necessarily wrong, though auto-cancelation seems to be more convenient in practice. The more important thing is to provide a composable model for converting between models in a scoped fashion. Cats Effect 1 provides `uncancelable`, which allows users to move from the auto-cancelable model to the continual one. Fabio pointed out that what is missing is a `cancelable` function which converts from the continual model *back* to the auto-cancelable one. This proposal was later implemented in ZIO, where appears to be quite effective in practice!

Cats Effect 3 fully implements this proposal with the following pair of functions on `Concurrent`:

```scala
def cancelable[A](fa: F[A]): F[A]
def uncancelable[A](fa: F[A]): F[A]
```

These functions eliminate each other, such that `cancelable(uncancelable(fa)) <-> fa`, and `uncancelable(cancelable(fa)) <-> fa`, which is quite intuitive. Additionally, this pair of functions makes it possible for an implementing concrete datatype to define *either* the auto-cancelable or the continual models as their default, so long as they are able to lawfully implement these two "scoped mode shift" functions.

Using these functions, we can solve the semaphore acquisition problem from earlier:

```scala
bracket(cancelable(sem.acquire))(_ => useTheSemaphore)(_ => sem.release)
```

And now we have the best of both worlds: the semaphore is acquired interruptably (avoiding deadlocks), but if it is acquired we are guaranteed to safely release it (avoiding resource leaks).

As an aside, we can still safely provide a default implementation of `uncancelable` in the following way:

```scala
def uncancelable[A](fa: F[A]): F[A] =
  bracket(fa)(_.pure)(_ => unit)
```

This is, in fact, a law which relates `bracket` and `uncancelable` (and by extension, `cancelable`). Concrete implementations may have a more efficient version, however, and are always free to override this implementation with one of their own, so long as it complies with the stated equivalence.

### A Note on Fairness

In the context of functional effects, *fairness* is generally seen as equivalent to ensuring the current fiber yields its native thread back to the underlying executor in a timely fashion. Having a single logical thread hogging an underlying native thread for a long period of time inhibits responsiveness and can (in extreme cases) lead to thread pool starvation, as the application is unable to respond to incoming requests due to long-lived computations eating up all of the available resources and never yielding back control.

In the current version of Cats Effect, it isn't possible (without relying on implementation details) to write generic code which properly encodes fairness. This is particularly problematic when the underlying datatype (for example, `cats.effect.IO`) doesn't automatically self-optimize for fairness, and instead relies on users explicitly "opting in", which they cannot do through the abstractions.

To resolve this, Cats Effect 3 adds the following function to `Concurrent`:

```scala
def yieldTo[A](fa: F[A]): F[A]
```

All this does is introduce a fairness boundary. It yields control back to the underlying executor. Or rather, it is *suggested* that it does so. There are no laws here, nor really could there be. Implementations of `Concurrent` are expected to treat this as a serious hint from the user that this is an appropriate yield point for the current fiber, and fairness should be respected *here*. Implementations are certainly free to ignore this. As one plausible example, Monix automatically inserts fairness yield points (by default) once every 1024 actions. If one of those yields was automatically inserted *just* previous to the user sequencing `yieldTo`, then perhaps the user-initiated yield could be ignored. Tuning would be required to figure out whether or not this is actually a good idea.


[...omitted: sections "Wall-Clock Time" through "Bifunctor Classes"/"Variance Annotations"/"Non-Async Effects"; kept "Monadic Regions and Cancellation Semantics" and "Proposed Hierarchy" below...]

## Monadic Regions and Cancellation Semantics

Present-day Cats Effect defines an abstraction, `Bracket`, which is used to scope a *monadic region*. This monadic region is given certain properties with respect to errors and cancellation which makes it possible to acquire scarce resources in such a way that the freeing of those resources is guaranteed. The various properties implied by this functionality also make it possible to implement higher level primitives, such as `guarantee` (which allows one to suppress cancellation during a critical series of actions which must all be performed together).

This is very useful, but upon closer examination, something is missing. `Bracket` is defined by the following function signature (in Cats Effect 3):

```scala
def bracket[A, B](
    fa: F[A])(
    use: A => F[B])(
    handle: (A, ExitCase[E, B]) => F[Unit])
    : F[B]
```

The *scope* of the monadic region defined by `bracket` is statically constrained to be around the `use` effect. In other words, `handle` will be sequenced after `use`, no matter what. It isn't possible to acquire a resource, pair that acquisition with some finalizer which releases it, and then *return* that acquire/release pairing to some caller who can `flatMap` on it to build up a program dynamically.

In other words, `bracket` forms a *static* monadic region. This implies a clear dual: what about *dynamic* monadic regions? Fortunately, there is already quite a bit of prior art in this regard within the Cats Effect ecosystem alone! The `Resource` concrete datatype was implemented in Cats Effect 1.0 to handle this use-case:

```scala
val r: Resource[F, Unit] = for {
  a <- Resource.make(acquire)(release)
  _ <- ...
  _ <- ...
  _ <- ...
  _ <- ...
} yield ()

r.use(a => ...): F[B]
```

All of the `flatMap` calls on `Resource` extend the scope of the monadic region, to an arbitrary degree. The region is only closed when the `use` function is invoked, which interprets the structure into `Bracket[F]` and returns the result. This construct, as it turns out, is really really profoundly useful, and it can be found in several other guises throughout the ecosystem, including `fs2.Stream` and `zio.Managed` (though the latter is hard-coded to the `ZIO` type and is not generic, unlike `Resource` and `Stream`, but it does still define a dynamic monadic region).

In fact, the original paper introducing monadic regions ([Kiselyov and Shan, 2008](http://okmij.org/ftp/Computation/resource-aware-prog/region-io.pdf)) actually defines a dynamic region, not a static one! However, the paper is somewhat distinct from the situation in Cats Effect in that it *also* constrains effects to a closed algebra, predefined by the resource library itself. This allows the technique to encode statically provable resource safety (a very desirable property), but it also makes the technique undesirable in practice. Cats Effect allows users to construct arbitrary effects. In the absence of linear typing, this means that it is impossible to ever guarantee that resources are safely discarded (though we *can* guarantee that resources are always released), but the tradeoff is a much more practical effect system. Unfortunately, I am not aware of any prior literature describing dynamic monadic regions with open effect algebrae (though there is a little-known Haskell library which encodes the concept in a fashion similar to `Resource`).

This leaves Cats Effect in a somewhat undesirable position of having to break new ground on a previously-untried abstraction: `Region`. In general, Cats Effect attempts to be quite conservative in what it defines, given its highly central position in the ecosystem. In this case, there *is* prior art (e.g. `Resource`), but only in a concrete and specialized form. To that end, this particular construct remains the most divisive construct within the Cats Effect maintainership. Feel free to criticize accordingly!

As a motivating example, consider the following scenario:

- A pair of resources which must be safely acquired and release
- The acquisition semantics form a race, where each must be attempted and only the winner is kept open, while the loser is released and discarded

This is immensely difficult to encode with the current constructs. Higher level frameworks like fs2, Monix, and ZIO all have answers to this, but Cats Effect does not. Critically, the *reason* it is difficult to encode this use-case is the fact that `Resource` does not form a `Concurrent`, and thus lacks a `race` function. Unfortunately, the whole reason that `Resource` doesn't form a `Concurrent` comes down to the fact that `Concurrent` (in CE1) implies `Bracket`, and `Resource` cannot form a lawful `Bracket` since it is a dynamic region, not a static one.

To resolve this, in CE3 we split the notion of resource management into two typeclasses:

- `trait Bracket[F[_], E] extends Safe[F, E]`
- `trait Region[R[_[_], _], F[_], E] extends Safe[R[F, ?], E]`

This is all where `Safe` is defined as the following:

```scala
sealed trait Safe[F[_], E] extends MonadError[F, E]
```

So `Safe` forms a type union between `Bracket` and `Region`, which allows `Concurrent` to be defined in such a way that resource management is guaranteed, but the exact *form* of that resource management is unfixed:

```scala
trait Concurrent[F[_], E] extends MonadError[F, E] { self: Safe[F, E] =>
  // ...
}
```

So what then is `Region`, exactly? It is defined by two functions: `openCase` and `supersede`:

```scala
trait Region[R[_[_], _], F[_], E] extends Safe[R[F, ?], E] {
  def openCase[A](acquire: F[A])(release: (A, Case[_]) => F[Unit]): R[F, A]
  def supersede[B](rfa: R[F, _], rfb: R[F, B]): R[F, B]
}
```

The `openCase` function is analogous to `bracketCase` in the `Bracket` typeclass, in that it takes an acquisition effect and a release function, where the release function accepts the value which was acquired and the exit case (more on this type in a moment). For reference, `bracketCase` has the following definition:

```scala
def bracketCase[A, B](
    acquire: F[A])(
    use: A => F[B])(
    release: (A, Case[B]) => F[Unit])
    : F[B]
```

You'll notice that `bracketCase` defines the `Case` in terms of the result type, `B`. This is of course impossible with `openCase`, due to the fact that the region is dynamic, and the final result type is unknowable here – it depends on an arbitrary chain of `flatMap` calls which haven't happened yet!

`supersede` is tricky. The problem with a dynamic monadic region is not how to *open* the region, but rather how to *close* it. If every `flatMap` just extends the scope, you need some other function to "get you out", as it were. The problem is that the exact form of this function varies depending on the datatype. A value of type `Resource[F, A]` contains exactly one `A`, and we can get it out by calling `use`. A value of type `Stream[F, A]` contains many `A`s, or none at all, and there's no way of meaningfully abstracting over these two scenarios.

However, as it turns out, we don't really need to. `Monad` abstracts over things like this. For example, `IO[A]` is a monad that contains exactly one `A` (or an error), while `List[A]` contains zero or many `A`s. They're both `Monad`s, so how is this done exactly? By not attempting to abstract over *how you get things out*.

So rather than talking about how to get the `A` out of the `Region`, we instead talk about how to close the scope, which is what leads us to the following type signature:

```scala
def supersede[B](rfa: R[F, _], rfb: R[F, B]): R[F, B]
```

Given a region (`rfa`) who's value we don't care about, and another *completely independent* region (`rfb`), we can glue them together and produce the results of the second region, immediately closing the resource scope from the first region. In a sense, this is kind of like the `*>` operator, from `Apply`:

```scala
// roughly...
def *>[A, B](fa: F[A], fb: F[B]): F[B]
```

The `A` is ignored, we just return the `B`. Now it's *tempting* to say that we should just close the scope as soon as someone uses `*>` (or analogous), since we can guarantee that the `A` from within the region is not used in the result, and thus it is safe to free. However, in order to be lawful, `*>` must be consistent with `flatMap` in the following way:

```scala
def *>[A, B](fa: F[A], fb: F[B]): F[B] =
  fa.flatMap(_ => fb)
```

...and since `flatMap` extends the scope, so must `*>`. Intuitively, this translates into allowing someone to make the following transformation without changing the meaning of the code:

```scala
// this
for {
  _ <- fa
  b <- fb
} yield b

// ...must be the same as this
fa *> fb
```

And so we introduce a new function, `supersede`, which is functionally equivalent to `*>` save for the fact that `supersede` closes the left monadic region, while `*>` will nest the right region within the left (extending the left), just as `flatMap` would. This function also allows us to define a convenience function on `Region`, `close`, which has the following relatively trivial definition:

```scala
def close(rfa: R[F, _]): R[F, Unit] = supersede(rfa, unit)
```

Note that none of these functions allow you to abstract over getting values *out* of the region, but that's okay for the same reason that none of the other functions in Cats Effect allow you to abstract over getting values *out* of the effect, nor should they. Just as with `bracketCase`, these primitives are sufficient to write resource-safe code using dynamically scoped regions (as opposed to statically scoped in `Bracket`). This resource safety in turn makes it possible to write preemption-safe code with `Concurrent`, cancelable effects with `Async`, and so on.

### `ExitCase`

As you may have noticed in the above, `ExitCase` has been removed from the `bracketCase` and `openCase` signatures, replaced with just `Case`. This isn't because a new type has been introduced, but rather it is because the *concept* of cancellation has been removed from `Bracket` and `Region`! It's impossible to arrive in a situation where cancellation is relevant with *just* a `Bracket` or `Region`. Thus, it doesn't really make sense for either of them to codify the concept. Instead, we use a constrained type member to invert the contravariance and allow `Case` to be refined by subtypes:

```scala
sealed trait Safe[F[_], E] extends MonadError[F, E] {
  type Case[A]
  implicit def CaseInstance: MonadError[Case, E] with Traverse[Case]
}
```

(it's still an open question if we *need* the `Traverse` constraint, though clearly `ExitCase` can satisfy it)

Clearly we can define all of the laws for `Bracket` and `Region` without referring to cancellation, and those laws can be strengthened in `Concurrent` to deal with the `Canceled` case, but the real question is what this means for end-user syntax. Users want to write type signatures such as this one:

```scala
def foo[F[_], A](fa: F[A])(implicit F: Bracket[F, Throwable]) = ???
```

Is that constraint still meaningful without `ExitCase`? Yes, yes it is! The Scala compiler will define `F.Case` to be an existential type, meaning that it is entirely unknowable within the body of `foo`. We can still *have* values of that type, we just can't *do* anything with them. This in turn means that we're free to write generic code on top of raw `Bracket`, like above, but if we have an instance of `Case`, we can't get anything out of it (without using `Traverse`, see the note above).

In practice, this means that raw `Bracket` is perfectly useful if all you need is the `bracket` function. If you need the more powerful `bracketCase`, then you *probably* need to constrain the `Case` type in some way. For example, you can always constrain it to be precisely `ExitCase`:

```scala
def bar[F[_], A](fa: F[A])(implicit F: Bracket.Aux[F, Throwable, ExitCase[Throwable, ?]]) = ???

// or equivalently

def bar[F[_], A](fa: F[A])(implicit F: Bracket.Aux2[F, Throwable, ExitCase]) = ???
```

This is unwieldy, but we don't expect it to be particularly common.

`Concurrent` (and obviously everything that follows in the hierarchy) fixes `Case` to be `ExitCase[E, ?]`, which makes sense since `ExitCase` defines an algebra of results, errors, and cancellation, and `Concurrent` is where we introduce the concept of cancelability.

## Proposed Hierarchy

Now that all the conceptual groundwork has been laid, the following is provided as a visual reference for these ideas (and more). Note that not everything is fully reflected in this diagram, and also there are plenty of things here that are extensively motivated, but not described in this document. The most canonical reference will always be the source code. But still, visual aids are nice!

<img src="https://docs.google.com/drawings/d/e/2PACX-1vRsi2V3b1M8ADlMclP4nSYeuoZllL65TmyG8DnqoIczfm_tLLT0eJ2RNwZ8gjChnALvz-Brn1iQ2P3l/pub?w=1090&amp;h=1013">

(names still subject to bikeshedding!)

This is obviously *much* more complex than the current hierarchy, but I believe the complexity carries its weight. Some high-level points:

- `Safe` is not a typeclass. Rather, it is a closed type *union* between `Bracket` and `Region`. Saying that some `F` is `Safe` is to say that it has resource management capabilities, without specifying *how* resources are managed.
- `Bracket` represents a *static* monadic region, while `Region` represents a *dynamic* region.
- Neither `Bracket` nor `Region` know anything about cancellation. This is because it isn't possible to cancel anything without it being `Concurrent`! Their laws are defined in terms of errors (which they do know about, thanks to `MonadError`), while cancellation is codified (in types and laws) in `Concurrent`, similar to how `flatMap` is defined by `FlatMap` while `pure` is defined by `Applicative`, and additional laws are imposed on both when they come together in `Monad`.
- `Concurrent` extends neither `Bracket` nor `Region`, but rather uses the `Safe` union and self-types to say that all `Concurrent` instances must be *either* `Bracket` or `Region`
- `Temporal` splits the wall-clock related functions (`sleep` and `now`) away from general concurrency, allowing more granular abstractions (particularly useful for testing)
- It isn't reflected in the diagram, but `Temporal` (and above) are all generic in their error type, `E`, similar to `MonadError`. This is because `Throwable` is forced by the JVM when capturing side-effects, but `Temporal` and above are all pure and thus need not special-case a specific error type!
- `Async` is now the second-most powerful typeclass in the whole hierarchy. If you have an `Async`, you can do *almost* anything. Note that `Async` is still inhabited by types which are not isomorphic to `IO` though, such as `OptionT[IO, ?]`
- `Sync` is split away from the rest of the hierarchy, and it's the only typeclass other than `Concurrent` which *loses* power in the new system. Specifically, if you have a `Sync` and only a `Sync`, you do not automatically get resource management (via `bracket`). Due to subtype encoding of typeclasses, it is somewhat difficult to resolve this limitation, and I have never seen a use-case in the wild where someone needed `bracket` *and* `delay` and nothing else.
- `Effect` (and friends) represent an isomorphism with `IO` (and equivalent). In other words, any type which forms an `Effect` must be exactly as powerful as `IO`, while any type which forms a `Managed` must be exactly as powerful as `Resource[IO, ?]`. Analogously for `SyncEffect` (equivalent to `SyncIO`) and `SyncManaged`. These names are awful.
- `LiftIO` is gone, and the hierarchy does not special-case `IO` at any point


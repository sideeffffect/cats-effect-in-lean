# cats-effect issue #1744: Uncancelable boundaries compose poorly (closed)

> Source: https://github.com/typelevel/cats-effect/issues/1744
> Collected: 2026-11-10
> Published: 2021-02-28

The motivating example here:

```scala
val fa = F.uncancelable(_ => fb) // where fb is something long but not infinite
F.uncancelable(poll => poll(fa) *> fc)
```

If we imagine canceling the above where cancellation is observed within `fb`, the cancellation will be suppressed until the end of the inner `uncancelable` (within `fa`) and then immediately become visible *before* the end of the `poll`, meaning that `fc` will not run despite the fact that there's no apparent "gap" between the end of the `uncancelable` and the end of the `poll`.

The *reason* this is visible is to abide by the functor laws. Specifically, consider the following pair of expressions:

```scala
fa.onCancel(fin)
fa.map(identity).onCancel(fin)
```

Per the functor laws, these must be equivalent. Thus, cancellation must be visible *at the end* of an `uncancelable` block just as it would be at the end of an `uncancelable` block + some identity `map` or `flatMap` action. (note: there's some wiggle room here due to the soft nature of external cancellation and the fact that we're allowed to let the signal remain unobserved for some time, but internal cancellation makes this brutally and immediately apparent)

Unfortunately, this kind of visibility makes all sorts of things harder or impossible to express. `allocated` on `Resource` becomes particularly dangerous, since you can't guarantee that you're able to get at the *results* of the `allocated` before some cancellation is made visible, and the results contain a finalizer which would not have been run within the `uncancelable` block (since the cancellation would not be visible at all until after such a block). This scenario commonly arises with `Resource.make` (where the `poll` is ignored). This probably means that `Async[Resource]` in its present form has some tiny bits of unsound finalizer semantics littered around its implementation.

In general, it's just not possible to trust, given an arbitrary expression `F[A]`, that one of the following *always* holds:

1. Results which are sensitive to leakage in the face of cancellation are wrapped such that any cancellation manifested *within* `fa` produces the appropriate cleanup
2. Cancellation which is unobserved within `fa` cannot be observed within some enclosing expression prior to that expression's first opportunity to handle it without loss

This is violated because `fa` in the above internally handles cancellation to the best of its ability (by wrapping its own critical region), but the outer expression is unable to handle cancellation before the point at which the results from `fa` are lost, which is precisely what `fa` was trying to avoid by wrapping itself in `uncancelable`.

I can think of a couple ways of addressing this issue:

- Violate the functor laws. I'm... not fond of this one, though as noted above, there is some interpretive wiggle room in those laws when it comes to external cancellation, which is already a hint and not a dictate. Still, I'm not *super* comfortable with substitutability being violated in such a blatant and easy-to-hit fashion. Our current violation of substitutability of the functor identity in the face of external cancellation requires 512 `map(identity)` calls in a row, which seems... improbable.
- Beef up `onCancel` in some fashion which allows it to detect the case where a value is produced despite cancellation. This runs afoul of the same functor law issue though in very short order, since we have to answer the question of what it means for an `uncancelable` to finish successfully, then get `map`ped once, then hit this hypothetical `onCancel`.
- Enhance `uncancelable` to optionally carry a "canceled despite completion" finalizer which would be passed the result (or presumably, the error). This at least seems theoretically tractable, though it probably re-raises the same composability issues as `bracketCase`. Also it's not clear it really solves the problem, since there would still be a gap wherein cancellation could be lost.
- Adopt an idiom of accepting a `Poll[F]` as a parameter on signatures which would normally have an inner `uncancelable`. So `Resource#allocated`, for example, would take a `Poll[F]` rather than having its own `uncancelable`. That's not necessarily safe though because it kind of depends on the "good will" of the caller
- Adopt an idiom of accepting a `Poll[F]` as a parameter and then *composing* it with an inner `Poll[F]`. In other words, instead of `uncancelable(poll => poll(uncancelable(poll => poll(fa))))` (where the inner `uncancelable` is likely in a different function), we would carrot people to do something like `uncancelable(outer => uncancelable(inner => outer(inner(fa))))`. This would be an appropriate step to take for any subexpression which produces results which must be considered critical (e.g. `racePair` is dodgy).

None of these are great. All of them involve resource leaks, and the one which has a special case in which resources *don't* leak achieves this by violating algebraic identities... and still leaks resources if people (reasonably) assume those identities hold. I think the *last* of them is probably the most achievable.

Btw this whole discussion is related to #1027 
---COMMENTS---
SystemFw: I'm going to come out and say it: we should break the Functor laws here.
The cancellation model is too important, and without the "atomicity" (for lack of a better term)  of `poll`, it doesn't work.
Plus, there is precedent in ZIO, which also blatantly breaks the functor laws there, in favour of a more predictable model, where
```
    IO.sleep(1.seconds)
      .uncancelable
      .onCancel(IO.println("surely impossible"))
      .timeoutTo(500.millis, IO.unit)
      .unsafeRunSync()
```
 does _not_ print "surely impossible".

> , we would carrot people to do something like uncancelable(outer => uncancelable(inner => outer(inner(fa))))

Unfortunately this is entirely untenable. The very first use case that got me thinking about this problem is using semaphores safely, i.e. `uncancelable { poll => poll(acquire) >> doSomething }`, and you can't just modify `acquire` to inject the outer poll. I believe the same would apply to most interesting cases (barriers, latches, etc).

Ultimately I think the goal is producing the model that is easy to reason about: cats laws are generally helpful for that, but in this case they force into a highly unintuitive, highly unpredictable model, and ultimately the concurrency and resource safety characteristics of `IO` bring way more value to users.

As a mostly useless philosophical point, we can also conclude the interruptible binds break the Functor laws by definition

> on. Our current violation of substitutability of the functor identity in the face of external cancellation requires 512 map(identity) calls in a row

yeah, but nothing prevents us from checking the interruption status at every bind, in which case the situation would be exactly the same

---
djspiewak: I'll respond more in a bit, but just quickly pointing out… Making interruption visible on each bind would not violate the functor laws at all. What would be a more blatant violation is making it visible every-other bind, because now you can shift semantics by adding identity transformations. I called out our case because we are breaking the laws, but you would need to add 512 identities to see it.

This case with uncancelable is very, very easy to see. In fact, I believe your original motivating example actually has a small map at the end of the region, basically demonstrating my point.

Can you elaborate further on semaphore? I believe the case I'm talking about is only relevant when there are holes in the subregion, which acquire does not have.
---
vasilmkd: What if we (I) benchmark making interruption visible every iteration?
---
djspiewak: You can do that fairly directly by adding `@volatile` to `canceled` and removing the artificial memory barrier check (since it's no longer necessary). The last time I did this, it was quite a significant impact, though it depended on which benchmark you trusted.
---
vasilmkd: I'll think about it.
---
SystemFw: > What if we (I) benchmark making interruption visible every iteration?

that's sort of orthogonal though, having a safe interruption model would break that law anyway I think



---
djspiewak: > that's sort of orthogonal though, having a safe interruption model would break that law anyway I think

Well, yes and no. As an matter of implementation, if we just artificially saw cancelation constantly at every interleaving point, then we wouldn't need the trailing check on `uncancelable`, which is what makes it a closed region rather than an open one.
---
SystemFw: > Can you elaborate further on semaphore? I believe the case I'm talking about is only relevant when there are holes in the subregion, which acquire does not have.

spoke about this in private convos, but leaving it here for clarity. Imagine a bounded structure (e..g a queue) implemented with a normal queue and a semaphore, where you essentially need these semantics:
```
decreaseSlotsOrBlock.continual(enqueue)
```
that basically translates to:
```
uncancelable( poll  => 
   poll(
    uncancelable(poll => 
      modifySemaphoreState.flatMap(poll(deferred.get).onCancel(restoreSemaphoreState))
    )
   ) >> enqueue
)
```
the inner `uncancelable` is the definition of `acquire`, which you cannot touch,  and the current model, because of the artificial check after `uncancelable` which can result in cancelation even if the action within `poll` did complete, does not guarantee that `>>` behaves as `continual`, therefore breaking the whole model

---
djspiewak: I think I'm basically convinced that it's better to not do the check at the end of the `uncancelable` region. The only trick is to adjust things so that we can sweet-talk the laws
---
djspiewak: Okay I have a start pushed to `bug/uncancelable-gap` on [djspiewak/cats-effect](https://github.com/djspiewak/cats-effect). A ton of law tests are still failing, and the diff will give you a bit of an idea of the chaos that ensues when you decide to conditionally break the functor laws… That's honestly probably the root of the problem with the transformers. I'm also unsure of whether or not it's fixable in all cases, but I suspect most of them will be fine given some sweet-talking.

It's very likely that `PureConc` is going to need some tweaking, but that's probably easy. I didn't look into that yet. What I did do is add a law which codifies the behavior we expect (along with a note that it's a violation of other laws), so in theory this is something we can rely on going forward.

I'm going to be very intermittent for the next few days, so if anyone wants to take this and run with it, go forth!

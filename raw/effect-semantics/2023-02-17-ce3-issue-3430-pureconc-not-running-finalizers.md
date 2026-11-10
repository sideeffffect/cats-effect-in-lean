# cats-effect issue #3430: PureConc not running finalizers (open)

> Source: https://github.com/typelevel/cats-effect/issues/3430
> Collected: 2026-11-10
> Published: 2023-02-17

I might be missing something completely obvious, but `PureConc` doesn't seem to run finalizers:

```scala
    "foo" in {
      val t: PureConc[Int, Int] = for {
        c <- F.ref(0)
        latch <- F.deferred[Unit]
        fib <- F.start((latch.complete(()) *> F.never[Unit]).onCancel(c.update(_ + 1)))
        _ <- latch.get
        _ <- fib.cancel
        v <- c.get
      } yield v

      pure.run(t) mustEqual Outcome.Succeeded(Some(1))
    }
```

If I put this in `PureConcSpec`, it fails with:
```
Succeeded(Some(0)) != Succeeded(Some(1))
```
---COMMENTS---
djspiewak: Well that absolutely looks like a bug…
---
durban: Yeah, something is definitely wrong here; possibly more than one thing.

What I'm (almost) sure is wrong is `PureFiber#cancel`:
https://github.com/typelevel/cats-effect/blob/series/3.x/kernel-testkit/shared/src/main/scala/cats/effect/kernel/testkit/pure.scala#L391. It just writes `Outcome.Canceled()` into an mvar. So if the fiber will not be scheduled any more (e.g., because it went into a `never`), who will run the finalizers?

There is also something strange going on with pushing/popping the finalizers, but I'm not sure what (if anything).

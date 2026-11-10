# Cats Effect IOFiber run loop: masking counter, poll ids, cancelation check threshold (excerpts)

> Source: https://github.com/typelevel/cats-effect/blob/series/3.x/core/shared/src/main/scala/cats/effect/IOFiber.scala ; https://github.com/typelevel/cats-effect/blob/series/3.x/docs/core/io-runtime-config.md
> Collected: 2026-11-10
> Published: Unknown

## IOFiber.scala lines 205-250
```scala
    readBarrier()
    _join
  }

  /* masks encoding: initMask => no masks, ++ => push, -- => pop */
  @tailrec
  private[this] def runLoop(
      _cur0: IO[Any],
      cancelationIterations: Int,
      autoCedeIterations: Int): Unit = {
    /*
     * `cur` will be set to `EndFiber` when the runloop needs to terminate,
     * either because the entire IO is done, or because this branch is done
     * and execution is continuing asynchronously in a different runloop invocation.
     */
    if (_cur0 eq IO.EndFiber) {
      return
    }

    var nextCancelation = cancelationIterations - 1
    var nextAutoCede = autoCedeIterations
    if (nextCancelation <= 0) {
      // Ensure that we see cancelation.
      readBarrier()
      nextCancelation = runtime.cancelationCheckThreshold
      // automatic yielding threshold is always a multiple of the cancelation threshold
      nextAutoCede -= nextCancelation

      if (nextAutoCede <= 0) {
        resumeTag = AutoCedeR
        resumeIO = _cur0
        val ec = currentCtx
        rescheduleFiber(ec, this)
        return
      }
    }

    if (shouldFinalize()) {
      val fin = prepareFiberForCancelation(null)
      runLoop(fin, nextCancelation, nextAutoCede)
    } else {
      /* Null IO, blow up but keep the failure within IO */
      val cur0: IO[Any] = if (_cur0 == null) {
        IO.Error(new NullPointerException())
      } else {
        _cur0
```

## IOFiber.scala lines 555-605 (Uncancelable = tag 12, UnmaskRunLoop = tag 13)
```scala
        case 12 =>
          val cur = cur0.asInstanceOf[Uncancelable[Any]]

          if (isStackTracing) {
            pushTracingEvent(cur.event)
          }

          masks += 1
          val id = masks
          val poll = new Poll[IO] {
            def apply[B](ioa: IO[B]): IO[B] =
              IO.Uncancelable.UnmaskRunLoop(ioa, id, IOFiber.this)
          }

          val next =
            try cur.body(poll)
            catch {
              case t if UnsafeNonFatal(t) =>
                IO.raiseError(t)
              case t: Throwable =>
                onFatalFailure(t)
            }

          /*
           * The uncancelableK marker is used by `succeeded` and `failed`
           * to unmask once body completes.
           */
          conts = ByteStack.push(conts, UncancelableK)
          runLoop(next, nextCancelation, nextAutoCede)

        case 13 =>
          val cur = cur0.asInstanceOf[Uncancelable.UnmaskRunLoop[Any]]
          val self = this

          /*
           * we keep track of nested uncancelable sections.
           * The outer block wins.
           */
          if (masks == cur.id && (self eq cur.self)) {
            masks -= 1
            /*
             * The UnmaskK marker gets used by `succeeded` and `failed`
             * to restore masking state after `cur.ioa` has finished
             */
            conts = ByteStack.push(conts, UnmaskK)
          }

          runLoop(cur.ioa, nextCancelation, nextAutoCede)

        case 14 =>
          val cur = cur0.asInstanceOf[IOCont[Any, Any]]
```

## IOFiber.scala lines 1172-1177
```scala
  private[this] def shouldFinalize(): Boolean =
    canceled && isUnmasked()

  private[this] def isUnmasked(): Boolean =
    masks == 0

```

## docs/core/io-runtime-config.md (two rows)
| `cats.effect.cancelation.check.threshold` <br/> `CATS_EFFECT_CANCELATION_CHECK_THRESHOLD`        | `Int` (`512`)      | Configure how often cancellation is checked. By default, every 512 iterations of the run loop.                                    |
| `cats.effect.auto.yield.threshold.multiplier` <br/> `CATS_EFFECT_AUTO_YIELD_THRESHOLD_MULTIPLIER` | `Int` (`2`)        | `autoYieldThreshold = autoYieldThresholdMultiplier x cancelationCheckThreshold`. See [thread model](../thread-model.md).          |

[...omitted: rest of IOFiber.scala (1648 lines)...]

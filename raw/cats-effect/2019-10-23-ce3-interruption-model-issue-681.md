# Cats Effect 3.0 Interruption Model Proposal (issue, by SystemFw)

> Source: https://github.com/typelevel/cats-effect/issues/681
> Collected: 2026-11-10
> Published: 2019-10-23

Verbatim issue body. This proposal introduced the uncancelable/poll interruption model used in CE3.

I'm writing this proposal to describe the interruption model I'd like to see for cats-effect 3.0.
I'm only going to be focusing on semantics, things like the place in the hierarchy should be discussed elsewhere.
The main goals of this proposal are to lower the skill level needed to write interruption- and finalisation- safe code, and to preserve as much compositionality as possible in a problem that at some level defies it.
I'm going to try setting enough context to justify the decisions in this proposal, if you'd like to skip to the core of it, go to the `Combinators and Semantics` section.

## The problem

The notion of _safety_ in concurrent code is not univocal, and often revolves around two separate concepts: _finalisation_ and _interruption_.
Finalisation is needed to ensure that certain sections of the code will run in any scenario: for example to close resources, or restore some data to a valid state.
Interruption is needed to avoid using resources once the calling code has decided they are no longer needed, to prevent deadlock by offering timeouts, and to compositionally express several patterns (e.g. do this for 10 seconds, then start doing that).
Unfortunately, these two concepts are at odds at a _fundamental level_ :
- Interruption means "No matter what you are doing, stop"
- Finalisation means "No matter what you say, I must keep going"

From a theoretical point of view, there is no perfect compromise: by prioritising resource safety at all costs, you lose all interruption (this is current `uncancelable`), and by prioritising interruption at
all costs, you lose resource safety (this is your standard `flatMap`).
However, _I will posit that for our users, loss of resource safety is more dangerous than loss of interruption_, and therefore we shall keep things as interruptible as possible, but prioritise resource safety when breaking a tie. You will hopefully see exactly what I mean by this, further down in the proposal.

## Current situation

I think it's safe to say that currently writing resource safe code that preserves interruption is a matter for experts, for two reasons:

- The first is that users need to be familiar with `guaranteeCase`, `bracketCase`, `continual`,  `uncancelable`, and the interaction of those with `join` and `cancel`.  Each operation has subtly  different semantics when it comes to  interruption and they are all absolutely necessary in some scenarios.

- The second is more fundamental: writing interruption-aware code means basically writing code that restores some properties when  interruption happens. How and what needs to be restored generally depends on _where_  interruption happened, and _there is no way of knowing that_.
In practice this often means having to do complicated reasoning over  a piece of state and figure out how to write code which can always restore it to a "steady" state, which can get very complex.

## Principles

1) As a default, interruption can happen "anywhere" (any yield points, between any two flatMaps), but in critical sections the writer of the code needs to limit and control where interruption can happen. The ability to do this is what makes the model easier to use.
2) The _writer_ of the code, not the caller, is ultimately in control of  the resource safety of the code they write. It shouldn't be possible for someone to call code that was designed to be resource safe and somehow make it resource unsafe.
3) If we accept principle 2, it turns out that interruption behaves in exactly the opposite way, the _caller_ of the code is ultimately in control of whether the code they are calling is interruptible or
  not. The writer can _allow_ interruption in limited places, but  cannot have a guarantee that the final code will be interruptible,  it's up to the caller.
 In other words, it's possible for someone to call code that was  designed to be interruptible and make it uninterruptible. This is  unavoidable really (if we want principle 2), but I'll argue it's the
  correct default.  Also, preserving interruptibility is fairly easy, unlike today.

## Combinators and Semantics

### Safe regions

The model can be described by two functions (names can be changed):

```scala
def onCancel[A](fa: F[A])(finalizer: F[Unit]): F[A]
def mask[A](region: Poll => F[A]): F[A]

class Poll {
  def apply[B](fa: F[B]): F[B]
}


// or, in dotty to show the higher rank
def mask[A](region: ([B] => F[B] => F[B]) => F[A]): F[A]
```

`onCancel` attaches a finalizer to an `F[A]`. Upon interruption, all registered finalizers are run and the rest of the computation is short-circuited. The code triggering interruption backpressures on
said finalizers.
`mask` allows to control interruption in critical sections by defining a region in which interruption cannot happen unless one explicitly encloses the code that can be interrupted in a call to `Poll.apply`. 
Because the writer of the code now knows exactly at which points interruption can happen, it's easy to add the correct logic via `onCancel`. We will soon see that the semantics of `Poll.apply` need to be refined a bit, but this is a good first intuition.
Example:

```scala
val p1 = mask { poll =>
  for {
    r <- openResource
    c <- poll(waitOnCondition).onCancel(closeResource)
    _ <- modifySomeStateDependingOn(c, r).attempt
    _ <- closeResource
  } yield ()
}
```
Which means:

```scala
val p1 = mask { poll =>
  for {
    r <- openResource // cannot be interrupted
    // flatMap cannot be interrupted
    c <- poll(waitOnCondition).onCancel(closeResource) // waiting can be interrupted
    // flatMap cannot be interrupted
    r <- modifySomeStateDependingOn(c, r).attempt // cannot be interrupted
   // flatMap cannot be interrupted
    _ <- closeResource // cannot be interrupted
  } yield ()
}
```

Note that `p1` is _almost_ the same as
```scala
openResource.bracket { r =>
  waitOnCondition.flatMap { c =>
    modifySomeStateDependingOn(c, r).attempt
  }
}{closeResource}
```

but there is a crucial difference, in the `bracket` version `.flatMap` and `modifySomeState...` can be interrupted, which means the code now has to worry about restoring `SomeState`, without knowing ifinterruption happened on `waitOnCondition`, or in between, or in any of the `flatMaps` that might make up `modifySomeState...`, requiring complex reasoning to figure out what to restore `SomeState` to.
I hope this illustrates how much nicer this model is to work with, as you essentially get to build a safe region where you need one.

Note 1: 
In the snippet above I simply `attempt`ed any synchronous errors for brevity, but all sorts of error handling are possible of course.

Note 2:
In cats-effect 2.0, you have to `bracket` _and_ `continual` to write`p1` correctly.

### Nested regions and restore semantics

So, in the section above we have defined `Poll.apply`, which is called in an uninterruptible region defined by `mask`, as making its argument interruptible again. 
We will now see how these semantics are slightly wrong and require some refinement in order to comply with the principles above.
Imagine `p1` is being called by `p2`, which is also safety-aware:

```scala
val p2 = mask { poll =>
  _ <- openResource2 
  _ <- p1
  _ <- closeResource2
}
```

Now, `p2` _thinks_ it's safe, but it's unaware that inside `p1` there is an interruptible region defined by a call to `poll`, and so it can now be interrupted and not execute `closeResource2`.
In other words, writing resource safe code requires inspecting all downstream code to know whether a `flatMap` is safe, which in my opinion is not an acceptable solution.

We can solve this problem by changing the semantics of `Poll.apply`: a call to `Poll.apply` makes its argument _inherit_ the interruption status of the outer scope.
For example, if we have `def main = p1`, the outer scope interruption status is `interruptible` (by  default things are interruptible), and inside `p1` `waitOnCondition` inherits this status, i.e. it's
interruptible, and we have recovered the previous semantics.
However, when nested inside `p2`, the outer scope is `uninterruptible` since we are inside `mask`, and so the call to `poll` inside `p1` inherits that, and things are safe again.
If `p2` wants to allow interruption of `p1`, it can call `poll` again:
```scala
val p2 = mask { poll =>
  _ <- openResource2 
  _ <- poll(p1).onCancel(closeResource2)
  _ <- closeResource2
}

def main = p2
```

`p1.poll` inherits the status of `p2.poll`, which inherits `main`, meaning that `waitOnCondition` is now interruptible again, but none of the other parts are, which are the desired semantics. This extends to arbitrary nesting.

Let's highlight where the tradeoff lies: the caller of code written in`mask` can take code that is safely interruptible, and (perhaps accidentally) make it uninterruptible by not calling `poll` on it.
Or, to look at it from the other side, the _writer_ of code in `mask` cannot _guarantee_ that their code is interruptible, it can only allow for it by calling `poll`, but the caller will have the final say.

I think this is the correct tradeoff: as the caller, you know whether you care about interrupting one of the things you call or not, so the failure mode of forgetting to call `poll` is way less dangerous than the initial semantics, where the code you write can become interruptible because something way down in the callstack has used an interruptible region.

I think this as compositional as we can get, and hopefully explains principles 2 and 3, and clarifies what I mean by saying that on balance, resource safety is favoured.

## Relationship with `bracket` etc.

We don't have to rewrite `bracket` and co., and actually we could also forego `onCancel` and use `guaranteeCase`, but I'll point out for the sake of argument how our native combinators can be easily expressed in this model.
This should also serve as a small example section:

```scala
bracketCase = mask { poll =>
  acquire.flatMap { r =>
     poll(use(r))
       .onCancel(close(ExitCase.Canceled))
       .handleErrorWith(e => close(ExitCase.Error(e)) >> F.raiseError(e))
       .flatMap(result => close(ExitCase.Completed).as(result)) 
  }
  
interruptibleBracketCase = mask { poll =>
  poll(acquire).flatMap { r =>
     poll(use(r))
       .onCancel(close(ExitCase.Canceled))
       .handleErrorWith(e => close(ExitCase.Error(e)) >> F.raiseError(e))
       .flatMap(result => close(ExitCase.Completed).as(result)) 
  }
 
uncancelable = mask(_ => fa)

continual = mask { poll =>
  poll(fa).flatMap(f)
}
```

## Differences with Haskell

This model is obviously inspired by Haskell's async exceptions, but there is a huge difference: in haskell some blessed operations are interruptible even inside `mask`, for example `MVar.take`.
As argued above, I think this is not a great default in general, and it's even worse in cats-effect because things like `MVar` aren't built in and users can create their own blocking primitives.
Another obvious difference is that `onCancel/guaranteeCase` aren't the same as `handleErrorWith`, so you cannot catch interruption, whereas in haskell you can and you need to remember to rethrow.

## Open questions on `start`

There is an open question about `start`: the Haskell's equivalent (`forkIO`) has the spawned fiber inherit the interruption status if `forkIO` is called inside `mask`, with another primitive
`forkIOWithUnmask` to achieve independence.
I still haven't made up my mind as to which semantics are necessary or desirable here. The other questions are around what happens if users pass a `Poll` instance around, but I think those shouldn't constitute a blocker to the main drive of the proposal.

## Thanks

Sorry for the wall of text! I did my best to try and condensate this immensely tricky problem to its essence, but it still turned out super long.


# IO ADT and fiber state (model data)

> Sources: typelevel/cats-effect source at v3.7.1 (`IO.scala`, `IOFiber.scala`, `IOFiberConstants.java`, `ContState.scala`, `UnsafeNonFatal.scala`, `pure.scala`), read 2026-11-10; own Phase 2 steps 1–3 code in `CatsEffectInLean/Model/`
> Raw: [IO ADT and fiber state notes](../../raw/cats-effect/2026-11-10-io-adt-and-fiber-state-notes.md)

## Overview

Phase 2 steps 1–3: data definitions only, no step function. Files: `CatsEffectInLean/Model/Val.lean`, `Syntax.lean`, `Fiber.lean`, `State.lean`, `Examples.lean`. All types derive `DecidableEq`. `Examples.lean` checks them with `decide +kernel`. Builds in under 1 s.

## IO constructors

26 constructors, not 25: tags 0–24 plus `EndFiber` (tag -1). Order: `Pure`, `Error`, `Delay`, `RealTime`, `Monotonic`, `ReadEC`, `Map`, `FlatMap`, `Attempt`, `HandleErrorWith`, `Canceled`, `OnCancel`, `Uncancelable`, `UnmaskRunLoop`, `IOCont`, `Get`, `Cede`, `Start`, `RacePair`, `Sleep`, `EvalOn`, `Blocking`, `Local`, `IOTrace`, `ReadRT`, `EndFiber` (`IO.scala:2205-2334`). `IO.tag` gives the Scala tag. `TracingEvent` fields are dropped.

## User code

- A function in the syntax is `Fn.user id` (user code) or `Fn.rt k` (a runtime closure, `RtFn`). `IO`, `Fn`, `RtFn` are one mutual inductive.
- `UserEnv.call id arg refs : UserResult`. `refs` is a snapshot of the `Ref` cells.
- `UserResult` = list of `UserEffect` (`writeRef`, `invokeCb` now, `deferCb` later) + `UserOut` (`ret v`, `prog p`, `throw e`). So user code can return, raise, write refs, and call a callback 0, 1 or more times.
- `RtFn` holds runtime closures: `Get` finalizer, tracing deregister finalizer, `_cancel`, `_join`, `RacePair` and `Sleep` registrations. The step function adds more, each with a citation.

## Values and errors

- `Val`: unit, bool, nat, int, pair, left/right, none/some, `err`, three outcome values, handles (`fiber`, `ref`, `deferred`, `poll maskId fiber`, `cont state`, `ec`), opaque `trace`/`runtime`.
- `Val` has no `IO` values. Programs flow only through `UserOut.prog`.
- `Err` = code + `ErrKind` (`nonFatal`, `interrupted`, `fatal`), from `UnsafeNonFatal`. A fatal error never becomes an `Outcome`; it sets `State.fatal` (`onFatalFailure`, `IOFiber.scala:1597`).

## Fiber state and the two mask models

- `Fiber M` mirrors `IOFiber.scala:77-107`: `objectState` (typed `ObjEntry`), `finalizers`, `callbacks` (handle + `OutcomeCb`), `resumeTag`, `resumeIO`, `conts` (`ContK`), `canceled`, `mask : M`, `finalizing`, `outcome`, `suspended`.
- `ContState` cell: `initial | waiting | result r` + `wasFinalizing` + owner fiber.
- `MaskModel M` = the 8 mask operations of the run loop. Two instances:
  - `counterMaskModel` (`IOFiber`): `masks : Nat`; `poll` id = counter after increment.
  - `specMaskModel` (`PureConc`): stack of fresh ids, plus a `saved` stack so the shared `UnmaskK` can restore the right id. Id 0 is reserved for `prepareFiberForCancelation`.
- `Examples.lean` proves by `decide +kernel` that an escaped `poll` used in a new region at the same depth unmasks it in the counter model but not in the spec model. This is the first difftest question ([Semantics](semantics.md), "escaped poll").

## Global state and choices

- `State M`: `fibers`, `refs`, `deferreds`, `conts` (ContState cells), `clock`, `ready` (fiber ids in enqueue order), `running`, `events` (deferred callbacks, timers), `fatal`.
- `Choice`: `pick idx` (task boundary, replay), `step observe` (one run-loop iteration; `observe` = cancel visible), `cancel fiber` (external cancel), `fire idx` (event), `tick` (advance clock).

## Source surprises

1. 26 constructors, not 25 (plan text was wrong).
2. `Local` (tag 22) calls the user function without `try` (`IOFiber.scala:1058-1063`). A throw escapes the run loop. Candidate for a later property.
3. `succeeded` trampolines at depth 512 (`IOFiber.scala:1226-1229`): one extra run-loop iteration, so an extra cancelation check point inside long `map` chains.
4. Stack tracing (on by default) adds one extra finalizer per suspended `Get` (`IOFiber.scala:802-810`). The model must count it to match `finalizers.isEmpty()` checks.
5. `InterruptedException` is non-fatal for the run loop but fatal for Scala `NonFatal`.

## Open points

- `IO[IO[A]]` values (for example `Option[IO[Unit]]` from `async` registration) are not in `Val`. If derived combinators need them, make `Val` and `IO` mutual.
- `Ref` creation by user code (fresh id) is not a `UserEffect` yet.
- Spec model detail: `PureConc` `poll` also calls `realizeCancelation` after the body (`pure.scala:303`). The step function must decide where this goes.

## See Also

- [Source layout](source-layout.md)
- [Semantics of CE3](semantics.md)
- [TestControl and schedule replay](testcontrol.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Project plan](../methodology/project-plan.md)
- [Fairness and liveness](../semantics/fairness-and-liveness.md)

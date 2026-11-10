/-!
# Untyped values (`Val`)

Phase 2 step 1. One untyped value universe for all `IO` results (user decision 1,
`wiki/methodology/project-plan.md`). Typed wrappers appear only in property statements.

All citations are paths in the Cats Effect repository at tag `v3.7.1`.

Design rules (`wiki/lean/kernel-evaluation.md`): plain inductives, derived `DecidableEq`,
`Nat` ids for handles, no functions inside data.
-/

namespace CatsEffectInLean.Model

/-- The class of a `Throwable`, as the run loop sees it.

`core/shared/src/main/scala/cats/effect/unsafe/UnsafeNonFatal.scala:37-41`:
`VirtualMachineError`, `ThreadDeath`, `LinkageError` and `ControlThrowable` are fatal.
All other throwables are non-fatal. `InterruptedException` is non-fatal for the run loop
(`UnsafeNonFatal.scala:25-29`), but it is fatal for `scala.util.control.NonFatal`.
We keep it as a separate case because interruptible blocking code
(`core/jvm-native/src/main/scala/cats/effect/IOFiberPlatform.scala:27`) depends on it. -/
inductive ErrKind where
  /-- An ordinary exception. `UnsafeNonFatal(t) = true`. -/
  | nonFatal
  /-- `java.lang.InterruptedException`. `UnsafeNonFatal(t) = true`
  (`UnsafeNonFatal.scala:25-26`). -/
  | interrupted
  /-- `VirtualMachineError | ThreadDeath | LinkageError | ControlThrowable`.
  `UnsafeNonFatal(t) = false` (`UnsafeNonFatal.scala:38-39`). The run loop calls
  `onFatalFailure` (`core/shared/src/main/scala/cats/effect/IOFiber.scala:1597`), which shuts
  down all runtimes and rethrows. This is never a fiber `Outcome`. -/
  | fatal
  deriving DecidableEq, Repr

/-- A `Throwable` value. `code` tells apart different exceptions; `kind` is its class
for `UnsafeNonFatal` (`core/shared/src/main/scala/cats/effect/unsafe/UnsafeNonFatal.scala:37`).

Not modelled: `null` throwables and the `NullPointerException` that the run loop makes
for a `null` `IO` (`IOFiber.scala:247-249`) or a `null` callback result (`IOFiber.scala:647-648`).
Lean has no `null`. -/
structure Err where
  /-- Identity of the exception (two errors are equal if their codes and kinds are equal). -/
  code : Nat
  /-- The class of the exception for `UnsafeNonFatal`. -/
  kind : ErrKind := .nonFatal
  deriving DecidableEq, Repr

/-- `UnsafeNonFatal.apply` (`core/shared/src/main/scala/cats/effect/unsafe/UnsafeNonFatal.scala:37-41`). -/
def Err.isNonFatal (e : Err) : Bool :=
  match e.kind with
  | .fatal => false
  | _ => true

/-- An untyped value. Each Scala value that an `IO` program can produce maps to one `Val`.

Handles (`fiber`, `ref`, `deferred`, `cont`, `ec`) are `Nat` ids into tables of the global
state (`CatsEffectInLean/Model/State.lean`).

Outcome values are flat constructors (`ocSucceeded`, `ocErrored`, `ocCanceled`). They mirror
`Outcome[IO, Throwable, A]` (`kernel/shared/src/main/scala/cats/effect/kernel/Outcome.scala`).
In `IO`, `Succeeded(fa)` always holds `IO.pure(a)` (`IOFiber.scala:1492-1495`), so we keep
only `a`.

Not in `Val`: values of type `IO[A]`. User code returns programs through
`UserOut.prog` (`CatsEffectInLean/Model/Syntax.lean`). -/
inductive Val where
  /-- `()`. -/
  | unit
  /-- `Boolean`. -/
  | bool (b : Bool)
  /-- A natural number (`Int`/`Long` values that are not negative, durations in the
  virtual-time unit, counters). -/
  | nat (n : Nat)
  /-- A signed integer. -/
  | int (i : Int)
  /-- A pair `(a, b)` (`Tuple2`). -/
  | pair (a b : Val)
  /-- `Left(v)`. Also the error side of `Either[Throwable, A]` with `v = err e`. -/
  | left (v : Val)
  /-- `Right(v)`. -/
  | right (v : Val)
  /-- `None`. -/
  | none
  /-- `Some(v)`. -/
  | some (v : Val)
  /-- A `Throwable` as a value (for example the result of `attempt` is `left (err e)`). -/
  | err (e : Err)
  /-- `Outcome.Succeeded(IO.pure(v))`. -/
  | ocSucceeded (v : Val)
  /-- `Outcome.Errored(e)`. -/
  | ocErrored (e : Err)
  /-- `Outcome.Canceled()` (`IOFiber.scala:1577`). -/
  | ocCanceled
  /-- A `FiberIO[A]` handle: the id of an `IOFiber` (`IOFiber.scala:68-76`). -/
  | fiber (id : Nat)
  /-- A `Ref[IO, A]` handle: the id of a `Ref` cell. -/
  | ref (id : Nat)
  /-- A `Deferred[IO, A]` handle: the id of an `IODeferred` cell
  (`core/shared/src/main/scala/cats/effect/IODeferred.scala:21`). -/
  | deferred (id : Nat)
  /-- A `Poll[IO]` handle. `IOFiber` makes it in the `Uncancelable` branch
  (`IOFiber.scala:562-567`); it remembers the mask `id` and the fiber `self`.
  The meaning of `maskId` depends on the mask model (`CatsEffectInLean/Model/Fiber.lean`). -/
  | poll (maskId : Nat) (fiber : Nat)
  /-- The `cb` and `get` pair of one `IOCont` (`IOFiber.scala:642-757`): the id of its
  `ContState` cell. -/
  | cont (state : Nat)
  /-- An `ExecutionContext` handle (`ReadEC`, `EvalOn`). -/
  | ec (id : Nat)
  /-- Opaque `Trace` value (`IOTrace`, `IOFiber.scala:1065-1066`). -/
  | trace
  /-- Opaque `IORuntime` value (`ReadRT`, `IOFiber.scala:1069-1070`). -/
  | runtime
  deriving DecidableEq, Repr

/-- The final state of a fiber: `Outcome[IO, Throwable, Any]`
(`kernel/shared/src/main/scala/cats/effect/kernel/Outcome.scala`; field `outcome` at
`core/shared/src/main/scala/cats/effect/IOFiber.scala:106-107`). -/
inductive Outcome where
  /-- `Succeeded(IO.pure(v))`. -/
  | succeeded (v : Val)
  /-- `Errored(e)`. -/
  | errored (e : Err)
  /-- `Canceled()`. -/
  | canceled
  deriving DecidableEq, Repr

/-- An outcome as a value (for `join` and `racePair` results). -/
def Outcome.toVal : Outcome → Val
  | .succeeded v => .ocSucceeded v
  | .errored e => .ocErrored e
  | .canceled => .ocCanceled

/-- `Either[Throwable, A]` as a value: `Left(e)` becomes `left (err e)`. -/
def Val.ofExcept : Except Err Val → Val
  | .error e => .left (.err e)
  | .ok v => .right v

end CatsEffectInLean.Model

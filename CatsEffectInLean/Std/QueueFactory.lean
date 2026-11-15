import CatsEffectInLean.Std.QueueConcurrent
import CatsEffectInLean.Std.QueueAsync

/-!
# `Queue` factories for `IO` and one interface over both families (Phase 7, track Q)

`Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala` at `v3.7.1`. The factories take a
`GenConcurrent[F, ?]` and pick the family by the runtime class of the instance: `IO.asyncForIO`
is an `Async[IO]`, so `F match { case f0: Async[F] => ... }` (`Q:79-85`, `Q:161-167`,
`Q:200-206`) takes the `Async` branch for `IO`. The mirror follows the branches in order.

* `bounded(capacity)` (`Q:74-91`): `assertNonNegative` (`Q:230-234`, a synchronous throw for a
  negative capacity; `Nat` capacities are never negative); `1 < capacity < 65534`
  (`Short.MaxValue.toInt * 2`): `BoundedAsyncQueue`; else `capacity > 0`: `BoundedQueue`; else
  `synchronous`.
* `dropping(capacity)` (`Q:196-210`): `assertPositive` (`Q:236-240`) throws for `capacity <= 0`
  before an `IO` exists, so `capacity >= 1` is a precondition of `droppingIO`;
  `1 < capacity < 65534`: `DroppingAsyncQueue`; else `DroppingQueue`.
* `circularBuffer(capacity)` (`Q:224-228`): `assertPositive`, then `CircularBufferQueue`
  (no `Async` variant).
* `synchronous` (`Q:149-150`), `unbounded` (`Q:160-167`: `UnboundedAsyncQueue` for `IO`),
  `unsafeBounded` (`Q:130-137`), `unsafeUnbounded` (`Q:181-182`).
* The private factories `boundedForConcurrent`, `unboundedForConcurrent` (= `BoundedQueue` with
  capacity `Int.MaxValue`), `droppingForConcurrent` (`Q:93-110`) are the `Concurrent` twins; the
  difftest runner (package `cats.effect`) reaches them, and `bounded(1)`, `bounded(n >= 65534)`
  and `dropping(1)` reach the same classes through the public API.
-/

namespace CatsEffectInLean.Std.QueueFactory

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std

/-- `Short.MaxValue.toInt * 2` (`Q:78`). -/
def asyncLimit : Nat := 65534

/-- `Int.MaxValue` (`Q:103`). -/
def intMax : Nat := 2147483647

/-- The kind of queue a factory makes. -/
inductive QKind where
  | bounded (cap : Nat)
  | dropping (cap : Nat)
  | circular (cap : Nat)
  | synchronous
  | unbounded
  /-- `boundedForConcurrent(cap)` (`Q:93-95`). -/
  | boundedConc (cap : Nat)
  /-- `unboundedForConcurrent` (`Q:101-103`). -/
  | unboundedConc
  /-- `droppingForConcurrent(cap)` (`Q:108-110`). -/
  | droppingConc (cap : Nat)
  deriving DecidableEq, Repr

/-- The factory term (`F = IO`). -/
def newIO : QKind → IO
  | .bounded cap =>
    if 1 < cap && cap < asyncLimit then QueueAsync.newBIO .bounded cap
    else if cap > 0 then QueueConcurrent.newAbsIO .bounded cap
    else QueueConcurrent.newSyncIO
  | .dropping cap =>
    if 1 < cap && cap < asyncLimit then QueueAsync.newBIO .dropping cap
    else QueueConcurrent.newAbsIO .dropping cap
  | .circular cap => QueueConcurrent.newAbsIO .circular cap
  | .synchronous => QueueConcurrent.newSyncIO
  | .unbounded => QueueAsync.newUIO
  | .boundedConc cap => QueueConcurrent.newAbsIO .bounded cap
  | .unboundedConc => QueueConcurrent.newAbsIO .bounded intMax
  | .droppingConc cap => QueueConcurrent.newAbsIO .dropping cap

/-- The family of a queue object `o` (closure id). -/
inductive Fam where
  | abs
  | sync
  | async
  deriving DecidableEq, Repr

def famOf (o : Nat) : Option Fam :=
  match QueueConcurrent.Obj.ofId? o with
  | some (.abs _ _ _) => some .abs
  | some (.sync _) => some .sync
  | none => (QueueAsync.Obj.ofId? o).map fun _ => .async

/-- A non-queue value as a queue (a type error of the caller). -/
def notQueue : IO := .error { code := 999999, kind := .fatal }

/-- `q.offer(a)`. -/
def offerIO (o : Nat) (a : Val) : IO :=
  match famOf o with
  | some .abs => QueueConcurrent.offerIO o a
  | some .sync => QueueConcurrent.sOfferIO o a
  | some .async => QueueAsync.offerIO o a
  | none => notQueue

/-- `q.tryOffer(a)`. -/
def tryOfferIO (o : Nat) (a : Val) : IO :=
  match famOf o with
  | some .abs => QueueConcurrent.tryOfferIO o a
  | some .sync => QueueConcurrent.sTryOfferIO o a
  | some .async => QueueAsync.tryOfferIO o a
  | none => notQueue

/-- `q.take`. -/
def takeIO (o : Nat) : IO :=
  match famOf o with
  | some .abs => QueueConcurrent.takeIO o
  | some .sync => QueueConcurrent.sTakeIO o
  | some .async => QueueAsync.takeIO o
  | none => notQueue

/-- `q.tryTake`. -/
def tryTakeIO (o : Nat) : IO :=
  match famOf o with
  | some .abs => QueueConcurrent.tryTakeIO o
  | some .sync => QueueConcurrent.sTryTakeIO o
  | some .async => QueueAsync.tryTakeIO o
  | none => notQueue

/-- `q.size`. -/
def sizeIO (o : Nat) : IO :=
  match famOf o with
  | some .abs => QueueConcurrent.sizeIO o
  | some .sync => QueueConcurrent.sSizeIO
  | some .async => QueueAsync.sizeIO o
  | none => notQueue

/-- Run a queue closure (either family), if `id` is one. -/
def call? (id : Nat) (arg : Val) (v : View) : Option UserResult :=
  match QueueConcurrent.call? id arg v with
  | some r => some r
  | none => QueueAsync.call? id arg v

/-- The environment of a program that uses these queues, with user code `u` for the other ids. -/
def env (u : UserEnv) : UserEnv where
  call id arg refs := ((call? id arg { refs }).getD (u.callV id arg { refs }))
  callV id arg v := ((call? id arg v).getD (u.callV id arg v))

/-- The library closures that a public operation puts into a user program (`WellFormed`, clause 3):
the method entry closures (`this` = a held queue reference), the factory closures, `IO.ref`,
`IO.deferred`. The other closures are internal: user code never gets them. -/
def isPublic (id : Nat) : Bool :=
  match QueueConcurrent.QC.ofId? id with
  | some (.newRef _) | some .newDeferred | some (.mkAbs _ _) | some .mkSync
  | some (.offerBody _ _) | some (.tryOfferBody _ _) | some (.takeBody _) | some (.tryTakeBody _)
  | some (.getState _) | some .sizeK | some (.sOfferK _ _) | some (.sTryOfferBody _ _) | some (.sTakeK _)
  | some (.sTryTakeOuter _) => true
  | some _ => false
  | none =>
    match QueueAsync.QA.ofId? id with
    | some (.newB _ _) | some .newU | some (.bTakeBody _) | some (.bTryTake _) | some (.bSize _)
    | some (.bOfferBody _ _) | some (.bTryOffer _ _) | some (.dOffer _ _) | some (.uOffer _ _)
    | some (.uTryOffer _ _) | some (.uSize _) | some (.uTakeBody _) | some (.uTryTake _) => true
    | _ => false

end CatsEffectInLean.Std.QueueFactory

import CatsEffectInLean.Model.Codec

/-!
# The `Concurrent` queues: `AbstractQueue` (`BoundedQueue`, `DroppingQueue`, `CircularBufferQueue`) and `Synchronous` (mirror; Phase 7, track Q)

`Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala` at `v3.7.1`. These classes take a
`GenConcurrent[F, ?]`. With `F = IO` the instance is `IO.asyncForIO` (`IOAsync`,
`core/shared/src/main/scala/cats/effect/IO.scala:1996-2180`). The factories that pick them for
`IO` are in `Std/QueueFactory.lean`.

## How the Scala code maps to the model

* `F.ref(x)` = `IO.ref(x)` = `IO(Ref.unsafe(x))` (`IO.scala:2161`, `IO.scala:1822`): a `Delay`
  thunk that allocates a `Ref` cell (`UserEffect.allocRef`). `Ref.unsafe` makes a `SyncRef`
  (`kernel/jvm-native/src/main/scala/cats/effect/kernel/SyncRef.scala`): `get` = `F.delay(ar.get)`
  (`:30`), `update` = `F.delay(spin())` (`:65-73`), `modify` = `F.delay(spin)` (`:86-95`). One
  model step is atomic, so the CAS loop succeeds at once. `flatModify(f)` =
  `F.uncancelable(_ => F.flatten(modify(f)))` (`kernel/shared/src/main/scala/cats/effect/kernel/Ref.scala:123-124`).
* `F.deferred` = `IO.deferred` = `IO(new IODeferred)` (`IO.scala:2163`, `IO.scala:1824`);
  `d.complete(x)` = `IO { ... }` (`core/shared/src/main/scala/cats/effect/IODeferred.scala:62-69`,
  `RtFn.deferredComplete`); `d.get` = `cell.get()` (`IODeferred.scala:71`, `IO.deferredGetOf`). In
  this file every `get` is built on a `Deferred` that was made in the same call chain and that
  nobody else holds yet, so `cell.get()` gives `initial` (`IO.deferredGetOf d none`).
* `F uncancelable` = `Uncancelable` (`IO.scala:2095-2096`); `poll(fa)` = `UnmaskRunLoop`
  (`IOFiber.scala:564-567`, `IO.applyPoll`); `onCancel` = `OnCancel` (`IO.scala:590-591`);
  `F.unit` = `IO.unit` = `Pure(())` (`IO.scala:2020-2021`); `F.pure` = `Pure` (`IO.scala:2017-2018`).
* `fa.flatten` (cats syntax, `F.flatten`) = `flatMap(fa)(x => x)` (cats `FlatMap.flatten`; `IO#flatten`
  = `flatMap(ev)`, `IO.scala:472`): `.flatMap fa flattenK`. `fa.void` = `map(_ => ())`
  (`IO.scala:2152`, `IO.scala:961-962`); `fa.as(b)` = `map(_ => b)` (`IO.scala:2008-2009`,
  `IO.scala:182-183`); `fa *> fb` = `productR` = `flatMap(_ => fb)` with a strict `fb`
  (`IO.scala:2081-2082`, `IO.scala:903-904`); `fa.ifM(t, f)` = `flatMap(if (_) t else f)` with
  by-name `t`, `f` (cats `FlatMap.ifM`; `IO#ifM`, `IO.scala:568-569`).
* `modify` returns an `F[F[...]]`: the inner `F` is a value. A `Val` cannot hold an `IO`, so
  the modify thunk returns a descriptor (`Desc`), and `flattenK` (the `x => x` of `flatten`)
  builds the same term (`descIO`). The strict argument `fb` of `*>` is built when `*>` is
  called; it reads no state here, so `thenD d` (`_ => fb`) builds it from its descriptor.
* `this`: each lambda of a queue method captures the queue object. The object is a closure
  reference `Val.fn o` (decision 58) whose closure value holds the class, the capacity and the
  state `Ref` (`objVal`, `syncObjVal`). User code that holds the queue holds only `Val.fn o`; it
  cannot read or write the state `Ref` (a `Ref` inside a library closure is not available,
  `WF.avail`). The object itself is not a function in Scala; calling it gives a non-fatal
  error (`objCallErr`).
* Scala `Queue` = list (`enqueue` appends, `dequeue` takes the head). `filter(_ ne x)` and
  `head eq latch` compare `Deferred` objects by identity: the model compares `Deferred` ids.

## State encoding

`State(queue, size, takers, offerers)` (`Q:585-589`) = `pair (listV queue) (pair (nat size)
(pair (listV takers) (listV offerers)))`, takers and offerers as `Val.deferred d`.
`SyncState(offerers, takers)` (`Q:374-376`) = `pair (listV offerers) (listV takers)`, an offerer
as `pair a (deferred latch)`, a taker as `deferred latch`.
-/

namespace CatsEffectInLean.Std.QueueConcurrent

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of these closures (track Q: 50..59). -/
def ns : Nat := 50

/-- An ill-typed argument (impossible in Scala). -/
def illCode : Nat := 999999

/-- `require(capacity > 0, ...)` of `BoundedQueue` (`Q:515`): `IllegalArgumentException`. -/
def requireErr : Err := { code := 500001 }

/-- A call of a queue object as a function (not possible in Scala). -/
def objCallErr : Err := { code := 500002 }

/-- The three subclasses of `AbstractQueue` (`Q:382-583`). -/
inductive Kind where
  /-- `BoundedQueue` (`Q:511-543`). -/
  | bounded
  /-- `DroppingQueue` (`Q:545-560`). -/
  | dropping
  /-- `CircularBufferQueue` (`Q:562-583`). -/
  | circular
  deriving DecidableEq, Repr

def Kind.code : Kind → Nat
  | .bounded => 0
  | .dropping => 1
  | .circular => 2

def Kind.ofCode : Nat → Option Kind
  | 0 => some .bounded
  | 1 => some .dropping
  | 2 => some .circular
  | _ => none

/-! ## Objects -/

/-- The object `new BoundedQueue(capacity, state)` (or `DroppingQueue`, `CircularBufferQueue`). -/
def objVal (k : Kind) (cap s : Nat) : Val := cloVal ns 100 [.nat k.code, .nat cap, .ref s]

/-- The object `new Synchronous(stateR)`. -/
def syncObjVal (s : Nat) : Val := cloVal ns 101 [.ref s]

/-- The closure id of an object (odd: library). -/
def objId (k : Kind) (cap s : Nat) : Nat := 2 * valToNat (objVal k cap s) + 1

def syncObjId (s : Nat) : Nat := 2 * valToNat (syncObjVal s) + 1

/-- A decoded queue object. -/
inductive Obj where
  | abs (k : Kind) (cap s : Nat)
  | sync (s : Nat)
  deriving DecidableEq, Repr

/-- The object of closure id `o`. -/
def Obj.ofId? (o : Nat) : Option Obj :=
  if isLibId o then
    match (cloOfId o).bind ofCloVal with
    | some (50, 100, [.nat k, .nat cap, .ref s]) => (Kind.ofCode k).map fun k => .abs k cap s
    | some (50, 101, [.ref s]) => some (.sync s)
    | _ => none
  else none

/-! ## State -/

/-- `State(queue, size, takers, offerers)` (`Q:585-589`). -/
structure St where
  queue : List Val
  size : Nat
  takers : List Nat
  offerers : List Nat
  deriving DecidableEq, Repr

def St.toVal (s : St) : Val :=
  .pair (listV s.queue) (.pair (.nat s.size)
    (.pair (listV (s.takers.map .deferred)) (listV (s.offerers.map .deferred))))

/-- `State.empty` (`Q:592-593`). -/
def St.empty : St := { queue := [], size := 0, takers := [], offerers := [] }

/-- Deferred ids of a list value. -/
def defIds (v : Val) : Option (List Nat) :=
  (unlistV v).bind fun l => l.mapM fun
    | .deferred d => some d
    | _ => none

def St.ofVal? : Val → Option St
  | .pair q (.pair (.nat n) (.pair t o)) =>
    match unlistV q, defIds t, defIds o with
    | some q, some t, some o => some { queue := q, size := n, takers := t, offerers := o }
    | _, _, _ => none
  | _ => none

/-- `SyncState(offerers, takers)` (`Q:374-380`). -/
structure SSt where
  offerers : List (Val × Nat)
  takers : List Nat
  deriving DecidableEq, Repr

def SSt.toVal (s : SSt) : Val :=
  .pair (listV (s.offerers.map fun (a, l) => .pair a (.deferred l))) (listV (s.takers.map .deferred))

/-- `SyncState.empty` (`Q:379`). -/
def SSt.empty : SSt := { offerers := [], takers := [] }

def SSt.ofVal? : Val → Option SSt
  | .pair o t =>
    match (unlistV o).bind (fun l => l.mapM fun
        | .pair a (.deferred l) => some (a, l)
        | _ => none), defIds t with
    | some o, some t => some { offerers := o, takers := t }
    | _, _ => none
  | _ => none

/-- `ScalaQueue.filter(_ ne x)`. -/
def dropId (x : Nat) (l : List Nat) : List Nat := l.filter (· != x)

/-! ## Closures -/

/-- The lambdas. Field `o` is the queue object (`this`, a closure reference); `a` an element;
`w` an offerer `Deferred`; `t` a taker `Deferred`; `l` a latch `Deferred`; `m p` a poll;
`d` a descriptor; `b` a value. -/
inductive QC where
  /-- `Ref.unsafe(x)` thunk of `IO.ref` (`IO.scala:1822`). -/
  | newRef (x : Val)
  /-- `new IODeferred` thunk of `IO.deferred` (`IO.scala:1824`). -/
  | newDeferred
  /-- `new BoundedQueue(capacity, _)` etc. (`Q:95`, `Q:110`, `Q:227`). -/
  | mkAbs (k : Kind) (cap : Nat)
  /-- `new Synchronous(_)` (`Q:150`). -/
  | mkSync
  /-- `x => x` of `flatten`: build the term of descriptor `x`. -/
  | flattenK
  /-- `_ => fb` of `fa *> fb` (`fb` built before, descriptor `d`). -/
  | thenD (d : Val)
  /-- `_ => ()` of `void`. -/
  | voidK
  /-- `_ => b` of `as(b)`. -/
  | asK (b : Val)
  -- `AbstractQueue` (`Q:382-509`)
  /-- `poll => F.deferred[Unit] flatMap {...}` of `offer` (`Q:398-399`). -/
  | offerBody (o : Nat) (a : Val)
  /-- `offerer => { val modificationF = ...; modificationF.flatten }` (`Q:399-412`). -/
  | offerK (o : Nat) (a : Val) (m p : Nat)
  /-- The `modify` thunk of `offer` (`Q:400-410`). -/
  | offerMod (o : Nat) (a : Val) (w m p : Nat)
  /-- `_ => F.flatten(modify(f))` of `flatModify` in `tryOffer` (`Q:417`; `Ref.scala:123-124`). -/
  | tryOfferBody (o : Nat) (a : Val)
  /-- The `modify` thunk of `tryOffer` (`Q:417-427`). -/
  | tryOfferMod (o : Nat) (a : Val)
  /-- `poll => F.deferred[Unit] flatMap {...}` of `take` (`Q:430-431`). -/
  | takeBody (o : Nat)
  /-- `taker => { val modificationF = ...; modificationF.flatten }` (`Q:431-481`). -/
  | takeK (o : Nat) (m p : Nat)
  /-- The `modify` thunk of `take` (`Q:432-478`). -/
  | takeMod (o : Nat) (t m p : Nat)
  /-- `_ => F.flatten(modify(f))` of `flatModify` in `tryTake` (`Q:485`). -/
  | tryTakeBody (o : Nat)
  /-- The `modify` thunk of `tryTake` (`Q:485-497`). -/
  | tryTakeMod (o : Nat)
  /-- `SyncRef.get` thunk of `size` (`Q:499`; `SyncRef.scala:30`). -/
  | getState (o : Nat)
  /-- `_.size` of `size` (`Q:499`). -/
  | sizeK
  /-- The `modify` thunk of `cleanup` in `take` (`Q:456-464`). -/
  | cleanupTake (o : Nat) (t : Nat)
  /-- The `modify` thunk of `notifyNextTaker` (`Q:501-508`). -/
  | notifyNext (o : Nat)
  /-- The `modify` thunk of `cleanup` in `BoundedQueue.onOfferNoCapacity` (`Q:526-535`). -/
  | cleanupOffer (o : Nat) (w : Nat)
  -- `Synchronous` (`Q:242-360`)
  /-- `latch => F uncancelable {...}` of `offer` (`Q:247-248`). -/
  | sOfferK (o : Nat) (a : Val)
  /-- `poll => ...; modificationF.flatten` of `offer` (`Q:248-271`). -/
  | sOfferBody (o : Nat) (a : Val) (l : Nat)
  /-- The `modify` thunk of `offer` (`Q:253-268`). -/
  | sOfferMod (o : Nat) (a : Val) (l m p : Nat)
  /-- `if (_) F.unit else poll(offer(a))` of `checkCommit` (`Q:251`). -/
  | sIfCommit (o : Nat) (a : Val) (m p : Nat)
  /-- The `update` thunk of `cleanupF` in `offer` (`Q:261-264`). -/
  | sOfferCleanup (o : Nat) (l : Nat)
  /-- `_ => F.flatten(modify(f))` of `flatModify` in `tryOffer` (`Q:275`). -/
  | sTryOfferBody (o : Nat) (a : Val)
  /-- The `modify` thunk of `tryOffer` (`Q:275-290`). -/
  | sTryOfferMod (o : Nat) (a : Val)
  /-- `latch => F uncancelable {...}` of `commitF` (`Q:279-280`). -/
  | sCommitK (t : Nat) (a : Val)
  /-- `poll => taker.complete((a, latch)) *> poll(latch.get)` (`Q:280-283`). -/
  | sCommitBody (t : Nat) (a : Val) (l : Nat)
  /-- `latch => F uncancelable {...}` of `take` (`Q:293-294`). -/
  | sTakeK (o : Nat)
  /-- `poll => ...; modificationF.flatten` of `take` (`Q:294-344`). -/
  | sTakeBody (o : Nat) (l : Nat)
  /-- The `modify` thunk of `take` (`Q:295-341`). -/
  | sTakeMod (o : Nat) (l m p : Nat)
  /-- The `modify` thunk of `removeListener` (`Q:302-324`). -/
  | sRemoveListener (o : Nat) (l : Nat)
  /-- `if (_) F.unit else failCommit` of `removeListener.ifM(F.unit, failCommit)` (`Q:333`). -/
  | sIfFound (l : Nat)
  /-- `{ case (_, commitLatch) => commitLatch.complete(false).void }` (`Q:326-329`). -/
  | sFailCommit
  /-- `{ case (a, latch) => latch.complete(true).as(a) }` (`Q:336-338`). -/
  | sAwaitK
  /-- `_ => stateR.flatModify {...}` of `tryTake` (`Q:348-349`). -/
  | sTryTakeOuter (o : Nat)
  /-- `_ => F.flatten(modify(f))` of that `flatModify` (`Ref.scala:123-124`). -/
  | sTryTakeInner (o : Nat)
  /-- The `modify` thunk of `tryTake` (`Q:349-356`). -/
  | sTryTakeMod (o : Nat)
  deriving DecidableEq, Repr

def QC.toVal : QC → Val
  | .newRef x => cloVal ns 0 [x]
  | .newDeferred => cloVal ns 1 []
  | .mkAbs k cap => cloVal ns 2 [.nat k.code, .nat cap]
  | .mkSync => cloVal ns 3 []
  | .flattenK => cloVal ns 4 []
  | .thenD d => cloVal ns 5 [d]
  | .voidK => cloVal ns 6 []
  | .asK b => cloVal ns 7 [b]
  | .offerBody o a => cloVal ns 10 [.fn o, a]
  | .offerK o a m p => cloVal ns 11 [.fn o, a, .poll m p]
  | .offerMod o a w m p => cloVal ns 12 [.fn o, a, .deferred w, .poll m p]
  | .tryOfferBody o a => cloVal ns 13 [.fn o, a]
  | .tryOfferMod o a => cloVal ns 14 [.fn o, a]
  | .takeBody o => cloVal ns 15 [.fn o]
  | .takeK o m p => cloVal ns 16 [.fn o, .poll m p]
  | .takeMod o t m p => cloVal ns 17 [.fn o, .deferred t, .poll m p]
  | .tryTakeBody o => cloVal ns 18 [.fn o]
  | .tryTakeMod o => cloVal ns 19 [.fn o]
  | .getState o => cloVal ns 20 [.fn o]
  | .sizeK => cloVal ns 21 []
  | .cleanupTake o t => cloVal ns 22 [.fn o, .deferred t]
  | .notifyNext o => cloVal ns 23 [.fn o]
  | .cleanupOffer o w => cloVal ns 24 [.fn o, .deferred w]
  | .sOfferK o a => cloVal ns 30 [.fn o, a]
  | .sOfferBody o a l => cloVal ns 31 [.fn o, a, .deferred l]
  | .sOfferMod o a l m p => cloVal ns 32 [.fn o, a, .deferred l, .poll m p]
  | .sIfCommit o a m p => cloVal ns 33 [.fn o, a, .poll m p]
  | .sOfferCleanup o l => cloVal ns 34 [.fn o, .deferred l]
  | .sTryOfferBody o a => cloVal ns 35 [.fn o, a]
  | .sTryOfferMod o a => cloVal ns 36 [.fn o, a]
  | .sCommitK t a => cloVal ns 37 [.deferred t, a]
  | .sCommitBody t a l => cloVal ns 38 [.deferred t, a, .deferred l]
  | .sTakeK o => cloVal ns 39 [.fn o]
  | .sTakeBody o l => cloVal ns 40 [.fn o, .deferred l]
  | .sTakeMod o l m p => cloVal ns 41 [.fn o, .deferred l, .poll m p]
  | .sRemoveListener o l => cloVal ns 42 [.fn o, .deferred l]
  | .sIfFound l => cloVal ns 43 [.deferred l]
  | .sFailCommit => cloVal ns 44 []
  | .sAwaitK => cloVal ns 45 []
  | .sTryTakeOuter o => cloVal ns 46 [.fn o]
  | .sTryTakeInner o => cloVal ns 47 [.fn o]
  | .sTryTakeMod o => cloVal ns 48 [.fn o]

def QC.ofFields : Nat → List Val → Option QC
  | 0, [x] => some (.newRef x)
  | 1, [] => some .newDeferred
  | 2, [.nat k, .nat cap] => (Kind.ofCode k).map fun k => .mkAbs k cap
  | 3, [] => some .mkSync
  | 4, [] => some .flattenK
  | 5, [d] => some (.thenD d)
  | 6, [] => some .voidK
  | 7, [b] => some (.asK b)
  | 10, [.fn o, a] => some (.offerBody o a)
  | 11, [.fn o, a, .poll m p] => some (.offerK o a m p)
  | 12, [.fn o, a, .deferred w, .poll m p] => some (.offerMod o a w m p)
  | 13, [.fn o, a] => some (.tryOfferBody o a)
  | 14, [.fn o, a] => some (.tryOfferMod o a)
  | 15, [.fn o] => some (.takeBody o)
  | 16, [.fn o, .poll m p] => some (.takeK o m p)
  | 17, [.fn o, .deferred t, .poll m p] => some (.takeMod o t m p)
  | 18, [.fn o] => some (.tryTakeBody o)
  | 19, [.fn o] => some (.tryTakeMod o)
  | 20, [.fn o] => some (.getState o)
  | 21, [] => some .sizeK
  | 22, [.fn o, .deferred t] => some (.cleanupTake o t)
  | 23, [.fn o] => some (.notifyNext o)
  | 24, [.fn o, .deferred w] => some (.cleanupOffer o w)
  | 30, [.fn o, a] => some (.sOfferK o a)
  | 31, [.fn o, a, .deferred l] => some (.sOfferBody o a l)
  | 32, [.fn o, a, .deferred l, .poll m p] => some (.sOfferMod o a l m p)
  | 33, [.fn o, a, .poll m p] => some (.sIfCommit o a m p)
  | 34, [.fn o, .deferred l] => some (.sOfferCleanup o l)
  | 35, [.fn o, a] => some (.sTryOfferBody o a)
  | 36, [.fn o, a] => some (.sTryOfferMod o a)
  | 37, [.deferred t, a] => some (.sCommitK t a)
  | 38, [.deferred t, a, .deferred l] => some (.sCommitBody t a l)
  | 39, [.fn o] => some (.sTakeK o)
  | 40, [.fn o, .deferred l] => some (.sTakeBody o l)
  | 41, [.fn o, .deferred l, .poll m p] => some (.sTakeMod o l m p)
  | 42, [.fn o, .deferred l] => some (.sRemoveListener o l)
  | 43, [.deferred l] => some (.sIfFound l)
  | 44, [] => some .sFailCommit
  | 45, [] => some .sAwaitK
  | 46, [.fn o] => some (.sTryTakeOuter o)
  | 47, [.fn o] => some (.sTryTakeInner o)
  | 48, [.fn o] => some (.sTryTakeMod o)
  | _, _ => none

def QC.id (l : QC) : Nat := 2 * valToNat l.toVal + 1
def QC.fn (l : QC) : Fn := .user l.id

def QC.ofId? (id : Nat) : Option QC :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then QC.ofFields tag fs else none
    | none => none
  else none

/-! ## Descriptors of `IO` values held in values (tags 120..) -/

/-- `F.unit`. -/
def dUnit : Val := cloVal ns 120 []
/-- `F.pure(v)`. -/
def dPure (v : Val) : Val := cloVal ns 121 [v]
/-- `d.complete(x).void`. -/
def dCompleteVoid (d : Nat) (x : Val) : Val := cloVal ns 122 [.deferred d, x]
/-- `d.complete(x).as(b)`. -/
def dCompleteAs (d : Nat) (x b : Val) : Val := cloVal ns 123 [.deferred d, x, b]
/-- `(poll(offerer.get) *> poll(recurse)).onCancel(cleanup.flatten)` (`Q:537-538`). -/
def dOfferWait (o : Nat) (a : Val) (w m p : Nat) : Val := cloVal ns 124 [.fn o, a, .deferred w, .poll m p]
/-- `fb.void` with `fb = F.pure(true)` (`Q:573-574`, `Q:580`). -/
def dPureTrueVoid : Val := cloVal ns 125 []
/-- `await` (`Q:466-467`). -/
def dAwait (o t m p : Nat) : Val := cloVal ns 126 [.fn o, .deferred t, .poll m p]
/-- `release.complete(()) *> await` (`Q:473`). -/
def dReleaseAwait (o r t m p : Nat) : Val := cloVal ns 127 [.fn o, .deferred r, .deferred t, .poll m p]
/-- `poll(take).onCancel(notifyNextTaker.flatten)` (`Q:467`, the strict argument of `*>`). -/
def dTakeAgain (o m p : Nat) : Val := cloVal ns 128 [.fn o, .poll m p]
/-- `poll(recurse)` = `poll(offer(a))` (`Q:538`, the strict argument of `*>`). -/
def dOfferAgain (o : Nat) (a : Val) (m p : Nat) : Val := cloVal ns 129 [.fn o, a, .poll m p]
/-- `taker.complete((a, latch)) *> checkCommit` (`Q:257`). -/
def dFinish (o t : Nat) (a : Val) (l m p : Nat) : Val :=
  cloVal ns 130 [.fn o, .deferred t, a, .deferred l, .poll m p]
/-- `checkCommit` = `poll(latch.get).ifM(F.unit, poll(offer(a)))` (`Q:251`). -/
def dCheckCommit (o : Nat) (a : Val) (l m p : Nat) : Val := cloVal ns 131 [.fn o, a, .deferred l, .poll m p]
/-- `checkCommit.onCancel(cleanupF)` (`Q:267`). -/
def dCheckCommitClean (o : Nat) (a : Val) (l m p : Nat) : Val :=
  cloVal ns 132 [.fn o, a, .deferred l, .poll m p]
/-- `commitF` of `tryOffer` (`Q:279-284`). -/
def dCommit (t : Nat) (a : Val) : Val := cloVal ns 133 [.deferred t, a]
/-- `poll(latch.get)` (`Q:282`, the strict argument of `*>`). -/
def dPollGet (l m p : Nat) : Val := cloVal ns 134 [.deferred l, .poll m p]
/-- `awaitF` of `take` (`Q:336-338`). -/
def dAwaitF (o l m p : Nat) : Val := cloVal ns 135 [.fn o, .deferred l, .poll m p]

/-! ## Terms -/

/-- `d.complete(x)` (`IODeferred.scala:62-69`). -/
def completeIO (d : Nat) (x : Val) : IO := .delay (.rt (.deferredComplete d x))

/-- `modify(f).flatten` with modify thunk `th`. -/
def modFlatten (th : QC) : IO := .flatMap (.delay th.fn) QC.flattenK.fn

/-- `AbstractQueue#offer(a)` (`Q:397-414`). -/
def offerIO (o : Nat) (a : Val) : IO := .uncancelable (QC.offerBody o a).fn

/-- `AbstractQueue#tryOffer(a)` (`Q:416-427`): `state.flatModify {...}`. -/
def tryOfferIO (o : Nat) (a : Val) : IO := .uncancelable (QC.tryOfferBody o a).fn

/-- `AbstractQueue#take` (`Q:429-482`), a `val`. -/
def takeIO (o : Nat) : IO := .uncancelable (QC.takeBody o).fn

/-- `AbstractQueue#tryTake` (`Q:484-497`), a `val`: `state.flatModify {...}`. -/
def tryTakeIO (o : Nat) : IO := .uncancelable (QC.tryTakeBody o).fn

/-- `AbstractQueue#size` (`Q:499`): `state.get.map(_.size)`. -/
def sizeIO (o : Nat) : IO := .map (.delay (QC.getState o).fn) QC.sizeK.fn

/-- `notifyNextTaker.flatten` (`Q:467`, `Q:501-508`). -/
def notifyNextIO (o : Nat) : IO := modFlatten (.notifyNext o)

/-- `Synchronous#offer(a)` (`Q:246-272`). -/
def sOfferIO (o : Nat) (a : Val) : IO := .flatMap (.delay QC.newDeferred.fn) (QC.sOfferK o a).fn

/-- `Synchronous#tryOffer(a)` (`Q:274-290`): `stateR.flatModify {...}`. -/
def sTryOfferIO (o : Nat) (a : Val) : IO := .uncancelable (QC.sTryOfferBody o a).fn

/-- `Synchronous#take` (`Q:292-345`), a `val`. -/
def sTakeIO (o : Nat) : IO := .flatMap (.delay QC.newDeferred.fn) (QC.sTakeK o).fn

/-- `Synchronous#tryTake` (`Q:347-357`), a `val`. -/
def sTryTakeIO (o : Nat) : IO := .uncancelable (QC.sTryTakeOuter o).fn

/-- `Synchronous#size` (`Q:359`): `F.pure(0)`. -/
def sSizeIO : IO := .pure (.nat 0)

/-- `F.ref(State.empty).map(new K(capacity, _))` (`Q:95`, `Q:110`, `Q:227`). -/
def newAbsIO (k : Kind) (cap : Nat) : IO := .map (.delay (QC.newRef St.empty.toVal).fn) (QC.mkAbs k cap).fn

/-- `F.ref(SyncState.empty).map(new Synchronous(_))` (`Q:149-150`). -/
def newSyncIO : IO := .map (.delay (QC.newRef SSt.empty.toVal).fn) QC.mkSync.fn

/-- `poll(checkCommit-get).ifM(F.unit, poll(offer(a)))` (`Q:251`). -/
def checkCommitIO (o : Nat) (a : Val) (l m p : Nat) : IO :=
  .flatMap (IO.applyPoll (IO.deferredGetOf l none) m p) (QC.sIfCommit o a m p).fn

/-- `cleanupF` of `Synchronous#take` (`Q:301-334`): `removeListener.ifM(F.unit, failCommit)`. -/
def sTakeCleanupIO (o l : Nat) : IO := .flatMap (.delay (QC.sRemoveListener o l).fn) (QC.sIfFound l).fn

/-- The `IO` of a descriptor (impossible shapes: a fatal model error). -/
def descIO (d : Val) : IO :=
  match ofCloVal d with
  | some (50, 120, []) => .pure .unit
  | some (50, 121, [v]) => .pure v
  | some (50, 122, [.deferred d, x]) => .map (completeIO d x) QC.voidK.fn
  | some (50, 123, [.deferred d, x, b]) => .map (completeIO d x) (QC.asK b).fn
  | some (50, 124, [.fn o, a, .deferred w, .poll m p]) =>
    .onCancel (.flatMap (IO.applyPoll (IO.deferredGetOf w none) m p) (QC.thenD (dOfferAgain o a m p)).fn)
      (modFlatten (.cleanupOffer o w))
  | some (50, 125, []) => .map (.pure (.bool true)) QC.voidK.fn
  | some (50, 126, [.fn o, .deferred t, .poll m p]) =>
    .flatMap (.onCancel (IO.applyPoll (IO.deferredGetOf t none) m p) (modFlatten (.cleanupTake o t)))
      (QC.thenD (dTakeAgain o m p)).fn
  | some (50, 127, [.fn o, .deferred r, .deferred t, .poll m p]) =>
    .flatMap (completeIO r .unit) (QC.thenD (dAwait o t m p)).fn
  | some (50, 128, [.fn o, .poll m p]) => .onCancel (IO.applyPoll (takeIO o) m p) (notifyNextIO o)
  | some (50, 129, [.fn o, a, .poll m p]) => IO.applyPoll (offerIO o a) m p
  | some (50, 130, [.fn o, .deferred t, a, .deferred l, .poll m p]) =>
    .flatMap (completeIO t (.pair a (.deferred l))) (QC.thenD (dCheckCommit o a l m p)).fn
  | some (50, 131, [.fn o, a, .deferred l, .poll m p]) => checkCommitIO o a l m p
  | some (50, 132, [.fn o, a, .deferred l, .poll m p]) =>
    .onCancel (checkCommitIO o a l m p) (.delay (QC.sOfferCleanup o l).fn)
  | some (50, 133, [.deferred t, a]) => .flatMap (.delay QC.newDeferred.fn) (QC.sCommitK t a).fn
  | some (50, 134, [.deferred l, .poll m p]) => IO.applyPoll (IO.deferredGetOf l none) m p
  | some (50, 135, [.fn o, .deferred l, .poll m p]) =>
    .flatMap (.onCancel (IO.applyPoll (IO.deferredGetOf l none) m p) (sTakeCleanupIO o l)) QC.sAwaitK.fn
  | _ => .error { code := illCode, kind := .fatal }

/-! ## The closures -/

private def ret (v : Val) (es : List UserEffect := []) : UserResult := { effects := es, out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
def illTyped : UserResult := { out := .throw { code := illCode, kind := .fatal } }

/-- The `AbstractQueue` object `o` and its state in view `v`. -/
def absState (v : View) (o : Nat) : Option (Kind × Nat × Nat × St) :=
  match Obj.ofId? o with
  | some (.abs k cap s) =>
    match v.refs[s]? with
    | some x => (St.ofVal? x).map fun st => (k, cap, s, st)
    | none => none
  | _ => none

/-- The `Synchronous` object `o` and its state in view `v`. -/
def syncState (v : View) (o : Nat) : Option (Nat × SSt) :=
  match Obj.ofId? o with
  | some (.sync s) =>
    match v.refs[s]? with
    | some x => (SSt.ofVal? x).map fun st => (s, st)
    | none => none
  | _ => none

/-- `ar.compareAndSet(c, u)` succeeded: write `u`, return descriptor `d`. -/
def modRet (s : Nat) (u : St) (d : Val) : UserResult := ret d [.writeRef s u.toVal]

def sModRet (s : Nat) (u : SSt) (d : Val) : UserResult := ret d [.writeRef s u.toVal]

/-- `onOfferNoCapacity` (`Q:517-539`, `Q:549-556`, `Q:566-575`). -/
def onOfferNoCapacity (k : Kind) (o s : Nat) (st : St) (a : Val) (w m p : Nat) : UserResult :=
  match k with
  -- `BoundedQueue` (`Q:524-538`)
  | .bounded => modRet s { st with offerers := st.offerers ++ [w] } (dOfferWait o a w m p)
  -- `DroppingQueue`: `s -> F.unit` (`Q:556`)
  | .dropping => modRet s st dUnit
  -- `CircularBufferQueue`: `onTryOfferNoCapacity(s, a)`, then `fb.void` (`Q:573-574`, `Q:578-580`);
  -- `queue.dequeue` of an empty queue throws (never: `size >= capacity >= 1`)
  | .circular =>
    match st.queue with
    | _ :: rest => modRet s { st with queue := rest ++ [a] } dPureTrueVoid
    | [] => { out := .throw { code := 500003 } }

/-- `onTryOfferNoCapacity` (`Q:541-542`, `Q:558-559`, `Q:577-581`). -/
def onTryOfferNoCapacity (k : Kind) (s : Nat) (st : St) (a : Val) : UserResult :=
  match k with
  | .bounded | .dropping => modRet s st (dPure (.bool false))
  | .circular =>
    match st.queue with
    | _ :: rest => modRet s { st with queue := rest ++ [a] } (dPure (.bool true))
    | [] => { out := .throw { code := 500003 } }

/-- Run one closure on `arg` with view `v`. -/
def call (l : QC) (arg : Val) (v : View) : UserResult :=
  match l with
  | .newRef x => ret (.ref v.refs.length) [.allocRef x]
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred v.deferreds.length) }
  | .mkAbs k cap =>
    match arg with
    | .ref s =>
      -- `BoundedQueue`: `require(capacity > 0, ...)` (`Q:515`)
      if k == .bounded && cap == 0 then { out := .throw requireErr }
      else ret (.fn (objId k cap s))
    | _ => illTyped
  | .mkSync =>
    match arg with
    | .ref s => ret (.fn (syncObjId s))
    | _ => illTyped
  | .flattenK => prog (descIO arg)
  | .thenD d => prog (descIO d)
  | .voidK => ret .unit
  | .asK b => ret b
  -- `AbstractQueue#offer` (`Q:397-414`)
  | .offerBody o a =>
    match arg with
    | .poll m p => prog (.flatMap (.delay QC.newDeferred.fn) (QC.offerK o a m p).fn)
    | _ => illTyped
  | .offerK o a m p =>
    match arg with
    | .deferred w => prog (modFlatten (.offerMod o a w m p))
    | _ => illTyped
  | .offerMod o a w m p =>
    match absState v o with
    | some (k, cap, s, st) =>
      match st.takers with
      -- `takers.nonEmpty` (`Q:401-403`)
      | t :: rest =>
        modRet s { st with queue := st.queue ++ [a], size := st.size + 1, takers := rest } (dCompleteVoid t .unit)
      | [] =>
        -- `size < capacity` (`Q:405-406`)
        if st.size < cap then modRet s { st with queue := st.queue ++ [a], size := st.size + 1 } dUnit
        -- `onOfferNoCapacity(s, a, offerer, poll, offer(a))` (`Q:408-409`)
        else onOfferNoCapacity k o s st a w m p
    | none => illTyped
  -- `AbstractQueue#tryOffer` (`Q:416-427`)
  | .tryOfferBody o a => prog (modFlatten (.tryOfferMod o a))
  | .tryOfferMod o a =>
    match absState v o with
    | some (k, cap, s, st) =>
      match st.takers with
      | t :: rest =>
        modRet s { st with queue := st.queue ++ [a], size := st.size + 1, takers := rest }
          (dCompleteAs t .unit (.bool true))
      | [] =>
        if st.size < cap then modRet s { st with queue := st.queue ++ [a], size := st.size + 1 } (dPure (.bool true))
        else onTryOfferNoCapacity k s st a
    | none => illTyped
  -- `AbstractQueue#take` (`Q:429-482`)
  | .takeBody o =>
    match arg with
    | .poll m p => prog (.flatMap (.delay QC.newDeferred.fn) (QC.takeK o m p).fn)
    | _ => illTyped
  | .takeK o m p =>
    match arg with
    | .deferred t => prog (modFlatten (.takeMod o t m p))
    | _ => illTyped
  | .takeMod o t m p =>
    match absState v o with
    | some (_, cap, s, st) =>
      match st.queue, st.offerers with
      -- `queue.nonEmpty && offerers.isEmpty` (`Q:433-435`)
      | a :: rest, [] => modRet s { st with queue := rest, size := st.size - 1 } (dPure a)
      -- `queue.nonEmpty` (`Q:437-446`)
      | a :: rest, r :: tail =>
        if st.size - 1 < cap then
          modRet s { st with queue := rest, size := st.size - 1, offerers := tail } (dCompleteAs r .unit a)
        else modRet s { st with queue := rest, size := st.size - 1 } (dPure a)
      -- empty queue (`Q:448-477`)
      | [], [] => modRet s { st with takers := st.takers ++ [t] } (dAwait o t m p)
      | [], r :: rest => modRet s { st with takers := st.takers ++ [t], offerers := rest } (dReleaseAwait o r t m p)
    | none => illTyped
  -- `AbstractQueue#tryTake` (`Q:484-497`)
  | .tryTakeBody o => prog (modFlatten (.tryTakeMod o))
  | .tryTakeMod o =>
    match absState v o with
    | some (_, _, s, st) =>
      match st.queue, st.offerers with
      | a :: rest, [] => modRet s { st with queue := rest, size := st.size - 1 } (dPure (.some a))
      | a :: rest, r :: tail =>
        modRet s { st with queue := rest, size := st.size - 1, offerers := tail } (dCompleteAs r .unit (.some a))
      | [], _ => modRet s st (dPure .none)
    | none => illTyped
  -- `AbstractQueue#size` (`Q:499`)
  | .getState o =>
    match Obj.ofId? o with
    | some (.abs _ _ s) => ret (v.refs.getD s .unit)
    | _ => illTyped
  | .sizeK =>
    match St.ofVal? arg with
    | some st => ret (.nat st.size)
    | none => illTyped
  -- `cleanup` of `take` (`Q:456-464`)
  | .cleanupTake o t =>
    match absState v o with
    | some (_, _, s, st) =>
      match dropId t st.takers with
      | [] => modRet s { st with takers := [] } dUnit
      | t2 :: rest => modRet s { st with takers := rest } (dCompleteVoid t2 .unit)
    | none => illTyped
  -- `notifyNextTaker` (`Q:501-508`)
  | .notifyNext o =>
    match absState v o with
    | some (_, _, s, st) =>
      match st.takers with
      | [] => modRet s st dUnit
      | t :: rest => modRet s { st with takers := rest } (dCompleteVoid t .unit)
    | none => illTyped
  -- `cleanup` of `BoundedQueue.onOfferNoCapacity` (`Q:526-535`)
  | .cleanupOffer o w =>
    match absState v o with
    | some (_, _, s, st) =>
      match dropId w st.offerers with
      | [] => modRet s { st with offerers := [] } dUnit
      | w2 :: rest => modRet s { st with offerers := rest } (dCompleteVoid w2 .unit)
    | none => illTyped
  -- `Synchronous#offer` (`Q:246-272`)
  | .sOfferK o a =>
    match arg with
    | .deferred l => prog (.uncancelable (QC.sOfferBody o a l).fn)
    | _ => illTyped
  | .sOfferBody o a l =>
    match arg with
    -- `checkCommit` is built here (`Q:251`); `modificationF.flatten` (`Q:270`)
    | .poll m p => prog (modFlatten (.sOfferMod o a l m p))
    | _ => illTyped
  | .sOfferMod o a l m p =>
    match syncState v o with
    | some (s, st) =>
      match st.takers with
      -- `takers.nonEmpty` (`Q:254-258`)
      | t :: tail => sModRet s { st with takers := tail } (dFinish o t a l m p)
      -- (`Q:260-267`)
      | [] => sModRet s { st with offerers := st.offerers ++ [(a, l)] } (dCheckCommitClean o a l m p)
    | none => illTyped
  | .sIfCommit o a m p =>
    match arg with
    | .bool true => prog (.pure .unit)
    | .bool false => prog (IO.applyPoll (sOfferIO o a) m p)
    | _ => illTyped
  | .sOfferCleanup o l =>
    match syncState v o with
    -- `offerers.filter(_._2 ne latch)` (`Q:261-264`)
    | some (s, st) => ret .unit [.writeRef s { st with offerers := st.offerers.filter (·.2 != l) }.toVal]
    | none => illTyped
  -- `Synchronous#tryOffer` (`Q:274-290`)
  | .sTryOfferBody o a => prog (modFlatten (.sTryOfferMod o a))
  | .sTryOfferMod o a =>
    match syncState v o with
    | some (s, st) =>
      match st.takers with
      | t :: tail => sModRet s { st with takers := tail } (dCommit t a)
      | [] => sModRet s st (dPure (.bool false))
    | none => illTyped
  | .sCommitK t a =>
    match arg with
    | .deferred l => prog (.uncancelable (QC.sCommitBody t a l).fn)
    | _ => illTyped
  | .sCommitBody t a l =>
    match arg with
    | .poll m p => prog (.flatMap (completeIO t (.pair a (.deferred l))) (QC.thenD (dPollGet l m p)).fn)
    | _ => illTyped
  -- `Synchronous#take` (`Q:292-345`)
  | .sTakeK o =>
    match arg with
    | .deferred l => prog (.uncancelable (QC.sTakeBody o l).fn)
    | _ => illTyped
  | .sTakeBody o l =>
    match arg with
    | .poll m p => prog (modFlatten (.sTakeMod o l m p))
    | _ => illTyped
  | .sTakeMod o l m p =>
    match syncState v o with
    | some (s, st) =>
      match st.offerers with
      -- `offerers.nonEmpty` (`Q:296-298`)
      | (x, w) :: tail => sModRet s { st with offerers := tail } (dCompleteAs w (.bool true) x)
      -- (`Q:300-340`)
      | [] => sModRet s { st with takers := st.takers ++ [l] } (dAwaitF o l m p)
    | none => illTyped
  | .sRemoveListener o l =>
    match syncState v o with
    -- `filterFound(takers, ScalaQueue())` (`Q:305-323`)
    | some (s, st) =>
      ret (.bool (st.takers.contains l)) [.writeRef s { st with takers := dropId l st.takers }.toVal]
    | none => illTyped
  | .sIfFound l =>
    match arg with
    | .bool true => prog (.pure .unit)
    -- `failCommit` (`Q:326-329`), built in the `modify` of `take`: `latch.get` read `initial`
    | .bool false => prog (.flatMap (IO.deferredGetOf l none) QC.sFailCommit.fn)
    | _ => illTyped
  | .sFailCommit =>
    match arg with
    | .pair _ (.deferred c) => prog (.map (completeIO c (.bool false)) QC.voidK.fn)
    | _ => illTyped
  | .sAwaitK =>
    match arg with
    | .pair a (.deferred c) => prog (.map (completeIO c (.bool true)) (QC.asK a).fn)
    | _ => illTyped
  -- `Synchronous#tryTake` (`Q:347-357`)
  | .sTryTakeOuter o => prog (.uncancelable (QC.sTryTakeInner o).fn)
  | .sTryTakeInner o => prog (modFlatten (.sTryTakeMod o))
  | .sTryTakeMod o =>
    match syncState v o with
    | some (s, st) =>
      match st.offerers with
      | (x, w) :: tail => sModRet s { st with offerers := tail } (dCompleteAs w (.bool true) (.some x))
      | [] => sModRet s st (dPure .none)
    | none => illTyped

/-- Run closure id `id`: a `QC` closure, or a queue object (`objCallErr`). -/
def call? (id : Nat) (arg : Val) (v : View) : Option UserResult :=
  match QC.ofId? id with
  | some l => some (call l arg v)
  | none =>
    match Obj.ofId? id with
    | some _ => some { out := .throw objCallErr }
    | none => none

end CatsEffectInLean.Std.QueueConcurrent

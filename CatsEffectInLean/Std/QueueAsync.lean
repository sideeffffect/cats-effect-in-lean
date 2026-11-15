import CatsEffectInLean.Std.Queue

/-!
# The `Async` queues: `BoundedAsyncQueue`, `DroppingAsyncQueue`, `UnboundedAsyncQueue` (mirror; Phase 7, track Q)

`Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala`, `UU` =
`std/shared/src/main/scala/cats/effect/std/UnsafeUnbounded.scala`, both at `v3.7.1`. `F = IO`,
`Async[IO]` = `IO.asyncForIO` (`IOAsync`, `core/shared/src/main/scala/cats/effect/IO.scala:1996-2180`).

## Model simplification: sequential consistency (decision 59, plan Phase 7 item 3)

These queues are lock-free. Their buffers (`UnsafeBounded`, `Q:1014-1188`, a port of the JCTools
`MpmcArrayQueue`; `UnsafeUnbounded`, `UU:23-113`) and their waiter lists (`UnsafeUnbounded` of
callbacks) use CAS loops on atomics. The model runs every user call (one `F.delay` thunk) as one
atomic step under sequential consistency. Then:

* `UnsafeBounded.put(a)` appends `a` if fewer than `bound` elements are in the buffer, else it
  throws `FailureSignal` (`Q:1049-1080`); `take()` removes the first element, or throws
  `FailureSignal` if the buffer is empty (`Q:1082-1114`); `size()` is the number of elements
  (`Q:1032-1047`). The intermediate states of the CAS loops (`tail` moved but `sequenceBuffer`
  not yet, the spins of `Q:1055-1071`, `Q:1088-1104`) are not modelled.
* `UnsafeUnbounded`: `put` appends a cell and returns it as `clear` (`UU:38-49`); `clear()` sets
  its data to `null` (`UU:104-106`); `take()` removes the first cell (`UU:52-86`); `size()` counts
  the cells (`UU:28-36`). The spin of `UU:65-68` cannot happen.

A real JVM has more interleavings than this model (also inside one thunk); the model has a
subset of them. A refutation in this model is real on the JVM; a proof is only about the
sequentially consistent subset.

## How the Scala code maps to the model

* `F.delay` = `Delay` (`IO.scala:2104`); `F uncancelable` = `Uncancelable` (`IO.scala:2095-2096`);
  `F defer` = `Sync.defer` = `flatMap(delay(thunk))(x => x)` (`kernel/shared/src/main/scala/cats/effect/kernel/Sync.scala:61-62`);
  `F.cont(body)` = `IO.cont` = `IOCont(body)` (`IO.scala:2051`, `IO.scala:1548-1549`);
  `F.async(k)` = `IO.async(k)` (`IO.scala:2002-2003`, `IO.scala:1418-1431`);
  `F.asyncCheckAttempt(k)` = `IO.asyncCheckAttempt(k)` (`IO.scala:1998-2000`, `IO.scala:1353-1368`);
  `lift` is the identity for `G = IO`; `*>` = `flatMap(_ => that)` (strict `that`,
  `IO.scala:2081-2082`); `onCancel` = `OnCancel`; `poll(fa)` = `UnmaskRunLoop` (`IO.applyPoll`).
* A thunk that returns an `F[...]` returns a descriptor; `flattenK` (`x => x` of `defer` and of
  `flatten`) builds the term (`descIO`). `thenD d` is `_ => fb` of `*>` (strict `fb`, built
  before; it reads no state).
* `var received`/`var result` (`Q:630-631`, `Q:903-904`) and `var succeeded` (`Q:800`) are one
  model `Ref` cell that the thunk allocates. User code never holds it.
* A callback `k` in a waiter list is the `resume` of an `IOCont` (`ContState` id); `f(EitherUnit)`
  is `UserEffect.invokeCb s (right unit)` (`Std.Queue.Takers`, `Std.Queue.notifyOne`).
* `this` is a closure reference `Val.fn o` (decision 58); its closure value holds the class, the
  capacity and the cells of the buffer and the waiter lists. User code that holds the queue cannot
  reach these cells. Calling the object is a non-fatal error (`objCallErr`).
-/

namespace CatsEffectInLean.Std.QueueAsync

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.Queue (Takers notifyOne)

/-- The namespace of these closures (track Q: 50..59). -/
def ns : Nat := 52

def illCode : Nat := 999999

/-- `require(capacity > 1, ...)` (`Q:601`): `IllegalArgumentException`. -/
def requireErr : Err := { code := 520001 }

/-- A call of a queue object as a function (not possible in Scala). -/
def objCallErr : Err := { code := 520002 }

/-- The two subclasses of `BaseBoundedAsyncQueue`. -/
inductive BKind where
  /-- `BoundedAsyncQueue` (`Q:782-869`). -/
  | bounded
  /-- `DroppingAsyncQueue` (`Q:990-1011`). -/
  | dropping
  deriving DecidableEq, Repr

def BKind.code : BKind → Nat
  | .bounded => 0
  | .dropping => 1

def BKind.ofCode : Nat → Option BKind
  | 0 => some .bounded
  | 1 => some .dropping
  | _ => none

/-! ## Objects -/

/-- `new BoundedAsyncQueue(capacity)` / `new DroppingAsyncQueue(capacity)`: capacity, buffer cell,
takers cell, offerers cell. -/
def bObjVal (k : BKind) (cap b : Nat) : Val := cloVal ns 100 [.nat k.code, .nat cap, .ref b, .ref (b + 1), .ref (b + 2)]

/-- `new UnboundedAsyncQueue()`: buffer cell, takers cell. -/
def uObjVal (b : Nat) : Val := cloVal ns 101 [.ref b, .ref (b + 1)]

def bObjId (k : BKind) (cap b : Nat) : Nat := 2 * valToNat (bObjVal k cap b) + 1
def uObjId (b : Nat) : Nat := 2 * valToNat (uObjVal b) + 1

/-- A decoded object: buffer cell `b`, takers `b + 1`, offerers `b + 2`. -/
inductive Obj where
  | bnd (k : BKind) (cap b : Nat)
  | unb (b : Nat)
  deriving DecidableEq, Repr

def Obj.ofId? (o : Nat) : Option Obj :=
  if isLibId o then
    match (cloOfId o).bind ofCloVal with
    | some (52, 100, [.nat k, .nat cap, .ref b, .ref t, .ref f]) =>
      if t == b + 1 && f == b + 2 then (BKind.ofCode k).map fun k => .bnd k cap b else none
    | some (52, 101, [.ref b, .ref t]) => if t == b + 1 then some (.unb b) else none
    | _ => none
  else none

/-- The buffer cell of an object. -/
def Obj.buf : Obj → Nat
  | .bnd _ _ b => b
  | .unb b => b

/-! ## State -/

/-- The elements in buffer cell `b`. -/
def bufOf (v : View) (b : Nat) : List Val := (unlistV (v.refs.getD b .unit)).getD []

/-- The waiter list in cell `c`. -/
def waitersOf (v : View) (c : Nat) : Takers := Takers.ofVal (v.refs.getD c .none)

/-- `notifyOne(waiters)` (`Q:746-776`; `UnboundedAsyncQueue.notifyOne`, `Q:958-987`) on the
waiter list in cell `c`: write the cells that are left, then call `f(EitherUnit)`. -/
def notifyAt (c : Nat) (t : Takers) : List UserEffect :=
  let r := notifyOne t.cells
  .writeRef c (Takers.toVal { t with cells := r.1 }) ::
    (match r.2 with
     | some s => [.invokeCb s (.right .unit)]
     | none => [])

/-! ## Closures -/

inductive QA where
  /-- `x => x` of `defer`/`flatten`: the term of descriptor `x`. -/
  | flattenK
  /-- `_ => fb` of `fa *> fb` (descriptor `d`). -/
  | thenD (d : Val)
  /-- The thunk of `F.delay(new BoundedAsyncQueue(capacity))` (`Q:99`, `Q:136`) or
  `F.delay(new DroppingAsyncQueue(capacity))` (`Q:114`). -/
  | newB (k : BKind) (cap : Nat)
  /-- The thunk of `F.delay(new UnboundedAsyncQueue())` (`Q:106`, `Q:182`). -/
  | newU
  -- `BaseBoundedAsyncQueue` (`Q:598-777`)
  /-- `poll => F defer {...}` of `take` (`Q:616-617`). -/
  | bTakeBody (o : Nat)
  /-- The thunk of that `F defer` (`Q:617-686`). -/
  | bTakeThunk (o m p : Nat)
  /-- The `Cont` body `(k, get, lift) => G uncancelable {...}` of `wait` (`Q:635-637`). -/
  | bWaitBody (o r : Nat)
  /-- `poll => lift(F delay {...}).flatten` (`Q:637-671`). -/
  | bWaitUnc (o r s : Nat)
  /-- The thunk of that `F delay` (`Q:639-668`). -/
  | bWaitReg (o r s m p : Nat)
  /-- The thunk of `F.delay(clear())` of a taker (`Q:666`). -/
  | bClearTaker (o c : Nat)
  /-- The thunk of `notifyAnyway` of `take` (`Q:676-680`). -/
  | bNotifyTakers (o : Nat)
  /-- The thunk of `F.defer(if (received) F.pure(result) else poll(take))` (`Q:683`). -/
  | recvThunk (r : Nat)
  /-- `x => x` of that `F.defer`: `some a` gives `F.pure(a)`, `none` gives `poll(take)`. -/
  | recvK (o m p : Nat)
  /-- The thunk of `tryTake` (`Q:689-698`). -/
  | bTryTake (o : Nat)
  /-- The thunk of `size` (`Q:613`). -/
  | bSize (o : Nat)
  -- `BoundedAsyncQueue` (`Q:782-869`)
  /-- `poll => F defer {...}` of `offer` (`Q:787-788`). -/
  | bOfferBody (o : Nat) (a : Val)
  /-- The thunk of that `F defer` (`Q:788-853`). -/
  | bOfferThunk (o : Nat) (a : Val) (m p : Nat)
  /-- The `Cont` body of `wait = F.async[Unit] {...}` (`Q:803`; `IO.scala:1419-1428`). -/
  | oWaitBody (o : Nat) (a : Val) (r : Nat)
  /-- `poll => lift(k(resume)) flatMap {...}` (`IO.scala:1421-1426`). -/
  | oWaitUnc (o : Nat) (a : Val) (r s : Nat)
  /-- The thunk of `k(resume) = F delay {...}` (`Q:804-838`). -/
  | oWaitReg (o : Nat) (a : Val) (r s : Nat)
  /-- `{ case Some(fin) => G.onCancel(poll(get), lift(fin)); case None => get }` (`IO.scala:1423-1425`). -/
  | oWaitSel (o s m p : Nat)
  /-- The thunk of `F.delay(clear())` of an offerer (`Q:836`). -/
  | bClearOfferer (o c : Nat)
  /-- The thunk of `notifyAnyway` of `offer` (`Q:841-845`). -/
  | bNotifyOfferers (o : Nat)
  /-- The thunk of `F.defer(if (succeeded) F.unit else poll(offer(a)))` (`Q:850`). -/
  | oRecvThunk (r : Nat)
  /-- `x => x` of that `F.defer`. -/
  | oRecvK (o : Nat) (a : Val) (m p : Nat)
  /-- The thunk of `tryOffer` (`Q:867`, `Q:856-865`) and of `DroppingAsyncQueue#tryOffer`
  (`Q:999-1000`, `Q:1002-1010`). -/
  | bTryOffer (o : Nat) (a : Val)
  /-- The thunk of `DroppingAsyncQueue#offer` (`Q:993-997`). -/
  | dOffer (o : Nat) (a : Val)
  -- `UnboundedAsyncQueue` (`Q:871-988`)
  /-- The thunk of `offer(a) = F.delay(unsafeOffer(a))` (`Q:884`, `Q:879-882`). -/
  | uOffer (o : Nat) (a : Val)
  /-- The thunk of `tryOffer` (`Q:886-890`). -/
  | uTryOffer (o : Nat) (a : Val)
  /-- The thunk of `size` (`Q:892`). -/
  | uSize (o : Nat)
  /-- `poll => F defer {...}` of `take` (`Q:894-895`). -/
  | uTakeBody (o : Nat)
  /-- The thunk of that `F defer` (`Q:895-946`). -/
  | uTakeThunk (o m p : Nat)
  /-- The `Cont` body of `wait = F.asyncCheckAttempt[Unit] {...}` (`Q:907`; `IO.scala:1355-1364`). -/
  | uWaitBody (o r : Nat)
  /-- `poll => lift(k(resume)) flatMap {...}` (`IO.scala:1357-1363`). -/
  | uWaitUnc (o r s : Nat)
  /-- The thunk of `k(resume) = F delay {...}` (`Q:908-933`). -/
  | uWaitReg (o r s : Nat)
  /-- The `flatMap` function of `asyncCheckAttempt` (`IO.scala:1358-1362`). -/
  | uWaitSel (o s m p : Nat)
  /-- The thunk of `F.delay(clear())` (`Q:931`). -/
  | uClear (o c : Nat)
  /-- The thunk of `notifyAnyway` (`Q:936-940`). -/
  | uNotify (o : Nat)
  /-- The thunk of `tryTake` (`Q:949-956`). -/
  | uTryTake (o : Nat)
  deriving DecidableEq, Repr

def QA.toVal : QA → Val
  | .flattenK => cloVal ns 0 []
  | .thenD d => cloVal ns 1 [d]
  | .newB k cap => cloVal ns 2 [.nat k.code, .nat cap]
  | .newU => cloVal ns 3 []
  | .bTakeBody o => cloVal ns 10 [.fn o]
  | .bTakeThunk o m p => cloVal ns 11 [.fn o, .poll m p]
  | .bWaitBody o r => cloVal ns 12 [.fn o, .ref r]
  | .bWaitUnc o r s => cloVal ns 13 [.fn o, .ref r, .cont s]
  | .bWaitReg o r s m p => cloVal ns 14 [.fn o, .ref r, .cont s, .poll m p]
  | .bClearTaker o c => cloVal ns 15 [.fn o, .nat c]
  | .bNotifyTakers o => cloVal ns 16 [.fn o]
  | .recvThunk r => cloVal ns 17 [.ref r]
  | .recvK o m p => cloVal ns 18 [.fn o, .poll m p]
  | .bTryTake o => cloVal ns 19 [.fn o]
  | .bSize o => cloVal ns 20 [.fn o]
  | .bOfferBody o a => cloVal ns 21 [.fn o, a]
  | .bOfferThunk o a m p => cloVal ns 22 [.fn o, a, .poll m p]
  | .oWaitBody o a r => cloVal ns 23 [.fn o, a, .ref r]
  | .oWaitUnc o a r s => cloVal ns 24 [.fn o, a, .ref r, .cont s]
  | .oWaitReg o a r s => cloVal ns 25 [.fn o, a, .ref r, .cont s]
  | .oWaitSel o s m p => cloVal ns 26 [.fn o, .cont s, .poll m p]
  | .bClearOfferer o c => cloVal ns 27 [.fn o, .nat c]
  | .bNotifyOfferers o => cloVal ns 28 [.fn o]
  | .oRecvThunk r => cloVal ns 29 [.ref r]
  | .oRecvK o a m p => cloVal ns 30 [.fn o, a, .poll m p]
  | .bTryOffer o a => cloVal ns 31 [.fn o, a]
  | .dOffer o a => cloVal ns 32 [.fn o, a]
  | .uOffer o a => cloVal ns 40 [.fn o, a]
  | .uTryOffer o a => cloVal ns 41 [.fn o, a]
  | .uSize o => cloVal ns 42 [.fn o]
  | .uTakeBody o => cloVal ns 43 [.fn o]
  | .uTakeThunk o m p => cloVal ns 44 [.fn o, .poll m p]
  | .uWaitBody o r => cloVal ns 45 [.fn o, .ref r]
  | .uWaitUnc o r s => cloVal ns 46 [.fn o, .ref r, .cont s]
  | .uWaitReg o r s => cloVal ns 47 [.fn o, .ref r, .cont s]
  | .uWaitSel o s m p => cloVal ns 48 [.fn o, .cont s, .poll m p]
  | .uClear o c => cloVal ns 49 [.fn o, .nat c]
  | .uNotify o => cloVal ns 50 [.fn o]
  | .uTryTake o => cloVal ns 51 [.fn o]

def QA.ofFields : Nat → List Val → Option QA
  | 0, [] => some .flattenK
  | 1, [d] => some (.thenD d)
  | 2, [.nat k, .nat cap] => (BKind.ofCode k).map fun k => .newB k cap
  | 3, [] => some .newU
  | 10, [.fn o] => some (.bTakeBody o)
  | 11, [.fn o, .poll m p] => some (.bTakeThunk o m p)
  | 12, [.fn o, .ref r] => some (.bWaitBody o r)
  | 13, [.fn o, .ref r, .cont s] => some (.bWaitUnc o r s)
  | 14, [.fn o, .ref r, .cont s, .poll m p] => some (.bWaitReg o r s m p)
  | 15, [.fn o, .nat c] => some (.bClearTaker o c)
  | 16, [.fn o] => some (.bNotifyTakers o)
  | 17, [.ref r] => some (.recvThunk r)
  | 18, [.fn o, .poll m p] => some (.recvK o m p)
  | 19, [.fn o] => some (.bTryTake o)
  | 20, [.fn o] => some (.bSize o)
  | 21, [.fn o, a] => some (.bOfferBody o a)
  | 22, [.fn o, a, .poll m p] => some (.bOfferThunk o a m p)
  | 23, [.fn o, a, .ref r] => some (.oWaitBody o a r)
  | 24, [.fn o, a, .ref r, .cont s] => some (.oWaitUnc o a r s)
  | 25, [.fn o, a, .ref r, .cont s] => some (.oWaitReg o a r s)
  | 26, [.fn o, .cont s, .poll m p] => some (.oWaitSel o s m p)
  | 27, [.fn o, .nat c] => some (.bClearOfferer o c)
  | 28, [.fn o] => some (.bNotifyOfferers o)
  | 29, [.ref r] => some (.oRecvThunk r)
  | 30, [.fn o, a, .poll m p] => some (.oRecvK o a m p)
  | 31, [.fn o, a] => some (.bTryOffer o a)
  | 32, [.fn o, a] => some (.dOffer o a)
  | 40, [.fn o, a] => some (.uOffer o a)
  | 41, [.fn o, a] => some (.uTryOffer o a)
  | 42, [.fn o] => some (.uSize o)
  | 43, [.fn o] => some (.uTakeBody o)
  | 44, [.fn o, .poll m p] => some (.uTakeThunk o m p)
  | 45, [.fn o, .ref r] => some (.uWaitBody o r)
  | 46, [.fn o, .ref r, .cont s] => some (.uWaitUnc o r s)
  | 47, [.fn o, .ref r, .cont s] => some (.uWaitReg o r s)
  | 48, [.fn o, .cont s, .poll m p] => some (.uWaitSel o s m p)
  | 49, [.fn o, .nat c] => some (.uClear o c)
  | 50, [.fn o] => some (.uNotify o)
  | 51, [.fn o] => some (.uTryTake o)
  | _, _ => none

def QA.id (l : QA) : Nat := 2 * valToNat l.toVal + 1
def QA.fn (l : QA) : Fn := .user l.id

def QA.ofId? (id : Nat) : Option QA :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then QA.ofFields tag fs else none
    | none => none
  else none

/-! ## Descriptors (tags 120..) -/

/-- `F.unit` / `G.unit`. -/
def dUnit : Val := cloVal ns 120 []
/-- `F.pure(v)`. -/
def dPure (v : Val) : Val := cloVal ns 121 [v]
/-- `(poll(wait) *> F.defer(...)).onCancel(notifyAnyway)` of `BaseBoundedAsyncQueue#take` (`Q:683-684`). -/
def dBTakeWait (o r m p : Nat) : Val := cloVal ns 122 [.fn o, .ref r, .poll m p]
/-- `F.defer(if (received) F.pure(result) else poll(take))` (`Q:683`, `Q:943`; strict argument of `*>`). -/
def dRecv (o r m p : Nat) : Val := cloVal ns 123 [.fn o, .ref r, .poll m p]
/-- `poll(get).onCancel(lift(F.delay(clear())))` (`Q:666`). -/
def dGetClear (o s c m p : Nat) : Val := cloVal ns 124 [.fn o, .cont s, .nat c, .poll m p]
/-- `(poll(wait) *> F.defer(...)).onCancel(notifyAnyway)` of `BoundedAsyncQueue#offer` (`Q:850-851`). -/
def dOfferWait (o : Nat) (a : Val) (r m p : Nat) : Val := cloVal ns 125 [.fn o, a, .ref r, .poll m p]
/-- `F.defer(if (succeeded) F.unit else poll(offer(a)))` (`Q:850`). -/
def dORecv (o : Nat) (a : Val) (r m p : Nat) : Val := cloVal ns 126 [.fn o, a, .ref r, .poll m p]
/-- `(poll(wait) *> F.defer(...)).onCancel(notifyAnyway)` of `UnboundedAsyncQueue#take` (`Q:943-944`). -/
def dUTakeWait (o r m p : Nat) : Val := cloVal ns 127 [.fn o, .ref r, .poll m p]

/-! ## Terms -/

/-- `BaseBoundedAsyncQueue#take` (`Q:615-687`), a `val`. -/
def bTakeIO (o : Nat) : IO := .uncancelable (QA.bTakeBody o).fn

/-- `UnboundedAsyncQueue#take` (`Q:894-947`), a `val`. -/
def uTakeIO (o : Nat) : IO := .uncancelable (QA.uTakeBody o).fn

/-- `take` of object `o`. -/
def takeIO (o : Nat) : IO :=
  match Obj.ofId? o with
  | some (.unb _) => uTakeIO o
  | _ => bTakeIO o

/-- `BoundedAsyncQueue#offer(a)` (`Q:786-854`). -/
def bOfferIO (o : Nat) (a : Val) : IO := .uncancelable (QA.bOfferBody o a).fn

/-- `offer(a)` of object `o`. -/
def offerIO (o : Nat) (a : Val) : IO :=
  match Obj.ofId? o with
  | some (.unb _) => .delay (QA.uOffer o a).fn
  | some (.bnd .dropping _ _) => .delay (QA.dOffer o a).fn
  | _ => bOfferIO o a

/-- `tryOffer(a)` of object `o`. -/
def tryOfferIO (o : Nat) (a : Val) : IO :=
  match Obj.ofId? o with
  | some (.unb _) => .delay (QA.uTryOffer o a).fn
  | _ => .delay (QA.bTryOffer o a).fn

/-- `tryTake` of object `o`. -/
def tryTakeIO (o : Nat) : IO :=
  match Obj.ofId? o with
  | some (.unb _) => .delay (QA.uTryTake o).fn
  | _ => .delay (QA.bTryTake o).fn

/-- `size` of object `o`. -/
def sizeIO (o : Nat) : IO :=
  match Obj.ofId? o with
  | some (.unb _) => .delay (QA.uSize o).fn
  | _ => .delay (QA.bSize o).fn

/-- `F.delay(new BoundedAsyncQueue(capacity))` etc. -/
def newBIO (k : BKind) (cap : Nat) : IO := .delay (QA.newB k cap).fn

/-- `F.delay(new UnboundedAsyncQueue())`. -/
def newUIO : IO := .delay QA.newU.fn

/-- `wait` of `BaseBoundedAsyncQueue#take`: `F.cont(...)` = `IOCont(body)` (`Q:635`). -/
def bWaitIO (o r : Nat) : IO := .ioCont (QA.bWaitBody o r).fn

/-- `wait` of `BoundedAsyncQueue#offer`: `F.async[Unit] {...}` = `IOCont(body)` (`Q:803`). -/
def oWaitIO (o : Nat) (a : Val) (r : Nat) : IO := .ioCont (QA.oWaitBody o a r).fn

/-- `wait` of `UnboundedAsyncQueue#take`: `F.asyncCheckAttempt[Unit] {...}` = `IOCont(body)` (`Q:907`). -/
def uWaitIO (o r : Nat) : IO := .ioCont (QA.uWaitBody o r).fn

/-- The term of a descriptor. -/
def descIO (d : Val) : IO :=
  match ofCloVal d with
  | some (52, 120, []) => .pure .unit
  | some (52, 121, [v]) => .pure v
  | some (52, 122, [.fn o, .ref r, .poll m p]) =>
    .onCancel (.flatMap (IO.applyPoll (bWaitIO o r) m p) (QA.thenD (dRecv o r m p)).fn)
      (.delay (QA.bNotifyTakers o).fn)
  | some (52, 123, [.fn o, .ref r, .poll m p]) => .flatMap (.delay (QA.recvThunk r).fn) (QA.recvK o m p).fn
  | some (52, 124, [.fn o, .cont s, .nat c, .poll m p]) =>
    .onCancel (IO.applyPoll (.contGet s) m p) (.delay (QA.bClearTaker o c).fn)
  | some (52, 125, [.fn o, a, .ref r, .poll m p]) =>
    .onCancel (.flatMap (IO.applyPoll (oWaitIO o a r) m p) (QA.thenD (dORecv o a r m p)).fn)
      (.delay (QA.bNotifyOfferers o).fn)
  | some (52, 126, [.fn o, a, .ref r, .poll m p]) => .flatMap (.delay (QA.oRecvThunk r).fn) (QA.oRecvK o a m p).fn
  | some (52, 127, [.fn o, .ref r, .poll m p]) =>
    .onCancel (.flatMap (IO.applyPoll (uWaitIO o r) m p) (QA.thenD (dRecv o r m p)).fn)
      (.delay (QA.uNotify o).fn)
  | _ => .error { code := illCode, kind := .fatal }

/-! ## The closures -/

private def ret (v : Val) (es : List UserEffect := []) : UserResult := { effects := es, out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
def illTyped : UserResult := { out := .throw { code := illCode, kind := .fatal } }

/-- `buffer.put(a); notifyOne(takers); true` or `false` (`Q:856-865`, `Q:1002-1010`): the effects and
the result. -/
def tryOfferUnsafe (cap b : Nat) (a : Val) (v : View) : List UserEffect × Bool :=
  let buf := bufOf v b
  if buf.length < cap then
    (.writeRef b (listV (buf ++ [a])) :: notifyAt (b + 1) (waitersOf v (b + 1)), true)
  else ([], false)

/-- Run one closure. -/
def call (l : QA) (arg : Val) (v : View) : UserResult :=
  match l with
  | .flattenK => prog (descIO arg)
  | .thenD d => prog (descIO d)
  | .newB k cap =>
    -- `require(capacity > 1, ...)` (`Q:601`), then `buffer`, `takers`, `offerers` (`Q:603-606`)
    if cap ≤ 1 then { out := .throw requireErr }
    else
      let b := v.refs.length
      ret (.fn (bObjId k cap b)) [.allocRef (listV []), .allocRef (Takers.toVal {}), .allocRef (Takers.toVal {})]
  | .newU =>
    let b := v.refs.length
    ret (.fn (uObjId b)) [.allocRef (listV []), .allocRef (Takers.toVal {})]
  -- `BaseBoundedAsyncQueue#take` (`Q:615-687`)
  | .bTakeBody o =>
    match arg with
    | .poll m p => prog (.flatMap (.delay (QA.bTakeThunk o m p).fn) QA.flattenK.fn)
    | _ => illTyped
  | .bTakeThunk o m p =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) =>
      match bufOf v b with
      -- `buffer.take()`; `notifyOne(offerers)`; `F.pure(result)` (`Q:620-625`)
      | a :: rest => ret (dPure a) (.writeRef b (listV rest) :: notifyAt (b + 2) (waitersOf v (b + 2)))
      -- `FailureSignal`: `received`/`result` (`Q:630-631`); the result (`Q:683-684`)
      | [] => ret (dBTakeWait o v.refs.length m p) [.allocRef .none]
    | _ => illTyped
  | .bWaitBody o r =>
    match arg with
    | .cont s => prog (.uncancelable (QA.bWaitUnc o r s).fn)
    | _ => illTyped
  | .bWaitUnc o r s =>
    match arg with
    -- `lift(F delay {...}).flatten` (`Q:638-671`)
    | .poll m p => prog (.flatMap (.delay (QA.bWaitReg o r s m p).fn) QA.flattenK.fn)
    | _ => illTyped
  | .bWaitReg o r s m p =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) =>
      -- `val clear = takers.put(k)` (`Q:641`)
      let (c, t) := (waitersOf v (b + 1)).put s
      match bufOf v b with
      | a :: rest =>
        -- `result = buffer.take()`; `clear()`; `received = true`; `notifyOne(takers)`;
        -- `notifyOne(offerers)`; `G.unit` (`Q:645-661`)
        ret dUnit ([.writeRef b (listV rest), .writeRef r (.some a)] ++ notifyAt (b + 1) (t.clear c) ++
          notifyAt (b + 2) (waitersOf v (b + 2)))
      -- `poll(get).onCancel(lift(F.delay(clear())))` (`Q:663-666`)
      | [] => ret (dGetClear o s c m p) [.writeRef (b + 1) t.toVal]
    | _ => illTyped
  | .bClearTaker o c =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) => ret .unit [.writeRef (b + 1) ((waitersOf v (b + 1)).clear c).toVal]
    | _ => illTyped
  | .bNotifyTakers o =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) => ret .unit (notifyAt (b + 1) (waitersOf v (b + 1)))
    | _ => illTyped
  | .recvThunk r =>
    match v.refs.getD r .none with
    | .some a => ret (.some a)
    | _ => ret .none
  | .recvK o m p =>
    match arg with
    | .some a => prog (.pure a)
    | .none => prog (IO.applyPoll (takeIO o) m p)
    | _ => illTyped
  | .bTryTake o =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) =>
      match bufOf v b with
      -- `buffer.take()`; `notifyOne(offerers)`; `Some(back)` (`Q:691-693`)
      | a :: rest => ret (.some a) (.writeRef b (listV rest) :: notifyAt (b + 2) (waitersOf v (b + 2)))
      | [] => ret .none
    | _ => illTyped
  | .bSize o =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) => ret (.nat (bufOf v b).length)
    | _ => illTyped
  -- `BoundedAsyncQueue#offer` (`Q:786-854`)
  | .bOfferBody o a =>
    match arg with
    | .poll m p => prog (.flatMap (.delay (QA.bOfferThunk o a m p).fn) QA.flattenK.fn)
    | _ => illTyped
  | .bOfferThunk o a m p =>
    match Obj.ofId? o with
    | some (.bnd _ cap b) =>
      let buf := bufOf v b
      if buf.length < cap then
        -- `buffer.put(a)`; `notifyOne(takers)`; `F.unit` (`Q:791-796`)
        ret dUnit (.writeRef b (listV (buf ++ [a])) :: notifyAt (b + 1) (waitersOf v (b + 1)))
      else
        -- `var succeeded = false` (`Q:800`); the result (`Q:850-851`)
        ret (dOfferWait o a v.refs.length m p) [.allocRef (.bool false)]
    | _ => illTyped
  | .oWaitBody o a r =>
    match arg with
    | .cont s => prog (.uncancelable (QA.oWaitUnc o a r s).fn)
    | _ => illTyped
  | .oWaitUnc o a r s =>
    match arg with
    | .poll m p => prog (.flatMap (.delay (QA.oWaitReg o a r s).fn) (QA.oWaitSel o s m p).fn)
    | _ => illTyped
  | .oWaitReg o a r s =>
    match Obj.ofId? o with
    | some (.bnd _ cap b) =>
      -- `val clear = offerers.put(k)` (`Q:806`)
      let (c, f) := (waitersOf v (b + 2)).put s
      let buf := bufOf v b
      if buf.length < cap then
        -- `buffer.put(a)`; `clear()`; `succeeded = true`; `k(EitherUnit)`; `notifyOne(offerers)`
        -- (it writes the offerer cells); `notifyOne(takers)`; `None` (`Q:810-831`)
        ret .none ([.writeRef b (listV (buf ++ [a])), .writeRef r (.bool true), .writeRef (b + 2) (f.clear c).toVal,
          .invokeCb s (.right .unit)] ++ notifyAt (b + 2) (f.clear c) ++ notifyAt (b + 1) (waitersOf v (b + 1)))
      -- `Some(F.delay(clear()))` (`Q:833-836`)
      else ret (.some (.nat c)) [.writeRef (b + 2) f.toVal]
    | _ => illTyped
  | .oWaitSel o s m p =>
    match arg with
    | .some (.nat c) => prog (.onCancel (IO.applyPoll (.contGet s) m p) (.delay (QA.bClearOfferer o c).fn))
    | .none => prog (.contGet s)
    | _ => illTyped
  | .bClearOfferer o c =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) => ret .unit [.writeRef (b + 2) ((waitersOf v (b + 2)).clear c).toVal]
    | _ => illTyped
  | .bNotifyOfferers o =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) => ret .unit (notifyAt (b + 2) (waitersOf v (b + 2)))
    | _ => illTyped
  | .oRecvThunk r =>
    match v.refs.getD r (.bool false) with
    | .bool true => ret (.bool true)
    | _ => ret (.bool false)
  | .oRecvK o a m p =>
    match arg with
    | .bool true => prog (.pure .unit)
    | .bool false => prog (IO.applyPoll (bOfferIO o a) m p)
    | _ => illTyped
  | .bTryOffer o a =>
    match Obj.ofId? o with
    | some (.bnd _ cap b) => let (es, ok) := tryOfferUnsafe cap b a v; ret (.bool ok) es
    | _ => illTyped
  | .dOffer o a =>
    match Obj.ofId? o with
    | some (.bnd _ cap b) => ret .unit (tryOfferUnsafe cap b a v).1
    | _ => illTyped
  -- `UnboundedAsyncQueue` (`Q:871-988`)
  | .uOffer o a =>
    match Obj.ofId? o with
    -- `buffer.put(a)`; `notifyOne()` (`Q:879-882`)
    | some (.unb b) => ret .unit (.writeRef b (listV (bufOf v b ++ [a])) :: notifyAt (b + 1) (waitersOf v (b + 1)))
    | _ => illTyped
  | .uTryOffer o a =>
    match Obj.ofId? o with
    | some (.unb b) => ret (.bool true) (.writeRef b (listV (bufOf v b ++ [a])) :: notifyAt (b + 1) (waitersOf v (b + 1)))
    | _ => illTyped
  | .uSize o =>
    match Obj.ofId? o with
    | some (.unb b) => ret (.nat (bufOf v b).length)
    | _ => illTyped
  | .uTakeBody o =>
    match arg with
    | .poll m p => prog (.flatMap (.delay (QA.uTakeThunk o m p).fn) QA.flattenK.fn)
    | _ => illTyped
  | .uTakeThunk o m p =>
    match Obj.ofId? o with
    | some (.unb b) =>
      match bufOf v b with
      -- `F.pure(buffer.take())` (`Q:898`)
      | a :: rest => ret (dPure a) [.writeRef b (listV rest)]
      | [] => ret (dUTakeWait o v.refs.length m p) [.allocRef .none]
    | _ => illTyped
  | .uWaitBody o r =>
    match arg with
    | .cont s => prog (.uncancelable (QA.uWaitUnc o r s).fn)
    | _ => illTyped
  | .uWaitUnc o r s =>
    match arg with
    | .poll m p => prog (.flatMap (.delay (QA.uWaitReg o r s).fn) (QA.uWaitSel o s m p).fn)
    | _ => illTyped
  | .uWaitReg o r s =>
    match Obj.ofId? o with
    | some (.unb b) =>
      let (c, t) := (waitersOf v (b + 1)).put s
      match bufOf v b with
      -- `result = buffer.take()`; `clear()`; `received = true`; `notifyOne()`; `EitherUnit` (`Q:914-926`)
      | a :: rest => ret (.right .unit) ([.writeRef b (listV rest), .writeRef r (.some a)] ++ notifyAt (b + 1) (t.clear c))
      -- `Left(Some(F.delay(clear())))` (`Q:928-931`)
      | [] => ret (.left (.some (.nat c))) [.writeRef (b + 1) t.toVal]
    | _ => illTyped
  | .uWaitSel o s m p =>
    match arg with
    | .right a => prog (.pure a)
    | .left (.some (.nat c)) => prog (.onCancel (IO.applyPoll (.contGet s) m p) (.delay (QA.uClear o c).fn))
    | .left .none => prog (.contGet s)
    | _ => illTyped
  | .uClear o c =>
    match Obj.ofId? o with
    | some (.unb b) => ret .unit [.writeRef (b + 1) ((waitersOf v (b + 1)).clear c).toVal]
    | _ => illTyped
  | .uNotify o =>
    match Obj.ofId? o with
    | some (.unb b) => ret .unit (notifyAt (b + 1) (waitersOf v (b + 1)))
    | _ => illTyped
  | .uTryTake o =>
    match Obj.ofId? o with
    | some (.unb b) =>
      match bufOf v b with
      | a :: rest => ret (.some a) [.writeRef b (listV rest)]
      | [] => ret .none
    | _ => illTyped

/-- Run closure id `id`: a `QA` closure, or a queue object (`objCallErr`). -/
def call? (id : Nat) (arg : Val) (v : View) : Option UserResult :=
  match QA.ofId? id with
  | some l => some (call l arg v)
  | none =>
    match Obj.ofId? id with
    | some _ => some { out := .throw objCallErr }
    | none => none

end CatsEffectInLean.Std.QueueAsync

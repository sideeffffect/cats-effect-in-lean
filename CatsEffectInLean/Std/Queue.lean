import CatsEffectInLean.Model.Codec

/-!
# `Queue.unbounded` for `IO`: `UnboundedAsyncQueue` (mirror)

`Queue.unbounded[F, A]` with an `Async[F]` (so `IO`) is `unboundedForAsync`, which is
`F.delay(new UnboundedAsyncQueue())` (`Q:160-167`, `Q:105-106`). This file mirrors that class
(`Q:871-988`) and the lock-free list `UnsafeUnbounded` that holds its buffer and its takers
(`UU:23-113`). It does not mirror the `Concurrent` queues (`BoundedQueue` with `Ref` and
`Deferred`): `IO` never uses them for `unbounded`.

`Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala`,
`UU` = `std/shared/src/main/scala/cats/effect/std/UnsafeUnbounded.scala`,
`IO.scala` = `core/shared/src/main/scala/cats/effect/IO.scala`, all at `v3.7.1`.

## How the Scala code maps to the model

* `F` is `IO.asyncForIO` (`IOAsync`, `IO.scala:1996-2180`). Its operations used here:
  `delay` = `IO(thunk)` = `Delay` (`IO.scala:2104`, `IO.scala:1275`, `IO.scala:1284-1287`);
  `uncancelable` = `Uncancelable` (`IO.scala:2095-2096`, `IO.scala:1712-1713`);
  `defer` = `Sync.defer` = `flatMap(delay(thunk))(x => x)` (`kernel/.../Sync.scala:61-62`;
  `IOAsync` does not override it); `asyncCheckAttempt` = `IO.asyncCheckAttempt`
  (`IO.scala:1998-2000`, `IO.scala:1353-1368`); `*>` = `productR` = `flatMap(_ => that)`
  (`IO.scala:2081-2082`, `IO.scala:903-904`); `onCancel` = `OnCancel` (`IO.scala:2059-2060`,
  `IO.scala:590-591`); `poll(fa)` = `UnmaskRunLoop(fa, id, self)` (`IOFiber.scala:564-567`).
* Each Scala lambda is one `QLam` case; its captured values are its fields
  (`Codec.nsFn`, namespace `Queue.ns`).
* A `Val` cannot hold an `IO`. Where a Scala thunk returns an `IO` (the thunk of `F.defer`), the
  model thunk returns a `Val` code, and the `x => x` function of `defer` builds the same `IO`
  from it (as `RtFn.deferredDefer`/`deferredFlatten` in `Syntax.lean`). The run loop runs
  `FlatMap(Delay(thunk), f)` in one iteration (`IOFiber.scala:420-437`), so the steps are
  the same.
* The queue handle is `Val.ref b`. `Ref` cell `b` holds the buffer and cell `b + 1` holds the
  takers. A `var` of the Scala code (`received`, `result`) is one `Ref` cell that the thunk
  allocates (`UserEffect.allocRef`): `none` = `received == false`, `some x` =
  `received == true && result == x`. The two vars are always written together (`Q:914-919`).
* Atomicity: one user call is one atomic step (the model runs one thread, as `TestControl`).
  So the CAS loops of `UnsafeUnbounded` (`UU:41-46`, `UU:52-86`) are single steps: `put`
  appends a cell, `take` removes the first cell. The spin of `UU:65-68` cannot happen with one
  thread. A real JVM has more interleavings; the model has a subset of them.

## `UnsafeUnbounded` (`UU:23-113`)

A FIFO list of cells. `put(data)` appends a cell and returns it as `clear` (`UU:38-49`);
`clear()` sets the data of that cell to `null` (`UU:104-106`) but leaves the cell in the list.
`take()` removes the first cell and returns its data (maybe `null`), or throws
`FailureSignal` if the list is empty (`UU:52-86`). Buffer cells always hold data. Taker cells
hold the callback `k` of an `asyncCheckAttempt` (a `ContState` id) or `null` after `clear`.
-/

namespace CatsEffectInLean.Std.Queue

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the queue closures in `Codec.nsFn`. -/
def ns : Nat := 1

/-! ## State -/

/-- A list of values as one `Val`: `none` = `[]`, `some (pair h t)` = `h :: t`. -/
def listVal : List Val → Val
  | [] => .none
  | h :: t => .some (.pair h (listVal t))

/-- The inverse of `listVal` (`[]` for a value of another shape). -/
def valList : Val → List Val
  | .some (.pair h t) => h :: valList t
  | _ => []

/-- The takers list (`Q:876`): the next cell id, and the cells (id, data). Data `some s` is
the callback of `ContState` `s`; `none` is a cleared cell (`UU:104-106`). -/
structure Takers where
  /-- The id of the next cell that `put` makes. -/
  next : Nat := 0
  /-- The cells, first to last. -/
  cells : List (Nat × Option Nat) := []
  deriving DecidableEq, Repr

/-- `Takers` as a `Val`. -/
def Takers.toVal (t : Takers) : Val :=
  .pair (.nat t.next) (listVal (t.cells.map fun c =>
    .pair (.nat c.1) (match c.2 with | some s => .some (.cont s) | none => .none)))

/-- The inverse of `Takers.toVal` (empty for a value of another shape). -/
def Takers.ofVal : Val → Takers
  | .pair (.nat n) cs =>
    { next := n,
      cells := (valList cs).filterMap fun
        | .pair (.nat i) (.some (.cont s)) => some (i, some s)
        | .pair (.nat i) .none => some (i, none)
        | _ => none }
  | _ => {}

/-- The buffer of queue `q` in view `v`. -/
def buffer (v : View) (q : Nat) : List Val := valList (v.refs.getD q .none)

/-- The takers of queue `q` in view `v`. -/
def takers (v : View) (q : Nat) : Takers := Takers.ofVal (v.refs.getD (q + 1) .none)

/-- `notifyOne()` (`Q:958-987`) on the taker cells: `takers.take()` (`UU:52-86`); an empty list
throws `FailureSignal`, so stop (`Q:978-980`); a `null` cell (cleared) loops (`Q:967-969`,
`Q:983-986`); else call it with `EitherUnit` and stop (`Q:970-976`). Gives the cells that are
left and the `ContState` to call. -/
def notifyOne : List (Nat × Option Nat) → List (Nat × Option Nat) × Option Nat
  | [] => ([], none)
  | (_, none) :: rest => notifyOne rest
  | (_, some s) :: rest => (rest, some s)

/-- The effects of `notifyOne()` with takers `t` of queue `q`: write the takers that are left,
then call `f(EitherUnit)` (`Q:973`). `f` is the `resume` callback of an `IOCont`
(`IOFiber.scala:644-755`), so the call is `UserEffect.invokeCb` with `Right(())`. -/
def notifyEffects (q : Nat) (t : Takers) : List UserEffect :=
  let r := notifyOne t.cells
  .writeRef (q + 1) (Takers.toVal { t with cells := r.1 }) ::
    (match r.2 with
     | some s => [.invokeCb s (.right .unit)]
     | none => [])

/-- `clear()` of taker cell `c` (`UU:104-106`): its data becomes `null`. -/
def Takers.clear (t : Takers) (c : Nat) : Takers :=
  { t with cells := t.cells.map fun x => if x.1 == c then (x.1, none) else x }

/-- `takers.put(k)` (`UU:38-49`): append a cell with data `s`. Gives the cell id (`clear`). -/
def Takers.put (t : Takers) (s : Nat) : Nat × Takers :=
  (t.next, { next := t.next + 1, cells := t.cells ++ [(t.next, some s)] })

/-! ## Closures -/

/-- The lambdas of `UnboundedAsyncQueue` and of the `IO` code that it calls. Fields: `q` =
queue (buffer `Ref` id), `r` = the `Ref` cell of `received`/`result`, `s` = a `ContState` id,
`m`, `p` = a `poll` (mask id, fiber), `c` = a taker cell id, `x` = an element code
(`Codec.Val.enc`). -/
inductive QLam where
  /-- The thunk of `F.delay(new UnboundedAsyncQueue())` (`Q:105-106`). -/
  | newQueue
  /-- The thunk of `offer(a) = F.delay(unsafeOffer(a))` (`Q:884`, `Q:879-882`). -/
  | offer (q x : Nat)
  /-- The thunk of `tryTake` (`Q:949-956`). -/
  | tryTake (q : Nat)
  /-- `poll => F defer { ... }`, the body of `take` (`Q:894-947`). -/
  | takeBody (q : Nat)
  /-- The thunk of `F defer { ... }` in `take` (`Q:895-946`). -/
  | takeThunk (q : Nat)
  /-- `x => x` of `F.defer` in `take` (`Sync.scala:61-62`): build the `IO` from the code. -/
  | takeDefer (q m p : Nat)
  /-- The `Cont` body of `wait = F.asyncCheckAttempt { k => ... }` (`Q:907-934`;
  `IO.scala:1355-1364`): `(resume, get, lift) => G.uncancelable { poll => ... }`. -/
  | waitBody (q r : Nat)
  /-- `poll => lift(k(resume)) flatMap { ... }` of `asyncCheckAttempt` (`IO.scala:1357-1363`). -/
  | waitUnc (q r s : Nat)
  /-- The thunk of `k(resume) = F delay { ... }` (`Q:908-933`). -/
  | waitReg (q r s : Nat)
  /-- The `flatMap` function of `asyncCheckAttempt` (`IO.scala:1358-1362`). -/
  | waitSel (q s m p : Nat)
  /-- The thunk of `F.delay(clear())` (`Q:931`). -/
  | clear (q c : Nat)
  /-- The thunk of `notifyAnyway = F delay { notifyOne() }` (`Q:936-940`). -/
  | notifyAnyway (q : Nat)
  /-- `_ => that` of `poll(wait) *> that` (`Q:943`; `IO.scala:903-904`). -/
  | thenRecv (q m p r : Nat)
  /-- The thunk of `F.defer(if (received) F.pure(result) else poll(take))` (`Q:943`). -/
  | recvThunk (r : Nat)
  /-- `x => x` of that `F.defer` (`Sync.scala:61-62`). -/
  | recvDefer (q m p : Nat)
  deriving DecidableEq, Repr

/-- The fields of a closure (tag first). -/
def QLam.toList : QLam → List Nat
  | .newQueue => [0]
  | .offer q x => [1, q, x]
  | .tryTake q => [2, q]
  | .takeBody q => [3, q]
  | .takeThunk q => [4, q]
  | .takeDefer q m p => [5, q, m, p]
  | .waitBody q r => [6, q, r]
  | .waitUnc q r s => [7, q, r, s]
  | .waitReg q r s => [8, q, r, s]
  | .waitSel q s m p => [9, q, s, m, p]
  | .clear q c => [10, q, c]
  | .notifyAnyway q => [11, q]
  | .thenRecv q m p r => [12, q, m, p, r]
  | .recvThunk r => [13, r]
  | .recvDefer q m p => [14, q, m, p]

/-- The inverse of `QLam.toList`. -/
def QLam.ofList : List Nat → Option QLam
  | [0] => some .newQueue
  | [1, q, x] => some (.offer q x)
  | [2, q] => some (.tryTake q)
  | [3, q] => some (.takeBody q)
  | [4, q] => some (.takeThunk q)
  | [5, q, m, p] => some (.takeDefer q m p)
  | [6, q, r] => some (.waitBody q r)
  | [7, q, r, s] => some (.waitUnc q r s)
  | [8, q, r, s] => some (.waitReg q r s)
  | [9, q, s, m, p] => some (.waitSel q s m p)
  | [10, q, c] => some (.clear q c)
  | [11, q] => some (.notifyAnyway q)
  | [12, q, m, p, r] => some (.thenRecv q m p r)
  | [13, r] => some (.recvThunk r)
  | [14, q, m, p] => some (.recvDefer q m p)
  | _ => none

/-- The closure as a `Fn`. -/
def QLam.fn (l : QLam) : Fn := nsFn ns l.toList

/-! ## The public operations as `IO` terms -/

/-- `Queue.unbounded[IO, A]` = `F.delay(new UnboundedAsyncQueue())` (`Q:160-167`,
`Q:105-106`). It gives `Val.ref b`. -/
def newIO : IO := .delay QLam.newQueue.fn

/-- `q.offer(a)` (`Q:884`). Elements are values `x` (encoded in the closure). -/
def offerIO (q : Nat) (x : Val) : IO := .delay (QLam.offer q (Codec.Val.enc x)).fn

/-- `q.tryTake` (`Q:949-956`). -/
def tryTakeIO (q : Nat) : IO := .delay (QLam.tryTake q).fn

/-- `q.take` (`Q:894-947`): `F uncancelable { poll => ... }`. A `val`: `poll(take)` (`Q:943`)
runs this same term again. -/
def takeIO (q : Nat) : IO := .uncancelable (QLam.takeBody q).fn

/-- `wait` (`Q:907-934`): `IO.asyncCheckAttempt(k)` = `IOCont(body)` (`IO.scala:1353-1368`). -/
def waitIO (q r : Nat) : IO := .ioCont (QLam.waitBody q r).fn

/-- `F.defer(if (received) F.pure(result) else poll(take))` (`Q:943`):
`flatMap(delay(thunk))(x => x)`. -/
def recvIO (q m p r : Nat) : IO := .flatMap (.delay (QLam.recvThunk r).fn) (QLam.recvDefer q m p).fn

/-- A user result with no effects. -/
def ret (v : Val) (effects : List UserEffect := []) : UserResult := { effects, out := .ret v }

/-- A user result that is a program. -/
def prog (p : IO) (effects : List UserEffect := []) : UserResult := { effects, out := .prog p }

/-- A closure got an argument of the wrong shape (a model bug; never in a well-typed program). -/
def illTyped : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- Run one queue closure on `arg` with view `v`. -/
def call (l : QLam) (arg : Val) (v : View) : UserResult :=
  match l with
  | .newQueue =>
    -- `new UnboundedAsyncQueue()`: `buffer` and `takers` are new empty lists (`Q:875-876`)
    ret (.ref v.refs.length) [.allocRef (listVal []), .allocRef (Takers.toVal {})]
  | .offer q x =>
    match decVal x with
    | none => illTyped
    | some a =>
      -- `buffer.put(a)` (`Q:880`), then `notifyOne()` (`Q:881`)
      .writeRef q (listVal (buffer v q ++ [a])) :: notifyEffects q (takers v q) |> ret .unit
  | .tryTake q =>
    -- `Some(buffer.take())`, or `None` on `FailureSignal` (`Q:950-955`)
    match buffer v q with
    | [] => ret .none
    | a :: rest => ret (.some a) [.writeRef q (listVal rest)]
  | .takeBody q =>
    match arg with
    -- `F defer { ... }` (`Q:895`) = `flatMap(delay(thunk))(x => x)`
    | .poll m p => prog (.flatMap (.delay (QLam.takeThunk q).fn) (QLam.takeDefer q m p).fn)
    | _ => illTyped
  | .takeThunk q =>
    match buffer v q with
    -- `F.pure(buffer.take())` (`Q:898`): code `right a`
    | a :: rest => ret (.right a) [.writeRef q (listVal rest)]
    -- `FailureSignal` (`Q:900`): `var received = false; var result = null` (`Q:903-904`):
    -- a new cell `r`; code `left r`
    | [] => ret (.left (.nat v.refs.length)) [.allocRef .none]
  | .takeDefer q m p =>
    match arg with
    | .right a => prog (.pure a)
    -- `(poll(wait) *> F.defer(...)).onCancel(notifyAnyway)` (`Q:943-944`)
    | .left (.nat r) =>
      prog (.onCancel (.flatMap (.unmaskRunLoop (waitIO q r) m p) (QLam.thenRecv q m p r).fn)
        (.delay (QLam.notifyAnyway q).fn))
    | _ => illTyped
  | .waitBody q r =>
    match arg with
    -- `G.uncancelable { poll => ... }` (`IO.scala:1357`)
    | .cont s => prog (.uncancelable (QLam.waitUnc q r s).fn)
    | _ => illTyped
  | .waitUnc q r s =>
    match arg with
    -- `lift(k(resume)) flatMap { ... }` (`IO.scala:1358`); `k(resume) = F delay { ... }`
    -- (`Q:908`); `lift` is the identity for `IO`
    | .poll m p => prog (.flatMap (.delay (QLam.waitReg q r s).fn) (QLam.waitSel q s m p).fn)
    | _ => illTyped
  | .waitReg q r s =>
    -- `val clear = takers.put(k)` (`Q:910`)
    let (c, t) := (takers v q).put s
    match buffer v q with
    | a :: rest =>
      -- `result = buffer.take()` (`Q:914`); `clear()` (`Q:917`); `received = true` (`Q:919`);
      -- `notifyOne()` (`Q:923`); `EitherUnit` (`Q:926`)
      ret (.right .unit)
        ([.writeRef q (listVal rest), .writeRef r (.some a)] ++ notifyEffects q (t.clear c))
    -- `FailureSignal` (`Q:928-931`): `Left(Some(F.delay(clear())))`; code `left (some c)`
    | [] => ret (.left (.some (.nat c))) [.writeRef (q + 1) t.toVal]
  | .waitSel q s m p =>
    match arg with
    -- `case Right(a) => G.pure(a)` (`IO.scala:1359`)
    | .right a => prog (.pure a)
    -- `case Left(Some(fin)) => G.onCancel(poll(get), lift(fin))` (`IO.scala:1360`)
    | .left (.some (.nat c)) =>
      prog (.onCancel (.unmaskRunLoop (.contGet s) m p) (.delay (QLam.clear q c).fn))
    -- `case Left(None) => get` (`IO.scala:1361`)
    | .left .none => prog (.contGet s)
    | _ => illTyped
  | .clear q c =>
    -- `clear()` (`UU:104-106`)
    ret .unit [.writeRef (q + 1) ((takers v q).clear c).toVal]
  | .notifyAnyway q =>
    -- `notifyOne()` (`Q:939`)
    ret .unit (notifyEffects q (takers v q))
  | .thenRecv q m p r =>
    -- `_ => that`: `that` = `F.defer(...)` (`Q:943`)
    prog (recvIO q m p r)
  | .recvThunk r =>
    -- `if (received) F.pure(result) else poll(take)`: code `some result` or `none`
    match v.refs.getD r .none with
    | .some a => ret (.some a)
    | _ => ret .none
  | .recvDefer q m p =>
    match arg with
    | .some a => prog (.pure a)
    -- `poll(take)` (`Q:943`)
    | .none => prog (.unmaskRunLoop (takeIO q) m p)
    | _ => illTyped

end CatsEffectInLean.Std.Queue

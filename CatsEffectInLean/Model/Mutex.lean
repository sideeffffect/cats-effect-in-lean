import CatsEffectInLean.Model.Semaphore

/-!
# `std.Mutex` and `LockQueue` (mirror; Phase 7, track S)

`Mutex[IO]` (`std/shared/src/main/scala/cats/effect/std/Mutex.scala`, `M` below) at `v3.7.1`.
There is one implementation, `ConcurrentImpl` (`M:87-97`); `Mutex.in` (`M:79-85`) builds the same
class with `Ref.in`. The `AsyncImpl` of earlier versions is gone: commit `8deb2fdabe` ("Re-implement
Mutex using the shared LockQueue") replaced both by `LockQueue.lock`
(`std/shared/src/main/scala/cats/effect/std/LockQueue.scala`, `LQ` below), a variant of the
Craig, Landin and Hagersten (CLH) queue lock with `Deferred` cells. `TransformedMutex`
(`M:99-111`) only maps with a natural transformation; it is not mirrored. So the twin of
`Mutex` at v3.7.1 is `Semaphore(1).permit` (the docs, `docs/std/mutex.md:7-8`: "Basically, it's a
`Semaphore` with a single available permit").

```scala
def apply[F[_]](implicit F: Concurrent[F]): F[Mutex[F]] =                          // M:68-74
  Ref.of[F, LockQueue.Cell](LockQueue.EmptyCell).map(state => new ConcurrentImpl(state))
override final val lock: Resource[F, Unit] = LockQueue.lock(queue = state)         // M:92-93

def lock[F[_]](queue: Ref[F, Cell])(implicit F: Concurrent[F]): Resource[F, Unit] = {   // LQ:42-109
  def awakeCell(ourCell: WaitingCell[F], nextCell: Cell): F[Unit] =                 // LQ:49-64
    queue.access.flatMap {
      case (lastCell, setter) =>
        if (lastCell eq ourCell) setter(nextCell)
        else F.pure(false)
    } flatMap {
      case false => ourCell.complete(nextCell).void
      case true => F.unit
    }
  def cancel(ourCell: WaitingCell[F], nextCell: Cell): F[Unit] = awakeCell(ourCell, nextCell)  // LQ:67-71
  def acquire(poll: Poll[F]): F[WaitingCell[F]] =                                    // LQ:74-101
    WaitingCell[F].flatMap { ourCell =>
      queue.getAndSet(ourCell).flatMap { lastCell =>
        def loop(nextCell: Cell): F[WaitingCell[F]] =
          if (nextCell eq EmptyCell) F.pure(ourCell)
          else {
            F.onCancel(
              poll(nextCell.asInstanceOf[WaitingCell[F]].get),
              cancel(ourCell, nextCell)
            ).flatMap(loop)
          }
        loop(nextCell = lastCell)
      }
    }
  def release(ourCell: WaitingCell[F]): F[Unit] = awakeCell(ourCell, nextCell = EmptyCell)  // LQ:104-105
  Resource.makeFull[F, WaitingCell[F]](acquire)(release).void                       // LQ:108
}
```

## The operations of `F = IO`

* `Ref.of(a)` with only `Concurrent[F]` in scope: `Make.concurrentInstance` = `F.ref(a)`
  (`kernel/shared/src/main/scala/cats/effect/kernel/Ref.scala:250`, `:208-211`) = `IO.ref(a)` =
  `IO(Ref.unsafe(a))` (`IO.scala:2161`, `:1822`).
* `SyncRef` (`kernel/jvm-native/src/main/scala/cats/effect/kernel/SyncRef.scala`): `getAndSet(a)` =
  `F.delay(ar.getAndSet(a))` (`:34`); `access` = `F.delay { val snapshot = ar.get; def setter =
  (a: A) => F.delay(ar.compareAndSet(snapshot, a)); (snapshot, setter) }` (`:47-52`). At v3.7.1 the
  setter has no "called once" flag. `compareAndSet` compares by reference: cells are `Deferred`
  objects or `null`, so reference equality is `Val` equality here.
* `WaitingCell[F]` = `Deferred[F, Cell]` = `F.deferred` = `IO.deferred` (`LQ:36-37`,
  `kernel/shared/src/main/scala/cats/effect/kernel/Deferred.scala:64-65`, `IO.scala:2163`, `:1824`).
* `nextCell.get` is `cell.get()` (`IODeferred.scala:71`), read when `loop` builds the term
  (`IO.deferredGetOf` with the view of the `loop` call).
* `F.onCancel(fa, fin)` = `OnCancel` (`IO.scala:2059-2060`, `:590-591`); `fin` is built first.
* `ourCell.complete(nextCell).void`: `complete` (`IODeferred.scala:62-69`), `void` = `F.void` =
  `IO#void` = `map(_ => ())` (`IO.scala:2152`, `:961-962`).
* Precedence: `queue.access.flatMap {...} flatMap {...}` is `(queue.access.flatMap {...}).flatMap {...}`.
* `lock.use(f)`: `lock` = `Bind(Allocate(resource), a => Pure(()))` (`.void` = `map(_ => ())`,
  `Resource.scala:396-397`, `:388-389`); `use(f)` = `fold(f, _.apply(_))`: `F.bracketFull(resource)
  { case (a, _) => continue(Pure(()), Nil) = f(()) } {...}` (`Resource.scala:156-196`), with the
  fold closures of `Model/Semaphore.lean` (`useOut f true`, `useRel`).

## Encoding

* Closures `ML` (namespace `ns = 61`). The mutex object (`new ConcurrentImpl(state)`, `M:74`) is
  `mutexV q`: a reference to the library closure `ML.obj q`, where cell `q` holds the last cell
  of the queue. `EmptyCell` (`null`, `LQ:30`) is `Val.none`; a waiting cell is `Val.deferred c`.
* The `setter` of `access` is a value: a reference to `ML.setter m snapshot`; `awA` applies it.
-/

namespace CatsEffectInLean.Model.Mutex

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of these closures (track S: 60..69). -/
def ns : Nat := 61

/-- `EmptyCell` (`null`, `LQ:30`). -/
def emptyCell : Val := .none

/-- The closures. Fields: `m` the mutex object (a closure id, held as `Val.fn m`), `c` our cell
(a `Deferred`), `next` a cell value, `mm pp` a poll, `snap` a snapshot of the queue cell, `f` a user
function. -/
inductive ML where
  /-- The mutex object `new ConcurrentImpl(state)` over queue cell `q`. A value. -/
  | obj (q : Nat)
  /-- `IO(Ref.unsafe(x))` thunk (`IO.scala:1822`). -/
  | newRef (x : Val)
  /-- `state => new ConcurrentImpl(state)` (`M:74`). -/
  | mkMutex
  /-- The `Allocate` function: `poll => acquire(poll).map(a => (a, _ => release(a)))`
  (`LQ:108`, `Resource.scala:942-944`). -/
  | acq (m : Nat)
  /-- `IO(new IODeferred)` thunk (`IO.scala:1824`). -/
  | newDeferred
  /-- `ourCell => queue.getAndSet(ourCell).flatMap {...}` (`LQ:75-100`). -/
  | acqCell (m mm pp : Nat)
  /-- The `getAndSet(ourCell)` thunk (`SyncRef.scala:34`). -/
  | getAndSet (m c : Nat)
  /-- `lastCell => loop(lastCell)` and the `flatMap(loop)` of `loop` (`LQ:78-99`). -/
  | loopK (m c mm pp : Nat)
  /-- The `access` thunk (`SyncRef.scala:47-52`). -/
  | access (m : Nat)
  /-- `setter = (a: A) => F.delay(ar.compareAndSet(snapshot, a))` (`SyncRef.scala:50`). A value. -/
  | setter (m : Nat) (snap : Val)
  /-- The `compareAndSet` thunk of `setter(a)`. -/
  | cas (m : Nat) (snap a : Val)
  /-- `{ case (lastCell, setter) => if (lastCell eq ourCell) setter(nextCell) else F.pure(false) }`
  (`LQ:58-60`). -/
  | awA (c : Nat) (next : Val)
  /-- `{ case false => ourCell.complete(nextCell).void; case true => F.unit }` (`LQ:61-64`). -/
  | awB (c : Nat) (next : Val)
  /-- `_ => ()` of `void` (`IO.scala:961-962`). -/
  | voidK
  /-- `a => (a, _ => release(a))` of `makeFull` (`Resource.scala:944`). -/
  | pairRel (m : Nat)
  /-- `_ => release(a)` of `makeFull` (`Resource.scala:944`): `release(ourCell)` (`LQ:104-105`). -/
  | relEc (m c : Nat)
  /-- Public operations for user code (decision 58): `_ => Mutex[IO]` and `_ => m.lock.use(f)`. -/
  | opNew
  | opLockUse (m f : Nat)
  deriving DecidableEq, Repr

def ML.toVal : ML → Val
  | .obj q => cloVal ns 0 [.ref q]
  | .newRef x => cloVal ns 1 [x]
  | .mkMutex => cloVal ns 2 []
  | .acq m => cloVal ns 3 [.fn m]
  | .newDeferred => cloVal ns 4 []
  | .acqCell m mm pp => cloVal ns 5 [.fn m, .poll mm pp]
  | .getAndSet m c => cloVal ns 6 [.fn m, .deferred c]
  | .loopK m c mm pp => cloVal ns 7 [.fn m, .deferred c, .poll mm pp]
  | .access m => cloVal ns 8 [.fn m]
  | .setter m snap => cloVal ns 9 [.fn m, snap]
  | .cas m snap a => cloVal ns 10 [.fn m, snap, a]
  | .awA c next => cloVal ns 11 [.deferred c, next]
  | .awB c next => cloVal ns 12 [.deferred c, next]
  | .voidK => cloVal ns 13 []
  | .pairRel m => cloVal ns 14 [.fn m]
  | .relEc m c => cloVal ns 15 [.fn m, .deferred c]
  | .opNew => cloVal ns 40 []
  | .opLockUse m f => cloVal ns 41 [.fn m, .fn f]

def ML.ofFields : Nat → List Val → Option ML
  | 0, [.ref q] => some (.obj q)
  | 1, [x] => some (.newRef x)
  | 2, [] => some .mkMutex
  | 3, [.fn m] => some (.acq m)
  | 4, [] => some .newDeferred
  | 5, [.fn m, .poll mm pp] => some (.acqCell m mm pp)
  | 6, [.fn m, .deferred c] => some (.getAndSet m c)
  | 7, [.fn m, .deferred c, .poll mm pp] => some (.loopK m c mm pp)
  | 8, [.fn m] => some (.access m)
  | 9, [.fn m, snap] => some (.setter m snap)
  | 10, [.fn m, snap, a] => some (.cas m snap a)
  | 11, [.deferred c, next] => some (.awA c next)
  | 12, [.deferred c, next] => some (.awB c next)
  | 13, [] => some .voidK
  | 14, [.fn m] => some (.pairRel m)
  | 15, [.fn m, .deferred c] => some (.relEc m c)
  | 40, [] => some .opNew
  | 41, [.fn m, .fn f] => some (.opLockUse m f)
  | _, _ => none

def ML.id (l : ML) : Nat := 2 * valToNat l.toVal + 1
def ML.fn (l : ML) : Fn := .user l.id

def ML.ofId? (id : Nat) : Option ML :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then ML.ofFields tag fs else none
    | none => none
  else none

/-- The mutex value over queue cell `q`. -/
def mutexV (q : Nat) : Val := .fn (ML.obj q).id

/-- The id of the mutex object over cell `q`. -/
def mutexId (q : Nat) : Nat := (ML.obj q).id

/-- The queue cell of a mutex object id. -/
def mutexRef? (m : Nat) : Option Nat :=
  match ML.ofId? m with
  | some (.obj q) => some q
  | _ => none

/-! ## Terms -/

/-- `Mutex[IO]` (`M:68-74`). -/
def newIO : IO := .map (.delay (ML.newRef emptyCell).fn) ML.mkMutex.fn

/-- `awakeCell(ourCell, nextCell)` (`LQ:49-64`). -/
def awakeCellIO (m c : Nat) (next : Val) : IO :=
  .flatMap (.flatMap (.delay (ML.access m).fn) (ML.awA c next).fn) (ML.awB c next).fn

/-- `loop(nextCell)` (`LQ:88-97`), built in view `v` (`nextCell.get` reads the cell now). -/
def loopIO (m c mm pp : Nat) (v : View) : Val → IO
  | .deferred d =>
    .flatMap (.onCancel (IO.applyPoll (IO.deferredGetOf d (v.deferred d)) mm pp) (awakeCellIO m c (.deferred d)))
      (ML.loopK m c mm pp).fn
  | .none => .pure (.deferred c)
  | _ => .error { code := Semaphore.illCode, kind := .fatal }

/-- `m.lock.use(f)` (`M:92-93`, `LQ:108`, `Resource.scala:156-208`): `IO.bracketFull` (track G
mirror) with the fold closures of `Model/Semaphore.lean`. -/
def lockUseIO (m f : Nat) : IO :=
  Bracket.bracketFullIO (ML.acq m).id (Semaphore.SL.useOut f true).id Semaphore.SL.useRel.id

/-! ## The closures -/

private def ret (v : Val) : UserResult := { out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
def illTyped : UserResult := Semaphore.illTyped

def call (l : ML) (arg : Val) (v : View) : UserResult :=
  match l with
  | .obj _ => illTyped
  | .newRef x => { effects := [.allocRef x], out := .ret (.ref v.refs.length) }
  | .mkMutex =>
    match arg with
    | .ref q => ret (mutexV q)
    | _ => illTyped
  | .acq m =>
    match arg with
    -- `acquire(poll)` = `WaitingCell[F].flatMap {...}`; then `.map(a => (a, _ => release(a)))`
    | .poll mm pp => prog (.map (.flatMap (.delay ML.newDeferred.fn) (ML.acqCell m mm pp).fn) (ML.pairRel m).fn)
    | _ => illTyped
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred v.deferreds.length) }
  | .acqCell m mm pp =>
    match arg with
    | .deferred c => prog (.flatMap (.delay (ML.getAndSet m c).fn) (ML.loopK m c mm pp).fn)
    | _ => illTyped
  | .getAndSet m c =>
    match mutexRef? m with
    | some q =>
      match v.refs[q]? with
      | some old => { effects := [.writeRef q (.deferred c)], out := .ret old }
      | none => illTyped
    | none => illTyped
  | .loopK m c mm pp => prog (loopIO m c mm pp v arg)
  | .access m =>
    match mutexRef? m with
    | some q =>
      match v.refs[q]? with
      | some snap => ret (.pair snap (.fn (ML.setter m snap).id))
      | none => illTyped
    | none => illTyped
  | .setter _ _ => illTyped
  | .cas m snap a =>
    match mutexRef? m with
    | some q =>
      match v.refs[q]? with
      | some cur =>
        if cur == snap then { effects := [.writeRef q a], out := .ret (.bool true) }
        else ret (.bool false)
      | none => illTyped
    | none => illTyped
  | .awA c next =>
    match arg with
    | .pair last (.fn sId) =>
      if last == .deferred c then
        -- `setter(nextCell)`: apply the setter value (a Scala function call that builds the `IO`)
        match ML.ofId? sId with
        | some (.setter m snap) => prog (.delay (ML.cas m snap next).fn)
        | _ => illTyped
      else prog (.pure (.bool false))
    | _ => illTyped
  | .awB c next =>
    match arg with
    | .bool false => prog (.map (Semaphore.completeIO c next) ML.voidK.fn)
    | .bool true => prog (.pure .unit)
    | _ => illTyped
  | .voidK => ret .unit
  | .pairRel m =>
    match arg with
    | .deferred c => ret (.pair arg (.fn (ML.relEc m c).id))
    | _ => illTyped
  | .relEc m c => prog (awakeCellIO m c emptyCell)
  | .opNew => prog newIO
  | .opLockUse m f => prog (lockUseIO m f)

/-! ## Dispatch -/

/-- The environment of a program that uses `Semaphore` and `Mutex`: these closures, the `Bracket`
mirror (`IO.bracketFull` of `Resource#use`), and user code `u` (even ids). -/
def dispatch (u : UserEnv) : Nat → Val → View → UserResult :=
  fun id arg v =>
    -- one level of the dispatcher for the closures that call back (`useOut`, `useRel`, `Bracket`)
    go u 8 id arg v
where
  go (u : UserEnv) : Nat → Nat → Val → View → UserResult
  | 0, id, arg, v => u.callV id arg v
  | fuel + 1, id, arg, v =>
    match Semaphore.SL.ofId? id with
    | some l => Semaphore.call (go u fuel) l arg v
    | none =>
      match ML.ofId? id with
      | some l => call l arg v
      | none =>
        match Bracket.BLam.ofId? id with
        | some l => Bracket.call (go u fuel) (fun _ => .error { code := Semaphore.illCode, kind := .fatal }) l arg v
        | none => u.callV id arg v

def env (u : UserEnv) : UserEnv where
  call id arg refs := dispatch u id arg { refs }
  callV := dispatch u

end CatsEffectInLean.Model.Mutex

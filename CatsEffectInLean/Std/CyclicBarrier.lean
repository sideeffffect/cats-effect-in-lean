import CatsEffectInLean.Model.Codec

/-!
# `std.CyclicBarrier` (mirror; Phase 7, track L)

`CB` = `std/shared/src/main/scala/cats/effect/std/CyclicBarrier.scala` at `v3.7.1`.
`K/` = `kernel/shared/src/main/scala/cats/effect/kernel/`, `IO.scala` =
`core/shared/src/main/scala/cats/effect/IO.scala`, both at `v3.7.1`.

```scala
def apply[F[_]](capacity: Int)(implicit F: GenConcurrent[F, ?]): F[CyclicBarrier[F]] = {   // CB:58
  if (capacity < 1)
    throw new IllegalArgumentException(...)                                                // CB:59-61
  case class State(awaiting: Int, epoch: Long, unblock: Deferred[F, Unit])                // CB:63
  F.deferred[Unit].map(State(capacity, 0, _)).flatMap(F.ref).map { state =>               // CB:65
    new CyclicBarrier[F] {
      val await: F[Unit] =                                                                 // CB:67
        F.deferred[Unit].flatMap { gate =>                                                 // CB:68
          state.flatModifyFull {                                                           // CB:69
            case (poll, State(awaiting, epoch, unblock)) =>
              val awaitingNow = awaiting - 1                                               // CB:71
              if (awaitingNow == 0)                                                        // CB:73
                State(capacity, epoch + 1, gate) -> unblock.complete(()).void              // CB:74
              else {
                val newState = State(awaitingNow, epoch, unblock)                          // CB:76
                val cleanup = state.update { s =>                                          // CB:79
                  if (s.epoch == epoch) s.copy(awaiting = s.awaiting + 1)
                  else s
                }
                newState -> poll(unblock.get).onCancel(cleanup)                            // CB:84
              }
          }
        }
    }
  }
}
```

## Operations with `F = IO` (`IOAsync`)

As in `Std/CountDownLatch.lean`: `F.deferred` = `Delay` (`IO.scala:2163`, `:1824`); `F.ref(a)` =
`IO(Ref.unsafe(a))` = `Delay` (`IO.scala:2161`, `:1822`; `SyncRef`, `K/Ref.scala:314`);
`.flatMap(F.ref)` passes the eta-expansion `a => F.ref(a)`; `map`/`flatMap` = `Map`/`FlatMap`
(`IO.scala:2098-2102`). `flatModifyFull(f)` = `F.uncancelable(poll => F.flatten(modify(f(poll, _))))`
(`K/Ref.scala:140-141`, not overridden by `SyncRef`); `modify` = `F.delay(spin)`
(`kernel/jvm-native/src/main/scala/cats/effect/kernel/SyncRef.scala:86-95`), `update` =
`F.delay(spin)` (`SyncRef.scala:65-73`): one model step each, the CAS succeeds the first time.
`unblock.complete(()).void` = `Map(Delay(complete), _ => ())` (`IODeferred.scala:62-69`,
`IO.scala:2152`, `:961-962`). `poll(fa)` = `UnmaskRunLoop` (`IO.applyPoll`); `.onCancel(fin)` =
`IOAsync.onCancel` = `OnCancel(fa, fin)` (`IO.scala:2059-2060`, `:590-591`).

`unblock.get` (`IODeferred.scala:71`, `cell.get()`) and `poll(…).onCancel(cleanup)` are built
inside the `modify` function, so `get` reads the cell at the time of the `modify` step: the
effect code keeps that snapshot.

The `val await` is built once, when the barrier object is made. Building an `IO` term reads no
state and has no effect, so the model builds it at each call (`awaitIO`): the same term.

## Encoding

* `State(awaiting, epoch, unblock)` = `pair (int awaiting) (pair (nat epoch) (deferred d))`.
  `awaiting` is an `Int` as in Scala (so `awaiting - 1` is exact). `epoch` is a `Long` that
  starts at 0 and only grows by 1; the model uses `Nat` (an overflow needs 2^63 trips).
* The barrier object is a closure reference `Val.fn (BLam.obj r cap v).id` (odd id; decision
  58). Argument `nat 0` is `await`.
* The `F[Unit]` that `modify` returns is an effect code (`Eff`, namespace `effNs`); `flattenK`
  builds the `IO`. Every handle in a code is a `Val` handle.
* `apply` with `capacity < 1` throws while Scala builds the term: `apply? cap` is `none`.

## Variants (not Cats Effect code, `v ≠ 0`)

`v = 0` is Cats Effect v3.7.1. Wrong functions for the wrong-function tests: `1` trips one
`await` early (`awaitingNow ≤ 1`), `2` does not re-increment on cancel (the cleanup keeps the
state), `3` re-increments without the epoch check, `4` never completes `unblock` ("never wake").

Decision 63 battery for `await` (the only public operation): `5` always raises, `6` never returns,
`7` drops its effect (returns `()` at once, no count), `8` doubles its effect (decrements the count
by 2).
-/

namespace CatsEffectInLean.Std.CyclicBarrier

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the closures (track L, Phase 7: namespaces 70..79). -/
def ns : Nat := 72
/-- The namespace of the effect codes. -/
def effNs : Nat := 73

/-- `IllegalArgumentException` (`CB:59-61`). -/
def iaeErr : Err := { code := 7000003 }

/-- An argument of the wrong shape: impossible in a well-typed Scala program. -/
def illErr : Err := { code := 999999, kind := .fatal }

/-- The error of the battery variant that raises (not Cats Effect code). -/
def battErr : Err := { code := 7000011 }

/-! ## State -/

/-- `State(awaiting, epoch, unblock)` (`CB:63`). -/
def stateVal (a : Int) (e d : Nat) : Val := .pair (.int a) (.pair (.nat e) (.deferred d))

/-- The state as Scala sees it. -/
inductive St where
  | mk (a : Int) (e d : Nat)
  | bad
  deriving DecidableEq, Repr

def St.ofVal : Val → St
  | .pair (.int a) (.pair (.nat e) (.deferred d)) => .mk a e d
  | _ => .bad

/-- A `Deferred` snapshot as a value: `some x` (completed with `x`) or `none` (`initial`). -/
def snapD : Option Val → Val
  | some x => .some x
  | none => .none

def snapDOpt : Val → Option Val
  | .some x => some x
  | _ => none

/-! ## Effect codes -/

/-- An `F[Unit]` that `modify` returns. -/
inductive Eff where
  /-- `unblock.complete(()).void` (`CB:74`). -/
  | trip (d : Nat)
  /-- `poll(unblock.get).onCancel(cleanup)` (`CB:84`); `snap` = the cell of `unblock` at the
  `modify` step; `cleanup` (`CB:79-82`) captures `state` and `epoch`. -/
  | wait (r e d : Nat) (snap : Val) (m p : Nat) (v : Nat)
  /-- `F.unit`: only variant 4 (not Cats Effect code). -/
  | unit
  deriving DecidableEq, Repr

def Eff.toVal : Eff → Val
  | .trip d => cloVal effNs 0 [.deferred d]
  | .wait r e d snap m p v => cloVal effNs 1 [.ref r, .nat e, .deferred d, snap, .poll m p, .nat v]
  | .unit => cloVal effNs 2 []

def Eff.ofFields : Nat → List Val → Option Eff
  | 0, [.deferred d] => some (.trip d)
  | 1, [.ref r, .nat e, .deferred d, snap, .poll m p, .nat v] => some (.wait r e d snap m p v)
  | 2, [] => some .unit
  | _, _ => none

def Eff.ofVal? (c : Val) : Option Eff :=
  match ofCloVal c with
  | some (k, tag, fs) => if k == effNs then Eff.ofFields tag fs else none
  | none => none

/-! ## Closures -/

/-- The lambdas (library closures, odd ids, namespace `ns`). `v` is the variant. -/
inductive BLam where
  /-- The thunk of `IO(new IODeferred)` (`IO.scala:1824`). -/
  | newDeferred
  /-- `State(capacity, 0, _)` (`CB:65`). -/
  | mkState (cap : Nat)
  /-- `a => F.ref(a)` (the eta-expansion of `F.ref` in `.flatMap(F.ref)`, `CB:65`). -/
  | refK
  /-- The thunk of `IO(Ref.unsafe(x))` (`IO.scala:1822`). -/
  | newRef (x : Val)
  /-- `state => new CyclicBarrier[F] { … }` (`CB:65-90`). -/
  | mkBarrier (cap v : Nat)
  /-- The barrier object (`CB:66-89`): `nat 0` ↦ `await`. -/
  | obj (r cap v : Nat)
  /-- `gate => state.flatModifyFull { … }` (`CB:68-88`). -/
  | gateK (r cap v : Nat)
  /-- `poll => F.flatten(modify(f(poll, _)))` of `flatModifyFull` (`K/Ref.scala:141`). -/
  | fmfBody (r cap g v : Nat)
  /-- The thunk of `modify(f(poll, _))` (`SyncRef.scala:86-95`) with `f` of `CB:69-87`. -/
  | modifyThunk (r cap g m p v : Nat)
  /-- `fa => fa` of `flatten`, on an effect code. -/
  | flattenK
  /-- The thunk of `cleanup` = `state.update { s => … }` (`CB:79-82`, `SyncRef.scala:65-73`). -/
  | cleanupThunk (r e v : Nat)
  /-- Not Cats Effect code (battery variant 6): `d => d.get` on a new `Deferred` (never returns). -/
  | neverK
  deriving DecidableEq, Repr

def BLam.toVal : BLam → Val
  | .newDeferred => cloVal ns 0 []
  | .mkState cap => cloVal ns 1 [.nat cap]
  | .refK => cloVal ns 2 []
  | .newRef x => cloVal ns 3 [x]
  | .mkBarrier cap v => cloVal ns 4 [.nat cap, .nat v]
  | .obj r cap v => cloVal ns 5 [.ref r, .nat cap, .nat v]
  | .gateK r cap v => cloVal ns 6 [.ref r, .nat cap, .nat v]
  | .fmfBody r cap g v => cloVal ns 7 [.ref r, .nat cap, .deferred g, .nat v]
  | .modifyThunk r cap g m p v => cloVal ns 8 [.ref r, .nat cap, .deferred g, .poll m p, .nat v]
  | .flattenK => cloVal ns 9 []
  | .cleanupThunk r e v => cloVal ns 10 [.ref r, .nat e, .nat v]
  | .neverK => cloVal ns 11 []

def BLam.ofFields : Nat → List Val → Option BLam
  | 0, [] => some .newDeferred
  | 1, [.nat cap] => some (.mkState cap)
  | 2, [] => some .refK
  | 3, [x] => some (.newRef x)
  | 4, [.nat cap, .nat v] => some (.mkBarrier cap v)
  | 5, [.ref r, .nat cap, .nat v] => some (.obj r cap v)
  | 6, [.ref r, .nat cap, .nat v] => some (.gateK r cap v)
  | 7, [.ref r, .nat cap, .deferred g, .nat v] => some (.fmfBody r cap g v)
  | 8, [.ref r, .nat cap, .deferred g, .poll m p, .nat v] => some (.modifyThunk r cap g m p v)
  | 9, [] => some .flattenK
  | 10, [.ref r, .nat e, .nat v] => some (.cleanupThunk r e v)
  | 11, [] => some .neverK
  | _, _ => none

/-- The closure id (odd: a library closure). -/
def BLam.id (l : BLam) : Nat := 2 * valToNat l.toVal + 1

/-- The closure as a `Fn`. -/
def BLam.fn (l : BLam) : Fn := .user l.id

/-- The closure of an id, if it is one of this mirror. -/
def BLam.ofId? (id : Nat) : Option BLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then BLam.ofFields tag fs else none
    | none => none
  else none

/-! ## Builders -/

/-- `CyclicBarrier[IO](capacity)` (`CB:58-91`): `none` when `capacity < 1` (Scala throws
`IllegalArgumentException` while it builds the term, `CB:59-61`). -/
def apply? (cap : Nat) (v : Nat := 0) : Option IO :=
  if cap < 1 then none
  else some (.map (.flatMap (.map (.delay BLam.newDeferred.fn) (BLam.mkState cap).fn) BLam.refK.fn)
    (BLam.mkBarrier cap v).fn)

/-- The barrier object with state cell `r` (a closure reference). -/
def barrierVal (r cap : Nat) (v : Nat := 0) : Val := .fn (BLam.obj r cap v).id

/-- `await` (`CB:67-88`) = `F.deferred[Unit].flatMap { gate => … }`. Variants 5-7 replace the
whole operation (battery, not Cats Effect code). -/
def awaitIO (r cap : Nat) (v : Nat := 0) : IO :=
  if v == 5 then .error battErr
  else if v == 6 then .flatMap (.delay BLam.newDeferred.fn) BLam.neverK.fn
  else if v == 7 then .pure .unit
  else .flatMap (.delay BLam.newDeferred.fn) (BLam.gateK r cap v).fn

/-- `cleanup` (`CB:79-82`). -/
def cleanupIO (r e v : Nat) : IO := .delay (BLam.cleanupThunk r e v).fn

/-- The state cell, capacity and variant of a barrier value. -/
def barrierOf? (b : Val) : Option (Nat × Nat × Nat) :=
  match b with
  | .fn id =>
    match BLam.ofId? id with
    | some (.obj r cap v) => some (r, cap, v)
    | _ => none
  | _ => none

/-- The `IO` of an effect code (`fa => fa` of `flatten`). -/
def effIO : Eff → IO
  -- `unblock.complete(()).void`
  | .trip d => .map (.delay (.rt (.deferredComplete d .unit))) (.rt .voidK)
  -- `poll(unblock.get).onCancel(cleanup)`
  | .wait r e d snap m p v => .onCancel (IO.applyPoll (IO.deferredGetOf d (snapDOpt snap)) m p) (cleanupIO r e v)
  | .unit => .pure .unit

private def ret (x : Val) : UserResult := { out := .ret x }
private def prog (q : IO) : UserResult := { out := .prog q }
private def illTyped : UserResult := { out := .throw illErr }

/-- Run closure `l` on `arg` with view `w`. -/
def call (l : BLam) (arg : Val) (w : View) : UserResult :=
  match l with
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred w.deferreds.length) }
  | .mkState cap =>
    match arg with
    | .deferred d => ret (stateVal cap 0 d)
    | _ => illTyped
  | .refK => prog (.delay (BLam.newRef arg).fn)
  | .newRef x => { effects := [.allocRef x], out := .ret (.ref w.refs.length) }
  | .mkBarrier cap v =>
    match arg with
    | .ref r => ret (barrierVal r cap v)
    | _ => illTyped
  | .obj r cap v =>
    match arg with
    | .nat 0 => prog (awaitIO r cap v)
    | _ => illTyped
  | .gateK r cap v =>
    match arg with
    -- `state.flatModifyFull { … }` = `uncancelable(poll => flatten(modify(f(poll, _))))`
    | .deferred g => prog (.uncancelable (BLam.fmfBody r cap g v).fn)
    | _ => illTyped
  | .fmfBody r cap g v =>
    match arg with
    | .poll m p => prog (.flatMap (.delay (BLam.modifyThunk r cap g m p v).fn) BLam.flattenK.fn)
    | _ => illTyped
  | .modifyThunk r cap g m p v =>
    match St.ofVal (w.refs.getD r .unit) with
    | .mk a e d =>
      -- `val awaitingNow = awaiting - 1` (variant 8, not Cats Effect code: `- 2`)
      let now := if v == 8 then a - 2 else a - 1
      -- `if (awaitingNow == 0)` (variant 1, not Cats Effect code: `awaitingNow ≤ 1`)
      if (if v == 1 then now ≤ 1 else if v == 8 then now ≤ 0 else now == 0) then
        -- `State(capacity, epoch + 1, gate) -> unblock.complete(()).void`
        { effects := [.writeRef r (stateVal cap (e + 1) g)],
          out := .ret (if v == 4 then Eff.unit.toVal else (Eff.trip d).toVal) }
      else
        -- `newState -> poll(unblock.get).onCancel(cleanup)`; `unblock.get` reads the cell now
        { effects := [.writeRef r (stateVal now e d)],
          out := .ret (Eff.wait r e d (snapD (w.deferred d)) m p v).toVal }
    | .bad => illTyped
  | .flattenK =>
    match Eff.ofVal? arg with
    | some x => prog (effIO x)
    | none => illTyped
  | .cleanupThunk r e v =>
    match St.ofVal (w.refs.getD r .unit) with
    -- `if (s.epoch == epoch) s.copy(awaiting = s.awaiting + 1) else s`
    | .mk a e' d =>
      if v == 2 then { effects := [.writeRef r (stateVal a e' d)], out := .ret .unit }
      else if v == 3 || e' == e then { effects := [.writeRef r (stateVal (a + 1) e' d)], out := .ret .unit }
      else { effects := [.writeRef r (stateVal a e' d)], out := .ret .unit }
    | .bad => illTyped
  | .neverK =>
    match arg with
    | .deferred d => prog (IO.deferredGetOf d (w.deferred d))
    | _ => illTyped

/-- The closures of this mirror (`WellFormed`: user code may name them; their captured handles
must be available). -/
def isLib (id : Nat) : Bool := (BLam.ofId? id).isSome

end CatsEffectInLean.Std.CyclicBarrier

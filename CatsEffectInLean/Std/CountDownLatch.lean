import CatsEffectInLean.Model.Codec

/-!
# `std.CountDownLatch` (mirror; Phase 7, track L)

`CDL` = `std/shared/src/main/scala/cats/effect/std/CountDownLatch.scala` at `v3.7.1`.
`K/` = `kernel/shared/src/main/scala/cats/effect/kernel/`, `IO.scala` =
`core/shared/src/main/scala/cats/effect/IO.scala`, both at `v3.7.1`.

```scala
def apply[F[_]](n: Int)(implicit F: GenConcurrent[F, ?]): F[CountDownLatch[F]] =   // CDL:57
  if (n < 1)
    throw new IllegalArgumentException(...)                                          // CDL:58-60
  else
    for {
      state <- State.initial[F](n)                                                   // CDL:63
      ref <- F.ref(state)                                                            // CDL:64
    } yield new ConcurrentCountDownLatch[F](ref)                                     // CDL:65

override def release: F[Unit] =                                                      // CDL:71
  state.flatModify {
    case Awaiting(n, signal) =>
      if (n > 1) (Awaiting(n - 1, signal), F.unit) else (Done(), signal.complete(()).void)
    case d @ Done() => (d, F.unit)
  }

override def await: F[Unit] =                                                        // CDL:78
  state.get.flatMap {
    case Awaiting(_, signal) => signal.get
    case Done() => F.unit
  }

def initial[F[_]](n: Int)(implicit F: GenConcurrent[F, ?]): F[State[F]] =           // CDL:92
  F.deferred[Unit].map { signal => Awaiting(n, signal) }
```

## Operations with `F = IO` (`GenConcurrent[IO]` = `IO.asyncForIO`, `IOAsync`)

* `F.deferred` = `IO.deferred` = `IO(new IODeferred)` (`IO.scala:2163`, `:1824`): a `Delay`.
* `F.ref(a)` = `IO.ref(a)` = `IO(Ref.unsafe(a))` (`IO.scala:2161`, `:1822`); `Ref.unsafe` is a
  `SyncRef` (`K/Ref.scala:314`). `SyncRef.get` = `F.delay(ar.get)`
  (`kernel/jvm-native/src/main/scala/cats/effect/kernel/SyncRef.scala:30`), `modify` =
  `F.delay(spin)` (`SyncRef.scala:86-95`). One model step is atomic, so the CAS loop succeeds the
  first time and writes the new value.
* `flatModify(f)` = `F.uncancelable(_ => F.flatten(modify(f)))` (`K/Ref.scala:123-124`, not
  overridden by `SyncRef`); `F.flatten` = cats `flatMap(ffa)(fa => fa)` (not overridden).
* The `for` is `State.initial(n).flatMap(state => F.ref(state).map(ref => new ...))`;
  `flatMap`/`map` = `IOAsync.flatMap`/`map` = `FlatMap`/`Map` (`IO.scala:2098-2102`).
* `F.unit` = `IO.unit` = `Pure(())` (`IO.scala:2020-2021`, `:1715`, `:1720`).
* `signal.complete(())` = `IO { ... }` (`core/shared/src/main/scala/cats/effect/IODeferred.scala:62-69`,
  `RtFn.deferredComplete`); `.void` = `IOAsync.void` = `IO#void` = `map(_ => ())`
  (`IO.scala:2152`, `:961-962`, `RtFn.voidK`).
* `signal.get` = `cell.get()` (`IODeferred.scala:71`): it reads the cell when the closure runs
  (`IO.deferredGetOf`).

## Encoding

* The `Ref` holds the state: `Awaiting(n, signal)` = `pair (nat n) (deferred d)`, `Done()` =
  `none` (`St`). `latches: Int` is at least 1 in every reachable state (`apply` checks `n ≥ 1`,
  `release` decrements only when `n > 1`), so it is a `Nat`.
* The latch object `new ConcurrentCountDownLatch(ref)` is a closure reference
  `Val.fn (CLam.obj r v).id` (odd id; decision 58). Its methods are calls of that closure:
  argument `nat 0` is `release`, `nat 1` is `await`. A program that holds the reference can call
  them; it cannot read or write the state cell `r` (the cell is captured by the closure, not held:
  `WF.avail`).
* The `F[Unit]` that `modify` returns is an effect code (`Eff`, namespace `effNs`), and
  `fa => fa` of `flatten` (`flattenK`) builds the `IO` from it. Handles in the codes are `Val`
  handles, so a program can name a code only with the handles it holds.
* `apply` with `n < 1` throws while Scala builds the term, not inside `F`. `apply? n` is `none`
  then; a closure that mirrors code that calls `apply` returns `UserOut.throw iaeErr`.

## Variants (not Cats Effect code, `v ≠ 0`)

`v = 0` is Cats Effect v3.7.1. The other values are wrong functions for the wrong-function tests
(`wiki/methodology/agent-workflow.md`, review rubric): `1` releases the waiters one `release`
early (`n > 2`), `2` never completes `signal` ("never wake"), `3` raises on `release` after
`Done` ("release beyond 0 fails").

Decision 63 battery (wrong functions, one per public operation and failure kind): `4` `release`
always raises, `5` `release` never returns, `6` `release` drops its effect (returns `()`, no
decrement), `7` `release` doubles its effect (decrements by 2), `8` `await` always raises, `9`
`await` never returns, `10` `await` drops its effect (returns `()` at once). `await` has no effect
on the state, so "doubles" is meaningless for it (two `await`s return at the same time as one).
-/

namespace CatsEffectInLean.Std.CountDownLatch

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the closures (track L, Phase 7: namespaces 70..79). -/
def ns : Nat := 70
/-- The namespace of the effect codes. -/
def effNs : Nat := 71

/-- `IllegalArgumentException` (`CDL:59-60`). -/
def iaeErr : Err := { code := 7000001 }

/-- An argument of the wrong shape: impossible in a well-typed Scala program. -/
def illErr : Err := { code := 999999, kind := .fatal }

/-- The error of the battery variants that raise (not Cats Effect code). -/
def battErr : Err := { code := 7000010 }

/-! ## State -/

/-- `Awaiting(n, signal)` (`CDL:87-88`). -/
def awaitingVal (n d : Nat) : Val := .pair (.nat n) (.deferred d)

/-- `Done()` (`CDL:89`). -/
def doneVal : Val := .none

/-- The state as Scala sees it. -/
inductive St where
  | awaiting (n d : Nat)
  | done
  /-- Not a state value (impossible in a typed program). -/
  | bad
  deriving DecidableEq, Repr

def St.ofVal : Val → St
  | .pair (.nat n) (.deferred d) => .awaiting n d
  | .none => .done
  | _ => .bad

/-! ## Effect codes -/

/-- An `F[Unit]` that `modify` returns. -/
inductive Eff where
  /-- `F.unit`. -/
  | unit
  /-- `signal.complete(()).void`. -/
  | complete (d : Nat)
  deriving DecidableEq, Repr

def Eff.toVal : Eff → Val
  | .unit => cloVal effNs 0 []
  | .complete d => cloVal effNs 1 [.deferred d]

def Eff.ofVal? (c : Val) : Option Eff :=
  match ofCloVal c with
  | some (k, 0, []) => if k == effNs then some .unit else none
  | some (k, 1, [.deferred d]) => if k == effNs then some (.complete d) else none
  | _ => none

/-! ## Closures -/

/-- The lambdas (library closures, odd ids, namespace `ns`). `v` is the variant. -/
inductive CLam where
  /-- The thunk of `IO(new IODeferred)` (`IO.scala:1824`). -/
  | newDeferred
  /-- `signal => Awaiting(n, signal)` (`CDL:93`). -/
  | awaitingK (n : Nat)
  /-- `state => F.ref(state).map(ref => new ConcurrentCountDownLatch[F](ref))` (`CDL:63-65`). -/
  | refK (v : Nat)
  /-- The thunk of `IO(Ref.unsafe(x))` (`IO.scala:1822`, `K/Ref.scala:314`). -/
  | newRef (x : Val)
  /-- `ref => new ConcurrentCountDownLatch[F](ref)` (`CDL:65`). -/
  | mkLatch (v : Nat)
  /-- The latch object `ConcurrentCountDownLatch(state)` (`CDL:67-84`): `nat 0` ↦ `release`,
  `nat 1` ↦ `await`. -/
  | obj (r v : Nat)
  /-- `_ => F.flatten(modify(f))` of `flatModify` (`K/Ref.scala:124`), `f` of `CDL:72-76`. -/
  | relBody (r v : Nat)
  /-- The thunk of `modify(f)` (`SyncRef.scala:86-95`) with `f` of `CDL:72-76`. -/
  | relModify (r v : Nat)
  /-- `fa => fa` of `flatten`, on an effect code. -/
  | flattenK
  /-- The thunk of `state.get` = `F.delay(ar.get)` (`SyncRef.scala:30`). -/
  | stateGet (r : Nat)
  /-- `{ case Awaiting(_, signal) => signal.get; case Done() => F.unit }` (`CDL:79-82`). -/
  | awaitSel
  deriving DecidableEq, Repr

def CLam.toVal : CLam → Val
  | .newDeferred => cloVal ns 0 []
  | .awaitingK n => cloVal ns 1 [.nat n]
  | .refK v => cloVal ns 2 [.nat v]
  | .newRef x => cloVal ns 3 [x]
  | .mkLatch v => cloVal ns 4 [.nat v]
  | .obj r v => cloVal ns 5 [.ref r, .nat v]
  | .relBody r v => cloVal ns 6 [.ref r, .nat v]
  | .relModify r v => cloVal ns 7 [.ref r, .nat v]
  | .flattenK => cloVal ns 8 []
  | .stateGet r => cloVal ns 9 [.ref r]
  | .awaitSel => cloVal ns 10 []

def CLam.ofFields : Nat → List Val → Option CLam
  | 0, [] => some .newDeferred
  | 1, [.nat n] => some (.awaitingK n)
  | 2, [.nat v] => some (.refK v)
  | 3, [x] => some (.newRef x)
  | 4, [.nat v] => some (.mkLatch v)
  | 5, [.ref r, .nat v] => some (.obj r v)
  | 6, [.ref r, .nat v] => some (.relBody r v)
  | 7, [.ref r, .nat v] => some (.relModify r v)
  | 8, [] => some .flattenK
  | 9, [.ref r] => some (.stateGet r)
  | 10, [] => some .awaitSel
  | _, _ => none

/-- The closure id (odd: a library closure). -/
def CLam.id (l : CLam) : Nat := 2 * valToNat l.toVal + 1

/-- The closure as a `Fn`. -/
def CLam.fn (l : CLam) : Fn := .user l.id

/-- The closure of an id, if it is one of this mirror. -/
def CLam.ofId? (id : Nat) : Option CLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then CLam.ofFields tag fs else none
    | none => none
  else none

/-! ## Builders -/

/-- `CountDownLatch[IO](n)` (`CDL:57-65`): `none` when `n < 1` (Scala throws
`IllegalArgumentException` while it builds the term, `CDL:58-60`). -/
def apply? (n : Nat) (v : Nat := 0) : Option IO :=
  if n < 1 then none
  else some (.flatMap (.map (.delay CLam.newDeferred.fn) (CLam.awaitingK n).fn) (CLam.refK v).fn)

/-- The latch object with state cell `r` (a closure reference). -/
def latchVal (r : Nat) (v : Nat := 0) : Val := .fn (CLam.obj r v).id

/-- A program that never returns (battery variants only): a new `Deferred`, read with the
`await` selector of `Awaiting(1, d)`. -/
def neverIO : IO := .flatMap (.map (.delay CLam.newDeferred.fn) (CLam.awaitingK 1).fn) CLam.awaitSel.fn

/-- `release` (`CDL:71-76`) = `state.flatModify(f)` = `Uncancelable(_ => flatten(modify(f)))`.
Variants 4-6 replace the whole operation (battery, not Cats Effect code). -/
def releaseIO (r : Nat) (v : Nat := 0) : IO :=
  if v == 4 then .error battErr
  else if v == 5 then neverIO
  else if v == 6 then .pure .unit
  else .uncancelable (CLam.relBody r v).fn

/-- `await` (`CDL:78-82`) = `state.get.flatMap { … }`. Variants 8-10 replace the whole operation
(battery, not Cats Effect code). -/
def awaitIO (r : Nat) (v : Nat := 0) : IO :=
  if v == 8 then .error battErr
  else if v == 9 then neverIO
  else if v == 10 then .pure .unit
  else .flatMap (.delay (CLam.stateGet r).fn) CLam.awaitSel.fn

/-- The state cell and variant of a latch value. -/
def latchOf? (l : Val) : Option (Nat × Nat) :=
  match l with
  | .fn id =>
    match CLam.ofId? id with
    | some (.obj r v) => some (r, v)
    | _ => none
  | _ => none

/-- The `IO` of an effect code (`fa => fa` of `flatten`). -/
def effIO : Eff → IO
  | .unit => .pure .unit
  -- `signal.complete(()).void`
  | .complete d => .map (.delay (.rt (.deferredComplete d .unit))) (.rt .voidK)

private def ret (x : Val) : UserResult := { out := .ret x }
private def prog (p : IO) : UserResult := { out := .prog p }
private def illTyped : UserResult := { out := .throw illErr }

/-- Run closure `l` on `arg` with view `w`. -/
def call (l : CLam) (arg : Val) (w : View) : UserResult :=
  match l with
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred w.deferreds.length) }
  | .awaitingK n =>
    match arg with
    | .deferred d => ret (awaitingVal n d)
    | _ => illTyped
  -- `F.ref(state).map(ref => new ConcurrentCountDownLatch[F](ref))`
  | .refK v => prog (.map (.delay (CLam.newRef arg).fn) (CLam.mkLatch v).fn)
  | .newRef x => { effects := [.allocRef x], out := .ret (.ref w.refs.length) }
  | .mkLatch v =>
    match arg with
    | .ref r => ret (latchVal r v)
    | _ => illTyped
  | .obj r v =>
    match arg with
    | .nat 0 => prog (releaseIO r v)
    | .nat 1 => prog (awaitIO r v)
    | _ => illTyped
  | .relBody r v => prog (.flatMap (.delay (CLam.relModify r v).fn) CLam.flattenK.fn)
  | .relModify r v =>
    match St.ofVal (w.refs.getD r .unit) with
    -- `case Awaiting(n, signal) => if (n > 1) (Awaiting(n - 1, signal), F.unit) else (Done(), …)`
    | .awaiting n d =>
      if v == 7 then
        -- variant 7 (not Cats Effect code): the decrement is applied twice
        if n > 2 then { effects := [.writeRef r (awaitingVal (n - 2) d)], out := .ret Eff.unit.toVal }
        else { effects := [.writeRef r doneVal], out := .ret (Eff.complete d).toVal }
      else if (if v == 1 then n > 2 else n > 1) then
        { effects := [.writeRef r (awaitingVal (n - 1) d)], out := .ret Eff.unit.toVal }
      else if v == 2 then
        -- variant 2 (not Cats Effect code): never completes `signal`
        { effects := [.writeRef r doneVal], out := .ret Eff.unit.toVal }
      else { effects := [.writeRef r doneVal], out := .ret (Eff.complete d).toVal }
    -- `case d @ Done() => (d, F.unit)`
    | .done =>
      if v == 3 then { out := .throw { code := 7000002 } }  -- variant 3 (not Cats Effect code)
      else { effects := [.writeRef r doneVal], out := .ret Eff.unit.toVal }
    | .bad => illTyped
  | .flattenK =>
    match Eff.ofVal? arg with
    | some e => prog (effIO e)
    | none => illTyped
  | .stateGet r => ret (w.refs.getD r .unit)
  | .awaitSel =>
    match St.ofVal arg with
    -- `case Awaiting(_, signal) => signal.get`: `get` reads the cell now
    | .awaiting _ d => prog (IO.deferredGetOf d (w.deferred d))
    -- `case Done() => F.unit`
    | .done => prog (.pure .unit)
    | .bad => illTyped

/-- The closures of this mirror (`WellFormed`: user code may name them; their captured handles
must be available, so a program that does not hold a latch's cell cannot name its closures). -/
def isLib (id : Nat) : Bool := (CLam.ofId? id).isSome

end CatsEffectInLean.Std.CountDownLatch

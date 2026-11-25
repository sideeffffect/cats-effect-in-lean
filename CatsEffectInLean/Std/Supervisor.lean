import CatsEffectInLean.Model.Codec
import CatsEffectInLean.Model.Bracket
import CatsEffectInLean.Model.Race
import CatsEffectInLean.Model.Timeout

/-!
# `std.Supervisor` (mirror; Phase 7, track V)

`SV` = `std/shared/src/main/scala/cats/effect/std/Supervisor.scala` at `v3.7.1`.
`R` = `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`, `IO.scala` =
`core/shared/src/main/scala/cats/effect/IO.scala`, cats-core 2.13.0 (`cats/...`).

```scala
def apply[F[_]](await: Boolean)(implicit F: Concurrent[F]) = apply[F](await, None)(F)  // SV:128-129
private[std] def apply[F[_]](await, checkRestart)(implicit F: Concurrent[F]) =          // SV:131-139
  F match { case asyncF: Async[F] => applyForAsync(await, checkRestart)(asyncF)
            case _ => applyForConcurrent(await, checkRestart) }
private def supervisor[F[_]](mkState, await, checkRestart)(implicit F: Concurrent[F]) = // SV:160-175
  for {
    doneR <- Resource.eval(F.ref(false))
    state <- Resource.makeCase(mkState(doneR)) {
      case (st, Resource.ExitCase.Succeeded) if await => doneR.set(true) *> st.joinAll
      case (st, _) => doneR.set(true) *> st.cancelAll
    }
  } yield new SupervisorImpl[F](checkRestart, doneR, state)
def supervise[A](fa: F[A]): F[Fiber[F, Throwable, A]] =                                  // SV:184-328
  F.uncancelable { _ =>
    val monitor = checkRestart match {
      case Some(restart) => { (fa, fin) => ... }                                         // SV:187-288
      case None => { (fa, fin) => F.start(fa).flatMap { fib => F.start(fib.join.guarantee(fin)).as(fib) } }
    }
    for {
      done <- F.ref(false); insertResult <- F.deferred[Boolean]; token <- F.unique
      cleanup = state.remove(token)
      fiber <- monitor(insertResult.get.ifM(fa, F.canceled *> F.raiseError[A](new AssertionError(...))),
                       done.set(true) *> cleanup)
      insertOk <- state.add(token, fiber)
      _ <- insertResult.complete(insertOk)
      _ <- done.get.ifM(cleanup, F.unit)
      _ <- { if (!insertOk) F.raiseError(new IllegalStateException("supervisor already shutdown")) else F.unit }
    } yield fiber
  }
applyForConcurrent: state = F.ref[Map[Token, Fiber]](Map.empty).map { stateRef => ... }  // SV:331-366
applyForAsync: state = F.delay { new ConcurrentHashMap[Token, Fiber] ... }               // SV:368-409
```

The restart branch (`SV:187-288`) and both `State` implementations are mirrored closure by
closure below (each constructor cites its lines).

## `F = IO`

`Supervisor[IO](await)` takes the `Async` branch (`SV:136`): `IO.asyncForIO` is an `Async`.
`applyForConcurrent` (`SV:331-366`) runs only for an `F` that is `Concurrent` and not `Async`; it
is mirrored too (`cv = 1`), as a twin (`F = IO` through the `private[effect]` entry point).

* `F.ref(a)` = `IO.ref(a)` = `IO(Ref.unsafe(a))` (`IO.scala:2161`, `:1822`): a `Delay`; `get` =
  `F.delay(ar.get)`, `set(a)` = `F.delay(ar.set(a))`, `update`, `modify`, `getAndSet` = one
  `F.delay` (`kernel/jvm-native/.../SyncRef.scala:30-95`). One model step is atomic.
* `F.deferred` = `IO(new IODeferred)` (`IO.scala:2163`, `:1824`); `get` reads the cell when it is
  called (`IO.deferredGetOf`); `complete` = `RtFn.deferredComplete` (`IODeferred.scala:62-69`).
* `F.unique` = `Sync#unique` = `delay(new Unique.Token())` (`kernel/.../Sync.scala:38-39`; `IO`
  does not override it). A token is a fresh model `Ref` cell (`.ref t`), used only for identity.
* `F.start` = `Start`, `F.canceled` = `Canceled`, `F.raiseError` = `Error`, `F.unit` = `Pure(())`,
  `F.uncancelable` = `Uncancelable`; `flatMap`/`map`/`as`/`void`/`*>` are the `IOAsync`
  overrides (`IO.scala:2008`, `:2081-2082`, `:2098-2102`, `:2152`): `*>` = `flatMap(_ => that)`
  with `that` built first, `as(b)` = `map(_ => b)`, `void` = `map(_ => ())`.
* `x.guarantee(fin)` = `IOAsync.guarantee` = `IO#guarantee` (`IO.scala:2023-2024`, mirror
  `Bracket.guaranteeIO`); `x.guaranteeCase(f)` = `IO#guaranteeCase` (`IO.scala:2026-2027`, mirror
  `Bracket.guaranteeCaseIO`).
* `ifM(t, f)` = cats `FlatMap#ifM` = `flatMap(if (_) t else f)` (`cats/FlatMap.scala:142-143`).
* `fiber.join`/`fiber.cancel` of an `IOFiber` read `_join`/`_cancel` when they are called
  (`IO.joinOf`, `IO.cancelOf`, with the outcome at that time).
* `Resource#use(f)` = `fold(f, _.apply(_))` (`R:207-208`); `fold` (`R:156-196`) on this `Resource`:
  `Bind(Eval(F.ref(false)), k1)` → `F.ref(false).flatMap(a => continue(Pure(a), Frame(k1, Nil)))`
  (`R:191-192`) → `k1(doneR)` = `Bind(Allocate(_ => mkState(doneR).map(a => (a, e => release(a, e)))), mapK)`
  (`R:388-389`, `:396-397`, `:849-850`, `:879-880`, `:917-920`) → `F.bracketFull(resource)(useK)(relK)`
  (`R:173-184`, mirror `Bracket.bracketFullIO`); `useK` continues with `mapK(a)` = `Pure(new
  SupervisorImpl(...))` and then `onOutput` = `f`; `relK` = `onRelease(release,
  ExitCase.fromOutcome(outcome))` (`R:1229-1234`).
* `traverse_` on a `List` with `IO` (a `StackSafeMonad`) = `traverseVoidDirectly`:
  `[] ↦ G.unit`, else `G.void(foldLeft(f(first))(productR))` (`cats/Foldable.scala:603-604`,
  `cats/instances/list.scala:137-139`, `cats/Traverse.scala:299-309`); `f(a)` is built while the
  fold runs.
* `parUnorderedTraverse(f)` = `P.sequential(Traverse[List].traverse(ta)(a => P.parallel(f(a))))`
  (`cats/Parallel.scala:296-299`) with `G = ParallelF[IO, *]` (not a `StackSafeMonad`):
  `[] ↦ G.pure(Nil)`, else `G.map(Chain.traverseViaChain(as)(f))(_.toList)`
  (`cats/instances/list.scala:121-132`, `cats/data/Chain.scala:1190-1234`, width 128);
  `map2Eval` = `map2` (`cats/Apply.scala`, not overridden), `map2(a, b)(f)` =
  `ParallelF(F.both(a, b).map { case (x, y) => f(x, y) })`, `map` = `Map`
  (`kernel/.../instances/GenSpawnInstances.scala:49-66`); `F.both` = the kernel default
  (`Race.bothIO`).

## Encoding

* The supervisor `SupervisorImpl(checkRestart, doneR, state)` is a closure reference
  `Val.fn (SLam.obj s).id` (odd id, decision 58); calling it with a source code `src` is
  `supervise(fa)` where `fa` is the program of `src` (the caller's `ioOf`, as `Bracket.Src.ext`).
  `s` = `supV d m rs cv v`: `doneR` cell `d`, state cell `m`, `checkRestart` `rs` (`none` or
  `some (fn k)` with `k` a function `Outcome => Boolean`), state kind `cv` (0 = `applyForAsync`,
  1 = `applyForConcurrent`), variant `v`.
* The state cell holds the map as a list of `pair token fiber` in insertion order; the
  `Concurrent` state uses `none` for `null` (`SV:353-356`). The iteration order of
  `ConcurrentHashMap.values` and of a Scala `HashMap` depends on identity hashes; the mirror
  takes it as an input `ho : List Val → List Val` (applied to the entries; statements require
  that it is a permutation).
* A fiber in the map is `fiber t` (an `IOFiber`, `checkRestart = None`) or the restart wrapper
  `Val.fn (SLam.wrap r).id` (`SV:231-282`; `nat 0` ↦ `cancel`, `nat 1` ↦ `join`).
  Scala's `null` in `Deferred[Fiber]` is `none`.
* An `IO` that Scala holds as a value (`cleanup`, `fin`, the sides of `both`, the elements of a
  traverse) is a descriptor code (`D`, namespace `effNs`); `dIO` rebuilds the term.

## Variants (not Cats Effect code, `v ≠ 0`)

Wrong functions for the battery (decision 63) and the wrong-function tests: `1` `supervise`
raises, `2` `supervise` never returns, `3` `supervise` drops (starts `IO.unit`, not `fa`; no
state), `4` `supervise` doubles (`supervise(fa) *> supervise(fa)`), `5` the factory raises
(`use` fails before the body), `6` the factory never returns, `7` the finalizer drops (sets
`doneR`, does not cancel or join), `8` `await = false` joins instead of cancels, `9` `add`
ignores the shutdown (always `true`), `10` `remove` never removes, `11` the restart ignores
`canceled` and `done`, `12` `await = true` cancels instead of joins.
-/

namespace CatsEffectInLean.Std.Supervisor

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the closures (track V, Phase 7: namespaces 80..89). -/
def ns : Nat := 80
/-- The namespace of the descriptor codes. -/
def effNs : Nat := 81

/-- `IllegalStateException("supervisor already shutdown")` (`SV:322`). -/
def iseErr : Err := { code := 8000001 }
/-- `AssertionError("supervised fiber couldn't cancel ...")` (`SV:309-310`). -/
def aeCancelErr : Err := { code := 8000002, kind := .fatal }
/-- `AssertionError("unexpected fiber ...")` (`SV:268-269`). -/
def aeFiberErr : Err := { code := 8000003, kind := .fatal }
/-- An argument of the wrong shape: impossible in a well-typed Scala program. -/
def illErr : Err := { code := 999999, kind := .fatal }
/-- The error of the battery variants that raise (not Cats Effect code). -/
def battErr : Err := { code := 8000010 }

/-! ## Values -/

/-- The supervisor fields: `doneR` cell, state cell, `checkRestart`, state kind, variant. -/
structure Sup where
  d : Nat
  m : Nat
  rs : Val
  cv : Nat
  v : Nat
  deriving DecidableEq, Repr

def Sup.toVal (s : Sup) : Val := listV [.ref s.d, .ref s.m, s.rs, .nat s.cv, .nat s.v]

def Sup.ofVal? : Val → Option Sup
  | x =>
    match unlistV x with
    | some [.ref d, .ref m, rs, .nat cv, .nat v] => some { d, m, rs, cv, v }
    | _ => none

/-- One `supervise` call: the supervisor, the source of `fa`, the `done` cell, the
`insertResult` `Deferred`, the token. -/
structure Call where
  s : Sup
  src : Val
  dl : Nat
  ir : Nat
  tok : Val
  deriving DecidableEq, Repr

def Call.toVal (c : Call) : Val := listV [c.s.toVal, c.src, .ref c.dl, .deferred c.ir, c.tok]

def Call.ofVal? : Val → Option Call
  | x =>
    match unlistV x with
    | some [sv, src, .ref dl, .deferred ir, tok] =>
      match Sup.ofVal? sv with
      | some s => some { s, src, dl, ir, tok }
      | none => none
    | _ => none

/-- The restart context (`SV:188-193`): the call, `resultR`, `canceledR`, `currentR`. -/
structure RCtx where
  c : Call
  res : Nat
  can : Nat
  cur : Nat
  deriving DecidableEq, Repr

def RCtx.toVal (r : RCtx) : Val := listV [r.c.toVal, .deferred r.res, .ref r.can, .ref r.cur]

def RCtx.ofVal? : Val → Option RCtx
  | x =>
    match unlistV x with
    | some [cv, .deferred res, .ref can, .ref cur] =>
      match Call.ofVal? cv with
      | some c => some { c, res, can, cur }
      | none => none
    | _ => none

/-- `ExitCase.fromOutcome` (`R:1229-1234`). -/
def exitCaseOf : Val → Val
  | .ocSucceeded _ => .ocSucceeded .unit
  | .ocErrored e => .ocErrored e
  | _ => .ocCanceled

/-! ## Closures -/

/-- The lambdas (library closures, odd ids, namespace `ns`). -/
inductive SLam where
  /-- The thunk of `IO(Ref.unsafe(x))` (`IO.scala:1822`). -/
  | newRef (x : Val)
  /-- The thunk of `IO(new IODeferred)` (`IO.scala:1824`). -/
  | newDeferred
  /-- The thunk of `F.unique` = `delay(new Unique.Token())` (`Sync.scala:38-39`). -/
  | newToken
  /-- The thunk of `F.delay { new ConcurrentHashMap ... new State ... }` (`SV:372-374`). -/
  | newMap
  /-- `stateRef => new State[F] { ... }` (`SV:335-336`). -/
  | mkStateK
  /-- `a => continue(Resource.pure(a), Frame(k1, Nil))` of `Eval(F.ref(false))` (`R:191-192`),
  then `loop(k1(doneR), Nil)` = `F.bracketFull(...)` (`R:173-184`, `SV:167-174`). `f` = the
  `use` function. -/
  | evalK (aw : Bool) (rs : Val) (cv v f : Nat)
  /-- The `Allocate` function `_ => mkState(doneR).map(a => (a, e => release(a, e)))`
  (`R:849-850`, `:917-920`, `SV:168`). -/
  | acq (aw : Bool) (d cv v : Nat)
  /-- `a => (a, e => release(a, e))` (`R:920`). -/
  | pairRel (aw : Bool) (d cv v : Nat)
  /-- `e => release(st, e)`: the `makeCase` release (`SV:168-173`). -/
  | relE (aw : Bool) (d cv v : Nat) (st : Val)
  /-- `{ case (a, _) => continue(mapK(a), Nil) }` (`R:175-180`): `mapK(a)` =
  `Pure(new SupervisorImpl(checkRestart, doneR, a))` (`SV:174`), then `onOutput` = `f`. -/
  | useK (d : Nat) (rs : Val) (cv v f : Nat)
  /-- `{ case ((_, release), outcome) => onRelease(release, ExitCase.fromOutcome(outcome)) }`
  with `onRelease = _.apply(_)` (`R:181-184`, `:207-208`). -/
  | relK
  /-- The thunk of `ar.set(x)` (`SyncRef.scala`). -/
  | setThunk (r : Nat) (x : Val)
  /-- The thunk of `ar.get` (`SyncRef.scala:30`). -/
  | getThunk (r : Nat)
  /-- `_ => st.joinAll` of `doneR.set(true) *> st.joinAll` (`SV:170`). -/
  | thenJoinAll (m cv : Nat)
  /-- `_ => st.cancelAll` (`SV:172`). -/
  | thenCancelAll (m cv : Nat)
  /-- The thunk of `allFibers` of the `Async` state (`SV:391-401`). -/
  | values (m : Nat)
  /-- The thunk of `stateRef.getAndSet(null)` (`SV:356`). -/
  | getAndSetNull (m : Nat)
  /-- `_.values.toList` (`SV:356`). -/
  | valuesK
  /-- `_.traverse_(_.join.void)` (`SV:359`, `:403`). -/
  | joinTrav
  /-- `_ => f(a)` of `productR` in `traverseVoidDirectly` (`cats/Traverse.scala:305-306`). -/
  | thenD (d : Val)
  /-- `_.parUnorderedTraverse(_.cancel).void` (`SV:361`, `:404`). -/
  | cancelTrav
  /-- `_ :: Nil` (`cats/data/Chain.scala:1205`). -/
  | consNil
  /-- `{ case (a, b) => a :: b }` of `map2` (`Chain.scala:1211`, `GenSpawnInstances.scala:52-54`). -/
  | consK
  /-- `{ case (a, b) => a.concat(b) }` (`Chain.scala:1226`). -/
  | concatK
  /-- `Chain.fromSeq(_)` (`Chain.scala:1214`). -/
  | fromSeqK
  /-- `_.toList` (`cats/instances/list.scala:127`). -/
  | toListK
  /-- `_ => body` of `supervise` (`SV:185`). -/
  | supBody (s src : Val)
  /-- `done => F.deferred[Boolean].flatMap(...)` (`SV:296-297`). -/
  | kDone (s src : Val)
  /-- `insertResult => F.unique.map(...).flatMap(...)` (`SV:297-299`). -/
  | kIr (s src : Val) (dl : Nat)
  /-- `token => { val cleanup = state.remove(token); (token, cleanup) }` (`SV:298-299`). -/
  | tokPair (s : Val)
  /-- `{ case (token, cleanup) => monitor(...).flatMap(...) }` (`SV:299-300`). -/
  | kTok (s src : Val) (dl ir : Nat)
  /-- `fiber => state.add(token, fiber).flatMap(...)` (`SV:300-314`). -/
  | kFib (c : Val)
  /-- `insertOk => insertResult.complete(insertOk).flatMap(...)` (`SV:314-315`). -/
  | kAdd (c fib : Val)
  /-- `_ => done.get.ifM(cleanup, F.unit).flatMap(...)` (`SV:315-319`). -/
  | kCmp (c fib : Val) (ok : Bool)
  /-- `if (_) cleanup else F.unit` (`SV:319`). -/
  | ifDone (c : Val)
  /-- `_ => { if (!insertOk) raise else unit }.map(_ => fiber)` (`SV:319-327`). -/
  | kLast (fib : Val) (ok : Bool)
  /-- `_ => x`. -/
  | constV (x : Val)
  /-- `if (_) fa else F.canceled *> F.raiseError(...)` (`SV:305-311`). -/
  | ifIns (src : Val)
  /-- `_ => F.raiseError(e)` of `*>` (`SV:309`). -/
  | constErr (e : Err)
  /-- `fib => F.start(fib.join.guarantee(fin)).as(fib)` (`SV:291`). -/
  | monNone (c : Val)
  /-- The thunk of `state.put(token, fiber)` (`SV:385`). -/
  | putThunk (m : Nat) (tok fib : Val)
  /-- `_ => doneR.get.map(!_)` of `*>` (`SV:385`). -/
  | thenNotDone (d : Nat)
  /-- `!_` (`SV:385`). -/
  | notK
  /-- The thunk of `state.remove(token)` (`SV:376`). -/
  | removeThunk (m : Nat) (tok : Val) (v : Nat)
  /-- The thunk of `stateRef.update { case null => null; case map => map - token }` (`SV:338-341`). -/
  | updRemove (m : Nat) (tok : Val) (v : Nat)
  /-- The thunk of `stateRef.modify { case null => (null, false); case map => ... }` (`SV:343-347`). -/
  | modAdd (m : Nat) (tok fib : Val) (v : Nat)
  /-- `_ => cleanup` of `done.set(true) *> cleanup` (`SV:312`). -/
  | thenCleanup (c : Val)
  /-- `resultR => F.ref(false).flatMap(...)` (`SV:188-189`). -/
  | rRes (c : Val)
  /-- `canceledR => F.deferred[Fiber].flatMap(...)` (`SV:189-190`). -/
  | rCan (c : Val) (res : Nat)
  /-- `firstCurrent => F.ref(firstCurrent).flatMap(...)` (`SV:190-193`). -/
  | rFirst (c : Val) (res can : Nat)
  /-- `currentR => action(firstCurrent).as(wrapper)` (`SV:193-283`). -/
  | rCur (c : Val) (res can first : Nat)
  /-- `_ => started flatMap { f => current.complete(f).void }` of `action` (`SV:195-227`). -/
  | actBody (r : Val) (current : Nat)
  /-- `f => current.complete(f).void` (`SV:226`). -/
  | actK (current : Nat)
  /-- The `guaranteeCase` finalizer `oc => F.deferred.flatMap { newCurrent => ... }` (`SV:197-223`). -/
  | gcFin (r : Val)
  /-- `newCurrent => currentR.set(newCurrent) *> { ... }` (`SV:198-221`). -/
  | gcNew (r oc : Val)
  /-- `_ => canceledR.get flatMap { ... }` of `*>` (`SV:206-207`). -/
  | thenCan (r oc : Val) (nc : Nat)
  /-- `canceled => doneR.get flatMap { ... }` (`SV:207-208`). -/
  | canSel (r oc : Val) (nc : Nat)
  /-- `done => if (!canceled && !done && restart(oc)) action(newCurrent) else ...` (`SV:208-218`). -/
  | doneSel (r oc : Val) (nc : Nat) (canceled : Bool)
  /-- `_ => fin.guarantee(resultR.complete(oc).void)` of `*>` (`SV:216-217`). -/
  | thenFinRes (r oc : Val)
  /-- The restart wrapper `new Fiber[F, Throwable, A] { ... }` (`SV:231-282`): `nat 0` ↦
  `cancel`, `nat 1` ↦ `join`. -/
  | wrap (r : Val)
  /-- `_ => canceledR.set(true) *> delegateF flatMap { ... }` (`SV:235-240`). -/
  | wBody (r : Val)
  /-- `_ => delegateF` of `*>` (`SV:240`). -/
  | thenDelegate (r : Val)
  /-- `_.get` of `delegateF = currentR.get.flatMap(_.get)` (`SV:233`). -/
  | getDef
  /-- `{ case null => resultR.get.void; case fiber => (fiber.cancel *> fiber.join) flatMap {...} }` (`SV:240-278`). -/
  | wSel1 (r : Val)
  /-- `{ case Outcome.Canceled() => delegateF.flatMap {...}; case _ => resultR.get.void }` (`SV:247-277`). -/
  | wSel2 (r fiber : Val)
  /-- `{ case null => resultR.get.void; case fiber2 => ... }` (`SV:252-271`). -/
  | wSel3 (r fiber : Val)
  /-- `_ => cleanup *> F.raiseError(...)`'s second half (`SV:268`). -/
  | thenRaise (e : Err)
  /-- The supervisor object (`SV:177-329`): a call with a source code is `supervise(fa)`. -/
  | obj (s : Val)
  /-- `_ => supervise(fa)` of the battery variant 4 (not Cats Effect code). -/
  | twice (s src : Val)
  deriving DecidableEq, Repr

def SLam.toVal : SLam → Val
  | .newRef x => cloVal ns 0 [x]
  | .newDeferred => cloVal ns 1 []
  | .newToken => cloVal ns 2 []
  | .newMap => cloVal ns 3 []
  | .mkStateK => cloVal ns 4 []
  | .evalK aw rs cv v f => cloVal ns 5 [.bool aw, rs, .nat cv, .nat v, .fn f]
  | .acq aw d cv v => cloVal ns 6 [.bool aw, .ref d, .nat cv, .nat v]
  | .pairRel aw d cv v => cloVal ns 7 [.bool aw, .ref d, .nat cv, .nat v]
  | .relE aw d cv v st => cloVal ns 8 [.bool aw, .ref d, .nat cv, .nat v, st]
  | .useK d rs cv v f => cloVal ns 9 [.ref d, rs, .nat cv, .nat v, .fn f]
  | .relK => cloVal ns 10 []
  | .setThunk r x => cloVal ns 11 [.ref r, x]
  | .getThunk r => cloVal ns 12 [.ref r]
  | .thenJoinAll m cv => cloVal ns 13 [.ref m, .nat cv]
  | .thenCancelAll m cv => cloVal ns 14 [.ref m, .nat cv]
  | .values m => cloVal ns 15 [.ref m]
  | .getAndSetNull m => cloVal ns 16 [.ref m]
  | .valuesK => cloVal ns 17 []
  | .joinTrav => cloVal ns 18 []
  | .thenD d => cloVal ns 19 [d]
  | .cancelTrav => cloVal ns 20 []
  | .consNil => cloVal ns 21 []
  | .consK => cloVal ns 22 []
  | .concatK => cloVal ns 23 []
  | .fromSeqK => cloVal ns 24 []
  | .toListK => cloVal ns 25 []
  | .supBody s src => cloVal ns 26 [s, src]
  | .kDone s src => cloVal ns 27 [s, src]
  | .kIr s src dl => cloVal ns 28 [s, src, .ref dl]
  | .tokPair s => cloVal ns 29 [s]
  | .kTok s src dl ir => cloVal ns 30 [s, src, .ref dl, .deferred ir]
  | .kFib c => cloVal ns 31 [c]
  | .kAdd c fib => cloVal ns 32 [c, fib]
  | .kCmp c fib ok => cloVal ns 33 [c, fib, .bool ok]
  | .ifDone c => cloVal ns 34 [c]
  | .kLast fib ok => cloVal ns 35 [fib, .bool ok]
  | .constV x => cloVal ns 36 [x]
  | .ifIns src => cloVal ns 37 [src]
  | .constErr e => cloVal ns 38 [.err e]
  | .monNone c => cloVal ns 39 [c]
  | .putThunk m tok fib => cloVal ns 40 [.ref m, tok, fib]
  | .thenNotDone d => cloVal ns 41 [.ref d]
  | .notK => cloVal ns 42 []
  | .removeThunk m tok v => cloVal ns 43 [.ref m, tok, .nat v]
  | .updRemove m tok v => cloVal ns 44 [.ref m, tok, .nat v]
  | .modAdd m tok fib v => cloVal ns 45 [.ref m, tok, fib, .nat v]
  | .thenCleanup c => cloVal ns 46 [c]
  | .rRes c => cloVal ns 47 [c]
  | .rCan c res => cloVal ns 48 [c, .deferred res]
  | .rFirst c res can => cloVal ns 49 [c, .deferred res, .ref can]
  | .rCur c res can first => cloVal ns 50 [c, .deferred res, .ref can, .deferred first]
  | .actBody r current => cloVal ns 51 [r, .deferred current]
  | .actK current => cloVal ns 52 [.deferred current]
  | .gcFin r => cloVal ns 53 [r]
  | .gcNew r oc => cloVal ns 54 [r, oc]
  | .thenCan r oc nc => cloVal ns 55 [r, oc, .deferred nc]
  | .canSel r oc nc => cloVal ns 56 [r, oc, .deferred nc]
  | .doneSel r oc nc canceled => cloVal ns 57 [r, oc, .deferred nc, .bool canceled]
  | .thenFinRes r oc => cloVal ns 58 [r, oc]
  | .wrap r => cloVal ns 59 [r]
  | .wBody r => cloVal ns 60 [r]
  | .thenDelegate r => cloVal ns 61 [r]
  | .getDef => cloVal ns 62 []
  | .wSel1 r => cloVal ns 63 [r]
  | .wSel2 r fiber => cloVal ns 64 [r, fiber]
  | .wSel3 r fiber => cloVal ns 65 [r, fiber]
  | .thenRaise e => cloVal ns 66 [.err e]
  | .obj s => cloVal ns 67 [s]
  | .twice s src => cloVal ns 68 [s, src]

def SLam.ofFields : Nat → List Val → Option SLam
  | 0, [x] => some (.newRef x)
  | 1, [] => some .newDeferred
  | 2, [] => some .newToken
  | 3, [] => some .newMap
  | 4, [] => some .mkStateK
  | 5, [.bool aw, rs, .nat cv, .nat v, .fn f] => some (.evalK aw rs cv v f)
  | 6, [.bool aw, .ref d, .nat cv, .nat v] => some (.acq aw d cv v)
  | 7, [.bool aw, .ref d, .nat cv, .nat v] => some (.pairRel aw d cv v)
  | 8, [.bool aw, .ref d, .nat cv, .nat v, st] => some (.relE aw d cv v st)
  | 9, [.ref d, rs, .nat cv, .nat v, .fn f] => some (.useK d rs cv v f)
  | 10, [] => some .relK
  | 11, [.ref r, x] => some (.setThunk r x)
  | 12, [.ref r] => some (.getThunk r)
  | 13, [.ref m, .nat cv] => some (.thenJoinAll m cv)
  | 14, [.ref m, .nat cv] => some (.thenCancelAll m cv)
  | 15, [.ref m] => some (.values m)
  | 16, [.ref m] => some (.getAndSetNull m)
  | 17, [] => some .valuesK
  | 18, [] => some .joinTrav
  | 19, [d] => some (.thenD d)
  | 20, [] => some .cancelTrav
  | 21, [] => some .consNil
  | 22, [] => some .consK
  | 23, [] => some .concatK
  | 24, [] => some .fromSeqK
  | 25, [] => some .toListK
  | 26, [s, src] => some (.supBody s src)
  | 27, [s, src] => some (.kDone s src)
  | 28, [s, src, .ref dl] => some (.kIr s src dl)
  | 29, [s] => some (.tokPair s)
  | 30, [s, src, .ref dl, .deferred ir] => some (.kTok s src dl ir)
  | 31, [c] => some (.kFib c)
  | 32, [c, fib] => some (.kAdd c fib)
  | 33, [c, fib, .bool ok] => some (.kCmp c fib ok)
  | 34, [c] => some (.ifDone c)
  | 35, [fib, .bool ok] => some (.kLast fib ok)
  | 36, [x] => some (.constV x)
  | 37, [src] => some (.ifIns src)
  | 38, [.err e] => some (.constErr e)
  | 39, [c] => some (.monNone c)
  | 40, [.ref m, tok, fib] => some (.putThunk m tok fib)
  | 41, [.ref d] => some (.thenNotDone d)
  | 42, [] => some .notK
  | 43, [.ref m, tok, .nat v] => some (.removeThunk m tok v)
  | 44, [.ref m, tok, .nat v] => some (.updRemove m tok v)
  | 45, [.ref m, tok, fib, .nat v] => some (.modAdd m tok fib v)
  | 46, [c] => some (.thenCleanup c)
  | 47, [c] => some (.rRes c)
  | 48, [c, .deferred res] => some (.rCan c res)
  | 49, [c, .deferred res, .ref can] => some (.rFirst c res can)
  | 50, [c, .deferred res, .ref can, .deferred first] => some (.rCur c res can first)
  | 51, [r, .deferred current] => some (.actBody r current)
  | 52, [.deferred current] => some (.actK current)
  | 53, [r] => some (.gcFin r)
  | 54, [r, oc] => some (.gcNew r oc)
  | 55, [r, oc, .deferred nc] => some (.thenCan r oc nc)
  | 56, [r, oc, .deferred nc] => some (.canSel r oc nc)
  | 57, [r, oc, .deferred nc, .bool canceled] => some (.doneSel r oc nc canceled)
  | 58, [r, oc] => some (.thenFinRes r oc)
  | 59, [r] => some (.wrap r)
  | 60, [r] => some (.wBody r)
  | 61, [r] => some (.thenDelegate r)
  | 62, [] => some .getDef
  | 63, [r] => some (.wSel1 r)
  | 64, [r, fiber] => some (.wSel2 r fiber)
  | 65, [r, fiber] => some (.wSel3 r fiber)
  | 66, [.err e] => some (.thenRaise e)
  | 67, [s] => some (.obj s)
  | 68, [s, src] => some (.twice s src)
  | _, _ => none

/-- The closure id (odd: a library closure). -/
def SLam.id (l : SLam) : Nat := 2 * valToNat l.toVal + 1

/-- The closure as a `Fn`. -/
def SLam.fn (l : SLam) : Fn := .user l.id

/-- The closure of an id, if it is one of this mirror. -/
def SLam.ofId? (id : Nat) : Option SLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then SLam.ofFields tag fs else none
    | none => none
  else none

/-! ## Descriptors (an `IO` held as a value) -/

/-- Descriptor codes (namespace `effNs`). -/
inductive D where
  /-- `fa' = insertResult.get.ifM(fa, F.canceled *> F.raiseError(...))` (`SV:305-311`), built when
  the cell of `insertResult` held `snap`. -/
  | fa (src : Val) (ir : Nat) (snap : Val)
  /-- `cleanup = state.remove(token)` (`SV:299`). -/
  | cleanup (s tok : Val)
  /-- `fin = done.set(true) *> cleanup` (`SV:312`). -/
  | fin (c : Val)
  /-- `fib.join` of an `IOFiber`, built when `_join` held `snap` (`some oc` or `none`). -/
  | join (t : Nat) (snap : Val)
  /-- `x.join.void` of a fiber in the map, built at `snap` (`SV:359`). -/
  | joinVoid (x snap : Val)
  /-- `P.parallel(x.cancel)` of a fiber in the map, built at `snap` (`SV:361`). -/
  | cancel (x snap : Val)
  /-- A leaf chain of `traverseViaChain` over `xs` (each `pair x snap`), without `fromSeq`
  (`Chain.scala:1205-1213`). -/
  | chain (xs : Val)
  /-- `loop(start, end)` of `traverseViaChain` over `xs` (`Chain.scala:1200-1231`). -/
  | loop (xs : Val)
  /-- `fchain` after the chunks `cs` (`Chain.scala:1219-1229`). -/
  | tree (cs : Val)
  /-- `resultR.complete(oc).void` (`SV:217`, `:262`). -/
  | completeVoid (res : Nat) (oc : Val)
  deriving DecidableEq, Repr

def D.toVal : D → Val
  | .fa src ir snap => cloVal effNs 0 [src, .deferred ir, snap]
  | .cleanup s tok => cloVal effNs 1 [s, tok]
  | .fin c => cloVal effNs 2 [c]
  | .join t snap => cloVal effNs 3 [.fiber t, snap]
  | .joinVoid x snap => cloVal effNs 4 [x, snap]
  | .cancel x snap => cloVal effNs 5 [x, snap]
  | .chain xs => cloVal effNs 6 [xs]
  | .loop xs => cloVal effNs 7 [xs]
  | .tree cs => cloVal effNs 8 [cs]
  | .completeVoid res oc => cloVal effNs 9 [.deferred res, oc]

def D.ofVal? (c : Val) : Option D :=
  match ofCloVal c with
  | some (k, tag, fs) =>
    if k != effNs then none else
    match tag, fs with
    | 0, [src, .deferred ir, snap] => some (.fa src ir snap)
    | 1, [s, tok] => some (.cleanup s tok)
    | 2, [c] => some (.fin c)
    | 3, [.fiber t, snap] => some (.join t snap)
    | 4, [x, snap] => some (.joinVoid x snap)
    | 5, [x, snap] => some (.cancel x snap)
    | 6, [xs] => some (.chain xs)
    | 7, [xs] => some (.loop xs)
    | 8, [cs] => some (.tree cs)
    | 9, [.deferred res, oc] => some (.completeVoid res oc)
    | _, _ => none
  | none => none

/-- A snapshot of an outcome (`none` = not done) as a `Val`. -/
def snapVal : Option Outcome → Val
  | some oc => .some oc.toVal
  | none => .none

/-- A snapshot of a `Deferred` cell as a `Val`. -/
def dsnapVal : Option Val → Val
  | some x => .some x
  | none => .none

def dsnapOf : Val → Option Val
  | .some x => some x
  | _ => none

/-! ## Builders -/

/-- `F.ref(x)` (`IO.scala:2161`, `:1822`). -/
def newRefIO (x : Val) : IO := .delay (SLam.newRef x).fn
/-- `F.deferred` (`IO.scala:2163`, `:1824`). -/
def newDeferredIO : IO := .delay SLam.newDeferred.fn
/-- `r.get` of a `SyncRef`. -/
def getIO (r : Nat) : IO := .delay (SLam.getThunk r).fn
/-- `r.set(x)` of a `SyncRef`. -/
def setIO (r : Nat) (x : Val) : IO := .delay (SLam.setThunk r x).fn
/-- `x.void` = `map(_ => ())` (`IO.scala:961-962`). -/
def voidIO (x : IO) : IO := .map x (.rt .voidK)
/-- `d.complete(x).void`. -/
def completeVoidIO (d : Nat) (x : Val) : IO := voidIO (.delay (.rt (.deferredComplete d x)))
/-- A program that never returns (battery only): `Timeout.neverIO`. -/
def neverIO : IO := Timeout.neverIO

/-- `state.remove(token)` (`SV:338-341`, `:376`). -/
def removeIO (s : Sup) (tok : Val) : IO :=
  if s.cv == 1 then .delay (SLam.updRemove s.m tok s.v).fn
  else voidIO (.delay (SLam.removeThunk s.m tok s.v).fn)

/-- `state.add(token, fiber)` (`SV:343-347`, `:378-386`). -/
def addIO (s : Sup) (tok fib : Val) : IO :=
  if s.cv == 1 then .delay (SLam.modAdd s.m tok fib s.v).fn
  else .flatMap (.delay (SLam.putThunk s.m tok fib).fn) (SLam.thenNotDone s.d).fn

/-- `allFibers` (`SV:352-357`, `:391-401`). -/
def allFibersIO (m cv : Nat) : IO :=
  if cv == 1 then .map (.delay (SLam.getAndSetNull m).fn) SLam.valuesK.fn
  else .delay (SLam.values m).fn

/-- `joinAll` (`SV:359`, `:403`). -/
def joinAllIO (m cv : Nat) : IO := .flatMap (allFibersIO m cv) SLam.joinTrav.fn

/-- `cancelAll` (`SV:361`, `:404`). -/
def cancelAllIO (m cv : Nat) : IO := .flatMap (allFibersIO m cv) SLam.cancelTrav.fn

/-- The `makeCase` release (`SV:168-173`); variants 7, 8, 12 are not Cats Effect code. -/
def releaseIO (aw : Bool) (d cv v : Nat) (st : Val) (ec : Val) : IO :=
  match st with
  | .ref m =>
    if v == 7 then setIO d (.bool true)
    else
      let join := (ec == .ocSucceeded .unit && aw && v != 12) || (v == 8 && !aw)
      if join then .flatMap (setIO d (.bool true)) (SLam.thenJoinAll m cv).fn
      else .flatMap (setIO d (.bool true)) (SLam.thenCancelAll m cv).fn
  | _ => .error illErr

/-- `Supervisor[IO](await)` with `checkRestart = rs`, state kind `cv`, variant `v`, then
`.use(f)` (`SV:128-175`, `R:156-208`): `F.ref(false).flatMap(evalK)`. -/
def useIO (aw : Bool) (rs : Val) (cv v f : Nat) : IO :=
  if v == 5 then .error battErr
  else if v == 6 then neverIO
  else .flatMap (newRefIO (.bool false)) (SLam.evalK aw rs cv v f).fn

/-- The supervisor value. -/
def supVal (s : Sup) : Val := .fn (SLam.obj s.toVal).id

/-- `supervise(fa)` (`SV:184-328`) of the supervisor `s` with `fa` = the program of `src`.
Variants 1-4 replace the operation (battery, not Cats Effect code). -/
def superviseIO (s : Sup) (src : Val) : IO :=
  if s.v == 1 then .error battErr
  else if s.v == 2 then neverIO
  else if s.v == 3 then .start (.pure .unit)
  else if s.v == 4 then
    .flatMap (.uncancelable (SLam.supBody { s with v := 0 }.toVal src).fn) (SLam.twice s.toVal src).fn
  else .uncancelable (SLam.supBody s.toVal src).fn

/-- The supervisor `s` of a supervisor value, if it is one. -/
def supOf? : Val → Option Sup
  | .fn id =>
    match SLam.ofId? id with
    | some (.obj s) => Sup.ofVal? s
    | _ => none
  | _ => none


/-- The wrapper value of a restart context. -/
def wrapVal (r : RCtx) : Val := .fn (SLam.wrap r.toVal).id

/-- The restart context of a wrapper value. -/
def wrapOf? : Val → Option RCtx
  | .fn id =>
    match SLam.ofId? id with
    | some (.wrap r) => RCtx.ofVal? r
    | _ => none
  | _ => none

/-- `action(current)` (`SV:194-228`): `F uncancelable { _ => started flatMap {...} }`. -/
def actionIO (r : RCtx) (current : Nat) : IO := .uncancelable (SLam.actBody r.toVal current).fn

/-- The wrapper `cancel` (`SV:235-279`). -/
def wCancelIO (r : Val) : IO := .uncancelable (SLam.wBody r).fn

/-- `delegateF = currentR.get.flatMap(_.get)` (`SV:233`). -/
def delegateIO (r : RCtx) : IO := .flatMap (getIO r.cur) SLam.getDef.fn

/-- `fin.guarantee(resultR.complete(oc).void)` (`SV:216-217`, `:261-263`). -/
def finResIO (r : RCtx) (oc : Val) : IO :=
  Bracket.guaranteeIO (.ext (D.fin r.c.toVal).toVal) (.ext (D.completeVoid r.res oc).toVal)

/-- The `state.Fiber` element snapshot for a traverse: `pair x snap`. -/
def elemAt (v : View) (x : Val) : Val :=
  match x with
  | .fiber t => .pair x (snapVal (v.outcome t))
  | _ =>
    match wrapOf? x with
    | some r => .pair x (dsnapVal (v.deferred r.res))
    | none => .pair x .none

/-- `F.void(foldLeft(f(first))(productR))` (`cats/Traverse.scala:299-309`): `ds` are descriptor
codes, `d0` the `IO` of the first one. -/
def traverseVoidIO (d0 : IO) (ds : List Val) : IO :=
  voidIO (ds.foldl (fun g x => .flatMap g (SLam.thenD x).fn) d0)

/-- Split `xs` into the chunks of `Chain.traverseViaChain` (`Chain.scala:1217-1229`). -/
def chunks (step : Nat) : (fuel : Nat) → List Val → List (List Val)
  | 0, _ => []
  | _ + 1, [] => []
  | f + 1, xs => xs.take step :: chunks step f (xs.drop step)

/-- `ParallelF(F.both(a, b).map(k))` (`GenSpawnInstances.scala:49-54`). -/
def map2IO (a b : Val) (k : SLam) : IO := .map (Race.bothIO a b) k.fn

/-- `P.parallel(x.cancel)` of one element `pair x snap`. -/
def cancelElemIO : Val → IO
  | .pair (.fiber t) snap => IO.cancelOf t (Timeout.snapOutcome snap)
  | .pair x _ =>
    match wrapOf? x with
    | some r => wCancelIO r.toVal
    | none => .error illErr
  | _ => .error illErr

/-- The leaf chain (`Chain.scala:1205-1213`): right-nested `map2(f(a), right)(_ :: _)`, the last
element `G.map(f(a))(_ :: Nil)`. -/
def chainIO : List Val → IO
  | [] => .pure (listV [])
  | [x] => .map (cancelElemIO x) SLam.consNil.fn
  | x :: rest =>
    match x with
    | .pair y snap => map2IO (D.cancel y snap).toVal (D.chain (listV rest)).toVal SLam.consK
    | _ => .error illErr

/-- `fchain` of the chunks `cs` (`Chain.scala:1219-1229`): `loop(c0)`, then
`map2(fchain, loop(c))(_.concat(_))` for each next chunk. -/
def treeIO (cs : List Val) : IO :=
  match cs.reverse with
  | [] => .error illErr
  | [c] =>
    match unlistV c with
    | some xs => .map (chainIO xs) SLam.fromSeqK.fn
    | none => .error illErr
  | c :: init => map2IO (D.tree (listV init.reverse)).toVal (D.loop c).toVal SLam.concatK

/-- `loop(0, n)` of `Chain.traverseViaChain` (`Chain.scala:1200-1233`, width 128). -/
def loopIO (xs : List Val) : IO :=
  if xs.length ≤ 128 then .map (chainIO xs) SLam.fromSeqK.fn
  else treeIO ((chunks (xs.length / 128) xs.length xs).map listV)

/-- The `IO` of a descriptor. -/
def dIO : D → IO
  -- `insertResult.get.ifM(fa, ...)`
  | .fa src ir snap => .flatMap (IO.deferredGetOf ir (dsnapOf snap)) (SLam.ifIns src).fn
  | .cleanup s tok =>
    match Sup.ofVal? s with
    | some s => removeIO s tok
    | none => .error illErr
  -- `done.set(true) *> cleanup`
  | .fin c =>
    match Call.ofVal? c with
    | some k => .flatMap (setIO k.dl (.bool true)) (SLam.thenCleanup c).fn
    | none => .error illErr
  | .join t snap => IO.joinOf t (Timeout.snapOutcome snap)
  | .joinVoid x snap =>
    match x with
    | .fiber t => voidIO (IO.joinOf t (Timeout.snapOutcome snap))
    | _ =>
      match wrapOf? x with
      -- `def join = resultR.get` (`SV:281`)
      | some r => voidIO (IO.deferredGetOf r.res (dsnapOf snap))
      | none => .error illErr
  | .cancel x snap => cancelElemIO (.pair x snap)
  | .chain xs =>
    match unlistV xs with
    | some l => chainIO l
    | none => .error illErr
  | .loop xs =>
    match unlistV xs with
    | some l => loopIO l
    | none => .error illErr
  | .tree cs =>
    match unlistV cs with
    | some l => treeIO l
    | none => .error illErr
  | .completeVoid res oc => completeVoidIO res oc

/-- The sources of the `Bracket` and `Race` closures: descriptors of this mirror, else `ioOf`. -/
def srcOf (ioOf : Val → IO) (c : Val) : IO :=
  match D.ofVal? c with
  | some d => dIO d
  | none => ioOf c

/-- The map entries of a state cell value (`none` = `null`). -/
def entriesOf : Val → Option (List Val)
  | .none => none
  | x => unlistV x

/-- The fiber of an entry `pair token fiber`. -/
def entryFiber : Val → Val
  | .pair _ f => f
  | _ => .unit

/-- Remove the entry with `tok` (`map - token`, `ConcurrentHashMap.remove`). -/
def removeEntry (tok : Val) (es : List Val) : List Val :=
  es.filter fun e => match e with
    | .pair t _ => t != tok
    | _ => true

/-- Insert or replace the entry of `tok` (`map.updated`, `ConcurrentHashMap.put`). -/
def putEntry (tok fib : Val) (es : List Val) : List Val :=
  if es.any (fun e => match e with | .pair t _ => t == tok | _ => false) then
    es.map fun e => match e with
      | .pair t _ => if t == tok then .pair tok fib else e
      | _ => e
  else es ++ [.pair tok fib]

private def ret (x : Val) : UserResult := { out := .ret x }
private def prog (p : IO) : UserResult := { out := .prog p }
private def illTyped : UserResult := { out := .throw illErr }

/-- Run closure `l` on `arg` with view `v`. `uc` is the full dispatcher (user code and the other
mirrors), `ioOf` builds the program of a `supervise` source, `ho` is the iteration order of the
map (applied to the entries in insertion order). -/
def call (uc : Nat → Val → View → UserResult) (ioOf : Val → IO) (ho : List Val → List Val)
    (l : SLam) (arg : Val) (v : View) : UserResult :=
  match l with
  | .newRef x => { effects := [.allocRef x], out := .ret (.ref v.refs.length) }
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred v.deferreds.length) }
  | .newToken => { effects := [.allocRef .unit], out := .ret (.ref v.refs.length) }
  | .newMap => { effects := [.allocRef (listV [])], out := .ret (.ref v.refs.length) }
  | .mkStateK => ret arg
  | .evalK aw rs cv vr f =>
    match arg with
    | .ref d => prog (Bracket.bracketFullIO (SLam.acq aw d cv vr).id (SLam.useK d rs cv vr f).id SLam.relK.id)
    | _ => illTyped
  -- `mkState(doneR).map(a => (a, e => release(a, e)))`
  | .acq aw d cv vr =>
    let mk := if cv == 1 then .map (newRefIO (listV [])) SLam.mkStateK.fn else .delay SLam.newMap.fn
    prog (.map mk (SLam.pairRel aw d cv vr).fn)
  | .pairRel aw d cv vr => ret (.pair arg (.fn (SLam.relE aw d cv vr arg).id))
  | .relE aw d cv vr st => prog (releaseIO aw d cv vr st arg)
  | .useK d rs cv vr f =>
    match arg with
    | .pair (.ref m) _ => uc f (supVal { d, m, rs, cv, v := vr }) v
    | _ => illTyped
  | .relK =>
    match arg with
    | .pair (.pair _ (.fn r)) oc => uc r (exitCaseOf oc) v
    | _ => illTyped
  | .setThunk r x => { effects := [.writeRef r x], out := .ret .unit }
  | .getThunk r => ret (v.refs.getD r .unit)
  | .thenJoinAll m cv => prog (joinAllIO m cv)
  | .thenCancelAll m cv => prog (cancelAllIO m cv)
  | .values m =>
    match entriesOf (v.refs.getD m .unit) with
    | some es => ret (listV ((ho es).map entryFiber))
    | none => illTyped
  | .getAndSetNull m => { effects := [.writeRef m .none], out := .ret (v.refs.getD m .unit) }
  | .valuesK =>
    match entriesOf arg with
    | some es => ret (listV ((ho es).map entryFiber))
    | none => illTyped
  -- `_.traverse_(_.join.void)`: `f(a)` is built while the fold runs
  | .joinTrav =>
    match unlistV arg with
    | some [] => prog (.pure .unit)
    | some (x :: xs) =>
      let d (y : Val) : Val := match elemAt v y with
        | .pair z snap => (D.joinVoid z snap).toVal
        | _ => .unit
      match D.ofVal? (d x) with
      | some dx => prog (traverseVoidIO (dIO dx) (xs.map d))
      | none => illTyped
    | none => illTyped
  | .thenD d =>
    match D.ofVal? d with
    | some dd => prog (dIO dd)
    | none => illTyped
  -- `P.sequential(traverse(xs)(f)).void`; `f(a)` is built while the `Eval` is forced
  | .cancelTrav =>
    match unlistV arg with
    | some [] => prog (voidIO (.pure (listV [])))
    | some xs => prog (voidIO (.map (loopIO (xs.map (elemAt v))) SLam.toListK.fn))
    | none => illTyped
  | .consNil => ret (listV [arg])
  | .consK =>
    match arg with
    | .pair a b =>
      match unlistV b with
      | some l => ret (listV (a :: l))
      | none => illTyped
    | _ => illTyped
  | .concatK =>
    match arg with
    | .pair a b =>
      match unlistV a, unlistV b with
      | some l1, some l2 => ret (listV (l1 ++ l2))
      | _, _ => illTyped
    | _ => illTyped
  | .fromSeqK => ret arg
  | .toListK => ret arg
  | .supBody s src => prog (.flatMap (newRefIO (.bool false)) (SLam.kDone s src).fn)
  | .kDone s src =>
    match arg with
    | .ref dl => prog (.flatMap newDeferredIO (SLam.kIr s src dl).fn)
    | _ => illTyped
  | .kIr s src dl =>
    match arg with
    | .deferred ir =>
      prog (.flatMap (.map (.delay SLam.newToken.fn) (SLam.tokPair s).fn) (SLam.kTok s src dl ir).fn)
    | _ => illTyped
  | .tokPair s => ret (.pair arg (D.cleanup s arg).toVal)
  | .kTok s src dl ir =>
    match arg, Sup.ofVal? s with
    | .pair tok _, some sp =>
      let c : Call := { s := sp, src, dl, ir, tok }
      let fa := (D.fa src ir (dsnapVal (v.deferred ir))).toVal
      let mon : IO :=
        match sp.rs with
        -- `case None => F.start(fa).flatMap { fib => ... }` (`SV:290-292`)
        | .none =>
          match D.ofVal? fa with
          | some dfa => .flatMap (.start (dIO dfa)) (SLam.monNone c.toVal).fn
          | none => .error illErr
        -- `case Some(restart) => F.deferred[Outcome].flatMap { resultR => ... }` (`SV:187-188`)
        | _ => .flatMap newDeferredIO (SLam.rRes c.toVal).fn
      prog (.flatMap mon (SLam.kFib c.toVal).fn)
    | _, _ => illTyped
  | .kFib c =>
    match Call.ofVal? c with
    | some k => prog (.flatMap (addIO k.s k.tok arg) (SLam.kAdd c arg).fn)
    | none => illTyped
  | .kAdd c fib =>
    match Call.ofVal? c, arg with
    | some k, .bool ok =>
      prog (.flatMap (.delay (.rt (.deferredComplete k.ir (.bool ok)))) (SLam.kCmp c fib ok).fn)
    | _, _ => illTyped
  | .kCmp c fib ok =>
    match Call.ofVal? c with
    | some k => prog (.flatMap (.flatMap (getIO k.dl) (SLam.ifDone c).fn) (SLam.kLast fib ok).fn)
    | none => illTyped
  | .ifDone c =>
    match Call.ofVal? c, arg with
    | some k, .bool true => prog (removeIO k.s k.tok)
    | some _, .bool false => prog (.pure .unit)
    | _, _ => illTyped
  | .kLast fib ok => prog (.map (if ok then .pure .unit else .error iseErr) (SLam.constV fib).fn)
  | .constV x => ret x
  | .ifIns src =>
    match arg with
    | .bool true => prog (ioOf src)
    | .bool false => prog (.flatMap .canceled (SLam.constErr aeCancelErr).fn)
    | _ => illTyped
  | .constErr e => prog (.error e)
  -- `F.start(fib.join.guarantee(fin)).as(fib)`
  | .monNone c =>
    match arg with
    | .fiber t =>
      prog (.map (.start (Bracket.guaranteeIO (.ext (D.join t (snapVal (v.outcome t))).toVal)
        (.ext (D.fin c).toVal))) (SLam.constV arg).fn)
    | _ => illTyped
  | .putThunk m tok fib =>
    match entriesOf (v.refs.getD m .unit) with
    | some es => { effects := [.writeRef m (listV (putEntry tok fib es))], out := .ret .unit }
    | none => illTyped
  | .thenNotDone d => prog (.map (getIO d) SLam.notK.fn)
  | .notK =>
    match arg with
    | .bool b => ret (.bool !b)
    | _ => illTyped
  | .removeThunk m tok vr =>
    match entriesOf (v.refs.getD m .unit) with
    | some es =>
      if vr == 10 then ret .unit
      else { effects := [.writeRef m (listV (removeEntry tok es))], out := .ret .unit }
    | none => illTyped
  | .updRemove m tok vr =>
    match v.refs.getD m .unit with
    | .none => { effects := [.writeRef m .none], out := .ret .unit }
    | x =>
      match unlistV x with
      | some es =>
        if vr == 10 then { effects := [.writeRef m x], out := .ret .unit }
        else { effects := [.writeRef m (listV (removeEntry tok es))], out := .ret .unit }
      | none => illTyped
  | .modAdd m tok fib vr =>
    match v.refs.getD m .unit with
    | .none => { effects := [.writeRef m .none], out := .ret (.bool (vr == 9)) }
    | x =>
      match unlistV x with
      | some es => { effects := [.writeRef m (listV (putEntry tok fib es))], out := .ret (.bool true) }
      | none => illTyped
  | .thenCleanup c =>
    match Call.ofVal? c with
    | some k => prog (removeIO k.s k.tok)
    | none => illTyped
  -- the restart branch (`SV:187-288`)
  | .rRes c =>
    match arg with
    | .deferred res => prog (.flatMap (newRefIO (.bool false)) (SLam.rCan c res).fn)
    | _ => illTyped
  | .rCan c res =>
    match arg with
    | .ref can => prog (.flatMap newDeferredIO (SLam.rFirst c res can).fn)
    | _ => illTyped
  | .rFirst c res can =>
    match arg with
    | .deferred first => prog (.flatMap (newRefIO (.deferred first)) (SLam.rCur c res can first).fn)
    | _ => illTyped
  -- `action(firstCurrent).as(new Fiber { ... })`
  | .rCur c res can first =>
    match arg, Call.ofVal? c with
    | .ref cur, some k =>
      let r : RCtx := { c := k, res, can, cur }
      prog (.map (actionIO r first) (SLam.constV (wrapVal r)).fn)
    | _, _ => illTyped
  -- `started flatMap { f => current.complete(f).void }`, `started = F start { fa guaranteeCase {...} }`
  | .actBody r current =>
    match RCtx.ofVal? r with
    | some rc =>
      let fa := (D.fa rc.c.src rc.c.ir (dsnapVal none)).toVal
      prog (.flatMap (.start (Bracket.guaranteeCaseIO (.ext fa) (SLam.gcFin r).id)) (SLam.actK current).fn)
    | none => illTyped
  | .actK current => prog (completeVoidIO current arg)
  | .gcFin r => prog (.flatMap newDeferredIO (SLam.gcNew r arg).fn)
  | .gcNew r oc =>
    match arg, RCtx.ofVal? r with
    | .deferred nc, some rc => prog (.flatMap (setIO rc.cur (.deferred nc)) (SLam.thenCan r oc nc).fn)
    | _, _ => illTyped
  | .thenCan r oc nc =>
    match RCtx.ofVal? r with
    | some rc => prog (.flatMap (getIO rc.can) (SLam.canSel r oc nc).fn)
    | none => illTyped
  | .canSel r oc nc =>
    match arg, RCtx.ofVal? r with
    | .bool canceled, some rc => prog (.flatMap (getIO rc.c.s.d) (SLam.doneSel r oc nc canceled).fn)
    | _, _ => illTyped
  -- `if (!canceled && !done && restart(oc)) action(newCurrent) else newCurrent.complete(null) *> ...`
  | .doneSel r oc nc canceled =>
    match arg, RCtx.ofVal? r with
    | .bool done, some rc =>
      let notRestart : UserResult :=
        prog (.flatMap (.delay (.rt (.deferredComplete nc .none))) (SLam.thenFinRes r oc).fn)
      let flags := if rc.c.s.v == 11 then true else !canceled && !done
      if !flags then notRestart
      else
        match rc.c.s.rs with
        | .some (.fn k) =>
          let u := uc k oc v
          match u.out with
          | .ret (.bool true) => { effects := u.effects, out := .prog (actionIO rc nc) }
          | .ret (.bool false) => { notRestart with effects := u.effects }
          | .throw e => { effects := u.effects, out := .throw e }
          | _ => illTyped
        | _ => illTyped
    | _, _ => illTyped
  | .thenFinRes r oc =>
    match RCtx.ofVal? r with
    | some rc => prog (finResIO rc oc)
    | none => illTyped
  | .wrap r =>
    match arg, RCtx.ofVal? r with
    | .nat 0, some _ => prog (wCancelIO r)
    -- `def join = resultR.get`
    | .nat 1, some rc => prog (IO.deferredGetOf rc.res (v.deferred rc.res))
    | _, _ => illTyped
  -- `(canceledR.set(true) *> delegateF) flatMap { ... }`
  | .wBody r =>
    match RCtx.ofVal? r with
    | some rc =>
      prog (.flatMap (.flatMap (setIO rc.can (.bool true)) (SLam.thenDelegate r).fn) (SLam.wSel1 r).fn)
    | none => illTyped
  | .thenDelegate r =>
    match RCtx.ofVal? r with
    | some rc => prog (delegateIO rc)
    | none => illTyped
  | .getDef =>
    match arg with
    | .deferred x => prog (IO.deferredGetOf x (v.deferred x))
    | _ => illTyped
  | .wSel1 r =>
    match arg, RCtx.ofVal? r with
    | .none, some rc => prog (voidIO (IO.deferredGetOf rc.res (v.deferred rc.res)))
    -- `(fiber.cancel *> fiber.join) flatMap { ... }`: both built now
    | .fiber t, some _ =>
      let snap := snapVal (v.outcome t)
      prog (.flatMap (.flatMap (IO.cancelOf t (v.outcome t)) (SLam.thenD (D.join t snap).toVal).fn)
        (SLam.wSel2 r arg).fn)
    | _, _ => illTyped
  | .wSel2 r fiber =>
    match arg, RCtx.ofVal? r with
    | .ocCanceled, some rc => prog (.flatMap (delegateIO rc) (SLam.wSel3 r fiber).fn)
    | _, some rc => prog (voidIO (IO.deferredGetOf rc.res (v.deferred rc.res)))
    | _, none => illTyped
  | .wSel3 r fiber =>
    match arg, RCtx.ofVal? r with
    | .none, some rc => prog (voidIO (IO.deferredGetOf rc.res (v.deferred rc.res)))
    | fiber2, some rc =>
      let cleanup := finResIO rc .ocCanceled
      if fiber2 == fiber then prog cleanup
      else prog (.flatMap cleanup (SLam.constErr aeFiberErr).fn)
    | _, none => illTyped
  | .thenRaise e => prog (.error e)
  | .obj s =>
    match Sup.ofVal? s with
    | some sp => prog (superviseIO sp arg)
    | none => illTyped
  | .twice s src =>
    match Sup.ofVal? s with
    | some sp => prog (.uncancelable (SLam.supBody sp.toVal src).fn)
    | none => illTyped

/-- The closures of this mirror (`WellFormed`: user code may name them; their captured handles
must be available). -/
def isLib (id : Nat) : Bool := (SLam.ofId? id).isSome

/-- The dispatcher: this mirror, `Bracket`, `Race`, `Timeout`, else `u`. `ioOf` builds the program
of a `supervise` source; `ho` is the map order. -/
def dispatch (ho : List Val → List Val) (ioOf : Val → IO) (u : UserEnv) : Nat → Val → View → UserResult :=
  go 32
where
  go : Nat → Nat → Val → View → UserResult
  | 0, id, arg, v => u.callV id arg v
  | fuel + 1, id, arg, v =>
    match SLam.ofId? id with
    | some l => call (go fuel) ioOf ho l arg v
    | none =>
      match Bracket.BLam.ofId? id with
      | some l => Bracket.call (go fuel) (srcOf ioOf) l arg v
      | none =>
        match Race.ofId? id with
        | some l => Race.call (srcOf ioOf) l arg v
        | none =>
          match (if isLibId id then (cloOfId id).bind ofCloVal else none) with
          | some (k, tag, fs) =>
            if k == Timeout.ns then
              match Timeout.TLam.ofFields tag fs with
              | some l => Timeout.call (srcOf ioOf) l arg v
              | none => u.callV id arg v
            else u.callV id arg v
          | none => u.callV id arg v

/-- The environment with this mirror. -/
def env (ho : List Val → List Val) (ioOf : Val → IO) (u : UserEnv) : UserEnv where
  call id arg refs := dispatch ho ioOf u id arg { refs }
  callV := dispatch ho ioOf u

end CatsEffectInLean.Std.Supervisor

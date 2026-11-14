import CatsEffectInLean.Model.Bracket
import CatsEffectInLean.Model.Race
import CatsEffectInLean.Model.Timeout

/-!
# `parTraverseN` (mirror; Phase 6, batch 6.3)

`IO.parTraverseN(n)(ta)(f)` (`core/shared/src/main/scala/cats/effect/IO.scala:1593-1594`) is
`_asyncForIO.parTraverseN(n)(ta)(f)`. `IOAsync` does not override it, so the kernel default
`GenConcurrent#parTraverseN` (`kernel/shared/src/main/scala/cats/effect/kernel/GenConcurrent.scala:145-251`,
`K/GC` below) runs with the `IO` operations. There is no twin: one body. Paths at v3.7.1.

`T = List`. The helpers it calls:

* `MiniSemaphore` (`kernel/.../MiniSemaphore.scala:41-88`, `K/MS`): `F.ref(State(Queue(), n)).map(...)`;
  `acquire` (`:59-72`), `release` (`:74-83`, `state.flatModify`).
* `Ref` (`IO.ref` = `IO(Ref.unsafe(a))`, `IO.scala:1822`; the JVM `SyncRef`,
  `kernel/jvm-native/.../SyncRef.scala`): `get` = `F.delay(ar.get)` (`:30`), `update` = `F.delay(spin)`
  (`:65-73`), `modify` = `F.delay(spin)` (`:86-95`); `flatModify(f)` =
  `F.uncancelable(_ => F.flatten(modify(f)))` (`kernel/.../Ref.scala:123-124`). One model step is
  atomic, so the CAS loop succeeds at once.
* `Deferred` (`IO.deferred` = `IO(new IODeferred)`, `IO.scala:1824`): `get` = `cell.get()`
  (`IODeferred.scala:71`, `IO.deferredGetOf`), `complete` (`:62-69`, `RtFn.deferredComplete`),
  `tryGet` = `IO { ... }` (`:73-79`).
* cats-core 2.13.0: `List.traverse` with a `StackSafeMonad` (`IOAsync` is one, `IO.scala:1996`) is
  `map(traverseDirectly(fa)(f))(_.toList)` (`cats/instances/list.scala:121-125`), and
  `traverseDirectly` = `foldLeft(pure(Chain.empty)) { (accG, a) => map2(accG, f(a))(_ :+ _) }`
  (`cats/Traverse.scala:289-297`): `f(a)` is called while the fold runs (strict). `map2` =
  `flatMap(fa)(a => map(fb)(b => f(a, b)))` (`cats/FlatMap.scala:113-114`). `List.traverseVoid`
  with a `StackSafeMonad` = `void(foldLeft(f(first))(productR))` (`cats/Traverse.scala:299-308`);
  with `ParallelF` (`parTraverse_`, `cats/Parallel.scala:283-294`) the balanced tree `runHalf`
  (`cats/instances/list.scala:137-174`): `map2Eval` (`cats/Apply.scala:222-223`) = `map2` =
  `ParallelF(F.both(a, b).map(...))` (`kernel/.../instances/GenSpawnInstances.scala:49-54`), a leaf
  is `G.void(f(a))` = `map(_ => ())`, the empty list is `G.unit` = `F.unit`.
  `ifM(t, f)` = `flatMap(if (_) t else f)` (`cats/FlatMap.scala:142-143`, by-name).
* `*>` = `IO#productR` (strict `that`), `<*` = `IO#productL` = `flatMap(a => that.as(a))`,
  `>>` = `flatMap(_ => fb)` (by name), `guaranteeCase` = `IO#guaranteeCase` (`Model/Bracket.lean`),
  `void` = `map(_ => ())`, `voidError` = `handleError(_ => ())` (`IO.scala:977-980`), `start` =
  `Start`, `embed(x)` = `fold(x, raiseError, identity)`, `F.never` = `IO.never` (`Model/Timeout.lean`),
  `F.both` = `Model/Race.lean`.

## Encoding

* Closures `PT` (namespace `ns = 41`). User function `f` is an even id; the mirror calls it via
  `uc` (`uc f a view`).
* An `IO` held as a value (the traverse result is a `List[F[B]]`; `modify` returns an `F[...]`)
  is a descriptor `Val` (`Desc`); the closure that consumes it rebuilds the term.
* `Set[(Fiber, Deferred)]`: a list in insertion order. Scala's `Set1`..`Set4` keep insertion order
  under `+` and `-`; a fifth element makes a `HashSet` (identity-hash order), which the model does
  not mirror: it stops with the fatal error code `setLimitCode` (so inputs of length ≤ 4).
* `Chain` = list. A list value is `Codec.listV`.
* The source of an `IO` in a `guaranteeCase` or `both` is a source code (`ioOf`).
-/

namespace CatsEffectInLean.Model.ParTraverse

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of these closures (batch 6.3: 41..49). -/
def ns : Nat := 41

/-- The model limit: a supervision set of more than 4 elements. -/
def setLimitCode : Nat := 900041

/-- Error codes: an ill-typed argument (impossible in Scala). -/
def illCode : Nat := 999999

/-- The closures. Fields: `p` preempt deferred, `s` supervision ref, `q` semaphore state ref,
`f` user function, `a` element, `r` result deferred, `t` fiber, `w` waiter deferred, `m pp` a
poll, `c` a cause (`.none` = `None`, `.some (.err e)`), `snap` a cell snapshot. -/
inductive PT where
  /-- `IO(new IODeferred)` thunk. -/
  | newDeferred
  /-- `IO(Ref.unsafe(x))` thunk. -/
  | newRef (x : Val)
  /-- `preempt => F.ref(Set()).flatMap(...)` (`K/GC:151-152`). -/
  | k1 (n : Nat) (as : Val) (f : Nat)
  /-- `supervision => MiniSemaphore[F](n).flatMap(...)` (`K/GC:152`, `:170`). -/
  | k2 (n : Nat) (as : Val) (f p : Nat)
  /-- `state => new MiniSemaphore` (`K/MS:56`): the semaphore is its state ref. -/
  | semK
  /-- `sem => { val results = ta traverse {...}; results.flatMap(_.sequence).onCancel(...) }`. -/
  | k3 (as : Val) (f p s : Nat)
  /-- `map2(accG, f(a))(_ :+ _)`: `acc => map(f(a))(b => acc :+ b)` (element `a` of the traverse). -/
  | travM2 (f p s q : Nat) (a : Val)
  /-- `b => acc :+ b`. -/
  | snoc (acc : Val)
  /-- `_.toList` (identity on the list encoding). -/
  | toList
  /-- `tryGet` thunk of deferred `d` (`IODeferred.scala:73-79`). -/
  | tryGet (d : Nat)
  /-- `preempt.tryGet flatMap { case ... }` of the traverse lambda (`K/GC:172-176`). -/
  | elemSel (f p s q : Nat) (a : Val)
  /-- `poll => F.deferred[...].flatMap(result => ...)` (`K/GC:177`). -/
  | uncK (f p s q : Nat) (a : Val)
  /-- `result => { val action = ...; action flatMap {...} }` (`K/GC:178-232`). -/
  | resK (f p s q : Nat) (a : Val) (m pp : Nat)
  /-- `_ => that` of `poll(sem.acquire) *> (...).start` (`K/GC:182`). -/
  | thenStart (f p s q : Nat) (a : Val) (r : Nat)
  /-- `_ => f(a)` of `F.unit >> f(a)` (`K/GC:182`). -/
  | callF (f : Nat) (a : Val)
  /-- The `guaranteeCase` finalizer `oc => completion *> sem.release` (`K/GC:183-215`). -/
  | finK (p s q r : Nat)
  /-- `{ case Some(Some(e)) => ...; case Some(None) => ...; case None => result.complete(oc) }`. -/
  | compSucc (r : Nat) (oc : Val)
  /-- `ifM(result.complete(oc) <* cancelAll(Some(e)), false.pure)` (`K/GC:196-200`). -/
  | ifErr (s r : Nat) (e : Err)
  /-- `ifM(result.complete(oc) <* cancelAll(None).start, false.pure)` (`K/GC:203-209`). -/
  | ifCan (s r : Nat)
  /-- `a => that.as(a)` of `<*` with `that = cancelAll(c)` (`IO#productL`). -/
  | plCancelAll (s : Nat) (c : Val)
  /-- `a => that.as(a)` of `<*` with `that = cancelAll(None).start`. -/
  | plStartCancelAll (s : Nat)
  /-- `_ => b` of `as`. -/
  | asK (b : Val)
  /-- `_ => sem.release` of `completion *> sem.release` (`K/GC:214`). -/
  | thenRelease (q : Nat)
  /-- `_ => ()` of `void`. -/
  | voidK
  /-- `t => IO.pure(())` of `voidError` (`IO.scala:977-980`, `532-533`). -/
  | unitH
  /-- `fiber => supervision.update(_ + ((fiber, result))) *> preempt.tryGet flatMap {...}` (`K/GC:220-222`). -/
  | fibK (p s r : Nat)
  /-- `update(_ + ((fiber, result)))` thunk (`SyncRef.update`). -/
  | supAdd (s t r : Nat)
  /-- `update(_ - ((fiber, result)))` thunk. -/
  | supRemove (s t r : Nat)
  /-- `_ => that` of `*>` with `that = preempt.tryGet flatMap {...}` (`K/GC:222`). -/
  | thenAfter (p s t r : Nat)
  /-- `{ case Some(Some(e)) => fiber.cancel.as(...); ...; case None => F.pure(...) }` (`K/GC:222-232`). -/
  | selAfter (s t r : Nat)
  /-- `{ case Canceled() => F.unit; case _ => supervision.update(_ - ...) }` (`K/GC:228-231`). -/
  | finRes (s t r : Nat)
  /-- `_.embed(F.canceled *> F.never)` (`K/GC:227`). -/
  | embedK
  /-- `_ => F.never` of `F.canceled *> F.never`. -/
  | constNever
  /-- `_.sequence` (`K/GC:237`): traverse with `identity` over the descriptors. -/
  | seqK
  /-- `acc => map(io)(b => acc :+ b)` of `map2` in `_.sequence`; `d` the descriptor of `io`. -/
  | seqM2 (d : Val)
  /-- `SyncRef.get` thunk. -/
  | refGet (s : Nat)
  /-- `states => states.toList parTraverse_ {...}` of `cancelAll` (`K/GC:155-164`). -/
  | caK (c : Val)
  /-- `b => if (b) fiber.cancel else F.unit` of `result.complete(causeOC).ifM(...)` (`K/GC:162`). -/
  | ifCancel (t : Nat)
  /-- `b => if (b) cancelAll(None) else F.unit` of `cancelAllAndJoin` (`K/GC:166-167`). -/
  | ifCA (s : Nat)
  /-- `_ => that` of `*>` with `that = supervision.get.flatMap(...)` (`K/GC:167-168`). -/
  | thenJoinAll (s : Nat)
  /-- `states => states.toList.traverse_ { case (fiber, _) => fiber.join.void }` (`K/GC:168`). -/
  | joinAllK
  /-- `_ => fiber.join.void` (a `productR` step; `snap` = what `fiber.join` read). -/
  | constJoin (t : Nat) (snap : Val)
  /-- `poll => F.deferred[Unit].flatMap(wait => ...)` of `acquire` (`K/MS:60`). -/
  | acqBody (q : Nat)
  /-- `wait => { val cleanup = ...; state.modify {...}.flatten }` (`K/MS:61-71`). -/
  | acqWait (q m pp : Nat)
  /-- The `modify` thunk of `acquire` (`K/MS:64-69`). -/
  | modAcq (q w m pp : Nat)
  /-- `fa => fa` of `flatten` (`cats/FlatMap.scala:58-59`); the argument is a descriptor. -/
  | flattenK
  /-- `won => if (won) F.unit else release` (`K/MS:62`, `:77-78`). -/
  | wonK (q : Nat)
  /-- `_ => F.flatten(modify(f))` of `flatModify` in `release` (`Ref.scala:123-124`). -/
  | relBody (q : Nat)
  /-- The `modify` thunk of `release` (`K/MS:75-82`). -/
  | modRel (q : Nat)
  deriving DecidableEq, Repr

/-- Descriptors of `IO` values held in values. -/
def dRaise (e : Err) : Val := cloVal ns 90 [.err e]
def dCanceledNever : Val := cloVal ns 91 []
/-- `result.get.flatMap(_.embed(...)).guaranteeCase {...}` (`K/GC:225-231`); `snap` = what
`result.get` read. -/
def dResultGet (s t r : Nat) (snap : Val) : Val := cloVal ns 92 [.ref s, .fiber t, .deferred r, snap]
def dUnit : Val := cloVal ns 93 []
/-- `poll(wait.get).onCancel(cleanup)` (`K/MS:66`). -/
def dAcqWait (q w m pp : Nat) : Val := cloVal ns 94 [.ref q, .deferred w, .poll m pp]
/-- `waiting.head.complete(()).flatMap { granted => ... }` (`K/MS:78`). -/
def dGrant (q h : Nat) : Val := cloVal ns 95 [.ref q, .deferred h]

/-- Source codes (`ioOf`). -/
def srcAction (f : Nat) (a : Val) : Val := cloVal ns 80 [.nat f, a]
def srcResGet (r : Nat) (snap : Val) : Val := cloVal ns 81 [.deferred r, snap]
/-- A node of the `parTraverse_` tree of `cancelAll`: the states `xs` and the cause. -/
def srcPar (xs c : Val) : Val := cloVal ns 82 [xs, c]

def PT.toVal : PT → Val
  | .newDeferred => cloVal ns 0 []
  | .newRef x => cloVal ns 1 [x]
  | .k1 n as f => cloVal ns 2 [.nat n, as, .nat f]
  | .k2 n as f p => cloVal ns 3 [.nat n, as, .nat f, .deferred p]
  | .semK => cloVal ns 4 []
  | .k3 as f p s => cloVal ns 5 [as, .nat f, .deferred p, .ref s]
  | .travM2 f p s q a => cloVal ns 6 [.nat f, .deferred p, .ref s, .ref q, a]
  | .snoc acc => cloVal ns 7 [acc]
  | .toList => cloVal ns 8 []
  | .tryGet d => cloVal ns 9 [.deferred d]
  | .elemSel f p s q a => cloVal ns 10 [.nat f, .deferred p, .ref s, .ref q, a]
  | .uncK f p s q a => cloVal ns 11 [.nat f, .deferred p, .ref s, .ref q, a]
  | .resK f p s q a m pp => cloVal ns 12 [.nat f, .deferred p, .ref s, .ref q, a, .poll m pp]
  | .thenStart f p s q a r => cloVal ns 13 [.nat f, .deferred p, .ref s, .ref q, a, .deferred r]
  | .callF f a => cloVal ns 14 [.nat f, a]
  | .finK p s q r => cloVal ns 15 [.deferred p, .ref s, .ref q, .deferred r]
  | .compSucc r oc => cloVal ns 16 [.deferred r, oc]
  | .ifErr s r e => cloVal ns 17 [.ref s, .deferred r, .err e]
  | .ifCan s r => cloVal ns 18 [.ref s, .deferred r]
  | .plCancelAll s c => cloVal ns 19 [.ref s, c]
  | .plStartCancelAll s => cloVal ns 20 [.ref s]
  | .asK b => cloVal ns 21 [b]
  | .thenRelease q => cloVal ns 22 [.ref q]
  | .voidK => cloVal ns 23 []
  | .unitH => cloVal ns 24 []
  | .fibK p s r => cloVal ns 25 [.deferred p, .ref s, .deferred r]
  | .supAdd s t r => cloVal ns 26 [.ref s, .fiber t, .deferred r]
  | .supRemove s t r => cloVal ns 27 [.ref s, .fiber t, .deferred r]
  | .thenAfter p s t r => cloVal ns 28 [.deferred p, .ref s, .fiber t, .deferred r]
  | .selAfter s t r => cloVal ns 29 [.ref s, .fiber t, .deferred r]
  | .finRes s t r => cloVal ns 30 [.ref s, .fiber t, .deferred r]
  | .embedK => cloVal ns 31 []
  | .constNever => cloVal ns 32 []
  | .seqK => cloVal ns 33 []
  | .seqM2 d => cloVal ns 34 [d]
  | .refGet s => cloVal ns 35 [.ref s]
  | .caK c => cloVal ns 36 [c]
  | .ifCancel t => cloVal ns 37 [.fiber t]
  | .ifCA s => cloVal ns 38 [.ref s]
  | .thenJoinAll s => cloVal ns 39 [.ref s]
  | .joinAllK => cloVal ns 40 []
  | .constJoin t snap => cloVal ns 41 [.fiber t, snap]
  | .acqBody q => cloVal ns 42 [.ref q]
  | .acqWait q m pp => cloVal ns 43 [.ref q, .poll m pp]
  | .modAcq q w m pp => cloVal ns 44 [.ref q, .deferred w, .poll m pp]
  | .flattenK => cloVal ns 45 []
  | .wonK q => cloVal ns 46 [.ref q]
  | .relBody q => cloVal ns 47 [.ref q]
  | .modRel q => cloVal ns 48 [.ref q]

def PT.ofFields : Nat → List Val → Option PT
  | 0, [] => some .newDeferred
  | 1, [x] => some (.newRef x)
  | 2, [.nat n, as, .nat f] => some (.k1 n as f)
  | 3, [.nat n, as, .nat f, .deferred p] => some (.k2 n as f p)
  | 4, [] => some .semK
  | 5, [as, .nat f, .deferred p, .ref s] => some (.k3 as f p s)
  | 6, [.nat f, .deferred p, .ref s, .ref q, a] => some (.travM2 f p s q a)
  | 7, [acc] => some (.snoc acc)
  | 8, [] => some .toList
  | 9, [.deferred d] => some (.tryGet d)
  | 10, [.nat f, .deferred p, .ref s, .ref q, a] => some (.elemSel f p s q a)
  | 11, [.nat f, .deferred p, .ref s, .ref q, a] => some (.uncK f p s q a)
  | 12, [.nat f, .deferred p, .ref s, .ref q, a, .poll m pp] => some (.resK f p s q a m pp)
  | 13, [.nat f, .deferred p, .ref s, .ref q, a, .deferred r] => some (.thenStart f p s q a r)
  | 14, [.nat f, a] => some (.callF f a)
  | 15, [.deferred p, .ref s, .ref q, .deferred r] => some (.finK p s q r)
  | 16, [.deferred r, oc] => some (.compSucc r oc)
  | 17, [.ref s, .deferred r, .err e] => some (.ifErr s r e)
  | 18, [.ref s, .deferred r] => some (.ifCan s r)
  | 19, [.ref s, c] => some (.plCancelAll s c)
  | 20, [.ref s] => some (.plStartCancelAll s)
  | 21, [b] => some (.asK b)
  | 22, [.ref q] => some (.thenRelease q)
  | 23, [] => some .voidK
  | 24, [] => some .unitH
  | 25, [.deferred p, .ref s, .deferred r] => some (.fibK p s r)
  | 26, [.ref s, .fiber t, .deferred r] => some (.supAdd s t r)
  | 27, [.ref s, .fiber t, .deferred r] => some (.supRemove s t r)
  | 28, [.deferred p, .ref s, .fiber t, .deferred r] => some (.thenAfter p s t r)
  | 29, [.ref s, .fiber t, .deferred r] => some (.selAfter s t r)
  | 30, [.ref s, .fiber t, .deferred r] => some (.finRes s t r)
  | 31, [] => some .embedK
  | 32, [] => some .constNever
  | 33, [] => some .seqK
  | 34, [d] => some (.seqM2 d)
  | 35, [.ref s] => some (.refGet s)
  | 36, [c] => some (.caK c)
  | 37, [.fiber t] => some (.ifCancel t)
  | 38, [.ref s] => some (.ifCA s)
  | 39, [.ref s] => some (.thenJoinAll s)
  | 40, [] => some .joinAllK
  | 41, [.fiber t, snap] => some (.constJoin t snap)
  | 42, [.ref q] => some (.acqBody q)
  | 43, [.ref q, .poll m pp] => some (.acqWait q m pp)
  | 44, [.ref q, .deferred w, .poll m pp] => some (.modAcq q w m pp)
  | 45, [] => some .flattenK
  | 46, [.ref q] => some (.wonK q)
  | 47, [.ref q] => some (.relBody q)
  | 48, [.ref q] => some (.modRel q)
  | _, _ => none

def PT.id (l : PT) : Nat := 2 * valToNat l.toVal + 1
def PT.fn (l : PT) : Fn := .user l.id

def PT.ofId? (id : Nat) : Option PT :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then PT.ofFields tag fs else none
    | none => none
  else none

/-! ## Terms -/

/-- `IO.parTraverseN(n)(as)(f)` (`IO.scala:1593-1594`, `K/GC:145-251`); `require(n >= 1)` holds
(the caller checks it). -/
def parTraverseNIO (n : Nat) (as : List Val) (f : Nat) : IO :=
  .flatMap (.delay PT.newDeferred.fn) (PT.k1 n (listV as) f).fn

/-- `deferred.complete(x)` (`IODeferred.scala:62-69`). -/
def completeIO (d : Nat) (x : Val) : IO := .delay (.rt (.deferredComplete d x))

/-- `preempt.tryGet` (`IODeferred.scala:73-79`). -/
def tryGetIO (d : Nat) : IO := .delay (PT.tryGet d).fn

/-- `F.canceled *> F.never` (strict `that`). -/
def canceledNever : IO := .flatMap .canceled PT.constNever.fn

/-- `sem.acquire` (`K/MS:59-72`). -/
def acquireIO (q : Nat) : IO := .uncancelable (PT.acqBody q).fn

/-- `sem.release` (`K/MS:74-83`): `state.flatModify {...}` = `F.uncancelable(_ => F.flatten(modify(...)))`. -/
def releaseIO (q : Nat) : IO := .uncancelable (PT.relBody q).fn

/-- `cleanup` / `granted` continuation: `d.complete(()).flatMap { won => if (won) F.unit else release }`. -/
def completeThenRelease (q d : Nat) : IO := .flatMap (completeIO d .unit) (PT.wonK q).fn

/-- `cancelAll(cause)` (`K/GC:155-164`). -/
def cancelAllIO (s : Nat) (c : Val) : IO := .flatMap (.delay (PT.refGet s).fn) (PT.caK c).fn

/-- `cancelAllAndJoin` (`K/GC:166-168`). -/
def cancelAllAndJoinIO (p s : Nat) : IO :=
  .flatMap (.flatMap (completeIO p .none) (PT.ifCA s).fn) (PT.thenJoinAll s).fn

/-- The cause outcome of `cancelAll` (`K/GC:157-160`). -/
def causeOC : Val → Val
  | .some (.err e) => .ocErrored e
  | _ => .ocCanceled

/-- The traverse lambda `a => preempt.tryGet flatMap {...}` (`K/GC:172`). -/
def elemIO (f p s q : Nat) (a : Val) : IO := .flatMap (tryGetIO p) (PT.elemSel f p s q a).fn

/-- `ta traverse elem` (`cats/instances/list.scala:121-125`, `cats/Traverse.scala:289-297`). -/
def traverseIO (f p s q : Nat) (as : List Val) : IO :=
  match as with
  | [] => .pure (listV [])
  | _ => .map (as.foldl (fun accG a => .flatMap accG (PT.travM2 f p s q a).fn) (.pure (listV []))) PT.toList.fn

/-- `ParallelF` leaf of `parTraverse_` in `cancelAll`: `G.void(f(state))` with
`f((fiber, result)) = result.complete(causeOC).ifM(fiber.cancel, F.unit)`. -/
def parLeaf (c : Val) : Val → IO
  | .pair (.fiber t) (.deferred r) =>
    .map (.flatMap (completeIO r (causeOC c)) (PT.ifCancel t).fn) PT.voidK.fn
  | _ => .error { code := illCode, kind := .fatal }

/-- `runHalf(size, fa)` (`cats/instances/list.scala:143-171`) over the states `xs` (size ≥ 1).
A node is `ParallelF(F.both(left, right).map { case (a, b) => () })`; the halves are source
codes so that `Race.both` can rebuild them. -/
def runHalf (c : Val) (xs : List Val) : IO :=
  if xs.length > 1 then
    let l := xs.length / 2
    .map (Race.bothIO (srcPar (listV (xs.take l)) c) (srcPar (listV (xs.drop l)) c)) PT.voidK.fn
  else
    match xs with
    | [x] => parLeaf c x
    | _ => .error { code := illCode, kind := .fatal }

/-- The `IO` of a descriptor. -/
def descIO (d : Val) : IO :=
  match ofCloVal d with
  | some (41, 90, [.err e]) => .error e
  | some (41, 91, []) => canceledNever
  -- `result.get.flatMap(_.embed(...)).guaranteeCase { case Canceled() => F.unit; case _ => ... }`
  | some (41, 92, [.ref s, .fiber t, .deferred r, snap]) =>
    Bracket.guaranteeCaseIO (.ext (srcResGet r snap)) (PT.finRes s t r).id
  | some (41, 93, []) => .pure .unit
  -- `poll(wait.get).onCancel(cleanup)`: `wait` was just made and enqueued, so `get` read `initial`
  | some (41, 94, [.ref q, .deferred w, .poll m pp]) =>
    .onCancel (IO.applyPoll (IO.deferredGetOf w none) m pp) (completeThenRelease q w)
  | some (41, 95, [.ref q, .deferred h]) => completeThenRelease q h
  | _ => .error { code := illCode, kind := .fatal }

/-- The external sources of the `guaranteeCase` and `both` closures. -/
def ioOf : Val → IO
  | c =>
    match ofCloVal c with
    -- `F.unit >> f(a)` (`K/GC:182`)
    | some (41, 80, [.nat f, a]) => .flatMap (.pure .unit) (PT.callF f a).fn
    -- `result.get.flatMap(_.embed(F.canceled *> F.never))` (`K/GC:226-227`)
    | some (41, 81, [.deferred r, snap]) =>
      .flatMap (IO.deferredGetOf r (match snap with | .some x => some x | _ => none)) PT.embedK.fn
    | some (41, 82, [xs, cause]) =>
      match unlistV xs with
      | some l => runHalf cause l
      | none => .error { code := illCode, kind := .fatal }
    | _ => .error { code := illCode, kind := .fatal }

/-! ## The closures -/

private def ret (v : Val) : UserResult := { out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
def illTyped : UserResult := { out := .throw { code := illCode, kind := .fatal } }

/-- The list of a list value. -/
def listOf (v : Val) : List Val := (unlistV v).getD []

/-- `Set + elem` for `Set1`..`Set4` (insertion order); a fifth element: the model limit. -/
def setAdd (xs : List Val) (x : Val) : Option (List Val) :=
  if xs.contains x then some xs else if xs.length ≥ 4 then none else some (xs ++ [x])

/-- `Set - elem`. -/
def setRemove (xs : List Val) (x : Val) : List Val := xs.filter (· != x)

/-- The state of the semaphore: `(waiting, permits)`. -/
def semState (v : View) (q : Nat) : Option (List Val × Nat) :=
  match v.refs[q]? with
  | some (.pair w (.nat k)) => (unlistV w).map (·, k)
  | _ => none

/-- Run closure `l`. `uc` calls the user function `f`. -/
def call (uc : Nat → Val → View → UserResult) (l : PT) (arg : Val) (v : View) : UserResult :=
  match l with
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred v.deferreds.length) }
  | .newRef x => { effects := [.allocRef x], out := .ret (.ref v.refs.length) }
  | .k1 n as f =>
    match arg with
    -- `F.ref(Set()).flatMap(supervision => ...)`
    | .deferred p => prog (.flatMap (.delay (PT.newRef (listV [])).fn) (PT.k2 n as f p).fn)
    | _ => illTyped
  | .k2 n as f p =>
    match arg with
    -- `MiniSemaphore[F](n) flatMap { sem => ... }`; `F.ref(State(Queue(), n)).map(state => ...)`
    | .ref s =>
      prog (.flatMap (.map (.delay (PT.newRef (.pair (listV []) (.nat n))).fn) PT.semK.fn) (PT.k3 as f p s).fn)
    | _ => illTyped
  | .semK => ret arg
  | .k3 as f p s =>
    match arg with
    -- `results.flatMap(_.sequence).onCancel(cancelAllAndJoin)` (`K/GC:237`)
    | .ref q =>
      prog (.onCancel (.flatMap (traverseIO f p s q (listOf as)) PT.seqK.fn) (cancelAllAndJoinIO p s))
    | _ => illTyped
  | .travM2 f p s q a => prog (.map (elemIO f p s q a) (PT.snoc arg).fn)
  | .snoc acc => ret (listV (listOf acc ++ [arg]))
  | .toList => ret arg
  | .tryGet d => ret (match v.deferred d with | some x => .some x | none => .none)
  | .elemSel f p s q a =>
    match arg with
    | .some (.some (.err e)) => prog (.pure (dRaise e))
    | .some .none => prog (.pure dCanceledNever)
    | .none => prog (.uncancelable (PT.uncK f p s q a).fn)
    | _ => illTyped
  | .uncK f p s q a =>
    match arg with
    | .poll m pp => prog (.flatMap (.delay PT.newDeferred.fn) (PT.resK f p s q a m pp).fn)
    | _ => illTyped
  | .resK f p s q a m pp =>
    match arg with
    -- `action = poll(sem.acquire) *> (...).start`; `action flatMap { fiber => ... }`
    | .deferred r =>
      prog (.flatMap (.flatMap (IO.applyPoll (acquireIO q) m pp) (PT.thenStart f p s q a r).fn) (PT.fibK p s r).fn)
    | _ => illTyped
  | .thenStart f p s q a r =>
    -- `(F.unit >> f(a)).guaranteeCase {...}.void.voidError.start`
    prog (.start (.handleErrorWith
      (.map (Bracket.guaranteeCaseIO (.ext (srcAction f a)) (PT.finK p s q r).id) PT.voidK.fn) PT.unitH.fn))
  | .callF f a => uc f a v
  | .finK p s q r =>
    let completion : IO :=
      match arg with
      | .ocSucceeded _ => .flatMap (tryGetIO p) (PT.compSucc r arg).fn
      | .ocErrored e => .flatMap (completeIO p (.some (.err e))) (PT.ifErr s r e).fn
      | _ => .flatMap (completeIO p .none) (PT.ifCan s r).fn
    prog (.flatMap completion (PT.thenRelease q).fn)
  | .compSucc r oc =>
    match arg with
    | .some (.some (.err e)) => prog (completeIO r (.ocErrored e))
    | .some .none => prog (completeIO r .ocCanceled)
    | .none => prog (completeIO r oc)
    | _ => illTyped
  | .ifErr s r e =>
    match arg with
    | .bool true => prog (.flatMap (completeIO r (.ocErrored e)) (PT.plCancelAll s (.some (.err e))).fn)
    | .bool false => prog (.pure (.bool false))
    | _ => illTyped
  | .ifCan s r =>
    match arg with
    | .bool true => prog (.flatMap (completeIO r .ocCanceled) (PT.plStartCancelAll s).fn)
    | .bool false => prog (.pure (.bool false))
    | _ => illTyped
  | .plCancelAll s c => prog (.map (cancelAllIO s c) (PT.asK arg).fn)
  | .plStartCancelAll s => prog (.map (.start (cancelAllIO s .none)) (PT.asK arg).fn)
  | .asK b => ret b
  | .thenRelease q => prog (releaseIO q)
  | .voidK => ret .unit
  | .unitH => prog (.pure .unit)
  | .fibK p s r =>
    match arg with
    | .fiber t => prog (.flatMap (.delay (PT.supAdd s t r).fn) (PT.thenAfter p s t r).fn)
    | _ => illTyped
  | .supAdd s t r =>
    match v.refs[s]? with
    | some xs =>
      match setAdd (listOf xs) (.pair (.fiber t) (.deferred r)) with
      | some ys => { effects := [.writeRef s (listV ys)], out := .ret .unit }
      | none => { out := .throw { code := setLimitCode, kind := .fatal } }
    | none => illTyped
  | .supRemove s t r =>
    match v.refs[s]? with
    | some xs => { effects := [.writeRef s (listV (setRemove (listOf xs) (.pair (.fiber t) (.deferred r))))], out := .ret .unit }
    | none => illTyped
  | .thenAfter p s t r => prog (.flatMap (tryGetIO p) (PT.selAfter s t r).fn)
  | .selAfter s t r =>
    match arg with
    | .some (.some (.err e)) => prog (.map (IO.cancelOf t (v.outcome t)) (PT.asK (dRaise e)).fn)
    | .some .none => prog (.map (IO.cancelOf t (v.outcome t)) (PT.asK dCanceledNever).fn)
    | .none =>
      prog (.pure (dResultGet s t r (match v.deferred r with | some x => .some x | none => .none)))
    | _ => illTyped
  | .finRes s t r =>
    match arg with
    | .ocCanceled => prog (.pure .unit)
    | _ => prog (.delay (PT.supRemove s t r).fn)
  | .embedK =>
    match arg with
    | .ocSucceeded b => prog (.pure b)
    | .ocErrored e => prog (.error e)
    | .ocCanceled => prog canceledNever
    | _ => illTyped
  | .constNever => prog Timeout.neverIO
  | .seqK =>
    match listOf arg with
    | [] => prog (.pure (listV []))
    | ds => prog (.map (ds.foldl (fun acc d => .flatMap acc (PT.seqM2 d).fn) (.pure (listV []))) PT.toList.fn)
  | .seqM2 d => prog (.map (descIO d) (PT.snoc arg).fn)
  | .refGet s => ret (v.refs.getD s .unit)
  | .caK c =>
    match listOf arg with
    | [] => prog (.pure .unit)
    | xs => prog (runHalf c xs)
  | .ifCancel t =>
    match arg with
    | .bool true => prog (IO.cancelOf t (v.outcome t))
    | .bool false => prog (.pure .unit)
    | _ => illTyped
  | .ifCA s =>
    match arg with
    | .bool true => prog (cancelAllIO s .none)
    | .bool false => prog (.pure .unit)
    | _ => illTyped
  | .thenJoinAll s => prog (.flatMap (.delay (PT.refGet s).fn) PT.joinAllK.fn)
  | .joinAllK =>
    let snapOf (t : Nat) : Val := match v.outcome t with | some oc => .some oc.toVal | none => .none
    let joinVoid (t : Nat) : IO := .map (IO.joinOf t (v.outcome t)) PT.voidK.fn
    match listOf arg with
    | [] => prog (.pure .unit)
    | .pair (.fiber t0) _ :: rest =>
      prog (.map (rest.foldl (fun g x =>
        match x with
        | .pair (.fiber t) _ => .flatMap g (PT.constJoin t (snapOf t)).fn
        | _ => g) (joinVoid t0)) PT.voidK.fn)
    | _ => illTyped
  | .constJoin t snap =>
    prog (.map (IO.joinOf t (match snap with
      | .some (.ocSucceeded x) => some (.succeeded x)
      | .some (.ocErrored e) => some (.errored e)
      | .some .ocCanceled => some .canceled
      | _ => none)) PT.voidK.fn)
  | .acqBody q =>
    match arg with
    | .poll m pp => prog (.flatMap (.delay PT.newDeferred.fn) (PT.acqWait q m pp).fn)
    | _ => illTyped
  | .acqWait q m pp =>
    match arg with
    | .deferred w => prog (.flatMap (.delay (PT.modAcq q w m pp).fn) PT.flattenK.fn)
    | _ => illTyped
  | .modAcq q w m pp =>
    match semState v q with
    | some (ws, 0) =>
      { effects := [.writeRef q (.pair (listV (ws ++ [.deferred w])) (.nat 0))], out := .ret (dAcqWait q w m pp) }
    | some (ws, k + 1) => { effects := [.writeRef q (.pair (listV ws) (.nat k))], out := .ret dUnit }
    | none => illTyped
  | .flattenK => prog (descIO arg)
  | .wonK q =>
    match arg with
    | .bool true => prog (.pure .unit)
    | .bool false => prog (releaseIO q)
    | _ => illTyped
  | .relBody q => prog (.flatMap (.delay (PT.modRel q).fn) PT.flattenK.fn)
  | .modRel q =>
    match semState v q with
    | some (.deferred h :: ws, k) => { effects := [.writeRef q (.pair (listV ws) (.nat k))], out := .ret (dGrant q h) }
    | some ([], k) => { effects := [.writeRef q (.pair (listV []) (.nat (k + 1)))], out := .ret dUnit }
    | _ => illTyped

/-- The environment of a program that uses `parTraverseN`: these closures, the `Bracket`, `Race`
and `Timeout` mirrors, and user code `u` (even ids). -/
def dispatch (u : UserEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match PT.ofId? id with
  | some l => call u.callV l arg v
  | none =>
    match Bracket.BLam.ofId? id with
    | some l =>
      Bracket.call (fun k a w => match PT.ofId? k with
        | some l' => call u.callV l' a w
        | none => u.callV k a w) ioOf l arg v
    | none =>
      match Race.ofId? id with
      | some l => Race.call ioOf l arg v
      | none =>
        if isLibId id then
          match (cloOfId id).bind ofCloVal with
          | some (k, tag, fs) =>
            if k == Timeout.ns then
              match Timeout.TLam.ofFields tag fs with
              | some l => Timeout.call ioOf l arg v
              | none => u.callV id arg v
            else u.callV id arg v
          | none => u.callV id arg v
        else u.callV id arg v

def env (u : UserEnv) : UserEnv where
  call id arg refs := dispatch u id arg { refs }
  callV := dispatch u

end CatsEffectInLean.Model.ParTraverse

import CatsEffectInLean.Model.Codec
import CatsEffectInLean.Model.Timeout
import CatsEffectInLean.Model.Bracket

/-!
# `IO#memoize` = kernel `GenConcurrent#memoize` with `IOAsync` (mirror)

Phase 6, track M. `IO.scala` = `core/shared/src/main/scala/cats/effect/IO.scala`,
`K/` = `kernel/shared/src/main/scala/cats/effect/kernel/`, both at `v3.7.1`.

## Dispatch (checked 2026-11-10)

`IO#memoize` (`IO.scala:944-945`) is `Concurrent[IO].memoize(this)`, and `Concurrent[IO]` is
`IO.asyncForIO` (`IOAsync`, `IO.scala:1996-2180`). `IOAsync` does not override `memoize`. So
the body is the kernel default `GenConcurrent#memoize` (`K/GenConcurrent.scala:43-112`) with
the `IOAsync` operations. There is no second `IO` body: no `IO`-vs-kernel twin. The `Resource`
instance overrides `memoize` with a different body (`K/Resource.scala:1479-1480`,
`memoizedAcquire`, `K/Resource.scala:792-803`); track Res owns `Resource`, so it is not
mirrored here.

```scala
def memoize[A](fa: F[A]): F[F[A]] = {                                   // K/GenConcurrent.scala:43
  ref[Memoize[F, E, A]](Unevaluated()) map { state =>
    def evalOrSubscribe: F[A] =
      deferred[Fiber[F, E, A]] flatMap { deferredFiber =>
        state.flatModifyFull {
          case (poll, Unevaluated()) =>
            val go = {
              def tryComplete(result: Memoize[F, E, A]): F[Unit] = state.update {
                case Evaluating(fiber, _) if fiber eq deferredFiber => result
                case other => other
              }
              fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_)).guaranteeCase {
                case Outcome.Canceled() => tryComplete(Finished(Right(productR(canceled)(never))))
                case Outcome.Errored(err) => tryComplete(Finished(Left(err)))
                case Outcome.Succeeded(fa) => tryComplete(Finished(Right(fa)))
              }
            }
            val eval = go.start.flatMap { fiber =>
              deferredFiber.complete(fiber) *>
                poll(fiber.join.flatMap(_.embed(productR(canceled)(never))))
                  .onCancel(unsubscribe(deferredFiber))
            }
            Evaluating(deferredFiber, 1) -> eval
          case (poll, Evaluating(fiber, subscribers)) =>
            Evaluating(fiber, subscribers + 1) ->
              poll(fiber.get.flatMap(_.join).flatMap(_.embed(productR(canceled)(never))))
                .onCancel(unsubscribe(fiber))
          case (_, finished @ Finished(result)) =>                       // K/GenConcurrent.scala:91-92
            finished -> fromEither(result).flatten
        }
      }
    def unsubscribe(expected: Deferred[F, Fiber[F, E, A]]): F[Unit] =
      state.modify {
        case Evaluating(fiber, subscribers) if fiber eq expected =>
          if (subscribers == 1) Unevaluated() -> fiber.get.flatMap(_.cancel)
          else Evaluating(fiber, subscribers - 1) -> unit
        case other => other -> unit
      }.flatten
    state.get.flatMap {
      case Finished(result) => fromEither(result).flatten
      case _ => evalOrSubscribe
    }
  }
}
```

## `IOAsync` operations

* `ref(a)` = `IO.ref(a)` = `IO(Ref.unsafe(a))` = `Delay` (`IO.scala:2161`, `:1822`); the `Ref` is a
  `SyncRef` (`K/Ref.scala:314`). `SyncRef.get`, `update`, `modify` are each one `F.delay` of an
  `AtomicReference` loop (`kernel/jvm-native/.../SyncRef.scala:30`, `:65-72`, `:86-94`). One model
  step is atomic (one thread), so the CAS succeeds the first time; `update`/`modify` write the
  new value (also when it is the old one).
* `flatModifyFull(f)` = `F.uncancelable(poll => F.flatten(modify(f(poll, _))))` (`K/Ref.scala:140-141`,
  not overridden by `SyncRef`).
* `deferred` = `IO.deferred` = `IO(new IODeferred)` (`IO.scala:2163`, `:1824`); `complete(a)` =
  `IO { … }` (`RtFn.deferredComplete`); `get` reads the cell when it is called
  (`IO.deferredGetOf`).
* `map` = `Map`, `flatMap` = `FlatMap`, `handleErrorWith` = `HandleErrorWith`, `pure` = `Pure`,
  `raiseError` = `Error`, `unit` = `Pure(())`, `start` = `Start`, `canceled` = `Canceled`,
  `uncancelable` = `Uncancelable`, `onCancel` = `OnCancel`, `poll(fa)` = `UnmaskRunLoop`
  (`IO.applyPoll`) (`IO.scala:1998-2105`).
* `flatten` = cats `FlatMap.flatten` = `flatMap(ffa)(fa => fa)` (not overridden).
* `fromEither` = cats `ApplicativeError.fromEither`: `Right(a) => pure(a)`, `Left(e) => raiseError(e)`
  (not overridden).
* `x *> y` and `productR(x)(y)` = `IOAsync.productR` = `x.flatMap(_ => y)` (`IO.scala:2081-2082`);
  `y` is built first (a value argument).
* `never` = `Async.never` = `Timeout.neverIO` (`IOAsync` does not override it).
* `fa.guaranteeCase(fin)` = `IOAsync.guaranteeCase` = `IO#guaranteeCase` (`IO.scala:2026-2027`,
  `:523-530`). Its closures are mirrored here again (`gcBody`, `gcOnError`, `gcTap`; same
  structure as `Bracket.BLam.gcBody`/`gcOnError`/`gcTap`), because the finalizer is a library
  closure of this mirror, not a user function. The leaf closures `reportError`, `*> raiseError(t)`
  and `as(a)` are the `Bracket` closures (`Bracket.reportIO`, `BLam.raiseK`, `BLam.asK`).
* `oc.embed(x)` = `oc.fold(x, F.raiseError, identity)` (`K/Outcome.scala:73-74`). `fiber.join`
  reads `_join` and `fiber.cancel` reads `_cancel` when they are called (`IO.joinOf`,
  `IO.cancelOf`).

## Encoding

* The `Ref` holds the state as a `Val` (`stateVal`): `Unevaluated` = `none`,
  `Evaluating(d, n)` = `pair (deferred d) (nat n)`, `Finished(Left(e))` = `left (err e)`,
  `Finished(Right(IO.pure(a)))` = `right (some a)` (an `Outcome.Succeeded` of `IO` holds
  `IO.pure(a)`), `Finished(Right(productR(canceled)(never)))` = `right none`.
  `fiber eq deferredFiber` compares `Deferred` ids.
* A `Val` cannot hold an `IO`. Where Scala returns an `IO` as a value (the `F[B]` of `modify`,
  `fromEither(Right(fa))`), the model returns an effect code (`Eff`, namespace `effNs`) and the
  `fa => fa` of `flatten` (`flattenK`) builds the `IO` from it (`effIO`). The run loop runs
  `FlatMap(Delay(thunk), f)` and `FlatMap(Pure(x), f)` in one iteration each, as Scala does, so
  the step count is the same.
* The memoized `get` (the value of the outer `IO`) is the code `getVal r src variant`
  (`Eff.get`); `getIO` builds it. `src` is the code of `fa`; the caller gives `srcIO : Val → IO`.
* `variant` 0 is Cats Effect v3.7.1. `variant` 1 is **not Cats Effect code**: the fixed twin of
  CE-0030 (decision 39), where the `Finished` case of `flatModifyFull` returns
  `poll(fromEither(result).flatten)`. All other closures are shared.
-/

namespace CatsEffectInLean.Model.Memoize

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the memoize closures (track M, Phase 6: namespaces 30..39). -/
def ns : Nat := 30
/-- The namespace of the effect codes (`Eff`). -/
def effNs : Nat := 31

/-! ## State -/

/-- `Evaluating(d, n)`. -/
def evaluating (d n : Nat) : Val := .pair (.deferred d) (.nat n)

/-- The state of the memo as Scala sees it. -/
inductive St where
  | unevaluated
  | evaluating (d n : Nat)
  /-- `Finished(result)`; `res` is `left (err e)`, `right (some a)` or `right none`. -/
  | finished (res : Val)
  /-- Not a state value (impossible in a typed program). -/
  | bad

/-- Read a state value. -/
def St.ofVal : Val → St
  | .none => .unevaluated
  | .pair (.deferred d) (.nat n) => .evaluating d n
  | .left (.err e) => .finished (.left (.err e))
  | .right (.some a) => .finished (.right (.some a))
  | .right .none => .finished (.right .none)
  | _ => .bad

/-- The deferred snapshot code: `some v` (completed with `v`) or `none`. -/
def snapD (o : Option Val) : Val :=
  match o with
  | some v => .some v
  | none => .none

def snapDOpt : Val → Option Val
  | .some v => some v
  | _ => none

/-! ## Effect codes -/

/-- An `IO` that Scala passes as a value. -/
inductive Eff where
  /-- `IO.pure(a)` (the `fa` of `Succeeded(fa)`). -/
  | pure (a : Val)
  /-- `productR(canceled)(never)`. -/
  | canceledNever
  /-- `eval` of the `Unevaluated` case (`K/GenConcurrent.scala:78-82`): `go.start.flatMap { … }`. -/
  | eval (r : Nat) (src : Val) (d : Nat) (m p : Nat)
  /-- The effect of the `Evaluating` case (`K/GenConcurrent.scala:86-89`); `snap` = the cell of
  `fiber` when `fiber.get` was called (`snapD`). -/
  | sub (r fd : Nat) (snap : Val) (m p : Nat)
  /-- `fromEither(result).flatten` (`K/GenConcurrent.scala:92`, `:108`). -/
  | finished (res : Val)
  /-- Not Cats Effect code (variant 1): `poll(fromEither(result).flatten)`. -/
  | finishedPoll (res : Val) (m p : Nat)
  /-- `unit` (`K/GenConcurrent.scala:102`, `:104`). -/
  | unit
  /-- `fiber.get.flatMap(_.cancel)` (`K/GenConcurrent.scala:100`); `snap` as in `sub`. -/
  | cancel (d : Nat) (snap : Val)
  /-- The memoized `get` (`K/GenConcurrent.scala:107-110`): the value of the outer `IO`. -/
  | get (r : Nat) (src : Val) (variant : Nat)
  deriving DecidableEq, Repr

def Eff.toVal : Eff → Val
  | .pure a => cloVal effNs 0 [a]
  | .canceledNever => cloVal effNs 1 []
  | .eval r src d m p => cloVal effNs 2 [.ref r, src, .deferred d, .poll m p]
  | .sub r fd snap m p => cloVal effNs 3 [.ref r, .deferred fd, snap, .poll m p]
  | .finished res => cloVal effNs 4 [res]
  | .finishedPoll res m p => cloVal effNs 5 [res, .poll m p]
  | .unit => cloVal effNs 6 []
  | .cancel d snap => cloVal effNs 7 [.deferred d, snap]
  | .get r src variant => cloVal effNs 8 [.ref r, src, .nat variant]

def Eff.ofFields : Nat → List Val → Option Eff
  | 0, [a] => some (.pure a)
  | 1, [] => some .canceledNever
  | 2, [.ref r, src, .deferred d, .poll m p] => some (.eval r src d m p)
  | 3, [.ref r, .deferred fd, snap, .poll m p] => some (.sub r fd snap m p)
  | 4, [res] => some (.finished res)
  | 5, [res, .poll m p] => some (.finishedPoll res m p)
  | 6, [] => some .unit
  | 7, [.deferred d, snap] => some (.cancel d snap)
  | 8, [.ref r, src, .nat variant] => some (.get r src variant)
  | _, _ => none

def Eff.ofVal? (c : Val) : Option Eff :=
  match ofCloVal c with
  | some (k, tag, fs) => if k == effNs then Eff.ofFields tag fs else none
  | none => none

/-- The memoized `get` of state cell `r`, source `src`, variant `variant`, as a value. -/
def getVal (r : Nat) (src : Val) (variant : Nat) : Val := (Eff.get r src variant).toVal

/-! ## Closures -/

/-- The lambdas (library closures, odd ids, namespace `ns`). -/
inductive MLam where
  /-- The thunk of `IO(Ref.unsafe(Unevaluated()))` (`IO.scala:1822`, `K/Ref.scala:314`). -/
  | refThunk
  /-- `state => …` of `ref(…) map { state => … }`: returns the `get` (`K/GenConcurrent.scala:47-111`). -/
  | mkGet (src : Val) (variant : Nat)
  /-- The thunk of `state.get` = `F.delay(ar.get)` (`SyncRef.scala:30`). -/
  | stateGet (r : Nat)
  /-- `{ case Finished(result) => fromEither(result).flatten; case _ => evalOrSubscribe }`
  (`K/GenConcurrent.scala:107-110`). -/
  | getSel (r : Nat) (src : Val) (variant : Nat)
  /-- The thunk of `IO(new IODeferred)` (`IO.scala:1824`). -/
  | newDeferred
  /-- `deferredFiber => state.flatModifyFull { … }` (`K/GenConcurrent.scala:50-51`). -/
  | evalOrSub (r : Nat) (src : Val) (variant : Nat)
  /-- `poll => F.flatten(modify(f(poll, _)))` of `flatModifyFull` (`K/Ref.scala:141`). -/
  | fmfBody (r : Nat) (src : Val) (d : Nat) (variant : Nat)
  /-- The thunk of `modify(f(poll, _))` (`SyncRef.scala:86-94`) with the `flatModifyFull`
  function of `K/GenConcurrent.scala:51-93`. -/
  | modifyThunk (r : Nat) (src : Val) (d m p : Nat) (variant : Nat)
  /-- `fa => fa` of `flatten`, on an effect code. -/
  | flattenK
  /-- `F.pure(_)` (`K/GenConcurrent.scala:65`). -/
  | pureK
  /-- `F.raiseError(_)` (`K/GenConcurrent.scala:66`). -/
  | raiseK
  /-- `poll => …` of `IO#guaranteeCase` (`IO.scala:524-529`) on `go`'s source, with the
  finalizer `{ case … => tryComplete(…) }` of `K/GenConcurrent.scala:68-75`. -/
  | gcBody (r : Nat) (d : Nat) (src : Val)
  /-- The `onError` function of that `IO#guaranteeCase` (`IO.scala:526-528`, `:605-606`). -/
  | gcOnError (r d : Nat)
  /-- `a => finalizer(Outcome.succeeded(IO.pure(a))).as(a)` (`IO.scala:529`, `:474`). -/
  | gcTap (r d : Nat)
  /-- The thunk of `tryComplete(result)` = `state.update { … }` (`K/GenConcurrent.scala:55-61`,
  `SyncRef.scala:65-72`). -/
  | tryComplete (r d : Nat) (res : Val)
  /-- `fiber => deferredFiber.complete(fiber) *> …` (`K/GenConcurrent.scala:78-82`). -/
  | evalK (r d m p : Nat)
  /-- `_ => that` of that `*>`; `that` was built with `fiber.join` read as `snap`. -/
  | thenEval (r d f : Nat) (snap : Val) (m p : Nat)
  /-- `_.embed(productR(canceled)(never))` (`K/GenConcurrent.scala:80`, `:88`). -/
  | embedK
  /-- `_ => never` of `productR(canceled)(never)`. -/
  | constNever
  /-- The thunk of `state.modify { … }` of `unsubscribe(expected)` (`K/GenConcurrent.scala:96-105`). -/
  | unsubThunk (r d : Nat)
  /-- `_.join` (`K/GenConcurrent.scala:88`). -/
  | joinK
  /-- `_.cancel` (`K/GenConcurrent.scala:100`). -/
  | cancelK
  deriving DecidableEq, Repr

def MLam.toVal : MLam → Val
  | .refThunk => cloVal ns 0 []
  | .mkGet src variant => cloVal ns 1 [src, .nat variant]
  | .stateGet r => cloVal ns 2 [.ref r]
  | .getSel r src variant => cloVal ns 3 [.ref r, src, .nat variant]
  | .newDeferred => cloVal ns 4 []
  | .evalOrSub r src variant => cloVal ns 5 [.ref r, src, .nat variant]
  | .fmfBody r src d variant => cloVal ns 6 [.ref r, src, .deferred d, .nat variant]
  | .modifyThunk r src d m p variant => cloVal ns 7 [.ref r, src, .deferred d, .poll m p, .nat variant]
  | .flattenK => cloVal ns 8 []
  | .pureK => cloVal ns 9 []
  | .raiseK => cloVal ns 10 []
  | .gcBody r d src => cloVal ns 11 [.ref r, .deferred d, src]
  | .gcOnError r d => cloVal ns 12 [.ref r, .deferred d]
  | .gcTap r d => cloVal ns 13 [.ref r, .deferred d]
  | .tryComplete r d res => cloVal ns 14 [.ref r, .deferred d, res]
  | .evalK r d m p => cloVal ns 15 [.ref r, .deferred d, .poll m p]
  | .thenEval r d f snap m p => cloVal ns 16 [.ref r, .deferred d, .fiber f, snap, .poll m p]
  | .embedK => cloVal ns 17 []
  | .constNever => cloVal ns 18 []
  | .unsubThunk r d => cloVal ns 19 [.ref r, .deferred d]
  | .joinK => cloVal ns 20 []
  | .cancelK => cloVal ns 21 []

def MLam.ofFields : Nat → List Val → Option MLam
  | 0, [] => some .refThunk
  | 1, [src, .nat variant] => some (.mkGet src variant)
  | 2, [.ref r] => some (.stateGet r)
  | 3, [.ref r, src, .nat variant] => some (.getSel r src variant)
  | 4, [] => some .newDeferred
  | 5, [.ref r, src, .nat variant] => some (.evalOrSub r src variant)
  | 6, [.ref r, src, .deferred d, .nat variant] => some (.fmfBody r src d variant)
  | 7, [.ref r, src, .deferred d, .poll m p, .nat variant] => some (.modifyThunk r src d m p variant)
  | 8, [] => some .flattenK
  | 9, [] => some .pureK
  | 10, [] => some .raiseK
  | 11, [.ref r, .deferred d, src] => some (.gcBody r d src)
  | 12, [.ref r, .deferred d] => some (.gcOnError r d)
  | 13, [.ref r, .deferred d] => some (.gcTap r d)
  | 14, [.ref r, .deferred d, res] => some (.tryComplete r d res)
  | 15, [.ref r, .deferred d, .poll m p] => some (.evalK r d m p)
  | 16, [.ref r, .deferred d, .fiber f, snap, .poll m p] => some (.thenEval r d f snap m p)
  | 17, [] => some .embedK
  | 18, [] => some .constNever
  | 19, [.ref r, .deferred d] => some (.unsubThunk r d)
  | 20, [] => some .joinK
  | 21, [] => some .cancelK
  | _, _ => none

/-- The closure id (odd, `Codec.libFn`). -/
def MLam.id (l : MLam) : Nat := 2 * valToNat l.toVal + 1

/-- The closure as a `Fn`. -/
def MLam.fn (l : MLam) : Fn := .user l.id

/-- The closure of an id, if it is one of this mirror. -/
def MLam.ofId? (id : Nat) : Option MLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then MLam.ofFields tag fs else none
    | none => none
  else none

/-! ## Builders -/

/-- `fa.memoize` (`IO.scala:944-945`): `ref(Unevaluated()) map { state => … }`
(`K/GenConcurrent.scala:47`). `src` is the code of `fa`. -/
def memoizeIO (src : Val) (variant : Nat := 0) : IO :=
  .map (.delay MLam.refThunk.fn) (MLam.mkGet src variant).fn

/-- The memoized `get` of state cell `r` (`K/GenConcurrent.scala:107-110`). -/
def getIO (r : Nat) (src : Val) (variant : Nat) : IO :=
  .flatMap (.delay (MLam.stateGet r).fn) (MLam.getSel r src variant).fn

/-- The `get` of a value, if it is one. -/
def getOfVal? (c : Val) : Option IO :=
  match Eff.ofVal? c with
  | some (.get r src variant) => some (getIO r src variant)
  | _ => none

/-- `fromEither(result)` (`Right(fa) => pure(fa)`, `Left(e) => raiseError(e)`), with the `IO` in
`Right` as an effect code. -/
def fromEitherIO (res : Val) : IO :=
  match res with
  | .left (.err e) => .error e
  | .right (.some a) => .pure (Eff.pure a).toVal
  | .right .none => .pure Eff.canceledNever.toVal
  | _ => .error { code := 999999, kind := .fatal }

/-- `fromEither(result).flatten`. -/
def finishedIO (res : Val) : IO := .flatMap (fromEitherIO res) MLam.flattenK.fn

/-- `productR(canceled)(never)` = `canceled.flatMap(_ => never)`. -/
def canceledNeverIO : IO := .flatMap .canceled MLam.constNever.fn

/-- `tryComplete(result)` = `state.update { … }` = `Delay`. -/
def tryIO (r d : Nat) (res : Val) : IO := .delay (MLam.tryComplete r d res).fn

/-- `unsubscribe(expected)` = `state.modify { … }.flatten`. -/
def unsubIO (r d : Nat) : IO := .flatMap (.delay (MLam.unsubThunk r d).fn) MLam.flattenK.fn

/-- `go` (`K/GenConcurrent.scala:54-76`): `IO#guaranteeCase` = `Uncancelable(gcBody)`. -/
def goIO (r d : Nat) (src : Val) : IO := .uncancelable (MLam.gcBody r d src).fn

/-- The `this` of that `guaranteeCase`: `fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_))`. -/
def hackedIO (srcIO : Val → IO) (src : Val) : IO :=
  .handleErrorWith (.flatMap (srcIO src) MLam.pureK.fn) MLam.raiseK.fn

/-- The `IO` of an effect code (the `fa => fa` of `flatten`). -/
def effIO : Eff → IO
  | .pure a => .pure a
  | .canceledNever => canceledNeverIO
  -- `go.start.flatMap { fiber => … }`
  | .eval r src d m p => .flatMap (.start (goIO r d src)) (MLam.evalK r d m p).fn
  -- `poll(fiber.get.flatMap(_.join).flatMap(_.embed(…))).onCancel(unsubscribe(fiber))`
  | .sub r fd snap m p =>
    .onCancel (IO.applyPoll (.flatMap (.flatMap (IO.deferredGetOf fd (snapDOpt snap)) MLam.joinK.fn)
      MLam.embedK.fn) m p) (unsubIO r fd)
  | .finished res => finishedIO res
  | .finishedPoll res m p => IO.applyPoll (finishedIO res) m p
  | .unit => .pure .unit
  -- `fiber.get.flatMap(_.cancel)`
  | .cancel d snap => .flatMap (IO.deferredGetOf d (snapDOpt snap)) MLam.cancelK.fn
  | .get r src variant => getIO r src variant

private def ret (v : Val) : UserResult := { out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
/-- An argument of the wrong shape: impossible in a well-typed Scala program. -/
def illTyped : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- The state cell `r` in view `v` (`none` = no such cell: impossible, the mirror allocates it). -/
def cell (v : View) (r : Nat) : Val := v.refs.getD r (.nat 999999)

/-- Run closure `l` on `arg` with view `v`. `srcIO` builds `fa` from its code. -/
def call (srcIO : Val → IO) (l : MLam) (arg : Val) (v : View) : UserResult :=
  match l with
  -- `Ref.unsafe(Unevaluated())`: a new cell; its id is the number of cells before it
  | .refThunk => { effects := [.allocRef .none], out := .ret (.ref v.refs.length) }
  | .mkGet src variant =>
    match arg with
    | .ref r => ret (getVal r src variant)
    | _ => illTyped
  | .stateGet r => ret (cell v r)
  | .getSel r src variant =>
    match St.ofVal arg with
    -- `case Finished(result) => fromEither(result).flatten`
    | .finished res => prog (finishedIO res)
    -- `case _ => evalOrSubscribe` = `deferred[…] flatMap { … }`
    | .unevaluated | .evaluating _ _ =>
      prog (.flatMap (.delay MLam.newDeferred.fn) (MLam.evalOrSub r src variant).fn)
    | .bad => illTyped
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred v.deferreds.length) }
  | .evalOrSub r src variant =>
    match arg with
    -- `state.flatModifyFull { … }` = `uncancelable(poll => flatten(modify(f(poll, _))))`
    | .deferred d => prog (.uncancelable (MLam.fmfBody r src d variant).fn)
    | _ => illTyped
  | .fmfBody r src d variant =>
    match arg with
    | .poll m p => prog (.flatMap (.delay (MLam.modifyThunk r src d m p variant).fn) MLam.flattenK.fn)
    | _ => illTyped
  | .modifyThunk r src d m p variant =>
    match St.ofVal (cell v r) with
    -- `case (poll, Unevaluated()) => Evaluating(deferredFiber, 1) -> eval`
    | .unevaluated =>
      { effects := [.writeRef r (evaluating d 1)], out := .ret (Eff.eval r src d m p).toVal }
    -- `case (poll, Evaluating(fiber, subscribers)) => Evaluating(fiber, subscribers + 1) -> …`;
    -- `fiber.get` reads the cell now
    | .evaluating fd n =>
      { effects := [.writeRef r (evaluating fd (n + 1))],
        out := .ret (Eff.sub r fd (snapD (v.deferred fd)) m p).toVal }
    -- `case (_, finished @ Finished(result)) => finished -> fromEither(result).flatten`
    | .finished res =>
      { effects := [.writeRef r res],
        out := .ret (if variant == 1 then (Eff.finishedPoll res m p).toVal else (Eff.finished res).toVal) }
    | .bad => illTyped
  | .flattenK =>
    match Eff.ofVal? arg with
    | some e => prog (effIO e)
    | none => illTyped
  | .pureK => prog (.pure arg)
  | .raiseK =>
    match arg with
    | .err e => prog (.error e)
    | _ => illTyped
  | .gcBody r d src =>
    match arg with
    -- `val finalized = poll(this).onCancel(finalizer(Outcome.canceled))`;
    -- `finalized.onError(onError).flatTap(…)` (`IO.scala:525-529`)
    | .poll m p =>
      prog (.flatMap (.handleErrorWith (.onCancel (IO.applyPoll (hackedIO srcIO src) m p)
        (tryIO r d (.right .none))) (MLam.gcOnError r d).fn) (MLam.gcTap r d).fn)
    | _ => illTyped
  | .gcOnError r d =>
    match arg with
    -- `finalizer(Outcome.errored(e)).reportError *> IO.raiseError(t)` (`IO.scala:527`, `:605-606`)
    | .err t => prog (.flatMap (Bracket.reportIO (tryIO r d (.left (.err t)))) (Bracket.BLam.raiseK t).fn)
    | _ => illTyped
  -- `finalizer(Outcome.succeeded(IO.pure(a))).as(a)`
  | .gcTap r d => prog (.map (tryIO r d (.right (.some arg))) (Bracket.BLam.asK arg).fn)
  | .tryComplete r d res =>
    match St.ofVal (cell v r) with
    -- `case Evaluating(fiber, _) if fiber eq deferredFiber => result`
    | .evaluating fd _ =>
      if fd == d then { effects := [.writeRef r res], out := .ret .unit }
      else { effects := [.writeRef r (cell v r)], out := .ret .unit }
    -- `case other => other`
    | _ => { effects := [.writeRef r (cell v r)], out := .ret .unit }
  | .evalK r d m p =>
    match arg with
    -- `deferredFiber.complete(fiber) *> poll(fiber.join.flatMap(…)).onCancel(…)`: `fiber.join` now
    | .fiber f =>
      prog (.flatMap (.delay (.rt (.deferredComplete d (.fiber f))))
        (MLam.thenEval r d f (Timeout.snapVal (v.outcome f)) m p).fn)
    | _ => illTyped
  | .thenEval r d f snap m p =>
    prog (.onCancel (IO.applyPoll (.flatMap (IO.joinOf f (Timeout.snapOutcome snap)) MLam.embedK.fn) m p)
      (unsubIO r d))
  | .embedK =>
    match arg with
    | .ocSucceeded a => prog (.pure a)
    | .ocErrored e => prog (.error e)
    | .ocCanceled => prog canceledNeverIO
    | _ => illTyped
  | .constNever => prog Timeout.neverIO
  | .unsubThunk r d =>
    match St.ofVal (cell v r) with
    -- `case Evaluating(fiber, subscribers) if fiber eq expected => …`
    | .evaluating fd n =>
      if fd == d then
        if n == 1 then
          -- `Unevaluated() -> fiber.get.flatMap(_.cancel)`: `fiber.get` reads the cell now
          { effects := [.writeRef r .none], out := .ret (Eff.cancel d (snapD (v.deferred d))).toVal }
        else { effects := [.writeRef r (evaluating fd (n - 1))], out := .ret Eff.unit.toVal }
      else { effects := [.writeRef r (cell v r)], out := .ret Eff.unit.toVal }
    -- `case other => other -> unit`
    | _ => { effects := [.writeRef r (cell v r)], out := .ret Eff.unit.toVal }
  | .joinK =>
    match arg with
    | .fiber f => prog (IO.joinOf f (v.outcome f))
    | _ => illTyped
  | .cancelK =>
    match arg with
    | .fiber f => prog (IO.cancelOf f (v.outcome f))
    | _ => illTyped

/-- The library closures of this mirror and the leaf closures it uses (`WellFormed`). -/
def isLib (id : Nat) : Bool :=
  (MLam.ofId? id).isSome ||
    (match Bracket.BLam.ofId? id with
     | some (.reportK) | some (.reportEc _) | some (.reportThunk _) | some (.raiseK _) | some (.asK _) => true
     | _ => false) ||
    (match (cloOfId id).bind ofCloVal with
     | some (k, tag, fs) => isLibId id && k == Timeout.ns && (Timeout.TLam.ofFields tag fs).isSome
     | none => false)

end CatsEffectInLean.Model.Memoize

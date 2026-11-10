import CatsEffectInLean.Model.IOInstance
import CatsEffectInLean.Model.Codec

/-!
# `Resource[IO, A]`: the ADT and `allocatedCase` (CE-0002)

Phase 5. A mirror of the parts of `Resource` that `Resource.eval` and `Resource#allocatedCase`
need, at Cats Effect `v3.7.1`, with `F = IO`. `Resource.scala` below is
`kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`; `IO.scala` is
`core/shared/src/main/scala/cats/effect/IO.scala`.

`F = IO`: each `F.x` call of the generic code is the `IO.asyncForIO` (`IOAsync`) method, which
builds the `IO` node that `CatsEffectInLean/Model/IOInstance.lean` (`IOI`) documents:
`F.uncancelable` = `Uncancelable` (`IO.scala:2095-2096`), `flatMap` = `FlatMap`
(`IO.scala:2101-2102`), `map` = `Map` (`IO.scala:2098-2099`), `F.pure`/`.pure[F]` = `Pure`
(`IO.scala:2017-2018`), `F.unit` = `Pure(())` (`IO.scala:2020-2021`), `onCancel` = `OnCancel`
(`IO.scala:2059-2060`), `onError` = `IO#onError` (`IO.scala:2032-2033`, `:605-606`),
`handleError` = `IO#handleError` (`IO.scala:2029-2030`, `:532-533`).

## Closures

The generic code builds Scala lambdas at run time (for example
`a => continue(Resource.pure(a), stack, release)`, `Resource.scala:527`). In the model a lambda
is a `Fn.user id`. Each library lambda is one constructor of `Clo`, with its captured data. Its
id is `2 * valToNat c.toVal + 1` (odd; `CatsEffectInLean/Model/Codec.lean`). User code has
the even ids: user function `k` is `Fn.user (2 * k)` (`uid k`). `REnv.toEnv` is the `UserEnv`
that runs both: an even id calls the user code, an odd id decodes the closure and runs its
mirror (`cloCall`).

## Values that are functions or programs

`allocatedCase` returns `(B, ExitCase => F[Unit])`, and `Resource.make` stores an `F[Unit]` in a
tuple. A `Val` cannot hold a function or an `IO`. So such a value is a `Val` that describes it:

* a release function `ExitCase => F[Unit]` is `RelFn.toVal` (`RelFn` below);
* the `F[Unit]` `release(a)` of `make` is `ioRelease k a` (user release builder `k` at `a`).

`ExitCase` (`Resource.scala:1190-1232`) is `ocSucceeded unit` (`Succeeded`), `ocErrored e`
(`Errored(e)`), `ocCanceled` (`Canceled`).

## User code at the `Resource` level (`REnv`)

* `user`: ordinary user code (`UserEnv`), for `IO` lambdas, `applyFull` acquire functions
  `Poll[F] => F[(A, ExitCase => F[Unit])]`, and user release functions (`RelFn.user`).
* `bind k b`: the `flatMap` function `fs` of a `Bind` (`S => Resource[F, A]`). A pure Lean
  function that returns a `Resource` or throws. It has no side effects.
* `acquire k`: the `F[A]` acquire of `make` (a value in the Scala source; named by index).
* `release k a`: the release builder `A => F[Unit]` of `make`. Pure; it can throw.

Restriction: `bind` and `release` have no side effects. `make` calls `release(a)` inside the
`map` of acquire (`Resource.scala:902`); the model calls `release k a` there to see a throw,
and calls it again when the release runs (the same `IO`, because the function is pure).

## Model limits (not Cats Effect results)

* `loop` has fuel `loopFuel`. Scala's `@tailrec loop` can run forever (a `Bind` function that
  rebuilds its own `Bind`); then the thread hangs. With no fuel left the model returns a
  program that never ends (`Clo.spin`), so the run has no outcome.
* An ill-typed value (impossible in Scala) gives a fatal throw with code `illTypedCode`.
* Application of the combined release `rel2` (`RelFn.guarantee`, `Resource.scala:490`) is not
  mirrored: it needs `IO#guarantee` (`IO.scala:496-501`) and `reportError`
  (`IO.scala:967-972`), whose `ec.reportFailure(t)` thunk user effects cannot express. It
  gives a fatal throw with code `notMirroredCode`. `allocatedCase` itself never applies a
  `rel2`: it only builds it and passes it on. It applies only the `rel` that an `Allocate`
  returned.

Not mirrored: `fold`/`use`, `allocated`, `Resource#map` and the other combinators.
-/

namespace CatsEffectInLean.Model.Resource

open CatsEffectInLean.Model.Codec

/-- Fatal error code for an ill-typed value (a model limit). -/
def illTypedCode : Nat := 900001

/-- Fatal error code for the application of `rel2` (not mirrored). -/
def notMirroredCode : Nat := 900002

def illTyped : Err := { code := illTypedCode, kind := .fatal }
def notMirrored : Err := { code := notMirroredCode, kind := .fatal }

/-- `ExitCase.Succeeded` (`Resource.scala:1205`). -/
def exitSucceeded : Val := .ocSucceeded .unit
/-- `ExitCase.Errored(e)` (`Resource.scala:1213`). -/
def exitErrored (e : Err) : Val := .ocErrored e
/-- `ExitCase.Canceled` (`Resource.scala:1224`). -/
def exitCanceled : Val := .ocCanceled

/-- The `resource` function of an `Allocate` (`Poll[F] => F[(A, ExitCase => F[Unit])]`). -/
inductive AllocFn where
  /-- User code (`Resource.applyFull(resource)`, `Resource.scala:879-880`): user function
  `id` of `REnv.user`, called with the `poll` value. -/
  | user (id : Nat)
  /-- `Resource.make(acquire)(release)` (`Resource.scala:900-902`) =
  `apply(acquire.map(a => a -> release(a)))`; `apply` (`:826-832`) =
  `applyCase(resource.map { case (a, release) => (a, (_: ExitCase) => release) })`;
  `applyCase` (`:849-850`) = `applyFull(_ => resource)`. So the function is
  `_ => acquire.map(makePair).map(applyPair)`. `acquire` = `REnv.acquire acquire`,
  `release` = `REnv.release release`. -/
  | make (acquire : Nat) (release : Nat)
  deriving DecidableEq, Repr

/-- The `Resource` ADT (`Resource.scala:1167-1178`). -/
inductive Res where
  /-- `Allocate(resource)` (`Resource.scala:1167-1168`). -/
  | allocate (resource : AllocFn)
  /-- `Bind(source, fs)` (`Resource.scala:1173-1174`). `fs` = `REnv.bind fs`. -/
  | bind (source : Res) (fs : Nat)
  /-- `Pure(a)` (`Resource.scala:1176`). -/
  | pure (a : Val)
  /-- `Eval(fa)` (`Resource.scala:1178`). -/
  | eval (fa : IO)
  deriving DecidableEq, Repr

/-- `Resource.eval(fa)` = `Resource.Eval(fa)` (`Resource.scala:992-993`). -/
def Res.evalOf (fa : IO) : Res := .eval fa

/-- `Resource.pure(a)` = `Pure(a)` (`Resource.scala:977-978`). -/
def Res.pureOf (a : Val) : Res := .pure a

/-- `r.flatMap(f)` = `Bind(this, f)` (`Resource.scala:388-389`). -/
def Res.flatMap (r : Res) (f : Nat) : Res := .bind r f

/-- `Resource.make(acquire)(release)` (`Resource.scala:900-902`, through `apply`,
`applyCase`, `applyFull`, `:826-880`). -/
def Res.make (acquire release : Nat) : Res := .allocate (.make acquire release)

/-- A release function value `ExitCase => F[Unit]`. -/
inductive RelFn where
  /-- `_ => F.unit` (`Resource.scala:530`). -/
  | unit
  /-- `(_: ExitCase) => release` (`Resource.scala:830`), where `release` = `release(a)` of
  `make` (`Resource.scala:902`): `REnv.release k a`. -/
  | const (k : Nat) (a : Val)
  /-- A function value from user code: user function `id` of `REnv.user`, called with the
  `ExitCase`. -/
  | user (id : Nat)
  /-- `rel2 = (ec: ExitCase) => rel(ec).guarantee(F.unit >> release(ec))`
  (`Resource.scala:490`). Application not mirrored (module doc). -/
  | guarantee (rel : RelFn) (release : RelFn)
  deriving DecidableEq, Repr

/-- A tagged `Val`: `pair (nat t) payload`. -/
@[inline] def tagged (t : Nat) (payload : Val) : Val := .pair (.nat t) payload

def RelFn.toVal : RelFn → Val
  | .unit => tagged 0 .unit
  | .const k a => tagged 1 (.pair (.nat k) a)
  | .user id => tagged 2 (.nat id)
  | .guarantee a b => tagged 3 (.pair a.toVal b.toVal)

def RelFn.ofVal : Val → Option RelFn
  | .pair (.nat 0) .unit => some .unit
  | .pair (.nat 1) (.pair (.nat k) a) => some (.const k a)
  | .pair (.nat 2) (.nat id) => some (.user id)
  | .pair (.nat 3) (.pair a b) =>
    match RelFn.ofVal a, RelFn.ofVal b with
    | some a', some b' => some (.guarantee a' b')
    | _, _ => none
  | _ => none

/-- The `F[Unit]` value `release(a)` of `make` (tag 10). -/
def ioRelease (k : Nat) (a : Val) : Val := tagged 10 (.pair (.nat k) a)

/-- The stack of `allocatedCase` (`Resource.scala:466-469`): `Nil` or `Frame(head, tail)`.
Each `head` is a `Bind` function (`REnv.bind`). -/
abbrev Stack := List Nat

def stackToVal : Stack → Val
  | [] => .none
  | h :: t => .some (.pair (.nat h) (stackToVal t))

def stackOfVal : Val → Option Stack
  | .none => some []
  | .some (.pair (.nat h) t) => (stackOfVal t).map (h :: ·)
  | _ => none

def allocFnToVal : AllocFn → Val
  | .user id => tagged 0 (.nat id)
  | .make a r => tagged 1 (.pair (.nat a) (.nat r))

def allocFnOfVal : Val → Option AllocFn
  | .pair (.nat 0) (.nat id) => some (.user id)
  | .pair (.nat 1) (.pair (.nat a) (.nat r)) => some (.make a r)
  | _ => none

/-- The library lambdas, with their captured data. -/
inductive Clo where
  /-- `a => continue(Resource.pure(a), stack, release)` (`Resource.scala:527`). -/
  | evalK (stack : Stack) (release : RelFn)
  /-- `poll => resource(poll) flatMap { ... }` (`Resource.scala:486-513`). -/
  | allocBody (resource : AllocFn) (stack : Stack) (release : RelFn)
  /-- `{ case (b, rel) => ... }` (`Resource.scala:487-512`), with the `poll` of its body. -/
  | allocK (stack : Stack) (release : RelFn) (poll : Val)
  /-- The `handleErrorWith` lambda of `IO#onError(pf)` (`IO.scala:605-606`):
  `t => pf.applyOrElse(t, (_: Throwable) => IO.unit) *> IO.raiseError(t)`, with
  `pf = { case e => rel(ExitCase.Errored(e)).handleError(_ => ()) }` (`Resource.scala:510`). -/
  | onErrorH (rel : RelFn)
  /-- `_ => that` of `*>` = `productR` (`IO.scala:138-139`, `:903-904`), with
  `that = IO.raiseError(t)` (`IO.scala:606`). -/
  | raiseK (t : Err)
  /-- `t => IO.pure(f(t))` of `IO#handleError(f)` (`IO.scala:532-533`), with `f = _ => ()`
  (`Resource.scala:510`). -/
  | handleUnit
  /-- `a => a -> release(a)` (`Resource.scala:902`). -/
  | makePair (release : Nat)
  /-- `{ case (a, release) => (a, (_: ExitCase) => release) }` (`Resource.scala:828-831`). -/
  | applyPair
  /-- Model limit: a program that never ends (module doc). -/
  | spin
  deriving DecidableEq, Repr

def Clo.toVal : Clo → Val
  | .evalK s r => tagged 0 (.pair (stackToVal s) r.toVal)
  | .allocBody a s r => tagged 1 (.pair (allocFnToVal a) (.pair (stackToVal s) r.toVal))
  | .allocK s r p => tagged 2 (.pair (stackToVal s) (.pair r.toVal p))
  | .onErrorH r => tagged 3 r.toVal
  | .raiseK t => tagged 4 (.err t)
  | .handleUnit => tagged 5 .unit
  | .makePair k => tagged 6 (.nat k)
  | .applyPair => tagged 7 .unit
  | .spin => tagged 8 .unit

def Clo.ofVal : Val → Option Clo
  | .pair (.nat 0) (.pair s r) =>
    match stackOfVal s, RelFn.ofVal r with
    | some s', some r' => some (.evalK s' r')
    | _, _ => none
  | .pair (.nat 1) (.pair a (.pair s r)) =>
    match allocFnOfVal a, stackOfVal s, RelFn.ofVal r with
    | some a', some s', some r' => some (.allocBody a' s' r')
    | _, _, _ => none
  | .pair (.nat 2) (.pair s (.pair r p)) =>
    match stackOfVal s, RelFn.ofVal r with
    | some s', some r' => some (.allocK s' r' p)
    | _, _ => none
  | .pair (.nat 3) r => (RelFn.ofVal r).map .onErrorH
  | .pair (.nat 4) (.err t) => some (.raiseK t)
  | .pair (.nat 5) .unit => some .handleUnit
  | .pair (.nat 6) (.nat k) => some (.makePair k)
  | .pair (.nat 7) .unit => some .applyPair
  | .pair (.nat 8) .unit => some .spin
  | _ => none

/-- The id of a library closure (odd). -/
def cloFn (c : Clo) : Fn := libFn c.toVal

/-- User function `k` (even id). -/
def uid (k : Nat) : Fn := .user (2 * k)

/-- User code at the `Resource` level. See the module doc. -/
structure REnv where
  /-- Ordinary user code. Function `k` has id `2 * k` in programs (`uid k`). -/
  user : UserEnv
  /-- `Bind` functions `fs : S => Resource[F, A]`. -/
  bind : Nat → Val → Except Err Res
  /-- The acquire programs of `make`. -/
  acquire : Nat → IO
  /-- The release builders `A => F[Unit]` of `make`. -/
  release : Nat → Val → Except Err IO

/-- Fuel of one `loop` call (model limit). -/
def loopFuel : Nat := 1000000

/-- A program that never ends (model limit). -/
def spinIO : IO := .flatMap (.pure .unit) (cloFn .spin)

/-- `loop(current, stack, release)` of `allocatedCase` (`Resource.scala:480-528`). Branch
order as in Scala. `Except.error e`: a `Bind` function threw `e`. -/
def loop (r : REnv) : (fuel : Nat) → Res → Stack → RelFn → Except Err IO
  | 0, _, _, _ => .ok spinIO
  -- `case Allocate(resource) => F uncancelable { poll => resource(poll) flatMap { ... } }`
  -- (`Resource.scala:485-513`)
  | _ + 1, .allocate a, stack, release => .ok (.uncancelable (cloFn (.allocBody a stack release)))
  -- `case Bind(source, fs) => loop(source, Frame(fs, stack), release)` (`:515-516`)
  | f + 1, .bind source fs, stack, release => loop r f source (fs :: stack) release
  -- `case Pure(v) => stack match { case Nil => (v: B, release).pure[F]` (`:518-521`)
  | _ + 1, .pure v, [], release => .ok (.pure (.pair v release.toVal))
  -- `case Frame(head, tail) => loop(head(v), tail, release)` (`:522-523`)
  | f + 1, .pure v, head :: tail, release =>
    match r.bind head v with
    | .ok res => loop r f res tail release
    | .error e => .error e
  -- `case Eval(fa) => fa.flatMap(a => continue(Resource.pure(a), stack, release))` (`:526-527`)
  | _ + 1, .eval fa, stack, release => .ok (.flatMap fa (cloFn (.evalK stack release)))

/-- `allocatedCase` (`Resource.scala:464-531`): `loop(this, Nil, _ => F.unit)` (`:530`).
`Except.error e`: a `Bind` function threw while the program was built. -/
def allocatedCase (r : REnv) (res : Res) : Except Err IO :=
  loop r loopFuel res [] .unit

/-- A user call that must return a program. -/
def progOf (u : UserResult) : List UserEffect × Except Err IO :=
  match u.out with
  | .prog p => (u.effects, .ok p)
  | .throw e => (u.effects, .error e)
  | .ret _ => (u.effects, .error illTyped)

/-- `rel(ec)`: apply a release function value. -/
def applyRel (r : REnv) (v : View) : RelFn → Val → List UserEffect × Except Err IO
  -- `_ => F.unit` (`Resource.scala:530`): `IO.unit` = `Pure(())`
  | .unit, _ => ([], .ok (.pure .unit))
  -- `(_: ExitCase) => release` (`Resource.scala:830`)
  | .const k a, _ => ([], r.release k a)
  | .user id, ec => progOf (r.user.callV id ec v)
  -- `rel2` (`Resource.scala:490`): not mirrored
  | .guarantee _ _, _ => ([], .error notMirrored)

/-- A result with effects. -/
@[inline] def withEffects (es : List UserEffect) : Except Err IO → UserResult
  | .ok p => { effects := es, out := .prog p }
  | .error e => { effects := es, out := .throw e }

def throwR (e : Err) : UserResult := { out := .throw e }

/-- The mirror of each library closure, applied to `arg` with heap view `v`. -/
def cloCall (r : REnv) (c : Clo) (arg : Val) (v : View) : UserResult :=
  match c with
  | .evalK stack release =>
    -- `continue(Resource.pure(a), stack, release)` = `loop(...)` (`Resource.scala:472-476`)
    withEffects [] (loop r loopFuel (.pure arg) stack release)
  | .allocBody res stack release =>
    -- `resource(poll) flatMap { case (b, rel) => ... }` (`Resource.scala:487`)
    let k := cloFn (.allocK stack release arg)
    match res with
    | .user id =>
      let (es, p) := progOf (r.user.callV id arg v)
      withEffects es (p.map (fun p => .flatMap p k))
    | .make acq rel =>
      -- `_ => resource` with `resource = acquire.map(a => a -> release(a)).map { ... }`
      withEffects [] (.ok (.flatMap (.map (.map (r.acquire acq) (cloFn (.makePair rel)))
        (cloFn .applyPair)) k))
  | .allocK stack release poll =>
    match arg with
    | .pair b relV =>
      match RelFn.ofVal relV with
      | none => throwR illTyped
      | some rel =>
        -- `val rel2 = (ec: ExitCase) => rel(ec).guarantee(F.unit >> release(ec))` (`:490`)
        let rel2 := RelFn.guarantee rel release
        match stack with
        -- `case Nil => F.pure((b, rel2))` (`:493-505`)
        | [] => { out := .prog (.pure (.pair b rel2.toVal)) }
        -- `case Frame(head, tail) => poll(continue(head(b), tail, rel2))
        --   .onCancel(rel(ExitCase.Canceled))
        --   .onError { case e => rel(ExitCase.Errored(e)).handleError(_ => ()) }` (`:507-510`)
        | head :: tail =>
          match poll with
          | .poll m s =>
            match r.bind head b with
            | .error e => throwR e
            | .ok res =>
              match loop r loopFuel res tail rel2 with
              | .error e => throwR e
              | .ok io =>
                let (es, fin) := applyRel r v rel exitCanceled
                withEffects es (fin.map fun fin =>
                  .handleErrorWith (.onCancel (.unmaskRunLoop io m s) fin) (cloFn (.onErrorH rel)))
          | _ => throwR illTyped
    | _ => throwR illTyped
  | .onErrorH rel =>
    match arg with
    | .err t =>
      -- `pf.applyOrElse(t, ...) *> IO.raiseError(t)`, `pf(t) = rel(Errored(t)).handleError(_ => ())`
      let (es, p) := applyRel r v rel (exitErrored t)
      withEffects es (p.map fun p => .flatMap (.handleErrorWith p (cloFn .handleUnit)) (cloFn (.raiseK t)))
    | _ => throwR illTyped
  | .raiseK t => { out := .prog (.error t) }
  | .handleUnit => { out := .prog (.pure .unit) }
  | .makePair k =>
    match r.release k arg with
    | .error e => throwR e
    | .ok _ => { out := .ret (.pair arg (ioRelease k arg)) }
  | .applyPair =>
    match arg with
    | .pair a (.pair (.nat 10) (.pair (.nat k) a')) => { out := .ret (.pair a (RelFn.const k a').toVal) }
    | _ => throwR illTyped
  | .spin => { out := .prog spinIO }

/-- Even id: user code; odd id: a library closure. -/
def REnv.callV (r : REnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  if id % 2 == 0 then r.user.callV (id / 2) arg v
  else
    match natToVal (id / 2) with
    | some cv =>
      match Clo.ofVal cv with
      | some c => cloCall r c arg v
      | none => throwR illTyped
    | none => throwR illTyped

/-- The `UserEnv` of a program that uses `Resource`. -/
def REnv.toEnv (r : REnv) : UserEnv where
  call id arg refs := r.callV id arg { refs := refs }
  callV id arg v := r.callV id arg v

end CatsEffectInLean.Model.Resource

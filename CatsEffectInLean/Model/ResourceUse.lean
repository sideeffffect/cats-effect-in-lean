import CatsEffectInLean.Model.Resource
import CatsEffectInLean.Model.Bracket
import CatsEffectInLean.Model.Race

/-!
# `Resource#fold`/`use`/`use_`/`useEval`, `allocated`, the application of `rel2`, and `Resource#both` (mirror)

Phase 6, batch 6.2, track Res. Cats Effect `v3.7.1`, `F = IO`. `Resource.scala` =
`kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`, `IO.scala` =
`core/shared/src/main/scala/cats/effect/IO.scala`, `SyncRef.scala` =
`kernel/jvm-native/src/main/scala/cats/effect/kernel/SyncRef.scala`, `Ref.scala` =
`kernel/shared/src/main/scala/cats/effect/kernel/Ref.scala`.

This module extends the Phase 5 mirror (`Model/Resource.lean`: `Res`, `allocatedCase`, `Clo`).
It does not change it. It reuses the `IO#guarantee` and `IO.bracketFull` mirror of track G
(`Model/Bracket.lean`) and the `GenSpawn#both` mirror of track R (`Model/Race.lean`).

```scala
private[effect] def fold[B](onOutput: A => F[B],                                    // :156-196
    onRelease: (ExitCase => F[Unit], ExitCase) => F[Unit])(implicit F: MonadCancel[F, Throwable]): F[B] = {
  ...
  @tailrec def loop[C](current: Resource[F, C], stack: Stack[C]): F[B] =
    current match {
      case Allocate(resource) =>
        F.bracketFull(resource) {
          case (a, _) => stack match {
            case Nil => onOutput(a)
            case Frame(head, tail) => continue(head(a), tail) } } {
          case ((_, release), outcome) => onRelease(release, ExitCase.fromOutcome(outcome)) }
      case Bind(source, fs) => loop(source, Frame(fs, stack))
      case Pure(v) => stack match {
        case Nil => onOutput(v)
        case Frame(head, tail) => loop(head(v), tail) }
      case Eval(fa) => fa.flatMap(a => continue(Resource.pure(a), stack))
    }
  loop(this, Nil)
}
def use[B](f: A => F[B])(implicit F: MonadCancel[F, Throwable]): F[B] = fold(f, _.apply(_))  // :207-208
def useEval[B](implicit ev: A <:< F[B], F: MonadCancel[F, Throwable]): F[B] = use(ev)        // :215-216
def use_(implicit F: MonadCancel[F, Throwable]): F[Unit] = use(_ => F.unit)                  // :230
def allocated[B >: A](implicit F: MonadCancel[F, Throwable]): F[(B, F[Unit])] =             // :550-552
  F.uncancelable(poll => poll(allocatedCase).map { case (b, fin) => (b, fin(ExitCase.Succeeded)) })
def both[B](that: Resource[F, B])(implicit F: Concurrent[F]): Resource[F, (A, B)] = {      // :286-314
  type Finalizer = Resource.ExitCase => F[Unit]
  type Update = (Finalizer => Finalizer) => F[Unit]
  def allocate[C](r: Resource[F, C], storeFinalizer: Update): F[C] =
    r.fold(_.pure[F], (release, _) => storeFinalizer(fin => ec => F.unit >> fin(ec).guarantee(release(ec))))
  val noop: Finalizer = _ => F.unit
  val bothFinalizers = F.ref((noop, noop))
  Resource.makeCase(bothFinalizers) { (finalizers, ec) =>
      finalizers.get.flatMap { case (thisFin, thatFin) => F.void(F.both(thisFin(ec), thatFin(ec))) }
    }.evalMap { store =>
      val thisStore: Update = f => store.update(_.bimap(f, identity))
      val thatStore: Update = f => store.update(_.bimap(identity, f))
      F.both(allocate(this, thisStore), allocate(that, thatStore))
    }
}
```

With `F = IO` (`IO.asyncForIO`, `IOAsync`): `F.bracketFull` = `IO.bracketFull` (`IO.scala:2062-2064`,
mirror `Bracket.bracketFullIO`); `x.guarantee(fin)` = `IO#guarantee` (`IO.scala:496-501`, mirror
`Bracket.guaranteeIO`); `F.both` = the kernel default `GenSpawn#both` (no `IOAsync` override,
mirror `Race.bothIO`); `F.ref(a)` = `IO.ref(a)` = `IO(Ref.unsafe(a))` (`IO.scala:2161`, `:1822`),
`Ref.unsafe` = `new SyncRef(a)` (`Ref.scala:314`); `get` = `F.delay(ar.get)` (`SyncRef.scala:30`);
`update(f)` = `F.delay(spin())` (`SyncRef.scala:65-73`; one model step is atomic, so the CAS
succeeds at once); `F.void(x)` = `x.void` = `x.map(_ => ())` (`IO.scala:2152`, `:961-962`);
`F.pure`/`_.pure[F]` = `Pure`; `F.unit >> fb` = `flatMap(unit)(_ => fb)` with `fb` by name
(`cats/syntax/flatMap.scala:54`); `makeCase(acquire)(release)` =
`applyCase(acquire.map(a => (a, e => release(a, e))))` (`Resource.scala:917-920`), `applyCase(r)` =
`applyFull(_ => r)` = `Allocate(_ => r)` (`:849-850`, `:879-880`); `evalMap(f)` =
`flatMap(a => Resource.eval(f(a)))` (`:558-559`); `bimap` on `Tuple2` = `(f(a), g(b))` (cats
`Bifunctor`); `ExitCase.fromOutcome` (`:1229-1234`).

## Encoding

* Library lambdas are `ULam` closures, `Codec.cloVal` namespace `ns` = 20 (odd ids).
* A `Res` value that a lambda captures (`this`, `that` of `both`) is a code `Val`; the caller
  gives its meaning (`UEnv.resOf`, as `ioOf` of `Bracket` and `srcIO` of `Race`).
* An `IO` value that a lambda captures or that a value holds (`rel(ec)` in `rel2`, the `F[Unit]` of
  `allocated`, the sides of `F.both`) is a source code (`USrc`), rebuilt by `srcU`. A release
  function application `rel(ec)` keeps a snapshot of the view (`snapU`): a user release function
  (`RelFn.user`) may read state; the rebuild runs the same pure Lean function on the same
  snapshot, so it gives the same program (the effects happened once, at the call).
* New function values `ExitCase => F[Unit]` (`e => release(a, e)` of `makeCase`, the finalizers
  of `both`) are `RelFn.user idx` with `idx` the id of a `ULam`. `UEnv.rx` (the `REnv` that the
  Phase 5 interpreter gets) runs them; all other `idx` are user code (`REnv.user`).
* The `evalMap` lambda of `both` is a `Bind` function id (a `ULam` id). `UEnv.rx.bind` runs it.
  Nested `both` (a side that is a `both`) is bounded by `bindDepth` (a model limit).

## Model limits

* `fold` has fuel `Resource.loopFuel` (as `allocatedCase`); out of fuel gives a program that never
  ends.
* The effects of `rel(ec)` and `release(ec)` in one lambda see the same view (as in all mirrors).
-/

namespace CatsEffectInLean.Model.ResourceUse

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Resource

/-- The `Codec.cloVal` namespace of this mirror (track Res: namespaces 20-29). -/
def ns : Nat := 20

/-! ## Descriptors -/

/-- `onOutput` of `fold`. -/
inductive OnOut where
  /-- A function value of the program (`f` of `use(f)`): function id `f`. -/
  | user (f : Nat)
  /-- `_.pure[F]` of `both`'s `allocate` (`Resource.scala:294`). -/
  | pure
  /-- `ev` of `useEval` (`A <:< F[B]`, the identity): the value is a `USrc` code; its program. -/
  | evalDesc
  /-- `_ => F.unit` of `use_` (`Resource.scala:230`). -/
  | unitFn
  deriving DecidableEq, Repr

def OnOut.toVal : OnOut → Val
  | .user f => .pair (.nat 0) (.nat f)
  | .pure => .pair (.nat 1) .unit
  | .evalDesc => .pair (.nat 2) .unit
  | .unitFn => .pair (.nat 3) .unit

def OnOut.ofVal : Val → Option OnOut
  | .pair (.nat 0) (.nat f) => some (.user f)
  | .pair (.nat 1) .unit => some .pure
  | .pair (.nat 2) .unit => some .evalDesc
  | .pair (.nat 3) .unit => some .unitFn
  | _ => none

/-- `onRelease` of `fold`. -/
inductive OnRel where
  /-- `_.apply(_)` of `use` (`Resource.scala:208`). -/
  | apply
  /-- `(release, _) => storeFinalizer(fin => ec => F.unit >> fin(ec).guarantee(release(ec)))` of
  `both`'s `allocate` (`Resource.scala:295`); `storeFinalizer` = `thisStore` (side 0) or
  `thatStore` (side 1) on `Ref` `ref` (`:309-310`). -/
  | store (ref : Val) (side : Nat)
  deriving DecidableEq, Repr

def OnRel.toVal : OnRel → Val
  | .apply => .pair (.nat 0) .unit
  | .store r s => .pair (.nat 1) (.pair r (.nat s))

def OnRel.ofVal : Val → Option OnRel
  | .pair (.nat 0) .unit => some .apply
  | .pair (.nat 1) (.pair r (.nat s)) => some (.store r s)
  | _ => none

/-- The lambdas of this mirror. -/
inductive ULam where
  /-- The `resource` function of an `Allocate` as a function value (`Poll[F] => F[(A, ExitCase =>
  F[Unit])]`), passed to `F.bracketFull` (`Resource.scala:174`). -/
  | allocFn (a : AllocFn)
  /-- `{ case (a, _) => stack match { ... } }` of `fold` (`Resource.scala:175-179`). -/
  | foldUse (stack : Stack) (onOut onRel : Val)
  /-- `{ case ((_, release), outcome) => onRelease(release, ExitCase.fromOutcome(outcome)) }`
  (`Resource.scala:181-182`). -/
  | foldRel (onRel : Val)
  /-- `a => continue(Resource.pure(a), stack)` of `fold` (`Resource.scala:193`). -/
  | foldEvalK (stack : Stack) (onOut onRel : Val)
  /-- `poll => poll(allocatedCase).map { ... }` of `allocated` (`Resource.scala:551-552`); `res`
  = code of `this`. -/
  | allocatedBody (res : Val)
  /-- `{ case (b, fin) => (b, fin(ExitCase.Succeeded)) }` (`Resource.scala:552`). -/
  | allocatedK
  /-- `_ => release(ec)` of `F.unit >> release(ec)` in `rel2` (`Resource.scala:490`). -/
  | unitThenK (rel : Val) (ec : Val)
  /-- `_ => resource` of `makeCase(bothFinalizers)` in `both` (`Resource.scala:301-302`,
  `:917-920`, `:849-850`): `resource = bothFinalizers.map(a => (a, e => release(a, e)))`. -/
  | bothAlloc
  /-- The thunk of `IO(Ref.unsafe((noop, noop)))` (`IO.scala:1822`, `Ref.scala:314`). -/
  | refNewThunk (a : Val)
  /-- `a => (a, e => release(a, e))` of `makeCase` (`Resource.scala:920`). -/
  | mcPair
  /-- `e => release(a, e)` with the `both` release
  `(finalizers, ec) => finalizers.get.flatMap { ... }` (`Resource.scala:302-307`); `ref` = `a`. -/
  | bothRel (ref : Val)
  /-- The thunk of `ref.get` = `F.delay(ar.get)` (`SyncRef.scala:30`). -/
  | getThunk (ref : Val)
  /-- `{ case (thisFin, thatFin) => F.void(F.both(thisFin(ec), thatFin(ec))) }` (`Resource.scala:304-305`). -/
  | bothRelK (ec : Val)
  /-- `_ => ()` of `void` (`IO.scala:961-962`). -/
  | voidK
  /-- The `evalMap` lambda `store => Resource.eval(F.both(allocate(this, thisStore),
  allocate(that, thatStore)))` (`Resource.scala:308-313`, `:558-559`), as a `Bind` function. -/
  | evalMapK (ra rb : Val)
  /-- The thunk of `store.update(_.bimap(g, identity))` (side 0) or `_.bimap(identity, g)`
  (side 1), `g = fin => ec => F.unit >> fin(ec).guarantee(release(ec))` (`Resource.scala:295`,
  `:309-310`, `SyncRef.scala:65-73`). -/
  | updateThunk (ref : Val) (side : Nat) (release : Val)
  /-- The finalizer `ec => F.unit >> fin(ec).guarantee(release(ec))` (`Resource.scala:295`). -/
  | storedFin (fin release : Val)
  /-- `_ => fin(ec).guarantee(release(ec))` of that `>>`. -/
  | storedFinK (fin release ec : Val)
  /-- Not Cats Effect code (fixed twin of CE-0020, decision 39): `_ => resource` of the fixed
  `makeCase(bothFinalizers)`. -/
  | fixBothAlloc
  /-- Not Cats Effect code: `a => (a, e => fixedRelease(a, e))`. -/
  | fixMcPair
  /-- Not Cats Effect code: `e => fixedRelease(a, e)` with `fixedRelease = (finalizers, ec) =>
  finalizers.get.flatMap { case (thisFin, thatFin) => F.both(thisFin(ec).attempt,
  thatFin(ec).attempt).flatMap { case (x, y) => F.fromEither(x) *> F.fromEither(y) } }`. -/
  | fixBothRel (ref : Val)
  /-- Not Cats Effect code: the `flatMap` function of `fixedRelease` after `get`. -/
  | fixBothRelK (ec : Val)
  /-- Not Cats Effect code: `{ case (x, y) => F.fromEither(x) *> F.fromEither(y) }`. -/
  | fixRethrow
  deriving DecidableEq, Repr

/-- The closure value (`Codec.cloVal`, namespace `ns`). -/
def ULam.toVal : ULam → Val
  | .allocFn a => cloVal ns 0 [allocFnToVal a]
  | .foldUse s o r => cloVal ns 1 [stackToVal s, o, r]
  | .foldRel r => cloVal ns 2 [r]
  | .foldEvalK s o r => cloVal ns 3 [stackToVal s, o, r]
  | .allocatedBody res => cloVal ns 5 [res]
  | .allocatedK => cloVal ns 6 []
  | .unitThenK rel ec => cloVal ns 7 [rel, ec]
  | .bothAlloc => cloVal ns 8 []
  | .refNewThunk a => cloVal ns 9 [a]
  | .mcPair => cloVal ns 10 []
  | .bothRel r => cloVal ns 11 [r]
  | .getThunk r => cloVal ns 12 [r]
  | .bothRelK ec => cloVal ns 13 [ec]
  | .voidK => cloVal ns 14 []
  | .evalMapK ra rb => cloVal ns 15 [ra, rb]
  | .updateThunk r s rel => cloVal ns 16 [r, .nat s, rel]
  | .storedFin fin rel => cloVal ns 17 [fin, rel]
  | .storedFinK fin rel ec => cloVal ns 18 [fin, rel, ec]
  | .fixBothAlloc => cloVal ns 30 []
  | .fixMcPair => cloVal ns 31 []
  | .fixBothRel r => cloVal ns 32 [r]
  | .fixBothRelK ec => cloVal ns 33 [ec]
  | .fixRethrow => cloVal ns 34 []

/-- The inverse of `ULam.toVal` on the tag and the fields. -/
def ULam.ofFields : Nat → List Val → Option ULam
  | 0, [a] => (allocFnOfVal a).map .allocFn
  | 1, [s, o, r] => (stackOfVal s).map (fun s => .foldUse s o r)
  | 2, [r] => some (.foldRel r)
  | 3, [s, o, r] => (stackOfVal s).map (fun s => .foldEvalK s o r)
  | 5, [res] => some (.allocatedBody res)
  | 6, [] => some .allocatedK
  | 7, [rel, ec] => some (.unitThenK rel ec)
  | 8, [] => some .bothAlloc
  | 9, [a] => some (.refNewThunk a)
  | 10, [] => some .mcPair
  | 11, [r] => some (.bothRel r)
  | 12, [r] => some (.getThunk r)
  | 13, [ec] => some (.bothRelK ec)
  | 14, [] => some .voidK
  | 15, [ra, rb] => some (.evalMapK ra rb)
  | 16, [r, .nat s, rel] => some (.updateThunk r s rel)
  | 17, [fin, rel] => some (.storedFin fin rel)
  | 18, [fin, rel, ec] => some (.storedFinK fin rel ec)
  | 30, [] => some .fixBothAlloc
  | 31, [] => some .fixMcPair
  | 32, [r] => some (.fixBothRel r)
  | 33, [ec] => some (.fixBothRelK ec)
  | 34, [] => some .fixRethrow
  | _, _ => none

/-- The closure id (odd). -/
def ULam.id (l : ULam) : Nat := 2 * valToNat l.toVal + 1

/-- The closure as a `Fn`. -/
def ULam.fn (l : ULam) : Fn := .user l.id

/-- The closure of an id, if it is one of this mirror. -/
def ULam.ofId? (id : Nat) : Option ULam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then ULam.ofFields tag fs else none
    | none => none
  else none

/-- A release function value made by this mirror (`RelFn.user` with a `ULam` id). -/
def ULam.rel (l : ULam) : RelFn := .user l.id

/-! ## Sources (`IO` values that a lambda captures) -/

/-- A view snapshot as a value: `Ref` cells, fiber outcomes, `Deferred` cells. -/
def snapU (v : View) : Val :=
  .pair (listV v.refs)
    (.pair (listV (v.outcomes.map fun o => match o with | some oc => .some oc.toVal | none => .none))
      (listV (v.deferreds.map fun d => match d with | some x => .some x | none => .none)))

/-- An outcome value back as an `Outcome`. -/
def outcomeOfVal? : Val → Option Outcome
  | .ocSucceeded v => some (.succeeded v)
  | .ocErrored e => some (.errored e)
  | .ocCanceled => some .canceled
  | _ => none

/-- The view of a snapshot. -/
def viewOfSnap (s : Val) : View :=
  match s with
  | .pair rs (.pair os ds) =>
    { refs := (unlistV rs).getD [],
      outcomes := ((unlistV os).getD []).map fun o => match o with | .some x => outcomeOfVal? x | _ => none,
      deferreds := ((unlistV ds).getD []).map fun d => match d with | .some x => some x | _ => none }
  | _ => {}

/-- Source codes (namespace `ns`, tags 50-52). -/
inductive USrc where
  /-- `rel(ec)`: release function `rel` (`RelFn.toVal`) applied to `ec`, view `snap`. -/
  | relApp (rel ec snap : Val)
  /-- `F.unit >> release(ec)` (`Resource.scala:490`). -/
  | unitThen (rel ec : Val)
  /-- `r.fold(onOutput, onRelease)` with `r` = `resOf res` (`both`'s `allocate`, `:292-296`). -/
  | fold (res onOut onRel : Val)
  /-- Not Cats Effect code (fixed twin): `src.attempt` (`IO.Attempt`). -/
  | attempt (src : Val)
  deriving DecidableEq, Repr

def USrc.toVal : USrc → Val
  | .relApp r ec s => cloVal ns 50 [r, ec, s]
  | .unitThen r ec => cloVal ns 51 [r, ec]
  | .fold res o r => cloVal ns 52 [res, o, r]
  | .attempt c => cloVal ns 53 [c]

def USrc.ofVal (c : Val) : Option USrc :=
  match ofCloVal c with
  | some (k, 50, [r, ec, s]) => if k == ns then some (.relApp r ec s) else none
  | some (k, 51, [r, ec]) => if k == ns then some (.unitThen r ec) else none
  | some (k, 52, [res, o, r]) => if k == ns then some (.fold res o r) else none
  | some (k, 53, [c]) => if k == ns then some (.attempt c) else none
  | _ => none

/-! ## The environment -/

/-- User code at the `Resource` level (`REnv`), and the meaning of `Res` codes. -/
structure UEnv where
  r : REnv
  /-- The `Res` value of a code (`this`/`that` of `both`, `this` of `allocated`). -/
  resOf : Val → Option Res

/-- Nesting bound of `both` inside a side of `both` (model limit). -/
def bindDepth : Nat := 8

/-- `ExitCase.fromOutcome` (`Resource.scala:1229-1234`). -/
def exitOfOutcome : Val → Val
  | .ocSucceeded _ => exitSucceeded
  | v => v

/-- `F.unit` (`Pure(())`). -/
def unitIO : IO := .pure .unit

private def ret (v : Val) (es : List UserEffect := []) : UserResult := { effects := es, out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }

/-- Apply a release function that this mirror made (`RelFn.user` with a `ULam` id). -/
def libRelApp (l : ULam) (ec : Val) : Option IO :=
  match l with
  -- `e => release(a, e)`: `finalizers.get.flatMap { ... }` (`Resource.scala:302-307`)
  | .bothRel r => some (.flatMap (.delay (ULam.getThunk r).fn) (ULam.bothRelK ec).fn)
  -- `ec => F.unit >> fin(ec).guarantee(release(ec))` (`Resource.scala:295`)
  | .storedFin fin rel => some (.flatMap unitIO (ULam.storedFinK fin rel ec).fn)
  -- not Cats Effect code (fixed twin): `finalizers.get.flatMap { ... }`
  | .fixBothRel r => some (.flatMap (.delay (ULam.getThunk r).fn) (ULam.fixBothRelK ec).fn)
  | _ => none

/-- `rel(ec)`: apply a release function value (`ExitCase => F[Unit]`). Effects, then the program
or the throw. `.guarantee` is `rel2` (`Resource.scala:490`):
`(ec: ExitCase) => rel(ec).guarantee(F.unit >> release(ec))`; `rel(ec)` is called now (a strict
receiver), `release(ec)` later (by name). -/
def applyRelX (r : REnv) (v : View) : RelFn → Val → List UserEffect × Except Err IO
  | .unit, _ => ([], .ok unitIO)
  | .const k a, _ => ([], r.release k a)
  | .user idx, ec =>
    match (ULam.ofId? idx).bind (libRelApp · ec) with
    | some p => ([], .ok p)
    | none => progOf (r.user.callV idx ec v)
  | .guarantee rel release, ec =>
    let (es, p) := applyRelX r v rel ec
    (es, p.map fun _ =>
      Bracket.guaranteeIO (.ext (USrc.relApp rel.toVal ec (snapU v)).toVal)
        (.ext (USrc.unitThen release.toVal ec).toVal))

/-- The user code of the `Resource` level as the interpreter sees it: the release functions and
`Allocate` functions of this mirror run as the mirror (`RelFn.user` / `AllocFn.user` with a
`ULam` id); other ids are user code. -/
def idxCall (u : UserEnv) (idx : Nat) (arg : Val) (v : View) : UserResult :=
  match ULam.ofId? idx with
  -- `_ => resource` of `makeCase` (`Resource.scala:849-850`, `:917-920`, `:299`):
  -- `IO(Ref.unsafe((noop, noop))).map(a => (a, e => release(a, e)))`
  | some .bothAlloc =>
    prog (.map (.delay (ULam.refNewThunk (.pair RelFn.unit.toVal RelFn.unit.toVal)).fn) ULam.mcPair.fn)
  | some .fixBothAlloc =>
    prog (.map (.delay (ULam.refNewThunk (.pair RelFn.unit.toVal RelFn.unit.toVal)).fn) ULam.fixMcPair.fn)
  | some l =>
    match libRelApp l arg with
    | some p => prog p
    | none => u.callV idx arg v
  | none => u.callV idx arg v

/-- The user environment `REnv.user` with this mirror's function values. -/
def idxEnv (u : UserEnv) : UserEnv where
  call idx arg refs := idxCall u idx arg { refs }
  callV := idxCall u


/-! ## `fold` -/

/-- The `onOutput` call of `fold`, for a value `a`: effects, then the program or the throw. `uc`
calls a function of the program (`OnOut.user`). -/
def outCall (uc : Nat → Val → View → UserResult) (srcR : Val → IO) (o : Val) (a : Val) (v : View) :
    List UserEffect × Except Err IO :=
  match OnOut.ofVal o with
  | some (.user f) => progOf (uc f a v)
  -- `_.pure[F]` = `IO.pure(a)`
  | some .pure => ([], .ok (.pure a))
  -- `ev(a)`: the identity; the value is a `USrc` code of the program
  | some .evalDesc => ([], .ok (srcR a))
  -- `(_ => F.unit)(a)` = `Pure(())`
  | some .unitFn => ([], .ok unitIO)
  | none => ([], .error illTyped)

/-- `loop(current, stack)` of `fold` (`Resource.scala:171-194`), branch order as in Scala.
`bind` runs `Bind` functions, `out` is the `onOutput` call. `Except.error e`: a `Bind` function
or `onOutput` threw. -/
def foldLoop (bind : Nat → Val → Except Err Res) (out : Val → List UserEffect × Except Err IO)
    (onOut onRel : Val) : (fuel : Nat) → Res → Stack → List UserEffect × Except Err IO
  | 0, _, _ => ([], .ok spinIO)
  -- `case Allocate(resource) => F.bracketFull(resource) { ... } { ... }` (`:173-183`)
  | _ + 1, .allocate a, stack =>
    ([], .ok (Bracket.bracketFullIO (ULam.allocFn a).id (ULam.foldUse stack onOut onRel).id
      (ULam.foldRel onRel).id))
  -- `case Bind(source, fs) => loop(source, Frame(fs, stack))` (`:184-185`)
  | f + 1, .bind source fs, stack => foldLoop bind out onOut onRel f source (fs :: stack)
  -- `case Pure(v) => stack match { case Nil => onOutput(v)` (`:186-188`)
  | _ + 1, .pure v, [] => out v
  -- `case Frame(head, tail) => loop(head(v), tail)` (`:189-190`)
  | f + 1, .pure v, head :: tail =>
    match bind head v with
    | .ok res => foldLoop bind out onOut onRel f res tail
    | .error e => ([], .error e)
  -- `case Eval(fa) => fa.flatMap(a => continue(Resource.pure(a), stack))` (`:192-193`)
  | _ + 1, .eval fa, stack => ([], .ok (.flatMap fa (ULam.foldEvalK stack onOut onRel).fn))

/-- A rebuilt release program (`USrc.relApp`, `USrc.unitThen`). -/
def srcRel (r : REnv) (c : Val) : IO :=
  match USrc.ofVal c with
  | some (.relApp rel ec snap) =>
    match RelFn.ofVal rel with
    | some f =>
      match (applyRelX r (viewOfSnap snap) f ec).2 with
      | .ok p => p
      | .error e => .error e
    | none => .error illTyped
  -- `F.unit >> release(ec)` = `FlatMap(Pure(()), _ => release(ec))`
  | some (.unitThen rel ec) => .flatMap unitIO (ULam.unitThenK rel ec).fn
  -- not Cats Effect code (fixed twin): `rel(ec).attempt`
  | some (.attempt c) =>
    match USrc.ofVal c with
    | some (.relApp rel ec snap) =>
      match RelFn.ofVal rel with
      | some f =>
        match (applyRelX r (viewOfSnap snap) f ec).2 with
        | .ok p => .attempt p
        | .error e => .error e
      | none => .error illTyped
    | _ => .error illTyped
  | _ => .error illTyped

/-- `onOutput` of a rebuilt `fold` (only `_.pure[F]` of `both` is rebuilt). -/
def outPure (a : Val) : List UserEffect × Except Err IO := ([], .ok (.pure a))

/-- The `evalMap` lambda of `both` as a `Bind` function (`Resource.scala:308-313`):
`F.both(allocate(this, thisStore), allocate(that, thatStore))` is built now (strict arguments),
so `fold` runs now on both sides; a throw of a `Bind` function of a side is a throw of this
lambda. Then `Resource.eval(...)`. -/
def evalMapRes (resOf : Val → Option Res) (bind : Nat → Val → Except Err Res) (ra rb store : Val) :
    Except Err Res :=
  let side (res : Val) (s : Nat) : Except Err Unit :=
    match resOf res with
    | some r =>
      match (foldLoop bind outPure OnOut.pure.toVal (OnRel.store store s).toVal loopFuel r []).2 with
      | .ok _ => .ok ()
      | .error e => .error e
    | none => .error illTyped
  match side ra 0, side rb 1 with
  | .error e, _ => .error e
  | .ok _, .error e => .error e
  | .ok _, .ok _ =>
    .ok (.eval (Race.bothIO (USrc.fold ra OnOut.pure.toVal (OnRel.store store 0).toVal).toVal
      (USrc.fold rb OnOut.pure.toVal (OnRel.store store 1).toVal).toVal))

/-- `Bind` functions: the `evalMap` lambda of `both` runs as the mirror, other ids are user code.
`n` bounds the nesting of `both` in a side of `both` (model limit `bindDepth`). -/
def bindN (U : UEnv) : Nat → Nat → Val → Except Err Res
  | 0, k, a =>
    match ULam.ofId? k with
    | some (.evalMapK _ _) => .error illTyped
    | _ => U.r.bind k a
  | n + 1, k, a =>
    match ULam.ofId? k with
    | some (.evalMapK ra rb) => evalMapRes U.resOf (bindN U n) ra rb a
    | _ => U.r.bind k a

/-- The `REnv` that the Phase 5 interpreter (`Resource.loop`, `Resource.cloCall`) gets: user code
plus this mirror's function values and `Bind` functions. -/
def UEnv.rx (U : UEnv) : REnv :=
  { user := idxEnv U.r.user, bind := bindN U bindDepth, acquire := U.r.acquire, release := U.r.release }

/-- Rebuild a source (`Bracket` `ioOf`, `Race` `srcIO`). -/
def srcU (U : UEnv) (c : Val) : IO :=
  match USrc.ofVal c with
  | some (.fold res o rl) =>
    match U.resOf res, OnOut.ofVal o with
    | some r, some .pure =>
      match (foldLoop U.rx.bind outPure o rl loopFuel r []).2 with
      | .ok p => p
      | .error e => .error e
    | _, _ => .error illTyped
  | some _ => srcRel U.rx c
  | none => .error illTyped

/-- `r.fold(onOutput, onRelease)` (`Resource.scala:156-196`) at build time. -/
def foldIO (U : UEnv) (uc : Nat → Val → View → UserResult) (onOut onRel : Val) (r : Res) (v : View) :
    List UserEffect × Except Err IO :=
  foldLoop U.rx.bind (fun a => outCall uc (srcRel U.rx) onOut a v) onOut onRel loopFuel r []

/-- `r.use(f)` (`Resource.scala:207-208`): `fold(f, _.apply(_))`. -/
def useIO (U : UEnv) (uc : Nat → Val → View → UserResult) (f : Nat) (r : Res) (v : View) :
    List UserEffect × Except Err IO :=
  foldIO U uc (OnOut.user f).toVal OnRel.apply.toVal r v

/-- `r.use_` (`Resource.scala:230`): `use(_ => F.unit)`. -/
def useUnitIO (U : UEnv) (uc : Nat → Val → View → UserResult) (r : Res) (v : View) :
    List UserEffect × Except Err IO :=
  foldIO U uc OnOut.unitFn.toVal OnRel.apply.toVal r v

/-- `r.useEval` (`Resource.scala:215-216`): `use(ev)`, `ev` the identity on `F[B]` values (`USrc`
codes). -/
def useEvalIO (U : UEnv) (uc : Nat → Val → View → UserResult) (r : Res) (v : View) :
    List UserEffect × Except Err IO :=
  foldIO U uc OnOut.evalDesc.toVal OnRel.apply.toVal r v

/-- `r.allocated` (`Resource.scala:550-552`); `res` = code of `r` (`UEnv.resOf`). -/
def allocatedIO (res : Val) : IO := .uncancelable (ULam.allocatedBody res).fn

/-- `this.both(that)` (`Resource.scala:286-314`) as a `Res`; `ra`, `rb` = codes of `this`, `that`.
`Resource.makeCase(bothFinalizers)(...)` = `Allocate(_ => resource)` (`ULam.bothAlloc`, a
`REnv`-level function), `.evalMap(...)` = `Bind(_, evalMapK)`. -/
def bothRes (ra rb : Val) : Res := .bind (.allocate (.user ULam.bothAlloc.id)) (ULam.evalMapK ra rb).id

/-- Not Cats Effect code. The fixed twin of `both` (CE-0020, decision 39): the release runs the
two finalizer chains with `attempt`, so an error of one chain does not cancel the other, and
raises the first error after both ended. The `evalMap` part is the same as `both`. -/
def fixedBothRes (ra rb : Val) : Res := .bind (.allocate (.user ULam.fixBothAlloc.id)) (ULam.evalMapK ra rb).id

/-! ## The closures -/

/-- A result with effects. -/
def withEff (es : List UserEffect) : Except Err IO → UserResult
  | .ok p => { effects := es, out := .prog p }
  | .error e => { effects := es, out := .throw e }

private def throwI : UserResult := { out := .throw illTyped }

/-- Run closure `l` on `arg` with view `v`. `uc` calls a function of the program (`onOutput` of
`use`). -/
def callU (U : UEnv) (uc : Nat → Val → View → UserResult) (l : ULam) (arg : Val) (v : View) : UserResult :=
  match l with
  -- `resource(poll)`: the `Allocate` function (`F.bracketFull(resource)`, `Resource.scala:174`)
  | .allocFn (.user idx) => U.rx.user.callV idx arg v
  -- `make`: `_ => acquire.map(a => a -> release(a)).map { ... }` (`Resource.scala:826-902`)
  | .allocFn (.make acq rel) =>
    prog (.map (.map (U.r.acquire acq) (cloFn (.makePair rel))) (cloFn .applyPair))
  -- `{ case (a, _) => stack match { case Nil => onOutput(a);
  --   case Frame(head, tail) => continue(head(a), tail) } }` (`Resource.scala:175-179`)
  | .foldUse stack onOut onRel =>
    match arg with
    | .pair a _ =>
      match stack with
      | [] => let (es, p) := outCall uc (srcRel U.rx) onOut a v; withEff es p
      | head :: tail =>
        match U.rx.bind head a with
        | .ok res =>
          let (es, p) := foldLoop U.rx.bind (fun x => outCall uc (srcRel U.rx) onOut x v) onOut onRel
            loopFuel res tail
          withEff es p
        | .error e => { out := .throw e }
    | _ => throwI
  -- `{ case ((_, release), outcome) => onRelease(release, ExitCase.fromOutcome(outcome)) }`
  | .foldRel onRel =>
    match arg, OnRel.ofVal onRel with
    | .pair (.pair _ relV) oc, some o =>
      match RelFn.ofVal relV, o with
      -- `_.apply(_)` of `use`: `release(ec)`
      | some rel, .apply => let (es, p) := applyRelX U.rx v rel (exitOfOutcome oc); withEff es p
      -- `storeFinalizer(fin => ec => ...)` = `store.update(_.bimap(...))` = `F.delay(spin())`
      | some _, .store ref side => prog (.delay (ULam.updateThunk ref side relV).fn)
      | none, _ => throwI
    | _, _ => throwI
  -- `a => continue(Resource.pure(a), stack)` (`Resource.scala:193`)
  | .foldEvalK stack onOut onRel =>
    let (es, p) := foldLoop U.rx.bind (fun x => outCall uc (srcRel U.rx) onOut x v) onOut onRel
      loopFuel (.pure arg) stack
    withEff es p
  -- `poll => poll(allocatedCase).map { ... }` (`Resource.scala:551-552`)
  | .allocatedBody res =>
    match arg, U.resOf res with
    | .poll m p, some r =>
      match allocatedCase U.rx r with
      | .ok io => prog (.map (IO.applyPoll io m p) ULam.allocatedK.fn)
      | .error e => { out := .throw e }
    | _, _ => throwI
  -- `{ case (b, fin) => (b, fin(ExitCase.Succeeded)) }`: `fin(...)` is called now; the `F[Unit]`
  -- value is its source code
  | .allocatedK =>
    match arg with
    | .pair b finV =>
      match RelFn.ofVal finV with
      | some fin =>
        let (es, p) := applyRelX U.rx v fin exitSucceeded
        match p with
        | .ok _ => ret (.pair b (USrc.relApp finV exitSucceeded (snapU v)).toVal) es
        | .error e => { effects := es, out := .throw e }
      | none => throwI
    | _ => throwI
  -- `_ => release(ec)` (`Resource.scala:490`)
  | .unitThenK relV ec =>
    match RelFn.ofVal relV with
    | some rel => let (es, p) := applyRelX U.rx v rel ec; withEff es p
    | none => throwI
  | .bothAlloc => U.rx.user.callV ULam.bothAlloc.id arg v
  | .fixBothAlloc => U.rx.user.callV ULam.fixBothAlloc.id arg v
  | .fixMcPair => ret (.pair arg (ULam.fixBothRel arg).rel.toVal)
  -- not Cats Effect code: `F.both(thisFin(ec).attempt, thatFin(ec).attempt).flatMap(rethrow)`
  | .fixBothRelK ec =>
    match arg with
    | .pair thisV thatV =>
      match RelFn.ofVal thisV, RelFn.ofVal thatV with
      | some thisFin, some thatFin =>
        let (es1, p1) := applyRelX U.rx v thisFin ec
        match p1 with
        | .error e => { effects := es1, out := .throw e }
        | .ok _ =>
          let (es2, p2) := applyRelX U.rx v thatFin ec
          match p2 with
          | .error e => { effects := es1 ++ es2, out := .throw e }
          | .ok _ =>
            { effects := es1 ++ es2,
              out := .prog (.flatMap (Race.bothIO
                (USrc.attempt (USrc.relApp thisV ec (snapU v)).toVal).toVal
                (USrc.attempt (USrc.relApp thatV ec (snapU v)).toVal).toVal) ULam.fixRethrow.fn) }
      | _, _ => throwI
    | _ => throwI
  | .fixRethrow =>
    match arg with
    | .pair (.left (.err e)) _ => prog (.error e)
    | .pair _ (.left (.err e)) => prog (.error e)
    | .pair _ _ => prog unitIO
    | _ => throwI
  -- `Ref.unsafe(a)` (`Ref.scala:314`): a new cell; its id is the number of cells before it
  | .refNewThunk a => ret (.ref v.refs.length) [.allocRef a]
  -- `a => (a, e => release(a, e))` (`Resource.scala:920`)
  | .mcPair => ret (.pair arg (ULam.bothRel arg).rel.toVal)
  | .bothRel _ | .storedFin _ _ | .fixBothRel _ =>
    match libRelApp l arg with
    | some p => prog p
    | none => throwI
  -- `ar.get` (`SyncRef.scala:30`)
  | .getThunk (.ref i) =>
    match v.refs[i]? with
    | some x => ret x
    | none => throwI
  | .getThunk _ => throwI
  -- `{ case (thisFin, thatFin) => F.void(F.both(thisFin(ec), thatFin(ec))) }`: both calls now
  | .bothRelK ec =>
    match arg with
    | .pair thisV thatV =>
      match RelFn.ofVal thisV, RelFn.ofVal thatV with
      | some thisFin, some thatFin =>
        let (es1, p1) := applyRelX U.rx v thisFin ec
        match p1 with
        | .error e => { effects := es1, out := .throw e }
        | .ok _ =>
          let (es2, p2) := applyRelX U.rx v thatFin ec
          match p2 with
          | .error e => { effects := es1 ++ es2, out := .throw e }
          | .ok _ =>
            { effects := es1 ++ es2,
              out := .prog (.map (Race.bothIO (USrc.relApp thisV ec (snapU v)).toVal
                (USrc.relApp thatV ec (snapU v)).toVal) ULam.voidK.fn) }
      | _, _ => throwI
    | _ => throwI
  | .voidK => ret .unit
  -- a `Bind` function, not a program function
  | .evalMapK _ _ => throwI
  -- `spin()` of `update(f)` with `f = _.bimap(g, identity)` / `_.bimap(identity, g)`
  | .updateThunk (.ref i) side relV =>
    match v.refs[i]? with
    | some (.pair t u) =>
      let nv := if side == 0 then Val.pair (ULam.storedFin t relV).rel.toVal u
        else Val.pair t (ULam.storedFin u relV).rel.toVal
      ret .unit [.writeRef i nv]
    | _ => throwI
  | .updateThunk _ _ _ => throwI
  -- `fin(ec).guarantee(release(ec))`: receiver first, then the argument
  | .storedFinK finV relV ec =>
    match RelFn.ofVal finV, RelFn.ofVal relV with
    | some fin, some rel =>
      let (es1, p1) := applyRelX U.rx v fin ec
      match p1 with
      | .error e => { effects := es1, out := .throw e }
      | .ok _ =>
        let (es2, p2) := applyRelX U.rx v rel ec
        match p2 with
        | .error e => { effects := es1 ++ es2, out := .throw e }
        | .ok _ =>
          { effects := es1 ++ es2,
            out := .prog (Bracket.guaranteeIO (.ext (USrc.relApp finV ec (snapU v)).toVal)
              (.ext (USrc.relApp relV ec (snapU v)).toVal)) }
    | _, _ => throwI

/-! ## Dispatch -/

/-- Library closures except `Bracket`: this mirror, `Race`, and the Phase 5 `Resource` closures
(`Clo`, with `UEnv.rx`); all other ids go to `uc`. -/
def uDisp (U : UEnv) (uc : Nat → Val → View → UserResult) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match ULam.ofId? id with
  | some l => callU U uc l arg v
  | none =>
    match Race.ofId? id with
    | some l => Race.call (srcU U) l arg v
    | none =>
      if isLibId id then
        match (cloOfId id).bind Clo.ofVal with
        | some c => cloCall U.rx c arg v
        | none => uc id arg v
      else uc id arg v

/-- All closures: `Bracket` (its user-function calls go to `uDisp`), then `uDisp`. -/
def resDisp (U : UEnv) (uc : Nat → Val → View → UserResult) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match Bracket.BLam.ofId? id with
  | some l => Bracket.call (uDisp U uc) (srcU U) l arg v
  | none => uDisp U uc id arg v

/-- Program-level user code of `U`: function `k` of `REnv.user` has id `2 * k` (`uid k`). -/
def UEnv.userCall (U : UEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  if id % 2 == 0 then U.r.user.callV (id / 2) arg v else { out := .throw illTyped }

/-- The `UserEnv` of a program that uses this mirror. -/
def UEnv.toEnv (U : UEnv) : UserEnv where
  call id arg refs := resDisp U U.userCall id arg { refs }
  callV := resDisp U U.userCall

/-- The library closures (`WellFormed`): this mirror, `Race`, `Bracket`, Phase 5 `Resource`. -/
def isLib (id : Nat) : Bool :=
  (ULam.ofId? id).isSome || (Race.ofId? id).isSome || (Bracket.BLam.ofId? id).isSome || Resource.isLib id

end CatsEffectInLean.Model.ResourceUse

import CatsEffectInLean.Model.Codec

/-!
# `IO#guarantee`, `IO#guaranteeCase`, `IO#bracket*`, `IO.bracketFull` and the kernel twins (mirror)

Phase 6, track G. `IO.scala` = `core/shared/src/main/scala/cats/effect/IO.scala`, `K/MonadCancel.scala`
= `kernel/shared/src/main/scala/cats/effect/kernel/MonadCancel.scala`, both at `v3.7.1`.

```scala
def guarantee(finalizer: IO[Unit]): IO[A] =                                    // IO.scala:496-501
  IO uncancelable { poll =>
    val onError: PartialFunction[Throwable, IO[Unit]] = { case _ => finalizer.reportError }
    poll(this).onCancel(finalizer).onError(onError).flatTap(_ => finalizer)
  }

def guaranteeCase(finalizer: OutcomeIO[A] => IO[Unit]): IO[A] =               // IO.scala:523-530
  IO.uncancelable { poll =>
    val finalized = poll(this).onCancel(finalizer(Outcome.canceled))
    val onError: PartialFunction[Throwable, IO[Unit]] = {
      case e => finalizer(Outcome.errored(e)).reportError
    }
    finalized.onError(onError).flatTap { (a: A) => finalizer(Outcome.succeeded(IO.pure(a))) }
  }

def bracket[B](use: A => IO[B])(release: A => IO[Unit]): IO[B] =              // IO.scala:338-339
  bracketCase(use)((a, _) => release(a))

def bracketCase[B](use: A => IO[B])(release: (A, OutcomeIO[B]) => IO[Unit]): IO[B] =  // :370-371
  IO.bracketFull(_ => this)(use)(release)

def bracketFull[A, B](acquire: Poll[IO] => IO[A])(use: A => IO[B])(            // IO.scala:1826-1830
    release: (A, OutcomeIO[B]) => IO[Unit]): IO[B] =
  IO.uncancelable { poll =>
    acquire(poll).flatMap { a => IO.defer(poll(use(a))).guaranteeCase(release(a, _)) }
  }

private[effect] def reportError(implicit ev: A <:< Unit): IO[Unit] =          // IO.scala:967-972
  asInstanceOf[IO[Unit]].handleErrorWith { t =>
    IO.executionContext.flatMap(ec => IO(ec.reportFailure(t)))
  }
```

Helpers: `onError(pf) = handleErrorWith(t => pf.applyOrElse(t, (_: Throwable) => IO.unit) *>
IO.raiseError(t))` (`IO.scala:605-606`); `flatTap(f) = flatMap(a => f(a).as(a))` (`IO.scala:474`);
`as(b) = map(_ => b)` (`IO.scala:182-183`); `*> = productR = flatMap(_ => that)`
(`IO.scala:138-139`, `903-904`; `that` is a strict argument); `onCancel` = `OnCancel`
(`IO.scala:590-591`); `IO.uncancelable` = `Uncancelable` (`IO.scala:1712-1713`); `poll(io)` =
`UnmaskRunLoop` (`IOFiber.scala:564-567`, `IO.applyPoll`); `IO.defer(t) = delay(t).flatten`
= `Delay(t).flatMap(ev)` (`IO.scala:1296-1297`, `472`); `IO.executionContext` = `ReadEC`
(`IO.scala:1551`); `IO(x)` = `Delay` (`IO.scala:1275`).

The kernel defaults (`MonadCancel.Default` twins), instantiated with the `IO.asyncForIO`
operations (`IOAsync`, `IO.scala:1996`):

```scala
def guarantee[A](fa: F[A], fin: F[Unit]): F[A] = guaranteeCase(fa)(_ => fin)     // K:344-345
def guaranteeCase[A](fa: F[A])(fin: Outcome[F, E, A] => F[Unit]): F[A] =         // K:365-372
  uncancelable { poll =>
    val finalized = onCancel(poll(fa), fin(Outcome.canceled))
    val handled = onError(finalized) { case e => handleError(fin(Outcome.errored(e)))(_ => ()) }
    flatTap(handled)(a => fin(Outcome.succeeded(pure(a))))
  }
def bracketFull[A, B](acquire: Poll[F] => F[A])(use: A => F[B])(                 // K:447-456
    release: (A, Outcome[F, E, B]) => F[Unit]): F[B] =
  uncancelable { poll =>
    acquire(poll).flatMap { a => guaranteeCase(poll(unit >> use(a)))(release(a, _)) }
  }
```

With `F = IO`: `guaranteeCase` (virtual) is the `IOAsync` override = `IO#guaranteeCase`
(`IO.scala:2026-2027`); `onError` = `IO#onError` (`IO.scala:2032-2033`); `handleError` =
`IO#handleError` (`IO.scala:2029-2030`, `532-533`); `flatTap` is not overridden: cats
`FlatMap.flatTap = flatMap(fa)(a => as(f(a), a))` (`cats/FlatMap.scala:172-173`, cats-core 2.13.0)
with `as` = `IO#as`; `unit >> fb` = `F.flatMap(unit)(_ => fb)` with `fb` by name
(`cats/syntax/flatMap.scala:54`); `unit` = `Pure(())`. `IOAsync` overrides `guarantee`,
`guaranteeCase` and `bracketFull`, not `bracket`/`bracketCase`; their kernel defaults
(`K:397-398`, `K:423-425`) call the virtual `bracketFull`, so for `IO` they build the same
closures as `IO#bracket`/`IO#bracketCase` (`_ => acquire`, `(a, _) => release(a)`).

## Encoding

* Each Scala lambda is a library closure `BLam` (odd id, `Codec.libFn`, namespace `ns`).
* An `IO` value that a lambda captures (`this`, `finalizer` of `guarantee`) is a source code
  `Val` (`Src`). `Src.ext s` is a program of the caller: the caller gives `ioOf : Val → IO`
  (as `Timeout.srcIO`). The other `Src` cases are terms that this mirror builds itself.
* A user function (`finalizer` of `guaranteeCase`, `acquire`, `use`, `release`) is a function
  id (`Nat`). The library closure calls it in its own body, as Scala does: `uc id arg view`
  (the caller passes `env.callV`). The effects of that call come first; a throw of the user
  function is a throw of the closure (the run loop catches it, `IOFiber.scala`). A two-argument
  function `release(a, oc)` gets the argument `Val.pair a oc`.
* `Outcome.canceled` is `Val.ocCanceled`, `Outcome.errored(e)` is `Val.ocErrored e`,
  `Outcome.succeeded(IO.pure(a))` is `Val.ocSucceeded a` (`Outcome.toVal`).
* `IO.defer(poll(use(a)))`: a `Val` cannot hold an `IO`, so the thunk returns the marker `unit`,
  and `ev` (`deferEv`) calls `use(a)` and applies `poll`. The run loop runs `FlatMap` over
  `Delay` as `f(thunk())` in one `try` in one iteration (`IOFiber.scala:420-437`, `Step.lean`),
  so the user call has the same view, the same effects and the same error handling.
-/

namespace CatsEffectInLean.Model.Bracket

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of these closures in `Codec.cloVal` (queue 1, timeout 2, difftest 3). -/
def ns : Nat := 7

/-- The source of an `IO` value that a closure captures. -/
inductive Src where
  /-- A program of the caller, built by `ioOf s`. -/
  | ext (s : Val)
  /-- `IO.defer(poll(use(a)))` of `IO.bracketFull` (`IO.scala:1829`). -/
  | deferUse (use : Nat) (a : Val) (m p : Nat)
  /-- `poll(unit >> use(a))` of the kernel `bracketFull` (`K/MonadCancel.scala:454`). -/
  | pollUnitThen (use : Nat) (a : Val) (m p : Nat)
  /-- Not Cats Effect code: `poll(IO.defer(use(a)))` of the fixed twin `fixedBracketFullIO`
  (decision 39, CE-0005). -/
  | pollDefer (use : Nat) (a : Val) (m p : Nat)
  deriving DecidableEq, Repr

/-- The code of a source. -/
def Src.toVal : Src → Val
  | .ext s => .left s
  | .deferUse use a m p => .right (cloVal ns 100 [.nat use, a, .poll m p])
  | .pollUnitThen use a m p => .right (cloVal ns 101 [.nat use, a, .poll m p])
  | .pollDefer use a m p => .right (cloVal ns 102 [.nat use, a, .poll m p])

/-- The inverse of `Src.toVal`. -/
def Src.ofVal : Val → Option Src
  | .left s => some (.ext s)
  | .right c =>
    match ofCloVal c with
    | some (k, 100, [.nat use, a, .poll m p]) => if k == ns then some (.deferUse use a m p) else none
    | some (k, 101, [.nat use, a, .poll m p]) => if k == ns then some (.pollUnitThen use a m p) else none
    | some (k, 102, [.nat use, a, .poll m p]) => if k == ns then some (.pollDefer use a m p) else none
    | _ => none
  | _ => none

/-- The lambdas. Fields: `src`/`fin` = source codes (`Src.toVal`), `k`/`acq`/`use`/`rel` = user
function ids, `m p` = a `poll`, `e` = an error, `a` = a value. -/
inductive BLam where
  /-- `poll => ...` of `IO#guarantee` (`IO.scala:497-501`). -/
  | gBody (src fin : Val)
  /-- `t => pf.applyOrElse(t, ...) *> IO.raiseError(t)` of `onError` (`IO.scala:605-606`) in
  `IO#guarantee`, with `pf = { case _ => finalizer.reportError }` (`IO.scala:499`). -/
  | gOnError (fin : Val)
  /-- `a => (_ => finalizer)(a).as(a)` of `flatTap(_ => finalizer)` (`IO.scala:474`, `500`). -/
  | gTap (fin : Val)
  /-- `_ => that` of `*>` with `that = IO.raiseError(t)` (`IO.scala:606`). -/
  | raiseK (e : Err)
  /-- `_ => b` of `as(b)` (`IO.scala:182-183`). -/
  | asK (a : Val)
  /-- `t => IO.executionContext.flatMap(...)` of `reportError` (`IO.scala:969-971`). -/
  | reportK
  /-- `ec => IO(ec.reportFailure(t))` (`IO.scala:970`). -/
  | reportEc (e : Err)
  /-- The thunk `ec.reportFailure(t)` (`IO.scala:970`). -/
  | reportThunk (e : Err)
  /-- `poll => ...` of `IO#guaranteeCase` (`IO.scala:524-529`). -/
  | gcBody (src : Val) (k : Nat)
  /-- `onError` function of `IO#guaranteeCase`, with
  `pf = { case e => finalizer(Outcome.errored(e)).reportError }` (`IO.scala:526-528`, `605-606`). -/
  | gcOnError (k : Nat)
  /-- `(a: A) => finalizer(Outcome.succeeded(IO.pure(a)))` inside `flatTap` (`IO.scala:529`, `474`). -/
  | gcTap (k : Nat)
  /-- `poll => acquire(poll).flatMap { ... }` of `IO.bracketFull` (`IO.scala:1828-1829`). -/
  | bfBody (acq use rel : Nat)
  /-- `a => IO.defer(poll(use(a))).guaranteeCase(release(a, _))` (`IO.scala:1829`). -/
  | bfK (use rel m p : Nat)
  /-- The thunk of `IO.defer(poll(use(a)))` (`IO.scala:1296-1297`): returns the marker `unit`. -/
  | deferThunk
  /-- `ev` of `flatten` (`IO.scala:472`) in that `IO.defer`, with the thunk's work
  `poll(use(a))` (module doc). -/
  | deferEv (use : Nat) (a : Val) (m p : Nat)
  /-- `release(a, _)`: `oc => release(a, oc)` (`IO.scala:1829`, `K/MonadCancel.scala:454`). -/
  | relA (rel : Nat) (a : Val)
  /-- `_ => this` of `IO#bracketCase` (`IO.scala:371`). -/
  | constThis (src : Val)
  /-- `(a, _) => release(a)` of `IO#bracket` (`IO.scala:339`) and `MonadCancel#bracket`
  (`K/MonadCancel.scala:398`). -/
  | dropOc (rel : Nat)
  /-- `_ => fin` of the kernel `guarantee` (`K/MonadCancel.scala:345`). -/
  | constFin (fin : Val)
  /-- `poll => ...` of the kernel `guaranteeCase` (`K/MonadCancel.scala:366-371`). -/
  | dgcBody (src : Val) (k : Nat)
  /-- `IO#onError` function (`IO.scala:605-606`) with the kernel
  `pf = { case e => handleError(fin(Outcome.errored(e)))(_ => ()) }` (`K/MonadCancel.scala:368-369`). -/
  | dgcOnError (k : Nat)
  /-- `t => IO.pure(f(t))` of `IO#handleError` (`IO.scala:532-533`) with `f = _ => ()`. -/
  | unitH
  /-- `a => as(fin(Outcome.succeeded(pure(a))), a)` of cats `flatTap` (`cats/FlatMap.scala:172-173`,
  `K/MonadCancel.scala:370`). -/
  | dgcTap (k : Nat)
  /-- `poll => acquire(poll).flatMap { ... }` of the kernel `bracketFull` (`K/MonadCancel.scala:450-455`). -/
  | dbfBody (acq use rel : Nat)
  /-- `a => guaranteeCase(poll(unit >> use(a)))(release(a, _))` (`K/MonadCancel.scala:451-454`). -/
  | dbfK (use rel m p : Nat)
  /-- `_ => use(a)` of `unit >> use(a)` (`cats/syntax/flatMap.scala:54`). -/
  | thenUse (use : Nat) (a : Val)
  /-- Not Cats Effect code (fixed twin, decision 39): `poll => acquire(poll).flatMap { ... }`. -/
  | fbfBody (acq use rel : Nat)
  /-- Not Cats Effect code (fixed twin): `a => poll(IO.defer(use(a))).guaranteeCase(release(a, _))`. -/
  | fbfK (use rel m p : Nat)
  deriving DecidableEq, Repr

/-- The closure value (`Codec.cloVal`, namespace `ns`). `poll` values are captured as handle
values (`Val.poll m p`, visible to `WellFormed`). -/
def BLam.toVal : BLam → Val
  | .gBody src fin => cloVal ns 0 [src, fin]
  | .gOnError fin => cloVal ns 1 [fin]
  | .gTap fin => cloVal ns 2 [fin]
  | .raiseK e => cloVal ns 3 [.err e]
  | .asK a => cloVal ns 4 [a]
  | .reportK => cloVal ns 5 []
  | .reportEc e => cloVal ns 6 [.err e]
  | .reportThunk e => cloVal ns 7 [.err e]
  | .gcBody src k => cloVal ns 8 [src, .nat k]
  | .gcOnError k => cloVal ns 9 [.nat k]
  | .gcTap k => cloVal ns 10 [.nat k]
  | .bfBody acq use rel => cloVal ns 11 [.nat acq, .nat use, .nat rel]
  | .bfK use rel m p => cloVal ns 12 [.nat use, .nat rel, .poll m p]
  | .deferThunk => cloVal ns 13 []
  | .deferEv use a m p => cloVal ns 14 [.nat use, a, .poll m p]
  | .relA rel a => cloVal ns 15 [.nat rel, a]
  | .constThis src => cloVal ns 16 [src]
  | .dropOc rel => cloVal ns 17 [.nat rel]
  | .constFin fin => cloVal ns 18 [fin]
  | .dgcBody src k => cloVal ns 19 [src, .nat k]
  | .dgcOnError k => cloVal ns 20 [.nat k]
  | .unitH => cloVal ns 21 []
  | .dgcTap k => cloVal ns 22 [.nat k]
  | .dbfBody acq use rel => cloVal ns 23 [.nat acq, .nat use, .nat rel]
  | .dbfK use rel m p => cloVal ns 24 [.nat use, .nat rel, .poll m p]
  | .thenUse use a => cloVal ns 25 [.nat use, a]
  | .fbfBody acq use rel => cloVal ns 26 [.nat acq, .nat use, .nat rel]
  | .fbfK use rel m p => cloVal ns 27 [.nat use, .nat rel, .poll m p]

/-- The inverse of `BLam.toVal` on the tag and the fields (namespace already checked). -/
def BLam.ofFields : Nat → List Val → Option BLam
  | 0, [src, fin] => some (.gBody src fin)
  | 1, [fin] => some (.gOnError fin)
  | 2, [fin] => some (.gTap fin)
  | 3, [.err e] => some (.raiseK e)
  | 4, [a] => some (.asK a)
  | 5, [] => some .reportK
  | 6, [.err e] => some (.reportEc e)
  | 7, [.err e] => some (.reportThunk e)
  | 8, [src, .nat k] => some (.gcBody src k)
  | 9, [.nat k] => some (.gcOnError k)
  | 10, [.nat k] => some (.gcTap k)
  | 11, [.nat acq, .nat use, .nat rel] => some (.bfBody acq use rel)
  | 12, [.nat use, .nat rel, .poll m p] => some (.bfK use rel m p)
  | 13, [] => some .deferThunk
  | 14, [.nat use, a, .poll m p] => some (.deferEv use a m p)
  | 15, [.nat rel, a] => some (.relA rel a)
  | 16, [src] => some (.constThis src)
  | 17, [.nat rel] => some (.dropOc rel)
  | 18, [fin] => some (.constFin fin)
  | 19, [src, .nat k] => some (.dgcBody src k)
  | 20, [.nat k] => some (.dgcOnError k)
  | 21, [] => some .unitH
  | 22, [.nat k] => some (.dgcTap k)
  | 23, [.nat acq, .nat use, .nat rel] => some (.dbfBody acq use rel)
  | 24, [.nat use, .nat rel, .poll m p] => some (.dbfK use rel m p)
  | 25, [.nat use, a] => some (.thenUse use a)
  | 26, [.nat acq, .nat use, .nat rel] => some (.fbfBody acq use rel)
  | 27, [.nat use, .nat rel, .poll m p] => some (.fbfK use rel m p)
  | _, _ => none

/-- The closure id (odd, `Codec.libFn`). -/
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

/-- `io.reportError` (`IO.scala:967-972`): `HandleErrorWith(io, reportK)`. -/
def reportIO (io : IO) : IO := .handleErrorWith io BLam.reportK.fn

/-- `this.guarantee(finalizer)` (`IO.scala:496-501`) = `Uncancelable(gBody)`. -/
def guaranteeIO (src fin : Src) : IO := .uncancelable (BLam.gBody src.toVal fin.toVal).fn

/-- `this.guaranteeCase(finalizer)` (`IO.scala:523-530`); `k` = `finalizer`. -/
def guaranteeCaseIO (src : Src) (k : Nat) : IO := .uncancelable (BLam.gcBody src.toVal k).fn

/-- `IO.bracketFull(acquire)(use)(release)` (`IO.scala:1826-1830`). -/
def bracketFullIO (acq use rel : Nat) : IO := .uncancelable (BLam.bfBody acq use rel).fn

/-- `this.bracketCase(use)(release)` (`IO.scala:370-371`): `IO.bracketFull(_ => this)(use)(release)`. -/
def bracketCaseIO (src : Src) (use rel : Nat) : IO := bracketFullIO (BLam.constThis src.toVal).id use rel

/-- `this.bracket(use)(release)` (`IO.scala:338-339`): `bracketCase(use)((a, _) => release(a))`. -/
def bracketIO (src : Src) (use rel : Nat) : IO := bracketCaseIO src use (BLam.dropOc rel).id

/-- Kernel `guaranteeCase` with the `IO` operations (`K/MonadCancel.scala:365-372`). -/
def defaultGuaranteeCaseIO (src : Src) (k : Nat) : IO := .uncancelable (BLam.dgcBody src.toVal k).fn

/-- Kernel `guarantee` (`K/MonadCancel.scala:344-345`): `guaranteeCase(fa)(_ => fin)`, where
`guaranteeCase` is the `IOAsync` override `IO#guaranteeCase` (`IO.scala:2026-2027`). -/
def defaultGuaranteeIO (src fin : Src) : IO := guaranteeCaseIO src (BLam.constFin fin.toVal).id

/-- Kernel `bracketFull` with the `IO` operations (`K/MonadCancel.scala:447-456`). -/
def defaultBracketFullIO (acq use rel : Nat) : IO := .uncancelable (BLam.dbfBody acq use rel).fn

/-- Not Cats Effect code. The fixed twin of `IO.bracketFull` (decision 39, CE-0005):
`IO.uncancelable { poll => acquire(poll).flatMap { a => poll(IO.defer(use(a))).guaranteeCase(release(a, _)) } }`.
`use(a)` runs after the unmask, as in the kernel default. -/
def fixedBracketFullIO (acq use rel : Nat) : IO := .uncancelable (BLam.fbfBody acq use rel).fn

/-- The `IO` of a source. -/
def srcIO (ioOf : Val → IO) (c : Val) : IO :=
  match Src.ofVal c with
  | some (.ext s) => ioOf s
  -- `IO.defer(poll(use(a)))` = `Delay(thunk).flatMap(ev)` (`IO.scala:1296-1297`, `472`)
  | some (.deferUse use a m p) => .flatMap (.delay BLam.deferThunk.fn) (BLam.deferEv use a m p).fn
  -- `poll(unit >> use(a))` = `UnmaskRunLoop(FlatMap(Pure(()), _ => use(a)))`
  | some (.pollUnitThen use a m p) => IO.applyPoll (.flatMap (.pure .unit) (BLam.thenUse use a).fn) m p
  -- `poll(IO.defer(use(a)))`: `deferEv` with the identity poll (mask id 0), then the poll
  | some (.pollDefer use a m p) =>
    IO.applyPoll (.flatMap (.delay BLam.deferThunk.fn) (BLam.deferEv use a 0 0).fn) m p
  | none => .error { code := 999999, kind := .fatal }

/-! ## The closures -/

private def ret (v : Val) : UserResult := { out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
/-- An argument or a user result of the wrong shape: impossible in a well-typed Scala program. -/
def illTyped : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- Call a user function inside a library closure, and go on with the program it returns:
effects first; a throw of the user function is a throw of the closure. -/
def andThen (r : UserResult) (k : IO → IO) : UserResult :=
  match r.out with
  | .prog io => { effects := r.effects, out := .prog (k io) }
  | .throw e => { effects := r.effects, out := .throw e }
  | .ret _ => illTyped

/-- Call a function value that is a user function or one of the "leaf" lambdas of this mirror
(`_ => this`, `_ => fin`, `(a, _) => release(a)`). Calling a lambda value runs its body, as in
Scala. So the mirror calls `uc` only on user functions. -/
def callLeaf (uc : Nat → Val → View → UserResult) (ioOf : Val → IO) (k : Nat) (arg : Val) (v : View) :
    UserResult :=
  match BLam.ofId? k with
  -- `(_ => this)(poll)`
  | some (.constThis src) => prog (srcIO ioOf src)
  -- `(_ => fin)(oc)`
  | some (.constFin fin) => prog (srcIO ioOf fin)
  -- `((a, _) => release(a))(a, oc)`
  | some (.dropOc rel) =>
    match arg with
    | .pair a _ => uc rel a v
    | _ => illTyped
  | _ => uc k arg v

/-- Call a function value: also `release(a, _)` of `bracketFull`, whose `release` is a leaf. -/
def callFn (uc : Nat → Val → View → UserResult) (ioOf : Val → IO) (k : Nat) (arg : Val) (v : View) :
    UserResult :=
  match BLam.ofId? k with
  -- `release(a, oc)`
  | some (.relA rel a) => callLeaf uc ioOf rel (.pair a arg) v
  | _ => callLeaf uc ioOf k arg v

/-- Run closure `l` on `arg` with view `v`. `uc` calls a user function (`env.callV`), `ioOf`
builds an external source. -/
def call (uc : Nat → Val → View → UserResult) (ioOf : Val → IO) (l : BLam) (arg : Val) (v : View) :
    UserResult :=
  match l with
  | .gBody src fin =>
    match arg with
    -- `poll(this).onCancel(finalizer).onError(onError).flatTap(_ => finalizer)` (`IO.scala:500`)
    | .poll m p =>
      prog (.flatMap (.handleErrorWith (.onCancel (IO.applyPoll (srcIO ioOf src) m p) (srcIO ioOf fin))
        (BLam.gOnError fin).fn) (BLam.gTap fin).fn)
    | _ => illTyped
  | .gOnError fin =>
    match arg with
    -- `pf.applyOrElse(t, _ => IO.unit) *> IO.raiseError(t)`; `pf(t) = finalizer.reportError`
    | .err t => prog (.flatMap (reportIO (srcIO ioOf fin)) (BLam.raiseK t).fn)
    | _ => illTyped
  -- `(_ => finalizer)(a).as(a)`
  | .gTap fin => prog (.map (srcIO ioOf fin) (BLam.asK arg).fn)
  | .raiseK e => prog (.error e)
  | .asK a => ret a
  | .reportK =>
    match arg with
    -- `IO.executionContext.flatMap(ec => IO(ec.reportFailure(t)))`
    | .err t => prog (.flatMap .readEC (BLam.reportEc t).fn)
    | _ => illTyped
  | .reportEc e => prog (.delay (BLam.reportThunk e).fn)
  | .reportThunk e => { effects := [.report e], out := .ret .unit }
  | .gcBody src k =>
    match arg with
    -- `val finalized = poll(this).onCancel(finalizer(Outcome.canceled))`;
    -- `finalized.onError(onError).flatTap(...)`
    | .poll m p =>
      andThen (callFn uc ioOf k .ocCanceled v) fun fc =>
        .flatMap (.handleErrorWith (.onCancel (IO.applyPoll (srcIO ioOf src) m p) fc) (BLam.gcOnError k).fn)
          (BLam.gcTap k).fn
    | _ => illTyped
  | .gcOnError k =>
    match arg with
    -- `finalizer(Outcome.errored(e)).reportError *> IO.raiseError(t)`
    | .err t => andThen (callFn uc ioOf k (.ocErrored t) v) fun fe => .flatMap (reportIO fe) (BLam.raiseK t).fn
    | _ => illTyped
  -- `finalizer(Outcome.succeeded(IO.pure(a))).as(a)`
  | .gcTap k => andThen (callFn uc ioOf k (.ocSucceeded arg) v) fun fs => .map fs (BLam.asK arg).fn
  | .bfBody acq use rel =>
    match arg with
    -- `acquire(poll).flatMap { a => ... }`
    | .poll m p => andThen (callFn uc ioOf acq (.poll m p) v) fun ia => .flatMap ia (BLam.bfK use rel m p).fn
    | _ => illTyped
  -- `IO.defer(poll(use(a))).guaranteeCase(release(a, _))`
  | .bfK use rel m p => prog (guaranteeCaseIO (.deferUse use arg m p) (BLam.relA rel arg).id)
  | .deferThunk => ret .unit
  -- `poll(use(a))` (module doc: the thunk's work, in the same `try`)
  | .deferEv use a m p => andThen (callFn uc ioOf use a v) fun u => IO.applyPoll u m p
  -- `release(a, oc)`
  | .relA rel a => callLeaf uc ioOf rel (.pair a arg) v
  | .constThis src => prog (srcIO ioOf src)
  | .dropOc rel =>
    match arg with
    -- `(a, _) => release(a)`
    | .pair a _ => uc rel a v
    | _ => illTyped
  | .constFin fin => prog (srcIO ioOf fin)
  | .dgcBody src k =>
    match arg with
    -- `onCancel(poll(fa), fin(Outcome.canceled))`, `onError(finalized)(...)`, `flatTap(handled)(...)`
    | .poll m p =>
      andThen (callFn uc ioOf k .ocCanceled v) fun fc =>
        .flatMap (.handleErrorWith (.onCancel (IO.applyPoll (srcIO ioOf src) m p) fc) (BLam.dgcOnError k).fn)
          (BLam.dgcTap k).fn
    | _ => illTyped
  | .dgcOnError k =>
    match arg with
    -- `pf(e) *> IO.raiseError(t)`, `pf(e) = handleError(fin(Outcome.errored(e)))(_ => ())`
    | .err t =>
      andThen (callFn uc ioOf k (.ocErrored t) v) fun fe => .flatMap (.handleErrorWith fe BLam.unitH.fn) (BLam.raiseK t).fn
    | _ => illTyped
  | .unitH => prog (.pure .unit)
  -- `as(fin(Outcome.succeeded(pure(a))), a)`
  | .dgcTap k => andThen (callFn uc ioOf k (.ocSucceeded arg) v) fun fs => .map fs (BLam.asK arg).fn
  | .dbfBody acq use rel =>
    match arg with
    | .poll m p => andThen (callFn uc ioOf acq (.poll m p) v) fun ia => .flatMap ia (BLam.dbfK use rel m p).fn
    | _ => illTyped
  -- `guaranteeCase(poll(unit >> use(a)))(release(a, _))`
  | .dbfK use rel m p => prog (guaranteeCaseIO (.pollUnitThen use arg m p) (BLam.relA rel arg).id)
  | .thenUse use a => callFn uc ioOf use a v
  | .fbfBody acq use rel =>
    match arg with
    | .poll m p => andThen (callFn uc ioOf acq (.poll m p) v) fun ia => .flatMap ia (BLam.fbfK use rel m p).fn
    | _ => illTyped
  | .fbfK use rel m p => prog (guaranteeCaseIO (.pollDefer use arg m p) (BLam.relA rel arg).id)

/-- A user function id: even (`Codec` convention, `WellFormed`). -/
def userId (k : Nat) : Bool := k % 2 == 0

/-- A function field that `callLeaf` handles: a user function, or `_ => this`, `_ => fin`,
`(a, _) => release(a)` with a user `release`. -/
def leafOK (k : Nat) : Bool :=
  userId k ||
    match BLam.ofId? k with
    | some (.constThis _) | some (.constFin _) => true
    | some (.dropOc rel) => userId rel
    | _ => false

/-- A function field that `callFn` handles: a leaf, or `release(a, _)` with a leaf `release`. -/
def fnOK (k : Nat) : Bool :=
  leafOK k ||
    match BLam.ofId? k with
    | some (.relA rel _) => leafOK rel
    | _ => false

/-- The closures that the mirror builds: each function field passes `fnOK` (`relA`: `leafOK`).
Every closure that the builders and `call` make has this form when the user functions are
user ids. -/
def BLam.good : BLam → Bool
  | .gcBody _ k | .gcOnError k | .gcTap k | .dgcBody _ k | .dgcOnError k | .dgcTap k => fnOK k
  | .bfBody acq use rel | .dbfBody acq use rel | .fbfBody acq use rel => fnOK acq && fnOK use && leafOK rel
  | .bfK use rel _ _ | .dbfK use rel _ _ | .fbfK use rel _ _ => fnOK use && leafOK rel
  | .deferEv use _ _ _ | .thenUse use _ => fnOK use
  | .relA rel _ => leafOK rel
  | .dropOc rel => userId rel
  | _ => true

/-- `env` runs the closures of this mirror (`BLam.good`) with `ioOf` as the external sources,
and `env.callV` for the user functions that they call. -/
def LibEnv (env : UserEnv) (ioOf : Val → IO) : Prop :=
  ∀ (l : BLam), l.good = true → ∀ (arg : Val) (v : View),
    env.callV l.id arg v = call env.callV ioOf l arg v

/-- The library closures of this mirror (`WellFormed`): odd ids that decode to a good `BLam`. -/
def isLib (id : Nat) : Bool :=
  match BLam.ofId? id with
  | some l => l.good
  | none => false

/-! ## Lemmas: an environment that runs the mirror

An environment that sends the ids of this mirror to `call u ioOf` and all other ids to `u` is a
`LibEnv`, because `call` calls its user-function argument only on even ids (for good closures).
Track 6.2 (`Resource`) reuses these. -/

theorem BLam.ofFields_toVal (l : BLam) :
    (match ofCloVal l.toVal with
     | some (k, tag, fs) => if k == ns then BLam.ofFields tag fs else none
     | none => none) = some l := by
  cases l <;> simp [BLam.toVal, ofCloVal_cloVal, BLam.ofFields]

theorem BLam.ofId?_id (l : BLam) : BLam.ofId? l.id = some l := by
  have h1 : isLibId l.id = true := by simp [isLibId, BLam.id]
  have h2 : cloOfId l.id = some l.toVal := by
    simp only [cloOfId, BLam.id]
    rw [show (2 * valToNat l.toVal + 1) / 2 = valToNat l.toVal by omega]
    exact natToVal_valToNat _
  simp only [BLam.ofId?, h1, ite_true, h2, Option.bind_some]
  exact BLam.ofFields_toVal l

theorem BLam.ofId?_even {k : Nat} (hk : k % 2 = 0) : BLam.ofId? k = none := by
  simp [BLam.ofId?, isLibId, hk]

theorem BLam.odd_of_ofId? {k : Nat} {l : BLam} (h : BLam.ofId? k = some l) : userId k = false := by
  rcases Nat.mod_two_eq_zero_or_one k with hk | hk
  · rw [BLam.ofId?_even hk] at h; cases h
  · simp [userId, hk]

section congr
variable {uc₁ uc₂ : Nat → Val → View → UserResult} (ioOf : Val → IO)
  (h : ∀ k, k % 2 = 0 → ∀ a v, uc₁ k a v = uc₂ k a v)
include h

theorem callLeaf_congr {k : Nat} (hk : leafOK k = true) (a : Val) (v : View) :
    callLeaf uc₁ ioOf k a v = callLeaf uc₂ ioOf k a v := by
  unfold leafOK at hk
  unfold callLeaf
  rcases hof : BLam.ofId? k with _ | l
  · simp only [hof, Bool.or_false] at hk ⊢
    exact h k (by simpa [userId] using hk) a v
  · have hodd := BLam.odd_of_ofId? hof
    simp only [hof, hodd, Bool.false_or] at hk ⊢
    cases l <;> simp_all [userId]

theorem callFn_congr {k : Nat} (hk : fnOK k = true) (a : Val) (v : View) :
    callFn uc₁ ioOf k a v = callFn uc₂ ioOf k a v := by
  unfold callFn
  rcases hof : BLam.ofId? k with _ | l
  · have hl : leafOK k = true := by
      unfold fnOK at hk; simpa [hof] using hk
    exact callLeaf_congr ioOf h hl a v
  · cases l
    case relA rel a' =>
      have hl : leafOK rel = true := by
        unfold fnOK leafOK at hk
        simp [hof, BLam.odd_of_ofId? hof] at hk
        unfold leafOK; simpa [Bool.or_eq_true] using hk
      exact callLeaf_congr ioOf h hl _ v
    all_goals
      have hl : leafOK k = true := by
        unfold fnOK at hk; simpa [hof] using hk
      exact callLeaf_congr ioOf h hl a v

theorem call_congr {l : BLam} (hl : l.good = true) (a : Val) (v : View) :
    call uc₁ ioOf l a v = call uc₂ ioOf l a v := by
  have hF : ∀ k, fnOK k = true → ∀ a v, callFn uc₁ ioOf k a v = callFn uc₂ ioOf k a v :=
    fun k hk a v => callFn_congr ioOf h hk a v
  have hL : ∀ k, leafOK k = true → ∀ a v, callLeaf uc₁ ioOf k a v = callLeaf uc₂ ioOf k a v :=
    fun k hk a v => callLeaf_congr ioOf h hk a v
  cases l <;> simp only [BLam.good, Bool.and_eq_true] at hl <;> simp only [call] <;>
    (try split) <;> simp_all [userId]

end congr

/-- An environment that runs the mirror on its ids and `u` on all other ids is a `LibEnv`. -/
theorem libEnv_of_dispatch (env : UserEnv) (ioOf : Val → IO) (u : Nat → Val → View → UserResult)
    (henv : ∀ id a v, env.callV id a v =
      match BLam.ofId? id with
      | some l => call u ioOf l a v
      | none => u id a v) :
    LibEnv env ioOf := by
  intro l hl a v
  rw [henv, BLam.ofId?_id]
  refine call_congr ioOf (fun k hk a v => ?_) hl a v
  rw [henv, BLam.ofId?_even hk]

end CatsEffectInLean.Model.Bracket

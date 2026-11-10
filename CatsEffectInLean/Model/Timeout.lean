import CatsEffectInLean.Model.Codec

/-!
# `IO#timeout`, `IO#timeoutTo` and `IO.never` (mirror)

`IO.scala` = `core/shared/src/main/scala/cats/effect/IO.scala` at `v3.7.1`.

```scala
def timeout[A2 >: A](duration: Duration): IO[A2] =                      // IO.scala:818-823
  handleDuration(duration, this) { finiteDuration =>
    timeoutTo(finiteDuration, IO.defer(IO.raiseError(new TimeoutException(finiteDuration.toString))))
  }

def timeoutTo[A2 >: A](duration: Duration, fallback: IO[A2]): IO[A2] =  // IO.scala:850-860
  handleDuration[IO[A2]](duration, this) { finiteDuration =>
    IO.uncancelable { poll =>
      poll(racePair(IO.sleep(finiteDuration))) flatMap {
        case Left((oc, f)) => f.cancel *> oc.embed(poll(IO.canceled) *> IO.never)
        case Right((f, _)) =>
          f.cancel *> f.join.flatMap { oc => oc.fold(fallback, IO.raiseError, identity) }
      }
    }
  }
```

* `handleDuration` (`kernel/.../GenTemporal.scala:316-323`) calls the finite branch for a
  `FiniteDuration`. The model has only finite durations (`Nat`, the `Sleep` unit), so
  `timeout d` is the finite branch. `Duration.Inf` is not modelled.
* `racePair(that)` = `IO.racePair(this, that)` = `RacePair` (`IO.scala:644-647`,
  `IO.scala:1817-1820`); `IO.sleep(d)` = `Sleep(d)` (`IO.scala:1692-1696`); `poll(fa)` =
  `UnmaskRunLoop` (`IOFiber.scala:564-567`); `*>` = `flatMap(_ => that)` (`IO.scala:138-139`,
  `IO.scala:903-904`). `that` is a value argument, so Scala builds it before the `flatMap`:
  `f.cancel` reads `_cancel` and `f.join` reads `_join` when the `flatMap` function of
  `racePair` runs (`IO.cancelOf`, `IO.joinOf`).
* `oc.embed(onCancel)` = `oc.fold(onCancel, F.raiseError, identity)`
  (`kernel/.../Outcome.scala:73-74`); `Succeeded(fa)` holds `IO.pure(a)` (`Val.ocSucceeded a`).
* `IO.never` = `asyncForIO.never` = `async(_ => pure(Some(unit)))` (`IO.scala:1560`,
  `IO.scala:2198`, `kernel/.../Async.scala:168`); `IO.async` = `IOCont(body)`
  (`IO.scala:1418-1431`).
* `IO.defer(t)` = `delay(t).flatten` = `Delay(t).flatMap(ev)` (`IO.scala:1296-1297`,
  `IO.scala:472`). A `Val` cannot hold an `IO`: the model thunk makes the exception
  (`Val.err`), and the `flatMap` function returns `IO.raiseError` of it.
* `new TimeoutException(...)` is the error `timeoutErr` (code `timeoutCode`). Each `new` makes a
  new object; the model gives all of them one code.

The source `fa` is a closure field. A `Val` cannot hold an `IO`, so the field is a source
descriptor `src : Val`, and the caller gives the function `srcIO : Val → IO` that builds the
source. For `q.take.timeout(d)`, `src = Val.ref q` (the queue handle, so the closure id shows
that it captures `q`) and `srcIO (.ref q) = Std.Queue.takeIO q`.
-/

namespace CatsEffectInLean.Model.Timeout

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the timeout closures in `Codec.cloVal`. -/
def ns : Nat := 2

/-- The code of `java.util.concurrent.TimeoutException`. -/
def timeoutCode : Nat := 1000000

/-- `new TimeoutException(finiteDuration.toString)`. -/
def timeoutErr : Err := { code := timeoutCode }

/-- The lambdas of `timeoutTo` and `IO.never`. `src` = source code, `d` = duration, `m`, `p`
= a `poll`, `s` = a `ContState` id, `f` = a fiber id, `oc` = an outcome value, `snap` = what
`f.join` read (`snapVal`). -/
inductive TLam where
  /-- `poll => poll(racePair(IO.sleep(fd))) flatMap { ... }` (`IO.scala:852-858`). -/
  | body (src : Val) (d : Nat)
  /-- The `flatMap` function `{ case Left(...) => ...; case Right(...) => ... }`
  (`IO.scala:853-857`). -/
  | sel (d m p : Nat)
  /-- `_ => that` of `f.cancel *> oc.embed(poll(IO.canceled) *> IO.never)` (`IO.scala:854`).
  `oc` is the code of the outcome. -/
  | embed (oc : Val) (m p : Nat)
  /-- `_ => IO.never` of `poll(IO.canceled) *> IO.never` (`IO.scala:854`). -/
  | constNever
  /-- `_ => that` of `f.cancel *> f.join.flatMap(...)` (`IO.scala:856`). `snap` is the code
  of what `f.join` read: `none`, or `some oc`. -/
  | thenJoin (d f : Nat) (snap : Val)
  /-- `oc => oc.fold(fallback, IO.raiseError, identity)` (`IO.scala:856`). -/
  | fold (d : Nat)
  /-- The thunk of `IO.defer(IO.raiseError(new TimeoutException(...)))` (`IO.scala:822`). -/
  | fallbackThunk (d : Nat)
  /-- `ev` of `flatten` in that `IO.defer` (`IO.scala:472`). -/
  | fallbackFlatten
  /-- The `Cont` body of `IO.never` = `IO.async(_ => pure(Some(unit)))` (`IO.scala:1420`). -/
  | neverBody
  /-- `poll => lift(k(resume)) flatMap { ... }` of `IO.async` (`IO.scala:1421-1426`). -/
  | neverUnc (s : Nat)
  /-- The `flatMap` function of `IO.async` (`IO.scala:1422-1425`). -/
  | neverSel (s m p : Nat)
  deriving DecidableEq, Repr

/-- The closure value (`Codec.cloVal`, namespace `ns`). Handles are captured as handle values
(`Val.poll m p`, `Val.cont s`, `Val.fiber f`), so they are visible in the id
(`Model/WellFormed.lean`). -/
def TLam.toVal : TLam → Val
  | .body src d => cloVal ns 0 [src, .nat d]
  | .sel d m p => cloVal ns 1 [.nat d, .poll m p]
  | .embed oc m p => cloVal ns 2 [oc, .poll m p]
  | .constNever => cloVal ns 3 []
  | .thenJoin d f snap => cloVal ns 4 [.nat d, .fiber f, snap]
  | .fold d => cloVal ns 5 [.nat d]
  | .fallbackThunk d => cloVal ns 6 [.nat d]
  | .fallbackFlatten => cloVal ns 7 []
  | .neverBody => cloVal ns 8 []
  | .neverUnc s => cloVal ns 9 [.cont s]
  | .neverSel s m p => cloVal ns 10 [.cont s, .poll m p]

/-- The inverse of `TLam.toVal` on the tag and the fields (namespace already checked). -/
def TLam.ofFields : Nat → List Val → Option TLam
  | 0, [src, .nat d] => some (.body src d)
  | 1, [.nat d, .poll m p] => some (.sel d m p)
  | 2, [oc, .poll m p] => some (.embed oc m p)
  | 3, [] => some .constNever
  | 4, [.nat d, .fiber f, snap] => some (.thenJoin d f snap)
  | 5, [.nat d] => some (.fold d)
  | 6, [.nat d] => some (.fallbackThunk d)
  | 7, [] => some .fallbackFlatten
  | 8, [] => some .neverBody
  | 9, [.cont s] => some (.neverUnc s)
  | 10, [.cont s, .poll m p] => some (.neverSel s m p)
  | _, _ => none

/-- The closure as a `Fn`: a library closure (odd id, `Codec.libFn`). -/
def TLam.fn (l : TLam) : Fn := libFn l.toVal

/-- `fa.timeout(d)` for source code `src` (`IO.scala:818-823`, `IO.scala:850-860`):
`IO.uncancelable(body)` = `Uncancelable` (`IO.scala:1712-1713`). -/
def timeoutIO (src : Val) (d : Nat) : IO := .uncancelable (TLam.body src d).fn

/-- `IO.never` (`IO.scala:1560`, `kernel/.../Async.scala:168`, `IO.scala:1418-1431`). -/
def neverIO : IO := .ioCont TLam.neverBody.fn

/-- The `fallback` of `timeout` (`IO.scala:822`): `IO.defer(IO.raiseError(...))`. -/
def fallbackIO (d : Nat) : IO := .flatMap (.delay (TLam.fallbackThunk d).fn) TLam.fallbackFlatten.fn

/-- `Option[Outcome]` from the code of a `join` snapshot. -/
def snapOutcome : Val → Option Outcome
  | .some (.ocSucceeded v) => some (.succeeded v)
  | .some (.ocErrored e) => some (.errored e)
  | .some .ocCanceled => some .canceled
  | _ => none

/-- The code of a `join` snapshot. -/
def snapVal : Option Outcome → Val
  | some oc => .some oc.toVal
  | none => .none

private def ret (v : Val) : UserResult := { out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
private def illTyped : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- Run one timeout closure on `arg` with view `v`. `srcIO` builds the source from its code. -/
def call (srcIO : Val → IO) (l : TLam) (arg : Val) (v : View) : UserResult :=
  match l with
  | .body src d =>
    match arg with
    -- `poll(racePair(IO.sleep(finiteDuration))) flatMap { ... }` (`IO.scala:853`)
    | .poll m p => prog (.flatMap (IO.applyPoll (.racePair (srcIO src) (.sleep d)) m p) (TLam.sel d m p).fn)
    | _ => illTyped
  | .sel d m p =>
    match arg with
    -- `case Left((oc, f)) => f.cancel *> oc.embed(...)` (`IO.scala:854`)
    | .left (.pair oc (.fiber f)) =>
      prog (.flatMap (IO.cancelOf f (v.outcome f)) (TLam.embed oc m p).fn)
    -- `case Right((f, _)) => f.cancel *> f.join.flatMap { ... }` (`IO.scala:855-856`)
    | .right (.pair (.fiber f) _) =>
      prog (.flatMap (IO.cancelOf f (v.outcome f)) (TLam.thenJoin d f (snapVal (v.outcome f))).fn)
    | _ => illTyped
  | .embed oc m p =>
    match oc with
    -- `Succeeded(fa) => fa` (`Outcome.scala:73-74`)
    | .ocSucceeded a => prog (.pure a)
    -- `Errored(e) => F.raiseError(e)`
    | .ocErrored e => prog (.error e)
    -- `Canceled => poll(IO.canceled) *> IO.never`
    | .ocCanceled => prog (.flatMap (IO.applyPoll .canceled m p) TLam.constNever.fn)
    | _ => illTyped
  | .constNever => prog neverIO
  | .thenJoin d f snap =>
    -- `f.join.flatMap { oc => ... }` (`IO.scala:856`); `f.join` as read before
    prog (.flatMap (IO.joinOf f (snapOutcome snap)) (TLam.fold d).fn)
  | .fold d =>
    match arg with
    -- `oc.fold(fallback, IO.raiseError, identity)` (`IO.scala:856`)
    | .ocCanceled => prog (fallbackIO d)
    | .ocErrored e => prog (.error e)
    | .ocSucceeded a => prog (.pure a)
    | _ => illTyped
  | .fallbackThunk _ => ret (.err timeoutErr)
  | .fallbackFlatten =>
    match arg with
    | .err e => prog (.error e)
    | _ => illTyped
  | .neverBody =>
    match arg with
    -- `G.uncancelable { poll => ... }` (`IO.scala:1421`)
    | .cont s => prog (.uncancelable (TLam.neverUnc s).fn)
    | _ => illTyped
  | .neverUnc s =>
    match arg with
    -- `lift(k(resume)) flatMap { ... }` (`IO.scala:1422`); `k(_) = pure(Some(unit))`
    -- (`Async.scala:168`): code `some unit` for `Some(IO.unit)`
    | .poll m p => prog (.flatMap (.pure (.some .unit)) (TLam.neverSel s m p).fn)
    | _ => illTyped
  | .neverSel s m p =>
    match arg with
    -- `case Some(fin) => G.onCancel(poll(get), lift(fin))` (`IO.scala:1423`); `fin = IO.unit`
    | .some _ => prog (.onCancel (IO.applyPoll (.contGet s) m p) (.pure .unit))
    -- `case None => get` (`IO.scala:1424`)
    | .none => prog (.contGet s)
    | _ => illTyped

end CatsEffectInLean.Model.Timeout

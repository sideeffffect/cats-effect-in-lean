import CatsEffectInLean.Model.Codec
import CatsEffectInLean.Model.Timeout

/-!
# `race`, `raceOutcome`, `both`, `bothOutcome` for `IO` (mirror)

`IO.scala` = `core/shared/src/main/scala/cats/effect/IO.scala` and `K/` =
`kernel/shared/src/main/scala/cats/effect/kernel/` at `v3.7.1`.

## Dispatch (checked 2026-11-10)

`IO` has no own body for any of the four. Each entry point ends in the kernel default of
`GenSpawn` with the `IOAsync` instance (`IO.scala:1996`), which does not override them
(`IO.scala:1996-2170` has no `race`, `raceOutcome`, `both`, `bothOutcome`):

| Entry point | Calls | Body |
|---|---|---|
| `IO#race(that)` (`IO.scala:638-639`) | `IO.race(this, that)` (`IO.scala:1788-1789`) → `asyncForIO.race` | `K/GenSpawn.scala:401-427` |
| `IO#raceOutcome(that)` (`IO.scala:641-642`) | `IO.asyncForIO.raceOutcome(this, that)` | `K/GenSpawn.scala:370-376` |
| `IO#both(that)` (`IO.scala:243-244`) | `IO.both(this, that)` (`IO.scala:1732-1733`) → `asyncForIO.both` | `K/GenSpawn.scala:474-500` |
| `IO#bothOutcome(that)` (`IO.scala:228-229`) | `IO.asyncForIO.bothOutcome(this, that)`; `IO.bothOutcome(l, r)` (`IO.scala:1729-1730`) = `l.bothOutcome(r)` | `K/GenSpawn.scala:442-448` |

The entry points are plain method calls: they add no `IO` node. So this file is the kernel
default body (`Kernel/GenSpawn.lean`, `GenSpawn.Default.*`) with the `IOAsync` operations put in.
There is no second `IO` body, so no `IO`-vs-kernel twin exists for these four methods.

## `IOAsync` operations used by the default bodies

* `uncancelable` = `Uncancelable` (`IO.scala:2095-2096`, `IO.scala:1712-1713`); `poll(fa)` =
  `UnmaskRunLoop` (`IO.applyPoll`).
* `racePair` = `RacePair` (`IO.scala:2090-2093`, `IO.scala:1817-1820`).
* `flatMap` = `FlatMap` (`IO.scala:2101-2102`); `map` = `Map` (`IO.scala:2098-2099`).
* `x *> y` = `productR(x)(y)` = `x.productR(y)` = `x.flatMap(_ => y)` (`IO.scala:2081-2082`,
  `IO.scala:903-904`). `y` is a value argument: Scala builds it before the `flatMap`.
* `fa.as(b)` = `IOAsync.as` = `fa.map(_ => b)` (`IO.scala:2008-2009`, `IO.scala:182-183`).
* `fa.onCancel(fin)` = `OnCancel` (`IO.scala:2059-2060`).
* `fa.tupleLeft(b)` = cats `Functor.tupleLeft` = `map(fa)(a => (b, a))`; `tupleRight(b)` =
  `map(fa)(a => (a, b))` (cats-core 2.13.0 `Functor.scala:157`, `:171`).
* `fa.product(fb)` = cats `FlatMap.product` = `flatMap(fa)(a => map(fb)(b => (a, b)))`
  (cats-core 2.13.0 `FlatMap.scala:107-108`); not overridden by `IOAsync`.
* `raiseError` = `Error`; `canceled` = `Canceled`; `never` = `Async.never` =
  `async(_ => pure(Some(unit)))` (`K/Async.scala:168`) = `Timeout.neverIO`.
* `f.cancel` reads `_cancel` and `f.join` reads `_join` when the term is built
  (`IO.cancelOf`, `IO.joinOf`). Each is built inside the `flatMap` function of `racePair`, in one
  run-loop iteration, so they read the same view (`View.outcome`).
* An outcome `Succeeded(fa)` holds `IO.pure(a)` (`Val.ocSucceeded a`, `IOFiber.scala` `succeeded`).

## Closures and sources

The closures are library closures (`Codec.libFn`, odd ids) in namespace `ns`. The two sources
are closure fields: a `Val` cannot hold an `IO`, so a field is a source code, and the caller gives
`srcIO : Val → IO` (as in `Model/Timeout.lean`).
-/

namespace CatsEffectInLean.Model.Race

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the race closures in `Codec.cloVal` (track R, Phase 6; namespaces 1, 2, 3
are queue, timeout, program closures). -/
def ns : Nat := 10

/-- Which kernel default. -/
inductive Kind where
  | race | raceOutcome | bothOutcome | both
  deriving DecidableEq, Repr

def Kind.toNat : Kind → Nat
  | .race => 0 | .raceOutcome => 1 | .bothOutcome => 2 | .both => 3

def Kind.ofNat? : Nat → Option Kind
  | 0 => some .race | 1 => some .raceOutcome | 2 => some .bothOutcome | 3 => some .both
  | _ => none

/-- `Left(_)` (side 0) or `Right(_)` (side 1). -/
def inj (side : Nat) (x : Val) : Val := if side == 0 then .left x else .right x

/-- The lambdas of the four default bodies. `m`, `p` = a `poll`; `f` = a fiber id; `side` 0 =
`Left`, 1 = `Right`; `snap` = what `f.join` read (`Timeout.snapVal`). -/
inductive RLam where
  /-- `poll => poll(racePair(fa, fb)).flatMap { ... }`. -/
  | body (k : Kind) (a b : Val)
  /-- The `flatMap` function `{ case Left((oc, f)) => ...; case Right((f, oc)) => ... }`. -/
  | sel (k : Kind) (m p : Nat)
  /-- `race`: `_ => fa.map(Left(_))` (or `Right`) of `f.cancel *> fa.map(...)`, with
  `fa = IO.pure(v)`. -/
  | thenMapPure (v : Val) (side : Nat)
  /-- `_ => raiseError(e)` of `f.cancel *> raiseError(e)`. -/
  | thenRaise (e : Err)
  /-- `race`: `_ => f.join` of `f.cancel *> f.join` (`f.join` as read before). -/
  | thenJoin (f : Nat) (snap : Val)
  /-- `race`: `{ case Succeeded(fx) => fx.map(Right/Left(_)); case Errored(e) => raiseError(e);
  case Canceled() => poll(canceled) *> never }`. `side` is the side of the joined fiber. -/
  | joinSel (side m p : Nat)
  /-- `Left(_)` / `Right(_)` as a `map` function. -/
  | inj (side : Nat)
  /-- `_ => never` of `... *> never`. -/
  | constNever
  /-- `raceOutcome`: `_ => b` of `f.cancel.as(b)`. -/
  | constV (v : Val)
  /-- `bothOutcome`: `a => (oc, a)` (`tupleLeft(oc)`, side 0) or `a => (a, oc)`
  (`tupleRight(oc)`, side 1). -/
  | tuple (side : Nat) (oc : Val)
  /-- `both`: `{ case Succeeded(fx) => fa.product(fb); case Errored(e) => raiseError(e);
  case Canceled() => poll(canceled) *> never }` after `poll(f.join).onCancel(f.cancel)`.
  `side` = side of the winner, `v` = its value. -/
  | bothSel (side : Nat) (v : Val) (m p : Nat)
  /-- `a => map(fb)(b => (a, b))` of `FlatMap.product`, with `fb = IO.pure(b)`. -/
  | prodK (b : Val)
  /-- `b => (a, b)` of `FlatMap.product`. -/
  | pairWith (a : Val)
  /-- `both`: `_ => poll(canceled)` of `f.cancel *> poll(canceled)`. -/
  | constPollCanceled (m p : Nat)
  deriving DecidableEq, Repr

/-- The closure value (`Codec.cloVal`, namespace `ns`). Handles are captured as handle values,
so `WellFormed` sees them in the id. -/
def RLam.toVal : RLam → Val
  | .body k a b => cloVal ns 0 [.nat k.toNat, a, b]
  | .sel k m p => cloVal ns 1 [.nat k.toNat, .poll m p]
  | .thenMapPure v side => cloVal ns 2 [v, .nat side]
  | .thenRaise e => cloVal ns 3 [.err e]
  | .thenJoin f snap => cloVal ns 4 [.fiber f, snap]
  | .joinSel side m p => cloVal ns 5 [.nat side, .poll m p]
  | .inj side => cloVal ns 6 [.nat side]
  | .constNever => cloVal ns 7 []
  | .constV v => cloVal ns 8 [v]
  | .tuple side oc => cloVal ns 9 [.nat side, oc]
  | .bothSel side v m p => cloVal ns 10 [.nat side, v, .poll m p]
  | .prodK b => cloVal ns 11 [b]
  | .pairWith a => cloVal ns 12 [a]
  | .constPollCanceled m p => cloVal ns 13 [.poll m p]

/-- The inverse of `RLam.toVal` on the tag and the fields (namespace already checked). -/
def RLam.ofFields : Nat → List Val → Option RLam
  | 0, [.nat k, a, b] => (Kind.ofNat? k).map fun k => .body k a b
  | 1, [.nat k, .poll m p] => (Kind.ofNat? k).map fun k => .sel k m p
  | 2, [v, .nat side] => some (.thenMapPure v side)
  | 3, [.err e] => some (.thenRaise e)
  | 4, [.fiber f, snap] => some (.thenJoin f snap)
  | 5, [.nat side, .poll m p] => some (.joinSel side m p)
  | 6, [.nat side] => some (.inj side)
  | 7, [] => some .constNever
  | 8, [v] => some (.constV v)
  | 9, [.nat side, oc] => some (.tuple side oc)
  | 10, [.nat side, v, .poll m p] => some (.bothSel side v m p)
  | 11, [b] => some (.prodK b)
  | 12, [a] => some (.pairWith a)
  | 13, [.poll m p] => some (.constPollCanceled m p)
  | _, _ => none

/-- The closure as a `Fn`: a library closure (odd id, `Codec.libFn`). -/
def RLam.fn (l : RLam) : Fn := libFn l.toVal

/-- `GenSpawn.Default.<k>(fa, fb)` with `IOAsync`: `uncancelable { poll => ... }`. -/
def combIO (k : Kind) (a b : Val) : IO := .uncancelable (RLam.body k a b).fn

/-- `fa.race(fb)` (`IO.scala:638-639`, `IO.scala:1788-1789`, `K/GenSpawn.scala:401-427`). -/
def raceIO (a b : Val) : IO := combIO .race a b
/-- `fa.raceOutcome(fb)` (`IO.scala:641-642`, `K/GenSpawn.scala:370-376`). -/
def raceOutcomeIO (a b : Val) : IO := combIO .raceOutcome a b
/-- `fa.bothOutcome(fb)` (`IO.scala:228-229`, `K/GenSpawn.scala:442-448`). -/
def bothOutcomeIO (a b : Val) : IO := combIO .bothOutcome a b
/-- `fa.both(fb)` (`IO.scala:243-244`, `IO.scala:1732-1733`, `K/GenSpawn.scala:474-500`). -/
def bothIO (a b : Val) : IO := combIO .both a b

private def ret (v : Val) : UserResult := { out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
private def illTyped : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- `poll(canceled) *> never` (`K/GenSpawn.scala:414`, `:423`, `:484`, `:497`). -/
def pollCanceledNever (m p : Nat) : IO := .flatMap (IO.applyPoll .canceled m p) RLam.constNever.fn

/-- `race`, winner on side `side` with outcome `oc`, loser `f` (`K/GenSpawn.scala:405-414`,
`:416-424`). -/
def raceWin (side : Nat) (oc : Val) (f m p : Nat) (v : View) : UserResult :=
  match oc with
  -- `case Outcome.Succeeded(fa) => f.cancel *> fa.map(Left(_))`
  | .ocSucceeded a => prog (.flatMap (IO.cancelOf f (v.outcome f)) (RLam.thenMapPure a side).fn)
  -- `case Outcome.Errored(ea) => f.cancel *> raiseError(ea)`
  | .ocErrored e => prog (.flatMap (IO.cancelOf f (v.outcome f)) (RLam.thenRaise e).fn)
  -- `case Outcome.Canceled() => f.cancel *> f.join flatMap { ... }`
  | .ocCanceled =>
    prog (.flatMap
      (.flatMap (IO.cancelOf f (v.outcome f)) (RLam.thenJoin f (Timeout.snapVal (v.outcome f))).fn)
      (RLam.joinSel (1 - side) m p).fn)
  | _ => illTyped

/-- `both`, winner on side `side` with outcome `oc`, loser `f` (`K/GenSpawn.scala:478-486`,
`:488-497`). -/
def bothWin (side : Nat) (oc : Val) (f m p : Nat) (v : View) : UserResult :=
  match oc with
  -- `case Outcome.Succeeded(fa) => poll(f.join).onCancel(f.cancel).flatMap { ... }`
  | .ocSucceeded a =>
    prog (.flatMap (.onCancel (IO.applyPoll (IO.joinOf f (v.outcome f)) m p) (IO.cancelOf f (v.outcome f)))
      (RLam.bothSel side a m p).fn)
  -- `case Outcome.Errored(ea) => f.cancel *> raiseError(ea)`
  | .ocErrored e => prog (.flatMap (IO.cancelOf f (v.outcome f)) (RLam.thenRaise e).fn)
  -- `case Outcome.Canceled() => f.cancel *> poll(canceled) *> never`
  | .ocCanceled =>
    prog (.flatMap (.flatMap (IO.cancelOf f (v.outcome f)) (RLam.constPollCanceled m p).fn)
      RLam.constNever.fn)
  | _ => illTyped

/-- `fa.product(fb)` with `fa = IO.pure(x)`, `fb = IO.pure(y)` (`FlatMap.scala:107-108`). -/
def productIO (x y : Val) : IO := .flatMap (.pure x) (RLam.prodK y).fn

/-- Run one race closure on `arg` with view `v`. `srcIO` builds a source from its code. -/
def call (srcIO : Val → IO) (l : RLam) (arg : Val) (v : View) : UserResult :=
  match l with
  | .body k a b =>
    match arg with
    -- `poll(racePair(fa, fb)).flatMap { ... }`
    | .poll m p => prog (.flatMap (IO.applyPoll (.racePair (srcIO a) (srcIO b)) m p) (RLam.sel k m p).fn)
    | _ => illTyped
  | .sel k m p =>
    match k, arg with
    -- race (`K/GenSpawn.scala:403-425`)
    | .race, .left (.pair oc (.fiber f)) => raceWin 0 oc f m p v
    | .race, .right (.pair (.fiber f) oc) => raceWin 1 oc f m p v
    -- raceOutcome: `f.cancel.as(Left(oc))` / `f.cancel.as(Right(oc))` (`K/GenSpawn.scala:372-375`)
    | .raceOutcome, .left (.pair oc (.fiber f)) =>
      prog (.map (IO.cancelOf f (v.outcome f)) (RLam.constV (.left oc)).fn)
    | .raceOutcome, .right (.pair (.fiber f) oc) =>
      prog (.map (IO.cancelOf f (v.outcome f)) (RLam.constV (.right oc)).fn)
    -- bothOutcome: `poll(f.join).onCancel(f.cancel).tupleLeft(oc)` / `.tupleRight(oc)`
    -- (`K/GenSpawn.scala:444-447`)
    | .bothOutcome, .left (.pair oc (.fiber f)) =>
      prog (.map (.onCancel (IO.applyPoll (IO.joinOf f (v.outcome f)) m p) (IO.cancelOf f (v.outcome f)))
        (RLam.tuple 0 oc).fn)
    | .bothOutcome, .right (.pair (.fiber f) oc) =>
      prog (.map (.onCancel (IO.applyPoll (IO.joinOf f (v.outcome f)) m p) (IO.cancelOf f (v.outcome f)))
        (RLam.tuple 1 oc).fn)
    -- both (`K/GenSpawn.scala:476-498`)
    | .both, .left (.pair oc (.fiber f)) => bothWin 0 oc f m p v
    | .both, .right (.pair (.fiber f) oc) => bothWin 1 oc f m p v
    | _, _ => illTyped
  | .thenMapPure a side => prog (.map (.pure a) (RLam.inj side).fn)
  | .thenRaise e => prog (.error e)
  | .thenJoin f snap => prog (IO.joinOf f (Timeout.snapOutcome snap))
  | .joinSel side m p =>
    match arg with
    -- `case Outcome.Succeeded(fb) => fb.map(Right(_))`
    | .ocSucceeded b => prog (.map (.pure b) (RLam.inj side).fn)
    -- `case Outcome.Errored(eb) => raiseError(eb)`
    | .ocErrored e => prog (.error e)
    -- `case Outcome.Canceled() => poll(canceled) *> never`
    | .ocCanceled => prog (pollCanceledNever m p)
    | _ => illTyped
  | .inj side => ret (inj side arg)
  | .constNever => prog Timeout.neverIO
  | .constV b => ret b
  | .tuple side oc => ret (if side == 0 then .pair oc arg else .pair arg oc)
  | .bothSel side x m p =>
    match arg with
    -- `case Outcome.Succeeded(fb) => fa.product(fb)` (winner left: `fa` = winner)
    | .ocSucceeded y => prog (if side == 0 then productIO x y else productIO y x)
    | .ocErrored e => prog (.error e)
    | .ocCanceled => prog (pollCanceledNever m p)
    | _ => illTyped
  | .prodK b => prog (.map (.pure b) (RLam.pairWith arg).fn)
  | .pairWith a => ret (.pair a arg)
  | .constPollCanceled m p => prog (IO.applyPoll .canceled m p)

/-- The race closure of an id, if it is one. -/
def ofId? (id : Nat) : Option RLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then RLam.ofFields tag fs else none
    | none => none
  else none

end CatsEffectInLean.Model.Race

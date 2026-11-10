import CatsEffectInLean.Model.Resource

/-!
# Fixed twin of `allocatedCase` (upstream PR #4630, decision 39)

A mirror of `Resource#allocatedCase` as fixed by typelevel/cats-effect PR #4630, merged into
`series/3.7.x` (commit `2f94201`, 2026-10-12; not in a release, not on `series/3.x`).
`RES37` below is `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala` at that
commit. The v3.7.1 mirror is `CatsEffectInLean/Model/Resource.lean`; this file reuses its
`Res`, `REnv`, `RelFn`, `applyRel`, `progOf` and the closures `Clo.onErrorH`, `Clo.makePair`,
`Clo.applyPair`, `Clo.spin`. The fix is never applied to the v3.7.1 mirror ("never fix Cats
Effect in the model"): this is a separate twin, used only for the fixed-twin check of CE-0002.

## What the fix changes (`RES37:464-530` against v3.7.1 `Resource.scala:464-531`)

1. The whole interpreter runs inside one `F uncancelable { poll => ... }` (`RES37:470`), and
   `continue`/`loop` are defined inside it, so they capture `poll` (`RES37:472-483`).
2. `Allocate`: `resource(poll) flatMap { ... }` (`RES37:485-486`), with no inner `F.uncancelable`.
3. `Frame` after `Allocate`: `(poll(F.unit) >> continue(head(b), tail, rel2)).onCancel(...)
   
   .onError{...}` (`RES37:506-509`) instead of `poll(continue(...))...`. `>>` takes its
   argument by name, so `continue(head(b), ...)` runs inside the `flatMap` lambda (`FClo.thenK`).
4. `Eval`: `poll(fa).flatMap(a => continue(Resource.pure(a), stack, release))` (`RES37:524-525`).

`Bind` and `Pure` are as in v3.7.1 (`RES37:513-522`).

## Closures

The lambdas of the twin are `FClo`, with tags 20-23, so their ids never decode as a `Clo` (tags
0-8) and the reverse. `FEnv.callV` runs an odd id as an `FClo` if it decodes as one, else as in
`REnv.callV`. The body lambda captures `this : Resource`; a `Val` cannot hold a `Res` (it can
hold an `IO`), so the closure names it by an index into `FEnv.res`.
-/

namespace CatsEffectInLean.Model.ResourceFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Resource

/-- The lambdas of the fixed `allocatedCase`, with their captured data. -/
inductive FClo where
  /-- `poll => { ...; loop(this, Nil, _ => F.unit) }` (`RES37:470-529`); `this` is
  `FEnv.res k`. -/
  | body (k : Nat)
  /-- `a => continue(Resource.pure(a), stack, release)` (`RES37:525`), with the `poll` of the
  body. -/
  | evalK (stack : Stack) (release : RelFn) (poll : Val)
  /-- `{ case (b, rel) => ... }` (`RES37:487-510`), with the `poll` of the body. -/
  | allocK (stack : Stack) (release : RelFn) (poll : Val)
  /-- `_ => continue(head(b), tail, rel2)`: the by-name argument of `>>` (`RES37:507`). -/
  | thenK (b : Val) (head : Nat) (tail : Stack) (rel2 : RelFn) (poll : Val)
  deriving DecidableEq, Repr

def FClo.toVal : FClo → Val
  | .body k => tagged 20 (.nat k)
  | .evalK s r p => tagged 21 (.pair (stackToVal s) (.pair r.toVal p))
  | .allocK s r p => tagged 22 (.pair (stackToVal s) (.pair r.toVal p))
  | .thenK b h t r p =>
    tagged 23 (.pair b (.pair (.nat h) (.pair (stackToVal t) (.pair r.toVal p))))

def FClo.ofVal : Val → Option FClo
  | .pair (.nat 20) (.nat k) => some (.body k)
  | .pair (.nat 21) (.pair s (.pair r p)) =>
    match stackOfVal s, RelFn.ofVal r with
    | some s', some r' => some (.evalK s' r' p)
    | _, _ => none
  | .pair (.nat 22) (.pair s (.pair r p)) =>
    match stackOfVal s, RelFn.ofVal r with
    | some s', some r' => some (.allocK s' r' p)
    | _, _ => none
  | .pair (.nat 23) (.pair b (.pair (.nat h) (.pair t (.pair r p)))) =>
    match stackOfVal t, RelFn.ofVal r with
    | some t', some r' => some (.thenK b h t' r' p)
    | _, _ => none
  | _ => none

/-- The id of a twin closure (odd). -/
def fcloFn (c : FClo) : Fn := libFn c.toVal

/-- User code of the twin: `REnv` plus the resources that `FClo.body` names. -/
structure FEnv where
  /-- The user code, `Bind` functions, `make` parts (as in `REnv`). -/
  base : REnv
  /-- `this` of `allocatedCase` for `FClo.body k`. -/
  res : Nat → Res

/-- `poll(io)` with a `Poll` value (`IO.applyPoll`); ill-typed if the value is not a poll. -/
def applyPollV (io : IO) : Val → Option IO
  | .poll m s => some (IO.applyPoll io m s)
  | _ => none

/-- `loop(current, stack, release)` of the fixed `allocatedCase` (`RES37:480-526`), inside the
body, with its `poll` and heap view `v`. User code may run here (`resource(poll)`), so the
result has effects. Branch order as in Scala. -/
def loopF (f : FEnv) (poll : Val) (v : View) :
    (fuel : Nat) → Res → Stack → RelFn → List UserEffect × Except Err IO
  | 0, _, _, _ => ([], .ok spinIO)
  -- `case Allocate(resource) => resource(poll) flatMap { ... }` (`RES37:485-511`)
  | _ + 1, .allocate a, stack, release =>
    let k := fcloFn (.allocK stack release poll)
    match a with
    | .user id =>
      let (es, p) := progOf (f.base.user.callV id poll v)
      (es, p.map (fun p => .flatMap p k))
    | .make acq rel =>
      -- `_ => resource` with `resource = acquire.map(a => a -> release(a)).map { ... }`
      ([], .ok (.flatMap (.map (.map (f.base.acquire acq) (cloFn (.makePair rel)))
        (cloFn .applyPair)) k))
  -- `case Bind(source, fs) => loop(source, Frame(fs, stack), release)` (`RES37:513-514`)
  | n + 1, .bind source fs, stack, release => loopF f poll v n source (fs :: stack) release
  -- `case Pure(v) => stack match { case Nil => (v: B, release).pure[F]` (`RES37:516-519`)
  | _ + 1, .pure a, [], release => ([], .ok (.pure (.pair a release.toVal)))
  -- `case Frame(head, tail) => loop(head(v), tail, release)` (`RES37:520-521`)
  | n + 1, .pure a, head :: tail, release =>
    match f.base.bind head a with
    | .ok res => loopF f poll v n res tail release
    | .error e => ([], .error e)
  -- `case Eval(fa) => poll(fa).flatMap(a => continue(Resource.pure(a), stack, release))`
  -- (`RES37:524-525`)
  | _ + 1, .eval fa, stack, release =>
    match applyPollV fa poll with
    | some p => ([], .ok (.flatMap p (fcloFn (.evalK stack release poll))))
    | none => ([], .error illTyped)

/-- The mirror of each twin closure, applied to `arg` with heap view `v`. -/
def fcloCall (f : FEnv) (c : FClo) (arg : Val) (v : View) : UserResult :=
  match c with
  | .body k =>
    -- `loop(this, Nil, _ => F.unit)` (`RES37:528`), `arg` is the `poll`
    let (es, p) := loopF f arg v loopFuel (f.res k) [] .unit
    withEffects es p
  | .evalK stack release poll =>
    -- `continue(Resource.pure(a), stack, release)` = `loop(...)` (`RES37:472-476`)
    let (es, p) := loopF f poll v loopFuel (.pure arg) stack release
    withEffects es p
  | .allocK stack release poll =>
    match arg with
    | .pair b relV =>
      match RelFn.ofVal relV with
      | none => throwR illTyped
      | some rel =>
        -- `val rel2 = (ec: ExitCase) => rel(ec).guarantee(F.unit >> release(ec))` (`RES37:489`)
        let rel2 := RelFn.guarantee rel release
        match stack with
        -- `case Nil => F.pure((b, rel2))` (`RES37:492-504`)
        | [] => { out := .prog (.pure (.pair b rel2.toVal)) }
        -- `case Frame(head, tail) => (poll(F.unit) >> continue(head(b), tail, rel2))
        --   .onCancel(rel(ExitCase.Canceled))
        --   .onError { case e => rel(ExitCase.Errored(e)).handleError(_ => ()) }` (`RES37:506-509`)
        | head :: tail =>
          match applyPollV (.pure .unit) poll with
          | none => throwR illTyped
          | some pu =>
            let io := IO.flatMap pu (fcloFn (.thenK b head tail rel2 poll))
            let (es, fin) := applyRel f.base v rel exitCanceled
            withEffects es (fin.map fun fin =>
              .handleErrorWith (.onCancel io fin) (cloFn (.onErrorH rel)))
    | _ => throwR illTyped
  | .thenK b head _tail rel2 poll =>
    -- `continue(head(b), tail, rel2)`: `head(b)` can throw
    match f.base.bind head b with
    | .error e => throwR e
    | .ok res =>
      let (es, p) := loopF f poll v loopFuel res _tail rel2
      withEffects es p

/-- Even id: user code; odd id: a twin closure, else a closure of the v3.7.1 mirror. -/
def FEnv.callV (f : FEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  if id % 2 == 1 then
    match (natToVal (id / 2)).bind FClo.ofVal with
    | some c => fcloCall f c arg v
    | none => f.base.callV id arg v
  else f.base.callV id arg v

/-- The `UserEnv` of a program that uses the fixed twin. -/
def FEnv.toEnv (f : FEnv) : UserEnv where
  call id arg refs := f.callV id arg { refs := refs }
  callV id arg v := f.callV id arg v

/-- `allocatedCase` of the fixed twin (`RES37:464-530`) for the resource `f.res k`:
`F uncancelable { poll => ... loop(this, Nil, _ => F.unit) }`. -/
def allocatedCaseFixed (k : Nat) : IO := .uncancelable (fcloFn (.body k))

end CatsEffectInLean.Model.ResourceFixed

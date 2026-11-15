import CatsEffectInLean.Props.Phase7.Semaphore

/-!
# CE-0060 fixed twin (decision 39): eager removal of a canceled waiter

Not Cats Effect code. The `cleanup` of `acquireN` (`Semaphore.scala:188-191`) with `won = true`
calls `reclaim(req)`, which removes `req` only when it is the head of the queue. The twin removes
it wherever it is, as the code before PR #4648 did (v3.7.0: `waiting.filterNot(_ sameAs req)` and
`releaseN(permitsAcquiredSoFar)`):

```scala
val cleanup = req.complete.flatMap { won =>
  if (won) state.flatModify { case State(permits, waiting) =>
    waiting.find(_ sameAs req) match {
      case Some(r) => State(permits, waiting.filterNot(_ sameAs req)) -> releaseN(r.sunk)
      case None => State(permits, waiting) -> F.unit
    } }
  else releaseN(n)
}
```

The twin keeps the `won` race, the lazy `sweep` of `releaseN` and everything else. Closures `FX`
(namespace 65). `fixedEnv e` routes the `won = true` branch of `cleanup` to the twin.
-/

namespace CatsEffectInLean.Proofs.Phase7

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Semaphore

def fxns : Nat := 65

inductive FX where
  /-- `_ => F.flatten(modify(f))` of the twin's `flatModify`. -/
  | recBody (s g : Nat)
  /-- The `modify` thunk: remove the request with gate `g` wherever it is. -/
  | modRec (s g : Nat)
  deriving DecidableEq, Repr

def FX.toVal : FX → Val
  | .recBody s g => cloVal fxns 0 [.fn s, .deferred g]
  | .modRec s g => cloVal fxns 1 [.fn s, .deferred g]

def FX.id (l : FX) : Nat := 2 * valToNat l.toVal + 1
def FX.fn (l : FX) : Fn := .user l.id

def FX.ofId? (id : Nat) : Option FX :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (65, 0, [.fn s, .deferred g]) => some (.recBody s g)
    | some (65, 1, [.fn s, .deferred g]) => some (.modRec s g)
    | _ => none
  else none

def FX.call (l : FX) (v : View) : UserResult :=
  match l with
  | .recBody s g => { out := .prog (.flatMap (.delay (FX.modRec s g).fn) SL.flattenK.fn) }
  | .modRec s g =>
    match semRef? s with
    | some q =>
      match stateOf v q with
      | some (permits, waiting) =>
        match waiting.find? (fun r => r.2.2 == g) with
        | some (rq, rm, _) =>
          { effects := [.writeRef q (stateV permits (waiting.filter fun r => r.2.2 != g))],
            out := .ret (dRelease s (rq - rm)) }
        | none => { effects := [.writeRef q (stateV permits waiting)], out := .ret dUnit }
      | none => illTyped
    | none => illTyped

/-- The fixed twin of an environment: the `won = true` branch of `cleanup` is the twin. -/
def fixedEnv (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match FX.ofId? id with
    | some l => l.call v
    | none =>
      match SL.ofId? id, a with
      | some (.wonK s _ g), .bool true => { out := .prog (.uncancelable (FX.recBody s g).fn) }
      | _, _ => e.callV id a v

end CatsEffectInLean.Proofs.Phase7

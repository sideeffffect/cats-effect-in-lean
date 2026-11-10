import CatsEffectInLean.Props.Phase6.Race

/-!
# Leak smoke test (Phase 6, track R)

For each kernel default `k` (`race`, `raceOutcome`, `both`, `bothOutcome`) and each pair of
sides from `fam`, and for `timeout` with each side and duration: the exact state set of
`exploreP` (all fuel values, all `PChoice` lists), checked to be closed (`leakFreeP`), and the
leak observation `liveRaceChildren` at every state where the root completed. Both the direct
form (racing fiber 0) and the parent form of decision 50 (racing fiber 1).

Also: `raceOutcomeIsWinnerOutcome` on every completed state, the law
`uncancelableRaceNotInherited` (`checkEqvP`), and the wrong-function test (a `race` that never
cancels the loser must leak).

Exit code 1 if a check fails, or if a search does not close within the bound.
-/

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race

namespace LeakSmoke

/-- The sides: no user code, only mirror terms. -/
def fam : List (String × IO) :=
  [("pure", .pure (.nat 1)), ("raise", .error { code := 7 }), ("canceled", .canceled),
   ("never", Timeout.neverIO), ("sleep1", .sleep 1),
   ("onCancelNever", .onCancel Timeout.neverIO (.pure .unit)),
   ("cedeThen2", .map .cede (Race.RLam.constV (.nat 2)).fn),
   ("maskedRaise", .uncancelable (Race.RLam.thenRaise { code := 8 }).fn),
   ("maskedNever", .uncancelable Race.RLam.constNever.fn)]

/-- No user code: every non-mirror id throws. -/
def u0 : UserEnv := { call := fun _ _ _ => { out := .throw { code := 999999, kind := .fatal } } }

def bound : Nat := 20000

/-- The wrong function: a `race` whose `Succeeded` branch does not cancel the loser
(`fa.map(Left(_))` without `f.cancel *>`). -/
def noCancelEnv (fa fb : IO) : UserEnv :=
  let e := env fa fb u0
  { call := e.call
    callV := fun id arg v =>
      match Race.ofId? id, arg with
      | some (.sel .race _ _), .left (.pair (.ocSucceeded a) _) =>
        { out := .prog (.map (.pure a) (Race.RLam.inj 0).fn) }
      | some (.sel .race _ _), .right (.pair _ (.ocSucceeded b)) =>
        { out := .prog (.map (.pure b) (Race.RLam.inj 1).fn) }
      | _, _ => e.callV id arg v }

/-- `raceOutcomeIsWinnerOutcome` on one state. -/
def winnerOK (s : Sched CounterMask) : Bool :=
  match s.halt with
  | some (.done (.succeeded (.left oc))) => (fiberOutcome s 1).map Outcome.toVal == some oc
  | some (.done (.succeeded (.right oc))) => (fiberOutcome s 2).map Outcome.toVal == some oc
  | some (.done (.succeeded _)) => false
  | _ => true

structure Res where
  states : Nat
  closed : Bool
  leakFree : Bool
  done : Nat

def check (e : UserEnv) (io : IO) (r : Nat) (extra : Sched CounterMask → Bool := fun _ => true) : Res :=
  let L := (exploreP {} counterMaskModel e bound io).map Prod.fst
  let closed := ClosedP {} counterMaskModel e L && L.contains (Sched.init counterMaskModel io)
  { states := L.length, closed,
    leakFree := L.all fun s => (!s.rootDone || (liveRaceChildren s r).isEmpty) && extra s,
    done := (L.filter (·.rootDone)).length }

def kinds : List Race.Kind := [.race, .raceOutcome, .both, .bothOutcome]

end LeakSmoke

open LeakSmoke in
def main : IO UInt32 := do
  let mut bad : Nat := 0
  let mut n : Nat := 0
  let mut statesTotal : Nat := 0
  for k in kinds do
    for (na, a) in fam do
      for (nb, b) in fam do
        let e := env a b u0
        let extra := if k == .raceOutcome then winnerOK else fun _ => true
        let r1 := check e (Race.combIO k src0 src1) 0 extra
        let r2 := check e (parentIO (Race.combIO k src0 src1)) 1
        n := n + 2
        statesTotal := statesTotal + r1.states + r2.states
        let ok := r1.closed && r1.leakFree && r2.closed && r2.leakFree
        if !ok then bad := bad + 1
        IO.println s!"{repr k} {na} {nb}: direct {r1.states} states, {r1.done} done, closed {r1.closed}, ok {r1.leakFree}; parent {r2.states} states, {r2.done} done, closed {r2.closed}, ok {r2.leakFree}"
  for (na, a) in fam do
    for d in [0, 1, 2] do
      let e := env a a u0
      let r1 := check e (Timeout.timeoutIO src0 d) 0
      let r2 := check e (parentIO (Timeout.timeoutIO src0 d)) 1
      n := n + 2
      statesTotal := statesTotal + r1.states + r2.states
      let ok := r1.closed && r1.leakFree && r2.closed && r2.leakFree
      if !ok then bad := bad + 1
      IO.println s!"timeout {na} d={d}: direct {r1.states} states, {r1.done} done, closed {r1.closed}, ok {r1.leakFree}; parent {r2.states} states, {r2.done} done, closed {r2.closed}, ok {r2.leakFree}"
  -- wrong-function test
  let wf := check (noCancelEnv (.pure (.nat 1)) Timeout.neverIO) (Race.combIO .race src0 src1) 0
  IO.println s!"wrong function (race without cancel) on race(pure 1, never): closed {wf.closed}, leakFree {wf.leakFree} (expected false)"
  if wf.leakFree || !wf.closed then bad := bad + 1
  -- the closed law
  let law := checkEqvP {} counterMaskModel lawEnv bound raceNotInheritedLhs Timeout.neverIO
  IO.println s!"uncancelableRaceNotInherited: checkEqvP = {law}"
  if !law then bad := bad + 1
  IO.println s!"checks {n}, states {statesTotal}, failed groups {bad}"
  return if bad == 0 then 0 else 1

import CatsEffectInLean.Props.Phase6.Race

/-!
# Leak smoke test (Phase 6, track R)

Random-schedule smoke test of the statements in `Props/Phase6/Race.lean`. For each kernel
default `k` (`race`, `raceOutcome`, `both`, `bothOutcome`) and each pair of sides from `fam`,
and for `timeout` with each side and duration: `runs` random `PChoice` lists (preemption rate
0, 5, 20, 50 %, fuel 20,000), in the direct form (racing fiber 0) and the parent form of
decision 50 (racing fiber 1). At each run where the root completed: no live race child
(`liveRaceChildren`), and for `raceOutcome` the result is the winner's outcome.

An exact search (`exploreP`) is not used: with three fibers and a preemption at every run-loop
iteration the state sets grow past 10^4 states (the law below: 994 states after 800 expansions,
not closed), and `exploreP` is quadratic.

Also: the wrong-function test (a `race` that never cancels the loser must leak), and the
observations of random runs of both sides of `uncancelableRaceNotInherited`.

`lake exe leaksmoke [runs]` (default 200). Exit code 1 if a check fails.
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

def kinds : List Race.Kind := [.race, .raceOutcome, .both, .bothOutcome]

end LeakSmoke

namespace LeakSmoke

/-- A random choice list: `preempt` with probability `pp`/100, else `pick i` (`i < 4`). -/
def randChoices (g : StdGen) (n pp : Nat) : List PChoice × StdGen := Id.run do
  let mut g := g
  let mut cs : Array PChoice := #[]
  for _ in [0:n] do
    let (x, g1) := randNat g 0 99
    let (i, g2) := randNat g1 0 3
    g := g2
    cs := cs.push (if x < pp then .preempt else .pick i)
  return (cs.toList, g)

/-- `runs` random schedules of `io`: (completed runs, violations). `extra` is an additional
check on completed states. -/
def randCheck (e : UserEnv) (io : IO) (r : Nat) (runs : Nat) (seed : Nat)
    (extra : Sched CounterMask → Bool := fun _ => true) : Nat × Nat := Id.run do
  let mut g := mkStdGen seed
  let mut done := 0
  let mut bad := 0
  for k in [0:runs] do
    let (cs, g1) := randChoices g 400 ([0, 5, 20, 50][k % 4]!)
    g := g1
    let s := runSchedStateP {} counterMaskModel e 20000 cs (Sched.init counterMaskModel io)
    if s.rootDone then
      done := done + 1
      if !(liveRaceChildren s r).isEmpty || !extra s then bad := bad + 1
  return (done, bad)

end LeakSmoke

open LeakSmoke in
def main (args : List String) : IO UInt32 := do
  let out ← IO.getStdout
  let runs := match args with | [n] => n.toNat! | _ => 200
  let mut bad : Nat := 0
  let mut doneTot : Nat := 0
  let mut runTot : Nat := 0
  let mut seed : Nat := 1
  for k in kinds do
    for (na, a) in fam do
      for (nb, b) in fam do
        let e := env a b u0
        let extra := if k == .raceOutcome then winnerOK else fun _ => true
        let (d1, b1) := randCheck e (Race.combIO k src0 src1) 0 runs seed extra
        let (d2, b2) := randCheck e (parentIO (Race.combIO k src0 src1)) 1 runs (seed + 1)
        seed := seed + 2
        runTot := runTot + 2 * runs; doneTot := doneTot + d1 + d2; bad := bad + b1 + b2
        if b1 + b2 > 0 then IO.println s!"VIOLATION {repr k} {na} {nb}: direct {b1}, parent {b2}"
    IO.println s!"{repr k}: done"; out.flush
  for (na, a) in fam do
    for d in [0, 1, 2] do
      let e := env a a u0
      let (d1, b1) := randCheck e (Timeout.timeoutIO src0 d) 0 runs seed
      let (d2, b2) := randCheck e (parentIO (Timeout.timeoutIO src0 d)) 1 runs (seed + 1)
      seed := seed + 2
      runTot := runTot + 2 * runs; doneTot := doneTot + d1 + d2; bad := bad + b1 + b2
      if b1 + b2 > 0 then IO.println s!"VIOLATION timeout {na} d={d}: direct {b1}, parent {b2}"
  IO.println s!"runs {runTot}, root completed {doneTot}, violations {bad}"
  -- wrong-function test: a `race` that never cancels the loser must leak
  let (wd, wb) := randCheck (noCancelEnv (.pure (.nat 1)) Timeout.neverIO) (Race.combIO .race src0 src1) 0 runs 7
  IO.println s!"wrong function (race without cancel) on race(pure 1, never): completed {wd}, violations {wb} (expected > 0)"
  -- the closed law: observations of random runs of both sides
  let obsOf (io : IO) : List Obs := Id.run do
    let mut g := mkStdGen 99
    let mut os : List Obs := []
    for k in [0:runs] do
      let (cs, g1) := randChoices g 400 ([0, 5, 20, 50][k % 4]!)
      g := g1
      match runObsP {} counterMaskModel lawEnv 20000 cs io with
      | some o => if !os.contains o then os := o :: os
      | none => pure ()
    return os
  let lo := obsOf raceNotInheritedLhs
  let ro := obsOf Timeout.neverIO
  IO.println s!"uncancelableRaceNotInherited: lhs observations {repr lo}; rhs {repr ro}"
  let lawOK := lo == ro
  return if bad == 0 && wb > 0 && lawOK then 0 else 1

import CatsEffectInLean.Props.Phase7.CountDownLatch
import CatsEffectInLean.Props.Phase7.CyclicBarrier

/-!
# Smoke tests of the `CountDownLatch` and `CyclicBarrier` statements (Phase 7, track L)

Random inputs and random `PChoice` schedules (a fixed LCG; `preempt` with probability 1/4 at
each micro-step), for the seven statements of `Props/Phase7/CountDownLatch.lean` and
`Props/Phase7/CyclicBarrier.lean`, and the wrong-function tests (variants `v ≠ 0` of the
mirrors). The safety statements (`cdlAwaitNotEarly`, `cbNoEarlyTrip`, `cbCancelRemoved`) are
checked in **every** state of a run (each prefix of the schedule), the others in the final
state. Native evaluation (`#guard`), not part of the build:

    lake env lean test/Phase7/LatchSmoke.lean

The hypotheses are evaluated too (decision 53): every user program passes `WF.progOK` with the
statement library and `H0 = []`, and `as.length < cap` is checked where statement 4 needs it.
The user environment `uR` ignores its argument and its view and returns closed programs (so
`CallOK` and `PollOpaque` hold by the argument of `Proofs/Phase7/LatchWitness.lean`, `wf`).
Results are in `wiki/cats-effect/latch-barrier-model.md`.
-/

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

namespace LatchSmoke

/-- User code: id 2 `_ => pure 7`, id 4 `_ => canceled`. -/
def uR (id : Nat) (_ : Val) (_ : View) : UserResult :=
  match id with
  | 2 => { out := .prog (.pure (.nat 7)) }
  | 4 => { out := .prog .canceled }
  | _ => { out := .throw { code := 0 } }

def u : UserEnv := { call := fun id a refs => uR id a { refs }, callV := uR }

/-- A program that waits forever (the mirror's `await` selector on a new `Deferred`). -/
def nv : IO :=
  .flatMap (.map (.delay CatsEffectInLean.Std.CountDownLatch.CLam.newDeferred.fn)
    (CatsEffectInLean.Std.CountDownLatch.CLam.awaitingK 1).fn)
    CatsEffectInLean.Std.CountDownLatch.CLam.awaitSel.fn

/-- The user programs: pure, cede, sleep, self-cancel, masked self-cancel (observed at the next
`poll`), error, `cede` then pure, never. -/
def progs : Array IO :=
  #[.pure .unit, .cede, .sleep 3, .canceled, .uncancelable (.user 4), .error { code := 5 },
    .flatMap .cede (.user 2), .pure .unit, .cede]

/-- `nv` only in some runs (it blocks the run). -/
def progsNv : Array IO := progs.push nv

/-- LCG. -/
def next (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648

def sched (seed len : Nat) : List PChoice := Id.run do
  let mut x := seed * 2654435761 + 7
  let mut cs : Array PChoice := #[]
  for _ in [0:len] do
    x := next x
    if x % 4 == 0 then cs := cs.push .preempt else cs := cs.push (.pick ((x / 4) % 4))
  return cs.toList

/-- Random inputs: a count in 1..3, two lists of 0..3 programs, a list of cancel indices. -/
structure Inp where
  k : Nat
  xs : List IO
  ys : List IO
  cancels : List Nat

def inp (seed : Nat) (withNv : Bool) : Inp := Id.run do
  let mut x := next (seed * 7919 + 13)
  let pool := if withNv then progsNv else progs
  let k := 1 + x % 3
  x := next x
  let lx := x % 4
  x := next x
  let ly := x % 4
  let mut xs : List IO := []
  for _ in [0:lx] do
    x := next x
    xs := xs ++ [pool.getD (x % pool.size) (.pure .unit)]
  let mut ys : List IO := []
  for _ in [0:ly] do
    x := next x
    ys := ys ++ [pool.getD (x % pool.size) (.pure .unit)]
  let mut cs : List Nat := []
  for i in [0:lx] do
    x := next x
    if x % 3 == 0 then cs := cs ++ [i]
  return { k, xs, ys, cancels := cs }

def fuel : Nat := 2500
def nRuns : Nat := 1500

/-- All states of a run, from the initial state (each prefix of the schedule). -/
def states (env : UserEnv) (io : IO) (cs : List PChoice) : List (Sched CounterMask) := Id.run do
  let mut s : Sched CounterMask := Sched.init counterMaskModel io
  let mut out : Array (Sched CounterMask) := #[s]
  let mut c := cs
  for _ in [0:fuel] do
    match s.halt with
    | some _ => break
    | none =>
      s := s.tickP {} counterMaskModel env (c.headD (.pick 0))
      c := c.tail
      out := out.push s
  return out.toList

/-! ## `CountDownLatch` -/

namespace C
open CatsEffectInLean.Props.Phase7.CountDownLatch

/-- One run: `(hypotheses hold, all states, final state)`. -/
def runOf (i v : Nat) : Bool × List (Sched CounterMask) :=
  let x := inp i (i % 3 == 0)
  let ok := (x.xs ++ x.ys).all fun q => WF.progOK cdlLib (fun h => ([] : List Handle).contains h) q
  (ok, states (env x.xs x.ys u) (prog x.k x.xs x.cancels v) (sched i 300))

def nOf (i : Nat) : Nat := (inp i (i % 3 == 0)).k

def bad1 (n : Nat) (s : Sched CounterMask) : Bool :=
  (List.range 4).any (fun j => status s j == 2) && started s < n
def bad2 (n : Nat) (s : Sched CounterMask) : Bool :=
  s.halt == some .blocked && n ≤ started s && (List.range 4).any (fun j => status s j == 1)
def bad3 (s : Sched CounterMask) : Bool :=
  (s.halt == some .blocked || (match s.halt with | some (.done _) => true | _ => false)) &&
    completed s != started s

/-- `(hypothesis failures, violations of 1, 2, 3, blocked runs, runs with a passed awaiter)`. -/
def stats (v : Nat) : Nat × Nat × Nat × Nat × Nat × Nat := Id.run do
  let mut r := (0, 0, 0, 0, 0, 0)
  for i in [0:nRuns] do
    let (ok, ss) := runOf i v
    let n := nOf i
    let last := ss.getLastD (Sched.init counterMaskModel (.pure .unit))
    r := (r.1 + (if ok then 0 else 1),
          r.2.1 + (if ss.any (bad1 n) then 1 else 0),
          r.2.2.1 + (if bad2 n last then 1 else 0),
          r.2.2.2.1 + (if bad3 last then 1 else 0),
          r.2.2.2.2.1 + (if last.halt == some .blocked then 1 else 0),
          r.2.2.2.2.2 + (if (List.range 4).any (fun j => status last j == 2) then 1 else 0))
  return r

#eval stats 0
-- v3.7.1: hypotheses hold, no violation; the interesting cases occur
#guard let r := stats 0; r.1 == 0 && r.2.1 == 0 && r.2.2.1 == 0 && r.2.2.2.1 == 0 &&
  r.2.2.2.2.1 > 0 && r.2.2.2.2.2 > 0
-- wrong functions: each violates its statement
#eval (stats 1).2.1
#guard (stats 1).2.1 > 0
#eval (stats 2).2.2.1
#guard (stats 2).2.2.1 > 0
#eval (stats 3).2.2.2.1
#guard (stats 3).2.2.2.1 > 0

/-! Statement 4 (`cdlAwaitCompletes`, decision 63): a done root leaves no awaiter at status 1.
Variant 8 (`await` raises) breaks it. -/
def isDone (s : Sched CounterMask) : Bool := match s.halt with | some (.done _) => true | _ => false
def bad4 (s : Sched CounterMask) : Bool := isDone s && (List.range 4).any (fun j => status s j == 1)
def viol4 (v : Nat) : Nat × Nat := Id.run do
  let mut r := (0, 0)
  for i in [0:nRuns] do
    let last := (runOf i v).2.getLastD (Sched.init counterMaskModel (.pure .unit))
    r := (r.1 + (if bad4 last then 1 else 0), r.2 + (if isDone last then 1 else 0))
  return r
#eval (viol4 0, viol4 8)
#guard (viol4 0).1 == 0 && (viol4 0).2 > 0 && (viol4 8).1 > 0

end C

/-! ## `CyclicBarrier` -/

namespace B
open CatsEffectInLean.Props.Phase7.CyclicBarrier

def runOf (i v : Nat) (noCancel : Bool) : Bool × Inp × List (Sched CounterMask) :=
  -- no `nv` here: it uses `CountDownLatch` closures, which `cbLib` does not list
  let x := inp (i + 100000) false
  let cs := if noCancel then [] else x.cancels
  let ok := (x.xs ++ x.ys).all fun q => WF.progOK cbLib (fun h => ([] : List Handle).contains h) q
  (ok, x, states (env x.xs x.ys u) (prog (x.k + 0) x.xs x.ys cs v) (sched (i + 7) 300))

def bad1 (cap : Nat) (s : Sched CounterMask) : Bool := !(decide (passed s ≤ cap * (entered s / cap)))
def bad2 (cap : Nat) (s : Sched CounterMask) : Bool :=
  s.halt == some .blocked && (passed s % cap != 0 || !(decide (waiting s < cap)))
def bad3 (cap : Nat) (s : Sched CounterMask) : Bool := s.halt == some .blocked && !(decide (waiting s < cap))
def bad4 (cap : Nat) (s : Sched CounterMask) : Bool :=
  !(decide (passed s ≤ cap * ((entered s - canceledIn s) / cap)))

/-- Statements 1 and 2 (no program cancel): `(hyp failures, viol 1, viol 2, blocked, trips)`. -/
def stats12 (v : Nat) : Nat × Nat × Nat × Nat × Nat := Id.run do
  let mut r := (0, 0, 0, 0, 0)
  for i in [0:nRuns] do
    let (ok, x, ss) := runOf i v true
    let last := ss.getLastD (Sched.init counterMaskModel (.pure .unit))
    r := (r.1 + (if ok then 0 else 1),
          r.2.1 + (if ss.any (bad1 x.k) then 1 else 0),
          r.2.2.1 + (if bad2 x.k last then 1 else 0),
          r.2.2.2.1 + (if last.halt == some .blocked then 1 else 0),
          r.2.2.2.2 + (if passed last > 0 then 1 else 0))
  return r

/-- Statements 3 and 4 (program cancels): `(hyp failures, viol 3, viol 4 (where as.length < cap),
runs where 4 applies, runs with a canceled waiter)`. -/
def stats34 (v : Nat) : Nat × Nat × Nat × Nat × Nat := Id.run do
  let mut r := (0, 0, 0, 0, 0)
  for i in [0:nRuns] do
    let (ok, x, ss) := runOf i v false
    let last := ss.getLastD (Sched.init counterMaskModel (.pure .unit))
    let app4 := x.xs.length < x.k
    r := (r.1 + (if ok then 0 else 1),
          r.2.1 + (if bad3 x.k last then 1 else 0),
          r.2.2.1 + (if app4 && ss.any (bad4 x.k) then 1 else 0),
          r.2.2.2.1 + (if app4 then 1 else 0),
          r.2.2.2.2 + (if canceledIn last > 0 then 1 else 0))
  return r

#eval stats12 0
#guard let r := stats12 0; r.1 == 0 && r.2.1 == 0 && r.2.2.1 == 0 && r.2.2.2.1 > 0 && r.2.2.2.2 > 0
#eval stats34 0
#guard let r := stats34 0; r.1 == 0 && r.2.1 == 0 && r.2.2.1 == 0 && r.2.2.2.1 > 0 && r.2.2.2.2 > 0
-- wrong functions
#eval (stats12 1).2.1
#guard (stats12 1).2.1 > 0
#eval (stats12 4).2.2.1
#guard (stats12 4).2.2.1 > 0
#eval (stats34 2).2.2.1
#guard (stats34 2).2.2.1 > 0
#eval (stats34 3).2.1

/-! Two input shapes with many schedules, for the cancel races (random inputs rarely hit them):
`race`: `cap = 2`, two group A awaiters, cancel A0, two group B awaiters (statement 3; the
no-epoch-check variant 3 hangs when A1 trips before A0's cleanup runs); `removal`: `cap = 2`, one
group A awaiter, cancel A0, one group B awaiter (statement 4, `as.length < cap`; variant 2 lets
B0 trip alone). -/

/-- Schedules for the shapes: FIFO for `i % 40` micro-steps, a preemption of the root, then (in
every second block of 40 runs) 40 FIFO micro-steps, then a random schedule. The cancel must land
while A0 waits; that window is narrow (FIFO prefix of 9 or 10 steps), so pure random schedules
rarely hit it. -/
def shapeSched (i : Nat) : List PChoice :=
  List.replicate (i % 40) (.pick 0) ++ [.preempt] ++ List.replicate (40 * ((i / 40) % 2)) (.pick 0) ++
    sched (i + 31) 200

def shapeRuns (as bs : List IO) (v : Nat) : List (List (Sched CounterMask)) :=
  (List.range 800).map fun i => states (env as bs u) (prog 2 as bs [0] v) (shapeSched i)

def raceViol (v : Nat) : Nat :=
  ((shapeRuns [.pure .unit, .pure .unit] [.pure .unit, .pure .unit] v).filter
    (fun ss => bad3 2 (ss.getLastD (Sched.init counterMaskModel (.pure .unit))))).length
def removalViol (v : Nat) : Nat :=
  ((shapeRuns [.pure .unit] [.pure .unit] v).filter (fun ss => ss.any (bad4 2))).length
def removalCanceled : Nat :=
  ((shapeRuns [.pure .unit] [.pure .unit] 0).filter
    (fun ss => canceledIn (ss.getLastD (Sched.init counterMaskModel (.pure .unit))) > 0)).length

#eval (raceViol 0, raceViol 3, removalViol 0, removalViol 2, removalCanceled)
#guard raceViol 0 == 0 && removalViol 0 == 0
#guard raceViol 3 > 0 && removalViol 2 > 0 && removalCanceled > 0

/-! Statement 5 (`cbAwaitCompletes`, decision 63): a done root leaves `waiting = 0`. Variant 5
(`await` raises) breaks it. -/
def isDone (s : Sched CounterMask) : Bool := match s.halt with | some (.done _) => true | _ => false
def viol5 (v : Nat) : Nat × Nat := Id.run do
  let mut r := (0, 0)
  for i in [0:nRuns] do
    let last := (runOf i v false).2.2.getLastD (Sched.init counterMaskModel (.pure .unit))
    r := (r.1 + (if isDone last && waiting last != 0 then 1 else 0), r.2 + (if isDone last then 1 else 0))
  return r
#eval (viol5 0, viol5 5)
#guard (viol5 0).1 == 0 && (viol5 0).2 > 0 && (viol5 5).1 > 0

end B

end LatchSmoke

import CatsEffectInLean.Props.Phase6.ParTraverse
import CatsEffectInLean.Model.EnumP

/-!
# `parTraverseN` smoke test (Phase 6, batch 6.3)

Random-schedule smoke test of the four statements in `Props/Phase6/ParTraverse.lean`. For each
input it first checks the decidable hypotheses (`n ≥ 1`, length ≤ 4, `f` even, `a0` among the
first `n` inputs, the start program passes `progOK` with no handle; the user code is a fixed,
handle-free table, as in `Proofs/Phase6/ParTraverseWitness.lean`). Then `runs` random `PChoice`
lists (preemption rate 0, 5, 20, 50 %, fuel 20,000): every run that stops (`Sched.obs`) must meet
the claim.

Wrong-function tests (each must break its claim):
* statement 1: the result list reversed (`Map` with a harness `reverse`);
* statement 2: the last result dropped;
* statements 3, 4: `cancelAll` removed from the error (cancel) branch of the action finalizer
  (`K/GC:197-213`): the traversal then waits for the never-ending action.

An exact search (`exploreP`) is not used: with up to five fibers and a preemption at every run-loop
iteration the state sets are too large (track R measured > 10^4 states for three fibers).

`lake exe ptsmoke [runs]` (default 100). Exit code 1 if a check fails.
-/

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.ParTraverse
open CatsEffectInLean.Props.Phase6.ParTraverse

namespace PtSmoke

/-- User code: id 2 `_ => IO.pure(0)`, 4 `a => IO.cede.as(a)` (via 10), 6 `_ => IO.sleep(1).as(0)`
(via 12), 8 `_ => IO.raiseError(E3)`, 10 `_ => IO.pure(7)` (map target), 12 `_ => IO.pure(0)`,
14 `_ => IO.canceled`; and `a0`-dependent ids 20 (raise E5) / 22 (canceled) with `a0 = 1`. -/
def uR (id : Nat) (a : Val) : UserResult :=
  match id with
  | 2 => { out := .prog (.pure (.nat 0)) }
  | 4 => { out := .prog (.flatMap .cede (.user 10)) }
  | 6 => { out := .prog (.flatMap (.sleep 1) (.user 12)) }
  | 8 => { out := .prog (.error { code := 3 }) }
  | 10 => { out := .prog (.pure (.nat 7)) }
  | 12 => { out := .prog (.pure (.nat 0)) }
  | 14 => { out := .prog .canceled }
  | 20 => { out := .prog (if a = .nat 1 then .error { code := 5 } else Timeout.neverIO) }
  | 22 => { out := .prog (if a = .nat 1 then .canceled else Timeout.neverIO) }
  | _ => { out := .throw { code := 0 } }

def u : UserEnv where
  call id a _ := uR id a

/-- Wrong function for statements 3, 4: no `cancelAll` in the error/cancel branch. -/
def noCancelAll (e : UserEnv) : UserEnv where
  call := e.call
  callV id arg v :=
    match PT.ofId? id, arg with
    | some (.ifErr _ r err), .bool true => { out := .prog (completeIO r (.ocErrored err)) }
    | some (.ifCan _ r), .bool true => { out := .prog (completeIO r .ocCanceled) }
    | _, _ => e.callV id arg v

/-- A random choice list: `preempt` with probability `pp`/100, else `pick i` (`i < 6`). -/
def randChoices (g : StdGen) (n pp : Nat) : List PChoice × StdGen := Id.run do
  let mut g := g
  let mut cs : Array PChoice := #[]
  for _ in [0:n] do
    let (x, g1) := randNat g 0 99
    let (i, g2) := randNat g1 0 5
    g := g2
    cs := cs.push (if x < pp then .preempt else .pick i)
  return (cs.toList, g)

/-- `runs` random schedules: (stopped runs, runs that break `claim`). -/
def randCheck (e : UserEnv) (io : IO) (runs seed : Nat) (claim : Obs → Bool) : Nat × Nat := Id.run do
  let mut g := mkStdGen seed
  let mut stopped := 0
  let mut bad := 0
  for k in [0:runs] do
    let (cs, g1) := randChoices g 600 ([0, 5, 20, 50][k % 4]!)
    g := g1
    match runObsP {} counterMaskModel e 20000 cs io with
    | some o =>
      stopped := stopped + 1
      if !claim o then bad := bad + 1
    | none => pure ()
  return (stopped, bad)

def startOK (p : IO) : Bool := WF.progOK ptIsLib (fun h => ([] : List Handle).contains h) p

def lists : List (List Val) :=
  [[], [.nat 1], [.nat 1, .nat 2], [.nat 2, .nat 1, .nat 3], [.nat 1, .nat 2, .nat 3, .nat 4]]

def orderClaim (as : List Val) (o : Obs) : Bool :=
  match o.summary with
  | .done (.succeeded v) => (unlistV v).map (·.map fstOf) == some as
  | _ => true

end PtSmoke

open PtSmoke in
def main (args : List String) : IO UInt32 := do
  let runs := match args with | [n] => n.toNat! | _ => 100
  let mut bad : Nat := 0
  let mut stoppedTot : Nat := 0
  let mut seed : Nat := 1
  -- statement 1: all user functions, all n, all lists
  for f in [2, 4, 6, 8, 14] do
    for n in [1, 2, 3] do
      for as in lists do
        let io := parTraverseNIO n as (TL.tag f).id
        if !startOK io then IO.println s!"HYPOTHESIS order f={f} n={n}"; bad := bad + 1
        let (d, b) := randCheck (env (tagged u)) io runs seed (orderClaim as)
        seed := seed + 1; stoppedTot := stoppedTot + d; bad := bad + b
        if b > 0 then IO.println s!"VIOLATION order f={f} n={n} as={repr as}: {b}"
  IO.println "statement 1: done"
  -- statement 2: f = _ => IO.pure(0) (g = const 0)
  for n in [1, 2, 3] do
    for as in lists do
      let io := parTraverseNIO n as 2
      if !startOK io then IO.println s!"HYPOTHESIS pure n={n}"; bad := bad + 1
      let want : Summary := .done (.succeeded (listV (as.map fun _ => .nat 0)))
      let (d, b) := randCheck (env u) io runs seed (fun o => o.summary == want)
      seed := seed + 1; stoppedTot := stoppedTot + d; bad := bad + b
      if b > 0 then IO.println s!"VIOLATION pure n={n} as={repr as}: {b}"
  IO.println "statement 2: done"
  -- statements 3, 4: a0 = 1 among the first n inputs
  for (f, want) in [(20, Summary.done (.errored { code := 5 })), (22, .done .canceled)] do
    for n in [1, 2, 3] do
      for as in lists do
        if (as.take n).contains (.nat 1) then
          let io := parTraverseNIO n as f
          if !startOK io then IO.println s!"HYPOTHESIS abort f={f} n={n}"; bad := bad + 1
          let (d, b) := randCheck (env u) io runs seed (fun o => o.summary == want)
          seed := seed + 1; stoppedTot := stoppedTot + d; bad := bad + b
          if b > 0 then IO.println s!"VIOLATION abort f={f} n={n} as={repr as}: {b}"
  IO.println "statements 3, 4: done"
  IO.println s!"stopped runs {stoppedTot}, violations {bad}"
  -- wrong functions
  let rev : UserEnv := { call := (env (tagged u)).call
                         callV := fun id a v => if id == 1000001 then { out := .ret (listV ((unlistV a).getD []).reverse) } else (env (tagged u)).callV id a v }
  let as2 := [Val.nat 1, .nat 2]
  let (_, w1) := randCheck rev (.map (parTraverseNIO 2 as2 (TL.tag 2).id) (.user 1000001)) runs 7 (orderClaim as2)
  let drop : UserEnv := { call := (env u).call
                          callV := fun id a v => if id == 1000001 then { out := .ret (listV ((unlistV a).getD []).dropLast) } else (env u).callV id a v }
  let (_, w2) := randCheck drop (.map (parTraverseNIO 2 as2 2) (.user 1000001)) runs 8
    (fun o => o.summary == .done (.succeeded (listV [.nat 0, .nat 0])))
  let as3 := [Val.nat 2, .nat 1]
  let (_, w3) := randCheck (noCancelAll (env u)) (parTraverseNIO 2 as3 20) runs 9
    (fun o => o.summary == .done (.errored { code := 5 }))
  let (_, w4) := randCheck (noCancelAll (env u)) (parTraverseNIO 2 as3 22) runs 10
    (fun o => o.summary == .done .canceled)
  IO.println s!"wrong functions (runs that break the claim, expected > 0): reverse {w1}, drop {w2}, no cancelAll on error {w3}, on cancel {w4}"
  return if bad == 0 && w1 > 0 && w2 > 0 && w3 > 0 && w4 > 0 then 0 else 1

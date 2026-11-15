import CatsEffectInLean.Props.Phase7.Queue
import CatsEffectInLean.Proofs.Phase7.QueueWrongFunction
import CatsEffectInLean.Model.EnumP

/-!
# `Queue` smoke test (Phase 7, track Q)

Random-schedule smoke test of the statements in `Props/Phase7/Queue.lean`. For each random harness
input (kind, scripts, cancel plan) it checks the decidable hypotheses, then runs `runs` random
`PChoice` lists (preemption rate 0, 5, 20, 50 %, fuel 20,000). Every run that stops
(`Sched.obs`) must meet the claim of each statement whose hypotheses hold.

Wrong-function tests (`lake exe qsmoke wrong`): the ten wrong functions of
`Proofs/Phase7/QueueWrongFunction.lean`, each under 200 random schedules on its input; each must
break its claim, and the real mirror must meet it.

`lake exe qsmoke [cases] [runs] [seed]` (default 200 cases, 20 runs, seed 1). Exit code 1 if a
check fails. `lake exe qsmoke demo` prints the traces of a few fixed programs.
-/

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue
open CatsEffectInLean.Proofs.Phase7.QueueWrongFunction

namespace QSmoke

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

def isSublist : List Val → List Val → Bool
  | [], _ => true
  | _, [] => false
  | x :: xs, y :: ys => if x == y then isSublist xs ys else isSublist (x :: xs) ys

def subMulti (a b : List Val) : Bool := a.all fun x => a.count x ≤ b.count x

/-- The claims (decidable forms) for one run. -/
def noLossC (o : Obs) : Bool := o.summary != .done (.succeeded .unit) || subMulti (offeredOf o.out) (removedOf o.out)
def noDupC (scripts : List (List Op)) (o : Obs) : Bool := subMulti (removedOf o.out) (allOffers scripts)
/-- `Fifo` per remover (each script index, and the drain) and per producer (review batch 11a). -/
def fifoC (scripts : List (List Op)) (o : Obs) : Bool :=
  ((List.range scripts.length).map some ++ [none]).all fun c =>
    scripts.all fun s => isSublist ((removedBy o.out c).filter (· ∈ offersOf s)) (offersOf s)
def doneC (o : Obs) : Bool := o.summary == .done (.succeeded .unit)
/-- Statement 7 (`SeqSpec`) for one fiber running `s` on kind `k`. -/
def specC (k : QKind) (s : List Op) (o : Obs) : Bool :=
  let t := specRun (ruleOf k) [] s
  events o.out == t.1 && o.summary == (if t.2 then .blocked else .done (.succeeded .unit))
/-- Statement 5 with the join outcomes (review batch 12 H3). -/
def liveC (scripts : List (List Op)) (plan : List (Nat × Nat)) (o : Obs) : Bool :=
  (doneC o && (takers scripts).all fun i => plan.any (·.2 == i) ||
    (events o.out).any fun e => e.1 == evJoined && e.2.1 == i && (match e.2.2 with | .ocSucceeded _ => true | _ => false)) ||
  (o.summary == .blocked && subMulti (offeredOf o.out) (removedOf o.out) && subMulti (startedOf o.out) (offeredOf o.out))

def keepKinds : List QKind := [.boundedConc 1, .boundedConc 2, .unboundedConc, .synchronous, .bounded 2, .bounded 3, .unbounded]
def anyKinds : List QKind := keepKinds ++ [.droppingConc 1, .droppingConc 2, .circular 1, .circular 2, .dropping 2]

def isConc : QKind → Bool
  | .boundedConc _ | .unboundedConc | .synchronous | .droppingConc _ | .circular _ => true
  | .bounded c => !(1 < c && c < asyncLimit)
  | .dropping c => !(1 < c && c < asyncLimit)
  | .unbounded => false

def keeps : QKind → Bool
  | .droppingConc _ | .circular _ | .dropping _ => false
  | _ => true

/-- A random script with elements from `next`. -/
def randScript (g : StdGen) (next : Nat) (len : Nat) (prodOnly consOnly : Bool) : List Op × Nat × StdGen := Id.run do
  let mut g := g
  let mut n := next
  let mut ops : Array Op := #[]
  for _ in [0:len] do
    let (r, g1) := randNat g 0 99
    g := g1
    let op : Op :=
      if prodOnly then .offer (.nat n)
      else if consOnly then .take
      else if r < 35 then .offer (.nat n)
      else if r < 60 then .take
      else if r < 70 then .tryTake
      else if r < 80 then .tryOffer (.nat n)
      else if r < 90 then .cede
      else .size
    match op with
    | .offer _ | .tryOffer _ => n := n + 1
    | _ => pure ()
    ops := ops.push op
  return (ops.toList, n, g)

structure Case where
  k : QKind
  scripts : List (List Op)
  plan : List (Nat × Nat)
  deriving Repr

def randCase (g : StdGen) (pc : Bool) : Case × StdGen := Id.run do
  let mut g := g
  let (ki, g1) := randNat g 0 (anyKinds.length - 1)
  let (nf, g2) := randNat g1 1 3
  g := g2
  let k := (if pc then keepKinds else anyKinds).getD (ki % (if pc then keepKinds.length else anyKinds.length)) .unbounded
  let mut next := 1
  let mut scripts : Array (List Op) := #[]
  for i in [0:nf] do
    let (len, g3) := randNat g 1 4
    let (rk, g4) := randNat g3 0 1
    g := g4
    let (s, n2, g5) := randScript g next len (pc && (i == 0 || rk == 0)) (pc && i != 0 && rk == 1)
    scripts := scripts.push s; next := n2; g := g5
  let (np, g6) := randNat g 0 2
  g := g6
  let mut plan : Array (Nat × Nat) := #[]
  for _ in [0:np] do
    let (c, g7) := randNat g 0 3
    let (i, g8) := randNat g7 0 (nf - 1)
    g := g8
    plan := plan.push (c, i)
  return ({ k, scripts := scripts.toList, plan := plan.toList }, g)

/-- Run `io` under `runs` random schedules: (stopped runs, first failing observation). -/
def randCheck (e : UserEnv) (io : IO) (runs seed : Nat) (claim : Obs → Bool) : Nat × Option (List PChoice × Obs) := Id.run do
  let mut g := mkStdGen seed
  let mut stopped := 0
  for k in [0:runs] do
    let (cs, g1) := randChoices g 400 ([0, 5, 20, 50][k % 4]!)
    g := g1
    match runObsP {} counterMaskModel e 20000 cs io with
    | some o =>
      stopped := stopped + 1
      if !claim o then return (stopped, some (cs, o))
    | none => pure ()
  return (stopped, none)

def evStr (out : List Val) : String := toString (repr (events out))

def demo : IO Unit := do
  let progs : List (String × QKind × List (List Op) × List (Nat × Nat) × Mode) := [
    ("conc bounded 1: offer 1 2 / take take", .boundedConc 1, [[.offer (.nat 1), .offer (.nat 2)], [.take, .take]], [], .join [0, 1]),
    ("async bounded 2: offer 1 2 3 / take take take", .bounded 2, [[.offer (.nat 1), .offer (.nat 2), .offer (.nat 3)], [.take, .take, .take]], [], .join [0, 1]),
    ("unbounded: take / offer 1", .unbounded, [[.take], [.offer (.nat 1)]], [], .join [0, 1]),
    ("sync: offer 1 / take", .synchronous, [[.offer (.nat 1)], [.take]], [], .join [0, 1]),
    ("circular 2: offer 1 2 3, drain", .circular 2, [[.offer (.nat 1), .offer (.nat 2), .offer (.nat 3), .size]], [], .join [0]),
    ("dropping conc 2: offer 1 2 3 tryOffer 4", .droppingConc 2, [[.offer (.nat 1), .offer (.nat 2), .offer (.nat 3), .tryOffer (.nat 4), .tryTake]], [], .join [0]),
    ("dropping async 2", .dropping 2, [[.offer (.nat 1), .offer (.nat 2), .offer (.nat 3), .size]], [], .join [0]),
    ("conc bounded 1 cancel taker", .boundedConc 1, [[.take], [.offer (.nat 1)]], [(1, 0)], .cancelAll)]
  for (name, k, scripts, plan, mode) in progs do
    match runObsP {} counterMaskModel henv 20000 [] (rootIO k scripts plan mode) with
    | some o => IO.println s!"{name}: {repr o.summary} {evStr o.out}"
    | none => IO.println s!"{name}: no stop"

end QSmoke

open QSmoke in
def main (args : List String) : IO UInt32 := do
  if args == ["demo"] then demo; return 0
  if args.head? == some "exact" then
    -- exhaustive: every `PChoice` schedule of small inputs (`outcomesPList`, sound by
    -- `outcomesPList_sound`); every observation must meet the claims
    let bound := match args with | _ :: b :: _ => b.toNat! | _ => 4000
    -- one fiber (the root cancels it at every point): larger inputs do not close (3 fibers with a
    -- preemption at every run-loop iteration)
    let inputs : List (List (List Op) × List (Nat × Nat)) := [
      ([[.take]], [(0, 0)]),
      ([[.offer (.nat 1), .offer (.nat 2)]], [(0, 0)]),
      ([[.offer (.nat 1), .take]], [(0, 0)])]
    let mut bad := 0
    for k in anyKinds do
      for (sc, plan) in inputs do
        let t0 ← IO.monoMsNow
        match outcomesPList {} counterMaskModel henv bound (rootIO k sc plan .cancelAll) with
        | some os =>
          let fails := os.filter fun o =>
            !(noDupC sc o && doneC o && (!keeps k || noLossC o) && fifoC sc o)
          let t1 ← IO.monoMsNow
          IO.println s!"{repr k} {repr sc} plan={repr plan}: {os.length} observations, {fails.length} violations ({t1 - t0} ms)"
          bad := bad + fails.length
        | none =>
          IO.println s!"{repr k} {repr sc} plan={repr plan}: not closed within {bound} states"
          bad := bad + 1
    IO.println s!"qsmoke exact: {bad} violations"
    return (if bad == 0 then 0 else 1)
  if args == ["wrong"] then
    -- each wrong function must break its claim on a small fixed program, under some schedule
    let tests : List (String × UserEnv × IO × (Obs → Bool)) := [
      ("wDrop (concNoLoss)", wDrop, rootIO (.boundedConc 2) lossIn [(2, 0)] .cancelAll, noLossC),
      ("wDropAsync (asyncNoLoss)", wDropAsync, rootIO .unbounded lossIn [(2, 0)] .cancelAll, noLossC),
      ("wDup (concNoDup)", wDup, rootIO (.boundedConc 2) dupIn [] (.join [0]), noDupC dupIn),
      ("wDupAsync (asyncNoDup)", wDupAsync, rootIO (.bounded 2) dupIn [] (.join [0]), noDupC dupIn),
      ("wLifoConc (concFifo)", wLifoConc, rootIO (.boundedConc 3) fifoIn [] (.join [0]), fifoC fifoIn),
      ("wLifo (asyncFifo)", wLifo, rootIO (.bounded 3) fifoIn [] (.join [0]), fifoC fifoIn),
      ("wLastIfWaiters (concFifo)", wLastIfWaiters, rootIO (.boundedConc 2) fifoMulti [(1, 1)] .cancelAll, fifoC fifoMulti),
      ("wLastIfWaitersAsync (asyncFifo)", wLastIfWaitersAsync, rootIO (.bounded 3) fifoMulti [(1, 1)] .cancelAll, fifoC fifoMulti),
      ("wNoPassOn (concTakerLiveness)", wNoPassOn, rootIO (.boundedConc 2) passOnIn [(1, 0)] (.join [0, 1]), liveC passOnIn [(1, 0)]),
      ("wNoAnywayU (asyncTakerLiveness)", wNoAnywayU, rootIO .unbounded passOnIn [(1, 0)] (.join [0, 1]), liveC passOnIn [(1, 0)]),
      ("wHangConc (concNoDeadlock)", wHangConc, rootIO (.boundedConc 1) hangIn [(1, 0)] .cancelAll, doneC),
      ("wHangAsync (asyncNoDeadlock)", wHangAsync, rootIO .unbounded hangIn [(1, 0)] .cancelAll, doneC),
      ("wNoWake (concTakerLiveness)", wNoWake, rootIO (.boundedConc 2) lossIn [] (.join [0]), liveC lossIn []),
      ("wNoNotify (asyncTakerLiveness)", wNoNotify, rootIO .unbounded lossIn [] (.join [0]), liveC lossIn []),
      ("wSyncTakeRaises (concTakerLiveness, review 12 H3)", wSyncTakeRaises, rootIO .synchronous lossIn [] (.join [0]), liveC lossIn []),
      ("wLifo (twinSeq: Async side)", wLifo, rootIO (.bounded 3) fifoIn [] (.join [0]), fun o =>
        some (events o.out) == (runWith henv (.boundedConc 3) fifoIn [] (.join [0])).map (fun o => events o.out))]
    let mut failed := 0
    for (name, e, io, claim) in tests do
      let (d, f) := randCheck e io 200 7 claim
      match f with
      | some _ => IO.println s!"{name}: broken as expected ({d} stopped runs)"
      | none => IO.println s!"{name}: NOT BROKEN ({d} stopped runs)"; failed := failed + 1
      -- the real mirror meets the same claim
      let (d0, f0) := randCheck henv io 200 7 claim
      match f0 with
      | some _ => IO.println s!"  real mirror BREAKS it"; failed := failed + 1
      | none => IO.println s!"  real mirror meets it ({d0} stopped runs)"
    return (if failed == 0 then 0 else 1)
  let cases := match args with | n :: _ => n.toNat! | _ => 200
  let runs := match args with | _ :: r :: _ => r.toNat! | _ => 20
  let seed0 := match args with | _ :: _ :: s :: _ => s.toNat! | _ => 1
  let mut g := mkStdGen seed0
  let mut bad : Nat := 0
  let mut stopped : Nat := 0
  let mut seed := seed0 * 100000
  for i in [0:cases] do
    -- safety statements (mode cancelAll)
    let (c, g1) := randCase g false
    g := g1
    let io := rootIO c.k c.scripts c.plan .cancelAll
    -- the decidable hypotheses: distinct elements (`Fifo`), capacities of the families
    let offs := allOffers c.scripts
    if offs.eraseDups.length != offs.length then
      bad := bad + 1; IO.println s!"HYPOTHESIS nodup case {i}"
    let claim : Obs → Bool := fun o =>
      noDupC c.scripts o && doneC o && (!keeps c.k || noLossC o) && fifoC c.scripts o
    let (d, f) := randCheck henv io runs seed claim
    seed := seed + 1; stopped := stopped + d
    match f with
    | some (cs, o) =>
      bad := bad + 1
      IO.println s!"VIOLATION safety case {i}: {repr c} nodup={noDupC c.scripts o} done={doneC o} loss={noLossC o} fifo={fifoC c.scripts o} summary={repr o.summary} events={evStr o.out} choices={repr (cs.take 120)}"
    | none => pure ()
    -- liveness (mode join consumers)
    let (c2, g2) := randCase g true
    g := g2
    let plan2 := c2.plan.filter fun p => match c2.scripts[p.2]? with | some s => s.all (· == .take) | none => false
    -- no count hypothesis any more (review batch 11a L1)
    if true then
      let js := (List.range c2.scripts.length).filter fun i => match c2.scripts[i]? with | some s => takes s | none => false
      let io2 := rootIO c2.k c2.scripts plan2 (.join js)
      let (d2, f2) := randCheck henv io2 runs seed (liveC c2.scripts plan2)
      seed := seed + 1; stopped := stopped + d2
      match f2 with
      | some (cs, o) =>
        bad := bad + 1
        IO.println s!"VIOLATION liveness case {i}: {repr c2} plan={repr plan2} summary={repr o.summary} events={evStr o.out} choices={repr (cs.take 120)}"
      | none => pure ()
    -- statement 7 (seqSpec): one fiber, every kind
    let (len7, g8) := randNat g 1 7
    let (s7, _, g9) := randScript g8 1 len7 false false
    g := g9
    for k in anyKinds do
      let (d7, f7) := randCheck henv (rootIO k [s7] [] (.join [0])) (max 2 (runs / 4)) seed (specC k s7)
      stopped := stopped + d7
      match f7 with
      | some (_, o) =>
        bad := bad + 1
        IO.println s!"VIOLATION seqSpec case {i}: {repr k} {repr s7}: got {repr o.summary} {evStr o.out}, spec {repr (specRun (ruleOf k) [] s7)}"
      | none => pure ()
    -- statement 6 (twinSeq): one fiber, both sides, every stopped run gives the same result
    let (len, g4) := randNat g 1 7
    let (ci, g5) := randNat g4 2 4
    let (s1, _, g6) := randScript g5 1 len false false
    g := g6
    let resultsOf (k : QKind) : List (Summary × List Val) := Id.run do
      let mut gg := mkStdGen (seed + 7)
      let mut acc : List (Summary × List Val) := []
      for r in [0:runs] do
        let (cs, g7) := randChoices gg 200 ([0, 5, 20, 50][r % 4]!)
        gg := g7
        match runObsP {} counterMaskModel henv 20000 cs (rootIO k [s1] [] (.join [0])) with
        | some o => if !(acc.contains (o.summary, o.out)) then acc := (o.summary, o.out) :: acc
        | none => pure ()
      return acc
    for (a, b) in twinPairs ci do
      let ra := resultsOf a
      let rb := resultsOf b
      stopped := stopped + ra.length + rb.length
      if ra.length != 1 || rb.length != 1 || ra != rb then
        bad := bad + 1
        IO.println s!"VIOLATION twin case {i}: {repr a} vs {repr b} script={repr s1} {ra.length} vs {rb.length} results; {repr (ra.map fun r => (r.1, events r.2))} / {repr (rb.map fun r => (r.1, events r.2))}"
  IO.println s!"qsmoke: {cases} cases x 2, {stopped} stopped runs, {bad} violations"
  return (if bad == 0 then 0 else 1)

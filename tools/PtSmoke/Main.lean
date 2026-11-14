import CatsEffectInLean.Props.Phase6.ParTraverse
import CatsEffectInLean.Model.EnumP

/-!
# `parTraverseN` smoke test (Phase 6, batch 6.3)

Random-schedule smoke test of the seven statements in `Props/Phase6/ParTraverse.lean`. Each
statement runs with three `HashSet` orders (`id`, `reverse`, rotate by one) and inputs of up to six
elements (from five the supervision set is a `HashSet`). For each
input it first checks the decidable hypotheses (`n ≥ 1`, `f` even, `a0` among the
first `n` inputs, the start program passes `progOK` with no handle; the user code is a fixed,
handle-free table, as in `Proofs/Phase6/ParTraverseWitness.lean`). Then `runs` random `PChoice`
lists (preemption rate 0, 5, 20, 50 %, fuel 20,000): every run that stops (`Sched.obs`) must meet
the claim.

Wrong-function tests (each must break its claim):
* statement 1: the result list reversed (`Map` with a harness `reverse`);
* statement 2: the last result dropped;
* statements 3, 4: `cancelAll` removed from the error (cancel) branch of the action finalizer
  (`K/GC:197-213`): the traversal then waits for the never-ending action;
* statements 6, 7: the same wrong function on the random behaviour tables.

Statements 5-7 use random behaviour tables (per input: 0-2 `cede`s, then `pure`, `raiseError`
(`E3` or `E5`), `canceled` or `never`) that meet the hypotheses.

Concurrency limit ("at most `n` actions at once", Scaladoc `K/GC:132-133`; no statement yet, it
needs the shared privacy module of decision 56): `f` counts the running actions in a `Ref` and the
program returns the highest count. The mirror must stay `≤ n`; the wrong function (a semaphore
with 1000 permits, `K/GC:175`) must exceed `n`.

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
  [[], [.nat 1], [.nat 1, .nat 2], [.nat 2, .nat 1, .nat 3], [.nat 1, .nat 2, .nat 3, .nat 4],
   [.nat 1, .nat 2, .nat 3, .nat 4, .nat 5], [.nat 6, .nat 1, .nat 5, .nat 2, .nat 4, .nat 3]]

/-- The `HashSet` orders: insertion order, reversed, rotated by one. -/
def ords : List (String × (List Val → List Val)) :=
  [("id", fun xs => xs), ("rev", List.reverse), ("rot", fun xs => xs.drop 1 ++ xs.take 1)]

/-- A behaviour table for inputs `1..len`. -/
def bhOf (tbl : List (Nat × Base)) : Val → Nat × Base
  | .nat k => tbl.getD (k - 1) (0, .never)
  | _ => (0, .never)

/-- A random table: `kinds` lists the allowed bases. -/
def randTable (g : StdGen) (len : Nat) (kinds : List Base) : List (Nat × Base) × StdGen := Id.run do
  let mut g := g
  let mut t : Array (Nat × Base) := #[]
  for _ in [0:len] do
    let (k, g1) := randNat g 0 2
    let (b, g2) := randNat g1 0 (kinds.length - 1)
    g := g2
    t := t.push (k, kinds.getD b .never)
  return (t.toList, g)

/-- The decidable hypothesis "some input `a_i` with `p` and fewer than `n` `never`s before it". -/
def reachable (bh : Val → Nat × Base) (as : List Val) (n : Nat) (p : Base → Bool) : Bool :=
  (List.range as.length).any fun i => p (bh (as.getD i .unit)).2 && nevers bh (as.take i) < n

/-! ## Concurrency limit: ids 30-46, the counter is `Ref` 0 (allocated first) -/

def cntR (id : Nat) (n : Nat) (as : List Val) (v : View) : UserResult :=
  let st : Nat × Nat := match (v.refs[0]? : Option Val) with
    | some (.pair (.nat c) (.nat m)) => (c, m)
    | _ => (0, 0)
  match id with
  | 30 => { out := .prog (.flatMap (.delay (.user 32)) (.user 34)) }
  | 32 => { effects := [.writeRef 0 (.pair (.nat (st.1 + 1)) (.nat (max st.2 (st.1 + 1))))], out := .ret .unit }
  | 34 => { out := .prog (.flatMap .cede (.user 46)) }
  | 46 => { out := .prog (.delay (.user 36)) }
  | 36 => { effects := [.writeRef 0 (.pair (.nat (st.1 - 1)) (.nat st.2))], out := .ret (.nat 0) }
  | 38 => { effects := [.allocRef (.pair (.nat 0) (.nat 0))], out := .ret (.ref 0) }
  | 40 => { out := .prog (.flatMap (parTraverseNIO n as 30) (.user 44)) }
  | 42 => { out := .ret (.nat st.2) }
  | 44 => { out := .prog (.delay (.user 42)) }
  | _ => { out := .throw { code := 0 } }

def cntU (n : Nat) (as : List Val) : UserEnv where
  call id _ refs := cntR id n as { refs }
  callV id _ v := cntR id n as v

def cntIO : IO := .flatMap (.delay (.user 38)) (.user 40)

/-- Wrong function: the semaphore of `parTraverseN` gets 1000 permits. -/
def wide (e : UserEnv) : UserEnv where
  call := e.call
  callV id arg v :=
    match PT.ofId? id with
    | some (.k2 _ as f p) => e.callV (PT.k2 1000 as f p).id arg v
    | _ => e.callV id arg v

def maxClaim (n : Nat) (o : Obs) : Bool :=
  match o.summary with
  | .done (.succeeded (.nat m)) => m ≤ n
  | _ => false

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
  let mut genCases : Nat × Nat × Nat := (0, 0, 0)
  for (oname, ord) in ords do
    IO.println s!"HashSet order {oname}"
    -- statement 1: all user functions, all n, all lists
    for f in [2, 4, 6, 8, 14] do
      for n in [1, 2, 3] do
        for as in lists do
          let io := parTraverseNIO n as (TL.tag f).id
          if !startOK io then IO.println s!"HYPOTHESIS order f={f} n={n}"; bad := bad + 1
          let (d, b) := randCheck (env ord (tagged u)) io runs seed (orderClaim as)
          seed := seed + 1; stoppedTot := stoppedTot + d; bad := bad + b
          if b > 0 then IO.println s!"VIOLATION order f={f} n={n} as={repr as}: {b}"
    IO.println "statement 1: done"
    -- statement 2: f = _ => IO.pure(0) (g = const 0)
    for n in [1, 2, 3] do
      for as in lists do
        let io := parTraverseNIO n as 2
        if !startOK io then IO.println s!"HYPOTHESIS pure n={n}"; bad := bad + 1
        let want : Summary := .done (.succeeded (listV (as.map fun _ => .nat 0)))
        let (d, b) := randCheck (env ord u) io runs seed (fun o => o.summary == want)
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
            let (d, b) := randCheck (env ord u) io runs seed (fun o => o.summary == want)
            seed := seed + 1; stoppedTot := stoppedTot + d; bad := bad + b
            if b > 0 then IO.println s!"VIOLATION abort f={f} n={n} as={repr as}: {b}"
    IO.println "statements 3, 4: done"
    -- statements 5-7: random behaviour tables
    let mut g := mkStdGen 4242
    for trial in [0:40] do
      let as := lists[trial % lists.length]!
      let n := 1 + trial % 3
      -- statement 5
      let (t5, g1) := randTable g as.length [.ok (.nat 7), .ok (.nat 8)]
      let bh5 := bhOf t5
      let want5 : Summary := .done (.succeeded (listV (as.map fun a => (bh5 a).2.okVal)))
      let (d5, b5) := randCheck (env ord (behaved bh5)) (parTraverseNIO n as BL.body.id) (runs / 4 + 1) seed
        (fun o => o.summary == want5)
      seed := seed + 1; stoppedTot := stoppedTot + d5; bad := bad + b5
      genCases := (genCases.1 + 1, genCases.2)
      if b5 > 0 then IO.println s!"VIOLATION succeedsGen n={n} t={repr t5}: {b5}"
      -- statement 6
      let (t6, g2) := randTable g1 as.length [.ok (.nat 7), .err { code := 3 }, .err { code := 5 }, .never]
      let bh6 := bhOf t6
      if reachable bh6 as n (fun b => match b with | .err _ => true | _ => false) then
        let errs := as.filterMap fun a => match (bh6 a).2 with | .err e => some e | _ => none
        let (d6, b6) := randCheck (env ord (behaved bh6)) (parTraverseNIO n as BL.body.id) (runs / 4 + 1) seed
          (fun o => match o.summary with | .done (.errored e) => errs.contains e | _ => false)
        seed := seed + 1; stoppedTot := stoppedTot + d6; bad := bad + b6
        genCases := (genCases.1, genCases.2.1 + 1, genCases.2.2)
        if b6 > 0 then IO.println s!"VIOLATION errorAbortsGen n={n} t={repr t6}: {b6}"
      -- statement 7
      let (t7, g3) := randTable g2 as.length [.ok (.nat 7), .canc, .never]
      g := g3
      let bh7 := bhOf t7
      if reachable bh7 as n (· == .canc) then
        let (d7, b7) := randCheck (env ord (behaved bh7)) (parTraverseNIO n as BL.body.id) (runs / 4 + 1) seed
          (fun o => o.summary == .done .canceled)
        seed := seed + 1; stoppedTot := stoppedTot + d7; bad := bad + b7
        genCases := (genCases.1, genCases.2.1, genCases.2.2 + 1)
        if b7 > 0 then IO.println s!"VIOLATION cancelAbortsGen n={n} t={repr t7}: {b7}"
    IO.println "statements 5-7: done"
    -- concurrency limit
    for n in [1, 2, 3] do
      for as in lists do
        let (d, b) := randCheck (env ord (cntU n as)) cntIO (runs / 4 + 1) seed (maxClaim n)
        seed := seed + 1; stoppedTot := stoppedTot + d; bad := bad + b
        if b > 0 then IO.println s!"VIOLATION limit n={n} as={repr as}: {b}"
    IO.println "concurrency limit: done"
  IO.println s!"behaviour tables checked (statements 5, 6, 7): {genCases.1}, {genCases.2.1}, {genCases.2.2}"
  IO.println s!"stopped runs {stoppedTot}, violations {bad}"
  let ord : List Val → List Val := List.reverse
  -- wrong functions
  let rev : UserEnv := { call := (env ord (tagged u)).call
                         callV := fun id a v => if id == 1000001 then { out := .ret (listV ((unlistV a).getD []).reverse) } else (env ord (tagged u)).callV id a v }
  let as2 := [Val.nat 1, .nat 2]
  let (_, w1) := randCheck rev (.map (parTraverseNIO 2 as2 (TL.tag 2).id) (.user 1000001)) runs 7 (orderClaim as2)
  let drop : UserEnv := { call := (env ord u).call
                          callV := fun id a v => if id == 1000001 then { out := .ret (listV ((unlistV a).getD []).dropLast) } else (env ord u).callV id a v }
  let (_, w2) := randCheck drop (.map (parTraverseNIO 2 as2 2) (.user 1000001)) runs 8
    (fun o => o.summary == .done (.succeeded (listV [.nat 0, .nat 0])))
  let as3 := [Val.nat 2, .nat 1]
  let (_, w3) := randCheck (noCancelAll (env ord u)) (parTraverseNIO 2 as3 20) runs 9
    (fun o => o.summary == .done (.errored { code := 5 }))
  let (_, w4) := randCheck (noCancelAll (env ord u)) (parTraverseNIO 2 as3 22) runs 10
    (fun o => o.summary == .done .canceled)
  -- statements 6, 7 on five inputs (HashSet): `f(5)` raises (cancels) after a `cede`, the rest never
  let as5 := [Val.nat 1, .nat 2, .nat 3, .nat 4, .nat 5]
  let bhE : Val → Nat × Base := fun a => if a == .nat 5 then (1, .err { code := 5 }) else (0, .never)
  let bhC : Val → Nat × Base := fun a => if a == .nat 5 then (1, .canc) else (0, .never)
  let (_, w5) := randCheck (noCancelAll (env ord (behaved bhE))) (parTraverseNIO 5 as5 BL.body.id) runs 11
    (fun o => o.summary == .done (.errored { code := 5 }))
  let (_, w6) := randCheck (noCancelAll (env ord (behaved bhC))) (parTraverseNIO 5 as5 BL.body.id) runs 12
    (fun o => o.summary == .done .canceled)
  -- concurrency limit: 1000 permits
  let as4 := [Val.nat 1, .nat 2, .nat 3, .nat 4]
  let (_, w7) := randCheck (wide (env ord (cntU 1 as4))) cntIO runs 13 (maxClaim 1)
  let (_, w8) := randCheck (wide (env ord (cntU 2 as4))) cntIO runs 14 (maxClaim 2)
  IO.println s!"wrong functions (runs that break the claim, expected > 0): reverse {w1}, drop {w2}, no cancelAll on error {w3}, on cancel {w4}, gen error {w5}, gen cancel {w6}, 1000 permits n=1 {w7}, n=2 {w8}"
  return if bad == 0 && w1 > 0 && w2 > 0 && w3 > 0 && w4 > 0 && w5 > 0 && w6 > 0 && w7 > 0 && w8 > 0 then 0 else 1

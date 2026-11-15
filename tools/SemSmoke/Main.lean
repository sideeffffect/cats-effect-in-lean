import CatsEffectInLean.Props.Phase7.Semaphore
import CatsEffectInLean.Proofs.Phase7.SemaphoreCountFixedDefs

/-!
# `Semaphore`/`Mutex` smoke test (Phase 7, track S)

Random-schedule smoke test of the statements in `Props/Phase7/Semaphore.lean`. For each statement
it makes random inputs that meet the decidable hypotheses (`AllEnded`, `need ≤ k`, no `release` act
where the statement excludes it; the start program passes `progOK semLib` with no handle; the user
code below is a fixed table that holds no handle), then runs `runs` random `PChoice` lists
(preemption rate 0, 5, 20, 50 %, fuel 20,000). Every run that stops (`Sched.obs`) must meet the
claim. Statement 6 (`count` at rest) is expected to fail (CE-0060); the tool prints the first
failing input and schedule. The CE-0060 fixed twin (`Proofs/Phase7/SemaphoreCountFixedDefs.lean`)
must meet statements 2 and 6 on the same inputs.

Wrong-function tests (each must break its claim in some run):
* "leak a permit": `cleanup` of `acquireN` does not give back the permits of a won race
  (`won = false` branch is `F.unit`): statements 1, 2;
* "release twice": `releaseN(n)` adds `2n`: statement 1;
* "skip a waiter": `releaseN` drops the first woken request from the queue without completing its
  gate: statement 2 (a waiter never wakes);
* "LIFO": `releaseN` serves the newest request first: statement 7;
* "no wait": the mutex `loop` treats every cell as free: statement 4 (two holders);
* "lost wakeup": the mutex `release` never completes its cell: statement 5;
* "wide": `Semaphore(k + 1)` in place of `Semaphore(k)`: statement 3.

Forgery: a user function whose closure value is the lock state `Ref` (it captured the cell) writes
1000 permits. `WellFormed` rejects the root; when it runs, it breaks statement 1.

`lake exe semsmoke [runs]` (default 40). Exit code 1 if a check fails.
-/

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Semaphore
open CatsEffectInLean.Props.Phase7.Semaphore

namespace SemSmoke

/-- User code (no handles): 2 `_ => IO.pure(0)`; 4 `_ => emit 4 *> IO.cede *> IO.pure(0)` (via
16); 6 `_ => IO.sleep(1)`; 8 `_ => IO.raiseError(E3)`; 10 `_ => IO.canceled`; 12 `_ => IO.never`
(an `IOCont` whose callback is never called, via 18); 14 `_ => IO.cede.start *> IO.pure(0)`; 16 `_ => IO.pure(0)`. -/
def uR (id : Nat) (a : Val) : UserResult :=
  match id with
  | 2 => { out := .prog (.pure (.nat 0)) }
  | 4 => { effects := [.emit (.nat 4)], out := .prog (.flatMap .cede (.user 16)) }
  | 6 => { out := .prog (.sleep 1) }
  | 8 => { out := .prog (.error { code := 3 }) }
  | 10 => { out := .prog .canceled }
  | 12 => { out := .prog (.ioCont (.user 18)) }
  | 14 => { out := .prog (.flatMap (.start .cede) (.user 16)) }
  | 16 => { out := .prog (.pure (.nat 0)) }
  | 18 => match a with
    | .cont st => { out := .prog (.contGet st) }
    | _ => { out := .throw { code := 0 } }
  | _ => { out := .throw { code := 0 } }

def u : UserEnv where
  call id a _ := uR id a

def userIds : List Nat := [2, 4, 6, 8, 10, 12, 14]

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

/-- `runs` random schedules: (stopped runs, runs that break `claim`, first breaking schedule). -/
def randCheck (e : UserEnv) (io : IO) (runs seed : Nat) (claim : Obs → Bool) :
    Nat × Nat × Option (List PChoice) := Id.run do
  let mut g := mkStdGen seed
  let mut stopped := 0
  let mut bad := 0
  let mut first : Option (List PChoice) := none
  for k in [0:runs] do
    let (cs, g1) := randChoices g 400 ([0, 5, 20, 50][k % 4]!)
    g := g1
    match runObsP {} counterMaskModel e 20000 cs io with
    | some o =>
      stopped := stopped + 1
      if !claim o then
        bad := bad + 1
        if first.isNone then first := some cs
    | none => pure ()
  return (stopped, bad, first)

def startOK (p : IO) : Bool := WF.progOK semLib (fun _ => false) p

/-- Random acts that end every fiber `0..m-1` (cancel or join, in random order), with cedes and,
if `rel`, releases between them. -/
def randActs (g : StdGen) (m : Nat) (rel : Bool) : List Act × StdGen := Id.run do
  let mut g := g
  let mut order : Array Nat := (List.range m).toArray
  -- shuffle
  for i in [0:m] do
    let (j, g1) := randNat g 0 (m - 1)
    g := g1
    let a := order[i]!
    order := (order.set! i order[j]!).set! j a
  let mut acts : Array Act := #[]
  for i in order.toList do
    let (c, g1) := randNat g 0 9
    g := g1
    if c < 3 then acts := acts.push .cede
    if rel && c == 9 then acts := acts.push (.release (1 + i % 2))
    let (x, g2) := randNat g 0 1
    g := g2
    acts := acts.push (if x == 0 then .cancel i else .join i)
  return (acts.toList, g)

/-- A random `Use` (`sem`: all kinds; else `permit`/`counted`), with `n ≤ k` if `fit`. -/
def randUse (g : StdGen) (sem : Bool) (k : Nat) : Use × StdGen :=
  let (x, g1) := randNat g 0 9
  let (gi, g2) := randNat g1 0 (userIds.length - 1)
  let gid := userIds[gi]!
  let (n, g3) := randNat g2 0 (max 1 k)
  if !sem || x < 4 then (.permit gid, g3)
  else if x < 6 then (.counted gid, g3)
  else if x < 8 then (.acqRel n, g3)
  else (.tryRel n, g3)

/-- A random behaviour use with `need ≤ k`. -/
def randBUse (g : StdGen) (sem : Bool) (k : Nat) : BUse × StdGen :=
  let (x, g1) := randNat g 0 9
  let (c, g2) := randNat g1 0 2
  let (b, g3) := randNat g2 0 3
  let base : Base := match b with
    | 0 => .ok (.nat 1) | 1 => .err { code := 3 } | 2 => .canc | _ => .ok .unit
  let (n, g4) := randNat g3 0 k
  if (!sem || x < 5) && (!sem || 1 ≤ k) then (.permit c base, g4)
  else if x < 8 then (.acqRel n, g4)
  else (.tryRel n, g4)

/-! ## Wrong functions -/

/-- "leak a permit": `cleanup` with `won = false` is `F.unit` (`S:188-191`). -/
def leak (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match SL.ofId? id, a with
    | some (.wonK _ _ _), .bool false => { out := .prog (.pure .unit) }
    | _, _ => e.callV id a v

/-- "release twice": `releaseN(n)` adds `2n`. -/
def twice (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match SL.ofId? id with
    | some (.relBody s n) => e.callV (SL.relBody s (2 * n)).id a v
    | _ => e.callV id a v

/-- "skip a waiter": the `modify` of `releaseN` drops the first woken request (its gate is never
completed). -/
def skip (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match SL.ofId? id with
    | some (.modRel s n) =>
      let r := e.callV id a v
      match r.out with
      | .ret d =>
        match ofCloVal d with
        | some (60, 93, [sv, wk, hd]) =>
          { r with out := .ret (cloVal 60 93 [sv, listV (((unlistV wk).getD []).drop 1), hd]) }
        | _ => r
      | _ => r
    | _ => e.callV id a v

/-- "LIFO": `releaseN` serves the newest request first (the queue is reversed before `fulfil`). -/
def lifo (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match SL.ofId? id with
    | some (.modRel s _) =>
      match semRef? s with
      | some q =>
        match v.refs[q]? with
        | some (.pair p w) =>
          let w' := listV (((unlistV w).getD []).reverse)
          e.callV id a { v with refs := v.refs.set q (.pair p w') }
        | _ => e.callV id a v
      | none => e.callV id a v
    | _ => e.callV id a v

/-- "no wait": the mutex `loop` takes every cell as free. -/
def noWait (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match Mutex.ML.ofId? id with
    | some (.loopK _ c _ _) =>
      match a with
      | .deferred _ => { out := .prog (.pure (.deferred c)) }
      | _ => e.callV id a v
    | _ => e.callV id a v

/-- "lost wakeup": the mutex never completes its cell (`awakeCell` with `false` is `F.unit`). -/
def lostWake (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match Mutex.ML.ofId? id, a with
    | some (.awB _ _), .bool false => { out := .prog (.pure .unit) }
    | _, _ => e.callV id a v

/-- "wide": `Semaphore(k + 1)` (the harness `afterCell` makes one more permit). -/
def wide (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match HS.ofId? id with
    | some (.afterCell lk us as) =>
      match Lock.ofVal lk with
      | some (.sem k) => e.callV (HS.afterCell (Lock.sem (k + 1)).toVal us as).id a v
      | _ => e.callV id a v
    | _ => e.callV id a v

/-- A forging user function: its closure value is `Ref q` (the lock state), it writes 1000 permits. -/
def forging (q : Nat) : Nat := 2 * valToNat (.ref q)

def forgeU (q : Nat) : UserEnv where
  call id a refs :=
    if id == forging q then
      { effects := [.writeRef q (stateV 1000 [])], out := .prog (.pure .unit) }
    else u.call id a refs

/-! ## Claims -/

def claim1 (k r : Nat) (o : Obs) : Bool :=
  match o.summary with
  | .done (.succeeded v) => availOf v == some (k + r)
  | _ => true

def claim2 (k r : Nat) (o : Obs) : Bool :=
  match o.summary with
  | .done (.succeeded v) => availOf v == some (k + r)
  | _ => false

def claimHi (n : Nat) (o : Obs) : Bool :=
  match highest o with
  | some h => h ≤ n
  | none => false

def claim6 (o : Obs) : Bool :=
  match o.summary with
  | .done (.succeeded v) =>
    match availOf v, countOf v with
    | some a, some c => c == (a : Int)
    | _, _ => false
  | _ => true

def claim7 (ns : List Nat) (r : Nat) (o : Obs) : Bool :=
  o.summary == .done (.succeeded (.int ((r : Int) - (ns.foldl (· + ·) 0 : Nat))))

end SemSmoke

open SemSmoke in
def main (args : List String) : IO UInt32 := do
  let runs := match args with | [n] => n.toNat! | _ => 40
  let mut bad : Nat := 0
  let mut stoppedTot : Nat := 0
  let mut inputs : Array Nat := #[0, 0, 0, 0, 0, 0, 0, 0]
  let mut g := mkStdGen 2026
  let mut seed : Nat := 1
  let mut cex6 : Option (Nat × List BUse × List Act × List PChoice) := none
  let mut fixedBad : Nat := 0
  let mut v6inputs : Nat := 0
  for trial in [0:60] do
    let (k, g1) := randNat g 0 3
    let (m, g2) := randNat g1 1 3
    g := g2
    -- statements 1, 3 (semaphore, user code)
    let mut us : Array Use := #[]
    for _ in [0:m] do
      let (x, g') := randUse g true k
      g := g'; us := us.push x
    let (as1, g3) := randActs g m true
    let (as3, g4) := randActs g3 m false
    g := g4
    let r1 := lockRoot (.sem k) us.toList as1
    if !startOK r1 then IO.println s!"HYPOTHESIS 1 trial {trial}"; bad := bad + 1
    let (d1, b1, _) := randCheck (env u) r1 runs seed (claim1 k (released as1))
    seed := seed + 1; stoppedTot := stoppedTot + d1; bad := bad + b1
    inputs := inputs.modify 0 (· + 1)
    if b1 > 0 then IO.println s!"VIOLATION 1 k={k} us={repr us} as={repr as1}: {b1}"
    let r3 := lockRoot (.sem k) us.toList as3
    let (d3, b3, _) := randCheck (env u) r3 runs seed (claimHi k)
    seed := seed + 1; stoppedTot := stoppedTot + d3; bad := bad + b3
    inputs := inputs.modify 2 (· + 1)
    if b3 > 0 then IO.println s!"VIOLATION 3 k={k} us={repr us}: {b3}"
    -- statements 2, 6 (semaphore, behaviour tables)
    let mut bus : Array BUse := #[]
    for _ in [0:m] do
      let (x, g') := randBUse g true k
      g := g'; bus := bus.push x
    let (as2, g5) := randActs g m true
    g := g5
    let r2 := lockRoot (.sem k) (bus.toList.map BUse.toUse) as2
    let (d2, b2, _) := randCheck (env behaved) r2 runs seed (claim2 k (released as2))
    seed := seed + 1; stoppedTot := stoppedTot + d2; bad := bad + b2
    inputs := inputs.modify 1 (· + 1)
    if b2 > 0 then IO.println s!"VIOLATION 2 k={k} bus={repr bus} as={repr as2}: {b2}"
    let mut bus6 : Array BUse := #[]
    for _ in [0:m] do
      let (x, g') := randBUse g true (k + 1)
      g := g'; bus6 := bus6.push x
    let r6 := lockRoot (.sem k) (bus6.toList.map BUse.toUse) as2
    let (_, b6, f6) := randCheck (env behaved) r6 runs seed claim6
    seed := seed + 1
    inputs := inputs.modify 5 (· + 1)
    if b6 > 0 && cex6.isNone then cex6 := f6.map fun cs => (k, bus6.toList, as2, cs)
    -- the CE-0060 fixed twin: statements 2 and 6 hold
    let (_, bf6, _) := randCheck (CatsEffectInLean.Proofs.Phase7.fixedEnv (env behaved)) r6 runs seed claim6
    let (_, bf2, _) := randCheck (CatsEffectInLean.Proofs.Phase7.fixedEnv (env behaved)) r2 runs seed (claim2 k (released as2))
    fixedBad := fixedBad + bf6 + bf2
    if b6 > 0 then v6inputs := v6inputs + 1
    -- statements 4, 5, 8 (mutex)
    let mut mus : Array Use := #[]
    for _ in [0:m] do
      let (x, g') := randUse g false 1
      g := g'; mus := mus.push (if trial % 2 == 0 then x else match x with | .permit gg => .counted gg | y => y)
    let (am, g6) := randActs g m false
    g := g6
    let rm := lockRoot .mutex mus.toList am
    if !startOK rm then IO.println s!"HYPOTHESIS 4 trial {trial}"; bad := bad + 1
    let (d4, b4, _) := randCheck (env u) rm runs seed (claimHi 1)
    seed := seed + 1; stoppedTot := stoppedTot + d4; bad := bad + b4
    inputs := inputs.modify 3 (· + 1)
    if b4 > 0 then IO.println s!"VIOLATION 4 us={repr mus}: {b4}"
    let mut mbus : Array BUse := #[]
    for _ in [0:m] do
      let (x, g') := randBUse g false 1
      g := g'; mbus := mbus.push x
    let rm5 := lockRoot .mutex (mbus.toList.map BUse.toUse) am
    let (d5, b5, _) := randCheck (env behaved) rm5 runs seed (fun o => o.summary == .done (.succeeded .unit))
    seed := seed + 1; stoppedTot := stoppedTot + d5; bad := bad + b5
    inputs := inputs.modify 4 (· + 1)
    if b5 > 0 then IO.println s!"VIOLATION 5 bus={repr mbus}: {b5}"
    -- statement 8 (twin), one direction by sampling: each mutex core outcome is a sampled
    -- Semaphore(1) core outcome (more schedules on the semaphore side)
    let rs := lockRoot .semMutex mus.toList am
    let mut semCores : Array (Summary × List Val) := #[]
    let mut gg := mkStdGen (seed + 7)
    for kk in [0:4 * runs] do
      let (cs, g') := randChoices gg 400 ([0, 5, 20, 50][kk % 4]!)
      gg := g'
      match runObsP {} counterMaskModel (env u) 20000 cs rs with
      | some o => if !semCores.contains (core o) then semCores := semCores.push (core o)
      | none => pure ()
    let mut miss := 0
    for kk in [0:runs] do
      let (cs, g') := randChoices gg 400 ([0, 5, 20, 50][kk % 4]!)
      gg := g'
      match runObsP {} counterMaskModel (env u) 20000 cs rm with
      | some o => if !semCores.contains (core o) then miss := miss + 1
      | none => pure ()
    inputs := inputs.modify 7 (· + 1)
    if miss > 0 then IO.println s!"twin: {miss} mutex outcomes not sampled on Semaphore(1), us={repr mus} as={repr am}"
  -- statement 7 (FIFO)
  for ns in [[1], [2, 1], [1, 2], [3, 1, 1], [1, 1, 1], [2, 2, 1], [0, 1], [1, 3, 1]] do
    for r in [0, 1, 2, 3, 4, 6] do
      let (d7, b7, _) := randCheck fifoEnv (fifoRoot ns r) runs seed (claim7 ns r)
      seed := seed + 1; stoppedTot := stoppedTot + d7; bad := bad + b7
      inputs := inputs.modify 6 (· + 1)
      if b7 > 0 then IO.println s!"VIOLATION 7 ns={ns} r={r}: {b7}"
  IO.println s!"inputs per statement (1..8): {inputs}"
  IO.println s!"stopped runs {stoppedTot}, violations of statements 1-5, 7 {bad}"
  IO.println s!"statement 6: inputs with a violation {v6inputs}; fixed twin: runs that break statements 2 or 6: {fixedBad}"
  if fixedBad > 0 then bad := bad + 1
  match cex6 with
  | some (k, bus, as, cs) =>
    IO.println s!"statement 6 (count at rest) FAILS (expected, CE-0060): k={k} bus={repr bus} as={repr as} cs={repr (cs.take 60)}"
  | none => IO.println "statement 6: no counterexample found"
  -- wrong functions
  let usA : List Use := [.acqRel 1, .acqRel 1, .permit 4]
  let asA : List Act := [.cede, .cancel 1, .cede, .cancel 0, .join 2]
  let (_, w1, _) := randCheck (leak (env u)) (lockRoot (.sem 1) usA asA) (4 * runs) 101 (claim1 1 0)
  let (_, w2, _) := randCheck (twice (env u)) (lockRoot (.sem 1) usA (asA ++ [.release 1])) (4 * runs) 102 (claim1 1 1)
  let busB : List BUse := [.acqRel 1, .acqRel 1, .permit 1 (.ok .unit)]
  let (_, w3, _) := randCheck (skip (env behaved)) (lockRoot (.sem 1) (busB.map BUse.toUse) [.join 0, .join 1, .join 2]) (4 * runs) 103 (claim2 1 0)
  let (_, w4, _) := randCheck (lifo fifoEnv) (fifoRoot [1, 2] 1) (4 * runs) 104 (claim7 [1, 2] 1)
  let (_, w5, _) := randCheck (noWait (env u)) (lockRoot .mutex [.counted 4, .counted 4] [.join 0, .join 1]) (4 * runs) 105 (claimHi 1)
  let busM : List BUse := [.permit 1 (.ok .unit), .permit 0 (.ok .unit)]
  let (_, w6, _) := randCheck (lostWake (env behaved)) (lockRoot .mutex (busM.map BUse.toUse) [.join 0, .join 1]) (4 * runs) 106
    (fun o => o.summary == .done (.succeeded .unit))
  let (_, w7, _) := randCheck (wide (env u)) (lockRoot (.sem 1) [.counted 4, .counted 4] [.join 0, .join 1]) (4 * runs) 107 (claimHi 1)
  -- forgery
  let mut forgeAccepted := false
  let mut wF := 0
  for q in [1, 2] do
    let io := lockRoot (.sem 1) [.permit (forging q)] [.join 0]
    forgeAccepted := forgeAccepted || startOK io
    let (_, b, _) := randCheck (env (forgeU q)) io runs (110 + q) (claim1 1 0)
    wF := wF + b
  IO.println s!"forgery: accepted by WellFormed {forgeAccepted}; runs that break statement 1: {wF}"
  if forgeAccepted || wF == 0 then bad := bad + 1
  IO.println s!"wrong functions (runs that break the claim, expected > 0): leak {w1}, twice {w2}, skip {w3}, lifo {w4}, noWait {w5}, lostWake {w6}, wide {w7}"
  return if bad == 0 && w1 > 0 && w2 > 0 && w3 > 0 && w4 > 0 && w5 > 0 && w6 > 0 && w7 > 0 then 0 else 1

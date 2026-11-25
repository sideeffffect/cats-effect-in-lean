import CatsEffectInLean.Props.Phase7.Dispatcher

/-!
# `Dispatcher` smoke test (Phase 7, track P7D)

`lake exe dispsmoke [runs]`: random inputs and `PChoice` schedules for the statements of
`Props/Phase7/Dispatcher.lean`, for v3.7.1 (`v = 0`) and the wrong variants. Safety statements are
checked in every state of a run. The hypotheses are evaluated: `WF.progOK` of every user program
(the closed programs below), modes ≤ 1, submitters 0, 1 or `late`. Printed: per statement and
variant, the runs, the runs that reached the interesting case, and the violating runs.

User programs: `IO.pure(())`, `IO.cede`, `IO.sleep(1)`, `IO.raiseError`, `IO.canceled`,
`IO.never` (no handle). Worker choices: random. Map order: insertion order or reversed.
-/

open CatsEffectInLean.Model CatsEffectInLean.Props.Phase7.Dispatcher

def uR (_ : Nat) (_ : Val) (_ : View) : UserResult := { out := .throw { code := 1 } }
def u : UserEnv := { call := fun id a refs => uR id a { refs }, callV := uR }

def progs : Array IO := #[.pure .unit, .cede, .sleep 1, .error { code := 3 }, .canceled, Timeout.neverIO]

def nx (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648

def sched (seed len : Nat) : List PChoice := Id.run do
  let mut x := nx (seed * 31 + 7)
  let mut out : Array PChoice := #[]
  for _ in [0:len] do
    x := nx x
    out := out.push (if x % 6 == 0 then .preempt else .pick ((x / 7) % 4))
  return out.toList

structure Case where
  par : Bool
  aw : Bool
  n : Nat
  wc : Val
  x : Inp
  rev : Bool

/-- A random case; `pureOnly`: user programs `IO.pure(())`; `body`: submitters 0 only. -/
def mk (seed : Nat) (pureOnly body : Bool) : Case := Id.run do
  let mut x := nx (seed * 7919 + 13)
  let par := x % 2 == 0
  x := nx x
  let aw := x % 2 == 0
  x := nx x
  let n := if par then 1 + x % 2 else 1
  x := nx x
  let k := 1 + x % 3
  let mut ws : List IO := []
  let mut ps : List Nat := []
  let mut ms : List Nat := []
  let mut cn : List Nat := []
  let mut wc : List Val := []
  for j in [0:k] do
    x := nx x
    ws := ws ++ [if pureOnly then .pure .unit else progs.getD (x % progs.size) (.pure .unit)]
    x := nx x
    ps := ps ++ [if body then 0 else [0, 0, 1, late].getD (x % 4) 0]
    x := nx x
    let m := x % 2
    ms := ms ++ [m]
    x := nx x
    if m == 0 && x % 3 == 0 then cn := cn ++ [j]
    x := nx x
    wc := wc ++ [.nat (x % 3)]
  x := nx x
  let b := if pureOnly then .pure .unit else progs.getD (x % 3) (.pure .unit)
  x := nx x
  let c := if pureOnly then .pure .unit else progs.getD (x % 3) (.pure .unit)
  x := nx x
  return { par, aw, n, wc := CatsEffectInLean.Model.Codec.listV wc, rev := x % 2 == 0,
           x := { ws, ps, ms, cn, c, b, sw := false } }

def hoOf (rev : Bool) : List Val → List Val := if rev then List.reverse else id

def fuel : Nat := 1500

def states (cs : Case) (v : Nat) (sch : List PChoice) : List (Sched CounterMask) := Id.run do
  let e := env (hoOf cs.rev) cs.x u
  let mut s : Sched CounterMask := Sched.init counterMaskModel (prog cs.par cs.aw cs.n cs.wc cs.x.ws.length v)
  let mut out : Array (Sched CounterMask) := #[s]
  let mut c := sch
  for _ in [0:fuel] do
    match s.halt with
    | some _ => break
    | none =>
      s := s.tickP {} counterMaskModel e (c.headD (.pick 0)); c := c.tail
      out := out.push s
  return out.toList

def hypOK (cs : Case) : Bool :=
  (cs.x.b :: cs.x.c :: cs.x.ws).all (fun q => WF.progOK dispLib (fun h => ([] : List Handle).contains h) q) &&
  cs.x.ms.all (· ≤ 1) && cs.x.ps.all (fun p => p == 0 || p == 1 || p == late)

def isDone (s : Sched CounterMask) : Bool := match s.halt with | some (.done _) => true | _ => false
def k (cs : Case) := cs.x.ws.length

def bad1 (cs : Case) (s : Sched CounterMask) : Bool := (List.range (k cs)).any fun j => runs s j > 1 || fins s j > 1
def bad4 (cs : Case) (s : Sched CounterMask) : Bool :=
  (List.range (k cs)).any fun j => (rejected s j == 1 && runs s j != 0) ||
    (s.halt == some (.done (.succeeded .unit)) && cs.x.ps.getD j 0 == late && rejected s j != 1)
def incr : List Nat → Bool
  | a :: b :: r => a < b && incr (b :: r)
  | _ => true
def bad5 (cs : Case) (s : Sched CounterMask) : Bool :=
  !incr (order s) || ((List.range (k cs)).filter fun j => status s j == 1).length > 1
def bad7 (s : Sched CounterMask) : Bool := s.halt == some .blocked
def bad2 (cs : Case) (s : Sched CounterMask) : Bool :=
  match s.halt with
  | some (.done oc) => oc != .succeeded .unit || (List.range (k cs)).any fun j => status s j != 2
  | _ => false
def bad3 (cs : Case) (s : Sched CounterMask) : Bool :=
  isDone s && (List.range (k cs)).any fun j => accepted s j && status s j != 2
def bad6 (cs : Case) (s : Sched CounterMask) : Bool := isDone s && (List.range (k cs)).any fun j => status s j == 2
def bad8 (cs : Case) (s : Sched CounterMask) : Bool := isDone s && (List.range (k cs)).any fun j => status s j != 3

/-- Run `runs` random cases of statement `st` with variant `v`: (runs, hypothesis failures,
done runs, violating runs). -/
def stat (st v runs : Nat) : Array Nat := Id.run do
  let mut c : Array Nat := #[0, 0, 0, 0]
  for i in [0:runs] do
    let base := mk (i + 1000 * st) (st == 2 || st == 3 || st == 7) (st == 2 || st == 5 || st == 7)
    let x := base.x
    let sl : List CatsEffectInLean.Model.IO := x.ws.map (fun _ => CatsEffectInLean.Model.IO.sleep 1)
    let p0 := x.ps.map (fun _ => 0)
    let cRand : CatsEffectInLean.Model.IO := progs.getD (i % progs.size) (.pure .unit)
    let cs : Case := match st with
      | 2 => { base with aw := true, x := { x with cn := [] } }
      -- review 17 (B2): the concurrent submitter's prefix `c` is any user program (it can cancel
      -- itself or never end before it submits)
      | 3 => { base with aw := true, x := { x with cn := [], c := cRand, ps := x.ps.mapIdx fun j _ => j % 2 } }
      | 5 => { base with par := false, n := 1, x := { x with cn := [] } }
      | 6 => { base with aw := false, x := { x with ws := sl, cn := [], ps := p0, b := .cede } }
      | 8 => { base with par := true, x := { x with ws := sl, cn := [], ps := p0, ms := p0, b := .pure .unit, sw := true } }
      | _ => base
    c := c.modify 0 (· + 1)
    if !hypOK cs then c := c.modify 1 (· + 1)
    let ss := states cs v (sched i 400)
    let last := ss.getLastD (Sched.init counterMaskModel (.pure .unit))
    if isDone last then c := c.modify 2 (· + 1)
    let bad : Bool := match st with
      | 1 => ss.any (bad1 cs)
      | 2 => bad2 cs last
      | 3 => bad3 cs last
      | 4 => ss.any (bad4 cs)
      | 5 => ss.any (bad5 cs)
      | 6 => bad6 cs last
      | 7 => bad7 last
      | _ => bad8 cs last
    if bad then c := c.modify 3 (· + 1)
  return c

def main (args : List String) : IO Unit := do
  let runs := (args.head?.bind String.toNat?).getD 40
  let plan : List (Nat × String × List Nat) :=
    [(1, "runsOnce", [0, 4, 12]), (2, "awaitDrains", [0, 31, 1, 3, 9, 11, 13, 16]),
     (3, "noLostSubmission", [0, 32]), (4, "closedRejects", [0, 19, 15]), (5, "seqFifo", [0, 18]),
     (6, "cancels", [0, 20]), (7, "noDeadlock", [0, 2, 6, 10, 14, 15]), (8, "cancelStops", [0, 5, 7])]
  for (st, name, vs) in plan do
    for v in vs do
      let c := stat st v runs
      IO.println s!"{name} v{v}: runs {c[0]!} hypFail {c[1]!} done {c[2]!} violations {c[3]!}"

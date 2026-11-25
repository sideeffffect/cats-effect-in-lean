import CatsEffectInLean.Props.Phase7.Supervisor

/-!
# `Supervisor` smoke test (Phase 7, track V)

Random inputs and random `PChoice` schedules (a fixed LCG; `preempt` with probability 1/4 at each
micro-step) for the six statements of `Props/Phase7/Supervisor.lean`, on Cats Effect v3.7.1
(variant 0) and on the wrong variants of the mirror (`Std/Supervisor.lean`, `v ≠ 0`, not Cats
Effect code). Statements 2 and 3 are checked in every state of a run (each prefix), the others in
the final state. Two map orders: insertion order and its reverse.

The hypotheses are evaluated (decision 53): every user program passes `WF.progOK supLib` with
`H0 = []`; the user environment `u` returns closed programs that hold no handle.

`lake exe supsmoke [runs]` (default 600). Exit code 1 if Cats Effect v3.7.1 violates a statement
or a hypothesis fails, or a wrong variant breaks none of its statements.
-/

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase7.Supervisor

namespace SupSmoke

/-- User code: id 2 `_ => pure 7`, id 4 `_ => canceled`. -/
def uR (id : Nat) (a : Val) (_ : View) : UserResult :=
  match id with
  | 2 => { out := .prog (.pure (.nat 7)) }
  | 4 => { out := .prog .canceled }
  -- `IO.async_(_ => ())`: the `ContState` get, no callback (waits forever)
  | 6 => match a with
    | .cont st => { out := .prog (.contGet st) }
    | _ => { out := .throw { code := 0 } }
  | _ => { out := .throw { code := 0 } }

def u : UserEnv := { call := fun id a refs => uR id a { refs }, callV := uR }

/-- User programs: pure, cede, sleep, self-cancel, masked self-cancel, error, cede then pure, a
long sleep (a child that runs until the close). -/
def progs : Array IO :=
  #[.pure .unit, .cede, .sleep 3, .canceled, .uncancelable (.user 4), .error { code := 5 },
    .flatMap .cede (.user 2), .sleep 100000, .pure .unit, CatsEffectInLean.Model.Timeout.neverIO]

def next (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648

def sched (seed len : Nat) : List PChoice := Id.run do
  let mut x := seed * 2654435761 + 7
  let mut cs : Array PChoice := #[]
  for _ in [0:len] do
    x := next x
    if x % 4 == 0 then cs := cs.push .preempt else cs := cs.push (.pick ((x / 4) % 4))
  return cs.toList

structure Inp where
  aw : Bool
  r : Bool
  cv : Nat
  ws : List IO
  ps : List Nat
  b : IO
  rev : Bool

def inp (seed : Nat) (pureOnly flat : Bool) (rOk : Bool) : Inp := Id.run do
  let mut x := next (seed * 7919 + 13)
  let aw := x % 2 == 0
  x := next x
  let r := rOk && x % 4 == 0
  x := next x
  let cv := x % 2
  x := next x
  let k := 1 + x % 3
  let mut ws : List IO := []
  let mut ps : List Nat := []
  for j in [0:k] do
    x := next x
    ws := ws ++ [if pureOnly then .pure .unit else progs.getD (x % progs.size) (.pure .unit)]
    x := next x
    ps := ps ++ [if flat then 0 else if x % 7 == 0 then late else if j == 0 then 0 else x % (j + 1)]
  x := next x
  let b := if pureOnly then .pure .unit else progs.getD (x % progs.size) (.pure .unit)
  x := next x
  return { aw, r, cv, ws, ps, b, rev := x % 2 == 0 }

def hoOf (rev : Bool) : List Val → List Val := if rev then List.reverse else id

def fuel : Nat := 3000

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

def hypOK (x : Inp) : Bool :=
  (x.b :: x.ws).all fun q => WF.progOK supLib (fun h => ([] : List Handle).contains h) q

def runOf (x : Inp) (i v : Nat) : List (Sched CounterMask) :=
  states (env (hoOf x.rev) x.ws x.ps x.b u) (prog x.aw x.r x.cv x.ws.length v) (sched i 400)

def isDone (s : Sched CounterMask) : Bool := match s.halt with | some (.done _) => true | _ => false

def bad1 (k : Nat) (s : Sched CounterMask) : Bool := isDone s && (List.range k).any (fun j => status s j == 1)
def bad2 (k : Nat) (s : Sched CounterMask) : Bool := (List.range k).any (fun j => rejected s j == 1 && runs s j != 0)
def bad2b (ps : List Nat) (s : Sched CounterMask) : Bool :=
  s.halt == some (.done (.succeeded .unit)) &&
    (List.range ps.length).any (fun j => ps.getD j 0 == late && rejected s j != 1)
def bad7 (k : Nat) (s : Sched CounterMask) : Bool := isDone s && (List.range k).any (fun j => status s j == 2)
def bad3 (k : Nat) (s : Sched CounterMask) : Bool := (List.range k).any (fun j => runs s j > 1 || fins s j > 1)
def bad4 (k : Nat) (s : Sched CounterMask) : Bool :=
  match s.halt with
  | some (.done oc) => oc != .succeeded .unit || (List.range k).any (fun j => status s j != 2)
  | _ => false
def bad5 (s : Sched CounterMask) : Bool := s.halt == some .blocked
def bad6 (s : Sched CounterMask) : Bool := s.halt == some .blocked && (mapFibers s).any (terminated s)

/-- Violations of statements 1..6 over `n` runs of variant `v`; also hypothesis failures, done
runs, blocked runs. -/
def stats (n v : Nat) : Array Nat := Id.run do
  let mut c : Array Nat := Array.replicate 10 0
  for i in [0:n] do
    -- statements 1, 2: any input (restart allowed)
    let x := inp i false false true
    if !hypOK x then c := c.modify 6 (· + 1)
    let ss := runOf x i v
    let last := ss.getLastD (Sched.init counterMaskModel (.pure .unit))
    let k := x.ws.length
    if bad1 k last then c := c.modify 0 (· + 1)
    if ss.any (bad2 k) || bad2b x.ps last then c := c.modify 1 (· + 1)
    if isDone last then c := c.modify 7 (· + 1)
    if last.halt == some .blocked then c := c.modify 8 (· + 1)
    -- statements 3, 6: no restart
    let x3 := inp (i + 100000) false false false
    let ss3 := runOf x3 i v
    let last3 := ss3.getLastD (Sched.init counterMaskModel (.pure .unit))
    if ss3.any (bad3 x3.ws.length) then c := c.modify 2 (· + 1)
    if bad6 last3 then c := c.modify 5 (· + 1)
    -- statement 4: await = true, flat, pure
    let x4 := { inp (i + 200000) true true false with aw := true }
    let last4 := (runOf x4 i v).getLastD (Sched.init counterMaskModel (.pure .unit))
    if bad4 x4.ws.length last4 then c := c.modify 3 (· + 1)
    -- statement 5: pure, no restart
    let x5 := inp (i + 300000) true false false
    let last5 := (runOf x5 i v).getLastD (Sched.init counterMaskModel (.pure .unit))
    if bad5 last5 then c := c.modify 4 (· + 1)
    -- statement 7: await = false, sleeping children
    let x7 := inp (i + 400000) true false false
    let x7 := { x7 with aw := false, ws := x7.ws.map (fun _ => .sleep (1 + i % 5)),
                        b := if i % 2 == 0 then .cede else .pure .unit }
    let last7 := (runOf x7 i v).getLastD (Sched.init counterMaskModel (.pure .unit))
    if bad7 x7.ws.length last7 then c := c.modify 9 (· + 1)
  return c

end SupSmoke

open SupSmoke in
def main (args : List String) : IO UInt32 := do
  let n := (args.head?.bind String.toNat?).getD 600
  let mut fail := false
  let s0 := stats n 0
  IO.println s!"v3.7.1: violations 1..6 = {s0.extract 0 6}, 7 = {s0[9]!}, hypothesis failures {s0[6]!}, done {s0[7]!}, blocked {s0[8]!} (of {n})"
  if (s0.extract 0 7).any (· != 0) || s0[9]! != 0 then fail := true
  -- wrong variants: the statements each must break
  let expect : List (Nat × List Nat) :=
    [(1, [3]), (2, [4]), (3, [3]), (4, [2]), (5, [3]), (6, [4]), (7, [0]), (8, [9]), (9, [1]), (10, [5]),
     (11, [0]), (12, [3])]
  for (v, need) in expect do
    let s := stats n v
    let ok := need.all fun i => s[i]! > 0
    IO.println s!"variant {v}: violations 1..6 = {s.extract 0 6}, 7 = {s[9]!} (must break {need.map fun i => if i == 9 then 7 else i + 1}): {if ok then "ok" else "MISSED"}"
    if !ok then fail := true
  return if fail then 1 else 0

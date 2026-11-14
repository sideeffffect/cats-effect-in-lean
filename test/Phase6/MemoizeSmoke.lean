import CatsEffectInLean.Props.Phase6.Memoize

/-!
# Smoke tests of the `memoize` properties (track M, Phase 6)

Random `PChoice` schedules (a fixed LCG; preemption with probability 1/4 at each micro-step) on
a family of `fa`, for the three statements of `Props/Phase6/Memoize.lean`, and wrong-function
tests. Native evaluation (`#guard`), not part of the build:

    lake env lean test/Phase6/MemoizeSmoke.lean

Results are in `wiki/cats-effect/memoize-model.md`.
-/

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase6.Memoize

namespace MemoizeSmoke

/-- User code of the `fa` family (even ids, `id / 2`): 1 `_ => pure 7`, 2 `_ => canceled`,
3 the thunk `IO.ref(0)` (a new cell each time: the value tells evaluations apart). -/
def uR (id : Nat) (_ : Val) (v : View) : UserResult :=
  match id / 2 with
  | 1 => { out := .prog (.pure (.nat 7)) }
  | 2 => { out := .prog .canceled }
  | 3 => { effects := [.allocRef (.nat 0)], out := .ret (.ref v.refs.length) }
  | _ => { out := .throw { code := 0 } }

def u : UserEnv := { call := fun id a refs => uR id a { refs }, callV := uR }

/-- The `fa` family. -/
def fas : List (String × IO) :=
  [("pure", .pure (.nat 7)), ("error", .error { code := 5 }), ("canceled", .canceled),
   ("cede-pure", .flatMap .cede (.user 2)), ("sleep-pure", .flatMap (.sleep 10) (.user 2)),
   ("cede-canceled", .flatMap .cede (.user 4)), ("unc-canceled", .uncancelable (.user 4)),
   ("newRef", .delay (.user 6)), ("never", Timeout.neverIO)]

/-- A random schedule: `len` choices, `preempt` with probability 1/4, else `pick` of a random index. -/
def sched (seed len : Nat) : List PChoice := Id.run do
  let mut x := seed * 2654435761 + 12345
  let mut cs : Array PChoice := #[]
  for _ in [0:len] do
    x := (x * 1103515245 + 12345) % 2147483648
    if x % 4 == 0 then cs := cs.push .preempt else cs := cs.push (.pick ((x / 4) % 3))
  return cs.toList

def fuel : Nat := 3000
def nSched : Nat := 400

def runs (variant : Nat) (counted : Bool) (fa : IO) : List (Sched CounterMask) :=
  (List.range nSched).map fun i =>
    run fa u fuel (sched i 150) (if counted then countedTwoGets variant else twoGets variant)

def stuck (s : Sched CounterMask) : Bool := s.halt == some .blocked && memoFinished s 0
def agreeOK (s : Sched CounterMask) : Bool :=
  match s.halt with
  | some (.done (.succeeded (.pair oa ob))) => oa == ob
  | _ => true
def done (s : Sched CounterMask) : Bool := match s.halt with | some (.done _) => true | _ => false

/-- Statement 1: v3.7.1 is stuck only for the self-canceling `fa`; the fixed twin never. -/
def stuckCounts (variant : Nat) : List (String × Nat) :=
  fas.map fun (n, fa) => (n, ((runs variant false fa).filter stuck).length)

#eval stuckCounts 0
#guard (stuckCounts 1).all (·.2 == 0)
#guard ((stuckCounts 0).filter (·.2 > 0)).map (·.1) ⊆ ["canceled", "cede-canceled", "unc-canceled"]
#guard (stuckCounts 0).any (·.2 > 0)

/-- Statement 2: no violation of `memoizeGetsAgree` on v3.7.1; most runs complete. -/
def agreeStats : List (String × Nat × Nat) :=
  fas.map fun (n, fa) => let rs := runs 0 false fa; (n, (rs.filter done).length, (rs.filter (!agreeOK ·)).length)

#eval agreeStats
#guard agreeStats.all (·.2.2 == 0)

/-- Statement 3: the counter of `countedTwoGets` is at most 1 on v3.7.1. -/
def maxCounter : List (String × Nat) :=
  fas.map fun (n, fa) => (n, ((runs 0 true fa).map counter).foldl max 0)

#eval maxCounter
#guard maxCounter.all (·.2 ≤ 1)

/-! ## Wrong-function tests

A `memoize` whose `get` is `fa` itself (no cache). The test programs below have the shape of
`twoGets` and `countedTwoGets` with `get := fa` (user closures, namespace 33, test only). -/

def wns : Nat := 33

/-- `fa.start.flatMap(a => fa.start.flatMap(b => a.join.flatMap(oa => b.join.map(ob => (oa, ob)))))`
and the counted form `Ref(0).flatMap(c => (incr c *> fa) >> (incr c *> fa))`. -/
inductive WLam where
  | afterA | afterB (a : Nat) | thenJoin (b : Nat) | pairWith (oa : Val) | counted | second (c : Nat)

def WLam.toVal : WLam → Val
  | .afterA => cloVal wns 0 []
  | .afterB a => cloVal wns 1 [.fiber a]
  | .thenJoin b => cloVal wns 2 [.fiber b]
  | .pairWith oa => cloVal wns 3 [oa]
  | .counted => cloVal wns 4 []
  | .second c => cloVal wns 5 [.ref c]

def WLam.fn (l : WLam) : Fn := userFn l.toVal

def wu (fa : IO) : UserEnv :=
  let callV : Nat → Val → View → UserResult := fun id a v =>
    match (cloOfId id).bind ofCloVal with
    | some (33, 0, []) => match a with
      | .fiber x => { out := .prog (.flatMap (.start fa) (WLam.afterB x).fn) }
      | _ => { out := .throw { code := 0 } }
    | some (33, 1, [.fiber x]) => match a with
      | .fiber y => { out := .prog (.flatMap (IO.joinOf x (v.outcome x)) (WLam.thenJoin y).fn) }
      | _ => { out := .throw { code := 0 } }
    | some (33, 2, [.fiber y]) => { out := .prog (.map (IO.joinOf y (v.outcome y)) (WLam.pairWith a).fn) }
    | some (33, 3, [oa]) => { out := .ret (.pair oa a) }
    | some (33, 4, []) => match a with
      | .ref c => { out := .prog (.flatMap (srcIO fa (.ref c)) (WLam.second c).fn) }
      | _ => { out := .throw { code := 0 } }
    | some (33, 5, [.ref c]) => { out := .prog (srcIO fa (.ref c)) }
    | _ => uR id a v
  { call := fun id a refs => callV id a { refs }, callV }

def wrongTwo (fa : IO) : IO := .flatMap (.start fa) WLam.afterA.fn
def wrongCounted : IO := .flatMap (.delay TLam.newCounter.fn) WLam.counted.fn

def wrun (fa : IO) (cs : List PChoice) (io : IO) : Sched CounterMask :=
  runSchedStateP {} counterMaskModel (env fa (wu fa)) fuel cs (Sched.init counterMaskModel io)

-- statement 2 fails for the wrong function (`fa = IO.ref(0)`: two evaluations, two cells)
#guard !(agreeOK (wrun (.delay (.user 6)) [] (wrongTwo (.delay (.user 6)))))
-- statement 3 fails for the wrong function: the counter is 2
#guard counter (wrun (.pure (.nat 7)) [] wrongCounted) == 2
-- and the real `memoize` passes both on the same inputs (FIFO)
#guard agreeOK (run (.delay (.user 6)) u fuel [] (twoGets 0))
#guard counter (run (.pure (.nat 7)) u fuel [] (countedTwoGets 0)) == 1

end MemoizeSmoke

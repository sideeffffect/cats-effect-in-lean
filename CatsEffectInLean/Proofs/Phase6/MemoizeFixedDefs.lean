import CatsEffectInLean.Proofs.Phase6.MemoizeStuck

/-!
# CE-0030: fixed-twin check (decision 39), definitions

Variant 1 of the `memoize` mirror (`Model/Memoize.lean`) is **not Cats Effect code**: the
`Finished` case of `flatModifyFull` returns `poll(fromEither(result).flatten)`.

Program: `twoGets` (two `get` fibers, the root joins both) with a family of `fa`:
`IO.canceled`, `pure(7)`, `raiseError(E5)`, `emit >> canceled`, `start(emit) >> canceled`,
`cede >> canceled`, `uncancelable(_ => canceled)`. `emit` is a user thunk that emits a value;
`_ => canceled` is a user function. Schedules: one preemption at each position below 120, then
FIFO (fuel 200: every run ends; the longest FIFO run has 84 micro-steps). For `cede >> canceled`
one preemption never hits the window (the `cede` lets the second `get` finish first), so it also
gets the 150 two-preemption schedules `(i, j)`, `i ∈ [30, 40)`, `j ∈ [5, 20)`.

"Stuck" = the violation of `memoizeNoStuckGet`: blocked with a `Finished` memo.

| `fa` | v3.7.1 stuck at | fixed twin |
|---|---|---|
| `canceled` | 35, 36, 37 | all 120 runs complete (`done`) |
| `pure(7)` | none | all complete |
| `raiseError(E5)` | none | all complete |
| `emit >> canceled` | 35, 36, 37 | all complete |
| `start(emit) >> canceled` | 35, 36, 37 | all complete |
| `cede >> canceled` | none (one preemption); (34..37, 11..14) window with two | all complete (both grids) |
| `uncancelable(_ => canceled)` | 35, 36, 37 | all complete |

v3.7.1 fails exactly for the self-canceling `fa` and never for `pure`/`raiseError`.

The checks are in `MemoizeFixedParts/`, one module each (memory; a parallel CI matrix);
`MemoizeFixed.lean` collects them (`lean_lib TwinChecks`, `scripts/check_twin_checks.sh`).
-/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

/-! ## The original witness (`fa = IO.canceled`, no user code) -/

/-- One preemption at position `i` (then FIFO). -/
def onePreempt (variant i : Nat) : Option Summary :=
  (run fa u 120 (List.replicate i (.pick 0) ++ [.preempt]) (twoGets variant)).halt

/-! ## The `fa` family -/

/-- User code of the family (even ids, `id / 2`): 1 the thunk `emit(1)`, 2 `_ => IO.canceled`. -/
def famR (id : Nat) (_ : Val) (_ : View) : UserResult :=
  match id / 2 with
  | 1 => { effects := [.emit (.nat 1)], out := .ret .unit }
  | 2 => { out := .prog .canceled }
  | _ => { out := .throw { code := 0 } }

def famU : UserEnv := { call := fun id a refs => famR id a { refs }, callV := famR }

def faPure : IO := .pure (.nat 7)
def faError : IO := .error { code := 5 }
def faEmitCanceled : IO := .flatMap (.delay (.user 2)) (.user 4)
def faStartEmitCanceled : IO := .flatMap (.start (.delay (.user 2))) (.user 4)
def faCedeCanceled : IO := .flatMap .cede (.user 4)
def faUncCanceled : IO := .uncancelable (.user 4)

/-- Blocked with a `Finished` memo: a violation of `memoizeNoStuckGet`. -/
def stuck (s : Sched CounterMask) : Bool := s.halt == some .blocked && memoFinished s 0

/-- The root completed. -/
def isDone (s : Sched CounterMask) : Bool :=
  match s.halt with
  | some (.done _) => true
  | _ => false

def one (f : IO) (variant i : Nat) : Sched CounterMask :=
  run f famU 200 (List.replicate i (.pick 0) ++ [.preempt]) (twoGets variant)

def two (f : IO) (variant i j : Nat) : Sched CounterMask :=
  run f famU 250 (List.replicate i (.pick 0) ++ [.preempt] ++ List.replicate j (.pick 0) ++ [.preempt])
    (twoGets variant)

/-- The fixed twin completes on all 120 one-preemption schedules. -/
def fixedOK (f : IO) : Bool := (List.range 120).all fun i => isDone (one f 1 i)
/-- The positions where v3.7.1 is stuck. -/
def oldStuck (f : IO) : List Nat := (List.range 120).filter fun i => stuck (one f 0 i)

/-- The two-preemption grid. -/
def grid : List (Nat × Nat) := (List.range 10).flatMap fun a => (List.range 15).map fun b => (30 + a, 5 + b)



/-! ## Splitting the schedule lists (each check runs in two halves, for memory) -/

theorem range_split (n m : Nat) : List.range (n + m) = List.range' 0 n ++ List.range' n m := by
  rw [List.range_eq_range']
  have := (List.range'_append (s := 0) (m := n) (n := m) (step := 1)).symm
  simpa using this

/-- The two-preemption grid for `a ∈ [lo, lo + n)`. -/
def gridOn (lo n : Nat) : List (Nat × Nat) :=
  (List.range' lo n).flatMap fun a => (List.range 15).map fun b => (30 + a, 5 + b)

theorem grid_split : grid = gridOn 0 5 ++ gridOn 5 5 := by
  unfold grid gridOn
  rw [show (10 : Nat) = 5 + 5 from rfl, range_split, List.flatMap_append]

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

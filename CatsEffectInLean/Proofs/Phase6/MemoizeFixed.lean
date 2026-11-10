import CatsEffectInLean.Proofs.Phase6.MemoizeStuck

/-!
# CE-0030: fixed-twin check (decision 39)

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

In `lean_lib TwinChecks` (one declaration per program and variant, `decide +kernel`; built by
`scripts/check_twin_checks.sh`).
-/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

/-! ## The original witness (`fa = IO.canceled`, no user code) -/

/-- One preemption at position `i` (then FIFO). -/
def onePreempt (variant i : Nat) : Option Summary :=
  (run fa u 120 (List.replicate i (.pick 0) ++ [.preempt]) (twoGets variant)).halt

/-- The fixed twin is never blocked with one preemption at a position below 120. -/
theorem fixed_onePreempt :
    (List.range 120).all (fun i => onePreempt 1 i != some .blocked) = true := by decide +kernel

/-- v3.7.1 is blocked exactly at positions 35, 36, 37 (positions below 120). -/
theorem old_onePreempt :
    (List.range 120).filter (fun i => onePreempt 0 i == some .blocked) = [35, 36, 37] := by
  decide +kernel

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

theorem fam_fixed_canceled : fixedOK .canceled = true := by decide +kernel
theorem fam_old_canceled : oldStuck .canceled = [35, 36, 37] := by decide +kernel
theorem fam_fixed_pure : fixedOK faPure = true := by decide +kernel
theorem fam_old_pure : oldStuck faPure = [] := by decide +kernel
theorem fam_fixed_error : fixedOK faError = true := by decide +kernel
theorem fam_old_error : oldStuck faError = [] := by decide +kernel
theorem fam_fixed_emitCanceled : fixedOK faEmitCanceled = true := by decide +kernel
theorem fam_old_emitCanceled : oldStuck faEmitCanceled = [35, 36, 37] := by decide +kernel
theorem fam_fixed_startEmitCanceled : fixedOK faStartEmitCanceled = true := by decide +kernel
theorem fam_old_startEmitCanceled : oldStuck faStartEmitCanceled = [35, 36, 37] := by decide +kernel
theorem fam_fixed_cedeCanceled : fixedOK faCedeCanceled = true := by decide +kernel
theorem fam_old_cedeCanceled : oldStuck faCedeCanceled = [] := by decide +kernel
theorem fam_fixed_cedeCanceled2 :
    grid.all (fun (i, j) => isDone (two faCedeCanceled 1 i j)) = true := by decide +kernel
theorem fam_old_cedeCanceled2 :
    grid.filter (fun (i, j) => stuck (two faCedeCanceled 0 i j)) =
      [(34, 12), (34, 13), (34, 14), (35, 11), (35, 12), (35, 13), (36, 11), (36, 12), (37, 11)] := by
  decide +kernel
theorem fam_fixed_uncCanceled : fixedOK faUncCanceled = true := by decide +kernel
theorem fam_old_uncCanceled : oldStuck faUncCanceled = [35, 36, 37] := by decide +kernel

/-- All checks of this file (for the axiom check of `scripts/check_twin_checks.sh`). -/
theorem all_checks :
    ((List.range 120).all (fun i => onePreempt 1 i != some .blocked) = true ∧
     (List.range 120).filter (fun i => onePreempt 0 i == some .blocked) = [35, 36, 37]) ∧
    (fixedOK .canceled ∧ fixedOK faPure ∧ fixedOK faError ∧ fixedOK faEmitCanceled ∧
     fixedOK faStartEmitCanceled ∧ fixedOK faCedeCanceled ∧ fixedOK faUncCanceled) ∧
    (oldStuck .canceled = [35, 36, 37] ∧ oldStuck faPure = [] ∧ oldStuck faError = [] ∧
     oldStuck faEmitCanceled = [35, 36, 37] ∧ oldStuck faStartEmitCanceled = [35, 36, 37] ∧
     oldStuck faCedeCanceled = [] ∧ oldStuck faUncCanceled = [35, 36, 37]) ∧
    grid.all (fun (i, j) => isDone (two faCedeCanceled 1 i j)) = true ∧
    grid.filter (fun (i, j) => stuck (two faCedeCanceled 0 i j)) =
      [(34, 12), (34, 13), (34, 14), (35, 11), (35, 12), (35, 13), (36, 11), (36, 12), (37, 11)] :=
  ⟨⟨fixed_onePreempt, old_onePreempt⟩,
   ⟨fam_fixed_canceled, fam_fixed_pure, fam_fixed_error, fam_fixed_emitCanceled,
    fam_fixed_startEmitCanceled, fam_fixed_cedeCanceled, fam_fixed_uncCanceled⟩,
   ⟨fam_old_canceled, fam_old_pure, fam_old_error, fam_old_emitCanceled, fam_old_startEmitCanceled,
    fam_old_cedeCanceled, fam_old_uncCanceled⟩,
   fam_fixed_cedeCanceled2, fam_old_cedeCanceled2⟩

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

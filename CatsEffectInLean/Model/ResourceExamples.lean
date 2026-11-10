import CatsEffectInLean.Model.Resource
import CatsEffectInLean.Model.Outcomes

/-!
# `Resource` examples (CE-0002)

Hand-checked runs of `allocatedCase` (`CatsEffectInLean/Model/Resource.lean`) on the
multi-fiber scheduler (`runObs`, default `Config`, `counterMaskModel`, FIFO schedule). Each
check is `decide +kernel`. The expected values follow the Scala code at `v3.7.1`; cases B and C
are the cases of `reproducers/CE-0002/Repro.scala`.

`out` is newest first.
-/

namespace CatsEffectInLean.Model.ResourceExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource

/-- The error of `raiseError` in the examples. -/
def boom : Err := { code := 5 }

/-- `fa = IO.uncancelable(_ => IO.canceled)` (user body 0). -/
def faU : IO := .uncancelable (uid 0)

/-- `Resource.eval(fa).allocatedCase` with `fa = faU`. -/
def allocEval : IO := .flatMap faU (cloFn (.evalK [] .unit))

/-- Case B resources: `make(IO.pure(42))(_ => IO.unit).flatMap(_ => lift(faU))`. -/
def caseBEval : Res := (Res.make 1 2).flatMap 3
def caseBMake : Res := (Res.make 1 2).flatMap 4

/-- What `allocatedCase` builds for the case B resources (checked below). -/
def caseBEvalAlloc : IO := .uncancelable (cloFn (.allocBody (.make 1 2) [3] .unit))
def caseBMakeAlloc : IO := .uncancelable (cloFn (.allocBody (.make 1 2) [4] .unit))

/-- The fix of upstream PR #4630 for `Eval` (wrong-function test):
`F.uncancelable { poll => poll(fa).flatMap(a => continue(...)) }` (user body 9). -/
def fixedAlloc : IO := .uncancelable (uid 9)

/-- User code.
* 0: `_ => IO.canceled`;
* 1: acquire thunk: emit `1`, return `42`;
* 2, 3: release thunks: emit `100`, `101`;
* 4, 5: case B bodies `poll => poll(alloc).flatMap(_ => emit 7)` (eval, make);
* 6: `_ => { emit 7; IO.unit }`;
* 7: `applyFull` resource `poll => IO.pure((9, rel))` with `rel` = user function 8;
* 8: release function value `ec => { emit ec; IO.unit }`;
* 9: fixed `Eval` body; 10: `_ => fixedAlloc`; 11: `_ => allocEval`. -/
def user : UserEnv where
  call id arg _ := match id, arg with
    | 0, _ => { out := .prog .canceled }
    | 1, _ => { effects := [.emit (.nat 1)], out := .ret (.nat 42) }
    | 2, _ => { effects := [.emit (.nat 100)], out := .ret .unit }
    | 3, _ => { effects := [.emit (.nat 101)], out := .ret .unit }
    | 4, .poll m s => { out := .prog (.flatMap (.unmaskRunLoop caseBEvalAlloc m s) (uid 6)) }
    | 5, .poll m s => { out := .prog (.flatMap (.unmaskRunLoop caseBMakeAlloc m s) (uid 6)) }
    | 6, _ => { effects := [.emit (.nat 7)], out := .prog (.pure .unit) }
    | 7, _ => { out := .prog (.pure (.pair (.nat 9) (RelFn.user 8).toVal)) }
    | 8, ec => { effects := [.emit ec], out := .prog (.pure .unit) }
    | 9, .poll m s => { out := .prog (.flatMap (.unmaskRunLoop faU m s) (cloFn (.evalK [] .unit))) }
    | 10, _ => { out := .prog fixedAlloc }
    | 11, _ => { out := .prog allocEval }
    | _, _ => { out := .throw { code := 0 } }

/-- `Resource`-level code.
* `bind`: 0 `_ => eval(raiseError(boom))`, 1 `_ => make(0)(1)`, 2 `_ => eval(IO.canceled)`,
  3 `_ => eval(faU)`, 4 `_ => make(2)(2)`;
* `acquire`: 0 `IO.delay(user 1)`, 1 `IO.pure(42)`, 2 `faU`;
* `release`: 0 `IO.delay(user 2)`, 1 `IO.delay(user 3)`, 2 `IO.unit`. -/
def r : REnv where
  user := user
  bind k _ := match k with
    | 0 => .ok (.eval (.error boom))
    | 1 => .ok (Res.make 0 1)
    | 2 => .ok (.eval .canceled)
    | 3 => .ok (.eval faU)
    | 4 => .ok (Res.make 2 2)
    | _ => .error { code := 0 }
  acquire k := match k with
    | 0 => .delay (uid 1)
    | 1 => .pure (.nat 42)
    | 2 => faU
    | _ => .pure .unit
  release k _ := match k with
    | 0 => .ok (.delay (uid 2))
    | 1 => .ok (.delay (uid 3))
    | _ => .ok (.pure .unit)

/-- The program of `allocatedCase` (`.endFiber` if a `Bind` function throws while building). -/
def alloc (res : Res) : IO :=
  match allocatedCase r res with
  | .ok io => io
  | .error _ => .endFiber

/-- Run with fuel `n`, FIFO. -/
def run (n : Nat) (io : IO) : Option Obs := runObs {} counterMaskModel r.toEnv n [] io

def obs (s : Summary) (out : List Val) : Option Obs :=
  some { summary := s, out := out, refs := [], reports := [] }

/-! ## Success, error, cancel, LIFO -/

/-- `make(acquire)(release).allocatedCase`: succeeds with `(42, rel2)`; the release does not
run. `rel2 = rel(ec).guarantee(F.unit >> (_ => F.unit)(ec))` (`Resource.scala:490`). -/
theorem make_succeeds :
    run 40 (alloc (Res.make 0 0)) =
      obs (.done (.succeeded (.pair (.nat 42) (RelFn.guarantee (.const 0 (.nat 42)) .unit).toVal)))
        [.nat 1] := by
  decide +kernel

/-- Release on error: `make(acquire)(release).flatMap(_ => eval(raiseError(boom)))`. The
`onError` of `Resource.scala:510` runs the release, then the error goes on. -/
theorem release_on_error :
    run 60 (alloc ((Res.make 0 0).flatMap 0)) = obs (.done (.errored boom)) [.nat 100, .nat 1] := by
  decide +kernel

/-- Release on cancel: `make(acquire)(release).flatMap(_ => eval(IO.canceled))`. The
`onCancel` of `Resource.scala:509` runs the release. -/
theorem release_on_cancel :
    run 60 (alloc ((Res.make 0 0).flatMap 2)) = obs (.done .canceled) [.nat 100, .nat 1] := by
  decide +kernel

/-- Finalizers in LIFO order: `make(a)(r0).flatMap(_ => make(a)(r1)).flatMap(_ => eval(raiseError))`:
acquire, acquire, then release `r1` (`101`), then `r0` (`100`). -/
theorem release_lifo :
    run 120 (alloc (((Res.make 0 0).flatMap 1).flatMap 0)) =
      obs (.done (.errored boom)) [.nat 100, .nat 101, .nat 1, .nat 1] := by
  decide +kernel

/-- A user release function gets the `ExitCase`: `applyFull(poll => IO.pure((9, rel)))
.flatMap(_ => eval(raiseError(boom)))`. Here `rel` emits its argument when it is called. Scala
calls `rel(ExitCase.Canceled)` when it builds the `onCancel` (`Resource.scala:509`, strict
argument), so `Canceled` is emitted first, although that finalizer never runs. Then the
`onError` handler calls `rel(Errored(boom))` and runs it. -/
theorem release_sees_exit_case :
    run 60 (alloc ((Res.allocate (.user 7)).flatMap 0)) =
      obs (.done (.errored boom)) [.ocErrored boom, .ocCanceled] := by
  decide +kernel

/-! ## CE-0002 -/

/-- `fa` alone succeeds: the cancel request waits for the end of the mask, and nothing after
it checks. -/
theorem fa_succeeds : run 20 faU = obs (.done (.succeeded .unit)) [] := by decide +kernel

/-- `allocatedCase` of `Resource.eval(fa)` is `fa.flatMap(...)` (`Resource.scala:526-527`). -/
theorem allocEval_eq : allocatedCase r (.eval faU) = .ok allocEval := rfl

/-- Case C: `Resource.eval(fa).allocatedCase` is canceled after `fa`. -/
theorem caseC_eval : run 20 allocEval = obs (.done .canceled) [] := by decide +kernel

/-- Case C: the same under `IO.uncancelable(_ => ...)` succeeds. -/
theorem caseC_masked :
    run 20 (.uncancelable (uid 11)) = obs (.done (.succeeded (.pair .unit RelFn.unit.toVal))) [] := by
  decide +kernel

/-- Wrong-function test: the fix of PR #4630 succeeds, with and without the outer mask. -/
theorem fixed_lhs :
    run 30 fixedAlloc = obs (.done (.succeeded (.pair .unit RelFn.unit.toVal))) [] := by
  decide +kernel

theorem fixed_rhs :
    run 30 (.uncancelable (uid 10)) = obs (.done (.succeeded (.pair .unit RelFn.unit.toVal))) [] := by
  decide +kernel

theorem caseBEval_eq : allocatedCase r caseBEval = .ok caseBEvalAlloc := rfl
theorem caseBMake_eq : allocatedCase r caseBMake = .ok caseBMakeAlloc := rfl

/-- Case B with `Resource.eval`: `IO.uncancelable(poll => poll(res.allocatedCase).flatMap(_ =>
emit 7))`. The fiber is canceled; the continuation (`emit 7`) does not run. -/
theorem caseB_eval : run 80 (.uncancelable (uid 4)) = obs (.done .canceled) [] := by
  decide +kernel

/-- Case B with the twin `Resource.make(fa)(_ => IO.unit)`: the continuation runs. -/
theorem caseB_make :
    run 120 (.uncancelable (uid 5)) = obs (.done (.succeeded .unit)) [.nat 7] := by
  decide +kernel

end CatsEffectInLean.Model.ResourceExamples

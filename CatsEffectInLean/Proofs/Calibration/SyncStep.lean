import CatsEffectInLean.Props.Calibration.SyncStep

/-!
# Refutation of `syncStepIdentitySyncIO` (CE-0001)

Counterexample: case 4 of `reproducers/CE-0001/Repro.scala`,

```scala
IO.uncancelable(_ => IO.canceled *> flag.set(true))     // limit = Int.MaxValue
```

* Direct: `IO.canceled` inside an uncancelable region is a no-op. The run ends `Succeeded(())`
  and `flag = true`.
* Stepped: `SyncStep.interpret` takes the `Uncancelable` branch (`IO.scala:2390-2394`), calls
  the body with `IdPoll` and walks into `canceled *> ...`. `IO.Canceled` is not in `SyncIO`,
  so the result is `Left(IO.canceled.flatMap(_ => flag.set(true)))`: the mask is gone. That
  rest cancels itself: `Canceled`, `flag = false`.

Proof. The direct run under 6 `step true` choices gives `(Succeeded(()), [true], [])`. For the
stepped side, each `SyncIO` fuel below 6 gives "out of fuel", and each fuel `m + 6` gives the
same rest (`rfl` with a free `m`). The rest starts in state `s0`. The set `reach` of 10 states
is closed under all choices (`step true`, `step false`, `cancel c` for each `c`; a `cancel` on
a fiber that is not suspended does not read `c`), and no state in it shows the direct
observation. So no schedule of the stepped side gives it.

Wrong-function test: a `syncStep` that keeps the mask (upstream fix PR #4700) gives the rest
`IO.uncancelable(_ => IO.canceled *> ...)`, which shows the direct observation; the proof then
fails at `reach_obs`.
-/

namespace CatsEffectInLean.Proofs.Calibration

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs
open CatsEffectInLean.Props.Calibration

/-- The user code of the counterexample (user functions have even ids, `Model/Codec.lean`).
`0`: the body `_ => IO.canceled *> flag.set(true)` (it ignores the `poll`); `*>` is
`flatMap(_ => that)` (`IO.scala:138-139`, `IO.scala:903-904`). `2`: `_ => flag.set(true)`.
`4`: the thunk of `flag.set(true)`, the `IO.delay` of `SyncRef.set` (a write to `Ref` cell 0,
which exists before the program: `H0`). -/
def cxEnv : UserEnv where
  call
    | 0, _, _ => { out := .prog (.flatMap .canceled (.user 2)) }
    | 2, _, _ => { out := .prog (.delay (.user 4)) }
    | 4, _, _ => { effects := [.writeRef 0 (.bool true)], out := .ret .unit }
    | _, _, _ => { out := .ret .unit }

/-- `IO.uncancelable(body)` = `Uncancelable(body)` (`IO.scala:1712-1713`). -/
def cxFa : IO := .uncancelable (.user 0)

/-- `flag` = `Ref` cell 0, initially `false`. -/
def cxRefs : List Val := [.bool false]

/-- `Int.MaxValue`. -/
def cxLimit : Int := 2147483647

/-- The direct observation. -/
def cxDirect : Obs := (.done (.succeeded .unit), [.bool true], [])

/-- The direct run gives `Succeeded(())` with `flag = true`. -/
theorem direct_run : directObs cxEnv cxFa cxRefs (List.replicate 6 (.step true)) = cxDirect := by
  decide +kernel

/-- The rest that the stepped side runs: `IO.canceled.flatMap(_ => flag.set(true))`. -/
def cxRest : IO := .flatMap .canceled (.user 2)

/-- With `SyncIO` fuel `m + 6`, `syncStep(Int.MaxValue).unsafeRunSync()` gives `Left(cxRest)`
and does not change the heap. -/
theorem rest_big (m : Nat) :
    SyncStep.steppedRest counterMaskModel cxEnv (m + 6) cxFa cxLimit cxRefs
      = .ok (cxRest, { refs := cxRefs }) := by
  rfl

/-- Is a `steppedRest` result "out of fuel"? (`Except` has no `DecidableEq` instance.) -/
def isOutOfFuel : Except Summary (IO × Heap) → Bool
  | .error .outOfFuel => true
  | _ => false

/-- With less fuel, the `SyncIO` part is out of fuel. -/
theorem rest_small_check : ∀ k, k < 6 →
    isOutOfFuel (SyncStep.steppedRest counterMaskModel cxEnv k cxFa cxLimit cxRefs) = true := by
  decide +kernel

theorem rest_small (k : Nat) (hk : k < 6) :
    SyncStep.steppedRest counterMaskModel cxEnv k cxFa cxLimit cxRefs = .error .outOfFuel := by
  have h := rest_small_check k hk
  revert h
  generalize SyncStep.steppedRest counterMaskModel cxEnv k cxFa cxLimit cxRefs = r
  intro h
  match r, h with
  | .error .outOfFuel, _ => rfl

/-- One choice of the single-fiber driver. -/
abbrev S := Solo CounterMask

/-- `Solo.next` for the counterexample. -/
def nx (c : SoloChoice) (s : S) : S := Solo.next {} counterMaskModel cxEnv c s

/-- The successors of a state for the three representative choices. -/
def succs (s : S) : List S := [nx (.step true) s, nx (.step false) s, nx (.cancel 0) s]

/-- Breadth-first growth of a state list (no duplicates). -/
def grow : Nat → List S → List S
  | 0, l => l
  | n + 1, l =>
    grow n (l.foldl (fun acc s => (succs s).foldl
      (fun acc t => if acc.contains t then acc else acc ++ [t]) acc) l)

/-- The start state of the stepped `IO` run. -/
def s0 : S := rootOn counterMaskModel cxRest { refs := cxRefs }

/-- The states that the stepped run can reach (10 states). -/
def reach : List S := grow 6 [s0]

/-- No suspended fiber: then `cancel c` does not read `c`. -/
def noSusp : S → Bool
  | .suspended _ => false
  | .parked x => !x.fib.suspended
  | _ => true

/-- `cancel c` on a fiber that is not suspended does not depend on `c` (`cancelFiber` uses
`c` only for the takeover of a suspended fiber, `FIB:155-161`). -/
theorem nx_cancel (s : S) (h : noSusp s = true) (c : Nat) :
    nx (.cancel c) s = nx (.cancel 0) s := by
  cases s with
  | running l => rfl
  | parked x =>
    simp only [noSusp, Bool.not_eq_true'] at h
    simp [nx, Solo.next, cancelFiber, h]
  | suspended x => simp [noSusp] at h
  | _ => rfl

/-- `reach` is closed under the representative choices, and has no suspended fiber. -/
theorem reach_closed : ∀ s ∈ reach, noSusp s = true ∧ nx (.step true) s ∈ reach ∧
    nx (.step false) s ∈ reach ∧ nx (.cancel 0) s ∈ reach := by
  decide +kernel

/-- No state in `reach` shows the direct observation. -/
theorem reach_obs : ∀ s ∈ reach, ofSolo s ≠ cxDirect := by
  decide +kernel

/-- `reach` is closed under all choices. -/
theorem nx_mem (c : SoloChoice) (s : S) (hs : s ∈ reach) : nx c s ∈ reach := by
  obtain ⟨hn, ht, hf, hc⟩ := reach_closed s hs
  cases c with
  | step b => cases b <;> assumption
  | cancel c => rw [nx_cancel s hn c]; exact hc

/-- Every schedule keeps the stepped run in `reach`. -/
theorem exec_mem : ∀ (cs : List SoloChoice) (s : S), s ∈ reach →
    Solo.exec {} counterMaskModel cxEnv cs s ∈ reach
  | [], _, hs => hs
  | c :: cs, s, hs => exec_mem cs (nx c s) (nx_mem c s hs)

/-- No stepped run gives the direct observation. -/
theorem stepped_ne (fuel : Nat) (cs : List SoloChoice) :
    steppedObs cxEnv cxFa cxLimit cxRefs fuel cs ≠ cxDirect := by
  intro heq
  by_cases hf : fuel < 6
  · simp only [steppedObs, rest_small fuel hf, cxDirect] at heq
    cases heq
  · obtain ⟨m, rfl⟩ : ∃ m, fuel = m + 6 := ⟨fuel - 6, by omega⟩
    simp only [steppedObs, rest_big] at heq
    exact reach_obs _ (exec_mem cs s0 (by decide +kernel)) heq

/-! ## The witness is well-formed -/

theorem captured_small : WF.captured 0 = [] ∧ WF.captured 2 = [] ∧ WF.captured 4 = [] := by
  decide +kernel

/-- The start program passes `progOK` (decidable). -/
theorem cx_prog : WF.progOK (fun _ => false) ((refHandles cxRefs).contains ·) cxFa = true := by
  decide +kernel

/-- Each user function of `cxEnv` passes `CallOK`: it ignores the view; its effects and its
result use only `Ref` cell 0, which is in `H0`. -/
theorem cx_calls (id : Nat) (arg : Val) (v : View) :
    WF.CallOK (fun _ => false) (refHandles cxRefs) cxEnv id arg v := by
  obtain ⟨c0, c2, c4⟩ := captured_small
  refine ⟨fun w _ => ?_, ?_⟩
  · rcases id with _ | _ | _ | _ | _ | id <;> rfl
  · rcases id with _ | _ | _ | _ | _ | id <;>
      simp [WF.ResultOK, WF.EffectsOK, WF.OutOK, cxEnv, WF.progOK, WF.fnOK, WF.sub, c2, c4,
        Val.handles]
    exact WF.reach_of_mem (by simp [refHandles, cxRefs])

theorem cx_wellFormed : WellFormed (fun _ => false) (refHandles cxRefs) cxEnv cxFa :=
  ⟨cx_prog, fun id _ arg v => cx_calls id arg v⟩

/-- CE-0001: `syncStepIdentity` fails for `IO#syncStep` with `G = SyncIO`. -/
theorem syncStepIdentitySyncIO_refuted : ¬ syncStepIdentitySyncIO := by
  intro h
  obtain ⟨fuel, cs', heq⟩ :=
    (h cxEnv cxFa cxLimit cxRefs (by decide) cx_wellFormed).1 (List.replicate 6 (.step true))
      (by decide +kernel)
  rw [direct_run] at heq
  exact stepped_ne fuel cs' heq

end CatsEffectInLean.Proofs.Calibration

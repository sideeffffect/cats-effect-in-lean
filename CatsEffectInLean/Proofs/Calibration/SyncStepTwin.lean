import CatsEffectInLean.Proofs.Calibration.SyncStepTwinFamily

/-!
# CE-0001 fixed-twin check (decision 39): PR #4700 on the bounded domain

`Model/SyncStepFixed.lean` mirrors the fix of upstream PR #4700 (`DeferredPoll`, `Bind`, the
rewrap of `onCancel`, the `try` around the body). On the ten programs of
`SyncStepTwinFamily.lean` (all non-fatal; `uncancelable`, `poll` before and after an async
boundary, `onCancel`, `canceled`, a poll that escapes its region, nested regions, an error
through a rebuilt region, a throwing body):

* the fixed twin satisfies `StepIdentityFor` for all ten (`fixed_twin`);
* Cats Effect v3.7.1 fails it for programs 1, 4, 5, 6 and 10 (`v371_fails`) and satisfies it
  for 2, 3, 7, 8 and 9 (by the same check; not needed for the result).

So the property separates v3.7.1 from the upstream fix, and the refutation of
`syncStepIdentitySyncIO` is not an artifact that the fix also has (review batch 2, entry 5).

Programs 2, 5, 6 and 7 apply a poll after an async boundary (`IO.cede`). The reviewer
suspected that a fix that keeps `IdPoll` in the continuation is incomplete there. That is true
for such a fix (in program 2 its rest `uncancelable(_ => IO.cede *> IdPoll(IO.canceled) *> ...)`
ignores the cancel), but PR #4700 does not keep `IdPoll`: its `DeferredPoll` reads the real
`Poll` from the fiber's `IOLocal` state at run time, and the twin agrees with the direct run.

Program 10 shows a second difference that PR #4700 fixes: in v3.7.1 a throw from the body
leaves `interpret` (model: the rest is `IO.raiseError(e)`, `Errored`); the direct run and the
twin catch it in the region (`Succeeded`, emit 2).

Each check: the `SyncIO` part is out of fuel below a bound `F` and gives the same rest for each
fuel `m + F` (`rfl`); finite state lists are closed under both `step` choices, and all their
claim states have one observation (`StepCheck.lean`).
-/

namespace CatsEffectInLean.Proofs.Calibration.SyncStepTwin

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs
open CatsEffectInLean.Props.Calibration
open CatsEffectInLean.Proofs.Calibration.StepCheck

/-- The states of the direct run of program `n`. -/
def reachD (n : Nat) : List S := grow famEnv 20 [Solo.init counterMaskModel (prog n) []]

/-- The direct observation of program `n` (all ten runs end within 30 steps). -/
def oD (n : Nat) : Obs := eraseObs (directObs famEnv (prog n) [] (steps (List.replicate 30 true)))

/-- The fixed twin as the stepped side of program `n`. -/
def steppedFix (n : Nat) : Nat → List SoloChoice → Obs :=
  fun fuel cs => obsOfRest famEnv [] (Rfix n fuel) cs

/-- The v3.7.1 stepped side of program `n`. -/
def stepped371 (n : Nat) : Nat → List SoloChoice → Obs :=
  fun fuel cs => obsOfRest famEnv [] (R371 n fuel) cs

theorem steppedObs_eq (n : Nat) : steppedObs famEnv (prog n) lim [] = stepped371 n := rfl

set_option maxRecDepth 100000 in
theorem fix_big_1 (m : Nat) : Rfix 1 (m + 8) = Rfix 1 8 := by rfl

theorem fix_1 : StepIdentityFor (steppedFix 1) famEnv (prog 1) [] :=
  stepIdentity_of_check' famEnv (prog 1) [] (Rfix 1) 8 (oD 1) (reachD 1)
    (reachOf famEnv (Rfix 1 8) 40) 30 30 (by decide +kernel) fix_big_1
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_2 (m : Nat) : Rfix 2 (m + 8) = Rfix 2 8 := by rfl

theorem fix_2 : StepIdentityFor (steppedFix 2) famEnv (prog 2) [] :=
  stepIdentity_of_check' famEnv (prog 2) [] (Rfix 2) 8 (oD 2) (reachD 2)
    (reachOf famEnv (Rfix 2 8) 40) 30 30 (by decide +kernel) fix_big_2
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_3 (m : Nat) : Rfix 3 (m + 10) = Rfix 3 10 := by rfl

theorem fix_3 : StepIdentityFor (steppedFix 3) famEnv (prog 3) [] :=
  stepIdentity_of_check' famEnv (prog 3) [] (Rfix 3) 10 (oD 3) (reachD 3)
    (reachOf famEnv (Rfix 3 10) 40) 30 30 (by decide +kernel) fix_big_3
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_4 (m : Nat) : Rfix 4 (m + 6) = Rfix 4 6 := by rfl

theorem fix_4 : StepIdentityFor (steppedFix 4) famEnv (prog 4) [] :=
  stepIdentity_of_check' famEnv (prog 4) [] (Rfix 4) 6 (oD 4) (reachD 4)
    (reachOf famEnv (Rfix 4 6) 40) 30 30 (by decide +kernel) fix_big_4
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_5 (m : Nat) : Rfix 5 (m + 10) = Rfix 5 10 := by rfl

theorem fix_5 : StepIdentityFor (steppedFix 5) famEnv (prog 5) [] :=
  stepIdentity_of_check' famEnv (prog 5) [] (Rfix 5) 10 (oD 5) (reachD 5)
    (reachOf famEnv (Rfix 5 10) 40) 30 30 (by decide +kernel) fix_big_5
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_6 (m : Nat) : Rfix 6 (m + 8) = Rfix 6 8 := by rfl

theorem fix_6 : StepIdentityFor (steppedFix 6) famEnv (prog 6) [] :=
  stepIdentity_of_check' famEnv (prog 6) [] (Rfix 6) 8 (oD 6) (reachD 6)
    (reachOf famEnv (Rfix 6 8) 40) 30 30 (by decide +kernel) fix_big_6
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_7 (m : Nat) : Rfix 7 (m + 10) = Rfix 7 10 := by rfl

theorem fix_7 : StepIdentityFor (steppedFix 7) famEnv (prog 7) [] :=
  stepIdentity_of_check' famEnv (prog 7) [] (Rfix 7) 10 (oD 7) (reachD 7)
    (reachOf famEnv (Rfix 7 10) 40) 30 30 (by decide +kernel) fix_big_7
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_8 (m : Nat) : Rfix 8 (m + 12) = Rfix 8 12 := by rfl

theorem fix_8 : StepIdentityFor (steppedFix 8) famEnv (prog 8) [] :=
  stepIdentity_of_check' famEnv (prog 8) [] (Rfix 8) 12 (oD 8) (reachD 8)
    (reachOf famEnv (Rfix 8 12) 40) 30 30 (by decide +kernel) fix_big_8
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_9 (m : Nat) : Rfix 9 (m + 11) = Rfix 9 11 := by rfl

theorem fix_9 : StepIdentityFor (steppedFix 9) famEnv (prog 9) [] :=
  stepIdentity_of_check' famEnv (prog 9) [] (Rfix 9) 11 (oD 9) (reachD 9)
    (reachOf famEnv (Rfix 9 11) 40) 30 30 (by decide +kernel) fix_big_9
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem fix_big_10 (m : Nat) : Rfix 10 (m + 10) = Rfix 10 10 := by rfl

theorem fix_10 : StepIdentityFor (steppedFix 10) famEnv (prog 10) [] :=
  stepIdentity_of_check' famEnv (prog 10) [] (Rfix 10) 10 (oD 10) (reachD 10)
    (reachOf famEnv (Rfix 10 10) 40) 30 30 (by decide +kernel) fix_big_10
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem v371_big_1 (m : Nat) : R371 1 (m + 6) = R371 1 6 := by rfl

theorem v371_fails_1 : ¬ StepIdentityFor (stepped371 1) famEnv (prog 1) [] :=
  not_stepIdentity_of_check' famEnv (prog 1) [] (R371 1) 6 (oD 1)
    (reachOf famEnv (R371 1 6) 20) 30 (by decide +kernel) v371_big_1
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem v371_big_4 (m : Nat) : R371 4 (m + 4) = R371 4 4 := by rfl

theorem v371_fails_4 : ¬ StepIdentityFor (stepped371 4) famEnv (prog 4) [] :=
  not_stepIdentity_of_check' famEnv (prog 4) [] (R371 4) 4 (oD 4)
    (reachOf famEnv (R371 4 4) 20) 30 (by decide +kernel) v371_big_4
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem v371_big_5 (m : Nat) : R371 5 (m + 6) = R371 5 6 := by rfl

theorem v371_fails_5 : ¬ StepIdentityFor (stepped371 5) famEnv (prog 5) [] :=
  not_stepIdentity_of_check' famEnv (prog 5) [] (R371 5) 6 (oD 5)
    (reachOf famEnv (R371 5 6) 20) 30 (by decide +kernel) v371_big_5
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem v371_big_6 (m : Nat) : R371 6 (m + 6) = R371 6 6 := by rfl

theorem v371_fails_6 : ¬ StepIdentityFor (stepped371 6) famEnv (prog 6) [] :=
  not_stepIdentity_of_check' famEnv (prog 6) [] (R371 6) 6 (oD 6)
    (reachOf famEnv (R371 6 6) 20) 30 (by decide +kernel) v371_big_6
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

set_option maxRecDepth 100000 in
theorem v371_big_10 (m : Nat) : R371 10 (m + 2) = R371 10 2 := by rfl

theorem v371_fails_10 : ¬ StepIdentityFor (stepped371 10) famEnv (prog 10) [] :=
  not_stepIdentity_of_check' famEnv (prog 10) [] (R371 10) 2 (oD 10)
    (reachOf famEnv (R371 10 2) 20) 30 (by decide +kernel) v371_big_10
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

/-- The bounded domain of the check. -/
def domain : List Nat := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

/-- The fixed twin (PR #4700) satisfies `StepIdentityFor` on every program of the domain. -/
theorem fixed_twin : ∀ n ∈ domain, StepIdentityFor (steppedFix n) famEnv (prog n) [] := by
  intro n hn
  simp only [domain, List.mem_cons, List.not_mem_nil, or_false] at hn
  rcases hn with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact fix_1
  · exact fix_2
  · exact fix_3
  · exact fix_4
  · exact fix_5
  · exact fix_6
  · exact fix_7
  · exact fix_8
  · exact fix_9
  · exact fix_10

/-- Cats Effect v3.7.1 fails `StepIdentityFor` on programs 1, 4, 5, 6 and 10 of the domain. -/
theorem v371_fails : ∀ n ∈ [1, 4, 5, 6, 10],
    ¬ StepIdentityFor (steppedObs famEnv (prog n) lim []) famEnv (prog n) [] := by
  intro n hn
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hn
  rcases hn with rfl | rfl | rfl | rfl | rfl
  · exact v371_fails_1
  · exact v371_fails_4
  · exact v371_fails_5
  · exact v371_fails_6
  · exact v371_fails_10

end CatsEffectInLean.Proofs.Calibration.SyncStepTwin

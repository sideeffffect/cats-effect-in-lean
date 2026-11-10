import CatsEffectInLean.Props.Calibration.FatalRaise
import CatsEffectInLean.Proofs.Calibration.StepCheck

/-!
# Refutation of `raiseErrorTwin` (CE-0004), and its fixed twin

Counterexample: a fatal `e` (`ErrKind.fatal`, code 0), the program
`IO.raiseError(e).handleErrorWith(_ => IO.pure(1))`, `limit = Int.MaxValue`.

* Direct (`IO` run loop): the `Error` branch calls `onFatalFailure` (`IOFiber.scala:265-269`).
  After 3 `step true` choices the summary is `fatal e`.
* Stepped: `interpret` builds `SyncIO` nodes; the `SyncIO` run loop has no fatal check
  (`SyncIO.scala:257-259`), so the `handleErrorWith` handler runs and the result is `Right(1)`.
  For each `SyncIO` fuel `m + 7` the rest is `IO.pure(1)`; below 7 it is out of fuel. The root
  fiber of `IO.pure(1)` only reaches `Succeeded(1)`. So no stepped run shows `fatal e`.

Fixed twin (decision 39): `SyncIOEnv.fixFatalRaise := true`, a `SyncIO` run loop whose `Error`
branch throws a fatal error out of `unsafeRunSync`, as the `IO` run loop does. On the bounded
domain `twinDomain` (fatal, non-fatal and interrupted errors) the twin satisfies the statement
(`fixed_twin`). Cats Effect v3.7.1 satisfies it on the non-fatal members of the domain
(`v371_nonFatal`) and fails it on the fatal ones (`v371_fatal_fails`), so the refutation shows
exactly the `Error` branch difference.
-/

namespace CatsEffectInLean.Proofs.Calibration.FatalRaise

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs
open CatsEffectInLean.Props.Calibration
open CatsEffectInLean.Proofs.Calibration.StepCheck

/-- The `SyncIO` part of v3.7.1 for error `e`. -/
def R (e : Err) (fuel : Nat) : Except Summary (IO × Heap) :=
  SyncStep.steppedRest counterMaskModel handlerEnv fuel (raiseHandled e) maxIntLimit []

/-- The `SyncIO` closure meaning of the fixed twin. -/
def fixSenv : SyncIOEnv CounterMask :=
  { SyncStep.senv counterMaskModel handlerEnv with fixFatalRaise := true }

/-- The `SyncIO` part of the fixed twin for error `e`. -/
def Rfix (e : Err) (fuel : Nat) : Except Summary (IO × Heap) :=
  SyncStep.steppedRestWith counterMaskModel (SyncStep.syncStep counterMaskModel handlerEnv)
    fixSenv fuel (raiseHandled e) maxIntLimit []

/-- The heap that the `SyncIO` part leaves (one handle id used by the `prefixExec` fiber). -/
def h1 : Heap := { handles := 1 }

/-- The errors of the bounded domain: two fatal, one non-fatal, one interrupted. -/
def eF0 : Err := { code := 0, kind := .fatal }
def eF5 : Err := { code := 5, kind := .fatal }
def eN0 : Err := { code := 0, kind := .nonFatal }
def eI0 : Err := { code := 0, kind := .interrupted }

/-- The bounded domain of the fixed-twin check. -/
def twinDomain : List Err := [eF0, eF5, eN0, eI0]

/-! ## Cats Effect v3.7.1 -/

theorem R_big (e : Err) (he : e = eF0 ∨ e = eF5 ∨ e = eN0 ∨ e = eI0) (m : Nat) :
    R e (m + 7) = .ok (.pure (.nat 1), h1) := by
  rcases he with rfl | rfl | rfl | rfl <;> rfl

theorem R_small (e : Err) (he : e = eF0 ∨ e = eF5 ∨ e = eN0 ∨ e = eI0) :
    ∀ k, k < 7 → restClaims (R e k) = false := by
  rcases he with rfl | rfl | rfl | rfl <;> decide +kernel

/-- The stepped states of v3.7.1 (the root fiber of `IO.pure(1)`). -/
def reachPure : List S := grow handlerEnv 4 [rootOn counterMaskModel (.pure (.nat 1)) h1]

/-- The direct states for error `e`. -/
def reachD (e : Err) : List S := grow handlerEnv 6 [Solo.init counterMaskModel (raiseHandled e) []]

/-- v3.7.1 fails the statement for a fatal error. -/
theorem v371_fatal_fails (e : Err) (he : e = eF0 ∨ e = eF5) :
    ¬ StepIdentityFor (steppedObs handlerEnv (raiseHandled e) maxIntLimit [])
      handlerEnv (raiseHandled e) [] := by
  have hb := R_big e (by rcases he with rfl | rfl <;> simp)
  have hs := R_small e (by rcases he with rfl | rfl <;> simp)
  rcases he with rfl | rfl
  · exact not_stepIdentity_of_check handlerEnv _ [] (R eF0) 7 _ h1 (.fatal eF0, [], [])
      reachPure 3 hs hb (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel)
  · exact not_stepIdentity_of_check handlerEnv _ [] (R eF5) 7 _ h1 (.fatal eF5, [], [])
      reachPure 3 hs hb (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel)

/-- CE-0004: the `IO` and `SyncIO` run loops disagree on `raiseError(fatal)`. -/
theorem raiseErrorTwin_refuted : ¬ raiseErrorTwin :=
  fun h => v371_fatal_fails eF0 (.inl rfl) (h eF0)

/-- v3.7.1 satisfies the statement for the non-fatal members of the domain (ordinary inputs). -/
theorem v371_nonFatal (e : Err) (he : e = eN0 ∨ e = eI0) :
    StepIdentityFor (steppedObs handlerEnv (raiseHandled e) maxIntLimit [])
      handlerEnv (raiseHandled e) [] := by
  have hb := R_big e (by rcases he with rfl | rfl <;> simp)
  have hs := R_small e (by rcases he with rfl | rfl <;> simp)
  rcases he with rfl | rfl
  · exact stepIdentity_of_check handlerEnv _ [] (R eN0) 7 _ h1
      (.done (.succeeded (.nat 1)), [], []) (reachD eN0) reachPure 5 3 hs hb
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
  · exact stepIdentity_of_check handlerEnv _ [] (R eI0) 7 _ h1
      (.done (.succeeded (.nat 1)), [], []) (reachD eI0) reachPure 5 3 hs hb
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

/-! ## The fixed twin -/

theorem Rfix_big_fatal (e : Err) (he : e = eF0 ∨ e = eF5) (m : Nat) :
    Rfix e (m + 4) = .ok (.error e, h1) := by
  rcases he with rfl | rfl <;> rfl

theorem Rfix_big_nonFatal (e : Err) (he : e = eN0 ∨ e = eI0) (m : Nat) :
    Rfix e (m + 7) = .ok (.pure (.nat 1), h1) := by
  rcases he with rfl | rfl <;> rfl

/-- The stepped states of the twin for a fatal `e` (the root fiber of `IO.raiseError(e)`). -/
def reachErr (e : Err) : List S := grow handlerEnv 4 [rootOn counterMaskModel (.error e) h1]

/-- The fixed twin satisfies the statement on the whole bounded domain. -/
theorem fixed_twin : ∀ e ∈ twinDomain,
    StepIdentityFor (fun fuel cs => obsOfRest handlerEnv [] (Rfix e fuel) cs)
      handlerEnv (raiseHandled e) [] := by
  intro e he
  simp only [twinDomain, List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl | rfl | rfl | rfl
  · exact stepIdentity_of_check handlerEnv _ [] (Rfix eF0) 4 _ h1 (.fatal eF0, [], [])
      (reachD eF0) (reachErr eF0) 3 2 (by decide +kernel) (Rfix_big_fatal _ (.inl rfl))
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
  · exact stepIdentity_of_check handlerEnv _ [] (Rfix eF5) 4 _ h1 (.fatal eF5, [], [])
      (reachD eF5) (reachErr eF5) 3 2 (by decide +kernel) (Rfix_big_fatal _ (.inr rfl))
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
  · exact stepIdentity_of_check handlerEnv _ [] (Rfix eN0) 7 _ h1
      (.done (.succeeded (.nat 1)), [], []) (reachD eN0) reachPure 5 3 (by decide +kernel)
      (Rfix_big_nonFatal _ (.inl rfl))
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
  · exact stepIdentity_of_check handlerEnv _ [] (Rfix eI0) 7 _ h1
      (.done (.succeeded (.nat 1)), [], []) (reachD eI0) reachPure 5 3 (by decide +kernel)
      (Rfix_big_nonFatal _ (.inr rfl))
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)

/-- The program is a well-formed plain `IO` program (no handles; user code ignores its
argument and view and returns closed programs). -/
theorem raiseHandled_wellFormed (e : Err) : WellFormedIO handlerEnv (raiseHandled e) := by
  refine ⟨rfl, fun id _ arg v => ⟨fun w _ => rfl, ?_⟩, ?_⟩
  · by_cases h : id = 0 <;>
      simp [handlerEnv, h, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub, Val.handles]
  · refine WF.pollOpaque_of_const handlerEnv (fun id => handlerEnv.call id .unit []) [0]
      { out := .ret .unit } (fun _ _ _ _ => rfl) (by decide +kernel) ?_ ?_ (fun _ _ => rfl)
    · intro id _ h
      simp only [List.mem_cons, List.not_mem_nil, or_false] at h
      simp [handlerEnv, h]
    · intro σ _ k hk
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
      subst hk
      rfl

end CatsEffectInLean.Proofs.Calibration.FatalRaise

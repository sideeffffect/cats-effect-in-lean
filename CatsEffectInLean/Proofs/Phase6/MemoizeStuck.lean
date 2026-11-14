import CatsEffectInLean.Props.Phase6.Memoize

/-!
# Refutation of `memoizeNoStuckGet` (CE-0030)

Witness: `fa = IO.canceled` (`fa` cancels itself), no user code, and one preemption.

1. Fiber A runs `get`: `Unevaluated`, so it starts the evaluation fiber `go` and waits in
   `poll(fiber.join …)`.
2. Fiber B runs `get`: `state.get` sees `Evaluating`. The schedule preempts B before
   `state.flatModifyFull` (choice 35; 36 and 37 also work).
3. `go` runs `IO.canceled`: its `guaranteeCase` finalizer writes
   `Finished(Right(productR(canceled)(never)))`. A sees `Canceled` and ends `Canceled`.
4. B goes on: `flatModifyFull` sees `Finished` and returns `fromEither(result).flatten` =
   `canceled *> never` **inside the `uncancelable` of `flatModifyFull`, without `poll`**
   (`K/GenConcurrent.scala:91-92`, `K/Ref.scala:140-141`). `canceled` does nothing in a masked
   region, so B waits in `never` forever, and nothing can cancel it. The root waits for B:
   the run is blocked, with the memo `Finished`.

A `get` that sees `Finished` in `state.get` (`K/GenConcurrent.scala:108`) runs the same effect
without the mask and ends `Canceled`, as A did.

Fixed-twin check (decision 39): variant 1 of the mirror (`poll(fromEither(result).flatten)`, not
Cats Effect code) completes on the witness schedule (`fixed_wit`). On all schedules with one
preemption at a position below 120: `Proofs/Phase6/MemoizeFixed.lean` (`lean_lib TwinChecks`,
decision 45). More schedules: `test/Phase6/MemoizeSmoke.lean`.
-/

namespace CatsEffectInLean.Proofs.Phase6

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase6.Memoize

namespace MemoizeStuckWitness

/-- No user code: every user function throws (the witness calls none). -/
def userR : UserResult := { out := .throw { code := 0 } }

def u : UserEnv := { call := fun _ _ _ => userR }

def fa : IO := .canceled

/-- One preemption after 35 micro-steps. -/
def cs : List PChoice := List.replicate 35 (.pick 0) ++ [.preempt]

theorem wit_blocked : (run fa u 100 cs (twoGets 0)).halt = some .blocked := by decide +kernel

theorem wit_finished : memoFinished (run fa u 100 cs (twoGets 0)) 0 = true := by decide +kernel

/-! ### The witness is well-formed -/

theorem callV_even (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (env fa u).callV id a v = userR := by
  have h1 : isLibId id = false := by simp [isLibId, hid]
  show CatsEffectInLean.Props.Phase6.Memoize.dispatch fa u id a v = _
  simp [CatsEffectInLean.Props.Phase6.Memoize.dispatch, CatsEffectInLean.Model.Memoize.MLam.ofId?,
    bracketLeaf?, Bracket.BLam.ofId?_even hid, timeoutOf?, TLam.ofId?, h1, u]

theorem calls (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    WF.CallOK isLib [] (env fa u) id arg v := by
  refine ⟨fun w _ => ?_, ?_⟩
  · rw [callV_even id hid, callV_even id hid]
  · rw [callV_even id hid]; simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem env_opaque : WF.PollOpaque (env fa u) := by
  refine WF.pollOpaque_of_const (env fa u) (fun _ => userR) [] userR
    (fun id arg v hid => callV_even id hid arg v) (by decide) (fun _ _ _ => rfl) ?_ (fun _ _ => rfl)
  intro σ _ k hk
  simp at hk

theorem fa_wf : WellFormed isLib [] (env fa u) fa :=
  ⟨by decide, fun id hid arg v => calls id hid arg v, env_opaque⟩

/-! ### Fixed-twin check (decision 39) -/

/-- The fixed twin completes on the witness schedule: both `get`s end `Canceled`. -/
theorem fixed_wit :
    (run fa u 100 cs (twoGets 1)).halt = some (.done (.succeeded (.pair .ocCanceled .ocCanceled))) := by
  decide +kernel

end MemoizeStuckWitness

open MemoizeStuckWitness in
theorem memoizeNoStuckGet_refuted : ¬ memoizeNoStuckGet := fun h => by
  have := h u fa fa_wf 100 cs wit_blocked
  rw [wit_finished] at this
  cases this

end CatsEffectInLean.Proofs.Phase6

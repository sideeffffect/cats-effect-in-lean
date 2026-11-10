import CatsEffectInLean.Props.Phase6.Resource
import CatsEffectInLean.Model.Outcomes

/-!
# Refutation of `bothReleasesBoth` (CE-0020)

Witness (the program of `reproducers/CE-0020/Repro.scala`):

* side A: `Resource.make(IO.unit.map(_ => emit 1))(_ => IO.delay(emit 101) *> IO.raiseError(boom))`;
* side B: `Resource.make(IO.unit.map(_ => emit 2))(_ => IO.delay(emit 102) *> IO.unit)`;
* `Resource.both(A, B).use(_ => IO.unit)`, at the root (no parent).

Schedule `sched`: FIFO for 89 choices, then `pick 1`. Both sides are acquired. In the release
of `makeCase` (`Resource.scala:302-305`), `F.both` starts one fiber per finalizer chain. The
chain of A raises `boom`; the root fiber (the `F.both` body) then runs before the fiber of B's
chain, takes the `Errored` branch and cancels that fiber (`GenSpawn.scala:476-498`). That fiber
has not started, so it ends `Canceled` and runs nothing: `102` is never emitted. The root ends
`Errored(boom)` with trace `[101, 2, 1]` (newest first). So `count 102 = 0 ≠ 1 = count 2`.

Proof: one run (`runObsP`, `decide +kernel`). The hypotheses hold: the markers and user code
(`callV_even`, `markersOnly`), the well-formed program (`prog_wf`: start program by
`decide +kernel`, user code by cases, poll opacity by `WF.pollOpaque_of_const`).

Fixed twin (decision 39): `ResourceUse.fixedBothRes` (`F.both(thisFin(ec).attempt,
thatFin(ec).attempt)`, then re-raise; not Cats Effect code) has no run with a skipped release
on 600 single-deviation schedules and 1,500 random schedules with preemption; v3.7.1 has
(`test/Phase6/ResourceSmoke.lean`). The reproducer shows the same on real Cats Effect.
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource

def boom : Err := { code := 5 }

def userR : Nat → UserResult
  | 1 => { effects := [.emit (.nat 1)], out := .ret .unit }
  | 2 => { effects := [.emit (.nat 2)], out := .ret .unit }
  | 3 => { effects := [.emit (.nat 101)], out := .ret .unit }
  | 4 => { effects := [.emit (.nat 102)], out := .ret .unit }
  | 5 => { out := .prog (.error boom) }
  | 6 => { out := .prog (.pure .unit) }
  | 7 => { out := .prog (.pure .unit) }
  | _ => { out := .throw { code := 0 } }

def user : UserEnv where
  call k _ _ := userR k

def renv : REnv where
  user := user
  bind := fun _ _ => .error { code := 0 }
  acquire := fun k => if k == 0 then .map (.pure .unit) (uid 1) else .map (.pure .unit) (uid 2)
  release := fun k _ => if k == 0 then .ok (.flatMap (.delay (uid 3)) (uid 5)) else .ok (.flatMap (.delay (uid 4)) (uid 6))

def U : UEnv where
  r := renv
  resOf := fun c => match c with
    | .nat 0 => some (Res.make 0 0)
    | .nat 1 => some (Res.make 1 1)
    | _ => none

def prog : IO := useOf U (2 * 7) (bothRes (.nat 0) (.nat 1))

/-- The schedule: FIFO (`pick 0`) for 89 choices, then `pick 1`. At that point the root fiber
(the `F.both` of the release, after the left finalizer chain errored) runs before the fiber of
the right finalizer chain, cancels it, and the right release never starts. -/
def sched : List PChoice := List.replicate 89 (PChoice.pick 0) ++ [.pick 1]

/-- The run: outcome `Errored(boom)`, trace (newest first) `[101, 2, 1]`: both acquires (`1`,
`2`) and the left release (`101`) ran; the right release (`102`) did not. -/
theorem run_witness :
    (runObsP {} counterMaskModel U.toEnv 6000 sched prog).map (fun o => (o.summary, o.out)) =
      some (.done (.errored boom), [.nat 101, .nat 2, .nat 1]) := by
  decide +kernel

/-! ### The hypotheses hold -/

theorem callV_even (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    U.toEnv.callV id a v = userR (id / 2) := by
  have h1 : Bracket.BLam.ofId? id = none := Bracket.BLam.ofId?_even hid
  have h2 : ULam.ofId? id = none := by simp [ULam.ofId?, Codec.isLibId, hid]
  have h3 : Race.ofId? id = none := by simp [Race.ofId?, Codec.isLibId, hid]
  show resDisp U U.userCall id a v = _
  simp [resDisp, uDisp, h1, h2, h3, Codec.isLibId, hid, UEnv.userCall, U, renv, user]

theorem markedA : MarkedMake U (.nat 0) (.pure .unit) 1 3 (.nat 1) (.nat 101) :=
  ⟨0, 0, rfl, rfl, fun a v => by rw [callV_even 2 rfl]; rfl, fun a v => by rw [callV_even 6 rfl]; rfl,
    fun _ => ⟨5, rfl⟩, rfl, rfl⟩

theorem markedB : MarkedMake U (.nat 1) (.pure .unit) 2 4 (.nat 2) (.nat 102) :=
  ⟨1, 1, rfl, rfl, fun a v => by rw [callV_even 4 rfl]; rfl, fun a v => by rw [callV_even 8 rfl]; rfl,
    fun _ => ⟨6, rfl⟩, rfl, rfl⟩

theorem markersOnly : UserMarkersOnly U.toEnv [2 * 1, 2 * 2, 2 * 3, 2 * 4] [.nat 1, .nat 2, .nat 101, .nat 102] := by
  refine ⟨fun id hid hm a v x hx => ?_, fun id hid a v p hp m hm => ?_⟩
  · rw [callV_even id hid]
    have hk : id = 2 * (id / 2) := by omega
    match h : id / 2, hm with
    | 0, _ | 5, _ | 6, _ | 7, _ => simp [userR]
    | 1, hm | 2, hm | 3, hm | 4, hm => rw [h] at hk; subst hk; simp at hm
    | n + 8, _ => simp [userR]
  · rw [callV_even id hid] at hp
    match h : id / 2, hp with
    | 5, hp | 6, hp | 7, hp =>
      simp only [userR, UserOut.prog.injEq] at hp; subst hp
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
      rcases hm with rfl | rfl | rfl | rfl <;> rfl
    | 0, hp | 1, hp | 2, hp | 3, hp | 4, hp => simp [userR] at hp
    | n + 8, hp => simp [userR] at hp

theorem userR_ok (n : Nat) (R : Handle → Prop) (v : View) :
    WF.ResultOK ResourceUse.isLib R v (userR n) := by
  match n with
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 =>
    simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub, Val.handles]
  | _ + 8 => simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem calls (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    WF.CallOK ResourceUse.isLib [] U.toEnv id arg v := by
  refine ⟨fun w _ => ?_, ?_⟩
  · rw [callV_even id hid, callV_even id hid]
  · rw [callV_even id hid]; exact userR_ok _ _ _

theorem env_opaque : WF.PollOpaque U.toEnv := by
  refine WF.pollOpaque_of_const U.toEnv (fun id => userR (id / 2)) [0, 2, 4, 6, 8, 10, 12, 14]
    { out := .throw { code := 0 } } (fun id arg v hid => callV_even id hid arg v) (by decide +kernel)
    ?_ ?_ (fun _ _ => rfl)
  · intro id hid hk
    simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
    obtain h | h : id / 2 ≤ 7 ∨ 8 ≤ id / 2 := by omega
    · omega
    · obtain ⟨k, hk⟩ := Nat.exists_eq_add_of_le h
      simp only [hk, show 8 + k = k + 8 by omega]; rfl
  · intro σ _ k hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    rcases hk with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> rfl

theorem prog_wf : WellFormed ResourceUse.isLib [] U.toEnv (withParent false prog) :=
  ⟨by decide +kernel, fun id hid arg v => calls id hid arg v, env_opaque⟩

end CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

namespace CatsEffectInLean.Proofs.Phase6

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Resource
open ResourceBothWitness in
theorem bothReleasesBoth_refuted : ¬ bothReleasesBoth := by
  intro h
  have hrun := run_witness
  rcases hr : runObsP {} counterMaskModel U.toEnv 6000 sched prog with _ | o
  · rw [hr] at hrun; cases hrun
  · rw [hr] at hrun
    simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at hrun
    have hc := h U (.nat 0) (.nat 1) (.pure .unit) (.pure .unit) 1 2 3 4 14 (.nat 1) (.nat 2) (.nat 101) (.nat 102)
      false markedA markedB (by decide +kernel) markersOnly (by simp) prog_wf o ⟨6000, sched, hr⟩ ⟨_, hrun.1⟩
    rw [hrun.2] at hc
    exact absurd hc.2 (by decide)

end CatsEffectInLean.Proofs.Phase6

import CatsEffectInLean.Props.Phase6.Bracket
import CatsEffectInLean.Model.EnumP

/-!
# Refutation of `bracketFullIsKernelDefault` (CE-0005)

Witness (case A of `reproducers/CE-0005/Repro.scala`):

* `acquire = _ => IO.canceled`: a cancel request inside the `bracketFull` mask (the same
  state as a parent fiber that cancels during acquire, case B of the reproducer).
* `use = _ => throw E5`: the `use` function throws when it is called (the case that the kernel
  comment at `K/MonadCancel.scala:452-453` talks about).
* `release = (_, _) => IO.unit`.

`IO.bracketFull` (`IO.scala:1829`) calls `use(a)` inside `IO.defer`, before `poll` unmasks.
So the throw comes first: `release(a, Errored(E5))` runs (`onError`), and the error leaves the
fiber: outcome `Errored(E5)`. The kernel body (`K/MonadCancel.scala:454`) unmasks first
(`poll(unit >> use(a))`); the run loop sees the cancel before `use(a)` is called: outcome
`Canceled`, `release(a, Canceled)`.

Proof: exact outcome sets under `EqvP` (`outcomesPList`, `decide +kernel`): left
`{Errored(E5)}`, right `{Canceled}`. One fiber, so preemption only splits the run.

Fixed-twin check (decision 39): `fixedBracketFullIO` (`poll(IO.defer(use(a)))`, not Cats Effect
code) agrees with the kernel body on the witness and on 7 more programs (`fixed_*`); v3.7.1
differs from the kernel body only on the witness (`old_*`).
-/

namespace CatsEffectInLean.Proofs.Phase6

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Props.Phase6.Bracket

namespace BracketFullWitness

/-- User code; it ignores its argument and the view. Even ids `2 * n`:
0 `_ => IO.canceled`, 1 `_ => throw E5`, 2 `_ => IO.unit`, 3 `_ => IO.unit` (acquire),
4 `_ => IO.canceled` (use), 5 `_ => IO.raiseError(E6)` (use). -/
def userR : Nat → UserResult
  | 0 => { out := .prog .canceled }
  | 1 => { out := .throw { code := 5 } }
  | 2 => { out := .prog (.pure .unit) }
  | 3 => { out := .prog (.pure .unit) }
  | 4 => { out := .prog .canceled }
  | 5 => { out := .prog (.error { code := 6 }) }
  | _ => { out := .throw { code := 0 } }

def user (id : Nat) (_ : Val) (_ : View) : UserResult := userR (id / 2)

/-- No external sources are used. -/
def ioOf : Val → IO := fun _ => .pure .unit

def disp (id : Nat) (a : Val) (v : View) : UserResult :=
  match BLam.ofId? id with
  | some l => call user ioOf l a v
  | none => user id a v

/-- The witness environment: the mirror on its ids, `user` on all other ids. -/
def env : UserEnv where
  call id a refs := disp id a { refs }
  callV := disp

theorem env_lib : LibEnv env ioOf := libEnv_of_dispatch env ioOf user (fun _ _ _ => rfl)

/-- `IO.bracketFull(acquire)(use)(release)` of the witness. -/
def lhs : IO := bracketFullIO 0 2 4
/-- The kernel body. -/
def rhs : IO := defaultBracketFullIO 0 2 4

def erroredObs : Obs := { summary := .done (.errored { code := 5 }), out := [], refs := [], reports := [] }
def canceledObs : Obs := { summary := .done .canceled, out := [], refs := [], reports := [] }

theorem lhs_outcomesP : outcomesPList {} counterMaskModel env 200 lhs = some [erroredObs] := by
  decide +kernel

theorem rhs_outcomesP : outcomesPList {} counterMaskModel env 200 rhs = some [canceledObs] := by
  decide +kernel

theorem not_eqvP : ¬ EqvP {} counterMaskModel env lhs rhs :=
  not_eqvP_of_checkNotEqvP {} counterMaskModel env (bound := 200) (by decide +kernel)

/-! ### The witness is well-formed -/

theorem callV_even (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    env.callV id a v = userR (id / 2) := by
  show disp id a v = _
  simp [disp, BLam.ofId?_even hid, user]

theorem userR_ok (n : Nat) (R : Handle → Prop) (v : View) :
    WF.ResultOK isLib R v (userR n) := by
  match n with
  | 0 | 1 | 2 | 3 | 4 | 5 => simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub, Val.handles]
  | _ + 6 => simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem calls (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) : WF.CallOK isLib [] env id arg v := by
  refine ⟨fun w _ => ?_, ?_⟩
  · rw [callV_even id hid, callV_even id hid]
  · rw [callV_even id hid]; exact userR_ok _ _ _

theorem env_opaque : WF.PollOpaque env := by
  refine WF.pollOpaque_of_const env (fun id => userR (id / 2)) [0, 2, 4, 6, 8, 10]
    { out := .throw { code := 0 } } (fun id arg v hid => callV_even id hid arg v) (by decide +kernel)
    ?_ ?_ (fun _ _ => rfl)
  · intro id hid hk
    simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
    obtain h | h : id / 2 ≤ 5 ∨ 6 ≤ id / 2 := by omega
    · omega
    · obtain ⟨k, hk⟩ := Nat.exists_eq_add_of_le h
      simp only [hk, show 6 + k = k + 6 by omega]; rfl
  · intro σ _ k hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    rcases hk with rfl | rfl | rfl | rfl | rfl | rfl <;> rfl

theorem wellFormed (p : IO) (hp : WF.progOK isLib (fun h => ([] : List Handle).contains h) p = true) :
    WellFormed isLib [] env p :=
  ⟨hp, fun id hid arg v => calls id hid arg v, env_opaque⟩

theorem lhs_wf : WellFormed isLib [] env lhs := wellFormed _ (by decide +kernel)
theorem rhs_wf : WellFormed isLib [] env rhs := wellFormed _ (by decide +kernel)

end BracketFullWitness

open BracketFullWitness in
theorem bracketFullIsKernelDefault_refuted : ¬ bracketFullIsKernelDefault := fun h =>
  not_eqvP (h env ioOf 0 2 4 env_lib lhs_wf rhs_wf)

end CatsEffectInLean.Proofs.Phase6

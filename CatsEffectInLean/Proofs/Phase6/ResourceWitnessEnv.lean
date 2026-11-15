import CatsEffectInLean.Props.Phase6.Resource
import CatsEffectInLean.Model.Outcomes

/-!
# The witness environment of the `Resource` statements (track Res, decisions 53, 56)

One small user environment for the satisfiability witnesses (`Proofs/Phase6/ResourceWitness.lean`)
and the CE-0020 refutation (`Proofs/Phase6/ResourceBoth.lean`). All user functions are constant.

* User code (`REnv` index `k` = program id `2 * k`): 5 `_ => IO.raiseError(boom)`, 6 `_ => IO.unit`
  (release rest `q`), 7 `_ => IO.unit` (the use function `f`, program id 14).
* Harness codes are token names (`code i` decodes to a closure value that holds `Ref` 0):
  acquire/release of side A `code 0`, `code 1`; of side B `code 2`, `code 3`; the `flatMap`
  function `code 4`; resource codes `cA`, `cB` hold `Ref` 0 themselves.
* `failA`: the rest of A's release raises `boom` (CE-0020); `two`: side B exists; `withBind`:
  the harness `flatMap` function exists.

The lemmas give the hypotheses that do not depend on the statement.
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Props.Phase6.HarnessPrivacy

def boom : Err := { code := 5 }

/-- `REnv`-level user code (index `k` = program id `2 * k`). -/
def userR : Nat → UserResult
  | 5 => { out := .prog (.error boom) }
  | 6 => { out := .prog (.pure .unit) }
  | 7 => { out := .prog (.pure .unit) }
  | _ => { out := .throw { code := 0 } }

def user : UserEnv where
  call k _ _ := userR k

/-- A harness code: a number whose closure value holds the token `Ref` 0. -/
def code (i : Nat) : Nat := 2 * valToNat (cloVal hns 60 [.ref logCell, .nat i])

def cA : Val := .pair (.ref logCell) (.nat 20)
def cB : Val := .pair (.ref logCell) (.nat 21)

def renv (failA two withBind : Bool) : REnv where
  user := user
  bind := fun k _ => if withBind && k == code 4 then .ok (Res.make (code 2) (code 3)) else .error { code := 0 }
  acquire := fun k =>
    if k == code 0 then .flatMap (.pure .unit) (HLam.markA logCell tagA).fn
    else if two && k == code 2 then .flatMap (.pure .unit) (HLam.markA logCell tagB).fn
    else .pure .unit
  release := fun k _ =>
    if k == code 1 then .ok (.flatMap (.delay (HLam.markT logCell tagRA).fn) (uid (if failA then 5 else 6)))
    else if two && k == code 3 then .ok (.flatMap (.delay (HLam.markT logCell tagRB).fn) (uid 6))
    else .ok (.pure .unit)

def W (failA two withBind : Bool) : UEnv where
  r := renv failA two withBind
  resOf := fun c => if c == cA then some (Res.make (code 0) (code 1))
    else if two && c == cB then some (Res.make (code 2) (code 3)) else none

theorem toEnv_callV_even (failA two withBind : Bool) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (W failA two withBind).toEnv.callV id a v = userR (id / 2) := by
  have h1 : Bracket.BLam.ofId? id = none := Bracket.BLam.ofId?_even hid
  have h2 : ULam.ofId? id = none := by simp [ULam.ofId?, Codec.isLibId, hid]
  have h3 : Race.ofId? id = none := by simp [Race.ofId?, Codec.isLibId, hid]
  show resDisp _ _ id a v = _
  simp [resDisp, uDisp, h1, h2, h3, Codec.isLibId, hid, UEnv.userCall, W, renv, user]

theorem callV_even (failA two withBind : Bool) (body : IO) (id : Nat) (hid : id % 2 = 0) (a : Val)
    (v : View) : (envH (W failA two withBind) body).callV id a v = userR (id / 2) := by
  have h0 : HLam.ofId? id = none := by simp [HLam.ofId?, Codec.isLibId, hid]
  show (match HLam.ofId? id with | some l => l.call body a v | none => _) = _
  rw [h0]; exact toEnv_callV_even _ _ _ id hid a v

/-- No user result names the token. -/
theorem userR_free (n : Nat) : tokFreeR toks (userR n) = true := by
  match n with
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 => decide +kernel
  | _ + 8 => rfl

theorem userPrivate (failA two withBind : Bool) : UserPrivate (W failA two withBind).toEnv toks :=
  fun id hid a v => by rw [toEnv_callV_even _ _ _ id hid]; exact userR_free _

theorem userR_ok (n : Nat) (R : Handle → Prop) (v : View) : WF.ResultOK libH R v (userR n) := by
  match n with
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 =>
    simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub, Val.handles]
  | _ + 8 => simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem calls (failA two withBind : Bool) (body : IO) (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    WF.CallOK libH [] (envH (W failA two withBind) body) id arg v := by
  refine ⟨fun w _ => ?_, ?_⟩
  · rw [callV_even _ _ _ _ id hid, callV_even _ _ _ _ id hid]
  · rw [callV_even _ _ _ _ id hid]; exact userR_ok _ _ _

theorem env_opaque (failA two withBind : Bool) (body : IO) : WF.PollOpaque (envH (W failA two withBind) body) := by
  refine WF.pollOpaque_of_const _ (fun id => userR (id / 2)) [10, 12, 14]
    { out := .throw { code := 0 } } (fun id arg v hid => callV_even _ _ _ _ id hid arg v) (by decide +kernel)
    ?_ ?_ (fun _ _ => rfl)
  · intro id hid hk
    simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
    obtain h | h : id / 2 ≤ 7 ∨ 8 ≤ id / 2 := by omega
    · have : id / 2 ≤ 4 := by omega
      match hn : id / 2, this with
      | 0, _ | 1, _ | 2, _ | 3, _ | 4, _ => rfl
    · obtain ⟨k, hk⟩ := Nat.exists_eq_add_of_le h
      simp only [hk, show 8 + k = k + 8 by omega]; rfl
  · intro σ _ k hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    rcases hk with rfl | rfl | rfl <;> rfl

theorem wellFormed (failA two withBind : Bool) (body : IO) :
    WellFormed libH [] (envH (W failA two withBind) body) harness :=
  ⟨by decide +kernel, fun id hid arg v => calls _ _ _ _ id hid arg v, env_opaque _ _ _ _⟩

/-- The harness codes are token names; `IO.unit` (the `a0` of the witnesses) is token-free. -/
theorem codes_named : tokFreeV toks (.nat (code 0)) = false ∧ tokFreeV toks (.nat (code 1)) = false ∧
    tokFreeV toks (.nat (code 2)) = false ∧ tokFreeV toks (.nat (code 3)) = false ∧
    tokFreeV toks (.nat (code 4)) = false ∧ tokFreeV toks cA = false ∧ tokFreeV toks cB = false ∧
    tokFreeIO toks (.pure .unit) = true := by
  decide +kernel

theorem markedA (failA two withBind : Bool) :
    MarkedMake (W failA two withBind) cA (code 0) (code 1) (.pure .unit) tagA tagRA := by
  obtain ⟨h0, h1, -, -, -, hA, -, hu⟩ := codes_named
  refine ⟨by simp [W], by simp [W, renv], fun _ => ⟨if failA then 5 else 6, by simp [W, renv]⟩,
    hu, hA, h0, h1⟩

theorem markedB (failA withBind : Bool) :
    MarkedMake (W failA true withBind) cB (code 2) (code 3) (.pure .unit) tagB tagRB := by
  obtain ⟨-, -, h2, h3, -, -, hB, hu⟩ := codes_named
  have hc02 : code 2 ≠ code 0 := by decide +kernel
  have hc13 : code 3 ≠ code 1 := by decide +kernel
  have hBA : cB ≠ cA := by decide
  refine ⟨by simp [W, hBA], by simp [W, renv, hc02], fun _ => ⟨6, by simp [W, renv, hc13]⟩, hu, hB, h2, h3⟩

end CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

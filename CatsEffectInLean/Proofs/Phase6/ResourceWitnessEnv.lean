import CatsEffectInLean.Props.Phase6.Resource
import CatsEffectInLean.Model.Outcomes

/-!
# The witness environment of the `Resource` statements (track Res, decision 53)

One small user environment for the satisfiability witnesses (`Proofs/Phase6/ResourceWitness.lean`)
and the CE-0020 refutation (`Proofs/Phase6/ResourceBoth.lean`). All user functions are constant.

* Markers: acquire markers emit `1001` (A), `1002` (B); release markers emit `1101` (RA),
  `1102` (RB). These values are not harness names.
* `REnv` indices: 1, 2 acquire `map` markers; 3, 4 release `delay` markers; 5 `_ => raise boom`;
  6 `_ => IO.unit`; 7 `_ => IO.unit` (the use function `f`, program id 14).
* Codes: acquire/release code 0 = side A, 1 = side B; `Bind` code 9 = `_ => make B`; resource
  codes `nat 20` (A), `nat 21` (B, only if `two`).
* `failA`: the rest of A's release raises `boom` (CE-0020); otherwise `IO.unit`.

The lemmas show the hypotheses that do not depend on the statement: the even ids run `userR`,
no user result mentions any harness name, and every program is `WellFormed` if its start term is.
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Props.Phase6.HarnessNames

def boom : Err := { code := 5 }

/-- `REnv`-level user code (index `k` = program id `2 * k`). -/
def userR : Nat → UserResult
  | 1 => { effects := [.emit (.nat 1001)], out := .ret .unit }
  | 2 => { effects := [.emit (.nat 1002)], out := .ret .unit }
  | 3 => { effects := [.emit (.nat 1101)], out := .ret .unit }
  | 4 => { effects := [.emit (.nat 1102)], out := .ret .unit }
  | 5 => { out := .prog (.error boom) }
  | 6 => { out := .prog (.pure .unit) }
  | 7 => { out := .prog (.pure .unit) }
  | _ => { out := .throw { code := 0 } }

def user : UserEnv where
  call k _ _ := userR k

def renv (failA withBind : Bool) : REnv where
  user := user
  bind := fun k _ => if withBind && k == 9 then .ok (Res.make 1 1) else .error { code := 0 }
  acquire := fun k => if k == 0 then .map (.pure .unit) (uid 1)
    else if k == 1 then .map (.pure .unit) (uid 2) else .pure .unit
  release := fun k _ =>
    if k == 0 then .ok (.flatMap (.delay (uid 3)) (uid (if failA then 5 else 6)))
    else if k == 1 then .ok (.flatMap (.delay (uid 4)) (uid 6)) else .ok (.pure .unit)

def W (failA two withBind : Bool) : UEnv where
  r := renv failA withBind
  resOf := fun c => match c with
    | .nat 20 => some (Res.make 0 0)
    | .nat 21 => if two then some (Res.make 1 1) else none
    | _ => none

def A : Val := .nat 1001
def B : Val := .nat 1002
def RA : Val := .nat 1101
def RB : Val := .nat 1102

/-- The harness names of the three statements. -/
def badUse : List Val := names (.nat 20) 0 0 1 3
def badBoth : List Val := names (.nat 20) 0 0 1 3 ++ names (.nat 21) 1 1 2 4
def badFlat : List Val := .nat 9 :: names (.nat 20) 0 0 1 3 ++ names (.nat 21) 1 1 2 4

theorem callV_even (failA two withBind : Bool) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (envH (W failA two withBind)).callV id a v = userR (id / 2) := by
  have h0 : HLam.ofId? id = none := by simp [HLam.ofId?, Codec.isLibId, hid]
  have h1 : Bracket.BLam.ofId? id = none := Bracket.BLam.ofId?_even hid
  have h2 : ULam.ofId? id = none := by simp [ULam.ofId?, Codec.isLibId, hid]
  have h3 : Race.ofId? id = none := by simp [Race.ofId?, Codec.isLibId, hid]
  show (match HLam.ofId? id with | some l => l.call a v | none => resDisp _ _ id a v) = _
  simp [h0, resDisp, uDisp, h1, h2, h3, Codec.isLibId, hid, UEnv.userCall, W, renv, user]

theorem toEnv_callV_even (failA two withBind : Bool) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (W failA two withBind).toEnv.callV id a v = userR (id / 2) := by
  have h1 : Bracket.BLam.ofId? id = none := Bracket.BLam.ofId?_even hid
  have h2 : ULam.ofId? id = none := by simp [ULam.ofId?, Codec.isLibId, hid]
  have h3 : Race.ofId? id = none := by simp [Race.ofId?, Codec.isLibId, hid]
  show resDisp _ _ id a v = _
  simp [resDisp, uDisp, h1, h2, h3, Codec.isLibId, hid, UEnv.userCall, W, renv, user]

/-- No user result mentions a name of `badFlat` (the largest list; the others are sublists). -/
theorem userR_clean (bad : List Val) (hb : bad = badUse ∨ bad = badBoth ∨ bad = badFlat) (n : Nat) :
    mentionsR bad (userR n) = false := by
  match n with
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 => rcases hb with rfl | rfl | rfl <;> decide +kernel
  | _ + 8 => simp [userR, mentionsR]

theorem userR_ok (n : Nat) (R : Handle → Prop) (v : View) :
    WF.ResultOK isLibH R v (userR n) := by
  match n with
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 =>
    simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub, Val.handles]
  | _ + 8 => simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem calls (failA two withBind : Bool) (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    WF.CallOK isLibH [] (envH (W failA two withBind)) id arg v := by
  refine ⟨fun w _ => ?_, ?_⟩
  · rw [callV_even _ _ _ id hid, callV_even _ _ _ id hid]
  · rw [callV_even _ _ _ id hid]; exact userR_ok _ _ _

theorem env_opaque (failA two withBind : Bool) : WF.PollOpaque (envH (W failA two withBind)) := by
  refine WF.pollOpaque_of_const _ (fun id => userR (id / 2)) [0, 2, 4, 6, 8, 10, 12, 14]
    { out := .throw { code := 0 } } (fun id arg v hid => callV_even _ _ _ id hid arg v) (by decide +kernel)
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

theorem wellFormed (failA two withBind : Bool) (p : IO)
    (hp : WF.progOK isLibH (fun h => ([] : List Handle).contains h) p = true) :
    WellFormed isLibH [] (envH (W failA two withBind)) p :=
  ⟨hp, fun id hid arg v => calls _ _ _ id hid arg v, env_opaque _ _ _⟩

theorem mapMarker (failA two withBind : Bool) (m : Nat) (x : Val)
    (hm : userR m = { effects := [.emit x], out := .ret .unit }) :
    MapMarker (W failA two withBind).toEnv (2 * m) x := fun a v => by
  rw [toEnv_callV_even _ _ _ _ (by omega)]; simpa using hm

theorem marker (failA two withBind : Bool) (m : Nat) (x : Val)
    (hm : userR m = { effects := [.emit x], out := .ret .unit }) :
    Marker (W failA two withBind).toEnv (2 * m) x := fun a v => by
  rw [toEnv_callV_even _ _ _ _ (by omega)]; simpa using hm

/-- Only the marker indices 1-4 emit, and they emit only their own value. -/
theorem emitsOnly (failA two withBind : Bool) (ms : List Nat) (xs : List Val)
    (h : ∀ n, 1 ≤ n → n ≤ 4 → 2 * n ∉ ms → ∀ x ∈ xs, .emit x ∉ (userR n).effects) :
    EmitsOnly (W failA two withBind).toEnv ms xs := by
  intro id hid hm a v x hx
  rw [toEnv_callV_even _ _ _ id hid]
  have hk : id = 2 * (id / 2) := by omega
  match hn : id / 2 with
  | 0 | 5 | 6 | 7 => simp [userR]
  | 1 => exact h 1 (by omega) (by omega) (by rw [hn] at hk; rw [← hk]; exact hm) x hx
  | 2 => exact h 2 (by omega) (by omega) (by rw [hn] at hk; rw [← hk]; exact hm) x hx
  | 3 => exact h 3 (by omega) (by omega) (by rw [hn] at hk; rw [← hk]; exact hm) x hx
  | 4 => exact h 4 (by omega) (by omega) (by rw [hn] at hk; rw [← hk]; exact hm) x hx
  | _ + 8 => simp [userR]

end CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

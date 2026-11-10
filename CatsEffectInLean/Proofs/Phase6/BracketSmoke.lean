import CatsEffectInLean.Props.Phase6.Bracket
import CatsEffectInLean.Model.BracketExamples
import CatsEffectInLean.Model.EnumP

/-!
# Smoke tests of the `guarantee`/`bracket` properties (Phase 6, track G)

Not registered. Exact outcome sets (`EqvP`, `exploreP`, `decide +kernel`) on concrete programs
of `Model/BracketExamples.lean`, plus the parent lambdas of `Props/Phase6/Bracket.lean`.
They support the `open` entries; they prove nothing for all programs.

* `guaranteeIsGuaranteeCase`: holds for 14 pairs `(fa, fin)`; a broken `guarantee` that never
  runs the finalizer breaks it (`law_wrongFunction`).
* `bracketFullIsKernelDefaultPureUse`: holds for 4 pure `use` functions with a self-cancel in
  acquire (the CE-0005 situation) and without it.
* `bracketReleaseOnce`, `guaranteeFinalizerOnce`: the parent-cancel programs have about 3,000
  states each; `decide +kernel` needs about 19 GB per module. These checks are `#guard`s
  (compiled evaluation, not kernel-checked) in `test/Phase6/BracketSmokeParent.lean`; run them
  with `lake env lean test/Phase6/BracketSmokeParent.lean`.
-/

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

/-- `BracketExamples.env` plus the parent lambdas. -/
def disp2 (id : Nat) (a : Val) (v : View) : UserResult :=
  match BLam.ofId? id with
  | some l => call user progOf l a v
  | none =>
    match cloOfId id with
    | some c =>
      match ofCloVal c with
      | some (8, 0, []) => PLam.cancelJoin.call a v
      | some (8, 1, [.fiber f]) => (PLam.thenJoin f).call a v
      | _ => user id a v
    | none => user id a v

def env2 : UserEnv where
  call id a refs := disp2 id a { refs }
  callV := disp2

/-! ## The law `guaranteeIsGuaranteeCase` -/

def lawL (s f : Nat) : IO := guaranteeIO (.ext (.nat s)) (.ext (.nat f))
def lawR (s f : Nat) : IO := guaranteeCaseIO (.ext (.nat s)) (uid 0 [.nat f])

theorem law_0_3 : checkEqvP {} counterMaskModel env 400 (lawL 0 3) (lawR 0 3) = true := by decide +kernel
theorem law_2_3 : checkEqvP {} counterMaskModel env 400 (lawL 2 3) (lawR 2 3) = true := by decide +kernel
theorem law_1_3 : checkEqvP {} counterMaskModel env 400 (lawL 1 3) (lawR 1 3) = true := by decide +kernel
theorem law_3_3 : checkEqvP {} counterMaskModel env 400 (lawL 3 3) (lawR 3 3) = true := by decide +kernel
theorem law_5_3 : checkEqvP {} counterMaskModel env 400 (lawL 5 3) (lawR 5 3) = true := by decide +kernel
theorem law_7_3 : checkEqvP {} counterMaskModel env 400 (lawL 7 3) (lawR 7 3) = true := by decide +kernel
theorem law_8_3 : checkEqvP {} counterMaskModel env 400 (lawL 8 3) (lawR 8 3) = true := by decide +kernel
theorem law_0_4 : checkEqvP {} counterMaskModel env 400 (lawL 0 4) (lawR 0 4) = true := by decide +kernel
theorem law_2_4 : checkEqvP {} counterMaskModel env 400 (lawL 2 4) (lawR 2 4) = true := by decide +kernel
theorem law_1_4 : checkEqvP {} counterMaskModel env 400 (lawL 1 4) (lawR 1 4) = true := by decide +kernel
theorem law_5_4 : checkEqvP {} counterMaskModel env 400 (lawL 5 4) (lawR 5 4) = true := by decide +kernel
theorem law_8_4 : checkEqvP {} counterMaskModel env 400 (lawL 8 4) (lawR 8 4) = true := by decide +kernel
theorem law_9_5 : checkEqvP {} counterMaskModel env 400 (lawL 9 5) (lawR 9 5) = true := by decide +kernel
theorem law_8_8 : checkEqvP {} counterMaskModel env 400 (lawL 8 8) (lawR 8 8) = true := by decide +kernel

/-- Wrong-function test: a `guarantee` that never runs the finalizer (`fa` alone). -/
theorem law_wrongFunction : checkNotEqvP {} counterMaskModel env 400 (progOf (.nat 0)) (lawR 0 3) = true := by
  decide +kernel

/-! ## The `bracketFull` twin with a pure `use` -/

theorem twin_pure_c_7 : checkEqvP {} counterMaskModel env 400 (bracketFullIO (uid 0 [.nat 1]) (uid 0 [.nat 7]) (uid 2 [.nat 9]))
    (defaultBracketFullIO (uid 0 [.nat 1]) (uid 0 [.nat 7]) (uid 2 [.nat 9])) = true := by decide +kernel
theorem twin_pure_c_2 : checkEqvP {} counterMaskModel env 400 (bracketFullIO (uid 0 [.nat 1]) (uid 0 [.nat 2]) (uid 2 [.nat 9]))
    (defaultBracketFullIO (uid 0 [.nat 1]) (uid 0 [.nat 2]) (uid 2 [.nat 9])) = true := by decide +kernel
theorem twin_pure_u_5 : checkEqvP {} counterMaskModel env 400 (bracketFullIO (uid 0 [.nat 6]) (uid 0 [.nat 5]) (uid 2 [.nat 9]))
    (defaultBracketFullIO (uid 0 [.nat 6]) (uid 0 [.nat 5]) (uid 2 [.nat 9])) = true := by decide +kernel
theorem twin_pure_u_8 : checkEqvP {} counterMaskModel env 400 (bracketFullIO (uid 0 [.nat 6]) (uid 0 [.nat 8]) (uid 2 [.nat 9]))
    (defaultBracketFullIO (uid 0 [.nat 6]) (uid 0 [.nat 8]) (uid 2 [.nat 9])) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.BracketSmoke

import CatsEffectInLean.Props.Phase6.Bracket
import CatsEffectInLean.Model.EnumP

/-!
# Smoke tests: release and finalizer run once (harness of decision 54)

Supports the open entries `core.IO.bracket.releaseOnce` and `core.IO.guarantee.finalizerOnce`
(restated after review batch 4). For each input the checks evaluate the hypotheses too
(decision 53): user functions even, `a0` passes `progOK` with no handle, and the user table is
constant code that ignores the view (`CallOK`, `PollOpaque` as in
`Proofs/Phase6/BracketWitness.lean`). Then the claim must hold for every observation of the exact
outcome set (`outcomesPList`, all schedules with preemption), and the broken implementations
(`childOf` with `g = 2`: no release; `g = 3`: no finalizer) must break it.

Compiled evaluation (`#guard`), not kernel-checked: the sets are too large for `decide +kernel`
in the default build. Run: `lake env lean test/Phase6/BracketSmokeParent.lean` (silent on
success).
-/

namespace CatsEffectInLean.Proofs.Phase6.BracketSmokeParent

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Props.Phase6.Bracket

/-- User code (even ids `2 n`), constant: 1 `IO.cede`, 2 `IO.unit`, 3 `IO.raiseError(E7)`,
4 `IO.canceled`, 5 `IO.cede >> IO.canceled`. -/
def sR : Nat → UserResult
  | 1 => { out := .prog .cede }
  | 2 => { out := .prog (.pure .unit) }
  | 3 => { out := .prog (.error { code := 7 }) }
  | 4 => { out := .prog .canceled }
  | 5 => { out := .prog (.flatMap .cede (.user 8)) }
  | _ => { out := .throw { code := 0 } }

def su : UserEnv where
  call id _ _ := sR (id / 2)

/-- The acquire programs. -/
def acqs : List IO := [.pure (.nat 5), .flatMap .cede (.user 4), .error { code := 9 }, .canceled]

def obsOf (a0 : IO) (g x y : Nat) : Option (List Obs) :=
  outcomesPList {} counterMaskModel (henv a0 su) 20000 (harness g x y)

def done (o : Obs) : Bool := match o.summary with | .done _ => true | _ => false

def relClaim (o : Obs) : Bool := !done o || count o 1 == count o 0
def finClaim (o : Obs) : Bool := !done o || (count o 1 ≤ 1 && count o 0 ≤ count o 1)

/-- The decidable hypotheses: user functions even, `a0` with no handle. -/
def hyps (a0 : IO) (x y : Nat) : Bool :=
  x % 2 == 0 && y % 2 == 0 && WF.progOK isLib (fun h => ([] : List Handle).contains h) a0

def holds (a0 : IO) (g x y : Nat) (p : Obs → Bool) : Bool :=
  hyps a0 x y && (obsOf a0 g x y).any (·.all p)

def breaks (a0 : IO) (g x y : Nat) (p : Obs → Bool) : Bool :=
  hyps a0 x y && (obsOf a0 g x y).any (·.any fun o => !p o)

-- bracket: 4 acquires x 4 uses (cede, unit, raise, canceled), release `IO.unit`
#guard acqs.all fun a0 => [2, 4, 6, 8].all fun use => holds a0 0 use 4 relClaim
-- release that suspends (`IO.cede`) and that cancels itself (`IO.cede >> IO.canceled`)
#guard holds (.pure (.nat 5)) 0 2 2 relClaim
#guard holds (.pure (.nat 5)) 0 2 10 relClaim
-- wrong function: a bracket that never runs release
#guard breaks (.pure (.nat 5)) 2 2 4 relClaim

-- guarantee: k in {cede, unit, raise, canceled}, q in {unit, cede, raise}
#guard [2, 4, 6, 8].all fun k => [4, 2, 6].all fun q => holds (.pure .unit) 1 k q finClaim
-- wrong function: a guarantee that never runs the finalizer
#guard breaks (.pure .unit) 3 2 4 finClaim

end CatsEffectInLean.Proofs.Phase6.BracketSmokeParent

import CatsEffectInLean.Props.Phase6.Bracket
import CatsEffectInLean.Model.BracketExamples
import CatsEffectInLean.Model.EnumP
import CatsEffectInLean.Proofs.Phase6.BracketSmoke

/-!
# Smoke tests: release and finalizer run once (parent cancels the child)

Supports the open entries `core.IO.bracket.releaseOnce` and `core.IO.guarantee.finalizerOnce`.
Each program has about 3,000 states under `exploreP`, too large for `decide +kernel` in the
default build (about 19 GB per module). So these are `#guard`s (compiled evaluation, not
kernel-checked). Run: `lake env lean test/Phase6/BracketSmokeParent.lean` (silent on success).
-/

namespace CatsEffectInLean.Proofs.Phase6.BracketSmokeParent

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket
open CatsEffectInLean.Proofs.Phase6.BracketSmoke

/-! ## Release and finalizer run once (parent cancels the child) -/

/-- All observations satisfy `p`. -/
def allObs (io : IO) (p : Obs → Bool) : Option Bool :=
  (outcomesPList {} counterMaskModel env2 4000 io).map (·.all p)

/-- `bracket(a0.flatMap(markA 77))(use)(_ => IO.delay(emit 88) *> IO.unit)` under `parent`. -/
def relProg (a0 use : Nat) : IO :=
  parent (bracketIO (.ext (.pair (.nat 50) (.nat a0))) (uid 0 [.nat use]) (uid 6 []))

def relOK (o : Obs) : Bool := o.out.count (.nat 88) == o.out.count (.nat 77)

#guard allObs (relProg 6 9) relOK == some true
#guard allObs (relProg 6 2) relOK == some true
#guard allObs (relProg 6 1) relOK == some true
#guard allObs (relProg 9 6) relOK == some true
#guard allObs (relProg 1 6) relOK == some true
#guard allObs (relProg 2 6) relOK == some true

-- Wrong-function test: a `bracket` that never runs release (`acquire.flatMap(use)`).
#guard allObs (parent (.flatMap (progOf (.pair (.nat 50) (.nat 6))) (.user (uid 0 [.nat 9])))) relOK == some false

def finOK (o : Obs) : Bool := o.out.count (.nat 88) ≤ 1 && o.out.count (.nat 77) ≤ o.out.count (.nat 88)

/-- `guarantee(IO.delay(emit 77) *> progOf c)(IO.delay(emit 88) *> IO.unit)` under `parent`. -/
def finProg (c : Nat) : IO := parent (guaranteeIO (.ext (.pair (.nat 51) (.nat c))) (.ext (.nat 10)))

#guard allObs (finProg 9) finOK == some true
#guard allObs (finProg 2) finOK == some true
#guard allObs (finProg 5) finOK == some true

end CatsEffectInLean.Proofs.Phase6.BracketSmokeParent

import CatsEffectInLean.Model.WellFormed

/-! Audit fixtures: property definitions. Not part of the library. -/

namespace AuditFixtures.Props

/-- True. -/
def addZero : Prop := ∀ n : Nat, n + 0 = n

/-- True. -/
def addComm : Prop := ∀ a b : Nat, a + b = b + a

/-- False: `0 - 1 + 1 = 1`. -/
def subAddCancel : Prop := ∀ a b : Nat, a - b + b = a

/-- A weaker statement than `addZero`. -/
def addZeroOrTrue : Prop := ∀ n : Nat, n + 0 = n ∨ True

/-- Uses a `Lib` without function fields (`Lib.idFree`), check `lib-fields` (decision 56). -/
def idFreeLib : Prop := (CatsEffectInLean.Model.Lib.idFree fun _ => false).ok 0 = false

/-- The same with a `{ ok := _ }` literal. -/
def litLib : Prop := ({ ok := fun _ => false } : CatsEffectInLean.Model.Lib).ok 0 = false

/-- Through another definition. -/
def viaDef : Prop := idFreeLib

end AuditFixtures.Props

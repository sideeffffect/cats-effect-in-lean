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

end AuditFixtures.Props

import AuditFixtures.Props

/-! Audit fixtures: theorems. Some are correct; some are planted mistakes that the
audit must reject when they are registered for the wrong property. -/

namespace AuditFixtures.Proofs
open AuditFixtures.Props

theorem addZero_proven : addZero := fun _ => rfl

theorem addComm_proven : addComm := Nat.add_comm

theorem subAddCancel_refuted : ¬ subAddCancel := fun h => absurd (h 0 1) (by decide)

/-- Planted: proves a weaker statement. -/
theorem addZeroOrTrue_proven : addZeroOrTrue := fun _ => Or.inr trivial

/-- Planted: proves the unfolded body. It is definitionally equal to `addZero`,
but the audit requires the constant itself. -/
theorem addZero_unfolded : ∀ n : Nat, n + 0 = n := fun _ => rfl

end AuditFixtures.Proofs

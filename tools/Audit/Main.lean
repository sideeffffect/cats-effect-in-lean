import Audit.Core
import CatsEffectInLean

/-! `lake exe audit`: audit the real registry against `inventory/inventory.csv`.
Run it from the repository root. -/

def main : IO UInt32 :=
  Audit.run {
    imports := #[`CatsEffectInLean]
    registry := CatsEffectInLean.registry
    csv := "inventory/inventory.csv"
    propModulePrefix := `CatsEffectInLean.Props
    thmModulePrefix := `CatsEffectInLean.Proofs }

import Audit.Core
import CatsEffectInLean

/-! `lake exe audit`: audit the real registry against `inventory/inventory.csv`.
Run it from the repository root. The heavy registry (`RegistryHeavy.lean`, decision 55) is
read but its theorems are not imported; `lake exe audit_heavy` checks them. -/

def main : IO UInt32 :=
  Audit.run {
    imports := #[`CatsEffectInLean]
    registry := CatsEffectInLean.registry
    heavy := CatsEffectInLean.registryHeavy
    verifyHeavy := false
    csv := "inventory/inventory.csv"
    propModulePrefix := `CatsEffectInLean.Props
    thmModulePrefix := `CatsEffectInLean.Proofs }

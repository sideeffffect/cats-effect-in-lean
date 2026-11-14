import Audit.Core
import CatsEffectInLean

/-! `lake exe audit_heavy` (decision 55): audit both registries in full. The heavy proof modules
(`CatsEffectInLean.heavyModules`, lean_lib `HeavyProofs`) must be built first
(`scripts/check_heavy_proofs.sh`); they are imported at run time only, so this executable
builds fast. Run it from the repository root. -/

def main : IO UInt32 :=
  Audit.run {
    imports := #[`CatsEffectInLean] ++ CatsEffectInLean.heavyModules
    registry := CatsEffectInLean.registry
    heavy := CatsEffectInLean.registryHeavy
    verifyHeavy := true
    csv := "inventory/inventory.csv"
    propModulePrefix := `CatsEffectInLean.Props
    thmModulePrefix := `CatsEffectInLean.Proofs }

import CatsEffectInLean.RegistryHeavy

/-! Print the heavy roots (`CatsEffectInLean.heavyModules`) and the theorems of the heavy
registry (`CatsEffectInLean.registryHeavy`), one per line: `module <name>` / `thm <name>`.
`scripts/check_heavy_proofs.sh` derives its module list and its `#print axioms` list from this
output (review batch 7, gap 3). Run: `lake env lean --run tools/HeavyList.lean`. -/

def main : IO Unit := do
  for m in CatsEffectInLean.heavyModules do
    IO.println s!"module {m}"
  for e in CatsEffectInLean.registryHeavy do
    if let some t := e.thm then
      IO.println s!"thm {t}"

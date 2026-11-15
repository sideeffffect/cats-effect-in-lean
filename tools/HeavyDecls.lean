import Lean

/-! Print every constant declared in the given modules, one name per line (no escaping).
`scripts/check_export_scope.py` compares this list with a `leanexport` file, so the paranoid
run shows that its export holds every heavy declaration (review batch 8, gap 4 evidence).
Run (after the modules are built): `lake env lean --run tools/HeavyDecls.lean <module>...` -/

open Lean

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "usage: HeavyDecls <module>..."
    return 2
  initSearchPath (← findSysroot)
  let mods := args.map String.toName
  let env ← importModules (mods.toArray.map ({ module := · })) {}
  let mut n := 0
  for (c, _) in env.constants.map₁.toList do
    if let some idx := env.getModuleIdxFor? c then
      if mods.contains (env.header.moduleNames[idx.toNat]!) then
        IO.println (c.toString (escape := false))
        n := n + 1
  if n == 0 then
    IO.eprintln "no constants found in the given modules"
    return 1
  return 0

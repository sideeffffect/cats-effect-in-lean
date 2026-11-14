#!/usr/bin/env bash
# Heavy proofs (decision 55, lean_lib HeavyProofs, registry CatsEffectInLean/RegistryHeavy.lean).
#
# 1. Build the heavy modules one module per `lake build`, in import order, so that only one
#    heavy Lean process runs at once (the largest `decide` needs about 8 GB).
# 2. `lake exe audit_heavy`: audit Registry.lean and RegistryHeavy.lean in full (theorem types,
#    modules, axioms) and run the full inventory cross-check, including the rows that the main
#    audit defers.
# 3. Explicit axiom check of the heavy theorems (`#print axioms`).
# 4. Kernel replay of every heavy module with `leanchecker`, one module per process (the main
#    job's `lake check` covers only the default target). Skip with SKIP_REPLAY=1 (the scheduled
#    paranoid run replays them itself).
#
# Usage: scripts/check_heavy_proofs.sh   (from any directory)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.elan/bin:$PATH"

dir=CatsEffectInLean/Proofs/Phase6
mods=(RaceLawCertLhs RaceLawCertRhs RaceLawDefs)
while IFS= read -r f; do
  b=$(basename "$f" .lean); mods+=("$b")
done < <(ls "$dir"/RaceLawChunks*.lean | sort -V)
mods+=(RaceLaw)

for m in "${mods[@]}"; do
  echo "== CatsEffectInLean.Proofs.Phase6.$m"
  lake build --wfail "CatsEffectInLean.Proofs.Phase6.$m"
done
lake build --wfail HeavyProofs audit_heavy

echo "== heavy registry audit"
lake exe audit_heavy

echo "== axioms of the heavy theorems"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/HeavyAxioms.lean" <<'LEAN'
import CatsEffectInLean.Proofs.Phase6.RaceLaw
#print axioms CatsEffectInLean.Proofs.Phase6.RaceLaw.uncancelableRaceNotInherited_proven
LEAN
out=$(lake env lean "$tmp/HeavyAxioms.lean" 2>&1)
echo "$out"
bad=$(echo "$out" | grep -o '\[[^]]*\]' | tr -d '[]' | tr ',' '\n' | sed 's/^ *//' | grep -v -E '^(propext|Classical\.choice|Quot\.sound)$' | grep -v '^$' || true)
if echo "$out" | grep -qi 'error'; then echo "FAIL: error while checking axioms"; exit 1; fi
if [[ $(echo "$out" | grep -c 'depends on axioms\|does not depend on any axioms') -ne 1 ]]; then echo "FAIL: expected 1 axiom report"; exit 1; fi
if [[ -n $bad ]]; then echo "FAIL: forbidden axioms: $bad"; exit 1; fi

if [[ "${SKIP_REPLAY:-0}" != 1 ]]; then
  # `leanchecker M` replays only the declarations of module M (measured: the root alone takes
  # 23 s, one chunk module about 3 min), so replay every heavy module, one process at a time.
  for m in "${mods[@]}"; do
    echo "== kernel replay (leanchecker) CatsEffectInLean.Proofs.Phase6.$m"
    lake env leanchecker "CatsEffectInLean.Proofs.Phase6.$m"
  done
fi
echo "OK: heavy proofs built, both registries audited, axioms only propext, Classical.choice, Quot.sound"

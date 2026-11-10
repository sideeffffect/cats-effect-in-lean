#!/usr/bin/env bash
# Build the CE-0002 fixed-twin checks (lean_lib TwinChecks) one module at a time, so that only
# one heavy Lean process runs at once (the largest needs about 13 GB), then check their axioms.
# Usage: scripts/check_twin_checks.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.elan/bin:$PATH"
lake build --wfail CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedChecks
for f in CatsEffectInLean/Proofs/Calibration/ResourceEvalFixedParts/*.lean; do
  m=${f%.lean}; m=${m//\//.}
  echo "== $m"
  lake build --wfail "$m"
done
lake build --wfail TwinChecks
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/TwinAxioms.lean" <<'LEAN'
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedOld
#print axioms CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed.fixedTwin_holds
#print axioms CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed.v371_fails
#print axioms CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed.v371_fails_more
LEAN
out=$(lake env lean "$tmp/TwinAxioms.lean" 2>&1)
echo "$out"
bad=$(echo "$out" | grep -o '\[[^]]*\]' | tr -d '[]' | tr ',' '\n' | sed 's/^ *//' | grep -v -E '^(propext|Classical\.choice|Quot\.sound)$' | grep -v '^$' || true)
if echo "$out" | grep -qi 'error'; then echo "FAIL: error while checking axioms"; exit 1; fi
if [[ $(echo "$out" | grep -c 'depends on axioms\|does not depend on any axioms') -ne 3 ]]; then echo "FAIL: expected 3 axiom reports"; exit 1; fi
if [[ -n $bad ]]; then echo "FAIL: forbidden axioms: $bad"; exit 1; fi
echo "OK: twin checks built; axioms only propext, Classical.choice, Quot.sound"

#!/usr/bin/env bash
# Fixed-twin checks and the track G smoke tests (lean_lib TwinChecks; decisions 39, 45, 57).
#
# Two modes:
# - Full (local, default): build every module of TwinChecks here.
# - Aggregate (CI job `twin-aggregate`, TWIN_ARTIFACTS_IN=<dir>): the matrix jobs `twin-module`
#   (scripts/check_heavy_module.sh --lib TwinChecks) built the other modules and uploaded their
#   artifacts; this job checks and installs them (scripts/install_artifacts.sh) and builds only
#   the aggregating roots (roots that import other TwinChecks modules).
#
# Steps:
# 1. Build the default target (outside the sandbox, as the main job does).
# 2. Module list: scripts/heavy_closure.py --lib TwinChecks (import closure of the lakefile roots
#    minus the default target, imports first).
# 3. Build the modules one at a time in the bwrap sandbox, each build checked to change only its
#    own artifacts (scripts/heavy_build.sh). In aggregate mode the installed artifacts must stay
#    byte-identical.
# 4. Axioms of the result theorems below: only propext, Classical.choice, Quot.sound.
#
# Usage: scripts/check_twin_checks.sh   (from any directory; needs bwrap)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.elan/bin:$PATH"
lake_bin=$(command -v lake)
artifacts_in=${TWIN_ARTIFACTS_IN:-}

# The result theorems of the twin checks (one or more per root).
theorems=(
  CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed.fixedTwin_holds
  CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed.v371_fails
  CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed.v371_fails_more
  CatsEffectInLean.Proofs.Phase6.BracketFullFixed.all_checks
  CatsEffectInLean.Proofs.Phase6.BracketSmoke.all_checks
  CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness.all_checks
  CatsEffectInLean.Proofs.Phase6.ResourceBothFixed.all_checks
  CatsEffectInLean.Proofs.Phase7.SemaphoreCountFixed.all_checks
  CatsEffectInLean.Proofs.Phase7.SupervisorRestartWitness.all_checks
)

safe=$(mktemp -d)
trap 'rm -rf "$safe"' EXIT

echo "== 1. default target (outside the sandbox, as in the main job)"
lake build --wfail CatsEffectInLean

echo "== 2. TwinChecks modules"
python3 scripts/heavy_closure.py --from-lakefile --lib TwinChecks > "$safe/mods.txt"
python3 scripts/heavy_closure.py --from-lakefile --lib TwinChecks --roots > "$safe/roots.txt"
python3 scripts/heavy_closure.py --from-lakefile --lib TwinChecks --aggregates > "$safe/aggr.txt"
mapfile -t mods < "$safe/mods.txt"
mapfile -t roots < "$safe/roots.txt"
mapfile -t aggr < "$safe/aggr.txt"
[[ ${#mods[@]} -gt 0 ]] || { echo "FAIL: no TwinChecks modules"; exit 1; }
printf '%s\n' "${mods[@]}"

if [[ -n "$artifacts_in" ]]; then
  echo "== 2b. install the artifacts of the matrix jobs from $artifacts_in"
  is_aggr() { local r; for r in "${aggr[@]}"; do [[ $r == "$1" ]] && return 0; done; return 1; }
  from_matrix=()
  for m in "${mods[@]}"; do is_aggr "$m" || from_matrix+=("$m"); done
  scripts/install_artifacts.sh "$artifacts_in" "$safe/installed.sha" "${from_matrix[@]}"
fi

echo "== 3. TwinChecks modules, sandboxed, one at a time"
scripts/heavy_build.sh "${mods[@]}"
if [[ -n "$artifacts_in" && -s "$safe/installed.sha" ]]; then
  (cd .lake && sha256sum --quiet -c "$safe/installed.sha") \
    || { echo "FAIL: installed matrix artifacts were rebuilt or changed"; exit 1; }
fi

echo "== 4. axioms"
axdir=.lake/twin-axioms
rm -rf "$axdir"; mkdir -p "$axdir"
{
  for r in "${roots[@]}"; do echo "import $r"; done
  for t in "${theorems[@]}"; do echo "#print axioms $t"; done
} > "$axdir/TwinAxioms.lean"
rc=0
out=$(scripts/sandbox.sh "$lake_bin" env lean "$axdir/TwinAxioms.lean" 2>&1) || rc=$?
echo "$out"
flat=$(echo "$out" | tr '\n' ' ')
if [[ $rc -ne 0 ]] || grep -qE ':[0-9]+:[0-9]+: error' <<< "$out"; then
  echo "FAIL: error while checking axioms (exit $rc)"; exit 1
fi
n_reports=$(echo "$flat" | grep -o 'depends on axioms\|does not depend on any axioms' | wc -l)
if [[ $n_reports -ne ${#theorems[@]} ]]; then
  echo "FAIL: expected ${#theorems[@]} axiom reports, got $n_reports"; exit 1
fi
bad=$(echo "$flat" | grep -o '\[[^]]*\]' | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
  | grep -v -E '^(propext|Classical\.choice|Quot\.sound)$' | grep -v '^$' || true)
if [[ -n $bad ]]; then echo "FAIL: forbidden axioms: $bad"; exit 1; fi
echo "OK: twin checks built in the sandbox; axioms only propext, Classical.choice, Quot.sound"

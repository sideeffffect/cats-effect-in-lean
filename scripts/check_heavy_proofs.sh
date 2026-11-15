#!/usr/bin/env bash
# Heavy proofs (decisions 55 and 57, lean_lib HeavyProofs, registry
# CatsEffectInLean/RegistryHeavy.lean).
#
# Two modes:
# - Full (local, default): build and replay every heavy module here.
# - Audit (CI job `heavy-audit`, HEAVY_ARTIFACTS_IN=<dir>): the matrix jobs `heavy-module`
#   (scripts/check_heavy_module.sh) built and replayed each non-root heavy module and uploaded its
#   artifacts; this job checks that an artifact set exists for every non-root module, installs
#   them, and builds and replays only the roots.
#
# Steps:
# 1. Build the default target and `audit_heavy` (outside the sandbox, as the main job does).
#    Copy the `audit_heavy` binary out of `.lake`.
# 2. Derive the lists (review batch 7, gap 3): `tools/HeavyList.lean` prints
#    `CatsEffectInLean.heavyModules` and the theorems of `registryHeavy`;
#    `scripts/heavy_closure.py` gives the heavy module closure (imports first) and fails if the
#    lakefile roots differ from `heavyModules`.
# 3. Build the heavy modules one at a time in the bwrap sandbox, each build checked to change
#    only its own artifacts (scripts/heavy_build.sh; review batch 7, gap 1). In audit mode the
#    installed artifacts must stay byte-identical (no rebuild of a module that a matrix job
#    replayed).
# 4. Run the copied `audit_heavy`: both registries in full, full inventory cross-check
#    (deferred rows included).
# 5. `#print axioms` of every heavy theorem, in the sandbox.
# 6. `leanchecker` replay, one module per process, in the sandbox: every heavy module (full
#    mode) or the roots (audit mode). Skip with SKIP_REPLAY=1 (paranoid-heavy.yml replays the
#    export through all kernels instead).
#
# Writes the heavy module list to $HEAVY_MODULES_OUT if set.
# Usage: scripts/check_heavy_proofs.sh   (from any directory; needs bwrap)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.elan/bin:$PATH"
lake_bin=$(command -v lake)
artifacts_in=${HEAVY_ARTIFACTS_IN:-}

safe=$(mktemp -d)
trap 'chmod -R u+w "$safe" 2>/dev/null; rm -rf "$safe"' EXIT

echo "== 1. default target and tools (outside the sandbox, as in the main job)"
lake build --wfail CatsEffectInLean audit_heavy
cp .lake/build/bin/audit_heavy "$safe/audit_heavy"
chmod a-w "$safe/audit_heavy"
lean_path=$(lake env printenv LEAN_PATH)

echo "== 2. heavy module and theorem lists"
lake env lean --run tools/HeavyList.lean > "$safe/heavylist.txt"
mapfile -t roots < <(sed -n 's/^module //p' "$safe/heavylist.txt")
mapfile -t thm_list < <(sed -n 's/^thm //p' "$safe/heavylist.txt")
[[ ${#roots[@]} -gt 0 ]] || { echo "FAIL: no heavy roots"; exit 1; }
[[ ${#thm_list[@]} -gt 0 ]] || { echo "FAIL: no heavy theorems in registryHeavy"; exit 1; }
python3 scripts/heavy_closure.py "${roots[@]}" > "$safe/mods.txt"
mapfile -t mods < "$safe/mods.txt"
[[ ${#mods[@]} -gt 0 ]] || { echo "FAIL: no heavy modules"; exit 1; }
printf '%s\n' "${mods[@]}"
if [[ -n "${HEAVY_MODULES_OUT:-}" ]]; then cp "$safe/mods.txt" "$HEAVY_MODULES_OUT"; fi
replay=("${mods[@]}")
if [[ -n "$artifacts_in" ]]; then
  echo "== 2b. install the artifacts of the matrix jobs from $artifacts_in"
  # the aggregating roots are built and replayed here; every other module comes from a matrix job
  python3 scripts/heavy_closure.py --aggregates "${roots[@]}" > "$safe/aggr.txt"
  mapfile -t aggr < "$safe/aggr.txt"
  is_aggr() { local r; for r in "${aggr[@]}"; do [[ $r == "$1" ]] && return 0; done; return 1; }
  replay=("${aggr[@]}")
  from_matrix=()
  for m in "${mods[@]}"; do is_aggr "$m" || from_matrix+=("$m"); done
  scripts/install_artifacts.sh "$artifacts_in" "$safe/installed.sha" "${from_matrix[@]}"
fi

echo "== 3. heavy modules, sandboxed, one at a time"
scripts/heavy_build.sh "${mods[@]}"
if [[ -n "$artifacts_in" && -s "$safe/installed.sha" ]]; then
  (cd .lake && sha256sum --quiet -c "$safe/installed.sha") \
    || { echo "FAIL: installed matrix artifacts were rebuilt or changed"; exit 1; }
fi

echo "== 4. heavy registry audit (copied binary)"
LEAN_PATH="$lean_path" "$safe/audit_heavy"

echo "== 5. axioms of the heavy theorems"
# the sandbox has a private /tmp, so the generated file goes to .lake (read by the sandbox only)
axdir=.lake/heavy-axioms
rm -rf "$axdir"; mkdir -p "$axdir"
{
  for m in "${roots[@]}"; do echo "import $m"; done
  for t in "${thm_list[@]}"; do echo "#print axioms $t"; done
} > "$axdir/HeavyAxioms.lean"
rc=0
out=$(scripts/sandbox.sh "$lake_bin" env lean "$axdir/HeavyAxioms.lean" 2>&1) || rc=$?
echo "$out"
flat=$(echo "$out" | tr '\n' ' ')
# Lean reports errors as `<file>:<line>:<col>: error`; a theorem name may contain "error" (for
# example `errorAborts`, review batch 8), so only that prefix and the exit code count
if [[ $rc -ne 0 ]] || grep -qE ':[0-9]+:[0-9]+: error' <<< "$out"; then
  echo "FAIL: error while checking axioms (exit $rc)"; exit 1
fi
n_reports=$(echo "$flat" | grep -o 'depends on axioms\|does not depend on any axioms' | wc -l)
if [[ $n_reports -ne ${#thm_list[@]} ]]; then
  echo "FAIL: expected ${#thm_list[@]} axiom reports, got $n_reports"; exit 1
fi
bad=$(echo "$flat" | grep -o '\[[^]]*\]' | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
  | grep -v -E '^(propext|Classical\.choice|Quot\.sound)$' | grep -v '^$' || true)
if [[ -n $bad ]]; then echo "FAIL: forbidden axioms: $bad"; exit 1; fi

if [[ "${SKIP_REPLAY:-0}" != 1 ]]; then
  for m in "${replay[@]}"; do
    echo "== 6. kernel replay (leanchecker) $m"
    scripts/sandbox.sh "$lake_bin" env leanchecker "$m"
  done
fi
echo "OK: heavy proofs built in the sandbox, both registries audited, axioms only propext, Classical.choice, Quot.sound"

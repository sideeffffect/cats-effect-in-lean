#!/usr/bin/env bash
# Heavy proofs (decision 55, lean_lib HeavyProofs, registry CatsEffectInLean/RegistryHeavy.lean).
#
# 1. Build the default target and the tools (`audit_heavy`) as the main job does. Copy the
#    `audit_heavy` binary to a directory outside `.lake`, and hash every file under
#    `.lake/build`.
# 2. Derive the heavy module list and the theorem list (review batch 7, gap 3):
#    `tools/HeavyList.lean` prints `CatsEffectInLean.heavyModules` and the theorems of
#    `registryHeavy`; `scripts/heavy_closure.py` gives the import closure of the roots minus the
#    default target, imports first, and fails if the lakefile roots differ.
# 3. Build the heavy modules one module per `lake build`, each inside the bwrap sandbox
#    (`scripts/sandbox.sh`: read-only file system except `.lake`, no network; review batch 7,
#    gap 1), so build-time code cannot change the sources, the inventory or the audit tool.
# 4. Check that the heavy build changed nothing outside its own module artifacts: every file
#    hashed in step 1 that does not belong to a heavy module is unchanged, and the git work
#    tree is unchanged.
# 5. Run the copied `audit_heavy`: audit Registry.lean and RegistryHeavy.lean in full
#    (theorem types, modules, axioms) and run the full inventory cross-check, including the rows
#    that the main audit defers.
# 6. Explicit `#print axioms` of every heavy theorem (from step 2), in the sandbox.
# 7. Kernel replay of every heavy module with `leanchecker` (one module per process; `leanchecker
#    M` replays only the declarations of M), in the sandbox. Skip with SKIP_REPLAY=1 (the
#    scheduled paranoid run replays the export through all kernels instead).
#
# Writes the heavy module list to $HEAVY_MODULES_OUT if set (used by paranoid-heavy.yml).
# Usage: scripts/check_heavy_proofs.sh   (from any directory; needs bwrap)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.elan/bin:$PATH"
lake_bin=$(command -v lake)

safe=$(mktemp -d)
trap 'chmod -R u+w "$safe" 2>/dev/null; rm -rf "$safe"' EXIT

echo "== 1. default target and tools (outside the sandbox, as in the main job)"
lake build --wfail CatsEffectInLean audit_heavy
cp .lake/build/bin/audit_heavy "$safe/audit_heavy"
chmod a-w "$safe/audit_heavy"
lean_path=$(lake env printenv LEAN_PATH)

echo "== 2. heavy module and theorem lists"
lake env lean --run tools/HeavyList.lean > "$safe/heavylist.txt"
roots=$(sed -n 's/^module //p' "$safe/heavylist.txt")
thms=$(sed -n 's/^thm //p' "$safe/heavylist.txt")
# shellcheck disable=SC2086
python3 scripts/heavy_closure.py $roots > "$safe/mods.txt"
mapfile -t mods < "$safe/mods.txt"
mapfile -t thm_list <<< "$thms"
[[ ${#mods[@]} -gt 0 ]] || { echo "FAIL: no heavy modules"; exit 1; }
[[ -n "$thms" ]] || { echo "FAIL: no heavy theorems in registryHeavy"; exit 1; }
printf '%s\n' "${mods[@]}"
if [[ -n "${HEAVY_MODULES_OUT:-}" ]]; then cp "$safe/mods.txt" "$HEAVY_MODULES_OUT"; fi

# hash every build file that does not belong to a heavy module
heavy_re=$(printf '%s\n' "${mods[@]}" | sed 's/\./\//g; s/^/\//; s/$/\\./' | paste -sd'|')
manifest() {
  find .lake/build -type f -print0 | sort -z | xargs -0 sha256sum | grep -v -E "$heavy_re" || true
}
manifest > "$safe/before.sha"
git status --porcelain=v1 --untracked-files=all > "$safe/git_before.txt"
git diff HEAD > "$safe/git_before.diff"

echo "== 3. heavy modules, one sandboxed lake build each"
for m in "${mods[@]}"; do
  echo "== build $m"
  scripts/sandbox.sh "$lake_bin" build --wfail "$m"
done
scripts/sandbox.sh "$lake_bin" build --wfail HeavyProofs

echo "== 4. nothing outside the heavy module artifacts changed"
manifest > "$safe/after.sha"
if ! diff -q "$safe/before.sha" "$safe/after.sha" > /dev/null; then
  echo "FAIL: the heavy build changed build files outside its own modules:"
  diff "$safe/before.sha" "$safe/after.sha" | head -20
  exit 1
fi
git status --porcelain=v1 --untracked-files=all > "$safe/git_after.txt"
git diff HEAD > "$safe/git_after.diff"
if ! cmp -s "$safe/git_before.txt" "$safe/git_after.txt" || ! cmp -s "$safe/git_before.diff" "$safe/git_after.diff"; then
  echo "FAIL: the heavy build changed the work tree"; exit 1
fi

echo "== 5. heavy registry audit (copied binary)"
LEAN_PATH="$lean_path" "$safe/audit_heavy"

echo "== 6. axioms of the heavy theorems"
# the sandbox has a private /tmp, so the generated file goes to .lake (read by the sandbox only)
axdir=.lake/heavy-axioms
rm -rf "$axdir"; mkdir -p "$axdir"
{
  for m in $roots; do echo "import $m"; done
  for t in "${thm_list[@]}"; do echo "#print axioms $t"; done
} > "$axdir/HeavyAxioms.lean"
out=$(scripts/sandbox.sh "$lake_bin" env lean "$axdir/HeavyAxioms.lean" 2>&1)
echo "$out"
flat=$(echo "$out" | tr '\n' ' ')
if echo "$flat" | grep -qi 'error'; then echo "FAIL: error while checking axioms"; exit 1; fi
n_reports=$(echo "$flat" | grep -o 'depends on axioms\|does not depend on any axioms' | wc -l)
if [[ $n_reports -ne ${#thm_list[@]} ]]; then
  echo "FAIL: expected ${#thm_list[@]} axiom reports, got $n_reports"; exit 1
fi
bad=$(echo "$flat" | grep -o '\[[^]]*\]' | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
  | grep -v -E '^(propext|Classical\.choice|Quot\.sound)$' | grep -v '^$' || true)
if [[ -n $bad ]]; then echo "FAIL: forbidden axioms: $bad"; exit 1; fi

if [[ "${SKIP_REPLAY:-0}" != 1 ]]; then
  for m in "${mods[@]}"; do
    echo "== 7. kernel replay (leanchecker) $m"
    scripts/sandbox.sh "$lake_bin" env leanchecker "$m"
  done
fi
echo "OK: heavy proofs built in the sandbox, both registries audited, axioms only propext, Classical.choice, Quot.sound"

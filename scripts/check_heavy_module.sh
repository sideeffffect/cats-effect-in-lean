#!/usr/bin/env bash
# One heavy module (decision 57: CI matrix job `heavy-module (<M>)`).
#
# 1. Ask scripts/heavy_closure.py which default-target modules and which heavy modules M needs.
# 2. Build the default-target dependencies (outside the sandbox, as the main CI job does).
# 3. Build the heavy dependencies and M one at a time in the bwrap sandbox, with the check that
#    each build changes only its own artifacts (scripts/heavy_build.sh).
# 4. Kernel replay of M with `leanchecker` in the sandbox (`leanchecker M` replays only M's own
#    declarations; each heavy dependency is replayed by its own matrix job).
# 5. If HEAVY_ARTIFACT_OUT is set, copy M's own build artifacts (`.lake/build/**/M.*`) to
#    $HEAVY_ARTIFACT_OUT/build/... with a sha256 list, for the `heavy-audit` job.
#
# Usage: scripts/check_heavy_module.sh <module>   (from any directory; needs bwrap)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.elan/bin:$PATH"
lake_bin=$(command -v lake)
m=${1:?usage: check_heavy_module.sh <module>}

deps=$(python3 scripts/heavy_closure.py --from-lakefile --deps "$m")
read -r -a light <<< "$(sed -n 's/^light //p' <<< "$deps")"
read -r -a heavy <<< "$(sed -n 's/^heavy //p' <<< "$deps")"
[[ ${heavy[-1]} == "$m" ]] || { echo "FAIL: heavy dependency list does not end with $m"; exit 1; }

echo "== default-target dependencies of $m (${#light[@]} modules)"
if [[ ${#light[@]} -gt 0 ]]; then lake build --wfail "${light[@]}"; fi

echo "== heavy dependencies and $m, sandboxed, one at a time"
scripts/heavy_build.sh "${heavy[@]}"

echo "== kernel replay (leanchecker) $m"
scripts/sandbox.sh "$lake_bin" env leanchecker "$m"

if [[ -n "${HEAVY_ARTIFACT_OUT:-}" ]]; then
  path=$(echo "$m" | sed 's/\./\//g')
  mkdir -p "$HEAVY_ARTIFACT_OUT"
  n=0
  while IFS= read -r -d '' f; do
    rel=${f#.lake/}
    mkdir -p "$HEAVY_ARTIFACT_OUT/$(dirname "$rel")"
    cp -p "$f" "$HEAVY_ARTIFACT_OUT/$rel"
    n=$((n + 1))
  done < <(find .lake/build -type f -path "*/$path.*" -print0)
  [[ $n -gt 0 ]] || { echo "FAIL: no artifacts for $m"; exit 1; }
  (cd "$HEAVY_ARTIFACT_OUT" && find build -type f -path "*/$path.*" -print0 | sort -z | xargs -0 sha256sum) \
    > "$HEAVY_ARTIFACT_OUT/$m.sha256"
  echo "== $n artifact files of $m in $HEAVY_ARTIFACT_OUT"
fi
echo "OK: $m built in the sandbox and replayed"

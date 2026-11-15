#!/usr/bin/env bash
# One CI matrix entry of a heavy library (decision 57): `heavy-module (<name>)` for lean_lib
# HeavyProofs, `twin-module (<name>)` for lean_lib TwinChecks. An entry is one module or a
# group of modules (scripts/heavy_closure.py --matrix).
#
# 1. Ask scripts/heavy_closure.py which default-target modules and which library modules the
#    entry's modules need.
# 2. Build the default-target dependencies (outside the sandbox, as the main CI job does).
# 3. Build the library dependencies and the entry's modules one at a time in the bwrap sandbox,
#    each build checked to change only its own artifacts (scripts/heavy_build.sh).
# 4. Unless SKIP_REPLAY=1: kernel replay of each of the entry's modules with `leanchecker` in
#    the sandbox (`leanchecker M` replays only M's own declarations; dependencies are replayed by
#    the entries that own them).
# 5. If HEAVY_ARTIFACT_OUT is set, copy each entry module's own artifacts (`.lake/build/**/M.*`)
#    to $HEAVY_ARTIFACT_OUT/build/... with one sha256 list per module, for the aggregate job.
#
# Usage: scripts/check_heavy_module.sh [--lib <lean_lib>] <module>...   (needs bwrap)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.elan/bin:$PATH"
lake_bin=$(command -v lake)
lib=HeavyProofs
if [[ "${1:-}" == --lib ]]; then lib=${2:?--lib needs a value}; shift 2; fi
[[ $# -gt 0 ]] || { echo "usage: check_heavy_module.sh [--lib <lean_lib>] <module>..."; exit 2; }
own=("$@")

deps=$(python3 scripts/heavy_closure.py --from-lakefile --lib "$lib" --deps "${own[@]}")
read -r -a light <<< "$(sed -n 's/^light //p' <<< "$deps")"
read -r -a heavy <<< "$(sed -n 's/^heavy //p' <<< "$deps")"

echo "== default-target dependencies (${#light[@]} modules)"
if [[ ${#light[@]} -gt 0 ]]; then lake build --wfail "${light[@]}"; fi

echo "== $lib dependencies and the entry's modules, sandboxed, one at a time"
scripts/heavy_build.sh "${heavy[@]}"

if [[ "${SKIP_REPLAY:-0}" != 1 ]]; then
  for m in "${own[@]}"; do
    echo "== kernel replay (leanchecker) $m"
    scripts/sandbox.sh "$lake_bin" env leanchecker "$m"
  done
fi

if [[ -n "${HEAVY_ARTIFACT_OUT:-}" ]]; then
  mkdir -p "$HEAVY_ARTIFACT_OUT"
  for m in "${own[@]}"; do
    path=$(echo "$m" | sed 's/\./\//g')
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
    echo "== $n artifact files of $m"
  done
fi
echo "OK: ${own[*]} built in the sandbox$([[ "${SKIP_REPLAY:-0}" == 1 ]] || echo " and replayed")"

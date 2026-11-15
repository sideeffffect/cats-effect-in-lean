#!/usr/bin/env bash
# Install the build artifacts that CI matrix jobs uploaded (scripts/check_heavy_module.sh), for
# an aggregate job (decision 57; review batch 8).
#
# For each given module M: $IN/M.sha256 must exist and match its files. The artifact directory
# must hold exactly the files that these lists name (an unlisted or missing file is an error).
# Then the listed files, all regular files, are copied into .lake. The combined list goes to
# <out.sha>; after its own sandboxed builds the caller checks with it that nothing installed was
# rebuilt or changed (`(cd .lake && sha256sum -c <out.sha>)`).
#
# Usage: scripts/install_artifacts.sh <in-dir> <out.sha> <module>...   (from the repository root)
set -euo pipefail
in=${1:?usage: install_artifacts.sh <in-dir> <out.sha> <module>...}
out=${2:?usage: install_artifacts.sh <in-dir> <out.sha> <module>...}
shift 2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
: > "$out"
mkdir -p "$in"
for m in "$@"; do
  [[ -f "$in/$m.sha256" ]] || { echo "FAIL: no artifacts for $m (matrix job missing)"; exit 1; }
  (cd "$in" && sha256sum --quiet -c "$m.sha256") || { echo "FAIL: artifacts of $m corrupted"; exit 1; }
  cat "$in/$m.sha256" >> "$out"
done
sed -E 's/^[0-9a-f]+  //' "$out" | sort > "$tmp/listed.txt"
(cd "$in" && find . -mindepth 1 -not -type d -not -name '*.sha256' -printf '%P\n' | sort) > "$tmp/present.txt"
if ! cmp -s "$tmp/listed.txt" "$tmp/present.txt"; then
  echo "FAIL: artifact files and sha256 lists differ:"
  diff "$tmp/listed.txt" "$tmp/present.txt" | head -20 || true
  exit 1
fi
while IFS= read -r rel; do
  [[ -f "$in/$rel" && ! -L "$in/$rel" ]] || { echo "FAIL: $rel is not a regular file"; exit 1; }
  mkdir -p ".lake/$(dirname "$rel")"
  cp -p "$in/$rel" ".lake/$rel"
done < "$tmp/listed.txt"
echo "== installed $(wc -l < "$tmp/listed.txt") artifact files of $# modules"

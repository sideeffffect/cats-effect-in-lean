#!/usr/bin/env bash
# Run all bug reproducers (reproducers/<id>/Repro.scala) with scala-cli and check the last line.
#
# Usage:
#   scripts/run_reproducers.sh                 # Cats Effect 3.7.1 (pinned); each must print "REPRODUCED <id>"
#   CE_VERSION=3.7-2f94201-SNAPSHOT scripts/run_reproducers.sh
#                                              # other version (for example a publishLocal snapshot);
#                                              # prints the result, does not fail on "NOT REPRODUCED"
#   scripts/run_reproducers.sh CE-0001 ...     # only these ids
#
# Exit code (pinned version): 0 if all print "REPRODUCED <id>" as last line, 1 otherwise.
# Exit code (CE_VERSION set): 0 if each last line is "REPRODUCED <id>" or "NOT REPRODUCED <id>".
#
# Not in CI yet: scala-cli downloads a JVM, Scala and Cats Effect on the first run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PINNED="3.7.1"
VERSION="${CE_VERSION:-$PINNED}"
SCALA_CLI="${SCALA_CLI:-$(command -v scala-cli || echo "$HOME/.local/share/coursier/bin/scala-cli")}"

if [ "$#" -gt 0 ]; then
  ids=("$@")
else
  ids=()
  for d in "$ROOT"/reproducers/*/; do
    [ -f "$d/Repro.scala" ] && ids+=("$(basename "$d")")
  done
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail=0
for id in "${ids[@]}"; do
  src="$ROOT/reproducers/$id/Repro.scala"
  if [ ! -f "$src" ]; then
    echo "MISSING $id ($src)"; fail=1; continue
  fi
  mkdir -p "$work/$id"
  # Replace the pinned Cats Effect version in the `//> using dep` lines only.
  sed -E "s#^(//> using dep org\.typelevel::cats-effect[a-z-]*):${PINNED}\$#\1:${VERSION}#" "$src" > "$work/$id/Repro.scala"
  out="$("$SCALA_CLI" run --server=false "$work/$id/Repro.scala" 2>&1 || true)"
  last="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1)"
  echo "== $id (cats-effect $VERSION)"
  printf '%s\n' "$out" | grep -v -E '^(Compiling|Compiled|Downloading|Downloaded)|\[90m' || true
  if [ "$VERSION" = "$PINNED" ]; then
    if [ "$last" != "REPRODUCED $id" ]; then
      echo "FAIL $id: last line is '$last', expected 'REPRODUCED $id'"; fail=1
    fi
  else
    if [ "$last" != "REPRODUCED $id" ] && [ "$last" != "NOT REPRODUCED $id" ]; then
      echo "FAIL $id: last line is '$last'"; fail=1
    fi
  fi
done
exit "$fail"

#!/usr/bin/env bash
# Run the difftest runner without sbt start-up cost.
# Usage: difftest/run.sh [FILE.jsonl ...]   (no files: read stdin)
# The first call (or a call after a source change) builds with sbt and caches the class path.
set -euo pipefail
args=()
for a in "$@"; do args+=("$(realpath "$a")"); done
dir=$(cd "$(dirname "$0")" && pwd)
cp_file=$dir/target/classpath.txt
if [[ ! -f $cp_file ]] || [[ -n $(find "$dir/src/main" "$dir/build.sbt" -newer "$cp_file" -print -quit) ]]; then
  mkdir -p "$dir/target"
  (cd "$dir" && sbt -batch -error "export Runtime/fullClasspath" < /dev/null | tail -n 1 > "$cp_file.tmp")
  mv "$cp_file.tmp" "$cp_file"
fi
exec java -cp "$(cat "$cp_file")" cats.effect.difftest.Main "${args[@]}"

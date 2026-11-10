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
  # sbt can print terminal escapes (for example ESC[0J) after the class path line,
  # so select the class path line itself, not the last line.
  (cd "$dir" && sbt -batch -error -Dsbt.color=false -Dsbt.supershell=false "export Runtime/fullClasspath" < /dev/null \
    | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -E '(\.jar|/classes)(:|$)' | tail -n 1 > "$cp_file.tmp")
  [[ -s $cp_file.tmp ]] || { echo "run.sh: could not read the class path from sbt" >&2; exit 1; }
  mv "$cp_file.tmp" "$cp_file"
fi
exec java -cp "$(cat "$cp_file")" cats.effect.difftest.Main "${args[@]}"

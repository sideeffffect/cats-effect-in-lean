#!/usr/bin/env bash
# Build heavy modules (decision 55) one at a time, each in the bwrap sandbox
# (scripts/sandbox.sh), and check after each build that the build changed nothing but the
# module's own artifacts (review batch 7, gap 1).
#
# For each module M, in the given order (imports first):
#   1. hash every file under .lake (build outputs and lake's own config) except M's own
#      artifacts (`<dir>/M.*`);
#   2. `lake build --wfail M` in the sandbox (read-only file system except .lake, no network);
#   3. fail if a hashed file changed, appeared or disappeared, or if the git work tree changed.
# So build-time code of M cannot change the sources, the inventory, the tools, or the
# artifacts of any other module (dependencies included) that later steps rely on.
#
# The caller must build the default-target dependencies first (outside the sandbox, as the main
# CI job does): a sandboxed build that writes their artifacts fails the check.
#
# Usage: scripts/heavy_build.sh <module>...   (from the repository root)
set -euo pipefail
export PATH="$HOME/.elan/bin:$PATH"
lake_bin=$(command -v lake)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

own_re() { # regex for the artifacts of module $1
  printf '/%s\\.' "$(echo "$1" | sed 's/\./\//g')"
}
manifest() { # every file under .lake (build outputs, lake config) except the artifacts of module $1
  find .lake -type f -not -name lake.lock -print0 | sort -z | xargs -0 -r sha256sum \
    | grep -v -E "$(own_re "$1")" || true
}
tree_state() {
  git status --porcelain=v1 --untracked-files=all
  git diff HEAD
}

for m in "$@"; do
  echo "== sandboxed build $m"
  manifest "$m" > "$tmp/before.sha"
  tree_state > "$tmp/tree_before"
  scripts/sandbox.sh "$lake_bin" build --wfail "$m"
  manifest "$m" > "$tmp/after.sha"
  tree_state > "$tmp/tree_after"
  if ! cmp -s "$tmp/before.sha" "$tmp/after.sha"; then
    echo "FAIL: building $m changed build files outside its own artifacts:"
    diff "$tmp/before.sha" "$tmp/after.sha" | head -20 || true
    exit 1
  fi
  if ! cmp -s "$tmp/tree_before" "$tmp/tree_after"; then
    echo "FAIL: building $m changed the work tree"; exit 1
  fi
done

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
manifest() { # every entry under .lake (build outputs, lake config) except the artifacts of module $1:
  # regular files by content hash; symlinks and other non-directory entries by type and target
  # (review batch 8: a symlink must not slip past the check)
  {
    find .lake -type f -not -name lake.lock -print0 | sort -z | xargs -0 -r sha256sum
    find .lake -not -type f -not -type d -printf '%y %p -> %l\n' | sort
  } | grep -v -E "$(own_re "$1")" || true
}
tree_state() {
  git status --porcelain=v1 --untracked-files=all
  git diff HEAD
}

# Let lake elaborate its configuration now, outside the sandbox (as every other lake call of
# the job does), so that a stale `.lake/config` from the CI cache is refreshed before the first
# snapshot. CI run 43651882144: the two jobs whose module has no default-target dependency ran
# no lake command before the first sandboxed build, so lake re-elaborated the changed lakefile
# inside it and `.lake/config/0/lakefile.olean{,.trace}` changed. The config stays in the hash
# check: after this step any change to it fails.
"$lake_bin" env true

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

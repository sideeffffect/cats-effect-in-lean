#!/usr/bin/env bash
# Run a command in a bwrap sandbox like the one of `lake check` (decision 55, review batch 7
# gap 1): the whole file system is read-only, except the repository's `.lake` directory and a
# private /tmp; no network. So build-time code (macros, `#eval`, `initialize`) cannot change the
# sources, the inventory, the audit tool sources or anything outside `.lake`.
# Callers must not trust anything under `.lake` that a sandboxed command could have written
# (scripts/check_heavy_proofs.sh copies the audit binary out first and hashes the rest).
#
# Needs bubblewrap with user namespaces (CI: scripts/setup-bwrap-apparmor.sh).
# Usage: scripts/sandbox.sh <command> [args...]   (run from the repository root)
set -euo pipefail
repo=$(pwd)
[[ -d "$repo/.lake" ]] || { echo "sandbox.sh: run from the repository root (no .lake)"; exit 2; }
# order matters: the private /tmp first, then the repository again (read-only; it may live
# under /tmp), then its writable .lake
exec bwrap \
  --ro-bind / / \
  --dev /dev \
  --proc /proc \
  --tmpfs /tmp \
  --ro-bind "$repo" "$repo" \
  --bind "$repo/.lake" "$repo/.lake" \
  --unshare-net \
  --unshare-pid \
  --die-with-parent \
  --chdir "$repo" \
  -- "$@"

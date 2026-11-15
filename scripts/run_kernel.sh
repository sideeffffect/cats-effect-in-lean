#!/usr/bin/env bash
# Run one kernel over a Lean export (decision 57: paranoid-heavy.yml, one matrix job per
# kernel). The commands mirror `lake check --paranoid` in Lean v4.35.0
# (src/lean/lake/Lake/CLI/Check.lean, `bundledKernels`, `runExternalKernel`): same executables,
# same arguments, the same nanoda config file, LEAN_ABORT_ON_PANIC=1, in a bwrap sandbox.
#
# Kernels: default (via `lake check --from-export`: Lean's kernel plus the axiom check),
#          lean-paranoid, lean4lean, nanoda, con-leche, con-ron.
# Usage: scripts/run_kernel.sh <kernel> <export.ndjson>   (from the repository root)
set -euo pipefail
export PATH="$HOME/.elan/bin:$PATH"
kernel=${1:?usage: run_kernel.sh <kernel> <export.ndjson>}
export_file=$(realpath "${2:?usage: run_kernel.sh <kernel> <export.ndjson>}")
mkdir -p .lake
bin=$(lake env printenv LEAN_SYSROOT 2>/dev/null || true)
if [[ -z "$bin" ]]; then bin=$(dirname "$(dirname "$(lake env which lean)")"); fi
bin=$bin/bin

run() { # sandboxed, export readable, nothing writable but .lake and a private /tmp
  LEAN_ABORT_ON_PANIC=1 scripts/sandbox.sh "$@"
}

case "$kernel" in
  default)
    # Lean's own kernel and the axiom check (only propext, Classical.choice, Quot.sound);
    # `lake check` sandboxes the kernel itself
    lake check --from-export "$export_file"
    ;;
  lean-paranoid) run "$bin/leanchecker-paranoid" --silent --from-export "$export_file" ;;
  lean4lean) run "$bin/lean4lean" --import "$export_file" ;;
  con-leche) run "$bin/con-leche" "$export_file" ;;
  con-ron) run "$bin/con-ron" "$export_file" ;;
  nanoda)
    cfg=.lake/nanoda-config.json
    cat > "$cfg" <<EOF
{"use_stdin":false,"export_file_path":"$export_file","permitted_axioms":["propext","Classical.choice","Quot.sound"],"unpermitted_axiom_hard_error":false,"num_threads":4,"nat_extension":true,"string_extension":true}
EOF
    run "$bin/nanoda_bin" "$cfg"
    ;;
  *) echo "unknown kernel $kernel"; exit 2 ;;
esac
echo "OK: $kernel kernel accepts $export_file"

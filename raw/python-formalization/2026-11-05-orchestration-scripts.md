# python-formalization orchestration scripts and build-pod config (verbatim)

> Source: https://github.com/Broyojo/python-formalization/blob/main/scripts
> Collected: 2026-11-10
> Published: 2026-11-05

Files: scripts/r, scripts/merge_module.sh, scripts/merge_batch.sh, scripts/merge_and_cover.sh, scripts/update_coverage.sh, scripts/audit.sh, sky/builder.yaml, sky/watchdog.sh, plus docstrings of check_coverage.py, list_python_functions.py, check_bugs.py.

## scripts/r

````
#!/usr/bin/env bash
# Run a command on the build cluster instead of this machine. Syncs the current
# git worktree to the pod, then runs the command there from the same relative
# directory. The pod holds only caches; this checkout stays the source of truth.
#   scripts/r lake build          (from lean/)
#   scripts/r python3 difftest/ipaddress_diff.py --cases 50000
set -euo pipefail
cluster=${PYLEAN_CLUSTER:-pylean}
root=$(git rev-parse --show-toplevel)
rel=$(git rev-parse --show-prefix)
name=$(basename "$root")
base=python-formalization

ssh -q "$cluster" "mkdir -p pf/wt/$name"
rsync -az --delete --exclude .git --exclude .claude --exclude vendor --exclude .lake \
    --exclude __pycache__ "$root/" "$cluster:pf/wt/$name/"

cmd=$(printf '%q ' "$@")
# A new worktree starts from the main checkout's build cache, so it only
# rebuilds what it changed.
exec ssh -q "$cluster" "source pf/env.sh
if [ ! -d pf/wt/$name/lean/.lake ] && [ -d pf/wt/$base/lean/.lake ]; then
    cp -a pf/wt/$base/lean/.lake pf/wt/$name/lean/.lake
fi
cd pf/wt/$name/$rel && $cmd"
````

## scripts/merge_module.sh

````
#!/usr/bin/env bash
# Merge a module agent's branch after checking it only touched its own paths,
# then run the full audit. Usage: scripts/merge_module.sh <branch> <Module> <key>
# e.g. scripts/merge_module.sh worktree-agent-abc Fractions fractions
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
branch=$1 mod=$2 key=$3
base=$(git merge-base HEAD "$branch")

# ALLOW names extra files a person has checked, such as a fix to a shared table.
outside=$(git diff --name-only "$base" "$branch" | grep -vxE "${ALLOW:-^$}" | grep -vE \
  "^(\.gitignore|lean/PyLean/$mod\.lean|lean/PyLean/$mod/.*|difftest/${key}(_[a-z0-9_]+)?\.py|bugs/${key}-[^/]*\.yaml|coverage/registry\.tsv|coverage/methods/[^/]*\.tsv|coverage/review/[^/]*\.tsv)$" || true)
if [ -n "$outside" ]; then
    echo "FAIL $branch touches files outside its module:"
    echo "FAIL path: $outside"
    exit 1
fi
git diff --stat "$base" "$branch" | tail -1
if ! git merge --no-ff -q -m "Merge $mod module ($branch)" "$branch"; then
    # A module's own rows win in coverage/methods, and the registry is regenerated
    # after the merge anyway. Reviews always keep main's verdicts: an author must
    # never overwrite an independent review.
    conflicts=$(git diff --name-only --diff-filter=U)
    if echo "$conflicts" | grep -qv '^coverage/'; then
        echo "FAIL $branch has conflicts outside coverage/:"
        echo "$conflicts"
        git merge --abort
        exit 1
    fi
    for f in $conflicts; do
        case "$f" in
            coverage/review/*) git checkout --ours -- "$f" ;;
            *) git checkout --theirs -- "$f" ;;
        esac
        git add "$f"
    done
    git commit -q --no-edit
fi
# Batch merges set SKIP_AUDIT and run one full audit afterwards.
[ -n "${SKIP_AUDIT:-}" ] || scripts/r scripts/audit.sh
````

## scripts/merge_batch.sh

````
#!/usr/bin/env bash
# Merge several modules, then run one audit and one coverage update. The audit
# takes long enough that one per merge is wasteful, and modules are each verified
# on their own branch first. Arguments are branch:Module:key triples.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
until mkdir .git/merge.lock 2>/dev/null; do sleep 10; done
trap 'rmdir .git/merge.lock' EXIT
for spec in "$@"; do
    IFS=: read -r branch mod key <<< "$spec"
    echo "=== $mod"
    SKIP_AUDIT=1 scripts/merge_module.sh "$branch" "$mod" "$key" 2>&1 | tail -3 | cut -c1-110
done
git status --short | grep -v '^??' | head -5
log=$(mktemp)
scripts/r scripts/audit.sh > "$log" 2>&1
echo "audit exit $?"
grep -E 'Build completed|properties:|^FAIL|AUDIT PASSED|not reproduced' "$log" | cut -c1-120 | tail -8
scripts/update_coverage.sh "batch merge" 2>&1 | tail -10 | cut -c1-125
````

## scripts/merge_and_cover.sh

````
#!/usr/bin/env bash
# Merge a module and update coverage, one at a time: audits share a directory on
# the pod, so overlapping ones are meaningless. Usage as for merge_module.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
until mkdir .git/merge.lock 2>/dev/null; do sleep 10; done
trap 'rmdir .git/merge.lock' EXIT
scripts/merge_module.sh "$1" "$2" "$3" 2>&1 |
    grep -E '^FAIL|AUDIT PASSED|Build completed|properties|not reproduced|NOT REPRO|error:|CONFLICT|touches' | cut -c1-130 | tail -8
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
    echo "MERGE GATE FAILED ($status) for $2"
    exit "$status"
fi
scripts/update_coverage.sh "$2 merged"
````

## scripts/update_coverage.sh

````
#!/usr/bin/env bash
# After a merge: export the registry on the pod, settle coverage rows and commit.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
scripts/r bash -c 'cd lean && lake env lean Report.lean' 2>/dev/null > coverage/registry.tsv
python3 scripts/check_coverage.py --prefill 2>&1 | tail -9 | cut -c1-100
git add -A coverage
git commit -qm "Update coverage: ${1:-after merge}

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YWjP4qJwNFDpaToxpZGnPi"
````

## scripts/audit.sh

````
#!/usr/bin/env bash
# Build the Lean project, reject forbidden proof escapes, audit the registry,
# re-run the differential tests, and check that every bug still reproduces.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

(cd lean && lake build)

if grep -rnwE 'sorry|admit|native_decide|bv_decide|ofReduceBool|implemented_by|extern' \
    --include='*.lean' lean/PyLean lean/PyLean.lean; then
    echo "FAIL forbidden proof escape found (see lines above)"
    exit 1
fi

(cd lean && lake env lean Audit.lean)
# Difftests run in parallel, and every one runs, so one failing harness cannot
# hide the results of the others. Each module's agent has already run its own at
# 50000 cases on several seeds; this is the cross-module check on merged code.
cases=${AUDIT_CASES:-20000}
logs=$(mktemp -d)
ls difftest/*_diff.py | xargs -P 8 -I{} sh -c \
    'n=$(basename {}); python3 {} --cases '"$cases"' > '"$logs"'/$n.log 2>&1; echo "$? $n $(tail -1 '"$logs"'/$n.log | cut -c1-60)"' \
    | sort -k2 | tee "$logs/status"
# A module still moving to 3.15.2 is listed in coverage/difftest-migrating.txt, one
# script per line with no blank lines. Its failures show above but do not fail the
# audit. The owner removes the line once the difftest passes on 3.15.2.
touch coverage/difftest-migrating.txt
failed=$(awk '$1 != 0 { print $2 }' "$logs/status" | grep -vxFf coverage/difftest-migrating.txt | tr '\n' ' ' || true)
python3 scripts/check_bugs.py || failed="$failed check_bugs"
if [ -n "$failed" ]; then
    echo "FAIL audit:$failed"
    exit 1
fi
echo "AUDIT PASSED"
````

## sky/builder.yaml

````
# Build host for Lean proofs and differential tests. Pinned to our own
# Kubernetes cluster: never let this fail over to a paid cloud. CPU only, so it
# takes no GPUs, and it leaves 32 CPUs on the node for other jobs.
#
# All state under ~/pylean is a disposable cache. The disk is shared with every
# other job on the node, so the watchdog stops builds if free space runs low.
#   sky launch -c pylean sky/builder.yaml -i 5 --down -y -d
name: pylean-builder

workdir: .

resources:
  infra: k8s/a100
  cpus: 64
  memory: 512
  disk_size: 200

setup: |
  set -euo pipefail
  SUDO=$(command -v sudo || true)
  S=$HOME/pylean
  mkdir -p $S/pf $S/elan $S/tmp
  ln -sfn $S/pf $HOME/pf
  ln -sfn $S/elan $HOME/.elan
  export TMPDIR=$S/tmp
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq build-essential git curl rsync zstd pkg-config \
    libssl-dev zlib1g-dev libbz2-dev liblzma-dev libffi-dev libsqlite3-dev libreadline-dev libmpdec-dev

  # Lean, at the toolchain the project pins.
  curl -sSfL https://elan.lean-lang.org/elan-init.sh -o /tmp/elan-init.sh
  sh /tmp/elan-init.sh -y --default-toolchain leanprover/lean4:v4.35.0
  export PATH=$HOME/.elan/bin:$PATH
  lean --version

  # The two interpreters the project tests against, built from source so the
  # stdlib includes test.support, which some difftests import.
  V=$HOME/pf/vendor
  mkdir -p $V
  [ -d $V/cpython-3.15 ] || git clone -q --depth 1 --branch v3.15.2 https://github.com/python/cpython.git $V/cpython-3.15
  if [ ! -x $HOME/pf/py315/bin/python3 ]; then
    (cd $V/cpython-3.15 && ./configure --quiet --prefix=$HOME/pf/py315 && make -j32 -s >build.log 2>&1 && make -s install >>build.log 2>&1)
  fi
  if ! $V/cpython-main/python -c "import _decimal" 2>/dev/null; then
    mkdir -p $V/cpython-main
    (cd $V/cpython-main && git init -q && git fetch -q --depth 1 https://github.com/python/cpython.git ef1fce0a69a19360643fb82ea3545ede21495c73 && git checkout -q FETCH_HEAD && ./configure --quiet && make -j32 -s >build.log 2>&1)
  fi
  ln -sf python $V/cpython-main/python.exe
  $HOME/pf/py315/bin/python3 -c "import sys, _datetime, _decimal, _bisect, _heapq, _pickle, _json, _ctypes, test.support; print(sys.version)"
  $V/cpython-main/python -c "import sys, _datetime, _decimal, _bisect, _heapq, _pickle, _json; print(sys.version)"

  # Commands sent from the authors' Mac name vendor/ by its absolute path ($PF in AGENTS.md); make it valid here.
  ROOT=/Users/broyojo/code/projects/python-formalization
  $SUDO mkdir -p $ROOT
  $SUDO ln -sfn $V $ROOT/vendor

  # Remote commands get these tools on PATH.
  cat > $HOME/pf/env.sh <<'ENV'
  export PATH=$HOME/pf/py315/bin:$HOME/.elan/bin:$PATH
  export TMPDIR=$HOME/pylean/tmp
  ENV
  sed -i 's/^  //' $HOME/pf/env.sh

# Keeps the pod alive while Lean runs; see the comment in the script.
run: |
  echo builder ready
  bash sky/watchdog.sh
````

## sky/watchdog.sh

````
#!/usr/bin/env bash
# The pod's only SkyPilot job. SkyPilot does not count work done over ssh as
# activity, so while this runs the pod is not idle; it exits once no Lean
# process has run for two hours, and autostop then tears the pod down.
# It also kills any Lean or pydiff process above 64 GB of resident memory, so one
# runaway elaboration or difftest case cannot take the pod down. Virtual-memory limits do not work here:
# Lean reserves about ten times what it uses, which starves it of threads.
# The disk is shared with other jobs on the node, so it stops all builds if
# free space falls below 30 GB.
idle=0
while [ "$idle" -lt 720 ]; do
    sleep 10
    if pgrep -x lean >/dev/null; then idle=0; else idle=$((idle + 1)); fi
    free=$(df --output=avail -BG / | tail -1 | tr -dc 0-9)
    if [ "$free" -lt 30 ]; then
        echo "$(date -u) disk at ${free} GB free, stopping builds" >> "$HOME/pf/watchdog.log"
        pkill -x lean; pkill -x lake; pkill -x pydiff
    fi
    ps -eo pid=,rss=,comm= | awk '($3 == "lean" || $3 == "pydiff") && $2 > 64 * 1024 * 1024 { print $1, $2 }' |
    while read -r pid rss; do
        echo "$(date -u) killed pid $pid at $((rss / 1048576)) GB" >> "$HOME/pf/watchdog.log"
        kill -9 "$pid"
    done
done
````

## scripts/check_coverage.py (module docstring only)

````
Validate coverage/methods/*.tsv against the registry and report whole-Python coverage.

Export the registry first, on the pod:
  scripts/r bash -c 'cd lean && lake env lean Report.lean' > coverage/registry.tsv

  python3 scripts/check_coverage.py             validate and print totals
  python3 scripts/check_coverage.py --prefill   settle todo rows from registry function names

--prefill settles a row only on a unique match, in the entry's own file first
and then across the whole manifest. Ambiguous names become `candidates:` notes
for a person or review agent to settle. Exits 1 on a malformed row, and
with --strict while any todo remains.

`modelled` is a claim by the author of the entry. It counts as reviewed only
once coverage/review/ says FAITHFUL (see coverage/REVIEW_PROMPT.md).
````

## scripts/list_python_functions.py (module docstring only)

````
Write the whole-Python function inventory to coverage/methods/*.tsv.

The inventory is the denominator of "formalize Python": every function, method,
opcode and grammar rule in the pinned CPython source gets one row, with status
modelled, excluded (with a reason) or todo. Re-running keeps the status, entry
and note of rows that still exist. Sources are parsed, never run.

This is for re-running on the pinned source. It carries a row's status by line
number, so moving to another CPython version goes through scripts/repin.py.

Usage: python3 scripts/list_python_functions.py <cpython-source-root>
````

## scripts/check_bugs.py (module docstring only)

````
Run every bugs/*.yaml reproducer on this Python and check it still reproduces.

Each reproducer must print `REPRODUCED <id>` when the bug is present. Usage:
  python3 scripts/check_bugs.py [--python /path/to/python] [bug-id ...]
Exits non-zero if a bug no longer reproduces (fixed upstream, or a broken reproducer).
Records listed in coverage/gone-in-3.15.txt are skipped unless named: they are 3.14.7
behaviour that 3.15.2 does not have.
````


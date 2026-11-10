#!/usr/bin/env python3
"""Per-op agreement counts for chosen ops (Phase 6, track R; decision 51).

Generates replay cases with `gen.gen_case` (optionally with some weights multiplied by a
factor), runs Scala and Lean, and counts, for each op in `--ops`, the cases that use the op and
agree on all compared fields. The weights only change how often a production is picked; no
generated case is dropped. Exit code 1 if any case is a mismatch, a harness error, a hang or a
generator bug. Unsupported cases (an op that the Lean model does not mirror yet, for example
`timeoutTo` with a user fallback) are counted and printed, never counted as agreeing.

Usage:
  opcount.py --seeds 1 2 3 --n 20000 --ops race raceOutcome both bothOutcome \
             --boost race=4 raceOutcome=4 both=4 bothOutcome=4 tpl_comb=4 tpl_combCancel=4 \
             --lean "lake exe cediff"
"""

import argparse
import collections
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drive  # noqa: E402
import gen  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, nargs='+', default=[1, 2, 3])
    ap.add_argument('--n', type=int, default=1000)
    ap.add_argument('--chunk', type=int, default=20000)
    ap.add_argument('--max-size', type=int, default=40)
    ap.add_argument('--ops', nargs='+', required=True)
    ap.add_argument('--boost', nargs='*', default=[], help='weight=factor')
    ap.add_argument('--lean', required=True)
    a = ap.parse_args(argv)
    weights = dict(gen.WEIGHTS)
    for b in a.boost:
        k, f = b.split('=')
        weights[k] = weights[k] * float(f)
    per_op = {op: collections.Counter() for op in a.ops}
    bins = collections.Counter()
    bad = []
    t0 = time.time()
    for seed in a.seeds:
        for start in range(0, a.n, a.chunk):
            cases = [gen.gen_case(seed, i, max_size=a.max_size, weights=weights)
                     for i in range(start, min(a.n, start + a.chunk))]
            s = drive.run_scala(cases)
            lo = drive.run_lean(a.lean, cases)
            for c in cases:
                b, d = drive.compare(c, s.get(c['id']), lo.get(c['id']))
                bins[b] += 1
                used = [op for op in a.ops if drive._has_op(c['prog'], (op,))]
                for op in used:
                    per_op[op][(seed, b)] += 1
                if b not in ('agree', 'unsupported'):
                    bad.append((c['id'], b, d))
            print(f"seed {seed}: {min(a.n, start + a.chunk)} cases, {time.time() - t0:.0f} s", flush=True)
    print(f"cases {sum(bins.values())}: " + "  ".join(f"{b} {k}" for b, k in bins.most_common()))
    for op in a.ops:
        agree = {sd: per_op[op][(sd, 'agree')] for sd in a.seeds}
        unsup = sum(k for (sd, b), k in per_op[op].items() if b == 'unsupported')
        other = sum(k for (sd, b), k in per_op[op].items() if b not in ('agree', 'unsupported'))
        print(f"  {op:12} agree {sum(agree.values()):7}  per seed {agree}  unsupported {unsup}  other {other}")
    for x in bad[:20]:
        print("  problem:", x)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Fast self-test of the difftest generator and driver (< 60 s). Runs in CI after `sbt test`.

Checks:
1. The type checker accepts the hand-written golden cases and rejects ill-typed programs.
2. The generator is deterministic, and case i does not depend on the number of cases.
3. Generated cases are well-typed, and the Scala runner gives no decode error, no
   non-UserError error (TypeError, decision 8), and no hang.
4. Scala replay and testcontrol runs are deterministic (each case twice, same line).
5. Driver with a fake Lean side (mock_lean.py): bins, shrinking, corpus save and rerun.
6. The regression corpus (difftest/corpus/) still gives the stored Scala results.
"""

import json
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import drive  # noqa: E402
import gen  # noqa: E402
from typecheck import TypeErr, check_prog, well_typed  # noqa: E402

N = 400
SEED = 20261110


def check(cond, msg):
    if not cond:
        raise SystemExit(f"FAIL: {msg}")
    print(f"ok: {msg}")


def main():
    t0 = time.time()
    # 1. type checker
    basic = [json.loads(x) for x in (drive.REPO / 'difftest/cases/basic.jsonl').read_text().splitlines() if x.strip()]
    check(all(well_typed(c['prog']) for c in basic), f"type checker accepts all {len(basic)} golden cases")
    N1 = {'t': 'nat', 'v': 1}
    bad = [
        {'op': 'map', 'e': {'op': 'pure', 'v': {'t': 'pair', 'a': N1, 'b': N1}}, 'fn': 2},  # inc on a pair
        {'op': 'bind', 'x': 'r', 'e': {'op': 'refNew', 'v': N1}, 'k': {'op': 'join', 'f': {'t': 'var', 'x': 'r'}}},
        {'op': 'poll', 'poll': 'p', 'e': {'op': 'cede'}},
        {'op': 'bind', 'x': 'r', 'e': {'op': 'refNew', 'v': N1}, 'k': {'op': 'refModify', 'r': {'t': 'var', 'x': 'r'}, 'fn': 0}},
        {'op': 'case', 'on': N1, 'l': 'a', 'lk': {'op': 'cede'}, 'r': 'b', 'rk': {'op': 'cede'}},
        {'op': 'async', 'cbs': [{'when': 'sync', 'ok': N1}, {'when': 'later', 'ok': {'t': 'unit'}}]},
    ]
    for p in bad:
        try:
            check_prog(p)
            check(False, f"type checker rejects {json.dumps(p)}")
        except TypeErr:
            pass
    check(True, f"type checker rejects {len(bad)} ill-typed programs")

    # 2. generator determinism
    a = gen.gen_cases(SEED, N)
    b = gen.gen_cases(SEED, N)
    check([gen.dumps(c) for c in a] == [gen.dumps(c) for c in b], "generator is deterministic")
    check(gen.dumps(gen.gen_case(SEED, N // 2)) == gen.dumps(a[N // 2]), "case i does not depend on N")

    # 3 + 4. Scala runs: no generator bug, deterministic
    tcs = [gen.to_testcontrol(c, t) for c in a[:N // 2] for t in (1, 2)]
    cases = a + tcs
    s1 = drive.run_scala(cases)
    s2 = drive.run_scala(cases)
    probs = [(c['id'], drive.scala_problem(s1.get(c['id']))) for c in cases if drive.scala_problem(s1.get(c['id']))]
    check(not probs, f"{len(cases)} Scala runs: no decode error, TypeError, or hang {probs[:3]}")
    nd = [c['id'] for c in cases if s1[c['id']]['_raw'] != s2[c['id']]['_raw']]
    check(not nd, f"Scala replay and testcontrol runs are deterministic {nd[:3]}")
    outs = {s1[c['id']]['outcome']['t'] for c in a}
    check({'succeeded', 'errored', 'canceled', 'blocked'} <= outs, f"replay outcomes cover {sorted(outs)}")

    # 5. driver with a fake Lean side
    mock = f"{sys.executable} {HERE / 'mock_lean.py'}"
    sample = cases
    lo = drive.run_lean(mock, sample)
    bins = {}
    for c in sample:
        b_, d = drive.compare(c, s1[c['id']], lo.get(c['id']))
        bins.setdefault(b_, []).append((c, d))
    check({'agree', 'mismatch', 'unsupported'} <= set(bins), f"bins with mock Lean: { {k: len(v) for k, v in bins.items()} }")
    mm = [(c, d) for c, d in bins['mismatch'] if c['mode'] == 'replay']
    check(bool(mm), "mock gives a replay mismatch")
    c, field = max(mm, key=lambda x: gen.size_of(x[0]['prog']))  # the largest: a real shrink
    sc = drive.shrink(c, mock, field)
    check(gen.size_of(sc['prog']) <= 4 and gen.size_of(sc['prog']) <= gen.size_of(c['prog']),
          f"shrink {c['id']}: size {gen.size_of(c['prog'])} -> {gen.size_of(sc['prog'])}, "
          f"choices {len(c.get('choices', []))} -> {len(sc.get('choices', []))}")
    with tempfile.TemporaryDirectory() as d:
        so = drive.run_scala([sc])[sc['id']]
        lo1 = drive.run_lean(mock, [sc])[sc['id']]
        check(drive.compare(sc, so, lo1) == ('mismatch', field), "shrunk case still mismatches")
        drive.save_corpus(sc, so, lo1, field, {'test': True}, Path(d))
        check(drive.main(['corpus', '--corpus-dir', d]) == 0, "corpus rerun (Scala only) passes")
        check(drive.main(['corpus', '--corpus-dir', d, '--lean', mock]) == 1, "corpus rerun flags the mock mismatch")

    # 6. regression corpus
    check(drive.main(['corpus']) == 0, "regression corpus gives the stored Scala results")
    dt = time.time() - t0
    check(dt < 60, f"self-test time {dt:.1f} s")


if __name__ == '__main__':
    main()

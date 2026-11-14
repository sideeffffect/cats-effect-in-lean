#!/usr/bin/env python3
"""Fast self-test of the difftest generator and driver (< 60 s). Runs in CI after `sbt test`.

Checks:
1. The type checker accepts the hand-written golden cases and rejects ill-typed programs.
2. The generator is deterministic, and case i does not depend on the number of cases.
3. Generated cases are well-typed, and the Scala runner gives no decode error, no
   non-UserError error (TypeError, decision 8), and no hang.
4. Scala replay and testcontrol runs are deterministic (each case twice, same line).
   Each format v1 op occurs in enough generated cases (static count).
5. Driver with a fake Lean side (mock_lean.py): bins, shrinking, corpus save and rerun.
6. The regression corpus (difftest/corpus/) still gives the stored Scala results.
7. Run-event coverage (coverage.py, decision 17): each key event in at least COV_MIN of
   COV_N cases (the 3 x 10,000 target is 5 %; a small sample needs a margin), and blocked
   plus fuel outcomes below COV_MAX_STUCK.
"""

import json
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import coverage  # noqa: E402
import drive  # noqa: E402
import gen  # noqa: E402
from typecheck import TypeErr, check_prog, well_typed  # noqa: E402

N = 400
SEED = 20261110
COV_N = 600
COV_MIN = 0.035
COV_MAX_STUCK = 0.25
# Static coverage of the format v1 ops (the 5 x 10,000 target is 5 %). timeoutTo runs on the
# model since track D (weight 0.35 -> 1.2), so it has the same minimum.
V1_OPS = ('syncStep', 'timeout', 'timeoutTo', 'queueNew', 'queueOffer', 'queueTake', 'queueTryTake',
          'allocatedCase', 'rPure', 'rEval', 'rMake', 'rFlatMap')
V1_MIN = 0.03
# Format v2 (track R): each op in at least this share of generated cases (static count)
V2_OPS = ('race', 'raceOutcome', 'both', 'bothOutcome')
V2_MIN = 0.05
V1_MIN_TIMEOUTTO = 0.03
# Share of cases with small IORuntimeConfig thresholds (`runtime`, preempt coverage; 25 %)
RUNTIME_MIN = 0.15
# Format v2 (track G): a lower share is enough (4 more ops share the weight)
V2G_OPS = ('guarantee', 'bracket', 'bracketCase', 'bracketFull')
V2G_MIN = 0.03
# Format v2 (track M): `memoize` comes only from `tpl_memo` (weight 0.4, so the minimums above
# still hold); opcount.py with `--boost tpl_memo=40` gives the 50,000-case runs
V2M_OPS = ('memoize', 'memoGet')
V2M_MIN = 0.01
# Format v2 (track Res): `use`, `allocated`, `Resource.both` (static count)
V2RES_OPS = ('rUse', 'rAllocated', 'rBoth')
V2RES_MIN = 0.02
# Format v2 (batch 6.3)
V2PT_OPS = ('parTraverseN',)
V2PT_MIN = 0.02


def check(cond, msg):
    if not cond:
        raise SystemExit(f"FAIL: {msg}")
    print(f"ok: {msg}")


def main():
    t0 = time.time()
    # 1. type checker
    basic = [json.loads(x) for f in ('basic', 'syncstep', 'resource', 'queue', 'race', 'bracket', 'memoize', 'resuse', 'partraverse')
             for x in (drive.REPO / f'difftest/cases/{f}.jsonl').read_text().splitlines() if x.strip()]
    check(all(well_typed(c['prog']) for c in basic), f"type checker accepts all {len(basic)} golden cases")
    N1 = {'t': 'nat', 'v': 1}
    bad = [
        {'op': 'map', 'e': {'op': 'pure', 'v': {'t': 'pair', 'a': N1, 'b': N1}}, 'fn': 2},  # inc on a pair
        {'op': 'bind', 'x': 'r', 'e': {'op': 'refNew', 'v': N1}, 'k': {'op': 'join', 'f': {'t': 'var', 'x': 'r'}}},
        {'op': 'poll', 'poll': 'p', 'e': {'op': 'cede'}},
        # format v2 (track M): `memoGet` on a `Ref`
        {'op': 'bind', 'x': 'r', 'e': {'op': 'refNew', 'v': N1}, 'k': {'op': 'memoGet', 'm': {'t': 'var', 'x': 'r'}}},
        {'op': 'bind', 'x': 'r', 'e': {'op': 'refNew', 'v': N1}, 'k': {'op': 'refModify', 'r': {'t': 'var', 'x': 'r'}, 'fn': 0}},
        {'op': 'case', 'on': N1, 'l': 'a', 'lk': {'op': 'cede'}, 'r': 'b', 'rk': {'op': 'cede'}},
        {'op': 'async', 'cbs': [{'when': 'sync', 'ok': N1}, {'when': 'later', 'ok': {'t': 'unit'}}]},
        # format v1: syncStep only at the root; resource ops only at resource positions
        {'op': 'seq', 'ps': [{'op': 'syncStep', 'e': {'op': 'cede'}, 'limit': 1}]},
        {'op': 'rPure', 'v': N1},
        # format v2: `both` gives a pair, `race` an either
        {'op': 'bind', 'x': 'x', 'e': {'op': 'both', 'a': {'op': 'cede'}, 'b': {'op': 'cede'}},
         'k': {'op': 'case', 'on': {'t': 'var', 'x': 'x'}, 'l': 'a', 'lk': {'op': 'cede'}, 'r': 'b', 'rk': {'op': 'cede'}}},
        {'op': 'allocatedCase', 'res': {'op': 'cede'}},
        {'op': 'bind', 'x': 'q', 'e': {'op': 'queueNew'}, 'k': {'op': 'seq', 'ps': [
            {'op': 'queueOffer', 'q': {'t': 'var', 'x': 'q'}, 'v': N1},
            {'op': 'queueOffer', 'q': {'t': 'var', 'x': 'q'}, 'v': {'t': 'unit'}}]}},
        # format v2: `use` does not see `y`; `use` does not see the poll of `bracketFull`; `y` is an outcome
        {'op': 'bracketCase', 'acq': {'op': 'cede'}, 'x': 'a', 'use': {'op': 'pure', 'v': {'t': 'var', 'x': 'o'}},
         'y': 'o', 'rel': {'op': 'cede'}},
        {'op': 'bracketFull', 'poll': 'p', 'acq': {'op': 'cede'}, 'x': 'a',
         'use': {'op': 'poll', 'poll': 'p', 'e': {'op': 'cede'}}, 'y': 'o', 'rel': {'op': 'cede'}},
        {'op': 'bracketCase', 'acq': {'op': 'cede'}, 'x': 'a', 'use': {'op': 'cede'}, 'y': 'o',
         'rel': {'op': 'map', 'e': {'op': 'pure', 'v': {'t': 'var', 'x': 'o'}}, 'fn': 2}},
        # format v2 (track Res): `rBoth` only at a resource position; its value is a pair
        {'op': 'rBoth', 'a': {'op': 'rPure', 'v': N1}, 'b': {'op': 'rPure', 'v': N1}},
        {'op': 'rUse', 'res': {'op': 'rBoth', 'a': {'op': 'rPure', 'v': N1}, 'b': {'op': 'rPure', 'v': N1}},
         'x': 'v', 'k': {'op': 'map', 'e': {'op': 'pure', 'v': {'t': 'var', 'x': 'v'}}, 'fn': 2}},
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
    v1cov = {op: sum(1 for c in a if drive._has_op(c['prog'], (op,))) / N for op in V1_OPS}
    low = {op: f for op, f in v1cov.items() if f < (V1_MIN_TIMEOUTTO if op == 'timeoutTo' else V1_MIN)}
    check(not low, f"each format v1 op in >= {V1_MIN:.0%} of {N} cases (timeoutTo {V1_MIN_TIMEOUTTO:.1%}) {low}")
    v2cov = {op: sum(1 for c in a if drive._has_op(c['prog'], (op,))) / N for op in V2_OPS}
    low2 = {op: f for op, f in v2cov.items() if f < V2_MIN}
    check(not low2, f"each format v2 op in >= {V2_MIN:.0%} of {N} cases {low2}")
    rt = sum(1 for c in a if 'runtime' in c) / N
    check(rt >= RUNTIME_MIN, f"small runtime thresholds in {rt:.0%} >= {RUNTIME_MIN:.0%} of {N} cases")
    v2gcov = {op: sum(1 for c in a if drive._has_op(c['prog'], (op,))) / N for op in V2G_OPS}
    lowg = {op: f for op, f in v2gcov.items() if f < V2G_MIN}
    check(not lowg, f"each format v2 op of track G in >= {V2G_MIN:.0%} of {N} cases {lowg}")
    v2mcov = {op: sum(1 for c in a if drive._has_op(c['prog'], (op,))) / N for op in V2M_OPS}
    lowm = {op: f for op, f in v2mcov.items() if f < V2M_MIN}
    check(not lowm, f"each format v2 op of track M in >= {V2M_MIN:.0%} of {N} cases {lowm}")
    v2rcov = {op: sum(1 for c in a if drive._has_op(c['prog'], (op,))) / N for op in V2RES_OPS}
    lowr = {op: f for op, f in v2rcov.items() if f < V2RES_MIN}
    check(not lowr, f"each format v2 op of track Res in >= {V2RES_MIN:.0%} of {N} cases {lowr}")
    v2pcov = {op: sum(1 for c in a if drive._has_op(c['prog'], (op,))) / N for op in V2PT_OPS}
    lowp = {op: f for op, f in v2pcov.items() if f < V2PT_MIN}
    check(not lowp, f"each format v2 op of batch 6.3 in >= {V2PT_MIN:.0%} of {N} cases {lowp}")

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

    # 7. run-event coverage
    cov = coverage.run([SEED], COV_N, gen, verbose=False)
    check(not cov['problems'] and cov['prefix_violations'] == 0,
          f"coverage run: {cov['prefix_runs']} prefix runs, no problem, no prefix violation")
    low = {k: cov['events'][k] for k in coverage.KEY_EVENTS if cov['events'][k] < COV_MIN * cov['cases']}
    check(not low, f"each key run event in >= {COV_MIN:.1%} of {cov['cases']} cases {low}")
    stuck = (cov['outcomes']['blocked'] + cov['outcomes']['fuel']) / cov['cases']
    check(stuck < COV_MAX_STUCK, f"blocked + fuel outcomes {stuck:.1%} < {COV_MAX_STUCK:.0%}")
    dt = time.time() - t0
    check(dt < 60, f"self-test time {dt:.1f} s")


if __name__ == '__main__':
    main()

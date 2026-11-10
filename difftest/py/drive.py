#!/usr/bin/env python3
"""Difftest driver: run generated cases on Scala (and Lean), compare, triage, shrink.

Rules: wiki/methodology/differential-testing.md ("Driver", "Triage bins", "Corpus").

Subcommands:
  run          generate cases, run Scala (replay + testcontrol), optionally Lean; sort into bins;
               shrink mismatches and save them to the corpus.
  check        Fixed case files: Scala and Lean; fails unless each case agrees or is unsupported.
  scala-check  Scala alone: replay determinism, testcontrol determinism, testcontrol outcome in
               the replay outcome set, coverage histogram, timing.
  shrink       shrink the cases of a JSONL file against a Lean command.
  corpus       rerun the regression corpus (difftest/corpus/*.json).

Examples:
  drive.py run --seeds 1 2 3 --n 10000 --lean "lake exe cediff"
  drive.py scala-check --seeds 1 2 3 --n 10000 --json /tmp/check.json
"""

import argparse
import collections
import datetime
import json
import os
import random
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen  # noqa: E402
from typecheck import well_typed  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SCALA_CMD = [str(REPO / 'difftest' / 'run.sh')]
CORPUS_DIR = REPO / 'difftest' / 'corpus'
CHUNK = 5000

# Automatic bins of the driver. A `mismatch` then gets one of TRIAGE_BINS by a human.
BINS = ('agree', 'unsupported', 'inconclusive', 'mismatch', 'known-model-bug', 'harness', 'generator-bug', 'hang')


def _has_op(p, ops):
    if isinstance(p, dict):
        return p.get('op') in ops or any(_has_op(v, ops) for v in p.values())
    if isinstance(p, list):
        return any(_has_op(v, ops) for v in p)
    return False


# Known model bugs (in CatsEffectInLean/, which the difftest does not fix). A replay mismatch of a
# case that matches the predicate goes to the bin `known-model-bug`, not `mismatch`. Each entry:
# id, predicate on the case, note. Details: raw/project-decisions/2026-11-10-difftest-v1-notes.md.
KNOWN_MODEL_BUGS = [
    ('idpoll',
     lambda c: c['prog'].get('op') == 'syncStep' and _has_op(c['prog']['e'], ('timeout', 'timeoutTo', 'allocatedCase')),
     'Timeout/Resource mirrors turn poll(fa) into UnmaskRunLoop also for the IdPoll (mask id 0) of '
     'syncStep; Scala IdPoll(fa) = fa. After the poll the root fiber stays masked in the model.'),
]


def known_model_bug(case):
    for bid, pred, _ in KNOWN_MODEL_BUGS:
        try:
            if pred(case):
                return bid
        except (KeyError, TypeError, AttributeError):
            pass
    return None
TRIAGE_BINS = ('untriaged', 'model-bug', 'harness-bug', 'model-simplification',
               'intended-ce-behaviour', 'underspecified', 'ce-bug')


def dumps(x):
    return json.dumps(x, separators=(',', ':'), sort_keys=True)


# ----------------------------------------------------------------- running

def _run_once(cmd, cases, timeout):
    with tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False) as f:
        for c in cases:
            f.write(json.dumps(c, separators=(',', ':')) + '\n')
        path = f.name
    try:
        p = subprocess.run(cmd + [path], cwd=REPO, capture_output=True, text=True, timeout=timeout)
    finally:
        os.unlink(path)
    out = {}
    for line in p.stdout.splitlines():
        if not line.strip():
            continue
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        o['_raw'] = line
        out[o.get('id', '')] = o
    if not out and cases and p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} failed (exit {p.returncode}): {p.stderr[-2000:]}")
    return out


def run_cmd(cmd, cases, timeout_per_case=0.05, base_timeout=60):
    """Run cases through a JSONL command. Returns {id: output}. A batch that times out is
    split in halves until the hanging case is found; it gets {"hang": true}."""
    res = {}
    for i in range(0, len(cases), CHUNK):
        res.update(_run_bisect(cmd, cases[i:i + CHUNK], timeout_per_case, base_timeout))
    return res


def _run_bisect(cmd, cases, tpc, base):
    try:
        return _run_once(cmd, cases, base + tpc * len(cases))
    except subprocess.TimeoutExpired:
        if len(cases) == 1:
            return {cases[0]['id']: {'id': cases[0]['id'], 'hang': True}}
        m = len(cases) // 2
        return {**_run_bisect(cmd, cases[:m], tpc, base), **_run_bisect(cmd, cases[m:], tpc, base)}


def run_scala(cases):
    return run_cmd(SCALA_CMD, cases)


def run_lean(lean_cmd, cases):
    return run_cmd(shlex.split(lean_cmd), cases, timeout_per_case=1.0, base_timeout=120)


# --------------------------------------------------------------- comparing

def scala_problem(s):
    """A problem in the Scala output alone (no Lean needed): bin and detail, or None."""
    if s is None:
        return 'harness', 'scala: no output line'
    if s.get('hang'):
        return 'hang', 'scala: case did not finish (timeout)'
    if 'error' in s:
        e = s['error']
        return ('generator-bug' if e.startswith('decode') else 'harness'), f"scala: {e}"
    raw = s.get('_raw') or dumps(s)
    if '"exn"' in raw or 'TypeError' in raw:
        # decision 8: a non-UserError error (TypeError) means the program was not well-typed
        return 'generator-bug', 'scala: non-UserError error in output'
    return None


def obs(o):
    return dumps({'outcome': o.get('outcome'), 'trace': o.get('trace')})


def compare(case, s, l):
    """Compare one case. Returns (bin, detail). `l` may be None when no Lean command is given."""
    p = scala_problem(s)
    if p:
        return p
    if l is None:
        return 'harness', 'lean: no output line'
    if l.get('hang'):
        return 'hang', 'lean: case did not finish (timeout)'
    if 'error' in l:
        return 'harness', f"lean: {l['error']}"
    if l.get('outcome') == 'unsupported':
        return 'unsupported', ','.join(l.get('unsupported', []))
    if case['mode'] == 'replay':
        # Lean lists the fields that it can compare (`compare`); outcome and trace always.
        # Without the list (old Lean side, mock): outcome, trace, and schedule if present.
        if 'compare' in l:
            fields = ['outcome', 'trace'] + [f for f in l['compare'] if f not in ('outcome', 'trace')]
        else:
            fields = ['outcome', 'trace'] + (['schedule'] if 'schedule' in l else [])
        for field in fields:
            if dumps(s.get(field)) != dumps(l.get(field)):
                kb = known_model_bug(case)
                return ('known-model-bug', f"{kb}:{field}") if kb else ('mismatch', field)
        return 'agree', ''
    # testcontrol: refinement. Lean gives the set of allowed (outcome, trace) pairs.
    if s['outcome'].get('t') == 'inconclusive':
        return 'inconclusive', 'scala: step cap'
    if 'outcomes' not in l:
        return 'harness', 'lean: testcontrol output without "outcomes"'
    allowed = {obs(x) for x in l['outcomes']}
    if obs(s) in allowed:
        return 'agree', ''
    if not l.get('complete', False):
        return 'inconclusive', 'lean: outcome set not complete'
    return 'mismatch', 'refinement'


# --------------------------------------------------------------- shrinking

PROG_KEYS = ('e', 'k', 'body', 'fin', 'a', 'b', 'lk', 'rk', 'fb', 'res', 'acq', 'rel')


def _nodes(p, path=()):
    yield path, p
    for k in PROG_KEYS:
        if k in p and isinstance(p[k], dict) and 'op' in p[k]:
            yield from _nodes(p[k], path + (k,))
    if p.get('op') == 'seq':
        for i, q in enumerate(p['ps']):
            yield from _nodes(q, path + ('ps', i))


def _replace(p, path, new):
    if not path:
        return new
    q = dict(p)
    k = path[0]
    if k == 'ps':
        ps = list(q['ps'])
        ps[path[1]] = _replace(ps[path[1]], path[2:], new)
        q['ps'] = ps
    else:
        q[k] = _replace(q[k], path[1:], new)
    return q


SIMPLE = [{'op': 'raise', 'code': 0}, {'op': 'never'}, {'op': 'pure', 'v': {'t': 'unit'}},
          {'op': 'pure', 'v': {'t': 'nat', 'v': 0}}, {'op': 'canceled'}, {'op': 'cede'}]


def prog_candidates(prog):
    for path, n in _nodes(prog):
        subs = [n[k] for k in PROG_KEYS if k in n and isinstance(n[k], dict) and 'op' in n[k]]
        if n.get('op') == 'seq':
            subs += n['ps']
            for i in range(len(n['ps'])):
                rest = n['ps'][:i] + n['ps'][i + 1:]
                yield _replace(prog, path, rest[0] if len(rest) == 1 else {**n, 'ps': rest})
        for s in subs:
            yield _replace(prog, path, s)
        for s in SIMPLE:
            if s != n:
                yield _replace(prog, path, s)
        if n.get('op') == 'async':
            for i in range(len(n['cbs'])):
                yield _replace(prog, path, {**n, 'cbs': n['cbs'][:i] + n['cbs'][i + 1:]})
            for i, cb in enumerate(n['cbs']):
                if cb['when'] == 'later':
                    yield _replace(prog, path, {**n, 'cbs': n['cbs'][:i] + [{**cb, 'when': 'sync'}] + n['cbs'][i + 1:]})
            if 'fin' in n:
                yield _replace(prog, path, {k: v for k, v in n.items() if k not in ('fin', 'tag')})
        if 'tag' in n:
            yield _replace(prog, path, {k: v for k, v in n.items() if k != 'tag'})


def choice_candidates(cs):
    n = len(cs)
    k = n
    while k >= 1:
        for i in range(0, n, k):
            yield cs[:i] + cs[i + k:]
        k //= 2
    for i, c in enumerate(cs):
        if isinstance(c, int) and c != 0:
            yield cs[:i] + [0] + cs[i + 1:]


def measure(case):
    cs = case.get('choices', [])
    return (gen.size_of(case['prog']), len(cs), sum(c for c in cs if isinstance(c, int)),
            len(json.dumps(case['prog'])), 'maxSteps' in case)


def case_candidates(case):
    base = {k: v for k, v in case.items() if k != 'prog'}
    seen = {dumps(case)}
    out = []

    def add(c):
        d = dumps(c)
        if d not in seen and well_typed(c['prog']):
            seen.add(d)
            out.append(c)
    # When a candidate removes a `start`, the fiber handles of the external cancel choices move.
    # So each program candidate also comes with all cancel handles set to 0 (the root).
    # A second variant also folds each run of picks before a cancel into one pick 0 (the smaller
    # program needs fewer steps before the cancel).
    cs0 = [{'cancel': 0} if isinstance(x, dict) else x for x in case.get('choices', [])]
    cs1 = []
    for x in cs0:
        if isinstance(x, dict) and cs1 and not isinstance(cs1[-1], dict):
            while cs1 and not isinstance(cs1[-1], dict):
                cs1.pop()
            cs1.append(0)
        cs1.append(x)
    remap = cs0 != case.get('choices', [])
    for p in prog_candidates(case['prog']):
        add({**base, 'prog': p})
        if remap:
            add({**base, 'choices': cs0, 'prog': p})
            add({**base, 'choices': cs1, 'prog': p})
    if 'choices' in case:
        for cs in choice_candidates(case['choices']):
            c = {k: v for k, v in case.items() if k != 'choices'}
            if cs:
                c['choices'] = cs
            add(c)
    if 'maxSteps' in case and case['maxSteps'] != 10000:
        add({k: v for k, v in case.items() if k != 'maxSteps'})
    return out


def shrink(case, lean_cmd, field, max_rounds=200, log=None, bin_='mismatch'):
    """Greedy delta debugging. A candidate is kept if the mismatch persists with the same
    first differing field (and the same bin: `mismatch` or `known-model-bug`). Each round runs
    all candidates in one Scala batch and one Lean batch."""
    cur = case
    for rnd in range(max_rounds):
        m = measure(cur)
        cands = [c for c in case_candidates(cur) if measure(c) < m]  # strict progress: no cycles
        if not cands:
            break
        for j, c in enumerate(cands):
            c['id'] = f"{case['id']}~s{rnd}.{j}"
        s = run_scala(cands)
        lo = run_lean(lean_cmd, cands)
        ok = [c for c in cands if compare(c, s.get(c['id']), lo.get(c['id'])) == (bin_, field)]
        if not ok:
            break
        cur = min(ok, key=measure)
        if log:
            log(f"  round {rnd}: size {gen.size_of(cur['prog'])}, choices {len(cur.get('choices', []))}")
    out = dict(cur)
    out['id'] = case['id']
    return out


def save_corpus(case, s, l, field, meta, corpus_dir=CORPUS_DIR):
    corpus_dir.mkdir(parents=True, exist_ok=True)
    kb = known_model_bug(case)
    entry = {
        'case': case,
        'scala': {'outcome': s.get('outcome'), 'trace': s.get('trace')},
        'lean': {k: v for k, v in l.items() if k != '_raw'},
        'field': field,
        'expect': 'known-model-bug' if kb else 'agree',
        'triage': 'model-bug' if kb else 'untriaged',
        'known_bug': kb or '',
        'note': '',
        'found': meta,
    }
    path = corpus_dir / f"{case['id'].replace('~', '_')}.json"
    path.write_text(json.dumps(entry, indent=1) + '\n')
    return path


def load_corpus(corpus_dir=CORPUS_DIR):
    if not corpus_dir.is_dir():
        return []
    return [(p, json.loads(p.read_text())) for p in sorted(corpus_dir.glob('*.json'))]


# --------------------------------------------------------------- run cases

def build_cases(seeds, n, modes, tc_seeds, max_size):
    cases = []
    for seed in seeds:
        for c in gen.gen_cases(seed, n, max_size=max_size):
            if 'replay' in modes:
                cases.append(c)
            if 'testcontrol' in modes:
                cases += [gen.to_testcontrol(c, t) for t in tc_seeds]
    return cases


def cmd_run(a):
    t0 = time.time()
    cases = build_cases(a.seeds, a.n, a.modes, a.tc_seeds, a.max_size)
    t1 = time.time()
    s = run_scala(cases)
    t2 = time.time()
    lo = run_lean(a.lean, cases) if a.lean else {}
    t3 = time.time()
    bins = collections.Counter()
    by_bin = collections.defaultdict(list)
    for c in cases:
        if a.lean:
            b, d = compare(c, s.get(c['id']), lo.get(c['id']))
        else:
            p = scala_problem(s.get(c['id']))
            b, d = p if p else ('scala-only', '')
        bins[b] += 1
        by_bin[b].append((c, d))
    print(f"cases {len(cases)}  gen {t1 - t0:.1f}s  scala {t2 - t1:.1f}s  lean {t3 - t2:.1f}s")
    for b, k in sorted(bins.items(), key=lambda x: -x[1]):
        print(f"  {b:15} {k}")
    for b in ('generator-bug', 'harness', 'hang'):
        for c, d in by_bin[b][:5]:
            print(f"  {b}: {c['id']}: {d}")
    details = collections.Counter(d for _, d in by_bin['mismatch'])
    if details:
        print("  mismatch fields:", dict(details))
    kdet = collections.Counter(d for _, d in by_bin['known-model-bug'])
    if kdet:
        print("  known model bugs (id:field):", dict(kdet))
    unsup = collections.Counter(op for _, d in by_bin['unsupported'] for op in d.split(',') if op)
    if unsup:
        print("  unsupported ops:", dict(unsup.most_common()))
    if a.lean and by_bin['mismatch'] and a.shrink:
        for c, field in by_bin['mismatch'][:a.max_shrink]:
            print(f"shrinking {c['id']} ({field}), size {gen.size_of(c['prog'])}")
            sc = shrink(c, a.lean, field, log=print)
            s1 = run_scala([sc])[sc['id']]
            l1 = run_lean(a.lean, [sc])[sc['id']]
            meta = {'date': datetime.date.today().isoformat(), 'orig_id': c['id'],
                    'orig_size': gen.size_of(c['prog']), 'size': gen.size_of(sc['prog'])}
            path = save_corpus(sc, s1, l1, field, meta, Path(a.corpus_dir))
            print(f"  saved {path}")
    if a.json:
        Path(a.json).write_text(json.dumps({'bins': bins, 'cases': len(cases)}, indent=1))
    bad = bins['generator-bug'] + bins['harness'] + bins['hang']
    return 1 if bad or (a.lean and bins['mismatch']) else 0


def cmd_shrink(a):
    cases = [json.loads(x) for x in Path(a.file).read_text().splitlines() if x.strip()]
    s = run_scala(cases)
    lo = run_lean(a.lean, cases)
    for c in cases:
        b, field = compare(c, s.get(c['id']), lo.get(c['id']))
        if b not in ('mismatch', 'known-model-bug'):
            print(f"{c['id']}: {b} (not shrunk)")
            continue
        sc = shrink(c, a.lean, field, log=print, bin_=b)
        print(json.dumps(sc, separators=(',', ':')))
        if a.save:
            meta = {'date': datetime.date.today().isoformat(), 'orig_id': c['id'],
                    'orig_size': gen.size_of(c['prog']), 'size': gen.size_of(sc['prog'])}
            print('saved', save_corpus(sc, run_scala([sc])[sc['id']], run_lean(a.lean, [sc])[sc['id']], field,
                                       meta, Path(a.corpus_dir)))
    return 0


def cmd_check(a):
    """Run fixed case files through Scala and Lean. Fail on any bin other than `agree` and
    `unsupported` (a case the model cannot run yet). Prints the bins."""
    cases = [json.loads(x) for f in a.files for x in Path(f).read_text().splitlines() if x.strip()]
    s = run_scala(cases)
    lo = run_lean(a.lean, cases)
    bins = collections.Counter()
    for c in cases:
        b, d = compare(c, s.get(c['id']), lo.get(c['id']))
        bins[b] += 1
        if b not in ('agree', 'unsupported'):
            print(f"  {c['id']}: {b} {d}")
    print(f"check: {len(cases)} cases  " + "  ".join(f"{b} {k}" for b, k in sorted(bins.items())))
    return 0 if set(bins) <= {'agree', 'unsupported'} else 1


def cmd_corpus(a):
    entries = load_corpus(Path(a.corpus_dir))
    if not entries:
        print("corpus: empty")
        return 0
    cases = [e['case'] for _, e in entries]
    s = run_scala(cases)
    lo = run_lean(a.lean, cases) if a.lean else None
    fails = 0
    for (path, e), c in zip(entries, cases):
        so = s.get(c['id'])
        p = scala_problem(so)
        if p:
            print(f"{path.name}: scala {p}")
            fails += 1
            continue
        if obs(so) != obs(e['scala']):
            print(f"{path.name}: Scala result changed (CE or runner change)")
            fails += 1
        if lo is not None:
            b, d = compare(c, so, lo.get(c['id']))
            want = e.get('expect', 'agree')
            if b != want:
                print(f"{path.name}: lean {b} {d}, expected {want}")
                fails += 1
    print(f"corpus: {len(entries)} entries, {fails} failures")
    return 1 if fails else 0


# ----------------------------------------------------------- scala-check

def static_features(prog):
    """Static coverage of one program: op names and edge-case patterns."""
    ops = collections.Counter()
    pats = set()

    def walk(p, polls, in_unc, in_fin_polls):
        # polls: name -> True if a `start` boundary was crossed since it was bound
        op = p['op']
        ops[op] += 1
        if op == 'poll':
            if polls.get(p['poll']):
                pats.add('escaped-poll (poll inside start child)')
            if p['poll'] in in_fin_polls:
                pats.add('poll in finalizer (outer poll)')
        if op == 'uncancelable':
            if in_unc:
                pats.add('nested uncancelable')
            walk(p['body'], {**polls, p['poll']: False}, True, in_fin_polls - {p['poll']})
            return
        if op == 'start':
            if in_unc:
                pats.add('start inside uncancelable')
            walk(p['e'], {k: True for k in polls}, False, in_fin_polls)
            return
        if op == 'racePair':
            for k in ('a', 'b'):
                walk(p[k], {k2: True for k2 in polls}, False, in_fin_polls)
            return
        if op == 'async':
            n = len(p['cbs'])
            pats.add(f"async with {n} callback(s)")
            for cb in p['cbs']:
                pats.add(f"async cb {cb['when']} {'ok' if 'ok' in cb else 'err'}")
            if 'fin' in p:
                pats.add('async with finalizer')
        if op in ('onCancel', 'guaranteeCase', 'async') and 'fin' in p:
            if _raises(p['fin']):
                pats.add(f'{op} finalizer that can raise')
            for k in PROG_KEYS:
                if k in p and isinstance(p[k], dict):
                    walk(p[k], polls, in_unc, in_fin_polls | set(polls) if k == 'fin' else in_fin_polls)
            return
        if op == 'cancel':
            pats.add('cancel child')
        for k in PROG_KEYS:
            if k in p and isinstance(p[k], dict) and 'op' in p[k]:
                walk(p[k], polls, in_unc, in_fin_polls)
        for q in p.get('ps', []):
            walk(q, polls, in_unc, in_fin_polls)
    walk(prog, {}, False, frozenset())
    return ops, pats


def _raises(p):
    if p.get('op') == 'raise' or (p.get('op') in ('delay', 'map') and p.get('fn') == 3):
        return True
    return any(_raises(p[k]) for k in PROG_KEYS if k in p and isinstance(p[k], dict) and 'op' in p[k]) or \
        any(_raises(q) for q in p.get('ps', []))


def dynamic_features(o):
    ev = collections.Counter()
    for e in o.get('trace', []):
        k = e['ev']
        if k == 'call':
            ev[f"call fn{e['fn']}"] += 1
        elif k == 'fin':
            ev[f"fin {e['op']}" + (f" oc={e['oc']['t']}" if 'oc' in e else '')] += 1
        elif k == 'complete':
            ev[f"complete ok={e['ok']}"] += 1
        else:
            ev[k] += 1
    sch = o.get('schedule')
    if isinstance(sch, list):
        for x in sch:
            if 'advance' in x:
                ev['sched: time advance'] += 1
            elif x.get('skipped'):
                ev['sched: cancel skipped (unknown handle)'] += 1
            elif 'cancel' in x:
                ev['sched: external cancel ' + ('root' if x['cancel'] == 0 else 'child')] += 1
            else:
                t = x['task']
                kind = {'f': 'fiber', 'x': 'canceler', 'c': 'callback', 't': 'timer'}[t[0]]
                ev[f"sched: run {kind} task"] += 1
                if len(x['ready']) > 1:
                    ev['sched: choice among >1 ready'] += 1
    oc = o['outcome']['t']
    ev[f"outcome {oc}"] += 1
    if o.get('pending'):
        ev['end: pending tasks/timers > 0'] += 1
    if o.get('failures'):
        ev['end: reportFailure calls'] += 1
    return ev


def cmd_scala_check(a):
    report = {'seeds': a.seeds, 'n': a.n, 'per_seed': []}
    cov_ops = collections.Counter()
    cov_pats = collections.Counter()
    cov_dyn = collections.Counter()   # number of cases with the event
    tot_dyn = collections.Counter()   # number of events
    gen_bugs = []
    nondet = []
    t_all = time.time()
    for seed in a.seeds:
        r = {'seed': seed}
        t0 = time.time()
        cases = gen.gen_cases(seed, a.n, max_size=a.max_size)
        r['gen_s'] = round(time.time() - t0, 2)
        t0 = time.time()
        o1 = run_scala(cases)
        r['replay_s'] = round(time.time() - t0, 2)
        o2 = run_scala(cases)
        r['replay_nondeterministic'] = sum(1 for c in cases if o1.get(c['id'], {}).get('_raw') != o2.get(c['id'], {}).get('_raw'))
        nondet += [c['id'] for c in cases if o1.get(c['id'], {}).get('_raw') != o2.get(c['id'], {}).get('_raw')][:5]
        oc = collections.Counter()
        for c in cases:
            o = o1.get(c['id'])
            p = scala_problem(o)
            if p:
                gen_bugs.append((c['id'], p))
                continue
            ops, pats = static_features(c['prog'])
            cov_ops.update(set(ops))
            cov_pats.update(pats)
            if gen.has_cancel_choice(c):
                cov_pats['case with external cancel choice'] += 1
            d = dynamic_features(o)
            cov_dyn.update(set(d))
            tot_dyn.update(d)
            oc[o['outcome']['t']] += 1
        r['outcomes'] = dict(oc)

        # testcontrol determinism and "testcontrol outcome is a replay outcome"
        base = [c for c in cases if not gen.has_cancel_choice(c) and 'maxSteps' not in c][:a.tc_cases]
        tcs = [gen.to_testcontrol(c, t) for c in base for t in a.tc_seeds]
        t0 = time.time()
        q1 = run_scala(tcs)
        r['testcontrol_s'] = round(time.time() - t0, 2)
        q2 = run_scala(tcs)
        r['testcontrol_cases'] = len(tcs)
        r['testcontrol_nondeterministic'] = sum(1 for c in tcs if q1.get(c['id'], {}).get('_raw') != q2.get(c['id'], {}).get('_raw'))
        rng = random.Random(f"sched:{seed}")
        variants = []
        for c in base:
            variants.append(gen.with_choices(c, [], 'fifo'))
            for k in range(a.schedules):
                variants.append(gen.with_choices(c, [rng.choice([0, 0, 1, 1, 2, 3]) for _ in range(60)], f"r{k}"))
        t0 = time.time()
        vs = run_scala(variants)
        r['replay_variants'] = len(variants)
        r['replay_variants_s'] = round(time.time() - t0, 2)
        sets = collections.defaultdict(set)
        osets = collections.defaultdict(set)
        for v in variants:
            o = vs.get(v['id'])
            if o and not scala_problem(o):
                bid = v['id'].rsplit('~', 1)[0]
                sets[bid].add(obs(o))
                osets[bid].add(dumps(o['outcome']))
        hit = ohit = inconc = tot = 0
        misses = []
        for c in tcs:
            o = q1.get(c['id'])
            if not o or scala_problem(o):
                gen_bugs.append((c['id'], scala_problem(o)))
                continue
            if o['outcome']['t'] == 'inconclusive':
                inconc += 1
                continue
            tot += 1
            bid = c['id'].rsplit('~', 1)[0]
            if obs(o) in sets[bid]:
                hit += 1
            elif len(misses) < 5:
                misses.append(c['id'])
            ohit += dumps(o['outcome']) in osets[bid]
        r['tc_in_replay_set'] = {'total': tot, 'outcome_and_trace': hit, 'outcome_only': ohit,
                                 'inconclusive': inconc, 'miss_examples': misses}
        report['per_seed'].append(r)
        print(json.dumps(r))
    report['total_s'] = round(time.time() - t_all, 1)
    total = sum(1 for _ in range(len(a.seeds) * a.n))
    report['coverage'] = {
        'cases': total,
        'ops_cases': dict(cov_ops.most_common()),
        'patterns_cases': dict(cov_pats.most_common()),
        'dynamic_cases': dict(cov_dyn.most_common()),
        'dynamic_events': dict(tot_dyn.most_common()),
    }
    report['generator_bugs'] = gen_bugs[:20]
    report['generator_bug_count'] = len(gen_bugs)
    report['nondeterministic_examples'] = nondet
    print(f"total {report['total_s']} s; generator bugs {len(gen_bugs)}")
    _print_hist("ops (cases containing)", cov_ops, total)
    _print_hist("patterns (cases)", cov_pats, total)
    _print_hist("dynamic (cases with event)", cov_dyn, total)
    if a.json:
        Path(a.json).write_text(json.dumps(report, indent=1))
    return 1 if gen_bugs or nondet else 0


def _print_hist(title, c, total):
    print(f"-- {title}")
    for k, v in c.most_common():
        print(f"  {100.0 * v / total:6.2f}%  {v:7}  {k}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)

    r = sub.add_parser('run')
    r.add_argument('--seeds', type=int, nargs='+', default=[1])
    r.add_argument('--n', type=int, default=1000)
    r.add_argument('--modes', default='replay,testcontrol')
    r.add_argument('--tc-seeds', type=int, nargs='+', default=[1])
    r.add_argument('--max-size', type=int, default=40)
    r.add_argument('--lean', help='Lean command, for example "lake exe cediff"')
    r.add_argument('--shrink', action='store_true', help='shrink mismatches and save them to the corpus')
    r.add_argument('--max-shrink', type=int, default=5)
    r.add_argument('--corpus-dir', default=str(CORPUS_DIR))
    r.add_argument('--json')

    c = sub.add_parser('scala-check')
    c.add_argument('--seeds', type=int, nargs='+', default=[1, 2, 3])
    c.add_argument('--n', type=int, default=10000)
    c.add_argument('--max-size', type=int, default=40)
    c.add_argument('--tc-seeds', type=int, nargs='+', default=[1, 2])
    c.add_argument('--tc-cases', type=int, default=2000, help='base cases per seed for the testcontrol checks')
    c.add_argument('--schedules', type=int, default=8, help='random replay schedules per base case')
    c.add_argument('--json')

    s = sub.add_parser('shrink')
    s.add_argument('file')
    s.add_argument('--lean', required=True)
    s.add_argument('--save', action='store_true')
    s.add_argument('--corpus-dir', default=str(CORPUS_DIR))

    k = sub.add_parser('corpus')
    k.add_argument('--lean')
    k.add_argument('--corpus-dir', default=str(CORPUS_DIR))

    f = sub.add_parser('check', help='fixed case files: fail unless every case agrees or is unsupported')
    f.add_argument('files', nargs='+')
    f.add_argument('--lean', required=True)

    a = ap.parse_args(argv)
    if a.cmd == 'run':
        a.modes = set(a.modes.split(','))
        return cmd_run(a)
    if a.cmd == 'scala-check':
        return cmd_scala_check(a)
    if a.cmd == 'shrink':
        return cmd_shrink(a)
    if a.cmd == 'check':
        return cmd_check(a)
    return cmd_corpus(a)


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Run-event coverage of generated difftest cases, measured on the Scala runner.

It counts what RAN (trace and schedule of the Scala replay run), not what the program text
contains. Design notes: wiki/methodology/differential-testing.md ("Generator", "Coverage").

Step attribution. The Scala output does not say which step emitted a trace event. This tool
runs each case again with `maxSteps = k` for k = 1 .. steps-1. Each run stops after k steps,
so its trace is the prefix of the full trace up to the end of step k-1. The lengths of these
prefixes give the step (and so the task label) of each event. The tool checks that each
prefix trace is a prefix of the full trace (counter `prefix violations`).

Owner of an event: the fiber label of its step. A step of a canceler `x<k>` belongs to the
cancel target. A step of a callback task `cb<a>.<i>` belongs to the owner of async `a`
(the fiber that emitted `asyncReg a`).

Cancel requests on a fiber L at trace position P:
- external: a schedule entry `{"cancel":h}` (not skipped); P = trace length before the step.
- internal: a marker `call fn1 arg fiber(h)` (the generator puts it just before `cancel f`).

Region markers (from the generator, see gen.MARK_*): `delay fn1 arg nat M`, where M encodes a
kind, a region id, and enter/exit. Kinds: uncancelable body, finalizer body, escaped poll
inside a finalizer, join result follows, `Resource` release body (format v1).

Usage:
  coverage.py --seeds 1 2 3 --n 10000 [--gen PATH/TO/gen.py] [--json FILE]
"""

import argparse
import collections
import importlib.util
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import drive  # noqa: E402
import gen as gen_default  # noqa: E402

# Run events of decision 17 (each is a fraction of cases), in report order.
KEY_EVENTS = [
    'ext cancel child (applied)',
    'ext cancel child (live target)',
    'fin async',
    'complete ok=false',
    'fin with canceled outcome (onCancel or guaranteeCase oc=canceled)',
    'choice among >1 ready',
    'cancel while masked, then region exit',
    'cancel during finalizer',
    'escaped poll used in finalizer',
    'callback after owner canceled',
    'join on canceled fiber',
    'cancel of nested parent (has started a fiber)',
]

# Format v1 run events (reported, no minimum yet).
V1_EVENTS = [
    'v1: TimeoutException seen',
    'v1: resource release ran',
]


def load_gen(path):
    if not path:
        return gen_default
    spec = importlib.util.spec_from_file_location('gen_alt', path)
    m = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(Path(path).resolve().parent))
    spec.loader.exec_module(m)
    return m


def marker(v):
    """Decode a region marker value: (kind, region id, is_exit) or None."""
    base = gen_default.MARK_BASE
    if not isinstance(v, int) or v < base or v >= base + 10 * gen_default.MARK_KIND:
        return None
    r = v - base
    return r // gen_default.MARK_KIND, (r % gen_default.MARK_KIND) // 2, r % 2 == 1


def step_entries(o):
    return [x for x in o.get('schedule', []) if isinstance(x, dict) and 'step' in x]


def prefix_cases(case, o):
    steps = o.get('steps', 0)
    out = []
    for k in range(1, steps):
        c = {kk: v for kk, v in case.items() if kk not in ('maxSteps', 'prog', 'id')}
        c['id'] = f"{case['id']}~p{k}"
        c['maxSteps'] = k
        c['prog'] = case['prog']
        out.append(c)
    return out


def analyse(case, o, prefix):
    """Run events of one case. `prefix`: {k: output of the run with maxSteps=k}."""
    ev = set()
    trace = o.get('trace', [])
    sched = o.get('schedule', [])
    steps = step_entries(o)
    fibers = {int(k): v for k, v in (o.get('fibers') or {}).items()}
    n_steps = len(steps)
    viol = 0

    # trace position at the start of each step
    start = [0] * (n_steps + 1)
    for k in range(1, n_steps):
        p = prefix.get(k)
        tr = p.get('trace', []) if p else None
        if tr is None or tr != trace[:len(tr)]:
            viol += 1
            tr = trace[:start[k - 1]]
        start[k] = max(len(tr), start[k - 1])
    start[n_steps] = len(trace)
    if n_steps == 0:
        start = [0, len(trace)]

    # owner of each step
    async_owner = {}
    step_owner = []
    for s in steps:
        t = s['task']
        if 'cancel' in s:
            step_owner.append(fibers.get(s['cancel'], t))
        else:
            step_owner.append(t)
    ev_step = []
    for k in range(max(n_steps, 1)):
        for _ in range(start[k], start[k + 1]):
            ev_step.append(k)
    ev_owner = []
    for i, e in enumerate(trace):
        k = ev_step[i] if i < len(ev_step) else n_steps - 1
        own = step_owner[k] if 0 <= k < n_steps else 'f0'
        if own.startswith('cb'):
            a = int(own[2:].split('.')[0])
            own = async_owner.get(a, own)
        if e['ev'] == 'asyncReg':
            async_owner[e['async']] = own
        ev_owner.append(own)

    # fiber creation: a label that first shows in a ready list after a step of its parent
    seen, parent, created = set(), {}, collections.defaultdict(list)
    for k, s in enumerate(steps):
        for lab in s['ready']:
            if lab not in seen:
                seen.add(lab)
                if k > 0 and lab.startswith('f'):
                    parent[lab] = step_owner[k - 1]
                    created[step_owner[k - 1]].append((k - 1, lab))
        seen.add(s['task'])

    # cancel requests: (position, target label, is_external, step index or None)
    reqs = []
    for k, s in enumerate(steps):
        if 'cancel' in s:
            lab = fibers.get(s['cancel'])
            if lab is None:
                continue
            reqs.append((start[k], lab, True, k))  # (trace position, target, external, step)
            if s['cancel'] != 0:
                ev.add('ext cancel child (applied)')
                later = any(x['task'] == lab for x in steps[k + 1:])
                if lab in s['ready'] or later:
                    ev.add('ext cancel child (live target)')
    for i, e in enumerate(trace):
        if e['ev'] == 'call' and e['fn'] == 1 and isinstance(e.get('arg'), dict) and e['arg'].get('t') == 'fiber':
            lab = fibers.get(e['arg']['id'])
            if lab is not None:
                reqs.append((i + 1, lab, False, ev_step[i] if i < len(ev_step) else n_steps - 1))

    # simple events
    for s in steps:
        if len(s['ready']) > 1:
            ev.add('choice among >1 ready')
    canceled_fin = []  # (position, owner)
    for i, e in enumerate(trace):
        k = e['ev']
        if k == 'fin':
            if e['op'] == 'async':
                ev.add('fin async')
            if e['op'] == 'onCancel' or (e['op'] == 'guaranteeCase' and e['oc']['t'] == 'canceled'):
                ev.add('fin with canceled outcome (onCancel or guaranteeCase oc=canceled)')
                canceled_fin.append((i, ev_owner[i]))
        elif k == 'complete' and e['ok'] is False:
            ev.add('complete ok=false')

    # markers: regions per owner
    regions = []  # (kind, id, owner, enter pos, exit pos or None)
    open_ = {}
    for i, e in enumerate(trace):
        if e['ev'] != 'call' or e['fn'] != 1 or not isinstance(e.get('arg'), dict) or e['arg'].get('t') != 'nat':
            continue
        m = marker(e['arg']['v'])
        if m is None:
            continue
        kind, rid, is_exit = m
        if kind == gen_default.MARK_ESC_POLL_FIN:
            ev.add('escaped poll used in finalizer')
        elif kind == gen_default.MARK_JOIN:
            nxt = trace[i + 1] if i + 1 < len(trace) else None
            if nxt and nxt['ev'] == 'call' and nxt['fn'] == 1 and nxt.get('arg') == {'t': 'canceled'}:
                ev.add('join on canceled fiber')
        elif kind == gen_default.MARK_REL:
            ev.add('v1: resource release ran')
        elif not is_exit:
            open_[(kind, rid, ev_owner[i])] = i
        else:
            key = (kind, rid, ev_owner[i])
            if key in open_:
                regions.append((kind, rid, ev_owner[i], open_.pop(key), i))

    for pos, lab, _ext, kstep in reqs:
        for kind, _rid, own, a, b in regions:
            if own != lab or not (a < pos <= b):
                continue
            if kind == gen_default.MARK_UNC:
                ev.add('cancel while masked, then region exit')
            elif kind == gen_default.MARK_FIN:
                ev.add('cancel during finalizer')
        if lab != 'f0' and any(kc < kstep for kc, _ in created.get(lab, [])):
            ev.add('cancel of nested parent (has started a fiber)')

    # callback after its owner was canceled (the async was pending at that time)
    reg_pos = {e['async']: i for i, e in enumerate(trace) if e['ev'] == 'asyncReg'}
    cancel_pos = collections.defaultdict(list)
    for pos, lab, _e, _k in reqs:
        cancel_pos[lab].append(pos)
    for i, own in canceled_fin:
        cancel_pos[own].append(i)
    for i, e in enumerate(trace):
        if e['ev'] == 'cb':
            a = e['async']
            own = async_owner.get(a)
            r = reg_pos.get(a, -1)
            if own and any(r < p <= i for p in cancel_pos.get(own, [])):
                ev.add('callback after owner canceled')
                break
    return ev, viol


def run(seeds, n, gen_mod, max_size=40, verbose=True):
    """Returns a report dict with per-event case counts."""
    res = {'seeds': seeds, 'n': n, 'cases': 0, 'events': collections.Counter(), 'outcomes': collections.Counter(),
           'dynamic': collections.Counter(), 'problems': [], 'prefix_violations': 0, 'prefix_runs': 0}
    t0 = time.time()
    for seed in seeds:
        cases = gen_mod.gen_cases(seed, n, max_size=max_size)
        outs = drive.run_scala(cases)
        pre_cases = []
        for c in cases:
            o = outs.get(c['id'])
            if o is not None and not drive.scala_problem(o):
                pre_cases += prefix_cases(c, o)
        pres = drive.run_scala(pre_cases) if pre_cases else {}
        res['prefix_runs'] += len(pre_cases)
        for c in cases:
            o = outs.get(c['id'])
            p = drive.scala_problem(o)
            res['cases'] += 1
            if p:
                res['problems'].append((c['id'], p))
                continue
            prefix = {}
            for k in range(1, o.get('steps', 0)):
                q = pres.get(f"{c['id']}~p{k}")
                if q is not None:
                    prefix[k] = q
            ev, viol = analyse(c, o, prefix)
            # `TimeoutException` is error code 999998 in the value language (format v1)
            if '999998' in json.dumps([o.get('outcome'), o.get('trace')]) or \
                    any(f.startswith('TimeoutException') for f in o.get('failures', [])):
                ev.add('v1: TimeoutException seen')
            res['prefix_violations'] += viol
            res['events'].update(ev)
            res['outcomes'][o['outcome']['t']] += 1
            res['dynamic'].update(set(drive.dynamic_features(o)))
        if verbose:
            print(f"seed {seed}: {n} cases, {len(pre_cases)} prefix runs, {time.time() - t0:.1f} s", file=sys.stderr)
    res['seconds'] = round(time.time() - t0, 1)
    return res


def print_report(res):
    tot = res['cases']
    print(f"cases {tot}; seconds {res['seconds']}; prefix runs {res['prefix_runs']}; "
          f"prefix violations {res['prefix_violations']}; problems (TypeError, decode, hang) {len(res['problems'])}")
    print("-- key run events (% of cases)")
    for k in KEY_EVENTS:
        print(f"  {100.0 * res['events'][k] / tot:6.2f}%  {res['events'][k]:7}  {k}")
    print("-- format v1 run events (% of cases)")
    for k in V1_EVENTS:
        print(f"  {100.0 * res['events'][k] / tot:6.2f}%  {res['events'][k]:7}  {k}")
    print("-- outcomes")
    for k, v in res['outcomes'].most_common():
        print(f"  {100.0 * v / tot:6.2f}%  {v:7}  {k}")
    print("-- other dynamic features (drive.dynamic_features)")
    for k, v in res['dynamic'].most_common():
        print(f"  {100.0 * v / tot:6.2f}%  {v:7}  {k}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--seeds', type=int, nargs='+', default=[1])
    ap.add_argument('--n', type=int, default=1000)
    ap.add_argument('--max-size', type=int, default=40)
    ap.add_argument('--gen', help='path of another gen.py (for before/after numbers)')
    ap.add_argument('--json')
    a = ap.parse_args(argv)
    res = run(a.seeds, a.n, load_gen(a.gen), a.max_size)
    print_report(res)
    if a.json:
        Path(a.json).write_text(json.dumps({k: (dict(v) if isinstance(v, collections.Counter) else v)
                                            for k, v in res.items()}, indent=1))
    return 1 if res['problems'] else 0


if __name__ == '__main__':
    sys.exit(main())

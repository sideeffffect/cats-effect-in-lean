#!/usr/bin/env python3
"""A fake Lean side for the driver self-test. Not a model.

It runs the Scala runner and copies its result, with planted faults:
- a program with `racePair` gives `"outcome":"unsupported"`;
- the first `{"ev":"fin","op":"onCancel"}` trace event is dropped (a planted "model bug").
Replay output: outcome, trace, schedule. Testcontrol output: "outcomes" (a set with one
element) and "complete": true (see wiki/methodology/differential-testing.md, "Driver").

Usage: mock_lean.py FILE.jsonl ...
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drive  # noqa: E402


def has_op(p, op):
    if isinstance(p, dict):
        return p.get('op') == op or any(has_op(v, op) for v in p.values())
    if isinstance(p, list):
        return any(has_op(v, op) for v in p)
    return False


def planted(trace):
    out, dropped = [], False
    for e in trace:
        if not dropped and e.get('ev') == 'fin' and e.get('op') == 'onCancel':
            dropped = True
            continue
        out.append(e)
    return out


def main():
    cases = []
    for f in sys.argv[1:]:
        cases += [json.loads(x) for x in Path(f).read_text().splitlines() if x.strip()]
    s = drive.run_scala(cases)
    for c in cases:
        o = s.get(c['id'])
        if o is None or 'error' in o or o.get('hang'):
            print(json.dumps({'v': 0, 'id': c['id'], 'error': 'mock: no scala result'}))
            continue
        if has_op(c['prog'], 'racePair'):
            print(json.dumps({'v': 0, 'id': c['id'], 'mode': c['mode'], 'outcome': 'unsupported', 'unsupported': ['racePair']}))
            continue
        tr = planted(o['trace'])
        if c['mode'] == 'replay':
            r = {'v': 0, 'id': c['id'], 'mode': 'replay', 'outcome': o['outcome'], 'trace': tr, 'schedule': o['schedule']}
        else:
            r = {'v': 0, 'id': c['id'], 'mode': 'testcontrol', 'outcomes': [{'outcome': o['outcome'], 'trace': tr}],
                 'complete': True}
        print(json.dumps(r, separators=(',', ':')))


if __name__ == '__main__':
    main()

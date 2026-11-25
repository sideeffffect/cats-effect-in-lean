#!/usr/bin/env python3
"""Generate the kernel-run modules of track P7D (Dispatcher witnesses, battery, refutations).

Each run is checked in chunks (kernel memory, decision 55): `tools/DispRuns/Dump.lean` prints the
states at task boundaries about every CHUNK micro-steps; module `R<id>S<i>` writes state `i` as a
literal and proves by `decide +kernel` that the run reaches it from the previous one; module
`R<id>` proves the observation of the last chunk and composes the chunks (`runP_add`) into a
fact about `run ... N CS V` (the `run` of `Props/Phase7/Dispatcher.lean`).

Usage: python3 tools/DispRuns/gen.py [run ids...]   (default: all; writes
CatsEffectInLean/Proofs/Phase7/DispatcherRuns/*.lean)
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'CatsEffectInLean' / 'Proofs' / 'Phase7' / 'DispatcherRuns'
NS = 'CatsEffectInLean.Proofs.Phase7.DispatcherRuns'
CHUNK = 90

DONE = 'some (Summary.done (.succeeded .unit))'
BLOCKED = 'some Summary.blocked'
ERRB = 'some (Summary.done (.errored CatsEffectInLean.Std.Dispatcher.battErr))'

# id: (par, aw, input, variant, seed or None, fuel or None (= until it stops), halt, [(obs, j, value)], doc)
RUNS = {
    '01': (False, True, 'xs0', 0, None, None, DONE, [('status', 0, 2), ('runs', 0, 1)], 'sequential, one pure task: it runs once, the root is done'),
    '02': (False, True, 'xs0', 1, None, None, DONE, [('status', 0, 0)], 'variant 1 (`unsafeToFutureCancelable` raises)'),
    '03': (False, True, 'xs0', 3, None, None, DONE, [('status', 0, 0)], 'variant 3 (`unsafeToFutureCancelable` drops)'),
    '04': (False, True, 'xs0', 4, None, None, DONE, [('runs', 0, 2)], 'variant 4 (`unsafeToFutureCancelable` doubles)'),
    '05': (False, True, 'xs0', 13, None, None, ERRB, [], 'variant 13 (`sequential` raises)'),
    '06': (False, True, 'xs0', 16, None, None, DONE, [('status', 0, 0)], 'variant 16 (the factory ignores `await`)'),
    '07': (False, True, 'xs0', 2, None, None, BLOCKED, [], 'variant 2 (`unsafeToFutureCancelable` never returns)'),
    '08': (False, True, 'xs0', 14, None, None, BLOCKED, [], 'variant 14 (`sequential` never returns)'),
    '09': (False, True, 'xs0', 15, None, None, BLOCKED, [], 'variant 15 (`sequential` release drops)'),
    '10': (False, True, 'xs1', 0, None, None, DONE, [('status', 0, 2)], 'sequential, one pure `unsafeRunAndForget` task'),
    '11': (False, True, 'xs1', 9, None, None, DONE, [('status', 0, 0)], 'variant 9 (`unsafeRunAndForget` raises)'),
    '12': (False, True, 'xs1', 11, None, None, DONE, [('status', 0, 0)], 'variant 11 (`unsafeRunAndForget` drops)'),
    '13': (False, True, 'xs1', 12, None, None, DONE, [('runs', 0, 2)], 'variant 12 (`unsafeRunAndForget` doubles)'),
    '14': (False, True, 'xs1', 10, None, None, BLOCKED, [], 'variant 10 (`unsafeRunAndForget` never returns)'),
    '15': (True, True, 'xs0', 0, None, None, DONE, [('status', 0, 0), ('runs', 0, 0)], 'CE-0091: `parallel(await = true)`, FIFO: the task never runs'),
    '16': (True, True, 'xs0', 31, None, None, DONE, [('status', 0, 2)], 'fixed twin 31 of CE-0091'),
    '17': (True, True, 'xs0', 0, 14, None, DONE, [('status', 0, 2)], '`parallel`, a schedule where the worker takes the task first'),
    '18': (True, True, 'xs0', 13, 14, None, ERRB, [], 'variant 13 (`parallel` raises)'),
    '19': (True, True, 'xs0', 14, None, None, BLOCKED, [], 'variant 14 (`parallel` never returns)'),
    '20': (True, True, '(pureInp [] [] [] p p)', 15, None, None, BLOCKED, [], 'variant 15 (`parallel` release drops): no pill, the outer Supervisor joins the worker forever'),
    '21': (False, True, 'xcn', 0, None, None, DONE, [], 'sequential, a task canceled by the body: the root is done'),
    '22': (False, True, 'xcn', 6, None, None, BLOCKED, [], 'variant 6 (the cancel action never returns)'),
    '23': (False, True, 'xlate', 0, None, None, DONE, [('rejected', 0, 1), ('runs', 0, 0)], 'a submission after the close throws, never runs'),
    '24': (False, True, 'xlate', 19, None, None, DONE, [('rejected', 0, 0)], 'variant 19 (no closed check)'),
    '25': (False, True, 'xce', 0, None, None, DONE, [('status', 0, 2), ('status', 1, 2), ('order', None, [0, 1])], 'sequential, two tasks: in order'),
    '26': (False, True, 'xce', 18, 50, 'OVERLAP', None, [('status', 0, 1), ('status', 1, 1)], 'variant 18 (`sequential` overlaps): two tasks run at once'),
    '27': (False, False, 'xsl', 0, None, None, DONE, [('status', 0, 3)], '`await = false`: the sleeping task is canceled'),
    '28': (False, False, 'xsl', 20, None, None, DONE, [('status', 0, 2)], 'variant 20 (the factory always awaits)'),
    '29': (True, True, 'xcan', 0, None, None, DONE, [('status', 0, 3)], '`parallel`: a cancel after the start cancels the task'),
    '30': (True, True, 'xcan', 5, None, None, DONE, [('status', 0, 2)], 'variant 5 (the cancel action raises)'),
    '31': (True, True, 'xcan', 7, None, None, DONE, [('status', 0, 2)], 'variant 7 (the cancel action drops)'),
    '32': (True, True, 'x90', 0, 14, None, DONE, [('status', 0, 2), ('status', 1, 0), ('rejected', 1, 0)], 'CE-0090: a submission during the release is accepted and never runs'),
    '33': (True, True, 'x90', 32, 14, None, DONE, [('status', 0, 2), ('status', 1, 2)], 'fixed twin 32 of CE-0090'),
    '34': (False, True, 'x90', 0, None, None, DONE, [('status', 0, 2), ('rejected', 1, 1)], 'sequential: the late concurrent submission throws'),
}

OVERLAP_STEP = {'26': 402}


def lean_bool(b):
    return 'true' if b else 'false'


def cs_expr(seed):
    return '[]' if seed is None else f'(sched {seed} 300)'


def drops(base, ds):
    e = base
    for d in ds:
        e = f'({e}.drop {d})'
    return e


def dump(par, aw, inp, v, seed, fuel):
    cmd = ['lake', 'env', 'lean', '--run', 'tools/DispRuns/Dump.lean', lean_bool(par), lean_bool(aw), inp,
           str(v), '-' if seed is None else str(seed), str(fuel), str(CHUNK)]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=True).stdout
    states, cur, end = [], None, None
    for line in out.splitlines():
        if line.startswith('step '):
            cur = [int(line.split()[1]), []]
            states.append(cur)
        elif line.startswith('end '):
            end = int(line.split()[1])
            cur = None
        elif cur is not None:
            cur[1].append(line)
    return [(k, '\n'.join(ls)) for k, ls in states], end


def obs_expr(term, halt, obs):
    parts = []
    if halt is not None:
        parts.append(f'({term}).halt == {halt}')
    for f, j, val in obs:
        if f == 'order':
            parts.append(f'order ({term}) == {val}')
        else:
            parts.append(f'{f} ({term}) {j} == {val}')
    return ' &&\n    '.join(parts)


HEADER = """import {imp}

/-! {doc}
Generated by `tools/DispRuns/gen.py` (track P7D, decision 55): {what}. -/

namespace {ns}

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase7.Dispatcher
open CatsEffectInLean.Proofs.Phase7.DispatcherCommon
"""


def gen(rid):
    par, aw, inp, v, seed, fuel, halt, obs, doc = RUNS[rid]
    if fuel == 'OVERLAP':
        fuel = OVERLAP_STEP[rid]
    states, end = dump(par, aw, inp, v, seed, fuel or 3000)
    n = end
    cs = cs_expr(seed)
    s0 = f'Sched.init counterMaskModel (prog {lean_bool(par)} {lean_bool(aw)} 1 .unit {inp}.ws.length {v})'
    envx = f'(env id {inp} u)'
    prev, prev_step, ds = s0, 0, []
    prev_mod = 'CatsEffectInLean.Proofs.Phase7.DispatcherCommon'
    for i, (k, rep) in enumerate(states, 1):
        d = k - prev_step
        mod = f'R{rid}S{i}'
        body = HEADER.format(imp=prev_mod, doc=f'Run {rid} ({doc}), chunk {i}: the state after {k} micro-steps.',
                             what='state literal from `Repr`, then the kernel check that the run reaches it', ns=f'{NS}.R{rid}')
        body += f'\n/-- The state after {k} micro-steps. -/\ndef S{i} : Sched CounterMask :=\n{rep}\n\n'
        body += (f'theorem reach{i} : runSchedStateP {{}} counterMaskModel {envx} {d} {drops(cs, ds)}\n'
                 f'    {"(" + prev + ")" if i == 1 else f"S{i - 1}"} = S{i} := by\n  decide +kernel\n\nend {NS}.R{rid}\n')
        (OUT / f'{mod}.lean').write_text(body)
        prev_mod = f'{NS}.{mod}'
        ds.append(d)
        prev_step = k
    r = n - prev_step
    last = f'({s0})' if not states else f'S{len(states)}'
    body = HEADER.format(imp=prev_mod, doc=f'Run {rid}: {doc}.', what='the last chunk and the composed fact', ns=f'{NS}.R{rid}')
    fin_term = f'runSchedStateP {{}} counterMaskModel {envx} {r} {drops(cs, ds)} {last}'
    body += f'\n/-- The last {r} micro-steps. -/\ntheorem fin :\n    ({obs_expr(fin_term, halt, obs)}) = true := by\n  decide +kernel\n\n'
    run_term = f'run id {lean_bool(par)} {lean_bool(aw)} 1 .unit {inp} u {n} {cs} {v}'
    split = ' + ('.join(str(d) for d in ds + [r]) + ')' * len(ds)
    rws = ', '.join(['runP_add, ' + f'reach{i}' for i in range(1, len(ds) + 1)])
    body += (f'/-- The run of {n} micro-steps. -/\ntheorem eq_fin : {run_term} =\n    {fin_term} := by\n'
             f'  show runSchedStateP {{}} counterMaskModel {envx} {n} {cs}\n    ({s0}) = _\n')
    if ds:
        body += f'  rw [show ({n} : Nat) = {split} from rfl, {rws}]\n'
    else:
        body += '  rfl\n'
    body += (f'\ntheorem obs :\n    ({obs_expr(run_term, halt, obs)}) = true := by\n'
             f'  rw [eq_fin]; exact fin\n\nend {NS}.R{rid}\n')
    (OUT / f'R{rid}.lean').write_text(body)
    return n, [k for k, _ in states]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ids = sys.argv[1:] or list(RUNS)
    for rid in ids:
        n, ks = gen(rid)
        print(f'R{rid}: {n} micro-steps, chunks at {ks}', flush=True)


if __name__ == '__main__':
    main()

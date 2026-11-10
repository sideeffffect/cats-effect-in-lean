#!/usr/bin/env python3
"""Seeded generator of difftest cases (format v1, JSON lines; v0 is a subset).

Spec of the format: wiki/methodology/difftest-program-format.md.
Design notes: wiki/methodology/differential-testing.md ("Generator").

- Type-directed: `Gen.prog(T, env, size)` makes a program of type T. Each case is checked
  with `typecheck.check_prog` (decision 8: a TypeError is a generator bug).
- Deterministic: case i of seed s depends only on (s, i) and the weight table.
- Edge-heavy: templates for escaped poll, poll in finalizers, racePair, Deferred handoff,
  async callbacks (0/1/2/3 calls, sync/later, with a finalizer), external cancel choices.
- Long-lived scenarios (decision 17, `tpl_scenario`): the root stays alive, so cancels and child
  steps really run. Run-event coverage: coverage.py.
- Format v2 (decision 51, track G): `guarantee`, `bracket`, `bracketCase`, `bracketFull` at any
  position, and `tpl_bracket` (the bracket in a started child that the parent cancels, so a
  cancel can land in acquire, use or release).
- Format v1 (decision 30): a root `syncStep` (`CONFIG['p_syncstep']`), `timeout`/`timeoutTo`
  around any program, `Queue.unbounded` ops (`tpl_queue`: producer/consumer, `take.timeout`, the
  CE-0003 shape), and `allocatedCase` of `Resource` trees (`g_res`). Programs inside resource
  nodes see no fiber or `Deferred` variables of the outer scope: the Lean `Resource` mirror builds
  them without a heap view (`Prog.resViewFree` in tools/Difftest/Prog.lean).

Usage:
  gen.py --seed 1 --n 1000 [--max-size 40] [--mode replay|testcontrol] [--out FILE]
"""

import argparse
import json
import random
import sys

from typecheck import check_prog

FORMAT_VERSION = 2
MAX_LIMIT = 2**31 - 1  # Int.MaxValue: the largest syncStep limit

# Region markers: `delay fn1 arg nat M` with M = MARK_BASE + kind * MARK_KIND + 2 * id + exit.
# They only add `call` trace events. coverage.py reads them to see what ran (decision 17).
MARK_BASE = 7_700_000_000
MARK_KIND = 1_000_000
MARK_UNC, MARK_FIN, MARK_ESC_POLL_FIN, MARK_JOIN, MARK_REL = 1, 2, 3, 4, 5

UNIT, BOOL, NAT = ('unit',), ('bool',), ('nat',)


def pair(a, b): return ('pair', a, b)
def either(a, b): return ('either', a, b)
def outcome(a): return ('outcome', a)
def fiber(a): return ('fiber', a)
def ref(a): return ('ref', a)
def deferred(a): return ('deferred', a)
def queue(a): return ('queue', a)


def race_type(a, b):
    return either(pair(outcome(a), fiber(b)), pair(fiber(a), outcome(b)))


def literalable(t):
    if t[0] in ('unit', 'bool', 'nat'):
        return True
    if t[0] in ('pair', 'either'):
        return literalable(t[1]) and literalable(t[2])
    if t[0] == 'outcome':
        return literalable(t[1])
    return False


# Weight table. A production is a candidate only when it fits the wanted type and the
# variables in scope. "tpl_*" are templates: small fixed shapes for known edge cases.
WEIGHTS = {
    'pure': 3, 'raise': 1.5, 'delay': 3, 'map': 2, 'bind': 6, 'seq': 4,
    'handleErrorWith': 2, 'attempt': 6,
    'uncancelable': 4, 'poll': 5, 'onCancel': 4, 'guaranteeCase': 4,
    'canceled': 4, 'cede': 3, 'never': 0.7, 'sleep': 1.5,
    'start': 4, 'join': 5, 'cancel': 5, 'racePair': 1,
    'refNew': 2, 'refGet': 3, 'refSet': 3, 'refModify': 3,
    'deferredNew': 2, 'deferredGet': 3, 'deferredComplete': 4,
    'async': 4, 'case': 2, 'split': 2,
    'tpl_escapedPoll': 3, 'tpl_race': 1.5, 'tpl_handoff': 1.5, 'tpl_cancelChild': 2.5, 'tpl_finStack': 4,
    'handle_boost': 2.5, 'tpl_ref': 1.5,
    'tpl_scenario': 3,  # parent + long-lived child + cancel (decision 17); see tpl_scenario
    'fn_raise': 0.4,  # relative weight of user function 3 (raise) in delay/map; others 1
    # format v1 (decision 30)
    'timeout': 1.2, 'timeoutTo': 0.35, 'allocatedCase': 2.2,
    'queueNew': 2, 'queueOffer': 3, 'queueTake': 3, 'queueTryTake': 6, 'tpl_queue': 2.2, 'tpl_resource': 1,
    'res_pure': 2.5, 'res_eval': 2.5, 'res_make': 3.5, 'res_flatMap': 12,
    # format v2 (track G)
    'guarantee': 1.5, 'bracket': 1.2, 'bracketCase': 1.2, 'bracketFull': 1.2, 'tpl_bracket': 1.5,
}

# Other knobs (probabilities and ranges).
CONFIG = {
    'p_cancel_case': 0.5,      # case gets one or more external {"cancel":h} choices
    'p_choices': 0.8,          # case gets a non-empty choice list
    'max_choices': 24,
    'p_small_maxsteps': 0.03,  # tiny maxSteps (fuel outcome)
    'poll_boost_fin': 3.0,     # poll weight factor inside finalizers
    'poll_boost_tpl': 3.0,     # poll weight factor inside the escaped-poll child
    'p_shadow': 0.05,          # reuse an existing value name (shadowing)
    'p_tag_omitted': 0.1,
    # decision 17: coverage of run events (measured by coverage.py)
    'p_scenario_root': 0.6,    # root program is a tpl_scenario (keeps the root alive)
    'p_scenario_ext': 0.4,     # a scenario uses an external {"cancel":h} choice, not `cancel f`
    'p_cancel_marker': 0.5,    # a generated `cancel f` gets a `delay fn1 f` marker before it
    'p_fifo_bias': 0.7,        # root scenario: choice list with mostly FIFO picks
    'p_hint_cancel': 0.95,     # use the scenario hint for external cancel choices
    # format v1
    'p_syncstep': 0.09,        # the root is `syncStep(prog, limit)`
    'p_queue_type': 0.1,       # bind_type gives a queue type
}


class Gen:
    def __init__(self, rng, weights=None, config=None):
        self.r = rng
        self.w = dict(WEIGHTS if weights is None else weights)
        self.c = dict(CONFIG if config is None else config)
        self.names = 0
        self.tags = 0
        self.rids = 0
        self.hints = []  # (fiber handle, lowest step, highest step) for external cancel choices
        self.fifo_bias = False  # root scenario: picks are mostly 0, so the planned timing holds

    # ------------------------------------------------------------ helpers

    def pick(self, opts):
        """opts: list of (weight, value). Weighted choice."""
        opts = [(w, v) for w, v in opts if w > 0]
        tot = sum(w for w, _ in opts)
        x = self.r.random() * tot
        for w, v in opts:
            x -= w
            if x < 0:
                return v
        return opts[-1][1]

    def fresh(self, pre, env=None):
        if pre == 'x' and env and self.r.random() < self.c['p_shadow']:
            vals = [n for n, b in env.items() if b[0] == 'val']
            if vals:
                return self.r.choice(vals)
        self.names += 1
        return f"{pre}{self.names}"

    def tag(self, d):
        if self.r.random() >= self.c['p_tag_omitted']:
            self.tags += 1
            d['tag'] = self.tags
        return d

    def nat_lit(self):
        n = self.pick([(5, 0), (5, 1), (3, 2), (2, 3), (2, 7), (0.05, 9 * 10**15)])
        return {'t': 'nat', 'v': n}

    def code(self):
        return self.pick([(4, 0), (4, 1), (2, 2), (1, 5)])

    def small_type(self):
        return self.pick([(4, NAT), (2, UNIT), (1.5, BOOL), (0.7, pair(NAT, NAT)),
                          (0.5, either(NAT, UNIT)), (0.3, outcome(NAT))])

    def lit_type(self, depth=0):
        """A random type that has literals (no handles). Depth limits nesting."""
        if depth > 1:
            return self.pick([(3, NAT), (1, UNIT), (1, BOOL)])
        k = self.pick([(4, 'nat'), (2, 'unit'), (1.5, 'bool'), (0.6, 'pair'), (0.6, 'either'), (0.3, 'outcome')])
        if k in ('nat', 'unit', 'bool'):
            return (k,)
        if k == 'outcome':
            return outcome(self.lit_type(depth + 1))
        return (k, self.lit_type(depth + 1), self.lit_type(depth + 1))

    def bind_type(self):
        a = self.small_type()
        return self.pick([(2, UNIT), (3, NAT), (1, BOOL), (0.7, pair(NAT, NAT)), (0.7, either(NAT, NAT)), (0.7, either(NAT, a)),
                          (0.5, outcome(a)), (3, fiber(a)), (2, ref(self.pick([(3, NAT), (1, a)]))),
                          (1.5, deferred(self.pick([(2, NAT), (1, UNIT), (1, a)]))),
                          (0.4, race_type(self.small_type(), self.small_type())),
                          (self.c['p_queue_type'] * 25, queue(self.pick([(3, NAT), (1, a)])))])

    def literal(self, t):
        k = t[0]
        if k == 'unit':
            return {'t': 'unit'}
        if k == 'bool':
            return {'t': 'bool', 'v': self.r.random() < 0.5}
        if k == 'nat':
            return self.nat_lit()
        if k == 'pair':
            return {'t': 'pair', 'a': self.literal(t[1]), 'b': self.literal(t[2])}
        if k == 'either':
            return {'t': 'left', 'v': self.literal(t[1])} if self.r.random() < 0.5 else \
                {'t': 'right', 'v': self.literal(t[2])}
        if k == 'outcome':
            x = self.r.random()
            if x < 0.5:
                return {'t': 'succeeded', 'v': self.literal(t[1])}
            if x < 0.8:
                return {'t': 'errored', 'code': self.code()}
            return {'t': 'canceled'}
        raise ValueError(t)

    @staticmethod
    def vars_of(env, pred):
        return [n for n, b in env.items() if b[0] == 'val' and pred(b[1])]

    @staticmethod
    def polls(env):
        return [n for n, b in env.items() if b[0] == 'poll']

    def atom(self, t, env):
        """An atom of type t, or None."""
        vs = self.vars_of(env, lambda u: u == t)
        if vs and (not literalable(t) or self.r.random() < 0.6):
            return {'t': 'var', 'x': self.r.choice(vs)}
        if literalable(t):
            return self.literal(t)
        return None

    def any_atom(self, env):
        vs = self.vars_of(env, lambda u: True)
        if vs and self.r.random() < 0.5:
            return {'t': 'var', 'x': self.r.choice(vs)}
        return self.literal(self.lit_type())

    def split_size(self, size, k):
        """Split size-1 into k positive parts (random)."""
        s = max(size - 1, k)
        cuts = sorted(self.r.randint(1, s - 1) for _ in range(k - 1)) if s > 1 else []
        parts, prev = [], 0
        for c in cuts + [s]:
            parts.append(max(1, c - prev))
            prev = c
        return parts

    # ------------------------------------------------------- user functions

    def fns_returning(self, t, env, as_prog):
        """(fn, argument type) pairs whose result has type t. With as_prog=False the argument
        must also be expressible as an atom."""
        out = []

        def ok(a):
            return as_prog or self.atom_possible(a, env)

        if ok(t):
            out.append((0, t))
        if t == UNIT:
            out.append((1, self.lit_type() if not as_prog else self.small_type()))
        if t == NAT:
            out.append((2, NAT))
        out.append((3, NAT))
        if t[0] == 'pair' and t[1] == t[2] and ok(t[1]):
            out.append((4, t[1]))
        if t == pair(NAT, NAT):
            out.append((5, NAT))
        if t == BOOL:
            out += [(6, BOOL), (7, NAT)]
        for fn, i in ((8, 1), (9, 2)):
            other = self.lit_type(1)
            a = pair(t, other) if i == 1 else pair(other, t)
            if ok(a):
                out.append((fn, a))
            else:
                ps = self.vars_of(env, lambda u: u[0] == 'pair' and u[i] == t)
                if ps:
                    out.append((fn, env[self.r.choice(ps)][1]))
        return out

    def atom_possible(self, t, env):
        return literalable(t) or bool(self.vars_of(env, lambda u: u == t))

    # ------------------------------------------------------------- programs

    def prog(self, t, env, size, ctx=None):
        ctx = ctx or {}
        w = self.w
        opts = []
        leaf = size <= 1
        polls = self.polls(env)
        pboost = ctx.get('pboost', 1.0)
        hb = w['handle_boost']  # productions that use a fiber/ref/deferred in scope

        # leaves
        if self.atom_possible(t, env):
            opts.append((w['pure'], lambda: {'op': 'pure', 'v': self.atom(t, env)}))
        opts.append((w['raise'], lambda: {'op': 'raise', 'code': self.code()}))
        opts.append((w['delay'], lambda: self.g_delay(t, env)))
        opts.append((w['never'] * (0.3 if ctx.get('root_path') else 1), lambda: {'op': 'never'}))
        if t == UNIT:
            opts += [(w['canceled'], lambda: {'op': 'canceled'}),
                     (w['cede'], lambda: {'op': 'cede'}),
                     (w['sleep'], lambda: {'op': 'sleep', 'ms': self.pick([(3, 0), (3, 1), (2, 10), (1, 100)])})]
            fibs = self.vars_of(env, lambda u: u[0] == 'fiber')
            if fibs:
                def g_cancel():
                    fv = {'t': 'var', 'x': self.r.choice(fibs)}
                    if self.r.random() < self.c['p_cancel_marker']:
                        return {'op': 'seq', 'ps': self.cancel_req(fv)}
                    return {'op': 'cancel', 'f': fv}
                opts.append((w['cancel'] * hb, g_cancel))
            rs = [x for x in self.vars_of(env, lambda u: u[0] == 'ref') if self.atom_possible(env[x][1][1], env)]
            if rs:
                def g_refset():
                    x = self.r.choice(rs)
                    return {'op': 'refSet', 'r': {'t': 'var', 'x': x}, 'v': self.atom(env[x][1][1], env)}
                opts.append((w['refSet'] * hb, g_refset))
        if t[0] == 'outcome':
            fs = self.vars_of(env, lambda u: u == fiber(t[1]))
            if fs:
                opts.append((w['join'] * hb, lambda: {'op': 'join', 'f': {'t': 'var', 'x': self.r.choice(fs)}}))
        if t[0] == 'ref' and self.atom_possible(t[1], env):
            opts.append((w['refNew'], lambda: {'op': 'refNew', 'v': self.atom(t[1], env)}))
        if t[0] == 'deferred':
            opts.append((w['deferredNew'], lambda: {'op': 'deferredNew'}))
        if t[0] == 'queue':
            opts.append((w['queueNew'], lambda: {'op': 'queueNew'}))
        opts += self.queue_opts(t, env)
        rg = self.vars_of(env, lambda u: u == ref(t))
        if rg:
            opts.append((w['refGet'] * hb, lambda: {'op': 'refGet', 'r': {'t': 'var', 'x': self.r.choice(rg)}}))
        rm = self.refmodify_opts(t, env)
        if rm:
            opts.append((w['refModify'] * hb, lambda: self.r.choice(rm)()))
        dg = self.vars_of(env, lambda u: u == deferred(t))
        if dg:
            opts.append((w['deferredGet'] * hb, lambda: {'op': 'deferredGet', 'd': {'t': 'var', 'x': self.r.choice(dg)}}))
        if t == BOOL:
            ds = [x for x in self.vars_of(env, lambda u: u[0] == 'deferred') if self.atom_possible(env[x][1][1], env)]
            if ds:
                def g_complete():
                    x = self.r.choice(ds)
                    return {'op': 'deferredComplete', 'd': {'t': 'var', 'x': x}, 'v': self.atom(env[x][1][1], env)}
                opts.append((w['deferredComplete'] * hb, g_complete))
        opts.append((w['async'], lambda: self.g_async(t, env, 1 if leaf else size, ctx)))
        if t[0] == 'fiber':
            opts.append((w['start'], lambda: {'op': 'start', 'e': self.prog(t[1], env, max(1, size - 1), self.child_ctx(ctx))}))
        if polls:
            opts.append((w['poll'] * pboost, lambda: {'op': 'poll', 'poll': self.r.choice(polls),
                                                     'e': self.prog(t, env, max(1, size - 1), ctx)}))

        if not leaf:
            opts += self.composite_opts(t, env, size, ctx)

        return self.pick(opts)()

    def queue_opts(self, t, env):
        """Queue ops of type t on the queues in scope (format v1)."""
        w, hb = self.w, self.w['handle_boost']
        opts = []
        qs = self.vars_of(env, lambda u: u[0] == 'queue')
        if t == UNIT:
            qo = [x for x in qs if self.atom_possible(env[x][1][1], env)]
            if qo:
                def g_offer():
                    x = self.r.choice(qo)
                    return {'op': 'queueOffer', 'q': {'t': 'var', 'x': x}, 'v': self.atom(env[x][1][1], env)}
                opts.append((w['queueOffer'] * hb, g_offer))
        qt = [x for x in qs if env[x][1][1] == t]
        if qt:
            opts.append((w['queueTake'] * hb, lambda: {'op': 'queueTake', 'q': {'t': 'var', 'x': self.r.choice(qt)}}))
        if t[0] == 'either' and t[1] == UNIT:
            qtt = [x for x in qs if env[x][1][1] == t[2]]
            if qtt:
                opts.append((w['queueTryTake'] * hb, lambda: {'op': 'queueTryTake', 'q': {'t': 'var', 'x': self.r.choice(qtt)}}))
        return opts

    def child_ctx(self, ctx):
        c = dict(ctx)
        c.pop('root_path', None)
        return c

    def refmodify_opts(self, t, env):
        out = []
        for x in self.vars_of(env, lambda u: u == ref(NAT)):
            out.append(lambda x=x: {'op': 'refModify', 'r': {'t': 'var', 'x': x}, 'fn': 3})
            if t == NAT:
                out.append(lambda x=x: {'op': 'refModify', 'r': {'t': 'var', 'x': x}, 'fn': 5})
        for x in self.vars_of(env, lambda u: u == ref(t)):
            out.append(lambda x=x: {'op': 'refModify', 'r': {'t': 'var', 'x': x}, 'fn': 4})
        return out

    def g_delay(self, t, env):
        fn, a = self.pick([(self.w['fn_raise'] if f == 3 else 1, (f, a)) for f, a in self.fns_returning(t, env, as_prog=False)])
        arg = self.atom(a, env) if fn != 1 else self.any_atom(env)
        d = {'op': 'delay', 'fn': fn}
        if not (arg == {'t': 'unit'} and self.r.random() < 0.5):
            d['arg'] = arg
        return d

    def g_async(self, t, env, size, ctx):
        n = self.pick([(2, 0), (4, 1), (3, 2), (1, 3)])
        cbs = []
        for _ in range(n):
            cb = {'when': 'sync' if self.r.random() < 0.5 else 'later'}
            if literalable(t) and self.r.random() < 0.75:
                cb['ok'] = self.literal(t)
            else:
                cb['err'] = self.code()
            cbs.append(cb)
        d = {'op': 'async', 'cbs': cbs}
        if size > 1 and self.r.random() < 0.6:
            d['fin'] = self.prog(self.small_type(), env, max(1, size - 1), self.fin_ctx(ctx))
            self.tag(d)
        return d

    def fin_ctx(self, ctx):
        c = self.child_ctx(ctx)
        c['pboost'] = max(c.get('pboost', 1.0), self.c['poll_boost_fin'])
        return c

    def composite_opts(self, t, env, size, ctx):
        w = self.w
        opts = []
        cc = self.child_ctx(ctx)

        def g_bind():
            s = self.bind_type()
            se, sk = self.split_size(size, 2)
            e = self.prog(s, env, se, cc)
            x = self.fresh('x', env)
            return {'op': 'bind', 'x': x, 'e': e, 'k': self.prog(t, {**env, x: ('val', s)}, sk, ctx)}
        opts.append((w['bind'], g_bind))

        def g_seq():
            n = self.pick([(4, 2), (2, 3), (1, 4)])
            parts = self.split_size(size, n)
            dfd = 3 if self.vars_of(env, lambda u: u[0] == 'deferred') else 0
            qs = self.vars_of(env, lambda u: u[0] == 'queue')
            qtt = either(UNIT, env[self.r.choice(qs)][1][1]) if qs else UNIT
            ps = [self.prog(self.pick([(6, UNIT), (1, self.small_type()), (dfd, BOOL), (2 if qs else 0, qtt)]), env, s, cc)
                  for s in parts[:-1]]
            ps.append(self.prog(t, env, parts[-1], ctx))
            return {'op': 'seq', 'ps': ps}
        opts.append((w['seq'], g_seq))

        fr = self.fns_returning(t, env, as_prog=True)

        def g_map():
            fn, a = self.pick([(self.w['fn_raise'] if f == 3 else 1, (f, a)) for f, a in fr])
            return {'op': 'map', 'e': self.prog(a, env, size - 1, cc), 'fn': fn}
        opts.append((w['map'], g_map))

        def g_hew():
            se, sk = self.split_size(size, 2)
            x = self.fresh('x', env)
            return {'op': 'handleErrorWith', 'e': self.prog(t, env, se, cc), 'x': x,
                    'k': self.prog(t, {**env, x: ('val', NAT)}, sk, ctx)}
        opts.append((w['handleErrorWith'], g_hew))

        if t[0] == 'either' and t[1] == NAT:
            opts.append((w['attempt'], lambda: {'op': 'attempt', 'e': self.prog(t[2], env, size - 1, cc)}))

        def g_unc():
            # reuse an outer poll name sometimes (shadowing a poll with a poll)
            ps = self.polls(env)
            q = self.r.choice(ps) if ps and self.r.random() < 0.15 else self.fresh('p')
            return {'op': 'uncancelable', 'poll': q, 'body': self.prog(t, {**env, q: ('poll',)}, size - 1, cc)}
        opts.append((w['uncancelable'], g_unc))

        def g_oncancel():
            se, sf = self.split_size(size, 2)
            return self.tag({'op': 'onCancel', 'e': self.prog(t, env, se, cc),
                             'fin': self.prog(self.small_type(), env, sf, self.fin_ctx(ctx))})
        opts.append((w['onCancel'], g_oncancel))

        def g_gc():
            se, sf = self.split_size(size, 2)
            x = self.fresh('x', env)
            return self.tag({'op': 'guaranteeCase', 'e': self.prog(t, env, se, cc), 'x': x,
                             'fin': self.prog(self.small_type(), {**env, x: ('val', outcome(t))}, sf, self.fin_ctx(ctx))})
        opts.append((w['guaranteeCase'], g_gc))

        # ---- format v2 (track G)
        def g_guarantee():
            se, sf = self.split_size(size, 2)
            return self.tag({'op': 'guarantee', 'e': self.prog(t, env, se, cc),
                             'fin': self.prog(self.small_type(), env, sf, self.fin_ctx(ctx))})
        opts.append((w['guarantee'], g_guarantee))
        for op in ('bracket', 'bracketCase', 'bracketFull'):
            opts.append((w[op], (lambda op=op: self.g_bracket(op, t, env, size, ctx))))
        if size >= 5:
            opts.append((w['tpl_bracket'], lambda: self.tpl_bracket(t, env, size, ctx)))

        if t[0] == 'either' and t[1][0] == 'pair' and t[1][1][0] == 'outcome' and t == race_type(t[1][1][1], t[2][1][1]):
            def g_race():
                sa, sb = self.split_size(size, 2)
                return {'op': 'racePair', 'a': self.prog(t[1][1][1], env, sa, cc), 'b': self.prog(t[2][1][1], env, sb, cc)}
            opts.append((w['racePair'] * 4, g_race))

        eits = [x for x in self.vars_of(env, lambda u: u[0] == 'either')]
        if eits or self.r.random() < 0.3:
            def g_case():
                if eits and self.r.random() < 0.8:
                    x = self.r.choice(eits)
                    on, (a, b) = {'t': 'var', 'x': x}, env[x][1][1:]
                else:
                    et = either(self.lit_type(1), self.lit_type(1))
                    on, (a, b) = self.literal(et), et[1:]
                sl, sr = self.split_size(size, 2)
                l, r = self.fresh('x', env), self.fresh('x', env)
                return {'op': 'case', 'on': on, 'l': l, 'lk': self.prog(t, {**env, l: ('val', a)}, sl, ctx),
                        'r': r, 'rk': self.prog(t, {**env, r: ('val', b)}, sr, ctx)}
            opts.append((w['case'], g_case))

        prs = self.vars_of(env, lambda u: u[0] == 'pair')
        if prs or self.r.random() < 0.3:
            def g_split():
                if prs and self.r.random() < 0.8:
                    x = self.r.choice(prs)
                    on, (a, b) = {'t': 'var', 'x': x}, env[x][1][1:]
                else:
                    pt = pair(self.lit_type(1), self.lit_type(1))
                    on, (a, b) = self.literal(pt), pt[1:]
                xa, xb = self.fresh('x', env), self.fresh('x', env)
                env2 = {**env, xa: ('val', a)}
                env2[xb] = ('val', b)
                return {'op': 'split', 'on': on, 'a': xa, 'b': xb, 'k': self.prog(t, env2, size - 1, ctx)}
            opts.append((w['split'], g_split))

        # ---- format v1
        opts.append((w['timeout'], lambda: {'op': 'timeout', 'e': self.timeout_source(t, env, size - 1, cc), 'ms': self.timeout_ms()}))
        if size >= 3:
            def g_timeout_to():
                se, sf = self.split_size(size, 2)
                return {'op': 'timeoutTo', 'e': self.timeout_source(t, env, se, cc), 'ms': self.timeout_ms(),
                        'fb': self.prog(t, env, sf, cc)}
            opts.append((w['timeoutTo'], g_timeout_to))
        if self.res_ok(t):
            opts.append((w['allocatedCase'], lambda: {'op': 'allocatedCase', 'res': self.g_res(t, env, size - 1, cc)}))

        # ---- templates
        if size >= 4:
            opts.append((w['tpl_escapedPoll'], lambda: self.tpl_escaped_poll(t, env, size, ctx)))
            opts.append((w['tpl_cancelChild'], lambda: self.tpl_cancel_child(t, env, size, ctx)))
        if size >= 3:
            opts.append((w['tpl_finStack'], lambda: self.tpl_fin_stack(t, env, size, ctx)))
        if size >= 5:
            opts.append((w['tpl_race'], lambda: self.tpl_race(t, env, size, ctx)))
            opts.append((w['tpl_handoff'], lambda: self.tpl_handoff(t, env, size, ctx)))
            opts.append((w['tpl_ref'], lambda: self.tpl_ref(t, env, size, ctx)))
        if size >= 6:
            opts.append((w['tpl_scenario'], lambda: self.tpl_scenario(t, env, size, ctx)))
        if size >= 4:
            opts.append((w['tpl_queue'], lambda: self.tpl_queue(t, env, size, ctx)))
        if size >= 4 and self.res_ok(t):
            opts.append((w['tpl_resource'], lambda: self.tpl_resource(t, env, size, cc)))
        return opts

    # ------------------------------------------------------- format v2

    def g_bracket(self, op, t, env, size, ctx, acq=None, acq_type=None):
        """`bracket`, `bracketCase` or `bracketFull` of type `t`: acquire of a bind type, use of
        type `t`, release of a small type (it sees `x`, and `y` = the outcome of use)."""
        cc = self.child_ctx(ctx)
        sa, su, sr = self.split_size(size, 3)
        a = self.bind_type() if acq is None else acq_type
        p = {'op': op}
        if op == 'bracketFull':
            q = self.fresh('p')
            p['poll'] = q
            actx = dict(cc)
            actx['pboost'] = max(actx.get('pboost', 1.0), self.c['poll_boost_fin'])
            p['acq'] = acq if acq is not None else self.prog(a, {**env, q: ('poll',)}, sa, actx)
        else:
            p['acq'] = acq if acq is not None else self.prog(a, env, sa, cc)
        x = self.fresh('x', env)
        p['x'] = x
        uenv = {**env, x: ('val', a)}
        p['use'] = self.prog(t, uenv, su, cc)
        renv = dict(uenv)
        if op != 'bracket':
            y = self.fresh('x', renv)
            p['y'] = y
            renv[y] = ('val', outcome(t))
        p['rel'] = self.prog(self.small_type(), renv, sr, self.fin_ctx(ctx))
        return self.tag(p)

    def tpl_bracket(self, t, env, size, ctx):
        """bind f = start(bracket*(acq, use, rel)) in seq(cedes, cancel f, maybe join f, k). The
        acquire and the use often suspend first (cede, sleep), so the cancel can land in either."""
        a = self.small_type()
        sc, sk = self.split_size(size, 2)
        op = self.pick([(1, 'bracket'), (1, 'bracketCase'), (1.3, 'bracketFull')])
        acq = None
        if self.r.random() < 0.6:
            wait = self.pick([(3, {'op': 'cede'}), (2, {'op': 'sleep', 'ms': self.pick([(1, 0), (2, 1), (1, 10)])}),
                              (1, {'op': 'canceled'})])
            acq = {'op': 'seq', 'ps': [wait, {'op': 'pure', 'v': self.nat_lit()}]}
        child = self.g_bracket(op, a, env, max(3, sc), ctx, acq=acq, acq_type=NAT)
        f = self.fresh('x')
        fv = {'t': 'var', 'x': f}
        env2 = {**env, f: ('val', fiber(a))}
        ps = [{'op': 'cede'} for _ in range(self.pick([(2, 0), (2, 1), (2, 2), (1, 4)]))]
        ps.append({'op': 'cancel', 'f': fv})
        k = self.prog(t, env2, sk, ctx)
        if self.r.random() < 0.6:
            ps.append(self.join_marked(fv, a, k, env2))
        else:
            ps.append(k)
        return {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': child}, 'k': {'op': 'seq', 'ps': ps}}

    # ------------------------------------------------------- format v1

    def timeout_source(self, t, env, size, ctx):
        """The source of a `timeout`: often it first waits (sleep, cede or never), so the timeout
        can fire."""
        e = self.prog(t, env, size, ctx)
        k = self.pick([(5, 'plain'), (4, 'sleep'), (1, 'cede'), (0.6, 'never')])
        if k == 'never':
            return {'op': 'never'}
        if k == 'plain':
            return e
        w = {'op': 'cede'} if k == 'cede' else {'op': 'sleep', 'ms': self.pick([(2, 1), (3, 10), (2, 100), (1, 2000)])}
        return {'op': 'seq', 'ps': [w, e]}

    def timeout_ms(self):
        return self.pick([(2, 0), (3, 1), (3, 10), (1, 100), (1, 1000)])

    @staticmethod
    def res_ok(t):
        """A resource value type: no handle types (the Lean mirror builds resource programs
        without a heap view, so no `join`/`cancel`/`deferredGet` on a bound handle)."""
        return literalable(t)

    @staticmethod
    def res_env(env):
        """The scope of a program inside a resource node: no fiber or Deferred variables."""
        return {k: b for k, b in env.items() if not (b[0] == 'val' and b[1][0] in ('fiber', 'deferred'))}

    def g_res(self, t, env, size, ctx):
        """A resource tree of value type t (format v1): rPure, rEval, rMake, rFlatMap."""
        w = self.w
        env = self.res_env(env)
        opts = []
        if self.atom_possible(t, env):
            opts.append((w['res_pure'], lambda: {'op': 'rPure', 'v': self.atom(t, env)}))
        opts.append((w['res_eval'], lambda: {'op': 'rEval', 'e': self.prog(t, env, max(1, size - 1), ctx)}))

        opts.append((w['res_make'], lambda: self.res_make(t, env, size, ctx)))
        if size >= 2:
            def g_flat():
                s = self.small_type()
                sa, sk = self.split_size(size, 2)
                x = self.fresh('x', env)
                kenv = {**env, x: ('val', s)}
                k = self.g_res(t, kenv, sk, ctx)
                f = self.pick([(3, 'plain'), (2, 'raise'), (1, 'canceled')])
                if f != 'plain':
                    # the rest fails or is canceled: the release of the earlier resources runs
                    stop = {'op': 'raise', 'code': self.code()} if f == 'raise' else {'op': 'canceled'}
                    k = {'op': 'rFlatMap', 'res': {'op': 'rEval', 'e': stop if f == 'raise' else
                                                   {'op': 'seq', 'ps': [stop, {'op': 'pure', 'v': {'t': 'unit'}}]}},
                         'x': self.fresh('x'), 'k': k}
                # often a `make` first: its release runs when the rest fails
                first = self.res_make(s, env, sa, ctx) if self.r.random() < 0.5 else self.g_res(s, env, sa, ctx)
                return {'op': 'rFlatMap', 'res': first, 'x': x, 'k': k}
            opts.append((w['res_flatMap'], g_flat))
        return self.pick(opts)()

    def res_make(self, t, env, size, ctx):
        """`rMake(acq, x, rel)` of value type t. `env` is a resource scope (`res_env`)."""
        sa, sr = self.split_size(max(size, 3), 2)
        x = self.fresh('x', env)
        rel = self.prog(self.small_type(), {**env, x: ('val', t)}, sr, self.fin_ctx(ctx))
        if self.r.random() < 0.8:  # a marker: the trace shows that the release ran
            self.rids += 1
            rel = {'op': 'seq', 'ps': [self.mark(MARK_REL, self.rids), rel]}
        return {'op': 'rMake', 'acq': self.prog(t, self.res_env(env), sa, ctx), 'x': x, 'rel': rel}

    def tpl_resource(self, t, env, size, ctx):
        """allocatedCase(rFlatMap(rMake(acq, x, rel), y, rest)): the rest often waits, fails or is
        canceled, so the release `rel(ExitCase)` runs (`Resource.scala:507-510`)."""
        renv = self.res_env(env)
        s = self.small_type()
        sm, sk = self.split_size(size - 1, 2)
        y = self.fresh('x', renv)
        kenv = {**renv, y: ('val', s)}
        stop = self.pick([(3, {'op': 'raise', 'code': self.code()}), (2, {'op': 'canceled'}), (2, {'op': 'cede'}),
                          (1, {'op': 'sleep', 'ms': 1}), (1, {'op': 'never'})])
        rest = {'op': 'rEval', 'e': {'op': 'seq', 'ps': [stop, self.prog(t, kenv, max(1, sk - 2), ctx)]}}
        return {'op': 'allocatedCase', 'res': {'op': 'rFlatMap', 'res': self.res_make(s, renv, sm, ctx), 'x': y, 'k': rest}}

    def tpl_queue(self, t, env, size, ctx):
        """bind q = queueNew in a producer/consumer scenario: consumers `take` (often with
        `timeout`, the CE-0003 shape) in started fibers, the parent offers, cancels or joins a
        consumer, and drains with `tryTake`."""
        a = self.pick([(4, NAT), (1, UNIT), (1, BOOL)])
        q = self.fresh('x')
        qv = {'t': 'var', 'x': q}
        env2 = {**env, q: ('val', queue(a))}
        take = {'op': 'queueTake', 'q': qv}
        ps = []
        cons = []
        for _ in range(self.pick([(1, 0), (4, 1), (2, 2)])):
            c = take if self.r.random() < 0.5 else {'op': 'timeout', 'e': take, 'ms': self.timeout_ms()}
            if self.r.random() < 0.25:
                c = self.tag({'op': 'onCancel', 'e': c, 'fin': self.prog(UNIT, env2, 1, self.fin_ctx(ctx))})
            f = self.fresh('x')
            cons.append(f)
            ps.append(('bind', f, {'op': 'start', 'e': c}))
        env3 = dict(env2)
        for f in cons:
            env3[f] = ('val', fiber(a))
        steps = []
        for _ in range(self.r.randint(1, 5)):
            k = self.pick([(4, 'offer'), (2, 'cede'), (1, 'sleep'), (2 if cons else 0, 'cancel'), (2 if cons else 0, 'join'),
                           (3, 'tryTake'), (1, 'take')])
            if k == 'offer':
                steps.append({'op': 'queueOffer', 'q': qv, 'v': self.literal(a)})
            elif k == 'cede':
                steps.append({'op': 'cede'})
            elif k == 'sleep':
                steps.append({'op': 'sleep', 'ms': self.pick([(2, 0), (3, 1), (1, 10)])})
            elif k == 'cancel':
                steps.append({'op': 'cancel', 'f': {'t': 'var', 'x': self.r.choice(cons)}})
            elif k == 'join':
                steps.append(self.join_marked({'t': 'var', 'x': self.r.choice(cons)}, a, {'op': 'cede'}, env3))
            elif k == 'tryTake':
                steps.append(self.trytake_marked(qv, a, env3))
            else:
                # the parent takes too: `attempt(timeout(take q))`, the result dropped
                steps.append({'op': 'map', 'e': {'op': 'attempt', 'e': {'op': 'timeout', 'e': take, 'ms': self.timeout_ms()}},
                              'fn': 1})
        if self.r.random() < 0.5:  # drain (CE-0003 program A)
            steps += [self.trytake_marked(qv, a, env3) for _ in range(self.pick([(2, 1), (1, 2)]))]
        k = self.prog(t, env3, max(1, size - len(steps) - 2), ctx)
        body = {'op': 'seq', 'ps': steps + [k]}
        for _, f, e in reversed(ps):
            body = {'op': 'bind', 'x': f, 'e': e, 'k': body}
        return {'op': 'bind', 'x': q, 'e': {'op': 'queueNew'}, 'k': body}

    def trytake_marked(self, qv, a, env):
        """bind r = tryTake q in delay fn1 r: the trace shows the result."""
        r = self.fresh('x')
        return {'op': 'bind', 'x': r, 'e': {'op': 'queueTryTake', 'q': qv},
                'k': {'op': 'delay', 'fn': 1, 'arg': {'t': 'var', 'x': r}}}

    # ------------------------------------------------------------ templates

    def tpl_escaped_poll(self, t, env, size, ctx):
        """bind f = uncancelable(p => start(child that uses p)) in k.
        The child runs after the uncancelable region ended (escaped poll). Often the poll is
        used inside a finalizer of the child."""
        a = self.small_type()
        sc, sk = self.split_size(size, 2)
        p = self.fresh('p')
        penv = {**env, p: ('poll',)}
        cctx = {'pboost': self.c['poll_boost_tpl']}
        shape = self.pick([(2, 'poll'), (2, 'finpoll'), (1, 'gcpoll'), (1, 'free')])
        if shape == 'poll':
            child = {'op': 'poll', 'poll': p, 'e': self.prog(a, penv, max(1, sc - 1), cctx)}
        elif shape == 'finpoll':
            body = self.prog(a, penv, max(1, sc // 2), cctx)
            if self.r.random() < 0.5:  # give the parent's cancel a chance to find the child suspended
                body = {'op': 'seq', 'ps': [self.suspend_point(penv), body]}
            child = self.tag({'op': 'onCancel', 'e': body,
                              'fin': {'op': 'poll', 'poll': p, 'e': self.esc_marked(self.prog(UNIT, penv, max(1, sc // 2), cctx))}})
        elif shape == 'gcpoll':
            x = self.fresh('x')
            fenv = {**penv, x: ('val', outcome(a))}
            child = self.tag({'op': 'guaranteeCase', 'e': self.prog(a, penv, max(1, sc // 2), cctx), 'x': x,
                              'fin': {'op': 'seq', 'ps': [{'op': 'poll', 'poll': p, 'e': self.esc_marked(self.prog(UNIT, fenv, 1, cctx))},
                                                          self.prog(UNIT, fenv, max(1, sc // 2), cctx)]}})
        else:
            child = self.prog(a, penv, sc, cctx)
        f = self.fresh('x')
        unc = {'op': 'uncancelable', 'poll': p, 'body': {'op': 'start', 'e': child}}
        if self.r.random() < 0.4:  # do more work inside the region after the start
            g = self.fresh('x')
            unc['body'] = {'op': 'bind', 'x': g, 'e': {'op': 'start', 'e': child},
                           'k': {'op': 'seq', 'ps': [self.prog(UNIT, {**penv, g: ('val', fiber(a))}, 2, {}),
                                                     {'op': 'pure', 'v': {'t': 'var', 'x': g}}]}}
        fenv = {**env, f: ('val', fiber(a))}
        k = self.prog(t, fenv, sk, ctx)
        if shape in ('finpoll', 'gcpoll') and self.r.random() < 0.7:
            # keep the parent alive until the child ran (else the finalizer never runs)
            fv = {'t': 'var', 'x': f}
            ps = self.cedes(self.pick([(1, 0), (2, 1), (1, 2)]))
            if shape == 'finpoll' or self.r.random() < 0.3:
                ps += self.cancel_req(fv)
            ps.append(self.join_marked(fv, a, k, fenv))
            k = {'op': 'seq', 'ps': ps}
        return {'op': 'bind', 'x': f, 'e': unc, 'k': k}

    def tpl_cancel_child(self, t, env, size, ctx):
        """bind f = start(child) in seq(maybe cede, cancel f, maybe join f, k)."""
        a = self.small_type()
        sc, sk = self.split_size(size, 2)
        f = self.fresh('x')
        fv = {'t': 'var', 'x': f}
        env2 = {**env, f: ('val', fiber(a))}
        ps = []
        for _ in range(self.pick([(2, 0), (2, 1), (1, 2)])):
            ps.append({'op': 'cede'})
        if self.r.random() < self.c['p_cancel_marker']:
            ps += self.cancel_req(fv)
        else:
            ps.append({'op': 'cancel', 'f': fv})
        k = self.prog(t, env2, sk, ctx)
        x = self.r.random()
        if x < 0.3:
            ps.append({'op': 'join', 'f': fv})
            ps.append(k)
        elif x < 0.6:
            ps.append(self.join_marked(fv, a, k, env2))
        else:
            ps.append(k)
        if sc >= 3 and self.r.random() < 0.6:
            child = self.tpl_fin_stack(a, env, sc, self.child_ctx(ctx))
        else:
            child = self.prog(a, env, sc, self.child_ctx(ctx))
        return {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': child}, 'k': {'op': 'seq', 'ps': ps}}

    def suspend_point(self, env):
        """A program of type unit where the fiber can be canceled: it ends the current task or
        it is a cancel point."""
        opts = [(3, {'op': 'cede'}), (2, {'op': 'canceled'}), (1.5, {'op': 'never'}),
                (1, {'op': 'sleep', 'ms': self.pick([(1, 0), (2, 1), (1, 10)])}),
                (2, {'op': 'async', 'cbs': self.pick([(2, []), (2, [{'when': 'later', 'ok': {'t': 'unit'}}])])})]
        ps = self.polls(env)
        if ps:
            opts.append((2, {'op': 'poll', 'poll': self.r.choice(ps), 'e': self.pick([(1, {'op': 'canceled'}), (1, {'op': 'cede'})])}))
        ds = self.vars_of(env, lambda u: u == deferred(UNIT))
        if ds:
            opts.append((1, {'op': 'deferredGet', 'd': {'t': 'var', 'x': self.r.choice(ds)}}))
        return self.pick(opts)

    def tpl_fin_stack(self, t, env, size, ctx):
        """1-3 layers of onCancel/guaranteeCase/async-finalizer around a core with a cancel or
        suspend point. Finalizers can raise, use an outer poll, or suspend."""
        layers = self.pick([(3, 1), (3, 2), (1, 3)])
        parts = self.split_size(size, layers + 1)
        cc = self.child_ctx(ctx)
        core_rest = self.prog(t, env, parts[0], cc)
        core = {'op': 'seq', 'ps': [self.suspend_point(env), core_rest] if self.r.random() < 0.7
                else [self.prog(UNIT, env, 1, cc), self.suspend_point(env), core_rest]}
        if self.r.random() < 0.25:
            core = {'op': 'seq', 'ps': [self.tag({'op': 'async', 'cbs': self.pick([(2, []), (1, [{'when': 'later', 'ok': {'t': 'unit'}}])]),
                                                  'fin': self.g_fin(env, 2, ctx)}), core]}
        e = core
        for i in range(layers):
            if self.r.random() < 0.5:
                e = self.tag({'op': 'onCancel', 'e': e, 'fin': self.g_fin(env, parts[i + 1], ctx)})
            else:
                x = self.fresh('x', env)
                e = self.tag({'op': 'guaranteeCase', 'e': e, 'x': x,
                              'fin': self.g_fin({**env, x: ('val', outcome(t))}, parts[i + 1], ctx)})
        return e

    def g_fin(self, env, size, ctx):
        k = self.pick([(4, 'any'), (1.5, 'raise'), (1, 'suspend')])
        if k == 'raise':
            return {'op': 'raise', 'code': self.code()}
        if k == 'suspend':
            sp = [self.suspend_point(env)]
            if self.r.random() < 0.6:  # markers: coverage.py sees a cancel that lands here
                sp = self.region(MARK_FIN, sp)
            return {'op': 'seq', 'ps': sp + [self.prog(UNIT, env, max(1, size - 1), self.fin_ctx(ctx))]}
        return self.prog(self.small_type(), env, size, self.fin_ctx(ctx))

    def tpl_race(self, t, env, size, ctx):
        """bind r = racePair(a, b) in case r of left(o,fb) => k1 | right(fa,o) => k2."""
        a, b = self.small_type(), self.small_type()
        sa, sb, s1, s2 = self.split_size(size, 4)
        cc = self.child_ctx(ctx)
        r = self.fresh('x')
        l, rr = self.fresh('x'), self.fresh('x')
        o1, f1, f2, o2 = (self.fresh('x') for _ in range(4))
        lk = {'op': 'split', 'on': {'t': 'var', 'x': l}, 'a': o1, 'b': f1,
              'k': self.prog(t, {**env, o1: ('val', outcome(a)), f1: ('val', fiber(b))}, s1, ctx)}
        rk = {'op': 'split', 'on': {'t': 'var', 'x': rr}, 'a': f2, 'b': o2,
              'k': self.prog(t, {**env, f2: ('val', fiber(a)), o2: ('val', outcome(b))}, s2, ctx)}
        return {'op': 'bind', 'x': r, 'e': {'op': 'racePair', 'a': self.prog(a, env, sa, cc), 'b': self.prog(b, env, sb, cc)},
                'k': {'op': 'case', 'on': {'t': 'var', 'x': r}, 'l': l, 'lk': lk, 'r': rr, 'rk': rk}}

    def tpl_ref(self, t, env, size, ctx):
        """bind r = refNew(n) in bind f = start(updates of r) in seq(updates of r, k)."""
        a = self.pick([(4, NAT), (1, pair(NAT, NAT))])
        sc, sk = self.split_size(size, 2)
        r, f = self.fresh('x'), self.fresh('x')
        renv = {**env, r: ('val', ref(a))}
        rv = {'t': 'var', 'x': r}

        def upd():
            k = self.pick([(3, 'modify'), (2, 'set'), (1, 'cede'), (1, 'get')])
            if k == 'modify':
                return {'op': 'refModify', 'r': rv, 'fn': 5 if a == NAT and self.r.random() < 0.7 else 4}
            if k == 'set':
                return {'op': 'refSet', 'r': rv, 'v': self.literal(a)}
            if k == 'get':
                return {'op': 'refGet', 'r': rv}
            return {'op': 'cede'}
        ct = self.small_type()
        child = {'op': 'seq', 'ps': [upd() for _ in range(self.r.randint(1, 3))] + [self.prog(ct, renv, sc, self.child_ctx(ctx))]}
        kenv = {**renv, f: ('val', fiber(ct))}
        k = {'op': 'seq', 'ps': [upd() for _ in range(self.r.randint(1, 3))] + [self.prog(t, kenv, sk, ctx)]}
        return {'op': 'bind', 'x': r, 'e': {'op': 'refNew', 'v': self.literal(a)},
                'k': {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': child}, 'k': k}}

    def tpl_handoff(self, t, env, size, ctx, force_race=False):
        """bind d = deferredNew in bind f = start(... deferredGet d ...) in k (k may complete d)."""
        a = self.pick([(3, NAT), (1, UNIT), (1, BOOL)])
        sc, sk = self.split_size(size, 2)
        d, f = self.fresh('x'), self.fresh('x')
        denv = {**env, d: ('val', deferred(a))}
        child = self.prog(a, denv, sc, self.child_ctx(ctx))
        if self.r.random() < 0.7:
            child = {'op': 'seq', 'ps': [{'op': 'deferredGet', 'd': {'t': 'var', 'x': d}}, child]} if self.r.random() < 0.5 \
                else {'op': 'deferredGet', 'd': {'t': 'var', 'x': d}}
        dv = {'t': 'var', 'x': d}
        race = force_race or self.r.random() < 0.45  # the child also completes d: one `complete` returns false
        if race:
            pre = self.cedes(self.pick([(2, 0), (2, 1), (1, 2)]))
            child = {'op': 'seq', 'ps': pre + [{'op': 'deferredComplete', 'd': dv, 'v': self.literal(a)}, child]}
        kenv = {**denv, f: ('val', fiber(a))}
        k = self.prog(t, kenv, sk, ctx)
        if race:
            ps = self.cedes(self.pick([(2, 0), (2, 1), (1, 2)]))
            ps.append({'op': 'deferredComplete', 'd': dv, 'v': self.literal(a)})
            if self.r.random() < 0.2:
                ps.append({'op': 'deferredComplete', 'd': dv, 'v': self.literal(a)})
            ps.append(self.pick([(2, {'op': 'join', 'f': {'t': 'var', 'x': f}}), (1, {'op': 'deferredGet', 'd': dv}), (1, {'op': 'cede'})]))
            k = {'op': 'seq', 'ps': ps + [k]}
        elif self.r.random() < 0.7:
            k = {'op': 'seq', 'ps': [{'op': 'deferredComplete', 'd': dv, 'v': self.literal(a)}, k]}
        return {'op': 'bind', 'x': d, 'e': {'op': 'deferredNew'},
                'k': {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': child}, 'k': k}}

    # ------------------------------------------------- decision 17 helpers

    def mark(self, kind, rid, exit_=False):
        return {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': MARK_BASE + kind * MARK_KIND + 2 * rid + (1 if exit_ else 0)}}

    def region(self, kind, ps):
        """seq(enter marker, ps..., exit marker); the value of the region is unit."""
        self.rids += 1
        return [self.mark(kind, self.rids)] + ps + [self.mark(kind, self.rids, True)]

    @staticmethod
    def cedes(n):
        return [{'op': 'cede'} for _ in range(n)]

    @staticmethod
    def cancel_req(fv):
        """`delay fn1 f` (trace event: a cancel request on f follows), then `cancel f`."""
        return [{'op': 'delay', 'fn': 1, 'arg': fv}, {'op': 'cancel', 'f': fv}]

    def esc_marked(self, p):
        """An escaped-poll body inside a finalizer: a marker shows that it ran."""
        self.rids += 1
        return {'op': 'seq', 'ps': [self.mark(MARK_ESC_POLL_FIN, self.rids), p]}

    def join_marked(self, fv, a, k, env):
        """bind o = join f in seq(join marker, delay fn1 o, k): the trace shows the join result."""
        o = self.fresh('x')
        self.rids += 1
        return {'op': 'bind', 'x': o, 'e': {'op': 'join', 'f': fv},
                'k': {'op': 'seq', 'ps': [self.mark(MARK_JOIN, self.rids), {'op': 'delay', 'fn': 1, 'arg': {'t': 'var', 'x': o}}, k]}}

    def tpl_scenario(self, t, env, size, ctx, root_first=False):
        """Parent starts a long-lived child, cedes n times, then cancels it (`cancel f`, or an
        external {"cancel":h} choice), and often joins it (decision 17: an external cancel acts
        only between tasks, so the parent must stay alive). The child has a shape that makes
        the cancel land at a chosen point. n is in a window [lo, hi] such that, under FIFO
        (the parent and the child take turns at each cede), the cancel lands at that point:
        - masked: inside an uncancelable region with cede points (then the region exits);
        - fin: inside the core (finalizer sees `canceled`) or inside a finalizer with cede points;
        - cb: while the child waits in an async with a later callback (often with a finalizer);
        - nested: after the child started a grandchild;
        - escpoll: the child got an escaped poll and uses it inside its finalizer;
        - complete: `tpl_handoff` where the parent and the child both complete a Deferred."""
        kind = self.pick([(4, 'masked'), (6, 'fin'), (4, 'cb'), (3, 'nested'), (3, 'escpoll'), (3, 'complete')])
        if kind == 'complete':
            return self.tpl_handoff(t, env, max(size, 5), ctx, force_race=True)
        a = self.small_type()
        sc, sk = self.split_size(max(size, 3), 2)
        cc = self.child_ctx(ctx)
        f = self.fresh('x')
        fv = {'t': 'var', 'x': f}
        env2 = {**env, f: ('val', fiber(a))}
        small = self.prog(a, env, self.pick([(2, 1), (1, 2)]), cc)
        start = None
        if kind == 'masked':
            q = self.fresh('p')
            m = self.pick([(2, 1), (2, 2), (1, 3)])
            inner = self.cedes(m)
            if self.r.random() < 0.3:
                inner.insert(0, {'op': 'async', 'cbs': [{'when': 'later', 'ok': {'t': 'unit'}}]})
                m += 1
            ps = self.region(MARK_UNC, inner)
            if self.r.random() < 0.4:
                ps.append({'op': 'poll', 'poll': q, 'e': self.pick([(2, {'op': 'cede'}), (1, {'op': 'canceled'})])})
            child = {'op': 'uncancelable', 'poll': q, 'body': {'op': 'seq', 'ps': ps + [small]}}
            if self.r.random() < 0.5:
                # a cancel point after the region (the child keeps running after the exit)
                child = {'op': 'seq', 'ps': [child, self.suspend_point(env), self.prog(a, env, max(1, sc - 4), cc)]}
            lo, hi = 1, m
        elif kind in ('fin', 'escpoll'):
            c = self.pick([(1, 0), (2, 1), (1, 2)]) if kind == 'fin' else self.pick([(2, 1), (1, 2)])
            if self.r.random() < 0.7:  # a core without suspension keeps the planned timing
                small = {'op': 'pure', 'v': self.literal(a)} if self.r.random() < 0.5 else self.g_delay(a, env)
            core = {'op': 'seq', 'ps': self.cedes(c) + [small]}
            if kind == 'fin' and self.r.random() < 0.3:
                core = {'op': 'seq', 'ps': [self.tag({'op': 'async', 'cbs': self.pick([(1, []), (1, [{'when': 'later', 'ok': {'t': 'unit'}}])]),
                                                      'fin': self.g_fin(env, 2, ctx)}), core]}
                c += 1
            m = self.pick([(1, 1), (2, 2), (2, 3)])
            gc = self.r.random() < 0.8
            x = self.fresh('x', env)
            fenv = {**env, x: ('val', outcome(a))} if gc else env
            if kind == 'fin':
                fin_ps = self.region(MARK_FIN, self.cedes(m))
                fin_ps.append(self.prog(self.small_type(), fenv, max(1, sc - 4), self.fin_ctx(ctx)))
            else:
                p = self.fresh('p')
                fenv = {**fenv, p: ('poll',)}
                pe = self.esc_marked({'op': 'seq', 'ps': self.cedes(m)})
                fin_ps = self.region(MARK_FIN, [{'op': 'poll', 'poll': p, 'e': pe}])
                fin_ps.append({'op': 'poll', 'poll': p, 'e': self.prog(UNIT, fenv, max(1, sc - 4), {'pboost': 3.0})}
                              if self.r.random() < 0.5 else self.prog(UNIT, fenv, max(1, sc - 4), {'pboost': 3.0}))
                start = lambda ch: {'op': 'uncancelable', 'poll': p, 'body': {'op': 'start', 'e': ch}}
            if gc:
                child = self.tag({'op': 'guaranteeCase', 'e': core, 'x': x, 'fin': {'op': 'seq', 'ps': fin_ps}})
            else:
                child = self.tag({'op': 'onCancel', 'e': core, 'fin': {'op': 'seq', 'ps': fin_ps}})
            # onCancel: cancel in the core; guaranteeCase: in the core or in the finalizer
            if gc and self.r.random() < 0.8:
                lo, hi = c + 1, c + m
            else:
                lo, hi = max(1, c), max(1, c)
        elif kind == 'cb':
            cbs = [{'when': 'later', 'ok': self.literal(a)}]
            if self.r.random() < 0.3:
                cbs.append({'when': 'later', 'err': self.code()} if self.r.random() < 0.5 else {'when': 'later', 'ok': self.literal(a)})
            asy = {'op': 'async', 'cbs': cbs}
            if self.r.random() < 0.85:
                asy['fin'] = self.g_fin(env, 2, ctx)
                self.tag(asy)
            c0 = self.pick([(2, 0), (1, 1)])
            e = {'op': 'seq', 'ps': self.cedes(c0) + [asy]}
            child = self.tag({'op': 'onCancel', 'e': e, 'fin': self.g_fin(env, max(1, sc - 4), ctx)}) \
                if self.r.random() < 0.6 else e
            lo, hi = c0 + 1, c0 + 1
        else:  # nested
            g = self.fresh('x')
            gt = self.small_type()
            if sc >= 3 and self.r.random() < 0.5:
                gchild = self.tpl_fin_stack(gt, env, sc // 2 + 1, cc)
            else:
                gchild = {'op': 'seq', 'ps': self.cedes(self.pick([(1, 1), (1, 2)])) + [self.prog(gt, env, max(1, sc // 2), cc)]}
            genv = {**env, g: ('val', fiber(gt))}
            mm = self.pick([(1, 1), (2, 2), (1, 3)])
            mid = self.cedes(mm)
            if self.r.random() < 0.3:
                mid.append({'op': 'join', 'f': {'t': 'var', 'x': g}})
            child = {'op': 'bind', 'x': g, 'e': {'op': 'start', 'e': gchild},
                     'k': {'op': 'seq', 'ps': mid + [self.prog(a, genv, max(1, sc // 2), cc)]}}
            if self.r.random() < 0.5:
                child = self.tag({'op': 'onCancel', 'e': child, 'fin': self.g_fin(env, 2, ctx)})
            lo, hi = 1, mm

        # an external cancel needs a known handle: only for the scenario at the root
        ext = root_first and self.r.random() < self.c['p_scenario_ext']
        n = self.pick([(1, self.r.randint(lo, hi)), (0.15, 0), (0.15, hi + 1)])
        if ext:
            ps = self.cedes(max(n, hi) + 1)
            self.hints.append((1, 2 * lo, 2 * hi))
        else:
            ps = self.cedes(n)
            # escpoll with guaranteeCase: the finalizer runs anyway; a cancel is optional
            if not (kind == 'escpoll' and child['op'] == 'guaranteeCase' and self.r.random() < 0.5):
                ps += self.cancel_req(fv)
            if kind == 'fin' and self.r.random() < 0.4:
                # a second canceler fiber: its cancel can land while the first cancel runs the finalizer
                j = n + self.r.randint(0, m)
                helper = {'op': 'seq', 'ps': self.cedes(j) + self.cancel_req(fv) + [{'op': 'pure', 'v': {'t': 'unit'}}]}
                ps.insert(0, {'op': 'start', 'e': helper})
        k = self.prog(t, env2, max(1, sk), ctx)
        tail = self.cedes(self.pick([(1, 0), (1, 1), (1, 2)]) + (2 if kind == 'cb' else 0))
        if tail:
            k = {'op': 'seq', 'ps': tail + [k]}
        if self.r.random() < (0.85 if ext else 0.6):
            ps.append(self.join_marked(fv, a, k, env2))
        else:
            ps.append(k)
        e = start(child) if start else {'op': 'start', 'e': child}
        return {'op': 'bind', 'x': f, 'e': e, 'k': {'op': 'seq', 'ps': ps}}


# ------------------------------------------------------------------ cases

def count_fibers(p):
    """Upper bound of fiber handles that a run can make: 1 (root) + start + racePair nodes."""
    n = 0
    stack = [p]
    while stack:
        q = stack.pop()
        if isinstance(q, dict):
            if q.get('op') in ('start', 'racePair'):
                n += 1
            stack.extend(v for v in q.values() if isinstance(v, (dict, list)))
        elif isinstance(q, list):
            stack.extend(q)
    return n + 1


def size_of(p):
    """Number of program nodes."""
    if isinstance(p, dict):
        return (1 if 'op' in p else 0) + sum(size_of(v) for v in p.values() if isinstance(v, (dict, list)))
    if isinstance(p, list):
        return sum(size_of(v) for v in p)
    return 0


def gen_choices(g, prog):
    r, c = g.r, g.c
    hint = bool(g.hints) and r.random() < c['p_hint_cancel']
    if r.random() >= c['p_choices'] and not hint:
        return []
    n = r.randint(1, c['max_choices'])
    bias = g.fifo_bias and r.random() < c['p_fifo_bias']
    cs = [g.pick([(5, 0), (4, 1), (2, 2), (1, 3), (0.3, 7)] if not bias else [(10, 0), (1, 1), (0.3, 2)]) for _ in range(n)]
    if hint:
        # decision 17: an external cancel of the scenario child, placed after some child steps
        # (mostly FIFO picks before it, so the parent and the child take turns as planned)
        h, lo, hi = g.hints[0]
        while len(cs) < hi:
            cs.append(0)
        for j in range(hi):
            cs[j] = g.pick([(4, 0), (1, 1)])
        for _ in range(g.pick([(3, 1), (1, 2)])):
            cs.insert(r.randint(lo, hi), {'cancel': h})
    if r.random() < c['p_cancel_case'] * (0.3 if hint else 1):
        nf = count_fibers(prog)
        for _ in range(g.pick([(5, 1), (2, 2), (1, 3)])):
            h = g.pick([(3, 0), (3 if nf > 1 else 0, r.randrange(1, nf) if nf > 1 else 0), (0.2, nf + 2)])
            # mostly early: many programs end after a few steps
            pos = g.pick([(1, 0), (4, r.randint(1, min(3, len(cs)))), (3, r.randint(1, min(8, len(cs)))), (2, r.randint(0, len(cs)))])
            cs.insert(pos, {'cancel': h})
    return cs


def gen_case(seed, i, max_size=40, weights=None, config=None):
    """Replay case i of a seed. Deterministic in (seed, i, weights, config, max_size)."""
    rng = random.Random(f"difftest-v0:{seed}:{i}")
    g = Gen(rng, weights, config)
    size = g.pick([(2, rng.randint(1, 5)), (5, rng.randint(6, 20)), (3, rng.randint(21, max(21, max_size)))])
    t = g.pick([(3, NAT), (2, UNIT), (1, BOOL), (1, either(NAT, NAT)), (1, outcome(NAT)), (1, pair(NAT, BOOL))])
    if rng.random() < g.c['p_syncstep']:
        # format v1: `syncStep(prog, limit)` at the root (it runs before the runtime starts)
        limit = g.pick([(2, 0), (3, 1), (3, 2), (3, 3), (2, 5), (1, 10), (4, MAX_LIMIT)])
        prog = {'op': 'syncStep', 'e': g.prog(t, {}, size, {'root_path': True}), 'limit': limit}
    elif size >= 4 and rng.random() < g.c['p_scenario_root']:
        prog = g.tpl_scenario(t, {}, size, {'root_path': True}, root_first=True)
        g.fifo_bias = True
    else:
        prog = g.prog(t, {}, size, {'root_path': True})
    check_prog(prog)  # raises TypeErr: generator bug
    case = {'v': FORMAT_VERSION, 'id': f"g{seed}-{i}", 'mode': 'replay'}
    cs = gen_choices(g, prog)
    if cs:
        case['choices'] = cs
    if rng.random() < g.c['p_small_maxsteps']:
        case['maxSteps'] = rng.randint(1, 5)
    case['prog'] = prog
    return case


def to_testcontrol(case, tc_seed, suffix=None):
    """The same program in testcontrol mode (no choices: TestControl has no external cancel)."""
    c = {'v': FORMAT_VERSION, 'id': f"{case['id']}~{suffix or f'tc{tc_seed}'}", 'mode': 'testcontrol', 'seed': tc_seed}
    if 'maxSteps' in case:
        c['maxSteps'] = case['maxSteps']
    c['prog'] = case['prog']
    return c


def with_choices(case, choices, suffix):
    c = {k: v for k, v in case.items() if k not in ('choices', 'prog')}
    c['id'] = f"{case['id']}~{suffix}"
    if choices:
        c['choices'] = choices
    c['prog'] = case['prog']
    return c


def has_cancel_choice(case):
    return any(isinstance(x, dict) for x in case.get('choices', []))


def gen_cases(seed, n, start=0, **kw):
    return [gen_case(seed, i, **kw) for i in range(start, start + n)]


def dumps(case):
    return json.dumps(case, separators=(',', ':'))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--n', type=int, default=100)
    ap.add_argument('--start', type=int, default=0, help='first case index')
    ap.add_argument('--max-size', type=int, default=40)
    ap.add_argument('--mode', choices=['replay', 'testcontrol'], default='replay')
    ap.add_argument('--tc-seed', type=int, default=1)
    ap.add_argument('--out', default='-')
    a = ap.parse_args()
    out = sys.stdout if a.out == '-' else open(a.out, 'w')
    for c in gen_cases(a.seed, a.n, a.start, max_size=a.max_size):
        if a.mode == 'testcontrol':
            c = to_testcontrol(c, a.tc_seed)
        out.write(dumps(c) + '\n')
    if out is not sys.stdout:
        out.close()


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Seeded generator of difftest cases (format v0, JSON lines).

Spec of the format: wiki/methodology/difftest-program-format.md.
Design notes: wiki/methodology/differential-testing.md ("Generator").

- Type-directed: `Gen.prog(T, env, size)` makes a program of type T. Each case is checked
  with `typecheck.check_prog` (decision 8: a TypeError is a generator bug).
- Deterministic: case i of seed s depends only on (s, i) and the weight table.
- Edge-heavy: templates for escaped poll, poll in finalizers, racePair, Deferred handoff,
  async callbacks (0/1/2/3 calls, sync/later, with a finalizer), external cancel choices.

Usage:
  gen.py --seed 1 --n 1000 [--max-size 40] [--mode replay|testcontrol] [--out FILE]
"""

import argparse
import json
import random
import sys

from typecheck import check_prog

FORMAT_VERSION = 0

UNIT, BOOL, NAT = ('unit',), ('bool',), ('nat',)


def pair(a, b): return ('pair', a, b)
def either(a, b): return ('either', a, b)
def outcome(a): return ('outcome', a)
def fiber(a): return ('fiber', a)
def ref(a): return ('ref', a)
def deferred(a): return ('deferred', a)


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
    'fn_raise': 0.4,  # relative weight of user function 3 (raise) in delay/map; others 1
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
}


class Gen:
    def __init__(self, rng, weights=None, config=None):
        self.r = rng
        self.w = dict(WEIGHTS if weights is None else weights)
        self.c = dict(CONFIG if config is None else config)
        self.names = 0
        self.tags = 0

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
                          (0.4, race_type(self.small_type(), self.small_type()))])

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
                opts.append((w['cancel'] * hb, lambda: {'op': 'cancel', 'f': {'t': 'var', 'x': self.r.choice(fibs)}}))
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
            ps = [self.prog(self.pick([(6, UNIT), (1, self.small_type()), (dfd, BOOL)]), env, s, cc) for s in parts[:-1]]
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
        return opts

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
            child = self.tag({'op': 'onCancel', 'e': self.prog(a, penv, max(1, sc // 2), cctx),
                              'fin': {'op': 'poll', 'poll': p, 'e': self.prog(UNIT, penv, max(1, sc // 2), cctx)}})
        elif shape == 'gcpoll':
            x = self.fresh('x')
            fenv = {**penv, x: ('val', outcome(a))}
            child = self.tag({'op': 'guaranteeCase', 'e': self.prog(a, penv, max(1, sc // 2), cctx), 'x': x,
                              'fin': {'op': 'seq', 'ps': [{'op': 'poll', 'poll': p, 'e': self.prog(UNIT, fenv, 1, cctx)},
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
        return {'op': 'bind', 'x': f, 'e': unc, 'k': self.prog(t, {**env, f: ('val', fiber(a))}, sk, ctx)}

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
        ps.append({'op': 'cancel', 'f': fv})
        if self.r.random() < 0.6:
            ps.append({'op': 'join', 'f': fv})
        ps.append(self.prog(t, env2, sk, ctx))
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
            return {'op': 'seq', 'ps': [self.suspend_point(env), self.prog(UNIT, env, max(1, size - 1), self.fin_ctx(ctx))]}
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

    def tpl_handoff(self, t, env, size, ctx):
        """bind d = deferredNew in bind f = start(... deferredGet d ...) in k (k may complete d)."""
        a = self.pick([(3, NAT), (1, UNIT), (1, BOOL)])
        sc, sk = self.split_size(size, 2)
        d, f = self.fresh('x'), self.fresh('x')
        denv = {**env, d: ('val', deferred(a))}
        child = self.prog(a, denv, sc, self.child_ctx(ctx))
        if self.r.random() < 0.7:
            child = {'op': 'seq', 'ps': [{'op': 'deferredGet', 'd': {'t': 'var', 'x': d}}, child]} if self.r.random() < 0.5 \
                else {'op': 'deferredGet', 'd': {'t': 'var', 'x': d}}
        kenv = {**denv, f: ('val', fiber(a))}
        k = self.prog(t, kenv, sk, ctx)
        if self.r.random() < 0.7:
            k = {'op': 'seq', 'ps': [{'op': 'deferredComplete', 'd': {'t': 'var', 'x': d}, 'v': self.literal(a)}, k]}
        return {'op': 'bind', 'x': d, 'e': {'op': 'deferredNew'},
                'k': {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': child}, 'k': k}}


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
    if r.random() >= c['p_choices']:
        return []
    n = r.randint(1, c['max_choices'])
    cs = [g.pick([(5, 0), (4, 1), (2, 2), (1, 3), (0.3, 7)]) for _ in range(n)]
    if r.random() < c['p_cancel_case']:
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

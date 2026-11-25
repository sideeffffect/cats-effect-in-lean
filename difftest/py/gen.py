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
- Format v2 (decision 51, track R): `race`, `raceOutcome`, `both`, `bothOutcome` where the wanted
  type fits, and `tpl_comb` (any type: bind the result of a combinator, often with a sleeping,
  never-ending or masked side) and `tpl_combCancel` (decision 50: a parent starts the combinator and
  cancels it).
- Format v2 (decision 51, track M): `memoize` and `memoGet` only through `tpl_memo` (a memo handle
  of type `('memo', A)` is bound and used by `memoGet`, never printed): sequential `get`s, two
  `get` fibers, a parent that cancels one `get` fiber, or cancels all and runs `get` again; `fa`
  often waits (`cede`, `sleep`) or cancels itself (the CE-0030 shape). `memoGet` is also a
  production of type A wherever a memo of type A is in scope.

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
def memo(a): return ('memo', a)


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
    'timeout': 1.2, 'timeoutTo': 1.2, 'allocatedCase': 2.2,
    'queueNew': 2, 'queueOffer': 3, 'queueTake': 3, 'queueTryTake': 6, 'tpl_queue': 2.2, 'tpl_resource': 1,
    'res_pure': 2.5, 'res_eval': 2.5, 'res_make': 3.5, 'res_flatMap': 12,
    # format v2 (track R)
    'race': 2.5, 'raceOutcome': 2.5, 'both': 2.5, 'bothOutcome': 2.5, 'tpl_comb': 5, 'tpl_combCancel': 2.5,
    # format v2 (track G)
    'guarantee': 1.0, 'bracket': 0.8, 'bracketCase': 0.8, 'bracketFull': 0.8, 'tpl_bracket': 1.0,
    # format v2 (track M)
    # tpl_memo 0.4: with 1.0 (or 0.5) a static share in selftest.py fell below its minimum (N = 400 is noisy)
    'tpl_memo': 0.4, 'memoGet': 4,
    # format v2 (track Res)
    'rUse': 0.5, 'rAllocated': 0.4, 'res_both': 2.0, 'tpl_resBoth': 0.5,
    # format v2 (batch 6.3): `parTraverseN` (lists of at most 5 elements: from 5 Scala uses a
    # `HashSet` with identity-hash order; the Lean side lists every order, review 8). Not a production of
    # `composite_opts` (a new option shifts the shared RNG and pushed `race` below its selftest
    # minimum); `gen_case` appends it with its own RNG (`p_par_traverse`). Weights here only
    # scale how often the two shapes are chosen there (`--boost` in opcount.py).
    'tpl_parTraverse': 1.2, 'tpl_parTraverseCancel': 0.6,
    # format v2 (Phase 7, track Q): the `qNew` queue scenario, appended by `gen_case` with its own
    # RNG (`p_queue2`), as `parTraverseN`; the weight only scales that probability (`--boost`)
    'tpl_queue2': 1.0,
    # format v2 (Phase 7, track S): `Semaphore` and `Mutex`, appended by `gen_case` with its own RNG
    # (`p_sem`), as `parTraverseN`; the weights scale the two shapes (`--boost` in opcount.py)
    'tpl_sem': 1.0, 'tpl_mutex': 0.6,
    # format v2 (Phase 7, track L): `CountDownLatch` and `CyclicBarrier` scenarios, appended by
    # `gen_case` with their own RNG (`p_latch`), like `parTraverseN`. Weights scale the two shapes.
    'tpl_cdl': 1.0, 'tpl_cb': 1.0,
    # format v2 (Phase 7, track V): a `Supervisor` scenario, appended by `gen_case` with its own
    # RNG (`p_sup`), like `parTraverseN`. The weight scales the probability (`--boost`).
    'tpl_sup': 1.0,
    # format v2 (Phase 7, track P7D): a `Dispatcher` scenario, appended by `gen_case` with its own
    # RNG (`p_disp`), like `parTraverseN`. The weight scales the probability (`--boost`).
    'tpl_disp': 1.0,
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
    # preempt coverage (Phase 5 gate caveat 3): small IORuntimeConfig thresholds
    'p_runtime': 0.25,
    'p_queue2': 0.08,          # Phase 7, track Q: append a `qNew` queue scenario (own RNG, see gen_case)
    'p_sem': 0.08,             # Phase 7, track S: append a `Semaphore`/`Mutex` part (own RNG, see gen_case)
    'p_latch': 0.08,           # Phase 7, track L: append a latch/barrier part (own RNG, see gen_case)
    'p_sup': 0.08,             # Phase 7, track V: append a Supervisor part (own RNG, see gen_case)
    'p_disp': 0.08,            # Phase 7, track P7D: append a Dispatcher part (own RNG, see gen_case)
    'p_par_traverse': 0.08,    # batch 6.3: append a `parTraverseN` part (own RNG, see gen_case)         # replay case gets a `runtime` field (auto-yield every few iterations)
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
        ms = self.vars_of(env, lambda u: u == memo(t))
        if ms:
            opts.append((w['memoGet'] * hb, lambda: {'op': 'memoGet', 'm': {'t': 'var', 'x': self.r.choice(ms)}}))
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

        # ---- format v2 (track Res): `use`, `allocated` of a resource tree; `both` in g_res
        if size >= 2:
            def g_ruse(op):
                s = self.small_type()
                sr, sk = self.split_size(size, 2)
                x = self.fresh('x', env)
                return {'op': op, 'res': self.g_res(s, env, sr, cc), 'x': x,
                        'k': self.prog(t, {**env, x: ('val', s)}, sk, cc)}
            opts.append((w['rUse'], lambda: g_ruse('rUse')))
            opts.append((w['rAllocated'], lambda: g_ruse('rAllocated')))
        if size >= 5:
            opts.append((w['tpl_resBoth'], lambda: self.tpl_res_both(t, env, size, cc)))

        # ---- format v2 (track R): type-directed combinators
        if size >= 3 and t[0] in ('either', 'pair'):
            kind = 'race' if t[0] == 'either' else 'both'
            opts.append((w[kind], lambda: self.g_comb(kind, t[1], t[2], env, size, cc)))
            if t[1][0] == 'outcome' and t[2][0] == 'outcome':
                kind2 = 'raceOutcome' if t[0] == 'either' else 'bothOutcome'
                opts.append((w[kind2] * 2, lambda: self.g_comb(kind2, t[1][1], t[2][1], env, size, cc)))

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
        if size >= 4:
            opts.append((w['tpl_comb'], lambda: self.tpl_comb(t, env, size, ctx)))
        if size >= 5:
            opts.append((w['tpl_combCancel'], lambda: self.tpl_comb_cancel(t, env, size, ctx)))
        if size >= 4 and self.res_ok(t):
            opts.append((w['tpl_resource'], lambda: self.tpl_resource(t, env, size, cc)))
        if size >= 4:
            opts.append((w['tpl_memo'], lambda: self.tpl_memo(t, env, size, ctx)))
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

    # ------------------------------------------------------- format v2 (track M)

    def memo_source(self, a, env, size, ctx):
        """`fa` of a memoize: often a marker first (the trace shows each evaluation), then a wait
        (cede, sleep) so other `get`s subscribe, sometimes a self-cancel (CE-0030) or an error."""
        self.rids += 1
        ps = [{'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_000_000 + self.rids}}] if self.r.random() < 0.8 else []
        x = self.r.random()
        if x < 0.35:
            ps.append(self.pick([(3, {'op': 'cede'}), (2, {'op': 'sleep', 'ms': self.pick([(1, 0), (2, 1), (2, 10), (1, 100)])})]))
        elif x < 0.5:
            ps.append({'op': 'canceled'})
        elif x < 0.6:
            ps.append({'op': 'raise', 'code': self.code()})
        ps.append(self.prog(a, env, max(1, size), ctx))
        return ps[0] if len(ps) == 1 else {'op': 'seq', 'ps': ps}

    def tpl_memo(self, t, env, size, ctx):
        """bind m = memoize(fa) in one of: sequential gets; two get fibers joined; a parent that
        cancels one of two get fibers; a parent that cancels the only get fiber and runs get again."""
        a = self.small_type()
        sf, sk = self.split_size(size, 2)
        m = self.fresh('m')
        mv = {'t': 'var', 'x': m}
        get = {'op': 'memoGet', 'm': mv}
        env2 = {**env, m: ('val', memo(a))}
        fa = self.memo_source(a, env, max(1, sf), ctx)
        shape = self.pick([(2, 'seq'), (3, 'two'), (2, 'cancelOne'), (2, 'rerun')])
        k = self.prog(t, env2, max(1, sk), ctx)
        cedes = lambda: [{'op': 'cede'} for _ in range(self.pick([(2, 0), (2, 1), (1, 2), (1, 4)]))]
        if shape == 'seq':
            body = {'op': 'seq', 'ps': [get for _ in range(self.pick([(2, 1), (2, 2), (1, 3)]))] + [k]}
        else:
            f1, f2 = self.fresh('x'), self.fresh('x')
            v1, v2 = {'t': 'var', 'x': f1}, {'t': 'var', 'x': f2}
            env3 = {**env2, f1: ('val', fiber(a)), f2: ('val', fiber(a))}
            k3 = self.prog(t, env3, max(1, sk), ctx)
            if shape == 'two':
                inner = {'op': 'seq', 'ps': cedes() + [self.join_marked(v1, a, self.join_marked(v2, a, k3, env3), env3)]}
                body = {'op': 'bind', 'x': f1, 'e': {'op': 'start', 'e': get},
                        'k': {'op': 'bind', 'x': f2, 'e': {'op': 'start', 'e': get}, 'k': inner}}
            elif shape == 'cancelOne':
                inner = {'op': 'seq', 'ps': cedes() + [{'op': 'cancel', 'f': v1}, self.join_marked(v2, a, k3, env3)]}
                body = {'op': 'bind', 'x': f1, 'e': {'op': 'start', 'e': get},
                        'k': {'op': 'bind', 'x': f2, 'e': {'op': 'start', 'e': get}, 'k': inner}}
            else:
                env4 = {**env2, f1: ('val', fiber(a))}
                k4 = self.prog(t, env4, max(1, sk), ctx)
                o = self.fresh('x')
                after = {'op': 'bind', 'x': o, 'e': get,
                         'k': {'op': 'seq', 'ps': [{'op': 'delay', 'fn': 1, 'arg': {'t': 'var', 'x': o}}, k4]}}
                body = {'op': 'bind', 'x': f1, 'e': {'op': 'start', 'e': get},
                        'k': {'op': 'seq', 'ps': cedes() + [{'op': 'cancel', 'f': v1}, after]}}
        return {'op': 'bind', 'x': m, 'e': {'op': 'memoize', 'e': fa}, 'k': body}

    # ------------------------------------------------- format v2 (Phase 7, track L)

    def latch_prefix(self, env, size, ctx):
        """User code before an `await`/`release`: often nothing or a wait, sometimes an arbitrary
        small program (it can raise, cancel itself or never end). `env` never holds the latch or
        barrier variable (they are never printed)."""
        x = self.r.random()
        if x < 0.35:
            return []
        if x < 0.65:
            return [self.pick([(3, {'op': 'cede'}), (2, {'op': 'sleep', 'ms': self.pick([(1, 0), (2, 1), (1, 10)])})])]
        if x < 0.72:
            return [{'op': 'canceled'}]
        if x < 0.77:
            return [{'op': 'raise', 'code': self.code()}]
        return [self.prog(self.small_type(), env, max(1, size), self.child_ctx(ctx))]

    def latch_wait(self, op_node, j, env, size, ctx):
        """`prefix; await; marker` (the marker `delay fn1 nat (9_100_000 + j)` shows a return in
        the trace), sometimes with an `onCancel` finalizer or inside `uncancelable` + `poll`."""
        mark = {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_100_000 + j}}
        x = self.r.random()
        if x < 0.25:
            w = self.tag({'op': 'onCancel', 'e': op_node, 'fin': {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_200_000 + j}}})
        elif x < 0.4:
            q = self.fresh('p')
            w = {'op': 'uncancelable', 'poll': q, 'body': {'op': 'seq', 'ps': [
                {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_300_000 + j}},
                self.tag({'op': 'onCancel', 'e': {'op': 'poll', 'poll': q, 'e': op_node},
                          'fin': {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_200_000 + j}}})]}}
        else:
            w = op_node
        return {'op': 'seq', 'ps': self.latch_prefix(env, size, ctx) + [w, mark]}

    def tpl_barrier_race(self, env, size, ctx):
        """The cancel-versus-trip race of `CyclicBarrier` (`CyclicBarrier.scala:77-82`): `cap - 1`
        awaiter fibers wait (the parent cedes); the parent starts a tripper fiber and at once
        cancels some waiters. A waiter that is suspended runs its finalizers in a later task, so
        under FIFO the tripper trips the barrier first and the cleanup sees the new epoch. Then
        `cap` (or more) late awaiters show the count of the next generation."""
        h = self.fresh('l')
        hv = {'t': 'var', 'x': h}
        cap = self.pick([(3, 2), (2, 3)])
        node = lambda: {'op': 'cbAwait', 'b': hv}
        mark = lambda j: {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_100_000 + j}}
        fs = [self.fresh('x') for _ in range(cap - 1)]
        tr = self.fresh('x')
        late = [self.fresh('x') for _ in range(cap + self.pick([(4, 0), (1, 1)]))]
        bodies = {f: self.latch_wait(node(), j, env, max(1, size // 4), ctx) if self.r.random() < 0.3
                  else {'op': 'seq', 'ps': [node(), mark(j)]} for j, f in enumerate(fs)}
        inner = {'op': 'seq', 'ps': [{'op': 'join', 'f': {'t': 'var', 'x': f}} for f in fs + [tr] + late]
                 + [{'op': 'pure', 'v': {'t': 'unit'}}]}
        for j, f in reversed(list(enumerate(late))):
            inner = {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': {'op': 'seq', 'ps': [node(), mark(10 + j)]}}, 'k': inner}
        cs = [{'op': 'cancel', 'f': {'t': 'var', 'x': f}} for f in fs if self.r.random() < 0.8]
        after = {'op': 'seq', 'ps': cs + [{'op': 'cede'} for _ in range(self.pick([(4, 0), (1, 1)]))] + [inner]}
        prog = {'op': 'bind', 'x': tr, 'e': {'op': 'start', 'e': {'op': 'seq', 'ps': [node(), mark(30)]}}, 'k': after}
        prog = {'op': 'seq', 'ps': [{'op': 'cede'} for _ in range(self.pick([(1, 1), (3, 2), (1, 3)]))] + [prog]}
        for f in reversed(fs):
            prog = {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': bodies[f]}, 'k': prog}
        return {'op': 'bind', 'x': h, 'e': {'op': 'cbNew', 'n': cap}, 'k': prog}

    def tpl_latch(self, env, size, ctx, barrier):
        """A `CountDownLatch` (or `CyclicBarrier`) scenario of type unit: make it, start 1-4
        awaiter fibers (and releasers for a latch), let the parent cede, release, await, cancel
        some fibers, start late awaiters, and join every fiber (or not, so a run can block)."""
        if barrier and self.r.random() < 0.25:
            return self.tpl_barrier_race(env, size, ctx)
        h = self.fresh('l')
        hv = {'t': 'var', 'x': h}
        n = self.pick([(3, 1), (4, 2), (3, 3), (1, 4)])
        node = (lambda: {'op': 'cbAwait', 'b': hv}) if barrier else (lambda: {'op': 'cdlAwait', 'l': hv})
        rel = lambda: {'op': 'cdlRelease', 'l': hv}
        sub = max(1, size // 4)
        cedes = lambda: [{'op': 'cede'} for _ in range(self.pick([(3, 0), (2, 1), (1, 2), (1, 4)]))]
        fibers = []
        steps = []
        k = self.pick([(1, 1), (3, 2), (3, 3), (2, 4)])
        for j in range(k):
            fibers.append((self.fresh('x'), self.latch_wait(node(), j, env, sub, ctx)))
        if not barrier:
            for i in range(self.pick([(1, 0), (3, 1), (3, 2), (2, 3), (1, 5)])):
                body = {'op': 'seq', 'ps': self.latch_prefix(env, sub, ctx) + [
                    {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_400_000 + i}}, rel()]}
                fibers.append((self.fresh('x'), body))
        self.r.shuffle(fibers)
        started = []
        for f, body in fibers:
            steps.append(('start', f, body))
            started.append(f)
            if self.r.random() < 0.3:
                steps.append(('do', cedes()))
        # the parent: releases, a wait of its own, cancels, late awaiters
        tail = []
        for _ in range(self.pick([(3, 0), (2, 1), (2, 2), (1, 3)]) if not barrier else 0):
            tail += cedes() + [rel()]
        # barrier: the parent's own `await` can trip the barrier just before it cancels a
        # released awaiter that has not run yet (the cancel loses the race; the cleanup must see
        # the new epoch); then late awaiters show the count of the next generation
        trip_first = barrier and self.r.random() < 0.35
        if trip_first:
            tail.append(self.latch_wait(node(), 20, env, sub, ctx))
        cancels = [f for f in started if self.r.random() < (0.5 if trip_first else 0.3)]
        for f in cancels:
            tail += ([] if trip_first else cedes()) + [{'op': 'cancel', 'f': {'t': 'var', 'x': f}}]
        late = []
        for j in range(self.pick([(3, 0), (2, 1), (1, 2)] if not trip_first else [(1, 1), (3, 2), (1, 3)])):
            late.append((self.fresh('x'), self.latch_wait(node(), 10 + j, env, sub, ctx)))
        if barrier and not trip_first and self.r.random() < 0.3:
            tail.append(self.latch_wait(node(), 20, env, sub, ctx))
        joins = [{'op': 'join', 'f': {'t': 'var', 'x': f}} for f in started + [x for x, _ in late]
                 if self.r.random() < 0.85]
        # build: bind l = new; bind f1 = start ...; ...; tail; late starts; joins; unit
        rest = {'op': 'seq', 'ps': tail + [] + [{'op': 'pure', 'v': {'t': 'unit'}}]} if not late else None
        if late:
            inner = {'op': 'seq', 'ps': cedes() + joins + [{'op': 'pure', 'v': {'t': 'unit'}}]}
            for f, body in reversed(late):
                inner = {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': body}, 'k': inner}
            rest = {'op': 'seq', 'ps': tail + [inner]}
        else:
            rest = {'op': 'seq', 'ps': tail + cedes() + joins + [{'op': 'pure', 'v': {'t': 'unit'}}]}
        prog = rest
        for st in reversed(steps):
            if st[0] == 'start':
                prog = {'op': 'bind', 'x': st[1], 'e': {'op': 'start', 'e': st[2]}, 'k': prog}
            elif st[1]:
                prog = {'op': 'seq', 'ps': st[1] + [prog]}
        new = {'op': 'cbNew', 'n': n} if barrier else {'op': 'cdlNew', 'n': n}
        return {'op': 'bind', 'x': h, 'e': new, 'k': prog}

    # ------------------------------------------- format v2 (Phase 7, track V)

    def sup_child(self, j, env, size, ctx, sv, depth):
        """A supervised child: user code (`latch_prefix`), markers, often an `onCancel`
        finalizer, sometimes a wait (cede, never), sometimes a grandchild that it supervises
        on the same supervisor `sv` (nested supervision; it can race the close)."""
        mark = lambda k: {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_500_000 + 100 * k + j}}
        core = self.latch_prefix(env, size, ctx) + [mark(1)]
        x = self.r.random()
        if x < 0.15:
            core += [{'op': 'never'}]
        elif x < 0.5:
            core += [{'op': 'cede'} for _ in range(self.pick([(2, 1), (2, 2), (1, 4)]))]
        elif x < 0.6:
            core += [{'op': 'raise', 'code': self.code()}]
        body = {'op': 'seq', 'ps': core + [mark(2)]}
        if self.r.random() < 0.5:
            body = self.tag({'op': 'onCancel', 'e': body, 'fin': mark(3)})
        # at most 5 `supervise` per scenario: the Lean side lists every map order of at most 5
        # entries (`Main.lean`); with 6 the Scala order (identity hashes) can be outside the list
        if depth < 1 and self.sup_left > 0 and self.r.random() < 0.25:
            self.sup_left -= 1
            sub = {'op': 'supervise', 's': sv, 'e': self.sup_child(j + 50, env, size, ctx, sv, depth + 1)}
            body = {'op': 'seq', 'ps': [body, {'op': 'attempt', 'e': sub}, mark(4)]}
        return body

    def tpl_sup(self, env, size, ctx):
        """A `Supervisor` scenario of type unit: `supUse` (await, restart, state kind random),
        supervise 1-4 children, then the body cedes, joins or cancels some children (or the
        restart wrapper), maybe raises or cancels itself, and returns; sometimes the supervisor
        escapes the body and a late `supervise` fails (`IllegalStateException`)."""
        s = self.fresh('s')
        sv = {'t': 'var', 'x': s}
        aw = self.r.random() < 0.5
        # restart path (`checkRestart = Some(_ => true)`): `always` restarts a finished child
        # forever, so these runs end by fuel; the Lean side is slow on them (large closure codes):
        # at most 2 children, no nesting, maxSteps 150 (`gen_case`)
        rs = self.r.random() < 0.2
        cv = self.r.random() < 0.3
        sub = max(1, size // 4)
        cedes = lambda: [{'op': 'cede'} for _ in range(self.pick([(3, 0), (2, 1), (1, 2), (1, 4)]))]
        k = self.pick([(3, 1), (3, 2)] if rs else [(3, 1), (3, 2), (2, 3), (1, 4)])
        fs = [self.fresh('x') for _ in range(k)]
        self.sup_left = 5 - k
        tail = cedes()
        for f in fs:
            r = self.r.random()
            if r < 0.25:
                tail += [{'op': 'cancel', 'f': {'t': 'var', 'x': f}}] + cedes()
            elif r < 0.45 and not rs:
                tail += [{'op': 'join', 'f': {'t': 'var', 'x': f}}]
        r = self.r.random()
        if r < 0.1:
            tail += [{'op': 'raise', 'code': self.code()}]
        elif r < 0.15:
            tail += [{'op': 'canceled'}]
        escape = self.r.random() < 0.15
        tail += [{'op': 'pure', 'v': sv if escape else {'t': 'unit'}}]
        body = {'op': 'seq', 'ps': tail}
        for j, f in reversed(list(enumerate(fs))):
            body = {'op': 'bind', 'x': f, 'e': {'op': 'supervise', 's': sv,
                    'e': self.sup_child(j, env, sub, ctx, sv, 1 if rs else 0)}, 'k': body}
        use = {'op': 'supUse', 'aw': aw, 'rs': rs, 'cv': cv, 'x': s, 'k': body}
        if escape:
            t = self.fresh('s')
            late = {'op': 'attempt', 'e': {'op': 'supervise', 's': {'t': 'var', 'x': t},
                    'e': {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_599_999}}}}
            return {'op': 'bind', 'x': t, 'e': use, 'k': {'op': 'seq', 'ps': [late, {'op': 'pure', 'v': {'t': 'unit'}}]}}
        return {'op': 'seq', 'ps': [{'op': 'attempt', 'e': use}, {'op': 'pure', 'v': {'t': 'unit'}}]}

    def disp_child(self, j, env, size, ctx, gv, dv, depth):
        """A dispatched effect: user code (`latch_prefix`), markers `9_6xx_xxx`, sometimes a wait on
        the gate `gv` (released later, or never), a cede, a raise; sometimes an `onCancel` finalizer;
        sometimes (depth 0) a follow-up submission to the same dispatcher `dv` (it can race the
        release: CE-0090)."""
        mark = lambda k: {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_600_000 + 100 * k + j}}
        core = self.latch_prefix(env, size, ctx) + [mark(1)]
        x = self.r.random()
        if x < 0.35:
            core += [{'op': 'deferredGet', 'd': gv}]
        elif x < 0.55:
            core += [{'op': 'cede'} for _ in range(self.pick([(2, 1), (2, 2), (1, 4)]))]
        elif x < 0.62:
            core += [{'op': 'raise', 'code': self.code()}]
        elif x < 0.66:
            core += [{'op': 'never'}]
        body = {'op': 'seq', 'ps': core + [mark(2)]}
        if self.r.random() < 0.4:
            body = self.tag({'op': 'onCancel', 'e': body, 'fin': mark(3)})
        if depth < 1 and self.disp_left > 0 and self.r.random() < 0.2:
            self.disp_left -= 1
            f = self.fresh('f')
            sub = {'op': 'bind', 'x': f, 'e': {'op': 'dSubmit', 'd': dv,
                   'e': self.disp_child(j + 50, env, size, ctx, gv, dv, depth + 1)},
                   'k': {'op': 'seq', 'ps': [{'op': 'cede'}, self.disp_poll(f)]}}
            body = {'op': 'seq', 'ps': [body, {'op': 'attempt', 'e': sub}, mark(4)]}
        return body

    def disp_poll(self, f):
        """`dPoll f`, its value in the trace (`delay fn1 x`)."""
        x = self.fresh('o')
        return {'op': 'bind', 'x': x, 'e': {'op': 'dPoll', 'f': {'t': 'var', 'x': f}},
                'k': {'op': 'delay', 'fn': 1, 'arg': {'t': 'var', 'x': x}}}

    def tpl_disp(self, env, size, ctx):
        """A `Dispatcher` scenario of type unit: `dUse` (parallel or sequential, await random), a
        gate `Deferred`; 1-4 submissions (`dSubmit`, `dForget`) of `disp_child` effects with cedes
        between; polls and cancels of the futures; the gate is opened (or not); sometimes a fiber
        that submits late (during or after the release: CE-0090) and opens the gate; sometimes the
        dispatcher or a future escapes the body and is used after the release (submission fails
        with `IllegalStateException`; a poll shows the final state).
        Cost limit (not an agreement limit): at most 3 accepted submissions (executor map) and 2
        cancels (worker map) per scenario. The Lean side replays every order of the largest
        `Supervisor` map counter (k! replays, about 0.5 s each); 5 entries cost about 60 s per case."""
        d, g = self.fresh('d'), self.fresh('g')
        dv, gv = {'t': 'var', 'x': d}, {'t': 'var', 'x': g}
        par = self.r.random() < 0.6
        aw = self.r.random() < 0.5
        sub = max(1, size // 4)
        cedes = lambda: [{'op': 'cede'} for _ in range(self.pick([(3, 0), (2, 1), (1, 2), (1, 4)]))]
        k = self.pick([(3, 1), (3, 2), (2, 3)])
        self.disp_left = 3 - k
        cancel_left = 2
        steps = []  # (kind, payload) in order; futures bound by name
        futs = []
        opened = False
        for j in range(k):
            child = self.disp_child(j, env, sub, ctx, gv, dv, 0)
            if self.r.random() < 0.4:
                steps.append(('do', {'op': 'dForget', 'd': dv, 'e': child}))
            else:
                f = self.fresh('f')
                futs.append(f)
                steps.append(('bind', f, {'op': 'dSubmit', 'd': dv, 'e': child}))
            for c in cedes():
                steps.append(('do', c))
            if not opened and self.r.random() < 0.2:
                opened = True
                steps.append(('do', {'op': 'deferredComplete', 'd': gv, 'v': {'t': 'nat', 'v': 1}}))
        for f in futs:
            r = self.r.random()
            if r < 0.3:
                steps.append(('do', self.disp_poll(f)))
            elif r < 0.85 and cancel_left > 0:
                cancel_left -= 1
                c = self.fresh('c')
                steps.append(('bind', c, {'op': 'dCancel', 'f': {'t': 'var', 'x': f}}))
                for x in cedes():
                    steps.append(('do', x))
                if self.r.random() < 0.6:
                    steps.append(('do', self.disp_poll(c)))
        if self.r.random() < 0.3 and self.disp_left > 0:
            # a late submitter: it can run while the release waits (CE-0090) or after it
            self.disp_left -= 1
            w = self.pick([(2, {'op': 'cede'}), (2, {'op': 'sleep', 'ms': 1}), (2, {'op': 'sleep', 'ms': 100}), (1, {'op': 'sleep', 'ms': 0})])
            lf = self.fresh('f')
            late = {'op': 'seq', 'ps': [w, {'op': 'attempt', 'e': {'op': 'bind', 'x': lf,
                    'e': {'op': 'dSubmit', 'd': dv, 'e': self.disp_child(70, env, sub, ctx, gv, dv, 1)},
                    'k': {'op': 'seq', 'ps': [{'op': 'sleep', 'ms': 10}, self.disp_poll(lf)]}}},
                    {'op': 'deferredComplete', 'd': gv, 'v': {'t': 'nat', 'v': 2}}]}
            steps.append(('do', {'op': 'start', 'e': late}))
        elif not opened and self.r.random() < 0.6:
            steps.append(('do', {'op': 'deferredComplete', 'd': gv, 'v': {'t': 'nat', 'v': 1}}))
        r = self.r.random()
        if r < 0.08:
            steps.append(('do', {'op': 'raise', 'code': self.code()}))
        elif r < 0.12:
            steps.append(('do', {'op': 'canceled'}))
        esc = self.pick([(5, None), (2, 'd')] + ([(2, 'f')] if futs else []))
        ret = {'op': 'pure', 'v': {'t': 'unit'}} if esc is None else \
            {'op': 'pure', 'v': dv if esc == 'd' else {'t': 'var', 'x': futs[-1]}}
        body = ret
        for st in reversed(steps):
            if st[0] == 'do':
                body = {'op': 'seq', 'ps': [st[1], body]}
            else:
                body = {'op': 'bind', 'x': st[1], 'e': st[2], 'k': body}
        body = {'op': 'bind', 'x': g, 'e': {'op': 'deferredNew'}, 'k': body}
        use = {'op': 'dUse', 'par': par, 'aw': aw, 'x': d, 'k': body}
        if esc is None:
            return {'op': 'seq', 'ps': [{'op': 'attempt', 'e': use}, {'op': 'pure', 'v': {'t': 'unit'}}]}
        t = self.fresh('e')
        after = [{'op': 'sleep', 'ms': self.pick([(1, 0), (1, 10)])}]
        if esc == 'd':
            after.append({'op': 'attempt', 'e': {'op': 'dSubmit', 'd': {'t': 'var', 'x': t},
                          'e': {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 9_699_999}}}})
        else:
            after.append(self.disp_poll(t))
        after.append({'op': 'pure', 'v': {'t': 'unit'}})
        return {'op': 'bind', 'x': t, 'e': use, 'k': {'op': 'seq', 'ps': after}}

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
        if size >= 3 and t[0] == 'pair':
            # format v2 (track Res): `rBoth(a, b)` of value type pair(a, b)
            def g_both():
                sa, sb = self.split_size(size, 2)
                return {'op': 'rBoth', 'a': self.g_res(t[1], env, sa, ctx), 'b': self.g_res(t[2], env, sb, ctx)}
            opts.append((w['res_both'], g_both))
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

    def g_par_traverse(self, env, size, ctx):
        """`parTraverseN(n)(xs)(x => f)`: 0..5 elements of a literal type (or variables of it),
        limit 1..5, `f` an arbitrary program of a small type (it can suspend, raise or cancel).
        Five elements make the supervision set a `HashSet` (review 8); `cediff` then lists the
        result of every order (`alternatives`) and the driver compares by refinement."""
        a = self.pick([(3, NAT), (1, UNIT), (1, BOOL)])
        k = self.pick([(1, 0), (2, 1), (3, 2), (3, 3), (3, 4), (2, 5)])
        xs = [self.atom(a, env) for _ in range(k)]
        x = self.fresh('x', env)
        n = self.pick([(4, 1), (4, 2), (2, 3), (1, 5)])
        f = self.prog(self.small_type(), {**env, x: ('val', a)}, max(1, size), self.child_ctx(ctx))
        return {'op': 'parTraverseN', 'n': n, 'xs': xs, 'x': x, 'f': f}

    def tpl_par_traverse(self, t, env, size, ctx, cancel):
        sp, sk = self.split_size(size, 2)
        p = self.g_par_traverse(env, sp, ctx)
        if not cancel:
            return {'op': 'seq', 'ps': [p, self.prog(t, env, sk, ctx)]}
        fv = self.fresh('x')
        env2 = {**env, fv: ('val', fiber(UNIT))}
        ps = [{'op': 'cede'} for _ in range(self.pick([(2, 0), (2, 1), (2, 2), (1, 4)]))]
        ps.append({'op': 'cancel', 'f': {'t': 'var', 'x': fv}})
        ps.append(self.prog(t, env2, sk, ctx))
        return {'op': 'bind', 'x': fv, 'e': {'op': 'start', 'e': {'op': 'map', 'e': p, 'fn': 1}},
                'k': {'op': 'seq', 'ps': ps}}

    # ---- Phase 7, track S: `Semaphore` and `Mutex` scenarios (type unit)

    def sem_mark(self, k):
        """A trace marker: `delay inc (nat k)` (type nat)."""
        return {'op': 'delay', 'fn': 2, 'arg': {'t': 'nat', 'v': k}}

    def sem_stop(self):
        """How a critical section ends: value, error, self-cancel, sleep, rarely never."""
        return self.pick([(6, {'op': 'pure', 'v': {'t': 'unit'}}), (2, {'op': 'raise', 'code': self.code()}),
                          (1.5, {'op': 'canceled'}), (1, {'op': 'sleep', 'ms': self.r.randint(1, 3)}),
                          (0.3, {'op': 'never'})])

    def sem_section(self, env, k, size):
        """The body of a critical section: cedes, a marker, maybe a small program, then a stop."""
        ps = [{'op': 'cede'} for _ in range(self.pick([(2, 0), (3, 1), (2, 2), (1, 4)]))]
        ps.append(self.sem_mark(k))
        if size > 2 and self.r.random() < 0.3:
            ps.append(self.prog(self.small_type(), env, min(size, 4), {}))
        ps.append(self.sem_stop())
        return {'op': 'map', 'e': {'op': 'seq', 'ps': ps}, 'fn': 1}

    def sem_fiber(self, sv, env, k, size):
        """One user of semaphore `sv` (type unit)."""
        s = {'t': 'var', 'x': sv}
        n = self.pick([(1, 0), (6, 1), (3, 2), (1, 3)])
        kind = self.pick([(5, 'permit'), (3, 'acqrel'), (2, 'masked'), (3, 'try'), (1.5, 'read')])
        if kind == 'permit':
            return {'op': 'semPermit', 's': s, 'e': self.sem_section(env, k, size)}
        if kind == 'acqrel':
            ps = [{'op': 'semAcquireN', 's': s, 'n': n}, self.sem_mark(k)]
            ps += [{'op': 'cede'} for _ in range(self.r.randint(0, 2))]
            ps.append({'op': 'semReleaseN', 's': s, 'n': n})
            return {'op': 'seq', 'ps': ps}
        if kind == 'masked':
            # `uncancelable(p => poll(acquireN(n)) *> section-with-release)`: no permit leaks
            pv = self.fresh('p')
            ps = [{'op': 'poll', 'poll': pv, 'e': {'op': 'semAcquireN', 's': s, 'n': n}}, self.sem_mark(k)]
            if self.r.random() < 0.5:
                ps.append({'op': 'poll', 'poll': pv, 'e': {'op': 'cede'}})
            ps.append({'op': 'semReleaseN', 's': s, 'n': n})
            return {'op': 'uncancelable', 'poll': pv, 'body': {'op': 'seq', 'ps': ps}}
        if kind == 'try':
            return {'op': 'map', 'e': {'op': 'seq', 'ps': [{'op': 'semTryAcquireN', 's': s, 'n': n},
                    {'op': 'semCount', 's': s}]}, 'fn': 1}
        return {'op': 'map', 'e': {'op': 'seq', 'ps': [{'op': 'cede'}, {'op': 'semAvailable', 's': s}]}, 'fn': 1}

    def tpl_sem(self, env, size):
        """`Semaphore[IO](k)`; 1-3 started users (permit, acquire/release, masked acquire, tryAcquire,
        reads); the parent cedes, cancels some users (a cancel can land while a user waits, holds a
        permit, or between acquire and release), releases, joins the rest, then reads `available` and
        `count`. Type unit."""
        sv = self.fresh('s')
        k = self.pick([(3, 0), (4, 1), (3, 2), (1, 3)])
        env2 = {**env, sv: ('val', ('sem',))}
        s = {'t': 'var', 'x': sv}
        m = self.pick([(2, 1), (3, 2), (2, 3)])
        fvs = [self.fresh('x') for _ in range(m)]
        ps = []
        for _ in range(self.pick([(2, 0), (3, 1), (2, 2), (1, 3)])):
            ps.append({'op': 'cede'})
        canceled = set()
        for j, fv in enumerate(fvs):
            if self.r.random() < 0.45:
                if self.r.random() < 0.5:
                    ps.append({'op': 'cede'})
                ps.append({'op': 'cancel', 'f': {'t': 'var', 'x': fv}})
                canceled.add(j)
            if self.r.random() < 0.35:
                ps.append({'op': 'semReleaseN', 's': s, 'n': self.pick([(3, 1), (2, 2), (1, 3)])})
        if self.r.random() < 0.3:
            ps.append({'op': 'semPermit', 's': s, 'e': self.sem_section(env2, 99, size)})
        for j, fv in enumerate(fvs):
            if j not in canceled:
                ps.append({'op': 'map', 'e': {'op': 'join', 'f': {'t': 'var', 'x': fv}}, 'fn': 1})
        ps.append({'op': 'map', 'e': {'op': 'semAvailable', 's': s}, 'fn': 1})
        ps.append({'op': 'map', 'e': {'op': 'semCount', 's': s}, 'fn': 1})
        body = {'op': 'seq', 'ps': ps}
        for j in reversed(range(m)):
            env_j = {**env2, **{fvs[i]: ('val', fiber(UNIT)) for i in range(j)}}
            body = {'op': 'bind', 'x': fvs[j], 'e': {'op': 'start', 'e': self.sem_fiber(sv, env_j, j + 1, size)},
                    'k': body}
        return {'op': 'bind', 'x': sv, 'e': {'op': 'semNew', 'n': k}, 'k': body}

    def tpl_mutex(self, env, size):
        """`Mutex[IO]`; 1-3 started users of `lock.use`; the parent cedes, cancels some users,
        maybe takes the lock itself, joins the rest, then takes the lock once more (it must be free).
        Type unit."""
        mv = self.fresh('m')
        env2 = {**env, mv: ('val', ('mutex',))}
        mm = {'t': 'var', 'x': mv}
        m = self.pick([(2, 1), (3, 2), (2, 3)])
        fvs = [self.fresh('x') for _ in range(m)]
        ps = [{'op': 'cede'} for _ in range(self.pick([(2, 0), (3, 1), (2, 2), (1, 3)]))]
        canceled = set()
        for j, fv in enumerate(fvs):
            if self.r.random() < 0.45:
                if self.r.random() < 0.5:
                    ps.append({'op': 'cede'})
                ps.append({'op': 'cancel', 'f': {'t': 'var', 'x': fv}})
                canceled.add(j)
        if self.r.random() < 0.4:
            ps.append({'op': 'mutexLock', 'm': mm, 'e': self.sem_section(env2, 99, size)})
        for j, fv in enumerate(fvs):
            if j not in canceled:
                ps.append({'op': 'map', 'e': {'op': 'join', 'f': {'t': 'var', 'x': fv}}, 'fn': 1})
        ps.append({'op': 'mutexLock', 'm': mm, 'e': {'op': 'map', 'e': self.sem_mark(100), 'fn': 1}})
        body = {'op': 'seq', 'ps': ps}
        for j in reversed(range(m)):
            env_j = {**env2, **{fvs[i]: ('val', fiber(UNIT)) for i in range(j)}}
            body = {'op': 'bind', 'x': fvs[j],
                    'e': {'op': 'start', 'e': {'op': 'mutexLock', 'm': mm, 'e': self.sem_section(env_j, j + 1, size)}},
                    'k': body}
        return {'op': 'bind', 'x': mv, 'e': {'op': 'mutexNew'}, 'k': body}

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

    def tpl_res_both(self, t, env, size, ctx):
        """rUse(rBoth(rMake(..), rMake(..)), x, k) (format v2, track Res). The release of one side
        often raises an error (the shape of CE-0020: the other side's release can be canceled)."""
        renv = self.res_env(env)
        a, b = self.small_type(), self.small_type()
        sa, sb, sk = self.split_size(size - 1, 3)
        ra, rb = self.res_make(a, renv, sa, ctx), self.res_make(b, renv, sb, ctx)
        if self.r.random() < 0.5:
            ra['rel'] = {'op': 'seq', 'ps': [ra['rel'], {'op': 'raise', 'code': self.code()}]}
        if self.r.random() < 0.3:
            a, b, ra, rb = b, a, rb, ra
        x = self.fresh('x', env)
        k = self.prog(t, {**env, x: ('val', pair(a, b))}, sk, ctx)
        return {'op': 'rUse', 'res': {'op': 'rBoth', 'a': ra, 'b': rb}, 'x': x, 'k': k}

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

    # ---- format v2 (Phase 7, track Q): `qNew` queues of every kind and both families
    Q2_KINDS = [(3, ('bounded', 1)), (3, ('bounded', 2)), (2, ('bounded', 3)), (1, ('bounded', 0)),
                (0.3, ('bounded', 70000)), (1, ('dropping', 1)), (2, ('dropping', 2)),
                (1, ('circularBuffer', 1)), (2, ('circularBuffer', 2)), (3, ('synchronous', 0)),
                (3, ('unbounded', 0)), (1, ('boundedConc', 1)), (2, ('boundedConc', 2)),
                (2, ('unboundedConc', 0)), (1, ('droppingConc', 2))]

    def q2_emit(self, e):
        """bind r = e in delay fn1 r: the trace shows the result."""
        r = self.fresh('x')
        return {'op': 'bind', 'x': r, 'e': e, 'k': {'op': 'delay', 'fn': 1, 'arg': {'t': 'var', 'x': r}}}

    def q2_take(self, qv):
        """A take: plain, the atomic pattern `uncancelable(poll => poll(take).flatMap(emit))`
        (QueueSuite "not lose data on canceled take"), or `take.timeout` (the CE-0003 shape)."""
        take = {'op': 'qTake', 'q': qv}
        x = self.r.random()
        if x < 0.4:
            return self.q2_emit(take)
        if x < 0.75:
            pv = self.fresh('p')
            return {'op': 'uncancelable', 'poll': pv,
                    'body': {'op': 'poll', 'poll': pv, 'e': self.q2_emit(take)}}
        return {'op': 'map', 'e': {'op': 'attempt', 'e': {'op': 'timeout', 'e': self.q2_emit(take),
                                                          'ms': self.timeout_ms()}}, 'fn': 1}

    def q2_op(self, qv, child):
        """One queue operation (results in the trace)."""
        self.q2_next += 1
        lit = {'t': 'nat', 'v': self.q2_next}
        k = self.pick([(4, 'offer'), (2, 'tryOffer'), (3 if child else 1, 'take'), (2, 'tryTake'),
                       (1, 'size'), (2, 'cede')])
        if k == 'offer':
            return {'op': 'qOffer', 'q': qv, 'v': lit}
        if k == 'tryOffer':
            return self.q2_emit({'op': 'qTryOffer', 'q': qv, 'v': lit})
        if k == 'take':
            return self.q2_take(qv)
        if k == 'tryTake':
            return self.q2_emit({'op': 'qTryTake', 'q': qv})
        if k == 'size':
            return self.q2_emit({'op': 'qSize', 'q': qv})
        return {'op': 'cede'}

    def tpl_queue2(self, t, env, size, ctx):
        """bind q = qNew(kind, cap) in a scenario: 0-3 child fibers run 1-4 queue operations each
        (often an atomic take, sometimes guarded by onCancel); the parent runs queue operations,
        cedes, sleeps, cancels or joins children; then it uses every queue op once more and drains
        with tryTake. Elements are distinct literals."""
        self.q2_next = getattr(self, 'q2_next', 0)
        kind, cap = self.pick(self.Q2_KINDS)
        q = self.fresh('x')
        qv = {'t': 'var', 'x': q}
        binds = []
        kids = []
        for _ in range(self.pick([(1, 0), (3, 1), (3, 2), (1, 3)])):
            ops = [self.q2_op(qv, True) for _ in range(self.r.randint(1, 4))]
            c = ops[0] if len(ops) == 1 else {'op': 'seq', 'ps': ops}
            if self.r.random() < 0.2:
                c = self.tag({'op': 'onCancel', 'e': c, 'fin': {'op': 'delay', 'fn': 1, 'arg': {'t': 'nat', 'v': 77}}})
            f = self.fresh('x')
            kids.append(f)
            binds.append((f, {'op': 'start', 'e': c}))
        steps = []
        for _ in range(self.r.randint(1, 6)):
            k = self.pick([(5, 'op'), (2, 'cede'), (1, 'sleep'), (2.5 if kids else 0, 'cancel'),
                           (1.5 if kids else 0, 'join')])
            if k == 'op':
                steps.append(self.q2_op(qv, False))
            elif k == 'cede':
                steps.append({'op': 'cede'})
            elif k == 'sleep':
                steps.append({'op': 'sleep', 'ms': self.pick([(2, 0), (3, 1), (1, 10)])})
            elif k == 'cancel':
                steps.append({'op': 'cancel', 'f': {'t': 'var', 'x': self.r.choice(kids)}})
            else:
                # join with a timeout: a child can wait forever on an empty queue
                steps.append({'op': 'map', 'e': {'op': 'attempt', 'e': {'op': 'timeout', 'e': {
                    'op': 'join', 'f': {'t': 'var', 'x': self.r.choice(kids)}}, 'ms': self.timeout_ms()}}, 'fn': 1})
        # every op at least once (a full queue makes `qOffer` wait, so it gets a timeout)
        self.q2_next += 1
        steps.append({'op': 'map', 'e': {'op': 'attempt', 'e': {'op': 'timeout', 'e': {
            'op': 'qOffer', 'q': qv, 'v': {'t': 'nat', 'v': self.q2_next}}, 'ms': self.timeout_ms()}}, 'fn': 1})
        self.q2_next += 1
        steps.append(self.q2_emit({'op': 'qTryOffer', 'q': qv, 'v': {'t': 'nat', 'v': self.q2_next}}))
        steps.append({'op': 'map', 'e': {'op': 'attempt', 'e': {'op': 'timeout', 'e': self.q2_emit(
            {'op': 'qTake', 'q': qv}), 'ms': self.timeout_ms()}}, 'fn': 1})
        steps.append(self.q2_emit({'op': 'qSize', 'q': qv}))
        steps += [self.q2_emit({'op': 'qTryTake', 'q': qv}) for _ in range(self.pick([(1, 1), (2, 2), (1, 3)]))]
        body = {'op': 'seq', 'ps': steps}
        for f, e in reversed(binds):
            body = {'op': 'bind', 'x': f, 'e': e, 'k': body}
        return {'op': 'bind', 'x': q, 'e': {'op': 'qNew', 'kind': kind, 'cap': cap}, 'k': body}

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

    # ---- format v2 (track R)

    COMBS = ('race', 'raceOutcome', 'both', 'bothOutcome')

    @staticmethod
    def comb_type(kind, a, b):
        """The value type of `kind(a, b)` after the interpreter's conversion."""
        if kind == 'race':
            return either(a, b)
        if kind == 'raceOutcome':
            return either(outcome(a), outcome(b))
        if kind == 'both':
            return pair(a, b)
        return pair(outcome(a), outcome(b))

    def comb_side(self, t, env, size, ctx):
        """One side of a combinator: often it waits first (sleep, cede), never ends, is masked, or
        has a finalizer, so the loser is really canceled and the cancel paths run."""
        k = self.pick([(5, 'plain'), (3, 'sleep'), (1.5, 'cede'), (1, 'never'), (1, 'masked'), (1.5, 'fin'),
                       (1, 'canceled'), (0.8, 'raise')])
        if k == 'never':
            return {'op': 'never'}
        if k == 'canceled':
            return {'op': 'seq', 'ps': [{'op': 'canceled'}, self.prog(t, env, max(1, size - 1), ctx)]}
        if k == 'raise':
            return {'op': 'seq', 'ps': [self.prog(UNIT, env, max(1, size // 2), ctx), {'op': 'raise', 'code': self.r.randint(0, 9)}]}
        e = self.prog(t, env, size, ctx)
        if k == 'plain':
            return e
        if k == 'masked':
            q = self.fresh('p')
            return {'op': 'uncancelable', 'poll': q, 'body': {'op': 'seq', 'ps': [{'op': 'sleep', 'ms': self.pick([(1, 1), (1, 10)])}, e]}}
        if k == 'fin':
            x = self.fresh('x', env)
            return self.tag({'op': 'guaranteeCase', 'e': e, 'x': x,
                             'fin': self.prog(UNIT, {**env, x: ('val', outcome(t))}, 1, self.fin_ctx(ctx))})
        w = {'op': 'cede'} if k == 'cede' else {'op': 'sleep', 'ms': self.pick([(2, 1), (3, 10), (1, 100)])}
        return {'op': 'seq', 'ps': [w, e]}

    def g_comb(self, kind, a, b, env, size, ctx):
        sa, sb = self.split_size(size, 2)
        return {'op': kind, 'a': self.comb_side(a, env, sa, ctx), 'b': self.comb_side(b, env, sb, ctx)}

    def tpl_comb(self, t, env, size, ctx):
        """bind x = comb(a, b) in k (any wanted type)."""
        kind = self.r.choice(self.COMBS)
        a, b = self.small_type(), self.small_type()
        sc, sk = self.split_size(size, 2)
        x = self.fresh('x', env)
        e = self.g_comb(kind, a, b, env, max(3, sc), self.child_ctx(ctx))
        return {'op': 'bind', 'x': x, 'e': e,
                'k': self.prog(t, {**env, x: ('val', self.comb_type(kind, a, b))}, sk, ctx)}

    def tpl_comb_cancel(self, t, env, size, ctx):
        """Decision 50: bind f = start(comb(a, b)) in seq(maybe cede/sleep, cancel f, maybe join f, k)."""
        kind = self.r.choice(self.COMBS)
        a, b = self.small_type(), self.small_type()
        sc, sk = self.split_size(size, 2)
        f = self.fresh('x')
        fv = {'t': 'var', 'x': f}
        ct = self.comb_type(kind, a, b)
        env2 = {**env, f: ('val', fiber(ct))}
        ps = [self.pick([(3, {'op': 'cede'}), (2, {'op': 'sleep', 'ms': 1}), (1, {'op': 'sleep', 'ms': 10}),
                         (1, {'op': 'pure', 'v': {'t': 'unit'}})])]
        ps.append({'op': 'cancel', 'f': fv})
        if self.r.random() < 0.7:
            ps.append({'op': 'join', 'f': fv})
        ps.append(self.prog(t, env2, sk, ctx))
        return {'op': 'bind', 'x': f, 'e': {'op': 'start', 'e': self.g_comb(kind, a, b, env, max(3, sc), self.child_ctx(ctx))},
                'k': {'op': 'seq', 'ps': ps}}

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
    # Preempt coverage: small thresholds put an auto-yield (the effect of a SchedP `preempt`
    # choice) after every few run-loop iterations. Own RNG, so the other fields do not change.
    rr = random.Random(f"difftest-runtime:{seed}:{i}")
    if rr.random() < g.c['p_runtime']:
        cct = rr.choice([1, 1, 2, 4])
        case['runtime'] = {'cancelationCheckThreshold': cct,
                           'autoYieldThreshold': cct * rr.randint(2 if cct == 1 else 1, 8)}
    # Batch 6.3: append `parTraverseN` (plain, or in a child that the parent cancels). Own RNG,
    # so the rest of the case does not change; the probability scales with the template weights.
    pr = random.Random(f"difftest-partraverse:{seed}:{i}")
    w = g.w
    pp = g.c['p_par_traverse'] * (w['tpl_parTraverse'] + w['tpl_parTraverseCancel']) / 1.8
    if prog.get('op') != 'syncStep' and pr.random() < pp:
        g2 = Gen(pr, weights, config)
        g2.names = 10000
        cancel = pr.random() * (w['tpl_parTraverse'] + w['tpl_parTraverseCancel']) < w['tpl_parTraverseCancel']
        extra = g2.tpl_par_traverse(UNIT, {}, pr.randint(3, 12), {}, cancel)
        prog = {'op': 'seq', 'ps': [prog, extra]}
        check_prog(prog)
    # Phase 7, track Q: append a `qNew` queue scenario. Own RNG, so the rest of the case does not
    # change; the probability scales with the template weight (`--boost tpl_queue2=F`).
    qr = random.Random(f"difftest-queue2:{seed}:{i}")
    if prog.get('op') != 'syncStep' and qr.random() < g.c['p_queue2'] * w['tpl_queue2']:
        g3 = Gen(qr, weights, config)
        g3.names = 40000  # own name base (latch 20000, semaphore 30000; review batch 11a D3)
        extra = g3.tpl_queue2(UNIT, {}, qr.randint(3, 12), {})
        prog = {'op': 'seq', 'ps': [prog, extra]}
        check_prog(prog)
    # Phase 7, track S: append a `Semaphore` or `Mutex` scenario. Own RNG, so the rest of the case
    # does not change; the probability scales with the template weights.
    sr = random.Random(f"difftest-semaphore:{seed}:{i}")
    ps = g.c['p_sem'] * (w['tpl_sem'] + w['tpl_mutex']) / 1.6
    if prog.get('op') != 'syncStep' and sr.random() < ps:
        g3 = Gen(sr, weights, config)
        g3.names = 30000
        mutex = sr.random() * (w['tpl_sem'] + w['tpl_mutex']) < w['tpl_mutex']
        extra = g3.tpl_mutex({}, sr.randint(3, 10)) if mutex else g3.tpl_sem({}, sr.randint(3, 10))
        prog = {'op': 'seq', 'ps': [prog, extra]}
        check_prog(prog)
    # Phase 7, track L: append a `CountDownLatch` or `CyclicBarrier` scenario. Own RNG, so the
    # rest of the case does not change; the probability scales with the template weights.
    lr = random.Random(f"difftest-latch:{seed}:{i}")
    pl = g.c['p_latch'] * (w['tpl_cdl'] + w['tpl_cb']) / 2.0
    if prog.get('op') != 'syncStep' and lr.random() < pl:
        g3 = Gen(lr, weights, config)
        g3.names = 20000
        barrier = lr.random() * (w['tpl_cdl'] + w['tpl_cb']) < w['tpl_cb']
        extra = g3.tpl_latch({}, lr.randint(3, 16), {}, barrier)
        prog = {'op': 'seq', 'ps': [prog, extra]}
        check_prog(prog)
    # Phase 7, track V: append a `Supervisor` scenario. Own RNG, so the rest of the case does not
    # change; the probability scales with the template weight.
    vr = random.Random(f"difftest-supervisor:{seed}:{i}")
    if prog.get('op') != 'syncStep' and vr.random() < g.c['p_sup'] * w['tpl_sup']:
        g3 = Gen(vr, weights, config)
        g3.names = 80000
        extra = g3.tpl_sup({}, vr.randint(3, 12), {})
        prog = {'op': 'seq', 'ps': [prog, extra]}
        if any(x.get('rs') for x in walk_sup(extra)):
            case['maxSteps'] = min(case.get('maxSteps', 150), 150)
        check_prog(prog)
    # Phase 7, track P7D: append a `Dispatcher` scenario. Own RNG, so the rest of the case does not
    # change; the probability scales with the template weight.
    dr = random.Random(f"difftest-dispatcher:{seed}:{i}")
    # not in a case with a tiny `maxSteps` (`p_small_maxsteps`): the scenario never runs there, it
    # only turns a finished run into a `fuel` one (self-test bound on blocked + fuel outcomes)
    if prog.get('op') != 'syncStep' and dr.random() < g.c['p_disp'] * w['tpl_disp'] and \
            case.get('maxSteps', 10000) > 5:
        g3 = Gen(dr, weights, config)
        g3.names = 90000
        extra = g3.tpl_disp({}, dr.randint(3, 12), {})
        prog = {'op': 'seq', 'ps': [prog, extra]}
        check_prog(prog)
    case['prog'] = prog
    return case


def walk_sup(p):
    """The `supUse` nodes of a program (track V)."""
    if isinstance(p, dict):
        if p.get('op') == 'supUse':
            yield p
        for v in p.values():
            yield from walk_sup(v)
    elif isinstance(p, list):
        for v in p:
            yield from walk_sup(v)


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

"""Scope and type checker for difftest programs (format v1; v0 is a subset).

Spec: wiki/methodology/difftest-program-format.md.
A program that passes `check_prog` cannot raise `TypeError` in the Scala runner
(decision 8: a TypeError is a generator bug). The generator asserts this for each case,
and the shrinker uses it to keep only well-typed candidates.

Types are tuples: ('unit',), ('bool',), ('nat',), ('pair', A, B), ('either', A, B),
('outcome', A), ('fiber', A), ('ref', A), ('deferred', A), ('queue', A) and, for resource
positions only, ('resource', A). Type variables are ('?', n).
Inference is first-order unification (no let-polymorphism; a variable has one type).
"""

MAX_NAT = 9 * 10**15


class TypeErr(Exception):
    pass


# user function id -> (argument type, result type) builder; `f` makes fresh variables
def _fn_sig(fn, f):
    a, b = f(), f()
    table = {
        0: (a, a),
        1: (a, ('unit',)),
        2: (('nat',), ('nat',)),
        3: (('nat',), a),  # raises UserError(n); result type is free
        4: (a, ('pair', a, a)),
        5: (('nat',), ('pair', ('nat',), ('nat',))),
        6: (('bool',), ('bool',)),
        7: (('nat',), ('bool',)),
        8: (('pair', a, b), a),
        9: (('pair', a, b), b),
    }
    if fn not in table:
        raise TypeErr(f"unknown user function {fn}")
    return table[fn]


class Checker:
    def __init__(self):
        self.sub = {}
        self.n = 0

    def fresh(self):
        self.n += 1
        return ('?', self.n)

    def resolve(self, t):
        while t[0] == '?' and t in self.sub:
            t = self.sub[t]
        return t

    def zonk(self, t):
        t = self.resolve(t)
        if t[0] == '?':
            return t
        return (t[0],) + tuple(self.zonk(x) for x in t[1:])

    def occurs(self, v, t):
        t = self.resolve(t)
        if t == v:
            return True
        return t[0] != '?' and any(self.occurs(v, x) for x in t[1:])

    def unify(self, a, b, where=""):
        a, b = self.resolve(a), self.resolve(b)
        if a == b:
            return
        if a[0] == '?':
            if self.occurs(a, b):
                raise TypeErr(f"{where}: infinite type")
            self.sub[a] = b
            return
        if b[0] == '?':
            self.unify(b, a, where)
            return
        if a[0] != b[0] or len(a) != len(b):
            raise TypeErr(f"{where}: {self.zonk(a)} vs {self.zonk(b)}")
        for x, y in zip(a[1:], b[1:]):
            self.unify(x, y, where)

    # ------------------------------------------------------------ values

    def val(self, v):
        if not isinstance(v, dict) or 't' not in v:
            raise TypeErr(f"bad value {v!r}")
        t = v['t']
        if t == 'unit':
            return ('unit',)
        if t == 'bool':
            if not isinstance(v.get('v'), bool):
                raise TypeErr("bool literal")
            return ('bool',)
        if t == 'nat':
            n = v.get('v')
            if not isinstance(n, int) or isinstance(n, bool) or not 0 <= n <= MAX_NAT:
                raise TypeErr(f"nat literal {n!r}")
            return ('nat',)
        if t == 'pair':
            return ('pair', self.val(v['a']), self.val(v['b']))
        if t == 'left':
            return ('either', self.val(v['v']), self.fresh())
        if t == 'right':
            return ('either', self.fresh(), self.val(v['v']))
        if t == 'succeeded':
            return ('outcome', self.val(v['v']))
        if t in ('errored', 'canceled'):
            return ('outcome', self.fresh())
        raise TypeErr(f"value tag {t!r} cannot be a literal")

    def atom(self, a, env):
        if isinstance(a, dict) and a.get('t') == 'var':
            b = env.get(a.get('x'))
            if b is None:
                raise TypeErr(f"unbound variable {a.get('x')!r}")
            if b[0] != 'val':
                raise TypeErr(f"{a['x']!r} is a poll, not a value")
            return b[1]
        return self.val(a)

    # ---------------------------------------------------------- programs

    def prog(self, p, env):
        op = p.get('op')
        f = self.fresh
        u = self.unify
        if op == 'pure':
            return self.atom(p['v'], env)
        if op == 'raise':
            return f()
        if op == 'delay':
            arg, res = _fn_sig(p['fn'], f)
            u(arg, self.atom(p['arg'], env) if 'arg' in p else ('unit',), f"delay fn {p['fn']}")
            return res
        if op == 'bind':
            t = self.prog(p['e'], env)
            return self.prog(p['k'], {**env, p['x']: ('val', t)})
        if op == 'seq':
            if not p['ps']:
                raise TypeErr("empty seq")
            t = None
            for q in p['ps']:
                t = self.prog(q, env)
            return t
        if op == 'map':
            arg, res = _fn_sig(p['fn'], f)
            u(arg, self.prog(p['e'], env), f"map fn {p['fn']}")
            return res
        if op == 'handleErrorWith':
            t = self.prog(p['e'], env)
            u(t, self.prog(p['k'], {**env, p['x']: ('val', ('nat',))}), "handleErrorWith")
            return t
        if op == 'attempt':
            return ('either', ('nat',), self.prog(p['e'], env))
        if op == 'uncancelable':
            return self.prog(p['body'], {**env, p['poll']: ('poll',)})
        if op == 'poll':
            if env.get(p['poll']) != ('poll',):
                raise TypeErr(f"{p['poll']!r} is not a bound poll")
            return self.prog(p['e'], env)
        if op == 'onCancel':
            t = self.prog(p['e'], env)
            self.prog(p['fin'], env)
            return t
        if op == 'guaranteeCase':
            t = self.prog(p['e'], env)
            self.prog(p['fin'], {**env, p['x']: ('val', ('outcome', t))})
            return t
        if op in ('canceled', 'cede', 'sleep'):
            return ('unit',)
        if op == 'never':
            return f()
        if op == 'start':
            return ('fiber', self.prog(p['e'], env))
        if op == 'join':
            a = f()
            u(self.atom(p['f'], env), ('fiber', a), "join")
            return ('outcome', a)
        if op == 'cancel':
            u(self.atom(p['f'], env), ('fiber', f()), "cancel")
            return ('unit',)
        if op == 'racePair':
            a, b = self.prog(p['a'], env), self.prog(p['b'], env)
            return ('either', ('pair', ('outcome', a), ('fiber', b)), ('pair', ('fiber', a), ('outcome', b)))
        if op == 'refNew':
            return ('ref', self.atom(p['v'], env))
        if op == 'refGet':
            a = f()
            u(self.atom(p['r'], env), ('ref', a), "refGet")
            return a
        if op == 'refSet':
            u(self.atom(p['r'], env), ('ref', self.atom(p['v'], env)), "refSet")
            return ('unit',)
        if op == 'refModify':
            s = f()
            u(self.atom(p['r'], env), ('ref', s), "refModify")
            arg, res = _fn_sig(p['fn'], f)
            u(arg, s, "refModify arg")
            out = f()
            if p['fn'] == 3:  # raises before it returns; the result shape is never seen
                return out
            u(res, ('pair', s, out), "refModify result")
            return out
        if op == 'deferredNew':
            return ('deferred', f())
        if op == 'deferredGet':
            a = f()
            u(self.atom(p['d'], env), ('deferred', a), "deferredGet")
            return a
        if op == 'deferredComplete':
            u(self.atom(p['d'], env), ('deferred', self.atom(p['v'], env)), "deferredComplete")
            return ('bool',)
        if op == 'async':
            t = f()
            for cb in p['cbs']:
                if cb.get('when') not in ('sync', 'later'):
                    raise TypeErr("callback.when")
                if ('ok' in cb) == ('err' in cb):
                    raise TypeErr("callback needs exactly one of ok/err")
                if 'ok' in cb:
                    u(t, self.val(cb['ok']), "async ok")
            if 'fin' in p:
                self.prog(p['fin'], env)
            return t
        if op == 'case':
            a, b = f(), f()
            u(self.atom(p['on'], env), ('either', a, b), "case")
            t = self.prog(p['lk'], {**env, p['l']: ('val', a)})
            u(t, self.prog(p['rk'], {**env, p['r']: ('val', b)}), "case branches")
            return t
        if op == 'split':
            a, b = f(), f()
            u(self.atom(p['on'], env), ('pair', a, b), "split")
            env2 = {**env, p['a']: ('val', a)}
            env2[p['b']] = ('val', b)
            return self.prog(p['k'], env2)
        # ---- format v1
        if op == 'timeout':
            _ms(p)
            return self.prog(p['e'], env)
        if op == 'timeoutTo':
            _ms(p)
            t = self.prog(p['e'], env)
            u(t, self.prog(p['fb'], env), "timeoutTo fallback")
            return t
        # ---- format v2 (track R)
        if op in ('race', 'raceOutcome', 'both', 'bothOutcome'):
            a, b = self.prog(p['a'], env), self.prog(p['b'], env)
            if op in ('raceOutcome', 'bothOutcome'):
                a, b = ('outcome', a), ('outcome', b)
            return ('either' if op.startswith('race') else 'pair', a, b)
        if op == 'queueNew':
            return ('queue', f())
        if op == 'queueOffer':
            u(self.atom(p['q'], env), ('queue', self.atom(p['v'], env)), "queueOffer")
            return ('unit',)
        if op == 'queueTake':
            a = f()
            u(self.atom(p['q'], env), ('queue', a), "queueTake")
            return a
        if op == 'queueTryTake':
            a = f()
            u(self.atom(p['q'], env), ('queue', a), "queueTryTake")
            return ('either', ('unit',), a)
        if op == 'allocatedCase':
            return self.res(p['res'], env)
        if op == 'syncStep':
            raise TypeErr("syncStep below the root")
        if op in RES_OPS:
            raise TypeErr(f"resource op {op!r} at a program position")
        raise TypeErr(f"unknown op {op!r}")

    def res(self, r, env):
        """The value type A of a resource node (`Resource[IO, A]`)."""
        op = r.get('op')
        if op == 'rPure':
            return self.atom(r['v'], env)
        if op == 'rEval':
            return self.prog(r['e'], env)
        if op == 'rMake':
            a = self.prog(r['acq'], env)
            self.prog(r['rel'], {**env, r['x']: ('val', a)})
            return a
        if op == 'rFlatMap':
            a = self.res(r['res'], env)
            return self.res(r['k'], {**env, r['x']: ('val', a)})
        raise TypeErr(f"op {op!r} at a resource position")


RES_OPS = ('rPure', 'rEval', 'rMake', 'rFlatMap')
MAX_LIMIT = 2**31 - 1


def _ms(p):
    ms = p.get('ms')
    if not isinstance(ms, int) or isinstance(ms, bool) or not 0 <= ms <= MAX_NAT:
        raise TypeErr(f"ms {ms!r}")


def check_prog(p):
    """Return the (zonked) type of a closed program, or raise TypeErr. `syncStep` is allowed
    only at the root."""
    c = Checker()
    try:
        if p.get('op') == 'syncStep':
            lim = p['limit']
            if not isinstance(lim, int) or isinstance(lim, bool) or not 0 <= lim <= MAX_LIMIT:
                raise TypeErr(f"syncStep limit {lim!r}")
            return c.zonk(c.prog(p['e'], {}))
        return c.zonk(c.prog(p, {}))
    except (KeyError, TypeError, AttributeError) as e:
        raise TypeErr(f"malformed program: {e!r}") from e


def well_typed(p):
    try:
        check_prog(p)
        return True
    except TypeErr:
        return False

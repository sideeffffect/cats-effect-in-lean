# HN: Formalizing CPython (python-formalization) — full comment thread

> Source: https://news.ycombinator.com/item?id=50435105 (via https://hn.algolia.com/api/v1/items/50435105)
> Collected: 2026-11-10
> Published: 2026-11-10

Story: "Formalizing CPython" -> https://broyojo.com/python-formalization/ , submitted by carnevalem, 42 points at collection time. The thread was a few hours old and small; all comments with text kept verbatim (one comment by perching_aix was [delayed]/empty).

### anewhnaccount2 — 2026-11-10 (https://news.ycombinator.com/item?id=50436290; parent 50435105)

Same approach for Julias stdlib: https://discourse.julialang.org/t/formalizing-julia-in-lean-and-finding-400-bugs-in-base/140243

### up2isomorphism — 2026-11-10 (https://news.ycombinator.com/item?id=50436609; parent 50435105)

AI does not kill research, research kills pretty much itself already.

### jakobnissen — 2026-11-10 (https://news.ycombinator.com/item?id=50436643; parent 50435105)

I think this approach to bug hunting is super promising (obviously - it finds a ton of bugs). The long-term problem is how this kind of bug-hunting can be done routinely, e.g. as part of a test suite. The approach taken by these people, the same approach as when the Julia folks did it, isn't really automatable, because it requires a lot of both human and AI agent work.

I guess longer term it needs to be built into the language, to prevent code and lean proofs from drifting. I.e. it could be opt-in properties that are written along the code, and which is then checked in the test suite. So very similar to ordinary compiler checks, except more expressive and expensive, and done only at test time.

### bb88 — 2026-11-10 (https://news.ycombinator.com/item?id=50436783; parent 50435105)

Only 418?

I would have expected around 10k.

Edit:  Professional python programmer.

### perching_aix — 2026-11-10 (https://news.ycombinator.com/item?id=50437082; parent 50436783)

[delayed]

### eternauta3k — 2026-11-10 (https://news.ycombinator.com/item?id=50436806; parent 50435105)

Is there a way to avoid the translation or replace it with normal parsing?

### choeger — 2026-11-10 (https://news.ycombinator.com/item?id=50436859; parent 50436806)

In principle, yes.

I am not a lean expert, but I imagine that python primitives like dicts, ints, functions, etc., have been defined in lean. So if you add a way to annotate python code with a proof, you should as well be able to automatically translate it to Lean completely.

### senderista — 2026-11-10 (https://news.ycombinator.com/item?id=50436866; parent 50435105)

Cite an AI-written document? Hell no.

### woggy — 2026-11-10 (https://news.ycombinator.com/item?id=50436896; parent 50435105)

Can we just develop in Lean and compile to something else for speed?

### iib — 2026-11-10 (https://news.ycombinator.com/item?id=50437029; parent 50436896)

Lean is actually pretty speedy as is, and it enables much harder optimizations[1]

[1] https://github.com/kim-em/lean-zip#verification-enables-performance

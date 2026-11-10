# HN: AI, Lean, and the Future of Formal Verification (Leo de Moura interview) — selected comments

> Source: https://news.ycombinator.com/item?id=50290652
> Collected: 2026-11-10
> Published: 2026-10-29

Story links to https://thedataexchange.media/leo-de-moura-lean-aws/ (219 points, 58 comments). Selected comments. Verbatim. [...omitted: remaining comments...]

### jdw64 — 2026-10-31 (https://news.ycombinator.com/item?id=50314487; parent 50290652)

While learning and applying formal verification in the context of using AI agents, what I feel is that sometimes it's hard to express my own thoughts as formal verification. But more than that, I doubt whether formal verification being done correctly actually solves the phenomenon of AI spinning in circles on a specific task.

For example, I want to eat chicken, so I try formally verifying "chicken dish," and every time GPT or Claude starts digging into the origin of the sauce in the chicken dish or the breed of the chicken. Then the chicken dish never gets finished and never makes it to dinner, and instead I gain deep knowledge about the origin of chickens.

Of course, I know that formal verification has liveness — meaning that there must be progress in the work is also part of formal verification — but the AI judges that learning the origin of the chicken counts as progress too. Yet it ends up doing work that it actually shouldn't be doing.

Personally, while organizing these AI anti-patterns, I feel that when you formally verify one condition, verification of another condition gets weakened, and within that phenomenon I sense the AI spinning in circles again. In the end, I end up going through the process of reading and merging everything one by one myself, and I want to know whether this is something only I experience.

### wbeckler — 2026-10-31 (https://news.ycombinator.com/item?id=50316022; parent 50290652)

I think the royal combo is Lean 4/TLA+/etc. plus AI plus a deterministic generator. For large systems formal method assertions need to be compressed down to a human comprehensible size. This can happen when the assertions are confirming the accuracy of a model and its attached code generators. The generator can generate proofs of the generated code and a human only needs to ensure that the generator provably generates the correct mass scale assertions.

This is how formal methods can constrain AI for large systems.

We're doing this at the Open Markets Initiative, where we've generated millions of lines of Lean 4, TLA+, and Rocq that ensure that our open source electronic trading protocol code is accurate. We didn't expect it but the Lean prover did identify some incorrect steps.
https://github.com/Open-Markets-Initiative

### voidhorse — 2026-10-31 (https://news.ycombinator.com/item?id=50321056; parent 50318321)

You don't. You place unwavering faith in the machine god.

This is why, for formal methods to really be the next step, we'll need deterministic source to CoC language compilers, and we'll need to go back again.

Lean is kind of an unfortunate, cargo cult choice because it only compiles to C. Really for software we should use a prover that has a lot more targets, like Danfy. Even Rocq (formerly Coq) can compile down to several functional languages, which is more than we can say for lean.

As usual, the AI crowd latched on to the first solution that came to mind, and thanks to its prominence in mathematics applications recently just lazily are starting to try and apply it to computing, without actually understanding anything or weighing trade offs. Of course, now we are basically stuck with Lean since the models will have been trained hard on it. At least it's a CoC language, but now we need to build a bunch of extra compilation around it  for this to really work.

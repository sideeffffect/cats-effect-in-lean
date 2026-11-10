# HN: When AI writes the software, who verifies it? (Leo de Moura) — selected comments

> Source: https://news.ycombinator.com/item?id=47234917
> Collected: 2026-11-10
> Published: 2026-03-03

305 points, ~282 comments. Selected substantive comments. Verbatim. [...omitted: remaining comments...]

### muraiki — 2026-03-03 (https://news.ycombinator.com/item?id=47237101; parent 47234917)

The article says that AWS's Cedar authorization policy engine is written in Lean, but it's actually written in Dafny. Writing Dafny is a lot closer to writing "normal" code rather than the proofs you see in Lean. As a non-mathematician I gave up pretty early in the Lean tutorial, while in a recent prototype I learned enough Dafny to be semi-confident in reviewing Claude's Dafny code in about half a day.

The Dafny code formed a security kernel at the core of a service, enforcing invariants like that an audit log must always be written to prior to a mutating operation being performed. Of course I still had bugs, usually from specification problems (poor spec / design) or Claude not taking the proof far enough (proving only for one of a number of related types, which could also have been a specification problem on my part).

In the end I realized I'm writing a bunch of I/O bound glue code and plain 'ol test driven development was fine enough for my threat model. I can review Python code more quickly and accurately than Dafny (or the Go code it eventually had to link to), so I'm back to optimizing for humans again...

### miraculixx — 2026-03-06 (https://news.ycombinator.com/item?id=47273786; parent 47240160)

Sure because it worked great when we tried last time, right? Just spec it out first, and AI will churn out the perfect app. Not.

For anyone who hasn't worked in a waterfall project and would like to try: You are kidding yourself.

There is no such thing as a perfect spec. Read that again and say it outloud.

It took humanity 50 years to figure out that perfect specs are impossible, unless of course you know exactly(!) what you need. And even then, the specs are never complete.

The reality is that we often don't know, and can't know, what we want, exactly, until we actually see and experience what we said we wanted. Then we adjust. Try again.

That's the reality for individuals already. By simply using logic we can deduct that entities made of more than one individual, aka companies, will not behave better. They just make it look better by giving you a nice document that says "we want this!", only to then come around when they see what they got, and to claim "wait, we didn't mean it like so!".

That's just human nature. Not much we can do. AI will not change that.

So when some people think AI will deliver perfect software given perfect specs, hence we have to write the specs first! That is just missing the boat my a mile.

Agile is not a process but a human-friendly way of doing things. It simply says hey you want this? Let me build that and show you. Then let's adjust or move to the next thing. Rinse and repeat. Agile works because it matches how humans think and act. Step by step, day by day.

### csense — 2026-03-03 (https://news.ycombinator.com/item?id=47240909; parent 47234917)

It seems like sound testing methodology to identify important theorems related to the code, prove them, and then verify the proof.

Verification gets sold as "bulletproof" but I'm skeptical for a couple reasons:

- How do you establish the relationship between the code and the theorem?  Lean theorem can be applied to zlib implemented in Lean, what if you want to check zlib implemented in a normal programming language like C, JS, Zig, or whatever?

- How do you know the key properties mean what you think they mean?  E.g. the theorem says "ZlibDecode.decompressSingle (ZlibEncode.compress data level) = .ok data" but it feels like it would be very easy to accidentally prove ∃ x s.t. decompress(compress(x)) == x while thinking you proved ∀ x, decompress(compress(x)) == x.

I've tried Lean and Coq and...I don't really like them.  The proofs use specialized programming languages.  And they seem deliberately designed to require you to use a context explorer to have any hope of understanding the proof at all.  OTOH a normal unit test is written in a general purpose programming language (usually the same one as the program being tested), I'm much more comfortable checking that a Claude-written unit test does what I think it's doing than a Claude-written Lean proof of correctness.

### anonymous6500 — 2026-03-04 (https://news.ycombinator.com/item?id=47245811; parent 47240909)

The article does not reveal it to me either how the existing code would be mapped to Lean and back. The impression from zlib example is that I'd be expected to program in Lean. No way it's going to happen. The language is too complex for me and my average colleague. We're also not going to have two parallel implementations in ordinary language and Lean and compare them with 'differential random testing' (see https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development/ someone linked in the discussion), that's just too taxing for bigger products, let alone we typically don't have enough time to do one implementation right.

The gap of having succinct, expressive, powerful and executable specification to be able to continuously verify AI-generated programs is real, but I don't see how Lean alone closes it. If the author's intention was to attract community to help build that out with Lean in the center, it's not clear to me where to even start. Since the author provided no hints or direction, I've a feeling it's not clear to them either.

### MickeyShmueli — 2026-03-04 (https://news.ycombinator.com/item?id=47248720; parent 47234917)

the test generation loop is brutal. i've been burned by this exact thing, you ask the agent to write code, then ask it to write tests for that code, and surprise, they all pass because the tests are literally just "does the code do what the code does"

honestly think the answer isn't more tests, it's stricter contracts. like if your API has an OpenAPI spec, you can validate requests/responses against it automatically. the spec becomes the source of truth, not the tests, not the implementation

we've been doing this backwards for years. write code, write tests that match the code, realize six months later that both the code and tests were implementing the wrong behavior. but if you have a machine-readable contract (openapi, json schema, whatever), at least you can verify one dimension automatically

ngl this is why i'm skeptical of "AI will write all the code" takes. without formal specs, you're just getting really confident garbage that happens to pass its own tests. which tbh describes a lot of human-written code too lol

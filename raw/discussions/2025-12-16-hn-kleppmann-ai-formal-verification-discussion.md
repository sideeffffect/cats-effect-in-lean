# HN: AI will make formal verification go mainstream (Kleppmann) — selected comments

> Source: https://news.ycombinator.com/item?id=46294574
> Collected: 2026-11-10
> Published: 2025-12-16

827 points, 434 comments. Selected substantive comments. Verbatim. [...omitted: remaining comments...]

### simonw — 2025-12-16 (https://news.ycombinator.com/item?id=46294858; parent 46294574)

I'm convinced now that the key to getting useful results out of coding agents (Claude Code, Codex CLI etc) is having good mechanisms in place to help those agents exercise and validate the code they are writing.

At the most basic level this means making sure they can run commands to execute the code - easiest with languages like Python, with HTML+JavaScript you need to remind them that Playwright exists and they should use it.

The next step up from that is a good automated test suite.

Then we get into quality of code/life improvement tools - automatic code formatters, linters, fuzzing tools etc.

Debuggers are good too. These tend to be less coding-agent friendly due to them often having directly interactive interfaces, but agents can increasingly use them - and there are other options that are a better fit as well.

I'd put formal verification tools like the ones mentioned by Martin on this spectrum too. They're potentially a fantastic unlock for agents - they're effectively just niche programming languages, and models are really good at even niche languages these days.

If you're not finding any value in coding agents but you've also not invested in execution and automated testing environment features, that's probably why.

### roadside_picnic — 2025-12-16 (https://news.ycombinator.com/item?id=46295780; parent 46294858)

I very much agree, and believe using languages with powerful types systems could be a big step in this direction. Most people's first experience with Haskell is "wow this is hard to write a program in, but when I do get it to compile, it works". If this works for human developers, it should also work for LLMs (especially if the human doesn't have to worry about the 'hard to write a program' part).

> The next step up from that is a good automated test suite.

And if we're going for a powerful type system, then we can really leverage the power of *property* tests which are currently *grossly* underused. Property tests are a perfect match for LLMs because they allow the human to create a small number of tests that cover a very wide surface of possible errors.

The "thinking in types" approach to software development in Haskell allows the human user to keep at a level of abstraction that still allows them to reason about critical parts of the program while not having to worry about the more tedious implementation parts.

Given how much interest there has been in using LLMs to improve Lean code for formal proofs in the math community, maybe there's a world where we make use of an even more powerful type systems than Haskell. If LLMs with the right language can help prove complex mathematical theorems, they it should certain be possible to write better software with them.

### yuppiemephisto — 2025-12-16 (https://news.ycombinator.com/item?id=46295284; parent 46294574)

I vibe code extremely extensively with Lean 4, enough to run out 2 claude code $200 accounts api limits every day for a week.

I added LSP support for images to get better feedback loops and opus was able to debug https://github.com/alok/LeanPlot. The entire library was vibe coded by older ai.

It also wrote https://github.com/alok/hexluthor (a hex color syntax highlighting extension that uses lean’s metaprogramming and lsp to show you what color a hex literal is) by using feedback and me saying “keep goign” (yes i misspelled it).

It has serious issues with slop and the limitations of small data, but the rate of progress is really really fast. Opus 4.5  and Gemini were a huge step change.

The language is also improving *very* fast. not as fast as AI.

The feedback loop is very real even for ordinary programming. The model really resists it though because it’s super hard, but again this is rapidly improving.

I started vibe coding Lean about 3 years ago and I’ve used Lean 3 (which was far worse). It’s my favorite language after churning through idk 30?

A big aspect of being successful with them is not being all or nothing with proofs. It’s very useful to write down properties as executable code and then just not prove them because they still have to type check and fit together and make sense. github.com/lecopivo/scilean is a good example (search “sorry_proof”).

There’s property testing with “plausible” as a nice 80/20 that can be upgraded to full proof at some point.

When the model gets to another jump in capacity, I predict it will emergently design better systems from the feedback needed to prove that they are correct in the first place. Formal Verification has a tendency like optimization to flow through the system in an anti-modular way and if you want to claw modularity back, you have to design it really really well. But ai gives a huge intellectual overhang. Why not let them put their capacity towards making better systems?

Even the documentation system for lean (verso) is (dependently!) typed.

Check out my Lean vibe codes at https://github.com/alok?tab=repositories&q=Lean&type=&language=&sort=

### pron — 2025-12-16 (https://news.ycombinator.com/item?id=46295648; parent 46294574)

> it’s not hard to extrapolate and imagine that process becoming fully automated in the next few years. And when that happens, it will totally change the economics of formal verification.

There is a problem with this argument similar to one made about imagining the future possibilities of vibe coding [1]: once we imagine AI to do this task, i.e. automatically prove software correct, we can just as easily imagine it to not have to do it (for *us*) in the first place. If AI can do the hardest things, those it is currently not very good at doing, there's no reason to *assume* it won't be able to do easier things/things it currently does better. In particular, we won't need it to verify our software for us, because there's no reason to believe that it won't be able to come up with what software we need better than us in the first place. It will come up with the idea, implement it, and then decide to what extent to verify it. Formal verification, or programming for that matter, will not become mainstream (as a human activity) but go extinct.

Indeed, it is far easier for humans to design and implement a proof assistant than it is to use one to verify a substantial computer program. A machine that will be able to effectively use a proof checker, will surely be able to come up with a novel proof checker on its own.

I agree it's not hard to extrapolate technological capabilities, but such extrapolation has a name: science fiction. Without a clear understanding of what makes things easier or harder for AI (in the near future), any prediction is based on arbitrary guesses that AI will be able to do X yet not Y. We can imagine any conceivable capability or limitation we like.  In science fiction we see technology that's both capable and limited in some rather arbitrary ways.

It's like trying to imagine what problems computers can and cannot efficiently solve before discovering the notion of compuational complexity classes.

[1]: https://news.ycombinator.com/item?id=46207505

### socketcluster — 2025-12-16 (https://news.ycombinator.com/item?id=46295924; parent 46295778)

Yes. I feel like people who are trying to push software verification have never worked on typical real-world software projects where the spec is like 100 pages long and still doesn't fully cover all the requirements and you still have to read between the lines and then requirements keep changing mid-way through the project... Implementing software to meet the spec takes a very long time and then you have to invest a lot of effort and deep thought to ensure that what you've produced fits within the spec so that the stakeholder will be satisfied. You need to be a mind-reader.

It's hard even for a human who understands the full business, social and political context to disambiguate the meaning and intent of the spec; to try to express it mathematically would be an absolute nightmare... and extremely unwise. You would literally need some kind of super intelligence... And the amount of stream-of-thought tokens which would have to be generated to arrive at a correct, consistent, unambiguous formal spec is probably going to cost more than just hiring top software engineers to build the thing with 100% test coverage of all main cases and edge cases.

Worst part is; after you do all the expensive work of formal verification; you end up proving the 'correctness' of a solution that the client doesn't want.

The refactoring required will invalidate the entire proof from the beginning. We haven't even figured out the optimal way to formally architect software that is resilient to requirement changes; in fact, the industry is REALLY BAD at this. Almost nobody is even thinking about it. I am, but I sometimes feel like I may be the only person in the world who cares about designing optimal architectures to minimize line count and refactoring diff size. We'd have to solve this problem first before we even think about formal verification of 'most software'.

Without a hypothetical super-intelligence which understands everything about the world; the risk of misinterpreting any given 'typical' requirement is almost 100%... And once we have such super-intelligence, we won't need formal verification because the super-intelligence will be able to code perfectly on the first attempt; no need to verify.

And then there's the fact that most software can tolerate bugs... If operationally important big tech software which literally has millions of concurrent users can tolerate bugs, then most software can tolerate bugs.

### infruset — 2025-12-17 (https://news.ycombinator.com/item?id=46296698; parent 46294574)

I was waiting for a post like this to hit the front page of Hacker News any day. Ever since Opus 4.5 and GPT 5.2 came out (mere weeks ago), I've been writing tens of thousands of lines of Lean 4 in a software engineering job and I feel like we are on the eve of a revolution. What used to take me 6 months of work when I was doing my PhD in Coq (now Rocq), now takes from a few hours to a few days. Whole programming languages can get formalized executable semantics in little time. Lean 4 already has a gigantic amount of libraries for math but also for computer science; I expect open source projects to sprout with formalizations of every language, protocol, standard, algorithm you can think of.

Even if you have never written formal proofs but are intrigued by them, try asking a coding agent to do some basic verification. You will not regret it.

Formal proof is not just about proving stuff, it's also about disproving stuff, by finding counterexamples. Once you have stated your property, you can let quickcheck/plausible attack it, possibly helped by a suitable generator which does not have to be random: it can be steered by an LLM as well.

Even further, I'm toying with the idea of including LLMs inside the formalization itself. There is an old and rich idea in the domain of formal proof, that of certificates: rather than proving that the algorithm that produces a result is correct, just compute a checkable certificate with untrusted code and verify it is correct. Checkable certificates can be produced by unverified programs, humans, and now LLMs. Properties, invariants, can all be "guessed" without harm by an LLM and would still have to pass a checker. We have truly entered an age of oracles. It's not halting-problem-oracle territory of course, but it sometimes feels pretty close for practical purposes. LLMs are already better at math than most of us and certainly than me, and so any problem I could plausibly solve on my own, they will do faster without my having to wonder if there is a subtle bug in the proof. I still need to look at the definitions and statements, of course, but my role has changed from finding to checking. Exploring the space of possible solutions is now mostly done better and faster by LLMs. And you can run as many in parallel as you can keep up with, in attention and in time (and money).

If anyone else is as excited about all this as I am, feel free to reach out in comments, I'd love to hear about people's projects !

### maxwells-daemon — 2025-12-17 (https://news.ycombinator.com/item?id=46298951; parent 46294574)

There are a couple of interesting benefits from the machine learning side that I think discussions of this kind often miss. (This has been my field of research for the last few years [1][2]; I bet my career on it because these ideas are so exciting to me!)

One is that modern formal systems like Lean are quite concise and flexible compared to what you're probably expecting. Lean provides the primitives to formalize all kinds of things, not just math or software. In fact, I really believe that basically _any_ question with a rigorous yes-or-no answer can have its semantics formalized into a kind of "theory". The proofs are often close to how an English proof might look, thanks to high-level tactics involving automation and the power of induction.

Another is that proof-checking solves what are (in my opinion) two of the biggest challenges in modern AI: reward specification and grounding. You can run your solver for a long time, and if it finds an answer, you can trust that without worrying about reward hacking or hallucination, even if the answer is much too complicated for you to understand. You can do RL for an unlimited time for the same reason. And Lean also gives you a 'grounded' model of the objects in your theory, so that the model can manipulate them directly.

In combination, these two properties are extremely powerful. Lean lets us specify an unhackable reward for an extremely diverse set of problems across math, science, and engineering, as well as a common environment to do RL in. It also lets us accept answers to questions without checking them ourselves, which "closes the loop" on tools which generate code or circuitry.

I plan to write a much more in-depth blog post on these ideas at some point, but for now I'm interested to see where the discussion here goes.

[1] https://leandojo.org/leandojo.html
[2] https://aristotle.harmonic.fun/

### GTP — 2025-12-17 (https://news.ycombinator.com/item?id=46300507; parent 46294574)

I doubt some of this article's claims.

> At present, a human with specialist expertise still has to guide the process, but it’s not hard to extrapolate and imagine that process becoming fully automated in the next few years.

We already had some software engineers here on HN explain that they don't make a large use of LLMs because the hard part of their job isn't to actually write the code, but to understand the requirements behind it. And formal verification is all about requirements.

> Reading and writing such formal specifications still requires expertise and careful thought. But writing the spec is vastly easier and quicker than writing the proof by hand, so this is progress.

Writing the spec is easier *once you are confident about having fully understood the requirements*, and here we get back to the above issue. Plus, it is already the case that you don't write the proof by hand, this is what the prover either assists you with or does in full.

> I find it exciting to think that we could just specify in a high-level, declarative way the properties that we want some piece of code to have, and then to vibe code the implementation along with a proof that it satisfies the specification.

And here is where I think problems will arise: moving from the high level specification to the formal one that is the one actually getting formally verified.

Of course, this would still be better than having no verification at all. But it is important to keep in mind that, with these additional levels of abstractions, you will likely end up with a weaker form of formal verification, so to speak. Maybe it is worth it to still verify some high assurance software "the old way" and leave this only for the cases where additional verification is nice to have but not a matter of life or death.

### newpavlov — 2025-12-17 (https://news.ycombinator.com/item?id=46302034; parent 46294574)

For all my skepticism towards using LLM in programming (I think that the current trajectory leads to slow degradation of the IT industry and massive loss of expertise in the following decades), LLM-based advanced proof assistants is the only bright spot for which I have high hopes.

Generation of proofs requires a lot of complex pattern matching, so it's a very good fit for LLMs (assuming sufficiently big datasets are available). And we can automatically verify LLM output, so hallucinations are not the problem. You still need proper engineers to construct and understand specifications (with or without LLM help), but it can significantly reduce development cost of high assurance software. LLMs also could help with explaining why a proof can not be generated.

But I think it would require a Rust-like breakthrough, not in the sense of developing the fundamental technology (after all, Rust is fairly conservative from the PLT point of view), but in the sense of making it accessible for a wider audience of programmers.

I also hope that we will get LLM-guided compilers which generate equivalency proofs as part of the compilation process. Personally, I find it surprising that the industry is able to function as well as it does on top of software like LLVM which feels like a giant with feet of clay with its numerous miscompilation bugs and human-written optimization heuristics which are applied to a somewhat vague abstract machine model. Just look how long it took to fix the  god damn noalias atrtibute! If not for Rust, it probably would've still been a bug ridden mess.

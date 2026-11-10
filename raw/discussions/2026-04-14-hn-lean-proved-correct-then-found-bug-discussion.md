# HN: Lean proved this program correct; then I found a bug — selected comments

> Source: https://news.ycombinator.com/item?id=47759709
> Collected: 2026-11-10
> Published: 2026-04-14

Story links to https://kirancodes.me/posts/log-who-watches-the-watchers.html (395 points, 177 comments). Selected substantive comments on spec completeness, trusted base, and trust in verification. Verbatim. [...omitted: remaining ~160 comments...]

### porcoda — 2026-04-14 (https://news.ycombinator.com/item?id=47759898; parent 47759709)

I’ve had similar experiences with code I’ve proven correct, although my issues were of the more common variety than the overflow issue - subtle spec bugs.  (I think the post mentions the denial of service issue as related to this: a spec gap)

If you have a spec that isn’t correct, you can certainly write code that conforms to that spec and write proofs to support it.  It just means you have verified a program that does something other than what you intended.  This is one of the harder parts of verification: clearly expressing your intention as a human.  As programs get more complex these get harder to write, which means it isn’t uncommon to have lean or rocq proofs for everything only to later find “nope, it has a bug that ultimately traces back to a subtle specification defect.”  Once you’ve gone through this a few times you quickly realize that tools like lean and rocq are tricky to use effectively.

I kinda worry that the “proof assistants will fix ai correctness” will lead to a false sense of assurance if the specs that capture human intention don’t get scrutinized closely.  Otherwise we’ll likely have lots of proofs for code that isn’t the code the humans actually intended due to spec flaws.

### jmalicki — 2026-04-14 (https://news.ycombinator.com/item?id=47760017; parent 47759898)

I have experience with similar things!

But that's not saying the proofs are an issue - usually the spec you can reasonably prove in lean or another prover, say TLA+ or Z3 depending on your kind of program - has to be overly simplified and have a lot of assumptions.

However, that is powerful.

It doesn't mean your program doesn't have bugs.

It means this big scary complicated algorithm you think works but are skeptical doesn't have bugs - so when you encounter one, you know the bug is elsewhere, and you start really looking at the boundaries of what could be misspecified, if the assumptions given to the prover are actually true, etc.

It eliminates the big scary thing everyone will think is the cause of the bug as the actual cause.

This has been insanely valuable to me lately.  It is also something I never really was able to do before the help of AI - vibe coding proofs about my programs is IMO one of the killer apps of AI, since there aren't a ton of great resources yet about how to do it well since it is rarely done.

### somat — 2026-04-14 (https://news.ycombinator.com/item?id=47760335; parent 47759898)

Whenever I read an article about formal verification systems there is always that nagging thought in the back of my head. Why can you trust your formal verification system to be bug free but you can't trust the program. should not the chance of bugs be about equal in both of them?

You have a program that does something and you write another program to prove it. What assurance do you have that one program has fewer bugs then the other? Why can one program have bugs but the other can't? How do you prove that you are proving the right thing? It all sort of ties into Heisenberg's uncertainty theorem. A system cannot be fully described from within that system.

Don't get me wrong, I think these are great systems doing great work. But I always feel there is something missing in the narrative.

I think a more practical view is that a program is already a sort of proof. there is a something to be solved and the program provides a mechanism to prove it. but this proof may be and probably is incorrect, as bugs are fixed it gets more and more correct. A powerful but time consuming tool to try and force correctness is to build the machine twice using different mechanisms. Then mismatched output indicates something is wrong with one of them. and your job as an engineer is to figure out which one. This is what formal verification brings to the table. The second mechanism.

### majormajor — 2026-04-14 (https://news.ycombinator.com/item?id=47760520; parent 47760335)

> Whenever I read an article about formal verification systems there is always that nagging thought in the back of my head. Why can you trust your formal verification system to be bug free but you can't trust the program. should not the chance of bugs be about equal in both of them?

A bug in the formal verification tool could be potentially noticed by any user of that formal verification tool. (And indirectly by any of their users noticing a bug about which they say "huh, I thought the tool told me that was impossible.")

A bug in your program can only be potentially noticed by you and your users.

There are also entirely categories of bugs that may not be relevant. For instance, if I'm trying to prove correctness of a distributed concurrent system and I use a model+verifier that verifies things in a sequential, non-concurrent way, then I don't have to worry about the prover having all the same sort of race conditions as my actual code.

But yeah, if you try to write your own prover to prove your own software, you could screw up either. But that's not what is being discussed here.

### andai — 2026-04-14 (https://news.ycombinator.com/item?id=47762332; parent 47759898)

Let me try wrap my head around this.

I notice two classes of bugs in my own programs:

- I meant the code to do X, but it does Y

- I meant the code to do X, and it does X, but X causes problems I didn't foresee

A proof assistant can help you prove the code does X, but it can't help you prove doing X doesn't cause problems you didn't foresee.

In other words, it can prove the soundness of the implementation, but not the design?

Is that right? Though I imagine if there are internal contradictions in the design, lean would catch those too.

So the issue would be "internally consistent yet incorrect designs"?

In the case of TFA, the issue was exhaustiveness, right? "What happens if..."

That sounds like a pretty important quality as far as security goes. Is there a way to make sure everything is actually verified?

I heard actually verifying everything is prohibitively expensive though, like it took 10-20 years to verify seL4 (10K LoC).

### ctmnt — 2026-04-14 (https://news.ycombinator.com/item?id=47760024; parent 47759709)

This article’s framing and title are odd. The author, in fact, found no bugs or errors in the proven code. She says so at the end of the article:

> The two bugs that were found both sat outside the boundary of what the proofs cover. The denial-of-service was a missing specification. The heap overflow was a deeper issue in the trusted computing base, the C++ runtime that the entire proof edifice assumes is correct.

Still an interesting and useful result to find a bug in the Lean runtime, but I’d argue that doesn’t justify the title. Or the claim that “the entire proof edifice” is somehow shaky.

It’s important to note that this is the Lean *runtime* that has a bug, not the Lean kernel, which is the part that actually does the verification (aka proving). [1] So it’s not even immediately clear what this bug would really apply to, since obviously no one’s running any compiled Lean code in any kind of production hot path.

[1] https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/

### gopiandcode — 2026-04-14 (https://news.ycombinator.com/item?id=47760076; parent 47760024)

Repeating myself, when we speak of bugs in a verified software system, I think it's fair to consider the entire binary a fair target.

If a buffer overflow causes the system to be exploited and all your bitcoins to be stolen, I don't think the fact that the bug being in the language runtime is going to be much consolation. Especially if the software you were running was advertised as formally verified as free of bugs.

Second, there was a bug in the code. Maybe not a functional correctness bug, but I, along with many and most end users, would consider a crashing program buggy. Maybe we just have different tastes or different standards on what we consider an acceptable level of software quality.

W.r.t people running Lean in production, you'd be surprised...

### dchftcs — 2026-04-14 (https://news.ycombinator.com/item?id=47762519; parent 47760024)

A missing specification in the proof of lean-zip, a lean component, is a real problem to the philosophy and practice of software verification.

To illustrate, let's say you want to verify a "Hello world" program. You'd think a verification involves checking that it outputs "Hello, world!".

However, if a contractor or AI hands you a binary, what do you need to verify? You will need to verify that it does exactly print "Hello, world!", no more, no less. It should write to stdout not stderr. It shouldn't somehow hold a lock on a system resource that it can't clean up. It cannot secretly install a root-kit. It cannot try to read your credentials and send it somewhere. So you will need to specify the proof to a sufficient level of detail to capture those potential deviations.

Broadly, with both bugs, you need to ask a question: does this bug actually invalidate my belief that the program is "good"? And here you are pulling up a fact that the bug isn't found in the Lean kernel, which makes an assumption that there's no side-effect that bleeds over the abstraction boundary between the runtime and the kernel that affects the  correctness of the proof; that safety guarantee is probably true 99.99% of the time - but if the bug causes a memory corruption, you'd be much less confident in that guarantee.

If you're really serious about verifying an unknown program, you will really think hard "what is missing from my spec"? And the answer will depend on things that are fuzzier than the Lean proof.

Now, pragmatically, there many ways a proof of correctness adds a lot of value. If you have the source code of a program, and you control the compiler, you can check the source code doesn't have weird imports ("why do I need kernel networking headers in this dumb calculator program?"), so the scope of the proof will be smaller, and you can write a small specification to prove it and the proof will be pretty convincing.

All in all, this is a toy problem that tells you : you can't verify what you don't know you should verify, and what you need to verify depends on the prior distribution of what the program is that you need to verify, so that conditional on the proof you have, the probability of correctness is sufficiently close to 1. There's a lesson to learn here, even if we deem Lean is still a good thing to use.

### Paracompact — 2026-04-14 (https://news.ycombinator.com/item?id=47760582; parent 47760305)

Formal methods practitioner here.

> That means proving the absence of bugs, and you cannot prove a negative. The best thing you can do is fail to find a bug, but that doesn't mean it isn't there.

You can conclusively (up my next point) prove a specific bug or class of bugs aren't there. But "entirely free of (all) bugs" is indeed a big misconception for what formal methods does.

> how do you know your formal verification is bug-free? Answer: you don't. Or if you try to formally verify your formal verification then you're just translating the problem to a new layer. It's just a chain of proofs that is always ultimately based on an unproven one, which invalidates the whole chain.

It's another misconception of formal methods to say that any result is established conclusively, without any caveats whatsoever. But then again neither is mathematics, or any other intellectual discipline. What formal methods does is reduce the surface area where mistakes could reasonably be expected to reside. Trusting the Rocq kernel, or a highly scrutinized model of computation and language semantics, is much easier than trusting the totality of random unannotated code residing in the foggiest depths of your average C compiler, for instance.

### akoboldfrying — 2026-04-14 (https://news.ycombinator.com/item?id=47760581; parent 47759709)

Nice work. Amusing that Lean's own standard library has a buffer overflow bug, which "leaked out" due to being exempted from the verification.

Regarding the DoS in the lean-zip application itself: I think this is a really neat example of the difficult problem of spec *completeness*, which is a subcase of the general problem (mentioned by porcoda in a sibling comment) of being sure that the spec is checking the right things. For a compression program, the natural, and I would also say *satisfyingly beautiful* thing to prove is that decomp(comp(x)) = x for all possible inputs x. It's tempting to think that at that point, "It's proven!" But of course the real world can call decomp() on something that has never been through comp() at all, and this simple, beautiful spec is completely silent on what will happen then.

### ajaystream — 2026-04-14 (https://news.ycombinator.com/item?id=47760799; parent 47759709)

The spec-completeness problem here is the same one that bites distributed systems verification: the proof holds inside an operating envelope (no adversarial inputs, trusted runtime, bounded sizes), and the interesting failures live at the boundary. TLA+ has the same property - you can prove liveness under a fairness assumption the deployment silently violates, and nothing in the proof tells you when reality drifted outside.

What I'd actually want from the tooling is a machine-checkable statement of the envelope itself, propagated as a runtime guard rather than a compile-time comment. Then "proof holds" and "we are still inside the proof's domain" are two separate, observable properties, and the unverified-parser / unverified-runtime cases stop being invisible.

### seanhunter — 2026-04-14 (https://news.ycombinator.com/item?id=47762307; parent 47759709)

This is very cool work but the author is labouring under a false premise about how axiomatic systems work:

> Every Lean proof assumes the runtime is correct.

No. Every valid Lean proof assumes that if the runtime/mathlib etc is correct, then it too is correct.

Tangentially also, most lean proofs are not dependent on whether or not the runtime has things like buffer overflows or denial of service against lean itself at all, because if I prove some result in Lean (without attacking the runtime) then a bug in the runtime doesn’t affect the validity of the result in general. It does mean however that it’s not ok to blindly trust a proof just because it only relies on standard axioms and has no “sorry”s. You also need to check that the proof doesn’t exploit lean itself.

# Formalizing Julia in Lean (and finding 400+ bugs in Base) — Julia Discourse thread (full)

> Source: https://discourse.julialang.org/t/formalizing-julia-in-lean-and-finding-400-bugs-in-base/140243
> Collected: 2026-11-10
> Published: 2026-10-25

Full thread (36 posts) retrieved via the Discourse JSON API, raw markdown of each post. Images are Discourse upload refs.

---
### #1 MilesCranmer (Miles Cranmer) — 2026-10-25


<div align="center">

# [Formalizing Julia in Lean](https://github.com/MilesCranmer/julia-in-lean)

</div>

Not sure how much people have been following the ongoing cybersecurity apocalypse, but one of the interesting things I've learned from it is how exactly teams have been finding exploits. Some of these exploits are found by  _formalizing_ software into [Lean 4](https://lean-lang.org/), and then attempting to prove (or refute) rigorously that certain properties are respected. This can identify problems that even the most heavy-handed prop-testing can fail to catch. Before AI coding agents, this would be a huge pain in the ass, because you literally need to write a formal math proof for every single property, but nowadays with the strong math performance of AI, it's actually possible to do this en masse for software.

I have taken a stab at modelling some of my own packages into Lean, and this has identified TONS of bugs that had gone undiscovered for a while (in DynamicExpressions.jl): 

<div align="center">

![image|519x500, 75%](upload://2gF2NzvE1IjvQY3MFVsoVejbXlL.jpeg) 

</div>

Some of which seem to be problematic correctness bugs that could have been encountered silently. Now, I should also mention that I try very hard to avoid bugs in the first place (this is actually a carefully written, heavily-tested, 100%-human-reviewed codebase, not some AI slop!!) - which I want to point out to emphasize just how powerful Lean formalization is for catching bugs.

The way this works is that each Julia function gets a Lean model, and each docstring promise turns into a theorem which the agents try to prove. When any proof fails, the counterexample is usually a bug, which then gets checked against real Julia.

I have now, also, taken a stab at doing this for Julia *itself* - formalizing the full source code in Lean. This has also been quite fruitful: so far this has found about 400 (!) bugs in Base. I have filed [75 of the ones I manually filtered](https://github.com/JuliaLang/julia/issues?q=is%3Aissue%20author%3AMilesCranmerBot): these are the ones I thought were worth a maintainer's time, after checking each against existing issues and PRs for duplicates. Again I should emphasise that this does not mean Base is buggy relative to most software, it just means that Lean formalization is a very powerful way to catch bugs!

<div align="center">

![image|690x293, 75%](upload://pPFYw0bpMuzzsm12UlbNpbMuFSp.png)

</div>
Anyways, I thought it might be useful for others to see how this all worked, and potentially use it themselves, so I put together a repository with a writeup, and all of the Lean code I used for these:

# https://github.com/MilesCranmer/julia-in-lean.

I discuss this more below.

---

## What one of these looks like

Here is a real issue, filed as [#64124](https://github.com/JuliaLang/julia/issues/64124). Julia reverses an ordinal range by rebuilding it with the negated step:

```julia
_reverse(r::OrdinalRange, ::Colon) = (:)(last(r), negate(step(r)), first(r))
```

The Lean version mirrors that line, with Julia's fixed-width integer arithmetic:

```lean
def reverse (r : Rng) : Jl Rng := do
  let st ← Num.negate (step r)
  colon3 (last r) st (first r)
```

The property, from the `reverse` docstring: reversing a range that Julia successfully constructed keeps the same number of elements.

```lean
def reverseCardinalityProp : Prop :=
  ∀ (a st b : Num) (r : Rng), stepRange a st b = .ok r →
    match reverse r with
    | .ok out => trueCount out = trueCount r
    | .error _ => False
```

This property can't be proven, because it is false. The counterexample the agent found is `Int8(0):typemin(Int8):typemin(Int8)`, which has two elements. Negating a step of `-128` wraps back around to `-128`, so the reversed range goes from `-128` "down" to `0`, which is empty:

```julia
julia> r = Int8(0):typemin(Int8):typemin(Int8)
0:-128:-128

julia> length(r), length(reverse(r))
(2, 0)
```

The same wraparound makes `sort` return an empty range for some inputs, since sorting a descending range calls `reverse`.

Many of the bugs look like that: an edge case at `typemin`, an empty collection, an unsigned type. (Some of which would be hard to run into in typical use). But some are nastier:

- [#64183](https://github.com/JuliaLang/julia/issues/64183): a miscompilation on master, where inference folds an `isa` check across loop iterations and a small loop returns the wrong answer. This one showed up because `Markdown.rst` started printing the wrong thing.
- [#64147](https://github.com/JuliaLang/julia/issues/64147): resizing `vec(M)` of a `BitArray` corrupts `M`, since the two share storage.
- [#64185](https://github.com/JuliaLang/julia/issues/64185): `@sprintf` of a large `BigFloat` after other output writes past the end of Printf's output buffer.
- [#64193](https://github.com/JuliaLang/julia/issues/64193): an artifact path lookup can reach outside the artifact directory.

## How it works

Each Julia function gets a Lean definition that follows the source line by line: same branches, same order of checks, same integer wraparound. Exceptions become values (`Except JlError α`, where `JlError` lists Julia's exception types). Then each property gets stated as a Lean `Prop` taken from a docstring, the manual, or an obvious invariant. Each property has to quantify over the _space_ of all inputs.

The main problem with letting agents do formal work is that they are good at producing things that look like proofs. So most of the setup checks them:

1. **Differential testing first.** Before proving anything, the Lean model is run on lots of inputs and compared against real Julia. For example, the integer core matched an exhaustive table of all 656,896 Int8/UInt8 cases, and the Float64 model matched on 236,954 operations. If the model disagrees with Julia, the model is wrong.
2. **An audit of the build.** The build fails unless every property is proven or refuted, each theorem has exactly the type of its property (or the negation), and no proof uses `sorry`, `native_decide`, or extra axioms. A separate check rejects statements that only test worked examples.
3. **A refutation only counts with a reproducer.** A Lean counterexample by itself is just a claim about the model. It only counts once a plain Julia script shows the same behavior on the real thing.
4. **Duplicate search.** Before anything is written up, the agent searches existing issues and PRs. A lot of what it finds is already known, for example [#58245](https://github.com/JuliaLang/julia/issues/58245).

Even with all these checks, the agents can cut corners. When I moved on to proving that every `@inbounds` and `unsafe_*` access in `base/` stays in bounds (1,152 sites), the first pass came back with 130 "proven" sites in under an hour. That seemed too fast... and indeed it was: a review against a fixed rubric found that 128 of those 130 proofs had just assumed the index was in bounds. The audit can't catch that, since the theorem is technically valid. So now every proof there has to pass that review too. (The memory-safety proofs are still unfinished.)

## Models and cost

Everything so far has cost about $5,000 in API-equivalent usage, mostly Claude Opus 5.5 and OpenAI's Daybreak Blue (via Codex). Regular models kept refusing parts of the task, since "find overflow bugs in this source code" trips their cybersecurity filter. Daybreak Blue is meant for authorized security work, so it is less likely to refuse it (you can sign up at https://chatgpt.com/cyber)

## Reporting

When I asked on Slack how to report these, the advice was one issue per bug rather than a single tracking issue, so that is what I do, and only for the bugs that are (1) new and (2) plausible to hit in real code. (A few people there also asked how I was finding them, which is why I wrote this up.)

I worked hard to avoid duplicates. The agent searches open and closed issues and PRs before writing anything up, and records every search. Before an issue goes up, the agent searches again, and I push back whenever something looks familiar. Many of the bugs are already known, some with a fix PR open, and I never post those. I read every issue before it goes up. The issues come from @MilesCranmerBot, which is also me (I split my GitHub activity by whether an AI wrote the text, so the provenance is easier to follow). And then any bug that might be exploitable goes to security@julialang.org instead.

All of the bugs are in the repo, including the ones I didn't post, as YAML files with a priority, the reproducer, and the output on Julia 1.13.2 and master: https://github.com/MilesCranmer/julia-in-lean/tree/main/julia-base/bugs. Most of these have not yet been reported because they are too much of an edge-case. For example, stuff like: wrong exception types, hard-to-reach edge cases, docs that contradict the code. (A handful of security-relevant ones are held back for now.)

## Caveats

"Proven" means proven about the Lean model. But inevitably this model is also written by agents and checked against Julia by differential testing, not generated from Julia automatically, so a proof is only as good as the model. The bugs do not have this problem: every one has a reproducer on real Julia. Coverage is partial: parts of about 90 files in `base/` plus some stdlib packages. I have also started on the C runtime (the GC, etc.). It is only about 10% done, so it is not in the repo yet.

## Trying it on your own package

The repo has the DynamicExpressions.jl model as a template. I would recommend starting with one small central module, set up the differential test and the audit, and only then let agents prove things. Also, good to write down the ambiguous cases, since some "bugs" are intended behavior. When a fix is written, your agent can update the model to the new source: the same statement should now be provable, and proving it acts like a check.

Interested to hear what people think!

---
### #2 greatpet () — 2026-10-25

[quote="MilesCranmer, post:1, topic:140243"]
I have now, also, taken a stab at doing this for Julia *itself* - formalizing the full source code in Lean.

[/quote]

The full source code of Base or the full source of Julia including the compiler and C runtime?

---
### #3 MilesCranmer (Miles Cranmer) — 2026-10-25 reply to #2

This is the goal, yeah. The repo has parts of Base and some stdlibs; the rest I'm still working on locally. The C runtime part is still pretty early.

---
### #4 dcelisgarza (Daniel Celis Garza) — 2026-10-25

This is amazing. I've been doing a clanker based correctness pass on my own package, PortfolioOptimisers.jl, myself. I think this is a good next step after finishing the pass and stabilising the library.

---
### #5 matthias314 (None) — 2026-10-25

Many abstract types in Julia don't have precise interface definitions. (For instance, [it's unclear](https://discourse.julialang.org/t/what-exactly-is-a-number/77331) what properties a `Number` has.) Without that, how can you prove anything about functions accepting such types?

---
### #6 MilesCranmer (Miles Cranmer) — 2026-10-25 reply to #5

The proofs tend to not be for abstract types, because, exactly as you say, they don't have precise interfaces a lot of the time.

Here's a more detailed explanation from the AI currently working on the formalization:

> 🤖 
> General proofs about abstract types aren't possible, and the project doesn't try. Nothing is stated about "every `Number`" or "every `AbstractArray`". Generic code shows up in one of two ways.
> 
> **1. Concrete types.** Most properties are about specific Base types: `Int8` through `UInt128`, `Float64`, `UnitRange{Int}`, `StepRange`, `Dict`, `String`, and so on. These types have fully known behaviour because their methods are defined in Base, down to the intrinsics. The Lean model mirrors those method bodies line by line, so a theorem about `length(::StepRange{Int8,Int8})` is a statement about real code. Most of the bugs found are of this kind, for example overflow near `typemin`/`typemax`, empty ranges, and wrong exception types.
> 
> **2. Generic functions under stated assumptions.** When a Base function calls user-defined methods, those methods become parameters of the Lean model, and the theorem names the properties it needs from them. For example, `isless` extended to `missing` (missing sorts last) is proven to be a strict weak order for any element type, under the hypothesis that the element type's own `isless` is one:
> 
> ```lean
> def IslessStrictWeak : Prop :=
>   ∀ (α : Type) (lt : α → α → Bool), StrictWeak lt → StrictWeak (islessM lt)
> ```
> 
> The hypothesis is the interface. If the documentation never states it, the theorem makes it explicit, and a user type that breaks it is outside the claim.
> 
> **Where the interface is vague.** Sometimes it isn't clear what a docstring promises, or a counterexample needs an input that may be outside the intended contract. In those cases the bug write-up records the doubt in a `maybe_intended` field instead of calling it a bug outright. A fair number of findings are of that kind, and they are kept separate from the clear wrong-result and crash reports.
> 
> So the proofs say nothing about the abstract interfaces themselves. They cover concrete Base code, or generic Base code relative to explicitly stated assumptions about the methods it calls.

A cool thing about lean is you can treat assumptions as arguments that you pass to a theorem or definition, so you might only prove a property under that assumption (a hypothesis).

For example, in point (2) above, `lt` is any ordering a user supplies. The theorem takes "lt is a strict weak order" as an *assumption* and proves that the missing-aware `isless` built on top of it is also one.

But note that this isn't pure math like Mathlib. Lean is a proof checker, so it can check statements about anything, including code. It's basically just checking "If I assume this thing, and this other thing, and the code looks like this, is this general property satisfied?"

Tangential but one of my students made an interactive game for learning Lean: https://leangame.autumnofautumn.com/. I find it helps get better intuition for how Lean proofs work.

---
### #7 foobar_lv2 () — 2026-10-26

Very cool! I am blown away at how well that worked!

So, for me the critical question would be: How does the formal modeling live aside the codebase, and evolve with it?

You spent ~$5k in tokens, and came back with a very impressive list of bugs. Presumably this approach also produces quite a number of false positives (the model was a little more ambitious than the code's intention, i.e. it flags a footgun as a bug; note that often, the collective of human authors don't have consensus on that either! Sometimes there is no objective truth on whether something is a bug) and false negatives (in order to make this work, there are quite a number of assumptions needed -- this is not "down to riscV formal model" a la https://www.anthropic.com/research/formal-verification or "down to ZFC" a la pure maths navier-stokes blowup).

Doing the same de-novo for every release does not scale very well. Something that can scale very well, and imo is the future of software engineering, is to have the formal models + proofs persistent, effectively as part of the code-base; such that e.g. a PR or downstream (i.e. julia Base-using code) can be cheaply checked.

That requires some machinery (if the codebase changes with some sequence of diffs, how can we "lift" the diffs to transport the models/proofs along that path?).

I think this also wants an additional semi-formal step in the middle: A more human-readable natual-language variant of the lean-model. Currently you go "vague docstring / developer intentions" <-> "formal model"; I think it is more helpful to go "vague docstring / developer intentions" <-> "extended docstring that reduces ambiguities" <-> "formal model".

That splits the path into "infer / clarify intention of the code" and "formally model the clarified intentions"; both steps are AI produced / AI-assisted, but both have very different required skillsets, and the "clarify intentions of the code" thing is easier to discuss between humans if it's not completely formalized lean.

"What are the intentions of this code? What invariants is it intended to require and guarantee?" is a question of social consensus; can't argue with a root-shell, but oh boy can you argue whether this is a fault in the stdlib or whether people are holding the stdlib wrong!

This consensus-building is expensive in a different way than $5k in tokens, so it should result in some source-controlled artifact (semi-formal model) that becomes part of the julia codebase.

A pre-LLM example is the use of clang-analyzer to establish certain invariants in the julia runtime.

---
### #8 jakobnissen (Jakob Nybo Andersen) — 2026-10-26

This is absolutely fantastic! This initiative will hopefully fix a lot of bugs up front and save a lot of user frustration.

I wonder if it'll also lead to renewed interest in specifying documentation more precisely and carefully. As you say, this technique can't really be used with abstract types because they promise nothing. I think that implies we should consider more carefully what we promise. After all, an interface with no promises has no bugs, but it's also completely useless.

Relatedly, I find it reassuring that AI agents rely so much on tools. The rise of AI agents has led to some defeatism in software engineering, where people begin to question if building tools have any value, if AI agents can just build whatever bridge they need as they are crossing it. For example, why does Julia the language matter if agents can just code in Rust? I think we're increasingly seeing that agents, too, need good tools.

---
### #9 woclass (Chengyu Han) — 2026-10-26 reply to #7

[quote="foobar_lv2, post:7, topic:140243"]
How does the formal modeling live aside the codebase, and evolve with it?
[/quote]

I think keeping specs alongside the code, and using external tools to verify a well-defined subset of the language, might be the most practical approach for existing languages. 

We would need two tools:

- A package/stdlib for writing contracts next to the code, with clear explanations of the intended behavior.
- A tool that translates Julia source or IR, together with those contracts, into a framework such as [Why3](https://why3.org/) or [Strata](https://github.com/strata-org/Strata) (built in Lean 4).

Then code and specs could evolve together.

This approach already has precedents:
- [Creusot](https://github.com/creusot-rs/creusot/blob/master/ARCHITECTURE.md) puts contracts in Rust code and checks them through Why3.
- [Stainless](https://epfl-lara.github.io/stainless/verification.html) checks annotated Scala code. 
- SPARK follows the same broad approach for Ada.

So keeping specs with the code and using a separate verifier is already an established approach.

---
### #10 MilesCranmer (Miles Cranmer) — 2026-10-26 reply to #9

[quote="foobar_lv2, post:7, topic:140243"]
How does the formal modeling live aside the codebase, and evolve with it?
[/quote]

Similar to what @woclass suggested, one idea I've been thinking about for my own packages is to keep a `test/lean/` folder that attempts to mirror the source. Any PR that changes the Julia code would also need a coding agent to update the matching Lean models.

Review would then consist of:
1. Codex/Claude automatic reviews checking that the Lean changes track the Julia changes, and that claimed properties are actually proven.
    * In some ways this is analogous to checking that test code actually checks a desired behavior.
2. CI running `cd test/lean && lake build` to check that all proofs are valid, plus the differential tests against real Julia.

This wouldn't guarantee correctness, because of course the Lean could just be wrong, but I think it would help improve it on average.

---
### #11 ianshmean (Ian Butterworth) — 2026-10-26

In terms of prioritizing fixes, it might be interesting to point claude at the pkgeval data in https://perf.julialang.org/llms.txt which can be ranked by package popularity (downloads), to see if any of the bugs came up in popular packages (pkgeval pass rate is currently 55% in the ecosystem).

---
### #12 dcelisgarza (Daniel Celis Garza) — 2026-10-26

In the vein of the other comments, does the formalising necessarily need an agent, or is there a world in which we can make a transpiler for the source code? And perhaps when it comes to docstrings implementing a set of structured standards that the same transpiler can also translate? Even just having a code transpiler alone would probably be extremely helpful.

---
### #13 MilesCranmer (Miles Cranmer) — 2026-10-26 reply to #12

So "formalization" is actually three things: (1) modelling Julia in Lean, (2) stating what properties it needs to satisfy, and (3) proving it does indeed satisfy those properties.

(1) is where you could imagine some automatic translation (although this would still be very hard, and you would still need to model external C libraries separately)
(2) is like writing tests at scale, based on natural language descriptions of properties.
(3) is the really expensive part, and this is completely impractical without coding agents. You're essentially writing an entire _formal_ mathematical proof of a complex property.

For example, here's `mod` on unsigned integers in `base/int.jl`:

```julia
mod(x::T, y::T) where {T<:Unsigned} = rem(x, y)
rem(x::T, y::T) where {T<:BitUnsigned64} = checked_urem_int(x, y)
```

(1) The model: Lean can't use Julia's types directly, so in the following code we write a Julia type `T` as an ordinary Lean value `t`. This can represent one of the ten machine integer types (`Int8`, ..., `UInt128`) we've defined. A `JInt t` is a value of type `T`, stored as an integer between `t.min` and `t.max` (Julia's `typemin(T)` and `typemax(T)`), and `wrap t` is two's-complement wraparound into that range. `checked_urem_int` throws `DivideError` on zero, otherwise returns the truncated remainder - we inline this logic and port to Lean:

```lean
def remInt (a b : JInt t) : Jl (JInt t) :=
  if b.val = 0 then .error .divideError else .ok (wrap t (a.val.tmod b.val))

def mod (a b : JInt t) : Jl (JInt t) :=
  if t.signed then
    if b.val = -1 then pure (lit t 0)
    else do
      let d ← fld a b
      pure (a - d * b)
  else remInt a b
```

(2) Then, the property: the `mod` docstring says the result is `x - y*fld(x,y)` computed without intermediate rounding, with the same sign as `y` and magnitude less than `abs(y)`. For every unsigned width and every nonzero divisor:

```lean
def UnsignedModuloBounds : Prop := ∀ t : IntTy, t.signed = false →
  ∀ a b : JInt t, b.val ≠ 0 → ∀ r : JInt t,
  JInt.mod a b = .ok r →
  r.val = a.val % b.val ∧ 0 ≤ r.val ∧ r.val < b.val
```

(3) Then we actually have to prove the thing. This is where it starts requiring some AI firepower:

```lean
theorem unsignedModuloBounds : UnsignedModuloBounds := by
  intro t ht a b hb r hr
  have ha : 0 ≤ a.val := by simpa [IntTy.min, ht] using a.property.1
  have hbpos : 0 < b.val := by
    have := b.property.1
    simp [IntTy.min, ht] at this
    omega
  have hlo := Int.emod_nonneg a.val hb
  have hhi := Int.emod_lt_of_pos a.val hbpos
  have hrange : t.min ≤ a.val % b.val ∧ a.val % b.val ≤ t.max := by
    have := b.property.2
    simp [IntTy.min, ht]
    omega
  have hw := wrapInt_of_inRange t (a.val % b.val) hrange
  simp [JInt.mod, ht, JInt.remInt, hb, Int.tmod_eq_emod_of_nonneg ha] at hr
  cases hr
  exact ⟨hw, by simpa [JInt.wrap, hw] using hlo, by simpa [JInt.wrap, hw] using hhi⟩
```

Here's the AI's natural language version of this:

[quote]

1. Take any unsigned type $T$, any $a, b \in T$ with $b \neq 0$, and suppose $\mathrm{mod}(a, b)$
returns $r$.
2. Since $T$ is unsigned, $\mathrm{typemin}(T) = 0$, so $a \geq 0$ and $b \geq 0$. Combined with $b \neq 0$, this gives $b > 0$.
3. By the standard library, $0 \leq a \bmod b$ and $a \bmod b < b$.
4. Hence $0 \leq a \bmod b \leq b - 1 \leq \mathrm{typemax}(T)$, so $a \bmod b$ fits in $T$ and
wrapping it into $T$ leaves it unchanged.
5. Unfolding the model: for unsigned $T$, $\mathrm{mod}$ is $\mathrm{rem}$. Since $b \neq 0$, it does not throw. Since $a \geq 0$, the truncated remainder equals the floored remainder. So $r = \mathrm{wrap}_T(a \bmod b)$.
6. By step 4, $r = a \bmod b$, and by step 3, $0 \leq r < b$. $\blacksquare$
[/quote]

This one is short, and also relies on some earlier theorems: `Int.emod_nonneg` (`a % b ≥ 0`), `Int.emod_lt_of_pos` (`a % b < b` for `b > 0`) and `Int.tmod_eq_emod_of_nonneg` (truncated and floored remainder agree for `a ≥ 0`) from Lean's standard library, plus our own `wrapInt_of_inRange` (wraparound leaves an in-range value unchanged). Most proofs are much longer. The agents might try many proofs before they find one that works.



Also this is a task where you need higher-intelligence AIs for. For example, GPT-6.1 Luna struggles a lot in finding these proofs! I tried to use it to save money, but there were some things it simply could not prove, despite grinding on it for hours.

---
### #14 jar1 () — 2026-10-26

It might be useful to encode these properties in Supposition.jl afterward so they can become part of the Julia test suites.

---
### #15 MilesCranmer (Miles Cranmer) — 2026-10-27

Some of these new ones are wild. Not sure I would ever notice without formal verification:

```
julia> collect(LinRange(0.1, 0.1, 5))
5-element Vector{Float64}:
 0.1
 0.1
 0.1
 0.1
 0.1

julia> collect(LinRange(0.1, 0.1, 6))
6-element Vector{Float64}:
 0.1
 0.10000000000000002
 0.1
 0.1
 0.1
 0.1


julia> collect(LinRange(0.1, 0.1, 7))
7-element Vector{Float64}:
 0.1
 0.1
 0.1
 0.1
 0.1
 0.1
 0.1
```

(Issue: https://github.com/JuliaLang/julia/issues/64272)

Also, `tanh(::Float32)` appears to be [locally non-monotonic](https://github.com/JuliaLang/julia/issues/64225) at an ordinary Float32 value:

```
julia> x = 0.49214557f0;

julia> tanh(x) > tanh(nextfloat(x))
true
```

---
### #16 adienes (Andy Dienes) — 2026-10-27 reply to #15

[quote="MilesCranmer, post:15, topic:140243"]
Also, `tanh(::Float32)` appears to be [locally non-monotonic](https://github.com/JuliaLang/julia/issues/64225) at an ordinary Float32 value:
[/quote]

this one was less surprising to me; aren't they usually approximated via high degree polynomials (well known for being wiggly)

---
### #17 tim.holy (tim.holy) — 2026-10-27 reply to #15

That's quite funny. But FWIW `LinRange`'s contract is not to aim for floating-point exactness, it's to support "discrete segments" in abstract spaces, e.g.,

```
julia> v1, v2 = randn(3), randn(3)
([2.093487445396677, 1.9716034523694344, -0.7075986181423533], [-0.7049273213892698, 1.108660285173183, 0.7804466703146531])

julia> r = LinRange(v1, v2, 5)
5-element LinRange{Vector{Float64}, Int64}:
 [2.09349, 1.9716, -0.707599], [1.39388, 1.75587, -0.335587], [0.69428, 1.54013, 0.036424], [-0.00532363, 1.3244, 0.408435], [-0.704927, 1.10866, 0.780447]
```

Meaning that what matters is the the set of required computational operations, not floating-point exactness, and anything that "fixes" the latter at the expense of the former is a step backwards.

Floating-point exactness is the domain of `StepRangeLen`.

---
### #18 haakon (Haakon) — 2026-10-27

Very interesting stuff!

I’m curious with examples like `reverse`, naively it seems to me the fix for out of bounds or edge cases such as this would be a form of runtime bounds check? In many codes I imagine you’d never run into this in practice if you inspect the values that are actually passed to these functions. In fact, people do things like turning off bounds checking of vector indexing to make code run faster.

For some of these bugs, do you imagine there will be tradeoffs of the kind I allude to above? Bug is identified, but some additional work is required to work around it during runtime. Users may opt out of the additional work.

---
### #19 pitsianis (Nikos Pitsianis) — 2026-10-27 reply to #13

This is very interesting, but I’d expect semantic correspondence to be part of the story. A Lean proof establishes a property of the Lean model; how do you validate that the model captures Julia’s behavior? Finding a counterexample in Lean that also exposes a bug in Julia’s implementation is useful. But not finding one in Lean doesn’t prove Julia’s implementation has no such bugs. How is the connection between the model and the implementation established?

---
### #20 MilesCranmer (Miles Cranmer) — 2026-10-27 reply to #17

I might die on this hill, and I appreciate the exposition, but I don't think I could ever feel comfortable in a world where LinRange can experience quantum fluctuations...

```julia
julia> collect(LinRange(0.9, nextfloat(0.9), 10))
 0.9
 0.8999999999999999
 0.9000000000000001
 0.9000000000000001
 0.9
 0.9000000000000001
 0.9000000000000001
 0.9
 0.9000000000000001
 0.9000000000000001
```

Anyways I dug into this because I was too curious (and/or stubborn) to leave it alone... I do think it's fixable. The crux of the issue is how Julia computes the `lerpi` for interpolation:

```julia
function lerpi(j::Integer, d::Integer, a::T, b::T) where T
    t = j/d # ∈ [0,1]
    # compute approximately fma(t, b, -fma(t, a, a))
    return T((1-t)*a + t*b)
end
```

This turns out to be non-monotonic when `sign(a) == sign(b)` and the endpoints are close together, due to floating point quirks.

Luckily, this can be avoided. For example NumPy's `linspace` doesn't try to be extra precise either, but because it computes `start + i*step` instead, with the last element set to `stop`, it doesn't have this problem:

```python
>>> np.linspace(0.9, np.nextafter(0.9, 1), 10).tolist()
[0.9, 0.9, 0.9, 0.9, 0.9, 0.9000000000000001, 0.9000000000000001, 0.9000000000000001, 0.9000000000000001, 0.9000000000000001]
```

If you mend Julia's `lerpi` to do the same

```julia
function lerpi(j::Integer, d::Integer, a::T, b::T) where T<:AbstractFloat
    return ifelse(j == d, b, T(a + j*((b - a)/d)))
end
```
(which is fewer FLOPs, too!) then the same range steps up once, as expected:
```julia
julia> collect(LinRange(0.9, nextfloat(0.9), 10))
 0.9
 0.9
 0.9
 0.9
 0.9
 0.9000000000000001
 0.9000000000000001
 0.9000000000000001
 0.9000000000000001
 0.9000000000000001
```

So I don't think the fix needs `StepRangeLen`-level precision, just a slightly tweaked formula.

---
### #21 ParadaCarleton (Lime) — 2026-10-27

This is amazing, and thank you so much for all your hard work! How reusable is this code—is there a package or something for finding errors in Julia with Lean? That'd be awesome to see :)

---
### #22 Palli (Páll Haraldsson) — 2026-10-29 reply to #20

[quote="MilesCranmer, post:20, topic:140243"]
If you mend Julia’s `lerpi` to do the same .. (which is fewer FLOPs, too!) then the same range steps up once
[/quote]

Maybe file an PR for this change? I timed it the same:

```
julia> @btime collect(LinRange(0.9, nextfloat(0.9), 10))
  27.814 ns (2 allocations: 144 bytes)
```

[Before and after 2 allocations, both 144 bytes, but should either allocate? Might be about global scope.] Maybe slightly faster, or just noise, at least not slower.

[quote="tim.holy, post:17, topic:140243"]
Floating-point exactness is the domain of `StepRangeLen`
[/quote]

What do you mean? We should compete with `np.linspace` with `LinRange` (not with `StepRangeLen`?!). `StepRangeLen` gives a different result and also with, if you meanst something like that:
```
julia> @btime collect(StepRangeLen(0.9, nextfloat(0.9) - 0.9, 10))
  29.148 ns (2 allocations: 144 bytes)
```

---
### #23 j-fu (Jürgen Fuhrmann) — 2026-10-30

Just seen in the na-digest:

```
From: Diana Halikias diana.halikias@nyu.edu
Date: October 27, 2026
Subject: Lean + Numerical linear algebra working group

We are running a biweekly working group over Zoom to discuss integrating
Lean and NLA research. Topics include an NLA Lean library, incorporating Lean
in combination with AI into our research workflows, proof formalization
standards for the research community, and theoretical underpinnings of Lean.
Our next meeting is Tuesday, Nov 10 at 9:30am eastern time. If you are
interested in joining the email list, please contact diana.halikias@nyu.edu. You
can also view the slides from our first meeting on the website:
dihalikias.github.io/lean-nla.html

Diana Halikias and Haim Avron
```

---
### #24 MilesCranmer (Miles Cranmer) — 2026-11-03

For a real Halloween fright... look at `floor(x; sigdigits=1)` near a power of 10!  :face_with_peeking_eye:

![image|690x371](upload://8TGwefhSxcRQEHLVALJ6YUN5ppF.png)

Luckily it is fixable:

https://github.com/JuliaLang/julia/pull/64624

---
### #25 langestefan (Stefan de Lange) — 2026-11-03 reply to #24

![image|300x169](upload://d62m3LvF7ZZJmPoJzYPgo2PnYWp.png)

---
### #26 greatpet () — 2026-11-04

I'm more surprised that there are functions, other than printing and `log10`, that hard-code the base 10.

---
### #27 scelles (Sébastien Celles (Github @s-celles)) — 2026-11-05 reply to #24

Thanks @MilesCranmer for this very impressive work.
I tried a quite similar approach than yours with Golang compiler.
See https://github.com/s-celles/go-in-lean and https://forum.golangbridge.org/t/go-in-lean-exploring-go-correctness-with-ai-agents-lean-4-and-qemu/42766 and catched some miscompilation bugs there (much less than in Julia :sweat_smile:) but I'm probably not a good bug wizard.

---
### #28 draftman9 (Draftman9) — 2026-11-05

[quote="MilesCranmer, post:1, topic:140243"]
a review against a fixed rubric found that 128 of those 130 proofs had just assumed the index was in bounds. The audit can’t catch that, since the theorem is technically valid.
[/quote]

This reminds me of the recent critique of OpenAI's Navier–Stokes Lean formalization (https://arxiv.org/abs/2610.08144). Both cases seem to expose the same fundamental weakness in AI-assisted formal verification: **a formally valid proof does not necessarily establish the intended claim.**

Perhaps the real challenge is no longer just verifying the proof, but independently verifying that **AI is proving the right theorem in the first place.**

More fundamentally, this raises a question about AI's ability to judge what truly matters. Perhaps human judgment remains indispensable precisely because **we are the ones who decide what is worth proving.**

---
### #29 foobar_lv2 () — 2026-11-05 reply to #28

[quote="draftman9, post:28, topic:140243"]
Both cases seem to expose the same fundamental weakness in AI-assisted formal verification: **a formally valid proof does not necessarily establish the intended claim.**
[/quote]
This is not the issue with the linked Navier-Stokes comment: Humans have checked that the formal claims of the Lean-proof do indeed correspond to the intended natural-language claims we want; and the Lean-kernel has checked that the formal proof is indeed correct and does prove the formal claims.

Instead the issue is: The formal lean proof is not very accessible to humans. It is accompanied with a pretty bad slop natural language proof / writeup. This writeup is also not very accessible to humans (it's just bad writing). 

The linked paper shows that the situation is even worse: The natural language writeup of the proof is not just bad prose; it is incorrect and significantly diverges from the formal Lean proof.

In other words: "dear chatgpt; please solve Navier-Stokes millenium problem. Make no mistakes.", "sure, here you go. No mistakes: Checked in lean", "reading the lean is too hard for me. Please ELIH (explain like I'm human)", "sure, there you go" -- and the explanation is not just hard to read, it is objectively wrong, both in that it does not explain the specific lean proof, and that the explanation does not correspond to any valid proof at all.

@MilesCranmer 's approach does have the issue you're alluding to: We cannot economically check that the formal claims in the lean proof correspond to the natural language claims.

For example https://www.anthropic.com/research/formal-verification does not have that problem: Anthropic has carefully chosen to start with claims where the correspondence of "formal lean claim" and "natural language claim" is economical to check by human labor.

I don't think that the "humans cannot economically verify the connection between formal claim and natural language claim" is catastrophic. The other issue -- we actually observe something between mistake and bald-faced lie when "de-formalizing" a proof -- is imo much worse.

(autoformalization is awesome -- it's RLVR, i.e. has verifiable rewards. Deformalization has no verifiable rewards, which makes it fundamentally harder. We can expect that it will forever lag behind autoformalization)

---
### #30 Tarny_GG_Channie () — 2026-11-05

One of the longstanding critiques of Julia is that it lacks correctness because Julia doesn't have a strong static typing and relies on dispatch that exposes a lot of surface to subtle bugs. Well, it seems that the solution is to literally brute-force it with AI agents. 

Welp, I guess compute can solve a lot of problems.

---
### #31 jakobnissen (Jakob Nybo Andersen) — 2026-11-05 reply to #30

I absolutely disagree with that. The lesson from this Lean exercise is that strong semantics and programmatically checkable interfaces finds bugs.
That is, Miles didn't just throw agents at Julia, tasked with finding bugs. He had the agents leverage another language with stronger semantics than Julia in order to find this.

---
### #32 Tarny_GG_Channie () — 2026-11-06 reply to #31

I mean... programmatically checkable interface designs are often proposed in Julia, but they often end up not working well enough because Julia is reliant on a permissive system. Even errors like "undefined variables" or even "no such thing exists" are only catchable runtime error and not something Julia will refuse to compile. When it does work well enough for one class of problem, it still could break generics (or even things like dual number used in autograd) and so on if the check was too conservative. Lean avoids this issue because anything that can be formally proven can be made correct. A standard static analysis tool doesn't have that resource.

---
### #33 okartal (Önder Kartal) — 2026-11-06 reply to #31

But Lean, ROCQ (or TLA+) are not programming languages "with stronger semantics", they fall into a different category - they sit above the code and are only used for formal specification and model checking, not for running code AFAIK. Maybe there is a restricted subset of Julia that can be combined with formal verification (see [Can LLMs Enable Verification in Mainstream Programming?](https://arxiv.org/pdf/2503.14183v1)) or bake formal verification into the compiler, see [CompCert - Main page](https://compcert.org/).

---
### #34 Tarny_GG_Channie () — 2026-11-06 reply to #33

I think one of the issues is that formalizing and checking is undecidable in general, which is why type checkers have to be conservative or filled with proof/annotation that programmers don't like. LLM changes this dynamic by putting the burden of proof out of programmers' hands.

---
### #35 mkitti (Mark Kittisopikul) — 2026-11-09

David Andrews and Chao Zhang tried formalize Python in Lean and also found 400+ bugs.

> AI agents wrote 613,318 lines of Lean that copy Python's internals line by line, tested every piece against the real Python, had a computer check every proof, and turned up 418 bug reports in Python along the way.

https://broyojo.com/python-formalization/

---
### #36 ianshmean (Ian Butterworth) — 2026-11-10 reply to #35

[quote="mkitti, post:35, topic:140243"]
https://broyojo.com/python-formalization/
[/quote]


> The closest project is **julia-in-lean**, which did this for the Julia language and directly inspired this one

Pretty neat. Nice one @MilesCranmer

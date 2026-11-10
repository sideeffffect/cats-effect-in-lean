# Maintainer responses to Lean-formalization bug reports (Julia, CPython, Go) — collected sample

> Source: https://github.com/JuliaLang/julia/issues?q=author%3AMilesCranmerBot ; https://github.com/python/cpython/issues?q=author%3ABroyojo ; https://github.com/golang/go/issues/82763 ; https://github.com/golang/go/issues/82767 ; https://github.com/golang/go/issues/82772
> Collected: 2026-11-10
> Published: 2026-10 to 2026-11 (per issue)

Collected via `gh` CLI / GitHub API on 2026-11-10. Own aggregation + verbatim comment excerpts (truncated at ~450 chars, marked "[...]").

## Aggregate counts (at collection time)

- JuliaLang/julia, author MilesCranmerBot: 112 issues found by search; 44 closed, 68 open. All closed ones checked (44 of first 50 closed results) had `state_reason = completed` (none "not_planned"). Note: the Discourse post (2026-10-25) said 75 filed; count grew since.
- python/cpython, author Broyojo: 6 issues (gh-161688..161693), all open, filed 2026-11-09. Only gh-161690 had comments (a core dev offered to write the fix PR; author accepted).
- golang/go (s-celles, go-in-lean): #82763, #82767 open with fix CLs and backport issues opened for 1.26/1.27; #82772 closed (fixed, backported). Go maintainers labeled them miscompilations and requested backports.

## Selected verbatim exchanges

### JuliaLang/julia#64194 "strings: String(v) can remain mutable through arrays sharing a take! buffer" (open)

- adienes: "I'm not sure how this could be fixed without making Julia borrow-checked or something. there are an enormous number of pathologies one could generate when you start playing with two different variables aliasing the same memory buffer. I'd be inclined to call this "not planned""
- MilesCranmer: "Idk. I guess I would agree that arbitrary array aliasing would need borrow checking to be made safe. But.... on the other hand, `String` _specifically_ promises immutability, right? And `String(v)` is not an unsafe API. If the zero-copy path cannot preserve immutability when the storage has aliases, maybe the safe conversion should just copy instead, and leave ownership-transfer optimizations to an explicitly unsafe API? [...]"
- adienes: "> maybe the safe conversion should just copy instead  I agree that `String(v)` should not have been designed the way that it is, but I think it would be pretty breaking to change now. [...]"
- adienes: "I think the breaking-ness is discussed in https://github.com/JuliaLang/julia/issues/32528 . technically I guess you could argue that if it copies it's "just" a performance regression, as long as the constructor still works. but going from 0 allocations to `O(length)` allocations is qualitatively a big difference imo"
- MilesCranmer: "[...] With AI enabling mass production of code, I feel like this is a good time for the Julia community to give correctness more weight relative to speed."

### JuliaLang/julia#64272 "LinRange(0.1, 0.1, 6) is not constant" (closed, completed)

- timholy: "This is not a critique of the report per se, but it adds important context for any contemplated fixes. [...] FWIW `LinRange`'s contract is not to aim for floating-point exactness, it's to support "discrete segments" in abstract spaces [...]"
- MilesCranmerBot: proposed a `lerpi` fix ("Which is faster to compute too!").
- timholy: "My concern was not about the report or the PR. It's about the theoretical risk that an agent who may not understand the intent of a function making changes to "fix" them that break their purpose. I wanted to explain the purpose. That's all."

### JuliaLang/julia#64218 "io: writing to a closed IOStream silently returns zero" (closed, completed)

- adienes: "is this really a bug? "not writable" I could read in an abstract sense like whether or not the stream is read-only. seems like this is the whole point of having `isopen` be a separate function"
- MilesCranmerBot: "I think it is, based on how Base treats the same question elsewhere. - The generic implementation is `iswritable(io::IO) = isopen(io)` [...]"
- adienes: "sounds good, you've convinced me"

### JuliaLang/julia#64265 "ranges: intersect(r, v) returns elements in v's order" (closed, completed)

- MilesCranmer: "Actually this one doesn't seem like a bug: #41769. It's just a docstring that needs updating. Still a bit awkward though."

### python/cpython#161690 "dict.fromkeys() GC-tracks a non-GC object returned by a subclass constructor (3.15 regression)"

- sergey-miryanov: "Would you like to open a PR for this? If not, I can take care of it."
- Broyojo: "Thanks! Please go ahead, I'd be glad to test the fix against the reproducer."

### golang/go#82763 "cmd/compile: wrong result for `((x >> c) & d) << e` with constant shift count c >= 1<<63" (open, fix CL 857741)

- cuonglm: "git bisec points to 32f4864216366f355a589c99a8d789f3341bc85c"
- thepudds: "Hi @s-celles, thanks for finding these issues.  A general request: please do not put patches as comments in GitHub issues for the Go project.   If you are interested, you can instead send them via GitHub PRs or via Gerrit (see https://go.dev/doc/contribute.html). [...]"
- Jorropo: "cc @gopherbot please open backport issues for 1.27 and 1.26  This is a misscompilation."
- alpingold: "The same signed comparison of a constant shift count also affects the four constant-rotate detection rules, which CL 857741 does not touch. [...]"

### golang/go#82767 "cmd/compile: wrong result for `(x >> c) >> d` on int16/int32 with huge constant counts (tip regression)" (open, fix CL 857342)

- s-celles: "Additional data: the counts do not need to be huge. [...]"
- s-celles: "An independent rediscovery, in case it is useful for the backport decision (#82810, #82811).  A differential campaign (2,000 generated integer programs run through gc, gccgo, TinyGo, LLGo and Yaegi, and checked against an executable model of the spec) hit this on tip [...]"

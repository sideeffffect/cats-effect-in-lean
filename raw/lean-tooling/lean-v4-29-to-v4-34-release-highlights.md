# Lean 4.29–4.34 release notes: highlights excerpts

> Source: https://lean-lang.org/doc/reference/latest/releases/v4.29.0/ (and v4.30.0 … v4.34.0)
> Collected: 2026-11-10
> Published: 2026 (see each section header for release date)


---
## Source: https://lean-lang.org/doc/reference/latest/releases/v4.34.0/
# Lean 4.34.0 (2026-09-14)🔗

For this release, 159 changes landed.
In addition to the 55 feature additions
and 63 fixes listed below,
there were 5 refactoring changes,
5 documentation improvements,
6 performance improvements,
2 improvements to the test suite,
and 23 other changes.

## Highlights🔗

Lean 4.34.0 focuses on the kernel: three soundness issues, found with AI adversarial testing, have been analyzed and fixed, and a series of additional defensive checks have been implemented for further reinforcement. In the automation side, `bv_decide` gets integrated with `sym` and `grind` interactive modes, while being ported to the `SymM` preprocessor that makes it up to six times faster. Work has continued on the floating-point API after `Float` and `Float32` models being introduced in 4.33.0; linters can now carry state across commands and attach code actions to their warnings, and Lake improves its linting, caching, and error reporting.

`vcgen` has also undergone significant development as part of a major release scheduled for v4.35.0.

This highlights section was contributed by Juanjo Madrigal.

### Kernel Soundness and Hardening🔗

Continuing the kernel work of v4.33.0, this release closes three routes to a proof of `False` — two in the kernel proper and one in the runtime's reference counting — and adds a round of defensive checks on top.
All three were reported by Daniel Selsam (OpenAI) using their internal models, and all three need a deliberately constructed input rather than ordinary source code: they matter when checking proofs that arrive from an untrusted source, not for a development that only elaborates its own code.

- 
#14806 makes `is_def_eq` caching order-independent.
The kernel cached successful queries in a union-find structure; since the implemented test is sound but incomplete, and therefore not transitive, the transitive closure that union-find computes made a query's answer depend on which queries had been asked before.
A crafted input used this to build a recursor whose type and computation rule disagreed, and derive `False`.
The union-find is replaced by a plain cache keyed on the query pair, so the answer is again a function of the two arguments.
An OpenAI agent went on to produce two distinct exploits from the issue; both are caught by `nanoda` and by the new `lean-inductive-models`.

- 
#14807 makes the kernel's `is_prop` require a sort.
When a term's inferred type was stuck rather than reducible to a sort, `is_prop` answered `false` instead of rejecting the term, which skipped the proof-irrelevance guard on projections and allowed a data field to be projected out of a value used as a `Prop`.
The bogus proof was also accepted by `nanoda`; `lean4lean` is believed not to have the bug.
#14843 applies the same fix to a copy of the old check inlined in `inductive.h`.

- 
#14838 freezes objects whose 32-bit reference count overflows, following the sticky-counter approach used by Koka.
Forcing the counter to wrap corrupted the object's state, and on machines with at least 18GB of free RAM this could be turned into a use-after-free in the official kernel and extended into a proof of `False`.
Kernels not built on the Lean runtime were unaffected.

The rest of the section is hardening rather than bug fixing:

- 
#14808 type-checks the recursors the kernel generates for an inductive type, and checks that each computation rule is type-preserving rather than merely well-typed.
A minor premise that expects an induction hypothesis the rule does not supply reduces to an under-applied function, which is still well-typed but no longer has the recursor's result type — so checking that the right-hand side has some type would not catch it.
This is defense in depth: it rejects only declarations that were already malformed.

- 
#14582 makes the kernel reject inductive declarations in which a datatype being declared occurs applied to anything other than the declaration's parameters and universe levels.
The frontend already enforced this, so only declarations built with `addDecl` directly are affected.

- 
#14849 bounds the size of `Nat` numerals the kernel computes at 128 MB, so a compact proof can no longer direct it to evaluate a numeral of many gigabytes.
Workloads that legitimately need larger numerals can raise the limit with the `LEAN_NAT_MAX_SIZE` environment variable.

- 
#14833 makes Lean require GMP 6.3.0 or newer, since earlier versions contain bugs that can make Lean produce unsound results in corner cases.
Building against an older GMP now fails at configuration time; `-DUSE_GMP=OFF` (Lean's own bignum implementation) and `-DFORCE_GMP=ON` are the two escape hatches.

### `bv_decide` Is Faster and Cooperates with `grind`🔗

#### Bit-blasting Inside `grind =>`🔗

#14672 makes `bv_decide` available from within `sym =>` mode, and #14713 connects it to the `grind` state: the relevant equivalence classes are encoded into the SAT problem alongside the goal, as are facts learned by theory solvers and by E-matching.

opaque g : UInt8 → UInt8

example (a b d : UInt8) (h0 : d = a ||| b)
(h1 : g d &&& 0xC0 = 0) :
g (a ||| b) &&& 0x40 = 0 := by
grind =>
bv_decide

On its own, `bv_decide` abstracts `g d` and `g (a ||| b)` as two unrelated opaque variables and reports a spurious counterexample.
Inside `grind =>`, congruence closure has already merged them using `h0`, so the SAT problem it hands to the solver is the one that actually needs solving.

#### Choosing Which Types Get Analyzed🔗

By default `bv_decide` guesses which structures and enum inductives in the context might matter and tries to incorporate them.
#14681 adds a `types [...]` clause that names them explicitly and turns the automatic discovery off, which keeps preprocessing tractable on goals mentioning many types of which only a few are relevant:
`inductive Color where
| red | green | blue

@[ext] structure Pair where
x : BitVec 8
y : BitVec 8

example (a b : Pair) (c d : Color) (h1 : a = b) (h2 : c = d) :
a.x = b.x ∧ d = c := bya:Pairb:Pairc:Colord:Colorh1:a = bh2:c = d⊢ a.x = b.x ∧ d = c
bv_decide types [Pair, Color]All goals completed! 🐙
`
Pinning is a restriction rather than a hint: everything not listed is treated as an opaque variable, so naming the wrong type leaves the goal outside the supported fragment.
A type that is neither a non-recursive structure nor an enum inductive is rejected outright.
The clause is accepted by `bv_normalize`, `bv_decide?`, and `bv_check` as well, and inside `sym =>`.

Note the `@[ext]` above: `bv_decide` takes a structure equality apart through the structure's extensionality lemma, so a structure without one stays opaque whether or not it is listed.

#### A Faster Preprocessor🔗

#14215 ports `bv_decide`'s preprocessor to `SymM`, the rewriting engine shared with `grind` and `cbv`.
On large, rewriting-heavy problems this is a speedup of up to 6x, and substitution of embedded constraints becomes linear in the total size of the hypotheses.
Breaking change: `@[bv_normalize]` is now a `Sym.simp` set, which differs in pattern-matching power and in the shape it requires of a theorem, and `bv_normalize`'s proving power shifts slightly in both directions.

Smaller improvements round this out: #14683 teaches the embedded-constraints pass to read both `a = true` and `(!a) = true`, and #14460 extends ground evaluation to more `BitVec` operations.
Elsewhere in the same engine, #14425 lets `grind` discharge the side conditions of conditional `Sym.simp` theorems, and #14459 adds an option for `Sym.dsimp` to rewrite inside instances, which can make more ground terms syntactically equal.

`SymM` also collects a batch of correctness fixes: the matcher no longer unifies metavariables unsoundly when matching nonlinear patterns (#14404), `grind` no longer drops E-matching theorems from custom attributes (#14426) or misses a valid contradiction because the canonicalizer resynthesized an instance inside a skipped binder (#14439), and `lia`/`grind` no longer emit a proof the kernel rejects when an integer expression's structure differs from that of its polynomial representation (#13587).
Further fixes: #14401, #14405, #14424, #14428, #14444, #14664, #14691, #14694, #14709.

### Linters and Deprecation Warnings🔗

Two changes extend what a linter can do.
#14357 introduces stateful linters, which persist state across command elaboration and can read the state of other linters, in an early/late two-phase architecture registered from an `initialize` block.
#14402 lets linters produce code actions, so a linter warning can now carry a fix that is one click away in the editor.

Deprecation reporting, introduced in v4.31.0, got a round of polish.
#14478 moves option deprecation onto the `@[deprecated]` attribute, so a deprecated option warns both when it is used with `set_option` and when it is read from meta code:
`open Lean in
@[deprecated "use `demo.newOpt` instead" (since := "2026-08-21")]
register_option demo.oldOpt : Bool :=
{ defValue := true, descr := "an old option" }
``open Lean in
def readsOldOpt (o : Options) : Bool := ``demo.oldOpt` has been deprecated: use `demo.newOpt` instead`demo.oldOpt.get o
`
`demo.oldOpt` has been deprecated: use `demo.newOpt` instead

#14564 re-parses the header so that each deprecated-module warning points at the `import` that actually pulls that module in, instead of collapsing every one of them onto the start of the header, and #14533 silences deprecated-syntax warnings inside definitions that are themselves deprecated — the same rule that already applied to deprecated constants:
`syntax "oldThing" : term
macro_rules | `(oldThing) => `(42)
deprecated_syntax termOldThing "use `42` instead"
(since := "2026-08-21")
``def fresh : Nat := `syntax 'termOldThing' has been deprecated: use `42` instead

Note: This linter can be disabled with `set_option linter.deprecated.syntax false``oldThing
`
syntax 'termOldThing' has been deprecated: use `42` instead

Note: This linter can be disabled with `set_option linter.deprecated.syntax false`

A definition that is on its way out, though, is allowed to keep using the syntax that is on its way out with it, and stays quiet:
`@[deprecated "use `fresh` instead" (since := "2026-08-21")]
def stale : Nat := oldThing
`

### Lake🔗

#14622 adds a `--code-quality` mode to `lake lint` that emits builtin linter results as machine-readable JSON entries instead of human-readable diagnostics, each keyed by the linter's option name.
Text-linter warnings are aggregated per module and linter into a single entry holding the count; environment-linter findings are reported per flagged declaration.
The entries are data rather than failures, so `lake lint --code-quality` succeeds even when violations are found.
Two entries — one aggregated from a text linter, one from an environment linter (a fixture from Lake's own test suite) — look like this:

{"value":{"scalar":{"value":2}},
"source":{"module":{"name":"Violations"}},
"name":"linter.unusedVariables"}

{"value":{"scalar":{"value":1}},
"source":{"declaration":{"name":"fooDummyMarker",
"module":"Violations"}},
"name":"linter.dummyMarker"}

On the caching side, #14720 demotes cache failures during a build to `trace`-level messages, so a build run with `--wfail` or `--iofail` no longer fails because of the cache alone, and #14651 fixes several ways a failed artifact transfer could go unrecorded, abort a whole transfer batch, or leave a corrupted artifact behind.
#14724 adds `lake cache get --package`, which fetches the outputs of a specific package in the workspace rather than only the root.

Error reporting improves in three places: `error: Lean exited with code 1` is elided when `lean` has already printed the real diagnostics (#14629), a `lean_lib` root module with no source file reports the underlying file error instead of a vague bad-imports message (#14625), and `lake update <pkg>` now fails on a package name the manifest does not know instead of silently ignoring it (#14630).
Finally, #14723 makes `MACOSX_DEPLOYMENT_TARGET` configurable through the Lake API and includes it in build traces.

### Performance and Robustness🔗

#14520 fixes an exponential blowup in `instantiateMVars` on proof terms that repeatedly reference hypotheses introduced by `MVarId.assert`/`intro` — as `MVarId.note`, `replaceLocalDecl`, and `simp at h` do.
Lifting substituted values is now memoized and canonicalized across a whole pass, restoring linear behavior: the reproduction from #14329 went from exceeding 41GB to elaborating in about 1.2 seconds, and one Mathlib module dropped 26G instructions (-55%).

#14397 makes the `set_option ... in` tactic elaborate incrementally, so editing inside such a block reuses the results of the unchanged leading tactics instead of re-running the whole block.
For diagnosing where the time goes, #14386 adds `store_traces_as name in cmd`, which runs `cmd`, reports its trace as usual, and additionally keeps the trace tree in memory under `name`, together with `#postprocess_traces name post` for re-viewing that tree through any postprocessor.
Where `postprocess_traces` from v4.33.0 transformed a trace as it was produced, this separates producing from viewing — which matters when the command took a minute to run.

Two robustness fixes are worth knowing about: #14204 detects failures when flushing a module's `.olean`, so an exhausted disk no longer leaves a silently truncated file behind, and #14687 fixes a use-after-free in `String.Pos.Raw.extract` when it is called with gigantic slice limits.
#14717 fixes the same function's model/runtime mismatch and adds a fast path for `String.extract` when the positions are known to be valid.

On the FFI side, #14505 fixes segfaults caused by private imports of the `Lean` library by making each module's initializer call `lean_initialize` when it needs to.
The call to `lean_initialize_runtime_module` became implicit in the same cleanup, so users of Lean as an FFI library no longer need to call either function themselves.

[...omitted: rest of v4.34.0 notes (library highlights, breaking changes, per-PR lists)...]

---
## Source: https://lean-lang.org/doc/reference/latest/releases/v4.33.0/
# Lean 4.33.0 (2026-08-10)🔗

For this release, 208 changes landed.
In addition to the 53 feature additions,
and 50 fixes listed below,
there were 12 refactoring changes,
11 documentation improvements,
21 performance improvements,
6 improvements to the test suite,
and 55 other changes.

## Highlights🔗

Lean 4.33.0 concentrates on responsiveness and consolidation: the editor keeps more of your work while you type, `try?` can propose proofs on its own, `lia` and `grind` tactics are improved, and `Float` stops being an opaque type. Continuing the transparency work of v4.31.0, it also enables `backward.isDefEq.respectTransparency.types` by default — the change most likely to need attention when porting.

This highlights section was contributed by Juanjo Madrigal.

### A More Responsive Editor🔗

Several independent changes make interactive editing noticeably smoother:

- 
#11958 stops the elaborator from rerunning a tactic when only the whitespace following it changes. Pressing return after a tactic to prepare the next line no longer discards the progress made by everything after it.

- 
#13712 makes `exact?`, `apply?`, `rw?`, and `grind +locals` stop waiting for earlier theorems in the same file to finish kernel-checking. In an editor session this used to show up as `try?` and `exact?` appearing to hang near the top of long files.

- 
#14234 makes completion, hovers, and the interactive term goal see the open namespaces and options of a term-level `open … in` or `set_option … in` scope, rather than those of the enclosing command.

- 
#14296 restores go-to-definition and find-references on a `let mut` variable that is referenced after a `for` loop.

Diagnostics became more actionable as well. The `unusedVariables` linter now offers the underscore rename as an applicable hint (#14259):
`def constantly (`Variable name `n` is not explicitly referenced.

Hint: The binding can be removed (if unused) or named `_` (if used implicitly). Alternatively, prefix the name with `_` to silence this warning:
[apply] _n

Note: This linter can be disabled with `set_option linter.unusedVariables false``n : Nat) : Nat := 0
`
Variable name `n` is not explicitly referenced.

Hint: The binding can be removed (if unused) or named `_` (if used implicitly). Alternatively, prefix the name with `_` to silence this warning:
[apply] _n

Note: This linter can be disabled with `set_option linter.unusedVariables false`

And a new linter warns about an `open` that does not in fact open every namespace ending in the given name (#14325): inside `namespace A`, an `open B` stops reaching `_root_.B` as soon as an upstream `A.B` appears, which explains the otherwise puzzling `unknown identifier` errors that follow. Finally, #14196 clarifies the warnings around reducibility attributes.

### Automatic `try?` Suggestions🔗

#13830 lets `try?` run on its own where a proof is missing, gated by three options that default to off:

- 
`autoTry.onEmptyProof` — an empty `by`, an empty `· `, an empty `case h => `, and so on.

- 
`autoTry.onUnsolvedGoal` — like the above, but also fires on proofs that already contain tactics and left a goal open; there the suggestion is appended to what is already written.

- 
`autoTry.onSorry` — a `sorry`, which the suggestion replaces.
`set_option autoTry.onEmptyProof true in
example (a b : Nat) : a + b = b + a := `Try these:
[apply] simp +arith
[apply] simp +arith only
[apply] grind
[apply] grind only``unsolved goals
a b:Nat⊢ a + b = b + a`by
`
unsolved goals
a b:Nat⊢ a + b = b + a

Try these:
[apply] simp +arith
[apply] simp +arith only
[apply] grind
[apply] grind only

### Tactic Improvements🔗

`lia` ran with E-matching disabled, so it could not see definitional lemmas. #14098 gives it its own `@[lia]` set — far smaller than `@[grind]`, which stays disabled — and #14107 tags the `min`/`max` definitions, closing the most common case where `omega` could not simply be replaced by `lia`:
`example (a b : Nat) : min a b ≤ max a b := bya:Natb:Nat⊢ min a b ≤ max a b liaAll goals completed! 🐙
example (a b : Int) : max a b = max b a := bya:Intb:Int⊢ max a b = max b a liaAll goals completed! 🐙
`
`grind` gains propagators that evaluate `BitVec` operations on literals, including through equalities recorded in the e-graph (#14393):
`example {x : BitVec 64} (h : x = 0#64 + 42#64) :
BitVec.extractLsb' 63 32 x = 0#32 := byx:BitVec 64h:x = 0#64 + 42#64⊢ BitVec.extractLsb' 63 32 x = 0#32 grindAll goals completed! 🐙
`
It also collects a batch of correctness fixes:

- 
bitvector literals that were not normalized to the form `grind` expects could be treated as two distinct values, in one case yielding a proof the kernel rejects (#14371 / #14370 / #14379);

- 
constraints of the form `0 ∣ p` could send the search into a loop (#14373);

- 
the ring solver could lose information in rings without `NoNatZeroDivisors` (#14390);

- 
`SymM` term invariants that user simprocs could silently break are now detected and repaired (#14299).

A new `liaSteps` option bounds the search on hard linear integer arithmetic (#14392). Finally, the e-matching annotations on container operations were retuned to connect two theories only when both are already in the e-graph, instead of one dragging in the other. More information in #14177 / #14194 / #14192 / #14182 / #14178.

### `Float` Is No Longer Opaque🔗

`Float` and `Float32` were opaque types with no logical content. #14079 adds `Float.Model` and `Float32.Model`, validated against the native implementation on cases from Berkeley TestFloat, and #14091 redefines the types to wrap them, with arithmetic, comparison, and conversion delegating to the model. Compiled code is unaffected. This is deliberately not a full floating-point library — the point is to let a downstream one connect to `Float` so its theorems transport.

Two consequences are visible right away. #14180 adds a `DecidableEq` instance that compares bit patterns, which is not the IEEE 754 relation `==` implements. And #14110 rewrites `Float.ofScientific` so that it rounds correctly — it passes over five million tests of the `parse-number-fxx-test-data` suite, at the cost of a much slower fallback path — and now reduces in the kernel:
`def nan : Float := 0.0 / 0.0

/-- info: false -/
#guard_msgs in
#eval nan == nan

example : nan = nan := by⊢ nan = nan decideAll goals completed! 🐙
example : (0.0 : Float) ≠ -0.0 := by⊢ 0.0 ≠ -0.0 decideAll goals completed! 🐙
example : 0.1 + 0.2 != 0.3 := rfl
`
That instance also backs float literals as `match` patterns (#14181), so `0.0` and `-0.0` select different branches:
`def describe (x : Float) : String :=
match x with
| 0.0 => "zero" | -0.0 => "negative zero" | _ => "other"

/-- info: "negative zero" -/
#guard_msgs in
#eval describe (-0.0)
`

### Lake🔗

#14235 makes module archives (`.ltar`) content-stable: byte-identical module outputs now produce a byte-identical archive whatever the inputs, checkout path, or build machine, so an input-only change uploads no new bytes and identical outputs deduplicate across revisions on cache services. #13646 adds a `requiresModuleSystem` package option, warning when a file without a `module` header imports the package; `allowNonModules` opts out.

Two fixes retire a class of `compiled configuration is invalid; run with '-R' to reconfigure` failures: #14284 makes an interrupted configuration leave a valid trace behind, and #14285 reconfigures when the trace cannot be read at all. There are also new module facets for dependency and link information (#14300 / #14254), and `lake new`/`lake init` with the `exe` template no longer emits library files (#14366).

### Kernel soundness fixes and further improvements🔗

This release fixes bugs in the Lean kernel and improves its robustness. Some of the soundness bugs can only be exploited from a malicious meta program running in the same process (which is already known to be unsafe). Others survive the export format and affect proof checking via `comparator` too, unless external checkers like `nanoda` are used as well.

- 
PR #14498 guards against free variables in opaque values. Soundness bug, but not affecting users of `comparator`.

- 
PR #14577 typechecks arguments to phantom parameters of nesting inductives. Soundness bug, affecting users of `comparator`.

- 
PR #14607 adds more checking against free variables. Possible soundness issue, not affecting `comparator`.

- 
PR #14608 checks level parameters uniformity in recursive definitions. Not a known soundness issue, as it only affects declarations marked as `partial` or `unsafe`.

- 
PR #14609 fixes a soundness issue in the module system. Does not affect users of `comparator`.

- 
PR #14613 recognize level expressions that may normalize to `Prop`. Soundness bug, affecting users of `comparator`.

- 
PR #14615 adds more level normalization to the handling of inductives. Not a soundness bug.

- 
PR #14616 rejects names using `_nested` in the names, to prevent clashes with the kernel’s internal construction for nested inductives. Soundness bug, but not affecting users of `comparator`.

- 
PR #14621 adds more hardening to the handling of nested inductives.

- 
PR #14631 checks the name field of a projection expression when comparing them. This hardens the kernel.

- 
PR #14632 hardens the kernel by checking more invariants explicitly.

- 
PR #14633 hardens the kernel by checking types of local context declarations sooner.

Also see the Postmortem for Kernel Soundness Bug #14576.

[...omitted: rest of v4.33.0 notes (library highlights, breaking changes, per-PR lists)...]

---
## Source: https://lean-lang.org/doc/reference/latest/releases/v4.32.0/
# Lean 4.32.0 (2026-07-13)🔗

For this release, 102 changes landed.
In addition to the 35 feature additions,
and 20 fixes listed below,
there were 7 refactoring changes,
2 documentation improvements,
9 performance improvements,
2 improvements to the test suite,
and 27 other changes.

## Highlights🔗

Lean 4.32.0 makes the new `do` elaborator the default, expands `do` notation with the `do←` marker for effect forwarding, and brings notable performance improvements including a ~10% reduction in `import Mathlib` time. Lake's linting framework gains option-based control and module-level linters, and an experimental incremental-compilation mode lands behind CLI flags.

This highlights section was contributed by Juanjo Madrigal.

### New `do` Elaborator is Now the Default🔗

#13305 makes the new `do` elaborator (introduced as experimental in v4.31.0) the default by flipping `backward.do.legacy` to `false`. The legacy elaborator remains available via `set_option backward.do.legacy true`. #13912 and #13931 add significant new capabilities:

#### `do←` — Effect Forwarding🔗

#13931 introduces the `do← body` marker (ASCII `do<- body`), which lets ordinary continuation-taking wrappers like `withReader` or `Meta.withLocalDecl` participate in the surrounding `do` block's control flow. When `do← body` appears as the last argument of an application inside a `do` block, the body's `return`, `break`, `continue`, and `mut`-variable reassignments are forwarded out through the wrapper to the enclosing block. For instance, let
`def withLogging [Monad m] [MonadLiftT IO m] (act : m α) : m α := do
IO.print "log!"
act
`
Internal `do← body` can mutate external variables:
`def mutForward : IO Nat := do
let mut x := 0
withLogging (do← x := x + 1)
return x

/--
info: log!
---
info: 1
-/
#guard_msgs in
#eval mutForward
`
It can also trigger an early return:
`def retForward : IO Nat := do
let x <- withLogging (do← return 5)
IO.println "unreachable"
return x + 100

/--
info: log!
---
info: 5
-/
#guard_msgs in
#eval retForward
`
Or break an external loop (and the `do← body` can be executed multiple times):
`def brkForward : IO Nat := do
let mut total := 0
for i in [1, 2, 3, 4, 5] do
total := total + (← withLogging (do←
if i > 3 then break
pure i))
return total

/--
info: log!log!log!log!
---
info: 6
-/
#guard_msgs in
#eval brkForward
`
The syntax is reminiscent of a nested action `(← body)`, but unlike a nested action, `body` is not run eagerly before the wrapping function is called. The wrapping function decides when to run `body`, and code is inserted to forward `body`'s effects to the outer `do` block.

#### Arbitrary `doElem`s in Nested Actions🔗

#13912 extends the `nestedAction` parser (`←` inside `do` blocks) to accept arbitrary `doElem`s after `←` instead of just terms.
`def bumpAndUse : IO Nat := do
let mut y := 1
let x ← pure (← if y < 3 then
y := y + 1
pure y
else
pure 0)
return x + y     -- x = 2 and y = 2

/-- info: 4 -/
#guard_msgs in
#eval bumpAndUse
`
`return e` inside `(← do …)` or `(← try … catch …)` now early-returns from the enclosing `do` block, not from the nested action. This a breaking change: replace with `pure e` when value-return from the nested block is intended, or wrap the `do` block in parentheses (`(← (do …))`).

#### Other `do` Elaborator Improvements🔗

- 
#13970 makes printed names of `mut` variables in error messages carry hover info so the infoview surfaces their type.

- 
#13910 renames the `liftMethod` parser to `nestedAction`, reflecting the terminology already used in documentation.

### Performance🔗

A fix to DiscrTree insertion (#13928) reduces the time to `import Mathlib` by approximately 10% by eliminating a non-linearity in the insertion algorithm.

Other notable performance work:

- 
#13123 makes the task thread pool reclaim idle worker threads after 5 seconds of inactivity, reducing memory waste from the 1GB default stack size per thread.

- 
#13938 adds tail-recursive `@[csimp]` runtime replacements for bounded-quantifier `Decidable` instances (`Nat.decidableBallLT`, `Nat.decidableExistsLT`, `Nat.decidableExistsLT'`), so running examples like
``true`#eval decide (∀ k, k < 2000000 → 0 ≤ k)
`false`#eval decide (∃ k, k < 50000000 ∧ k + 1 = 0)
`
no longer take quadratic time or overflow the stack.

- 
#13991 adds constant folding for `USize` operations and common bitwise operations, and #13974 extends it to `USize` relations. #14044 adds constant folding for `Nat.reprFast`.

### Monadic Verification: `mvcgen'` and `grind` Improvements🔗

The `mvcgen'` and `grind` ecosystem continues to mature:

- 
#13983 adds `mvcgen' until $t`, where `$t` is a conv-style pattern; verification-condition generation stops as soon as the program matches the pattern. For instance, compare the traces in these two examples:

def inc (n : Nat) : Id Nat := do
let a ← increaseBy n 1
let b ← increaseBy a 2
let c ← increaseBy b 3
let d ← increaseBy c 4
increaseBy d 5

example (n : Nat) : ⦃⌜True⌝⦄ inc n ⦃⇓ r => ⌜r = n + 15⌝⦄ := by
mvcgen' [inc]
trace_state
omega

example (n : Nat) : ⦃⌜True⌝⦄ inc n ⦃⇓ r => ⌜r = n + 15⌝⦄ := by
mvcgen' [inc] until increaseBy _ 4
case vc1 a =>
trace_state
mvcgen'    -- resume: run the remaining program to completion
omega

- 
#13925 consolidates `mvcgen'` syntax across tactic and `grind` (`sym =>`) modes:

example (n : Nat) : ⦃⌜True⌝⦄ inc n ⦃⇓ r => ⌜r = n + 15⌝⦄ := by
sym =>
mvcgen' [inc] <;> (show_asserted; finish)

`mvcgen' invariants?` (suggest mode) also works inside sym => … blocks.

- 
#13881 lets `mvcgen'` decompose programs whose head is a typeclass method projection (e.g. `Add.add inst a b`).

- 
#13888 teaches `mvcgen'` to register `Triple`-shaped local hypotheses as specs during VC generation.

- 
#13971 makes the `cbv` tactic available inside `grind`'s interactive `sym =>` mode.

### Lake: Linter Overhaul and Cache Improvements🔗

#### Environment Linters via Options🔗

#13893 (building on #13852's builtin linter sets) makes environment linters controlled by Lean options (`Lean.Option`), just like ordinary linters. Each environment linter is tied to a boolean option, so you can enable or disable it per declaration with `set_option linter.X false in ...` and across a lint run with the new `lake lint --linters=linter.X,-linter.Y` flag. Using `--lint-only` with the same syntax collects information only from the specified linters. Breaking change: the previous `lake lint` flags `--extra`, `--lint-all`, and the `builtin_nolint` attribute are removed in favour of this option-based control. `linter.extra` becomes a linter set whose members are the existing extra linters.

#### Module Linters🔗

#13917 adds module linters, which run once at the end of elaborating a module rather than after every command. A module linter receives the full array of top-level command syntaxes for the module, making it suitable for checks that need a whole-module view (e.g. enforcing module-wide syntactic conventions).

#### Other Lake Improvements🔗

- 
#13961 adds a `--record-exceptions` flag to `lake lint`, which inserts `set_option` flags to silence warnings on the definitions that triggered them.

- 
#14060 deduplicates cached artifacts by hash, and #14036 refines when and how Lake overwrites cache data with new `--no-overwrite` and `--force-overwrite` options. #13949 adds a `LAKE_RESTORE_ARTIFACTS` environment variable to override the workspace's `restoreAllArtifacts` configuration.

### Experimental: Incremental Compilation Caching🔗

#13965 adds experimental CLI flags that cache `lean`'s post-import elaboration state across invocations: `--incr-save FILE` writes a full snapshot at end of run, `--incr-load FILE` reuses one at startup, and `--incr-header-save FILE` writes a header-only snapshot (post-import `Environment`, no command bodies). A loaded snapshot is reused as far as unchanged syntax allows.

[...omitted: rest of v4.32.0 notes (library highlights, breaking changes, per-PR lists)...]

---
## Source: https://lean-lang.org/doc/reference/latest/releases/v4.31.0/
# Lean 4.31.0 (2026-06-13)🔗

For this release, 305 changes landed.
In addition to the 105 feature additions,
and 102 fixes listed below,
there were 17 refactoring changes,
5 documentation improvements,
13 performance improvements,
15 improvements to the test suite,
and 48 other changes.

## Highlights🔗

Lean 4.31.0 is a consolidation-heavy release: alongside a handful of new user-facing features — `do` blocks elaboration, Lake built-in linting, and richer editor hovers — it lands a large, coordinated effort to make definitional-equality checking properly respect transparency levels, a faster and reimplemented `mvcgen'`, significant development in libraries including HTTP, and broad performance work including an LLVM 22 upgrade.

This highlights section was contributed by Juanjo Madrigal.

### `do` Notation: New Loop Forms and New Elaborator🔗

The `while` condition in `do` blocks now accepts any condition form already allowed by `if` (#13534). In addition to `while c do …` and `while h : c do …`, you can now match against a pattern, binding either with `:=` or with `←`:

while let some x := stack.pop? do
process x

while let .ok line ← readLine? do
handle line

`repeat`/`while` loops also became verifiable (#13209). `whileM` is a counterpart to `Lean.Loop.forIn` that admits a one-step unfolding lemma `whileM_eq`. Existing `repeat`/`while` loops now expand through `whileM` without source changes, and the accompanying `@[spec]` theorems let `mvcgen`/`mvcgen'` discharge loop bodies given a termination measure and an invariant. See also #13689 / #13442 / #13447.

At the same time, the new `do` elaborator (accessible via `set_option backward.do.legacy false`) is also being developed: beyond extensibility, it already produces more precise and more actionable diagnostics:
`set_option backward.do.legacy false in
example : IO Nat := do
return 5
`This `do` element and its control-flow region are dead code. Consider removing it.`IO.println "never runs"
`
This `do` element and its control-flow region are dead code. Consider removing it.

The legacy elaborator instead rejects the same program with a coarser, purely structural error:
`set_option backward.do.legacy true in
example : IO Nat := do
`must be last element in a `do` sequence`return 5
IO.println "never runs"
`
must be last element in a `do` sequence

Related development in #13404 / #13542 / #13491 / #13494 / #13502 / #13506 / #13486 / #13397 / #13396 / #13399 / #13413 / #13434 / #13437 / #13507 / #13255 / #13250.

### Monadic Program Verification: `mvcgen'`🔗

Work continues on the monadic verification framework. #12965 introduces new foundations for reasoning about monadic Lean code, generalizing the assertion language for pre-/post-conditions of monadic Hoare triples from `SPred` to any `CompleteLattice`, separating post-conditions on terminating and abrupt paths, and resolving several universe-polymorphism issues.

Building on this, #13644 adds the experimental `mvcgen'` tactic, a from-scratch reimplementation of `mvcgen` on the new `SymM`-based symbolic-evaluation framework. It can outperform `mvcgen` by a factor of over 100x on some synthetic benchmarks and aspires to be feature-complete with it. `mvcgen'` can also be used as a step inside interactive `sym => …` blocks, where leftover verification conditions become subgoals for subsequent `grind` steps (#13680).

### Transparency and Defeq Discipline🔗

A cross-cutting theme of this release is making definitional-equality checking properly respect transparency: how aggressively Lean unfolds definitions when deciding whether two terms are definitionally equal. A plain `def` is defeq to its body at `.default` transparency, but `simp`/`dsimp` operate at the lower `.reducible` level, where it does not unfold:
`def x : Nat := 5

-- `rfl` checks defeq at `.default` transparency, so it closes the goal:
example : x = 5 := rfl

-- but `with_reducible` (where `simp`/`dsimp` run) won't unfold it:
example : x = 5 := `unsolved goals
⊢ x = 5`by⊢ x = 5 with_reducible `unknown tactic`refl⊢ x = 5

-- and `simp`/`dsimp` does not work either:
example : x = 5 := by⊢ x = 5 ``simp` made no progress`simp⊢ x = 5
`
Previously such transparency mismatches were common and hard to diagnose. The usual fix is to let the constant unfold at the lower transparency by marking it `@[reducible]`:
`@[reducible] def y : Nat := 5
example : y = 5 := by⊢ y = 5 with_reducible rflAll goals completed! 🐙
example : y = 5 := by⊢ y = 5 simpAll goals completed! 🐙
`
Migration: if proofs break under the stricter regime, the most common fixes are to scope `set_option backward.defeqAttrib.useBackward true in` over the affected declaration, switch `simpa using` to `simpa using!`, mark the relevant constants `@[implicit_reducible]`, or add the now-required projections explicitly to `simp`/`dsimp` calls. The diagnostics above (and `set_option diagnostics true` with `set_option trace.diagnostics true`) help locate the affected spots.

Related development: #13492 / #13363 / #13281 / #13512 / #13636 / #13833 / #13317 / #13368 / #13793 / #13280 / #13768 / #13772.

### Deprecating Modules, Syntax, and Options🔗

This release adds a family of tools for library authors to manage deprecations:

- 
#13002 adds a `deprecated_module` command that marks the current module as deprecated; importers receive a warning suggesting replacements. A `#show_deprecated_modules` command lists deprecated modules in the environment.

deprecated_module "use NewModule instead" (since := "2026-03-30")

- 
#13108 adds a `deprecated_syntax` command that marks syntax kinds as deprecated, emitting a linter warning when the deprecated syntax is elaborated, including through macro expansion.

- 
#13195 allows options to be marked deprecated, warning on `set_option` uses (controlled by `linter.deprecated.options`).

A related set of new linters warns about redundant modifiers: `linter.redundantVisibility` for `private`/`public` that matches the default (#13132), `linter.redundantExpose` for no-op `@[expose]`/`@[no_expose]` (#13359), and warnings for `@[simp]` theorems with a variable or unrecognized head symbol (#13325).

### Lake: Built-in Linting🔗

Lake gains a built-in linting framework, accessible through `lake lint` flags (#13393, #13431). It ships with environment linters upstreamed from Batteries/Mathlib (`defLemma`/`defProp`, `checkUnivs`) — see also the core upstreaming in #13356 — and a `builtinLint` package configuration option. Flags include `--builtin-lint`, `--builtin-only`, `--clippy`, `--lint-all`, and `--lint-only <name>`, and a `@[builtin_nolint]` attribute suppresses specific linters per declaration.

#13513 extends this to text linters by persisting their warnings into each module's `.olean`, and #13843 makes module-system targets lint their public surface, matching what downstream consumers see.

### Performance🔗

This release includes broad performance work:

- 
#13545 upgrades the bundled compiler toolchain from LLVM 19 to LLVM 22, bringing general improvements of up to 5% instructions depending on the benchmark.

- 
#13788 generates specialized `dec` code for values of known shape, and #13669 optimizes the `lean_dec_ref_cold` cold path.

- 
#13796 reduces `String.compare` to a single `memcmp`, and #13235 uses `memcmp` for `ByteArray` equality.

- 
#13651 replaces the tactic configuration elaboration system with one that directly constructs configuration objects and can skip term elaboration entirely; configuration evaluation now takes about 6.2% of the time it did before. The new system also supports custom configuration syntaxes and user configuration options for `simp` (e.g. `(user.optionName := …)`).

- 
Elaboration itself is faster for structure instance notation with many fields (#13760) and for `Expr.instantiateBetaRevRange` in the common case (#13758).

[...omitted: rest of v4.31.0 notes (library highlights, breaking changes, per-PR lists)...]

---
## Source: https://lean-lang.org/doc/reference/latest/releases/v4.30.0/
# Lean 4.30.0 (2026-05-26)🔗

For this release, 306 changes landed.
In addition to the 123 feature additions,
and 73 fixes listed below,
there were 17 refactoring changes,
8 documentation improvements,
19 performance improvements,
12 improvements to the test suite,
and 54 other changes.

## Highlights🔗

Lean 4.30.0 brings a new interactive `sym =>` tactic, a significantly expanded `cbv` tactic, completion of the new LCNF compiler backend with user-controllable borrow annotations, and a major overhaul of Lake's caching infrastructure.

This highlights section was contributed by Juanjo Madrigal.

### New `sym =>` Interactive Tactic🔗

#12970 adds `sym =>`, a new interactive tactic mode built on `grind`. Unlike `grind =>`, which eagerly introduces hypotheses and applies proof by contradiction, `sym =>` gives users explicit control over each step. So the user may use all the infrastructure provided by `grind` but with a custom strategy:
`example (f : Nat → Nat) (a b : Nat)
(hinj : ∀ x y, f x = f y → x = y) (h : f a = f b) : a = b := byf:Nat → Nata:Natb:Nathinj:∀ (x y : Nat), f x = f y → x = yh:f a = f b⊢ a = b
sym =>grindf:Nat → Nata:Natb:Nathinj:∀ (x y : Nat), f x = f y → x = yh:f a = f b⊢ a = b instantiategrindf:Nat → Nata:Natb:Nathinj:∀ (x y : Nat), f x = f y → x = yh:f a = f b⊢ a = b ; `[eqc] Equivalence classes
- [eqc] {a, b}
- [eqc] {f a, f b}`show_eqcsgrindf:Nat → Nata:Natb:Nathinj:∀ (x y : Nat), f x = f y → x = yh:f a = f b⊢ a = b ; finishAll goals completed! 🐙
`
[eqc] Equivalence classes
- [eqc] {a, b}
- [eqc] {f a, f b}

Available tactics include `intro`/`intros`, `apply`, `internalize`, `by_contra`, and `simp`. Solvers like `lia` and `ring` automatically introduce remaining binders and apply by-contradiction as needed.

Related development can be found in PRs: #12996 / #13018 / #13034 / #13039 / #13040 / #13041 / #13042 / #13046 / #13048 / #13080.

### `cbv` Tactic Expansion🔗

The `cbv` tactic, introduced in v4.29.0, is no longer experimental and receives major new capabilities in this release.

`cbv` performs a process similar to call-by-value evaluation in order to simplify or close the goals.
`def fact : Nat → Nat
| 0 => 1
| n+1 => (n+1) * fact n

def pow2 : Nat → Nat
| 0 => 1
| n+1 => 2 * pow2 n

-- `simp` requires providing functions
example : fact 5 < pow2 7 := by⊢ fact 5 < pow2 7 simp [fact, pow2]All goals completed! 🐙
-- `cbv` just executes directly
example : fact 5 < pow2 7 := by⊢ fact 5 < pow2 7 cbvAll goals completed! 🐙
`
v4.30.0 introduces the following improvements:

- 
#12597: `cbv_simproc` system mirroring `simp`'s `simproc` infrastructure.

- 
#12773: `at` location syntax (`cbv at h`, `cbv at h |-`, and `cbv at *`).

- 
#12788: `set_option cbv.maxSteps N` for user-configurable step limits.

- 
#12763: short-circuit evaluation for `Or`/`And`: for expressions like `decide (m < n ∨ expensive)`

- 
Other improvements: #12851 / #12944 / #12875 / #12888.

### Compiler: User Borrow Annotations and New LCNF Backend🔗

#### User Borrow Annotations🔗

#12830 enables support for user-provided borrow annotations. Users can now mark function arguments with `(x : @&Ty)` and have the borrow inference preserve these annotations, reducing reference counting pressure:

def process (ctx : @& Context) (data : Array Nat) : Result :=
...  -- `ctx` will not be reference counted

The compiler prioritizes preserving tail calls over borrow annotations. Use `trace.Compiler.inferBorrow` to see a detailed reasoning of the compiler's inference decisions. #12810 adds this tracing infrastructure.

#12942 marks the context argument of `ReaderT` as borrowed (`(a : @&ρ) → m α`), causing a widespread reduction in RC pressure across the entire metaprogramming stack.

#### New LCNF Backend Complete🔗

#12781 ports the C emission pass from IR to LCNF, marking the final step of the IR/LCNF conversion and enabling end-to-end code generation through the new compilation infrastructure.

#12665 ports the expand reset/reuse pass to LCNF with improved exponential-code prevention, resulting in a ~15% decrease in binary size and slight speedups across the board.

#### Other Compiler Improvements🔗

- 
#12971 increases Lean's default stack size to 1GB (pages are allocated dynamically, so this does not increase memory usage). The stack size can be customized via `LEAN_STACK_SIZE_KB`.

- 
#12539 replaces three independent name demangling implementations (Lean, C++, Python) with a single source of truth in `Lean.Compiler.NameDemangling`, deleting ~1,400 lines of duplicated code.

- 
#12724, #12727 extract ground array and boxed scalar literals into statically initialized data.

### Lake Cache Overhaul🔗

This release brings a comprehensive overhaul of Lake's caching infrastructure:

- 
#12634:  enables Lake to download artifacts from a remote cache service on demand as part of a `lake build`.

- 
#12927: `lake cache get` changes to download artifacts by default. Artifacts can be downloaded on demand with the new `--mappings-only` option.

- 
#12974: parallel artifact transfers using `curl --parallel` for both uploads and downloads.

- 
#13164: download optimizations by fetching all artifact URLs from Reservoir in a single bulk POST request instead of per-artifact redirects.

- 
#12914: `.ltar` archive packing/unpacking via `leantar`.

- 
#13144: new `lake cache` subcommands for staged cache uploads: `stage`, `unstage`, and `put-staged`, functioning as parallels for the commands of the same name in Mathlib's `lake exe cache`.

- 
#12935: new `fixedToolchain` option for packages only expected to function on a single toolchain (like Mathlib).

### Other Language Improvements🔗

- 
#13011 adds `@[deprecated_arg]`, a new attribute for deprecating individual function parameters. When a caller uses the old parameter name, the elaborator emits a deprecation warning with a code action hint.

- 
#12756 adds `deriving noncomputable instance Foo for Bar` syntax so that delta-derived instances can be marked noncomputable.

- 
#13117 re-enables `#print axioms` under the module system by computing axiom dependencies at olean serialization time.

- 
#12866 adds `optType` support to the `doPatDecl` parser, allowing `let ⟨width, height⟩ : Nat × Nat ← action` in do-notation.

- 
#12325 adds a warning when a `def` of class type does not declare an appropriate reducibility (e.g., `@[reducible]` or `@[implicit_reducible]`).

- 
#12233 replaces `instantiateMVars` with a two-pass implementation that reduces quadratic complexity from long chains of delayed-assigned metavariables to linear.

[...omitted: rest of v4.30.0 notes (library highlights, breaking changes, per-PR lists)...]

---
## Source: https://lean-lang.org/doc/reference/latest/releases/v4.29.0/
# Lean 4.29.0 (2026-03-27)🔗

For this release, 453 changes landed. In addition to the 112 feature additions and 107 fixes listed below there were 30 refactoring changes, 21 documentation improvements, 29 performance improvements, 26 improvements to the test suite and 115 other changes.

## Highlights🔗

Violetta Sim has helpfully written the release highlights from 4.16 through 4.29, and the Lean developers gratefully acknowledge her contributions.

### Performance Improvements🔗

#12082 and
#12044 reduce
startup time by storing closed terms directly in the binary, where
possible, and initializing the remaining ones lazily instead of at
startup.

#12406 significantly
reduces the memory consumed by LRAT proof checking in `bv_decide`.

### New Extensible `do` Elaborator🔗

#12459 adds a new,
extensible `do` elaborator. Users can opt into the new elaborator by
unsetting the option `backward.do.legacy`.

New elaborators for the builtin `doElem` syntax category can be
registered with attribute `doElem_elab`. For new syntax, additionally
a control info handler must be registered with attribute
`doElem_control_info` that specifies whether the new syntax `return`s
early, `break`s, `continue`s and which `mut` vars it reassigns.

Do elaborators have type
`TSyntax `doElem → DoElemCont → DoElabM Expr`, where `DoElabM` is
essentially `TermElabM` and the `DoElemCont` represents how the rest
of the `do` block is to be elaborated. Consult the docstrings for more
details.

Breaking Changes:

- 
The syntax for `let pat := rhs | otherwise` and similar now scope
over the `doSeq` that follows. Furthermore, `otherwise` and the
sequence that follows are now `doSeqIndented` in order not to steal
syntax from record syntax.

Breaking Changes when opting into the new `do` elaborator by unsetting
`backward.do.legacy`:

- 
`do` notation now always requires `Pure`.

- 
`do match` is now always non-dependent. There is
`do match (dependent := true)` that expands to a term match as a
workaround for some dependent uses.

### mvcgen: Specifications in the Local Context🔗

#12395 adds mvcgen
support for specifications in the local context. Example:

import Std.Tactic.Do

open Std.Do

set_option mvcgen.warning false

def foo (x : Id Nat → Id Nat) : Id Nat := do
let r₁ ← x (pure 42)
let r₂ ← x (pure 26)
pure (r₁ + r₂)

theorem foo_spec
(x : Id Nat → Id Nat)
(x_spec : ∀ (k : Id Nat) (_ : ⦃⌜True⌝⦄ k ⦃⇓r => ⌜r % 2 = 0⌝⦄), ⦃⌜True⌝⦄ x k ⦃⇓r => ⌜r % 2 = 0⌝⦄) :
⦃⌜True⌝⦄ foo x ⦃⇓r => ⌜r % 2 = 0⌝⦄ := by
mvcgen [foo, x_spec] <;> grind

def bar (k : Id Nat) : Id Nat := do
let r ← k
if r > 30 then return 12 else return r

example : ⦃⌜True⌝⦄ foo bar ⦃⇓r => ⌜r % 2 = 0⌝⦄ := by
mvcgen [foo_spec, bar] -- unfold `bar` and automatically apply the spec for the higher-order argument `k`

### grind: Higher-Order Miller Pattern Support in E-matching🔗

#12483 adds support
for higher-order Miller patterns in `grind`'s e-matching engine.
Previously, lambda arguments in e-matching patterns were always
treated as `dontCare`, meaning they could not contribute to matching
or bind pattern variables. This was a significant limitation for
theorems where lambda arguments carry essential structure, such as
`List.foldl`, `List.foldrM`, or any combinator that takes a function
argument.

With this change, when a pattern argument is a lambda whose body
satisfies the Miller pattern condition — i.e., pattern variables
are applied only to distinct lambda-bound variables — the lambda is
preserved as an `ho[...]` pattern. At instantiation time, these
higher-order patterns are matched via `isDefEq` after all first-order
pattern variables have been assigned by the E-graph.

Example

@[grind =] theorem applyFlip_spec (f : Nat → Nat → Nat) (a b : Nat)
: applyFlip (fun x y => f y x) a b = f b a := sorry

The pattern `applyFlip ho[fun x => fun y => #2 y x] #1 #0` captures
the lambda argument structurally: `#2` (the pattern variable for `f`)
is applied to distinct lambda-bound variables `y` and `x`. When
`grind` encounters `applyFlip (fun x y => Nat.add y x) 3 4`, it binds
`f := Nat.add` via `isDefEq` and fires the rewrite.

### One Axiom per Native Computation🔗

#12217 implements
RFC #12216: native
computation (`native_decide`, `bv_decide`) is represented in the logic
as one axiom per computation, asserting the equality that was obtained
from the native computation. `#print axiom` will no longer show
`Lean.trustCompiler`, but rather the auto-generated names of these
axioms (with, for example, `._native.bv_decide.` in the name). See the
RFC for more information.

### More Reliable Universe Level Inference in `inductive`/`structure` Commands🔗

#12514 improves
universe level inference for the `inductive` and `structure` commands
to be more reliable and to produce better error messages. See the PR
description for more information.

Breaking change. Universe level metavariables present only in
constructor fields are no longer promoted to be universe level
parameters: use explicit universe level parameters. This promotion was
inconsistently done depending on whether the inductive type's universe
level had a metavariable, and also it caused confusion for users,
since these universe levels are not constrained by the type former's
parameters.

Breaking change. Now recursive types do not count as “obvious
`Prop` candidates”. Use an explicit `Prop` type former annotation on
recursive inductive predicates.

### Simpler `noncomputable` Semantics🔗

#12028 gives a
simpler semantics to `noncomputable`, improving predictability as well
as preparing codegen to be moved into a separate build step without
breaking immediate generation of error messages.

Specifically, `noncomputable` is now needed whenever an axiom or
another `noncomputable` def is used by a def except for the following
special cases:

- 
uses inside proofs, types, type formers, and constructor arguments
corresponding to (fixed) inductive parameters are ignored

- 
uses of functions marked `@[extern]/@[implemented_by]/@[csimp]` are
ignored

- 
for applications of a function marked `@[macro_inline]`,
noncomputability of the inlining is instead inspected

Breaking change: After this change, more `noncomputable`
annotations than before may be required in exchange for improved
future stability.

### Changes to Instance and Reducibility Handling🔗

v4.29.0 brings a significant and breaking change to the handling of reducibility settings.
We address a longstanding problem: prior to v4.29.0, the `isDefEq` algorithm would bump the
transparency level up to `.default` (i.e. become willing to unfold default transparency definitions)
when comparing implicit arguments.

This was a serious problem, causing both immediate unpredictable performance problems in
`isDefEq`, and hiding many places where definitional abuse was occurring in downstream libraries.

In order to ensure scalability, and address these definitional abuse problems, we have
made the quite disruptive change, in #12179,
of removing this transparency level bump as the default path.

The changes to the transparency bump in comparing implicit arguments can be controlled in two ways:

- 
Definitions can be tagged with the new `@[implicit_reducible]` attribute.
This is intermediate between `@[reducible]` and `@[semireducible]` (i.e. the default setting),
in that the definition is mostly treated as semireducible, except when `isDefEq` is processing
implicit arguments or match discriminants.
See #12247 and #12567.

- 
The option `set_option backward.isDefEq.respectTransparency false` restores the previous behaviour prior to `v4.29.0`
(equivalently, all semireducible definitions are treated as `implicit_reducible`).
As a backward compatibility option, this may eventually be removed, but given how disruptive this change is we anticipate leaving the option available for the medium term.

As a consequence of these changes to transparency handling, existing definitional abuse problems in downstream libraries now surface in places
where previously they didn't. To help address these problems, which primarily, but not exclusively,
are caused by incorrectly implemented typeclass instances, we have made changes in #12897
to `inferInstanceAs` and the default `deriving` handler.
These ensure that instances created using them do not leak the definition of the types involved,
when the instances are reduced at less than semireducible transparency.

`inferInstanceAs α` synthesizes an instance of type `α` but now adjusts it to conform to the
expected type `β`, which must be inferable from context.

Example:

def D := Nat
instance : Inhabited D := inferInstanceAs (Inhabited Nat)

The adjustment will make sure that the resulting instance will not leak the RHS `Nat` when
reduced at transparency levels below `semireducible`, i.e. where `D` would not be unfolded either.

More specifically, given the source type (the argument) and target type (the expected type),
`inferInstanceAs` synthesizes an instance for the source type and then unfolds and rewraps its
components (fields, nested instances) as necessary to make them compatible with the target type. The
individual steps are represented by the following options, which all default to enabled and can be
disabled to help with porting:

- 
`backward.inferInstanceAs.wrap`: master switch for instance adjustment in both `inferInstanceAs`
and the default deriving handler

- 
`backward.inferInstanceAs.wrap.reuseSubInstances`: reuse existing instances for the target type
for sub-instance fields to avoid non-defeq instance diamonds

- 
`backward.inferInstanceAs.wrap.instances`: wrap non-reducible instances in auxiliary definitions

- 
`backward.inferInstanceAs.wrap.data`: wrap data fields in auxiliary definitions (proof fields are
always wrapped)

If you just need to synthesize an instance without transporting between types, use `inferInstance`
instead, potentially with a type annotation for the expected type.

A third significant change in `v4.29.0` is that `simp` and `dsimp` no longer process typeclass instances.
This behaviour was producing non-standard instances, and causing problems in Mathlib.
See #12244 and #12195.
The old behavior can be restored with

set_option backward.dsimp.instances true

or `simp +instances` for `simp`. Our experience so far, however, is that this is not often needed.

Finally we have fixed in #12172 a problem with how
we determine whether a function parameter is an instance, which has follow-on effects in several algorithms that depend on this classification.
This may cause potential regressions: automation may now behave differently
in cases where it previously misidentified instance parameters.
For example, a rewrite rule in `simp` that was not firing due to
incorrect indexing may now fire.

#### Migration guide🔗

Any projects wanting to postpone dealing with the adaptations required by the changes to transparency level bumps can
simply use `set_option backward.isDefEq.respectTransparency false`.

This can be set on a project-wide level in your `lakefile.toml`:

[leanOptions]
backward.isDefEq.respectTransparency = false

However we encourage you to instead localize the option in the files that need it,
or even on individual declarations using `set_option backward.isDefEq.respectTransparency false in ...`.
This makes it easier to start identifying the definitional abuse problems in your code.

If your project is downstream of Mathlib, you may find the following two scripts useful:

- 
`scripts/add_set_option.py` (available in `.lake/packages/mathlib/scripts/add_set_option.py` if you have Mathlib as a dependency)
which tries compiling your project, and automatically wrapping any failing declaration with `set_option backward.isDefEq.respectTransparency false in ...`,
in those cases where doing so resolves the failure.

- 
`scripts/rm_set_option.py`, which compiles your project and identifies all occurrences of `set_option backward.isDefEq.respectTransparency false in ...` which can be removed without causing a failure (in that same declaration).
This may happen because of earlier changes which resolve the definitional abuse problem.

These scripts can also be copied out of Mathlib and run on any project.

Again, when downstream of Mathlib you may also use the experimental `#defeq_abuse in ...` command,
which attempts to identify and explain, or at least give clues to, the underlying definitional abuse problem that
may explain why a declaration currently needs `set_option backward.isDefEq.respectTransparency false in ...`.
We encourage users to report problems with this command on the Zulip,
and we hope that as this diagnostic command stabilizes we will be able to make it available as part of a future Lean toolchain.

You are encouraged to review the construction of instances for all default transparency type synonyms in your project.
Where possible, you should use the `deriving` handler, or the new `inferInstanceAs` elaborator,
rather than writing term mode constructions which require unfolding the type synonym in order to typecheck.
The `inferInstanceAs` command now requires an expected type.
If you encounter errors where `inferInstanceAs` now gives an error because an expected type was not provided,
you may find that you should simply be using `inferInstance` instead.

### Universe Levels as Output Parameters🔗

#12423 adds the
attribute `@[univ_out_params]` for specifying which universe levels
should be treated as output parameters. By default, any universe level
that does not occur in any input parameter is considered an output
parameter.

[...omitted: rest of v4.29.0 notes (library highlights, breaking changes, per-PR lists)...]

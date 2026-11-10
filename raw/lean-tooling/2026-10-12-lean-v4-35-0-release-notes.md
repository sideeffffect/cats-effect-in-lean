# Lean 4.35.0 release notes (highlights and breaking changes)

> Source: https://lean-lang.org/doc/reference/latest/releases/v4.35.0/
> Collected: 2026-11-10
> Published: 2026-10-12

# Lean 4.35.0 (2026-10-12)🔗

For this release, 214 changes landed.
In addition to the 78 feature additions
and 57 fixes listed below,
there were 18 refactoring changes,
7 documentation improvements,
23 performance improvements,
2 improvements to the test suite,
and 29 other changes.

## Highlights🔗

The main new feature of Lean 4.35.0 is `vcgen`, a faster and more general successor of `mvcgen`.
It also adds `lake check` and `lake comparator`, which check a project with Lean's kernel and, if requested, with several independent kernels that now come with the toolchain.
On the tactic side, `rwa` has been redesigned, `constructor` now warns when it has to choose between constructors, and `grind` proves more goals about `BitVec` and fixed-width integers by translating them into `Nat` and `Int` arithmetic.
`Decidable` has a new definition based on `Bool`, which makes many more equations hold by `rfl`.

This highlights section was contributed by Juanjo Madrigal.

### `vcgen`, the successor of `mvcgen`🔗

Lean 4.35 ships `vcgen`, a verification condition generator that replaces `mvcgen` as a mostly drop-in successor; `mvcgen` is now deprecated. Improvements:

- 
Deep embeddings. `vcgen` builds on the `Std.WP` framework, whose weakest precondition interpretation applies to any program type rather than only to monads: besides `do`-programs in any monad, `vcgen` verifies deeply embedded languages, such as that of x64 assembler or WebAssembly for which a notion of weakest precondition is definable. This generality is the reason for the new name.

- 
Generalized assertion languages. The program logic's assertions can live in any complete lattice, which opens `vcgen` to assertion languages beyond predicates on the state, such as probabilistic logics and separation logic, and a generalized notion of frame preservation carries unchanged parts of an assertion across calls.

- 
Performance. `vcgen` runs on the new `SymM` framework and internalizes the shared goal context into `grind`'s E-graph once, so that the discharge step `vcgen … with finish` reuses it across all verification conditions. On the AddSubCancel benchmark, where the program is a stateful loop body repeated 2200 times, `vcgen` needs 0.32 s where `mvcgen` needs 66 s, and the kernel checks the resulting proof in 0.53 s instead of 246 s. The running time of `vcgen` grows linearly with the program size, at about 0.14 ms per loop iteration.

`mvcgen` vs `vcgen`

`vcgen` vs kernel
`vcgen` is still marked experimental: `set_option experimental.vcgen true` acknowledges this and silences the corresponding warning. The reference manual chapter and the tutorial Verifying Imperative Programs Using `vcgen` describe the tactic.

### Checking Projects with `lake check` and `lake comparator`🔗

Until now, checking a finished development with an external kernel, or checking that a proof matches a given statement with comparator, meant installing and configuring several separate tools.
This release brings all of this into Lake.

#14990 adds `lake check`, which builds the default targets of the current project, exports them, replays the export through the kernel, and fails if anything uses an axiom other than the standard ones.
#14885 and #15146 add `lake comparator`, a frontend to comparator: given a challenge module with theorem statements and a solution module, it checks that each named theorem in the solution proves the same statement as in the challenge, that it uses only the permitted axioms, and that the kernel accepts it.
By default, its configuration is read from `comparator.json` (#15147):

{
"challenge_module": "Challenge",
"solution_module": "Solution",
"theorem_names": ["imo2024_p1"],
"permitted_axioms": ["propext", "Quot.sound", "Classical.choice"]
}

Both commands treat the project as untrusted.
It is built and exported inside a `bubblewrap` sandbox that hides the user's home directory and only gives network access to dependency resolution (#15005), and the kernel runs in a separate process (#15055).
The sandbox is currently only available on Linux.

The release toolchain now also includes the external checkers `lean4lean` (#15048), `nanoda` (#15099), `con-leche` (#15130) and `con-ron` (#15153), together with `leanchecker-paranoid`, a version of `leanchecker` built with a hardened memory allocator (#14884).
With `--paranoid`, both commands run all of these checkers in addition to Lean's own kernel, and accept the project only if every one of them does (#15145):

lake check              # Lean's kernel, standard axioms only
lake check --paranoid   # ...and every bundled external checker

An export produced elsewhere, for example in a virtual machine or by someone with more computing resources, can be checked directly with `lake check --from-export`, `lake comparator --solution-from-export` or `lake comparator --challenge-from-export` (#15157), and `leanchecker` itself also gained a `--from-export` flag (#15050).

Related to this, #14953 removes `Lean.reduceBool`, `Lean.reduceNat` and the `Lean.trustCompiler` axiom, which had been deprecated since February.
Since `Lean.trustCompiler` was referenced from the definitions of `Lean.reduceBool` and `Lean.reduceNat`, it looked used in every environment that imported them, which made whole-environment axiom checks such as `lake check` less meaningful.
The work from v4.34.0 on the runtime's reference counting also continues, with three fixes that were also backported to v4.34.1.
#15241 and #15289 close two more ways in which an extremely large input could cause a use-after-free in the official kernel, and #15288 fixes a related problem with objects shared between threads, which the official kernel does not do in its default configuration but other Lean-based checkers might.
Kernels that are not based on the Lean runtime were not affected.

### Tactic Changes🔗

#### A Redesigned `rwa`🔗

`rwa` used to be a plain macro for `rw ...; assumption`, so the `assumption` step could end up closing some unrelated goal.
#14937 changes it so that it only works on the goal it was called on, and on the side goals created by the rewrite: `rwa [rules]` rewrites the goal and closes it with an assumption, while `rwa [rules] at h` rewrites `h` and then closes the main goal using `h` itself, rather than any matching assumption.
When the rewrite alone already closes the goal, it suggests using `rw` instead:
`example (a : Nat) : a + 0 = a := bya:Nat⊢ a + 0 = a
``rw` already closes the goal

Hint: Use `rw` instead of `rwa`:
[apply] rw [Nat.add_zero]

Note: This linter can be disabled with `set_option linter.unnecessaryRwa false``rwa [Nat.add_zeroa:Nat⊢ a = a]All goals completed! 🐙
`
`rw` already closes the goal

Hint: Use `rw` instead of `rwa`:
[apply] rw [Nat.add_zero]

Note: This linter can be disabled with `set_option linter.unnecessaryRwa false`

The forms `rwa [rules] at h₁ h₂` and `rwa [rules] at *` are deprecated; use `rw [rules] at h₁ h₂ <;> assumption` instead.

#### `constructor` Warns When It Has to Choose🔗

When more than one constructor fits the goal, `constructor` silently used the first one.
For a disjunction, this means it always picks the left side, which is often not intended.
#14854 makes it warn in this case:
`example : 2 ≤ 3 ∨ 3 ≤ 2 := by⊢ 2 ≤ 3 ∨ 3 ≤ 2
`Tactic `constructor` applied constructor `Or.inl`, but `Or.inr` also matches the goal.

Hint: Use `constructor!` to apply the first matching constructor without this warning:
[apply] constructor!`constructor⊢ 2 ≤ 3
decideAll goals completed! 🐙
`
Tactic `constructor` applied constructor `Or.inl`, but `Or.inr` also matches the goal.

Hint: Use `constructor!` to apply the first matching constructor without this warning:
[apply] constructor!

The new `constructor!` keeps the previous behavior without the warning.

#### Extra Facts for `lia` and `grobner`🔗

#15116 lets `lia` and `grobner` take a list of facts and lemmas, just like `grind`, so they no longer have to be added to the context first with `have`:
`def double (n : Nat) : Nat := 2 * n

theorem double_def (n : Nat) : double n = 2 * n := rfl

example (n : Nat) (h : double n ≤ 10) : n ≤ 5 := byn:Nath:double n ≤ 10⊢ n ≤ 5
lia [double_def n]All goals completed! 🐙
`

### Homomorphisms in `grind`🔗

#14727 completes support for homomorphisms in `grind`, building on the `[grind hom]` and `[grind hom_pred]` attributes that were prepared in v4.34.0.
Theorems with these attributes describe how to translate terms of one type into another type for which `grind` has a solver.
Lean comes with such translations for types including `Fin`, `BitVec`, and the fixed-width integer types `UInt8`–`UInt64`, `USize`, `Int8`–`Int64` and `ISize`, which are mapped to `Nat` and `Int` arithmetic.
As a result, goals like these, which mix machine arithmetic with bounds on natural numbers, can now be proved by `grind`:
`example (x : UInt8) (h : x.toNat < 100) :
(x + 1).toNat = x.toNat + 1 := byx:UInt8h:x.toNat < 100⊢ (x + 1).toNat = x.toNat + 1
grindAll goals completed! 🐙

example (x : BitVec 8) (h : x.toNat < 10) :
(x * 2).toNat < 20 := byx:BitVec 8h:x.toNat < 10⊢ (x * 2).toNat < 20
grindAll goals completed! 🐙
`
The translation is on by default and can be turned off with `grind -hom`.
It replaces the previous mechanism based on the `Lean.Grind.ToInt` type class.

### Decidable Propositions Are Now Based on `Bool`🔗

#8309 changes the definition of `Decidable`: instead of an inductive type with the constructors `isTrue` and `isFalse`, it is now a structure that stores a `Bool` together with a proof that this `Bool` reflects the proposition.
``class Decidable (p : Prop) : Type
number of parameters: 1
fields:
Decidable.decide : Bool
Decidable.reflects_decide : (decide p).Reflects p
constructor:
Decidable.intro {p : Prop} (decide : Bool) (reflects_decide : decide.Reflects p) : Decidable p`#print Decidable
`
class Decidable (p : Prop) : Type
number of parameters: 1
fields:
Decidable.decide : Bool
Decidable.reflects_decide : (decide p).Reflects p
constructor:
Decidable.intro {p : Prop} (decide : Bool) (reflects_decide : decide.Reflects p) : Decidable p

This means that `decide` on a proposition built from equations between `Bool`s now reduces to the corresponding `Bool` operations, so many equations hold by `rfl`:
`variable (a b : Bool)

example : decide (a = true) = a := rfl
example : decide (a = true ∧ b = true) = (a && b) := rfl
example : decide (a = true ∨ b = true) = (a || b) := rfl
example : decide (¬a) = !a := rfl
`
The `decide` tactic also no longer needs to carry proofs around, which makes it faster on well-written instances.
The recommended way to write such instances is now with `decidable_of_bool` or `decidable_of_iff`.
`Decidable.isTrue` and `Decidable.isFalse` still exist and can still be used as patterns in `match`, so most existing code keeps working.

### Other Language Improvements🔗

#14899 adds the `recall` command from Mathlib to Lean itself.
It restates an existing declaration, which is useful in teaching material and expository files, and Lean checks that the restatement matches the original:
`recall Nat.add_comm (n m : Nat) : n + m = m + n
`Type mismatch
Nat.add_comm
has type
∀ (n m : Nat), n + m = n + m
but is expected to have type
∀ (n m : Nat), n + m = m + n``Try this:
[apply] recall Nat.add_comm (n m : Nat) : n + m = m + n`recall Nat.add_comm (n m : Nat) : n + m = n + m
`
Type mismatch
Nat.add_comm
has type
∀ (n m : Nat), n + m = n + m
but is expected to have type
∀ (n m : Nat), n + m = m + n

`recall?` suggests the restatement for a given name:
``Try this:
[apply] recall Nat.add_comm (n m : Nat) : n + m = m + n`recall? Nat.add_comm
`
Try this:
[apply] recall Nat.add_comm (n m : Nat) : n + m = m + n

#14960 makes `#print` show the reduction rules of a recursor in a readable form, instead of the raw functions that the kernel uses:
``recursor Nat.rec.{u} {motive : Nat → Sort u} (zero : motive Nat.zero) (succ : (n : Nat) → motive n → motive n.succ)
(t : Nat) : motive t
number of parameters: 0
number of motives: 1 (position 1)
number of minor premises: 2 (positions 2–3)
number of indices: 0
major premise position: 4
rules:
Nat.rec zero succ Nat.zero
==> zero
Nat.rec zero succ n.succ
==> succ n (Nat.rec zero succ n)`#print Nat.rec
`
recursor Nat.rec.{u} {motive : Nat → Sort u} (zero : motive Nat.zero) (succ : (n : Nat) → motive n → motive n.succ)
(t : Nat) : motive t
number of parameters: 0
number of motives: 1 (position 1)
number of minor premises: 2 (positions 2–3)
number of indices: 0
major premise position: 4
rules:
Nat.rec zero succ Nat.zero
==> zero
Nat.rec zero succ n.succ
==> succ n (Nat.rec zero succ n)

#14834 makes “go to definition” work for fields that are used inside the definition of a later field of the same `structure` or `class`.

Deprecations got a few more checks: the `deprecated` linter warning now comes with a clickable fix that replaces the old name (#14705), and `@[deprecated]` itself warns when the replacement is also deprecated (#14816) or when it has a different type (#14600):
`def addOne (n : Nat) : Int := n + 1
``@[`The updated constant has a different type:
Nat → Int
instead of
Nat → Nat

This suggests that addressing the deprecation might be more involved than simply replacing the old name with the new name. This is often expected, but sometimes it indicates that the deprecation is in favor of the wrong declaration, or that there is a mistake in one of the statements.

If the type difference is intentional, use `+typeChanged` to silence this warning.

Hint: Add `+typeChanged`:
[apply] +typeChanged`deprecated addOne (since := "2026-10-01")]
def plusOne (n : Nat) : Nat := n + 1
`
The updated constant has a different type:
Nat → Int
instead of
Nat → Nat

This suggests that addressing the deprecation might be more involved than simply replacing the old name with the new name. This is often expected, but sometimes it indicates that the deprecation is in favor of the wrong declaration, or that there is a mistake in one of the statements.

If the type difference is intentional, use `+typeChanged` to silence this warning.

Hint: Add `+typeChanged`:
[apply] +typeChanged

For (co)inductive predicates, #14861 adds a `monotonicity_by` clause for giving the monotonicity proof by hand when the automatic proof fails, and #14855 generates the strong (co)induction principles `strong_coinduct` and `strong_induct`.

### Lake🔗

Apart from `lake check` and `lake comparator`, described above, the new Lake features in this release are mostly options for specific situations:

Stop a build at the first failure

`lake build --fail-fast`. Lake stops scheduling new jobs after the first failure, lets running jobs finish, and reports skipped jobs as `⊘ Canceled` (#14797, #14835).

Depend on a local package through a copy rather than in place

`copy = true` in a `[[require]]` entry with a `path`, or `require pkg from copy "path"` in a `lakefile.lean`. Lake copies the package into the workspace's packages directory, as it would clone a Git dependency, and uses the copy (#15142).

Precompile only part of the code, instead of using `precompileModules`

`precompileImports`, which compiles a module's imports but not the module itself, or `precompileLibrary`, which compiles a whole library for the modules that import it (#15015).

Upload the build outputs of a dependency to a cache

`lake build -o <file> --package <name>`, followed by `lake cache put <file> --package=<name>` (#15141).

Collect code-quality data from linters and custom checks

`lake lint --code-quality`, which now also reports metrics that linters record during elaboration (#14748, #14933) and runs checks registered with `@[package_code_quality_check]`, including ones from modules passed with `--checks` (#14716).

One more change needs no action: dependencies are now fetched as partial Git clones of a single revision, which reduces the amount of data downloaded (#14782).
As a consequence, Git commands such as `git blame` inside a dependency may need to fetch data on demand.

### Library Highlights🔗

#13490 adds `Nat.powMod`, which computes `b ^ e % m` without computing `b ^ e` first.
Compiled code uses GMP's modular exponentiation when Lean is built with GMP, and the definition itself uses square-and-multiply, so the kernel can also evaluate it efficiently.
Exponentiation on `Fin n` now uses it, so even large modular powers can be checked with `decide`:
`example : (2 : Fin 1000000007) ^ 1000000006 = 1 := bya:Boolb:Bool⊢ 2 ^ 1000000006 = 1 decideAll goals completed! 🐙
`
Other additions include a fused multiply-add for `Float` and `Float32` (#15024), a much larger public API for CNF formulas together with a rewritten LRAT checker (#14842), and missing order instances for `Fin`, `Int`, `Nat` and the fixed-width integers (#15092, #15088, #15071, #15122).
Several `Array` and `Vector` operations, such as `map`, `ofFn`, `zipWith` and `modify`, now reduce in the kernel across module boundaries, so that `decide` and `rfl` can evaluate them in files that use the module system (#14270, #14989, #14996, #15078, #15079).
Vectors are now displayed with the `#v[...]` notation (#14545):
``#v[10, 20, 30]`#eval #v[1, 2, 3].map (· * 10)
`
#v[10, 20, 30]

For finding performance problems caused by unintended copying, #15052 adds `markLinear` for `String`, `ByteArray`, `FloatArray` and `Array`, with #15069 and #15049 adding it for vectors and hash maps.
After `markLinear`, every write to the value must happen while it is not shared; if the environment variable `LEAN_ABORT_ON_NONLINEAR` is set, the program aborts at the first write that does not.

### Breaking Changes🔗

- 
#14624 fixes #9077, in which instance synthesis could see through a type synonym.
During instance search, a metavariable for an instance-implicit argument is now only assigned a value of the expected type, up to instance transparency.
The related change #14583 makes unification try its remaining heuristics before giving up with a stuck exception.
Migration: `set_option backward.isDefEq.respectTransparency.instanceSearchTypes false` restores the old instance search behavior, and `set_option backward.isDefEq.throwOnStuckAfterApp true` the old unification behavior.
In Mathlib, the affected declarations use the first option and are annotated with suggestions for a proper fix.

- 
#8309 changes the definition of `Decidable`, as described above.
Since `isTrue` and `isFalse` can still be used as patterns, relatively little code is affected, but code that relies on the old inductive definition may need to be adjusted.

- 
#14937 changes the behavior of `rwa`, as described above.
In particular, `rwa [rules] at h` now fails if the rewritten `h` does not close the goal, even if some other assumption would.
Migration: use `rw [rules] at h; assumption` to keep the old behavior, and `rw [rules] at h₁ h₂ <;> assumption` instead of the deprecated multi-location form.

- 
#14854 makes `constructor` warn when several constructors match.
Migration: use `constructor!` where the first constructor is really the intended one, or a more specific tactic such as `left` or `right`.

- 
#14727 removes the `Lean.Grind.ToInt` type class hierarchy and its instances, which `grind`'s arithmetic solver used before (only an empty placeholder class remains, and it will also be deleted), removes many `BitVec` and `UIntN` E-matching lemmas from the default `grind` set that are now covered by homomorphisms, and removes `[grind ext]` from `Fin.ext`.

- 
#14953 removes `Lean.reduceBool`, `Lean.reduceNat`, `Lean.ofReduceBool`, `Lean.ofReduceNat` and `Lean.trustCompiler`.
Migration: use `native_decide`, or `Lean.Meta.nativeEqTrue` in metaprograms.

- 
#14874 deprecates `mvcgen` and `mvcgen?` in favor of `vcgen`.

- 
#15141 makes `lake cache put-staged` require an explicit revision.
Migration: pass it with `--rev`, for example `--rev=$(git rev-parse HEAD)`.

- 
#15054 changes the precedence of range notation, so that `1 + 2...3` means `(1 + 2)...3` and `a...b |>.toList` means `(a...b).toList`.

- 
#14350 requires that when an element of singleton notation such as `{f x}` continues on the next line, the continuation is indented further than the start of the element, to avoid confusion with structure instance notation.

- 
#15019 removes the `withPosition` marker from the bodies of `macro` and `elab` declarations, which imposed an unexpected alignment constraint on them, and #15020 replaces the coercions between `Array Syntax` and `SepArray` with one from `TSepArray` to `SepArray` that keeps the source information of the separators.

- 
#14890 swaps the names of `Dyadic.not_lt` and `Dyadic.not_le` to match the lemmas for other number types.


[...omitted: full per-PR changelog lists (Language, Library, Compiler, Lake, etc.); selected items follow...]


- 
#14860
makes `invariant`, `decreasing`, and `assert` in a `do` block elaborate without `open Std.WP`, matching the `requires` and `ensures` clauses of a contract.

- 
#14858
removes the match-alternatives form of the `ensures` clause. Except for that, every clause of a contract (`requires`, `ensures`, `assert`, `invariant`, `decreasign`) elaborates like a `fun` telescope, including tuple patterns as in `ensures (lo, hi) => lo ≤ hi`.

- 
#14854
makes the `constructor` tactic emit a warning if multiple constructors match, and adds a `constructor!` tactic that has the previous behavior of silently applying the first matching constructor.

- 
#14845
gives the invariant of a `while` or `repeat` loop its own type, `def Std.WP.WhileInvariant α Pred := Bool → α → Pred`, a predicate over the loop's `exit` flag and the loop state. Previously, it reused `Std.WP.RepeatInvariant α α Pred = α ⊕ α → Pred`, a type which is awkward to use in practice.
#14545
renders `Vector` values using `#v[...]` literal notation instead of exposing their underlying structure representation, making evaluated vectors more concise and readable. It replaces the derived `Repr` instance.

- 
#14953
removes `Lean.reduceBool`, `Lean.reduceNat`, `Lean.ofReduceBool`, `Lean.ofReduceNat` and `Lean.trustCompiler`, along with the kernel's support for reducing applications of the first two by running the compiler. They have been deprecated since 2026-02-01 in favour of asserting native evaluations with axioms, which is what `native_decide` and `bv_decide` already do through `Lean.Meta.nativeEqTrue`. Nothing in the toolchain used them any more.

- 
#14842
refactors the LRAT checker and massively extends the publicly available CNF API in doing so, in particular we:


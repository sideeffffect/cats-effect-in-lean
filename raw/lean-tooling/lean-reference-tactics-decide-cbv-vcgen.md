# Lean reference: Tactic Reference excerpts (grind intro, decide/native_decide, cbv/decide_cbv, VC generation)

> Source: https://lean-lang.org/doc/reference/latest/Tactic-Proofs/Tactic-Reference/
> Collected: 2026-11-10
> Published: Unknown (reference for latest toolchain, fetched 2026-11-10)

## 14.5.12. SMT-Inspired Automation🔗
🔗tactic
grind
`grind` is a tactic inspired by modern SMT solvers. Picture a virtual whiteboard:
every time grind discovers a new equality, inequality, or logical fact,
it writes it on the board, groups together terms known to be equal,
and lets each reasoning engine read from and contribute to the shared workspace.
These engines work together to handle equality reasoning, apply known theorems,
propagate new facts, perform case analysis, and run specialized solvers
for domains like linear arithmetic and commutative rings.
See the reference manual's chapter on `grind` for more information.
`grind` is not designed for goals whose search space explodes combinatorially,
think large pigeonhole instances, graph‑coloring reductions, high‑order N‑queens boards,
or a 200‑variable Sudoku encoded as Boolean constraints.  Such encodings require
thousands (or millions) of case‑splits that overwhelm `grind`’s branching search.
For bit‑level or combinatorial problems, consider using `bv_decide`.
`bv_decide` calls a state‑of‑the‑art SAT solver (CaDiCaL) and then returns a
compact, machine‑checkable certificate.
Equality reasoning
`grind` uses congruence closure to track equalities between terms.
When two terms are known to be equal, congruence closure automatically deduces
equalities between more complex expressions built from them.
For example, if `a = b`, then congruence closure will also conclude that `f a` = `f b`
for any function `f`. This forms the foundation for efficient equality reasoning in `grind`.
Here is an example:
`example (f : Nat → Nat) (h : a = b) : f (f b) = f (f a) := bya:Natb:Natf:Nat → Nath:a = b⊢ f (f b) = f (f a)
grindAll goals completed! 🐙
`
Applying theorems using E-matching
To apply existing theorems, `grind` uses a technique called E-matching,
which finds matches for known theorem patterns while taking equalities into account.
Combined with congruence closure, E-matching helps `grind` discover
non-obvious consequences of theorems and equalities automatically.
Consider the following functions and theorems:
`def f (a : Nat) : Nat :=
a + 1
def g (a : Nat) : Nat :=
a - 1
@[grind =]
theorem gf (x : Nat) : g (f x) = x := byx:Nat⊢ g (f x) = x
simp [f, g]All goals completed! 🐙
`
The theorem `gf` asserts that `g (f x) = x` for all natural numbers `x`.
The attribute `[grind =]` instructs `grind` to use the left-hand side of the equation,
`g (f x)`, as a pattern for E-matching.
Suppose we now have a goal involving:
example {a b} (h : f b = a) : g a = b := by
grind
Although `g a` is not an instance of the pattern `g (f x)`,
it becomes one modulo the equation `f b = a`. By substituting `a`
with `f b` in `g a`, we obtain the term `g (f b)`,
which matches the pattern `g (f x)` with the assignment `x := b`.
Thus, the theorem `gf` is instantiated with `x := b`,
and the new equality `g (f b) = b` is asserted.
`grind` then uses congruence closure to derive the implied equality
`g a = g (f b)` and completes the proof.
The pattern used to instantiate theorems affects the effectiveness of `grind`.
For example, the pattern `g (f x)` is too restrictive in the following case:
the theorem `gf` will not be instantiated because the goal does not even
contain the function symbol `g`.
example (h₁ : f b = a) (h₂ : f c = a) : b = c := by
grind
You can use the command `grind_pattern` to manually select a pattern for a given theorem.
In the following example, we instruct `grind` to use `f x` as the pattern,
allowing it to solve the goal automatically:
grind_pattern gf => f x
example {a b c} (h₁ : f b = a) (h₂ : f c = a) : b = c := by
grind
You can enable the option `trace.grind.ematch.instance` to make `grind` print a
trace message for each theorem instance it generates.
You can also specify a multi-pattern to control when `grind` should apply a theorem.
A multi-pattern requires that all specified patterns are matched in the current context
before the theorem is applied. This is useful for theorems such as transitivity rules,
where multiple premises must be simultaneously present for the rule to apply.
The following example demonstrates this feature using a transitivity axiom for a binary relation `R`:
`opaque R : Int → Int → Prop
axiom Rtrans {x y z : Int} : R x y → R y z → R x z
[...omitted: rest of grind docs, simp, rw, induction, library search...]
## 14.5.18. Decision Procedures🔗
🔗tactic
decide
`decide` attempts to prove the main goal (with target type `p`) by synthesizing an instance of `Decidable p`
and then reducing that instance to evaluate the truth value of `p`.
If it reduces to `isTrue h`, then `h` is a proof of `p` that closes the goal.
The target is not allowed to contain local variables or metavariables.
If there are local variables, you can first try using the `revert` tactic with these local variables to move them into the target,
or you can use the `+revert` option, described below.
Options:
`decide +revert` begins by reverting local variables that the target depends on,
after cleaning up the local context of irrelevant variables.
A variable is relevant if it appears in the target, if it appears in a relevant variable,
or if it is a proposition that refers to a relevant variable.
`decide +kernel` uses kernel for reduction instead of the elaborator.
It has two key properties: (1) since it uses the kernel, it ignores transparency and can unfold everything,
and (2) it reduces the `Decidable` instance only once instead of twice.
`decide +native` uses the native code compiler (`#eval`) to evaluate the `Decidable` instance,
admitting the result via an axiom.
This can be significantly more efficient than using reduction, but it is at the cost of increasing the size
of the trusted code base.
Namely, it depends on the correctness of the Lean compiler and all definitions with an `@[implemented_by]` attribute.
Like with `+kernel`, the `Decidable` instance is evaluated only once.
Limitation: In the default mode or `+kernel` mode, since `decide` uses reduction to evaluate the term,
`Decidable` instances defined by well-founded recursion might not work because evaluating them requires reducing proofs.
Reduction can also get stuck on `Decidable` instances with `Eq.rec` terms.
These can appear in instances defined using tactics (such as `rw` and `simp`).
To avoid this, create such instances using definitions such as `decidable_of_iff` instead.
Examples
Proving inequalities:
`example : 2 + 2 ≠ 5 := by⊢ 2 + 2 ≠ 5 decideAll goals completed! 🐙
`
Trying to prove a false proposition:
example : 1 ≠ 1 := by decide
/-
tactic 'decide' proved that the proposition
1 ≠ 1
is false
-/
Trying to prove a proposition whose `Decidable` instance fails to reduce
opaque unknownProp : Prop
open scoped Classical in
example : unknownProp := by decide
/-
tactic 'decide' failed for proposition
unknownProp
since its 'Decidable' instance reduced to
Classical.choice ⋯
rather than to the 'isTrue' constructor.
-/
Properties and relations
For equality goals for types with decidable equality, usually `rfl` can be used in place of `decide`.
`example : 1 + 1 = 2 := by⊢ 1 + 1 = 2 decideAll goals completed! 🐙
example : 1 + 1 = 2 := by⊢ 1 + 1 = 2 rflAll goals completed! 🐙
`
🔗tactic
native_decide
`native_decide` is a synonym for `decide +native`.
It will attempt to prove a goal of type `p` by synthesizing an instance
of `Decidable p` and then evaluating it to `isTrue ..`. Unlike `decide`, this
uses `#eval` to evaluate the decidability instance.
This should be used with care because it adds the entire lean compiler to the trusted
part, and a new axiom will show up in `#print axioms` for theorems using
this method or anything that transitively depends on them. Nevertheless, because it is
compiled, this can be significantly more efficient than using `decide`, and for very
large computations this is one way to run external programs and trust the result.
`example : (List.range 1000).length = 1000 := by⊢ (List.range 1000).length = 1000 native_decideAll goals completed! 🐙
`
🔗tactic
omega
The `omega` tactic, for resolving integer and natural linear arithmetic problems.
It is not yet a full decision procedure (no "dark" or "grey" shadows),
but should be effective on many problems.
We handle hypotheses of the form `x = y`, `x < y`, `x ≤ y`, and `k ∣ x` for `x y` in `Nat` or `Int`
(and `k` a literal), along with negations of these statements.
We decompose the sides of the inequalities as linear combinations of atoms.
If we encounter `x / k` or `x % k` for literal integers `k` we introduce new auxiliary variables
and the relevant inequalities.
On the first pass, we do not perform case splits on natural subtraction.
If `omega` fails, we recursively perform a case split on
a natural subtraction appearing in a hypothesis, and try again.
The options
omega +splitDisjunctions +splitNatSub +splitNatAbs +splitMinMax
can be used to:
`splitDisjunctions`: split any disjunctions found in the context,
if the problem is not otherwise solvable.
`splitNatSub`: for each appearance of `((a - b : Nat) : Int)`, split on `a ≤ b` if necessary.
`splitNatAbs`: for each appearance of `Int.natAbs a`, split on `0 ≤ a` if necessary.
`splitMinMax`: for each occurrence of `min a b`, split on `min a b = a ∨ min a b = b`
Currently, all of these are on by default.
🔗tactic
bv_omega
`bv_omega` is `omega` with an additional preprocessor that turns statements about `BitVec` into statements about `Nat`.
Currently the preprocessor is implemented as `try simp only [bitvec_to_nat] at *`.
`bitvec_to_nat` is a `@[simp]` attribute that you can (cautiously) add to more theorems.
### 14.5.18.1. SAT Solver Integration🔗
🔗tactic
bv_decide
Close fixed-width `BitVec` and `Bool` goals by obtaining a proof from an external SAT solver and
verifying it inside Lean. The solvable goals are currently limited to
the Lean equivalent of `QF_BV`
automatically splitting up `structure`s that contain information about `BitVec` or `Bool`
`example : ∀ (a b : BitVec 64), (a &&& b) + (a ^^^ b) = a ||| b := by⊢ ∀ (a b : BitVec 64), (a &&& b) + (a ^^^ b) = a ||| b
introsa✝:BitVec 64b✝:BitVec 64⊢ (a✝ &&& b✝) + (a✝ ^^^ b✝) = a✝ ||| b✝
bv_decideAll goals completed! 🐙
`
If `bv_decide` encounters an unknown definition it will be treated like an unconstrained `BitVec`
variable. Sometimes this enables solving goals despite not understanding the definition because
the precise properties of the definition do not matter in the specific proof.
If `bv_decide` fails to close a goal it provides a counter-example, containing assignments for all
terms that were considered as variables.
In order to avoid calling a SAT solver every time, the proof can be cached with `bv_decide?`.
If solving your problem relies inherently on using associativity or commutativity, consider enabling
the `bv.ac_nf` option.
`bv_decide types [T₁, ..., Tₙ]` restricts the analysis of structures and enum inductives to
`T₁, ..., Tₙ`, treating all other ones as opaque variables.
Note: `bv_decide` trusts the correctness of the code generator and adds a axioms asserting its result.
Note: include `import Std.Tactic.BVDecide`
🔗tactic
bv_normalize
Run the normalization procedure of `bv_decide` only. Sometimes this is enough to solve basic
`BitVec` goals already.
Note: include `import Std.Tactic.BVDecide`
🔗tactic
bv_check
This tactic works just like `bv_decide` but skips calling a SAT solver by using a proof that is
already stored on disk. It is called with the name of an LRAT file in the same directory as the
current Lean file:
`bv_check "proof.lrat"`
🔗tactic
bv_decide?
Suggest a proof script for a `bv_decide` tactic call. Useful for caching LRAT proofs.
Note: include `import Std.Tactic.BVDecide`
## 14.5.19. Call-by-Value Evaluation🔗
The `cbv` tactic simulates call-by-value evaluation to reduce terms.
In call-by-value evaluation, the arguments to a function are reduced to values before the function call is reduced.
Roughly speaking, values are either functions or applications of constructors to values; the body of a function does not need to be a value for the function itself to count as a value.
This evaluation strategy matches the execution order of code produced by the Lean compiler, which makes it a good match for code that is written to perform well at run time.
`cbv` unfolds definitions using their equational lemmas and applies similar theorems that are automatically proved for matcher functions, producing propositional equality proofs at each step.
Because the unfolding is propositional rather than definitional, `cbv` can reduce functions defined via well-founded recursion or partial fixpoints.
In general, these functions are not definitionally equal to their unfoldings, so the kernel's definitional reduction does not reduce their recursive calls.
The proofs produced by `cbv` only use the three standard axioms (`propext`, `Quot.sound`, and `Classical.choice`).
In particular, they do not require trust in the correctness of the code generator, unlike `native_decide`.
Because `cbv` rewrites subterms via `congrArg` and `congrFun`, it cannot rewrite subterms that appear in dependent positions.
Rewriting the argument of a dependent function would change the type of subsequent arguments, and even with heterogeneous equality there are no suitable congruence lemmas for arbitrary dependent functions.
When reducing constant applications, `cbv` tries the following strategies in order:
Custom `cbv_eval` rewrite rules
Equational lemmas (e.g., `foo.eq_1`, `foo.eq_2`)
Unfolding equations
Kernel matcher reduction
Declarations marked with `cbv_opaque` are never unfolded unless a matching `cbv_eval` rewrite rule is provided.
syntaxCall-by-Value Evaluation
tactic ::= ...
| ```cbv` performs simplification that closely mimics call-by-value evaluation.
It reduces terms by unfolding definitions using their defining equations and
applying matcher equations. The unfolding is propositional, so `cbv` also works
with functions defined via well-founded recursion or partial fixpoints.
`cbv` reduces the goal type (and optionally hypothesis types) using call-by-value
evaluation. For equation goals (`lhs = rhs`), `cbv` automatically attempts `refl`
after reduction to close the goal.
`cbv` supports the standard `at` location syntax:
- `cbv` — reduce the goal target
- `cbv at h` — reduce hypothesis `h`
- `cbv at h |-` — reduce hypothesis `h` and the goal target
- `cbv at *` — reduce the goal target and all non-dependent propositional hypotheses
If a hypothesis reduces to `False`, the goal is closed immediately.
`cbv` is not a finishing tactic in general: it may leave a new (simpler) goal.
The proofs produced by `cbv` only use the three standard axioms.
In particular, they do not require trust in the correctness of the code
generator.``cbv (``Location specifications are used by many tactics that can operate on either the
hypotheses or the goal. It can have one of the forms:
* 'empty' is not actually present in this syntax, but most tactics use
`(location)?` matchers. It means to target the goal only.
* `at h₁ ... hₙ`: target the hypotheses `h₁`, ..., `hₙ`
* `at h₁ h₂ ⊢`: target the hypotheses `h₁` and `h₂`, and the goal
* `at *`: target all hypotheses and the goal``at ``A sequence of one or more locations at which a tactic should operate. These can include local
hypotheses and `⊢`, which denotes the goal.``(term | ``The `⊢` location refers to the current goal.``locationType)*)?
🔗tactic
cbv
`cbv` performs simplification that closely mimics call-by-value evaluation.
It reduces terms by unfolding definitions using their defining equations and
applying matcher equations. The unfolding is propositional, so `cbv` also works
with functions defined via well-founded recursion or partial fixpoints.
`cbv` reduces the goal type (and optionally hypothesis types) using call-by-value
evaluation. For equation goals (`lhs = rhs`), `cbv` automatically attempts `refl`
after reduction to close the goal.
`cbv` supports the standard `at` location syntax:
`cbv` — reduce the goal target
`cbv at h` — reduce hypothesis `h`
`cbv at h |-` — reduce hypothesis `h` and the goal target
`cbv at *` — reduce the goal target and all non-dependent propositional hypotheses
If a hypothesis reduces to `False`, the goal is closed immediately.
`cbv` is not a finishing tactic in general: it may leave a new (simpler) goal.
The proofs produced by `cbv` only use the three standard axioms.
In particular, they do not require trust in the correctness of the code
generator.
Reducing Well-Founded Recursive Functions
The function `countdown` is defined using well-founded recursion, so it is not definitionally equal to its unfolding.
Ordinary `rfl` cannot close the goal:
`def countdown (n : Nat) : List Nat :=
match n with
| 0 => [0]
| n + 1 => (n + 1) :: countdown n
termination_by n
``example : countdown 3 = [3, 2, 1, 0] := by⊢ countdown 3 = [3, 2, 1, 0] `Tactic `rfl` failed: The left-hand side
countdown 3
is not definitionally equal to the right-hand side
[3, 2, 1, 0]
⊢ countdown 3 = [3, 2, 1, 0]`rfl⊢ countdown 3 = [3, 2, 1, 0]
`
Tactic `rfl` failed: The left-hand side
countdown 3
is not definitionally equal to the right-hand side
[3, 2, 1, 0]
⊢ countdown 3 = [3, 2, 1, 0]
The `cbv` tactic can reduce `countdown 3` via propositional rewriting and then close the equation goal via `rfl`:
`example : countdown 3 = [3, 2, 1, 0] := by⊢ countdown 3 = [3, 2, 1, 0]
cbvAll goals completed! 🐙
`
Live ↪Reducing Hypotheses
The `cbv` tactic supports the standard `at` location syntax.
When used with `at h`, it reduces the type of hypothesis `h`.
When used with `at *`, it reduces all non-dependent propositional
hypotheses and the goal target.
`def countdown (n : Nat) : List Nat :=
match n with
| 0 => [0]
| n + 1 => (n + 1) :: countdown n
termination_by n
``example (x : List Nat) (h : x = countdown 2) :
x = [2, 1, 0] := byx:List Nath:x = countdown 2⊢ x = [2, 1, 0]
cbv at hx:List Nath:x = [2, 1, 0]⊢ x = [2, 1, 0]
exact hAll goals completed! 🐙
`
Live ↪`cbv` as a Non-Finishing Tactic
Unlike `decide`, `cbv` is not a terminal tactic.
It simplifies the goal as much as possible but may leave a goal that requires further reasoning.
Here, `cbv` reduces the call to `countdown` but leaves the membership goal:
`def countdown (n : Nat) : List Nat :=
match n with
| 0 => [0]
| n + 1 => (n + 1) :: countdown n
termination_by n
``example : 1 ∈ countdown 2 := `unsolved goals
⊢ List.Mem 1 [2, 1, 0]`by⊢ 1 ∈ countdown 2
cbv⊢ List.Mem 1 [2, 1, 0]
`
unsolved goals
⊢ List.Mem 1 [2, 1, 0]
Live ↪Dependent Positions
The function `wfLength` is a version of `List.length` that is defined via well-founded recursion instead of structural recursion.
As a result, it is irreducible:
`def wfLength : List Nat → Nat
| [] => 0
| _ :: xs => wfLength xs + 1
termination_by xs => xs
`
In a non-dependent `Std.TreeMap`, `cbv` can reduce the computed key `wfLength [1, 2]`:
`def myTreeMap : Std.TreeMap Nat Nat :=
.empty |>.insert (wfLength [1, 2]) 42
example : myTreeMap.toList = [⟨2, 42⟩] := by⊢ myTreeMap.toList = [(2, 42)]
cbvAll goals completed! 🐙
`
However, consider a dependent tree map `FinMap` that maps each key `n` to a value of type `Fin (n + 1)`:
`abbrev FinMap :=
Std.DTreeMap Nat (fun n => Fin (n + 1))
`
Here `cbv` gets stuck because the value type `Fin (n + 1)` depends on the key:
`example :
let m : FinMap :=
.empty |>.insert (wfLength [1, 2])
⟨0, by⊢ 0 < wfLength [1, 2] + 1 decide_cbvAll goals completed! 🐙⟩
m.toList = [⟨2, ⟨0, bym:FinMap := Std.DTreeMap.empty.insert (wfLength [1, 2]) ⟨0, ⋯⟩⊢ 0 < 2 + 1 omegaAll goals completed! 🐙⟩⟩] := `unsolved goals
⊢ [⟨wfLength [1, 2], ⟨0, ⋯⟩⟩] = [⟨2, ⟨0, ⋯⟩⟩]`by⊢ let m := Std.DTreeMap.empty.insert (wfLength [1, 2]) ⟨0, ⋯⟩;
Std.DTreeMap.toList m = [⟨2, ⟨0, ⋯⟩⟩]
cbv⊢ [⟨wfLength [1, 2], ⟨0, ⋯⟩⟩] = [⟨2, ⟨0, ⋯⟩⟩]
`
unsolved goals
⊢ [⟨wfLength [1, 2], ⟨0, ⋯⟩⟩] = [⟨2, ⟨0, ⋯⟩⟩]
Live ↪
### 14.5.19.1. `decide_cbv`🔗
🔗tactic
decide_cbv
`decide_cbv` is a finishing tactic that closes goals of the form `p`, where `p`
is a `Decidable` proposition. It proceeds in two steps:
Apply `of_decide_eq_true` to transform the goal into `decide p = true`.
Reduce `decide p` via call-by-value normalization. If the result is
definitionally equal to `true`, the goal is closed.
`decide_cbv` fails with an error if `decide p` does not reduce to `true`.
Unlike `cbv`, `decide_cbv` is a terminal tactic: it either closes the goal or
fails.
The proofs produced by `decide_cbv` only use the three standard axioms.
In particular, they do not require trust in the correctness of the code
generator.
`decide_cbv`
The `decide_cbv` tactic closes goals that are decidable propositions by reducing the `Decidable` instance via call-by-value evaluation:
`example : 2 + 3 = 5 ∧ 10 < 20 := by⊢ 2 + 3 = 5 ∧ 10 < 20
decide_cbvAll goals completed! 🐙
`
Unlike `native_decide`, `decide_cbv` does not require trust in the code generator.
Unlike `decide`, which uses definitional reduction, `decide_cbv` can handle functions defined by well-founded recursion:
`def isAllPositive : List Int → Bool
| [] => true
| x :: xs => x > 0 && isAllPositive xs
termination_by xs => xs
example : isAllPositive [1, 2, 3] = true := by⊢ isAllPositive [1, 2, 3] = true
decide_cbvAll goals completed! 🐙
`
Live ↪Prime Power Testing with `decide_cbv`
Because `decide_cbv` uses propositional unfolding, it can evaluate complex decision procedures involving well-founded recursive functions.
Here, `Nat.minFac` finds the smallest divisor of a number, while the helper `minFacAux` searches for the smallest odd divisor:
`def minFacAux (n k : Nat) : Nat :=
if h : n < k * k then n
else
if h' : k ∣ n then k
else
have : k ≤ n := byn:Natk:Nath:¬n < k * kh':¬k ∣ n⊢ k ≤ n
have := Nat.le_mul_self kn:Natk:Nath:¬n < k * kh':¬k ∣ nthis:k ≤ k * k⊢ k ≤ n; grindAll goals completed! 🐙
minFacAux n (k + 2)
termination_by n + 2 - k
def Nat.minFac (n : Nat) : Nat :=
if 2 ∣ n then 2 else minFacAux n 3
`
`Nat.log b n` computes the floor of the base-`b` logarithm of `n` by repeated squaring:
`def Nat.log (b n : Nat) : Nat :=
if b ≤ 1 then 0 else (go b n).2 where
go : Nat → Nat → Nat × Nat
| _, 0 => (n, 0)
| b, fuel + 1 =>
if n < b then (n, 0)
else
let (q, e) := go (b * b) fuel
if q < b then
(q, 2 * e)
else
(q / b, 2 * e + 1)
`
Here, `decide_cbv` can reduce the result of the decision procedure even though there is a free variable `k`:
`example : ¬∃ k,
k ≤ Nat.log 2 15151515151515 ∧
0 < k ∧
15151515151515 =
Nat.minFac 15151515151515 ^ k := by⊢ ¬∃ k, k ≤ Nat.log 2 15151515151515 ∧ 0 < k ∧ 15151515151515 = Nat.minFac 15151515151515 ^ k
decide_cbvAll goals completed! 🐙
`
Live ↪
### 14.5.19.2. Controlling `cbv` Behavior🔗
attributeCustom `cbv` Rewrite Rules
The `cbv_eval` attribute registers a theorem as a custom rewrite rule that `cbv` applies before trying equational lemmas.
The theorem must be an unconditional equality; one side (generally the left-hand side) must be an application of a constant.
attr ::= ...
| ``Register a theorem as a rewrite rule for `cbv` evaluation of a given definition.
You can instruct `cbv` to rewrite the lemma from right-to-left:
```lean
@[cbv_eval ←] theorem my_thm : rhs = lhs := ...
`````cbv_eval
The `←` modifier instructs `cbv` to apply the rule from right to left:
attr ::= ...
| ``Register a theorem as a rewrite rule for `cbv` evaluation of a given definition.
You can instruct `cbv` to rewrite the lemma from right-to-left:
```lean
@[cbv_eval ←] theorem my_thm : rhs = lhs := ...
`````cbv_eval ←
`cbv_eval`
Custom rewrite rules can be used to control how `cbv` evaluates specific functions.
For instance, the naïve definition of reversal, `slowReverse`, has quadratic complexity due to repeated use of `List.append`.
By providing a tail-recursive characterization via `fastReverse`, `cbv` can evaluate `slowReverse` efficiently:
`def slowReverse : List Nat → List Nat
| [] => []
| x :: xs => slowReverse xs ++ [x]
def fastReverse (xs : List Nat) : List Nat :=
go [] xs
where
go (acc : List Nat) : List Nat → List Nat
| [] => acc
| x :: xs => go (x :: acc) xs
theorem reverse_spec_aux (xs acc : List Nat) :
fastReverse.go acc xs =
slowReverse xs ++ acc := byxs:List Natacc:List Nat⊢ fastReverse.go acc xs = slowReverse xs ++ acc
fun_induction fastReverse.gocase1acc✝:List Nat⊢ acc✝ = slowReverse [] ++ acc✝case2acc✝:List Natx✝:Natxs✝:List Natih1✝:fastReverse.go (x✝ :: acc✝) xs✝ = slowReverse xs✝ ++ x✝ :: acc✝⊢ fastReverse.go (x✝ :: acc✝) xs✝ = slowReverse (x✝ :: xs✝) ++ acc✝
<;>case1acc✝:List Nat⊢ acc✝ = slowReverse [] ++ acc✝case2acc✝:List Natx✝:Natxs✝:List Natih1✝:fastReverse.go (x✝ :: acc✝) xs✝ = slowReverse xs✝ ++ x✝ :: acc✝⊢ fastReverse.go (x✝ :: acc✝) xs✝ = slowReverse (x✝ :: xs✝) ++ acc✝ grind [slowReverse]All goals completed! 🐙
@[cbv_eval] theorem slowReverse_cbv
(xs : List Nat) :
slowReverse xs = fastReverse xs := byxs:List Nat⊢ slowReverse xs = fastReverse xs
simp [fastReverse, reverse_spec_aux]All goals completed! 🐙
``example : slowReverse [1, 2, 3, 4, 5] = [5, 4, 3, 2, 1] := by⊢ slowReverse [1, 2, 3, 4, 5] = [5, 4, 3, 2, 1]
cbvAll goals completed! 🐙
`
Live ↪
attributeOpaque Declarations for `cbv`
The `cbv_opaque` attribute prevents `cbv` from unfolding a declaration using its equational lemmas or unfold theorems.
However, `cbv_eval` rewrite rules always take priority over `cbv_opaque`: if a matching `cbv_eval` rule exists for a declaration, it will be applied even if the declaration is marked `cbv_opaque`.
This allows replacing the default unfolding behavior with a controlled set of evaluation rules.
attr ::= ...
| cbv_opaque
Opaque Definitions with `@[cbv_opaque]`
Marking `countdown` as `cbv_opaque` prevents `cbv` from unfolding it, so the goal that was previously closed by `cbv` now remains unsolved:
`def countdown (n : Nat) : List Nat :=
match n with
| 0 => [0]
| n + 1 => (n + 1) :: countdown n
termination_by n
``attribute [cbv_opaque] countdown
``example : countdown 3 = [3, 2, 1, 0] := `unsolved goals
⊢ countdown 3 = [3, 2, 1, 0]`by⊢ countdown 3 = [3, 2, 1, 0]
cbv⊢ countdown 3 = [3, 2, 1, 0]
`
unsolved goals
⊢ countdown 3 = [3, 2, 1, 0]
Live ↪
#### 14.5.19.2.1. Custom Simplification Procedures🔗
A cbv simplification procedure (`cbv` simproc) is a user-defined metaprogram that `cbv` invokes on subexpressions matching a given pattern.
While `cbv_eval` rules are limited to static equality, `cbv` simprocs can perform arbitrary computation to decide how to rewrite a subexpression.
Common use cases include defining procedures for evaluating functions on literal values or short-circuiting control flow.
The simprocs used by `cbv` have type `Lean.Meta.Sym.Simp.Simproc`, which is distinct from the `Lean.Meta.Simp.Simproc` type used by the `simp` tactic.
The two systems are independent: registering a `cbv` simproc has no effect on `simp`, and vice versa.
syntaxCustom `cbv` Simplification Procedures
The body must have type `Simproc` (that is, `Expr → SimpM Result`).
The pattern is an expression with holes (`_`) that determines which subexpressions trigger the procedure.
Patterns are matched agains subexpressions structurally after unfolding reducible definitions and applying β-, η-, and ζ-reduction to both sides.
Matching is modulo α-equivalence (bound variable names are ignored), and proof and instance arguments in the pattern are treated as wildcards.
An optional phase specifier controls when the procedure fires during normalization.
When no phase is specified, the default is `↑` (post).
`↓` (pre)
Fires on each subexpression before `cbv` reduces it. The arguments are still unreduced. Use this phase to override `cbv`'s default call-by-value evaluation order. A typical use case would be to evaluate arguments lazily or to short-circuit evaluation (as the built-in `ite` and `Or` procedures do).
`cbv_eval` (eval)
Fires after arguments have been reduced to values, but before the function is unfolded. Use this phase to provide efficient ground evaluation procedures.
`↑` (post, default)
Fires after `cbv` has attempted standard reduction (equation lemmas, unfolding, kernel matching). Use this phase when standard reduction should be tried first.
command ::= ...
| ``A user-defined simplification procedure used by the `cbv` tactic.
The body must have type `Lean.Meta.Sym.Simp.Simproc` (`Expr → SimpM Result`).
Procedures are indexed by a discrimination tree pattern and fire at one of three phases:
`↓` (pre), `cbv_eval` (eval), or `↑` (post, default).`````attrKind` matches `("scoped" <|> "local")?`, used before an attribute like `@[local simp]`.``cbv_simproc name (pattern) := body
An optional phase specifier can be placed before the name:
command ::= ...
| ``A user-defined simplification procedure used by the `cbv` tactic.
The body must have type `Lean.Meta.Sym.Simp.Simproc` (`Expr → SimpM Result`).
Procedures are indexed by a discrimination tree pattern and fire at one of three phases:
`↓` (pre), `cbv_eval` (eval), or `↑` (post, default).`````attrKind` matches `("scoped" <|> "local")?`, used before an attribute like `@[local simp]`.``cbv_simproc ``Use this rewrite rule before entering the subterms``↓ name (pattern) := body
command ::= ...
| ``A user-defined simplification procedure used by the `cbv` tactic.
The body must have type `Lean.Meta.Sym.Simp.Simproc` (`Expr → SimpM Result`).
Procedures are indexed by a discrimination tree pattern and fire at one of three phases:
`↓` (pre), `cbv_eval` (eval), or `↑` (post, default).`````attrKind` matches `("scoped" <|> "local")?`, used before an attribute like `@[local simp]`.``cbv_simproc cbv_eval name (pattern) := body
The `cbv_simproc_decl` variant declares the procedure without activating it.
It can be activated later with `cbv_simproc`.
command ::= ...
| ``A `cbv_simproc` declaration without automatically adding it to the cbv simproc set.
To activate, use `attribute [cbv_simproc]`.``cbv_simproc_decl name (pattern) := body
attributeSimplification Procedure Attribute for `cbv`
The `cbv_simproc` attribute activates a previously declared simplification procedure (defined with `cbv_simproc_decl`) for use by `cbv`.
An optional phase specifier controls when the procedure fires during normalization.
attr ::= ...
| cbv_simproc
Phase specifiers control when the procedure fires:
attr ::= ...
| cbv_simproc ``Use this rewrite rule before entering the subterms``↓
attr ::= ...
| cbv_simproc ``Use this rewrite rule after entering the subterms``↑
attr ::= ...
| cbv_simproc cbv_eval
Declaring a `cbv_simproc`
A simplification procedure is declared by providing a pattern and a body of type `Lean.Meta.Sym.Simp.Simproc`.
The pattern is an expression with holes (`_`) that determines which subexpressions trigger the procedure.
Here, the pattern is (`myConst _`), which matches any application of `myConst`.
The procedure (`fun _e => do return .rfl`) ignores the expression, returning a result that indicates that no rewriting is to be performed.
`opaque myConst : Nat → Nat
open Lean Meta Sym.Simp in
cbv_simproc evalMyConst (myConst _) := fun _e => do
-- A real simproc would inspect `e`, compute a result,
-- and return `.step result proof`.
return .rfl
`
The ``Lean.Parser.«command_Cbv_simproc_decl_(_):=_» : command``A `cbv_simproc` declaration without automatically adding it to the cbv simproc set.
To activate, use `attribute [cbv_simproc]`.```cbv_simproc_decl` variant declares the procedure without activating it.
The `cbv_simproc` attribute can be used to activate it later, optionally at a specific phase:
`open Lean Meta Sym.Simp in
cbv_simproc_decl evalMyConst2 (myConst _) := fun _e =>
return .rfl
attribute [cbv_simproc cbv_eval] evalMyConst2
`
Live ↪Lazy evaluation of a head of the list
This is an example of a pre-phase simplification procedure that breaks the conventional call-by-value order of evaluation to achieve laziness.
The `↓` modifier ensures that `evalListHead` fires before the arguments to `List.head?` are evaluated.
It rewrites `List.head? (a :: as)` to `some a` using `List.head?_cons`, discarding the tail `as` without evaluating it.
Only the head element `a` is subsequently reduced by `cbv`.
`cbv_simproc ↓ evalListHead (List.head? _) := fun e => do
let_expr List.head? α listExpr := e | return .rfl
let_expr List.cons _ a as := listExpr | return .rfl
let Level.succ u ← Sym.getLevel α | return .rfl
let result ← Sym.share <| mkApp2 (mkConst ``Option.some [u]) α a
let proof := mkApp3 (mkConst ``List.head?_cons [u]) α a as
return .step result proof
theorem cbv_simproc_test : [5 + 5,6].head? = .some 10 := by⊢ [5 + 5, 6].head? = some 10 cbvAll goals completed! 🐙
`
Inspecting the proof term confirms that the simplification procedure fired: `List.head?_cons` appears directly in the proof, showing that `cbv` used the simproc's rewrite rather than reducing `List.head?` by unfolding its definition.
theorem cbv_simproc_test : [5 + 5, 6].head? = some 10 :=
of_eq_true
(Eq.trans (congrFun' (congrArg Eq (Eq.trans List.head?_cons (congrArg some (Eq.refl 10)))) (some 10))
(eq_self (some 10)))
Live ↪
Lean includes a number of built-in simplification procedures for `cbv`.
These handle control flow (`ite`, `dite`, `cond`, `Decidable.decide`, `Decidable.rec`), logical connectives (`Or`, `And`), and data structure operations (array indexing, string operations).
The control flow procedures use the `↓` (pre) phase to enable short-circuit evaluation, while the array and string procedures use the `cbv_eval` phase to reduce ground applications directly.
### 14.5.19.3. Options🔗
🔗option
cbv.maxSteps
Default value: `100000`
Controls the maximum number of steps for the `cbv` tactic.
🔗option
cbv.warning
Default value: `false`
When enabled, displays a warning that the `cbv` tactic is being used.
## 14.5.20. Controlling Reduction🔗
🔗tactic
with_reducible
[...omitted: reduction control, control flow, debugging, suggestions...]
## 14.5.26. Verification Condition Generation🔗
🔗tactic
mvcgen
`mvcgen` will break down a Hoare triple proof goal like `⦃P⦄ prog ⦃Q⦄` into verification conditions,
provided that all functions used in `prog` have specifications registered with `@[spec]`.
`mvcgen` is deprecated in favor of `vcgen`.
Verification Conditions and specifications
A verification condition is an entailment in the stateful logic of `Std.Do.SPred`
in which the original program `prog` no longer occurs.
Verification conditions are introduced by the `mspec` tactic; see the `mspec` tactic for what they
look like.
When there's no applicable `mspec` spec, `mvcgen` will try and rewrite an application
`prog = f a b c` with the simp set registered via `@[spec]`.
Features
When used like `mvcgen +noLetElim [foo_spec, bar_def, instBEqFloat]`, `mvcgen` will additionally
add a Hoare triple specification `foo_spec : ... → ⦃P⦄ foo ... ⦃Q⦄` to `spec` set for a
function `foo` occurring in `prog`,
unfold a definition `def bar_def ... := ...` in `prog`,
unfold any method of the `instBEqFloat : BEq Float` instance in `prog`.
it will no longer substitute away `let`-expressions that occur at most once in `P`, `Q` or `prog`.
Config options
`+noLetElim` is just one config option of many. Check out `Lean.Elab.Tactic.Do.VCGen.Config` for all
options. Of particular note is `stepLimit = some 42`, which is useful for bisecting bugs in
`mvcgen` and tracing its execution.
Extended syntax
Often, `mvcgen` will be used like this:
mvcgen [...]
case inv1 => exact I1
case inv2 => exact I2
all_goals (mleave; try grind)
There is special syntax for this:
mvcgen [...] invariants
· I1
· I2
with grind
When `I1` and `I2` need to refer to inaccessibles (`mvcgen` will introduce a lot of them for program
variables), you can use case label syntax:
mvcgen [...] invariants
| inv1 _ acc _ => I1 acc
| _ => I2
with grind
This is more convenient than the equivalent `· by rename_i _ acc _; exact I1 acc`.
Invariant suggestions
`mvcgen` will suggest invariants for you if you use the `invariants?` keyword.
mvcgen [...] invariants?
This is useful if you do not recall the exact syntax to construct invariants.
Furthermore, it will suggest a concrete invariant encoding "this holds at the start of the loop and
this must hold at the end of the loop" by looking at the corresponding VCs.
Although the suggested invariant is a good starting point, it is too strong and requires users to
interpolate it such that the inductive step can be proved. Example:
def mySum (l : List Nat) : Nat := Id.run do
let mut acc := 0
for x in l do
acc := acc + x
return acc
/--
info: Try this:
invariants
· ⇓⟨xs, letMuts⟩ => ⌜xs.prefix = [] ∧ letMuts = 0 ∨ xs.suffix = [] ∧ letMuts = l.sum⌝
-/
#guard_msgs (info) in
theorem mySum_suggest_invariant (l : List Nat) : mySum l = l.sum := by
generalize h : mySum l = r
apply Id.of_wp_run_eq h
mvcgen invariants?
all_goals admit
🔗tactic
vcgen
`vcgen` will break down a Hoare triple proof goal like `⦃P⦄ prog ⦃Q⦄` into verification conditions,
provided that all functions used in `prog` have specifications registered with `@[spec]`.
`vcgen` is experimental and subject to change. `set_option experimental.vcgen true` acknowledges
its experimental status and silences the warning that each call reports.
Program types
`vcgen` works on any program type `Prog` that carries a `Std.WP.WP` interpretation. A monad
is one such program type. An inductive type of commands is another, once its weakest precondition is
defined in terms of an operational semantics.
Verification conditions and specifications
A verification condition is an entailment `pre ⊑ post` in the assertion lattice of the goal. The
original program `prog` no longer occurs in it. The assertion lattice is any `CompleteLattice`, and
the entailment is its order, so a verification condition is an ordinary Lean goal that `grind` can
attack.
A `@[spec]` theorem declares a specification in one of two forms. A Hoare triple
`foo_spec : ⦃P⦄ foo a b c ⦃Q⦄` states it directly. An equation `baz_eq : baz a b c = ...` states it
by rewriting.
Features
When used like `vcgen [foo_spec, bar_def, baz_eq]`, `vcgen` will additionally
add a Hoare triple specification `foo_spec : ⦃P⦄ foo ... ⦃Q⦄` to the `spec` set for a function
`foo` occurring in `prog`,
unfold a definition `def bar_def ... := ...` in `prog`,
rewrite with an equational specification `baz_eq : baz ... = ...` in `prog`.
Config options
See `Lean.Elab.Tactic.Do.VCGen.Config` for the options. Of particular note are `stepLimit = some 42`,
which is useful for bisecting bugs and tracing execution, and `errorOnMissingSpec := false`, which
leaves a goal whose head has no matching spec as a verification condition for you to discharge.
Extended syntax
Often, `vcgen` will be used like this:
vcgen [...] invariants
· I1
· I2
with try finish
The `with` clause takes one step of `grind` mode, such as `finish`. That step shares the E-graph that
`vcgen` builds, so it sees the hypotheses of every verification condition. A sequence of steps needs
explicit grouping, as in `with (s₁; s₂)`.
Invariants also take a labelled form, which is useful for naming inaccessibles:
vcgen [...] invariants
| inv1 _ acc _ => I1 acc
| _ => I2
`vcgen` has two further clauses.
vcgen until f a _ c
stops VC generation at the first program that matches the pattern, and leaves that program in the
goal. Holes are written `_`, as in `conv in`.
vcgen frames
| f a _ c => F
supplies a frame for a call. Take `mkFreshNat : StateM (Nat × Nat) Nat`, which returns `s.1` and
increments it. Its specification mentions `s.1` alone:
@[spec] theorem mkFreshNat_spec :
⦃fun s => ⌜s.1 = n⌝⦄ mkFreshNat ⦃fun r s => ⌜r = n ∧ s.1 = n + 1⌝⦄
A caller that knows `s.2 = 7` loses that fact at the call, because the postcondition says nothing
about `s.2`. Writing
vcgen frames
| mkFreshNat => fun s => ⌜s.2 = 7⌝
carries `s.2 = 7` past the call, and `vcgen` proves that `mkFreshNat` preserves it. The named binders
are in scope in the frame, bound to the matched arguments.
Invariant suggestions
`vcgen [...] invariants?` warns that invariant suggestions are not available in `vcgen` and that
the keyword is slated for removal. Alternatives after `invariants?` elaborate like `invariants`.
### 14.5.26.1. Tactics for Stateful Goals in `Std.Do.SPred`🔗
#### 14.5.26.1.1. Starting and Stopping the Proof Mode🔗
🔗tactic
mstart
Start the stateful proof mode of `Std.Do.SPred`.
This will transform a stateful goal of the form `H ⊢ₛ T` into `⊢ₛ H → T`
upon which `mintro` can be used to re-introduce `H` and give it a name.
It is often more convenient to use `mintro` directly, which will
try `mstart` automatically if necessary.
🔗tactic
mstop
Stops the stateful proof mode of `Std.Do.SPred`.
This will simply forget all the names given to stateful hypotheses and pretty-print
a bit differently.
🔗tactic
mleave
Leaves the stateful proof mode of `Std.Do.SPred`, tries to eta-expand through all definitions
related to the logic of the `Std.Do.SPred` and gently simplifies the resulting pure Lean
proposition. This is often the right thing to do after `mvcgen` in order for automation to prove
the goal.
#### 14.5.26.1.2. Proving a Stateful Goal🔗
🔗tactic
mspec
`mspec` is an `apply`-like tactic that applies a Hoare triple specification to the target of the
stateful goal.
Given a stateful goal `H ⊢ₛ wp⟦prog⟧ Q'`, `mspec foo_spec` will instantiate
`foo_spec : ... → ⦃P⦄ foo ⦃Q⦄`, match `foo` against `prog` and produce subgoals for
the verification conditions `?pre : H ⊢ₛ P` and `?post : Q ⊢ₚ Q'`.
If `prog = x >>= f`, then `mspec Specs.bind` is tried first so that `foo` is matched against `x`
instead. Tactic `mspec_no_bind` does not attempt to do this decomposition.
If `?pre` or `?post` follow by `.rfl`, then they are discharged automatically.
`?post` is automatically simplified into constituent `⊢ₛ` entailments on
success and failure continuations.
`?pre` and `?post.*` goals introduce their stateful hypothesis under an inaccessible name.
You can give it a name with the `mrename_i` tactic.
Any uninstantiated MVar arising from instantiation of `foo_spec` becomes a new subgoal.
If the target of the stateful goal looks like `fun s => _` then `mspec` will first `mintro ∀s`.
If `P` has schematic variables that can be instantiated by doing `mintro ∀s`, for example
`foo_spec : ∀(n:Nat), ⦃fun s => ⌜n = s⌝⦄ foo ⦃Q⦄`, then `mspec` will do `mintro ∀s` first to
instantiate `n = s`.
Right before applying the spec, the `mframe` tactic is used, which has the following effect:
Any hypothesis `Hᵢ` in the goal `h₁:H₁, h₂:H₂, ..., hₙ:Hₙ ⊢ₛ T` that is
pure (i.e., equivalent to some `⌜φᵢ⌝`) will be moved into the pure context as `hᵢ:φᵢ`.
Additionally, `mspec` can be used without arguments or with a term argument:
`mspec` without argument will try and look up a spec for `x` registered with `@[spec]`.
`mspec (foo_spec blah ?bleh)` will elaborate its argument as a term with expected type
`⦃?P⦄ x ⦃?Q⦄` and introduce `?bleh` as a subgoal.
This is useful to pass an invariant to e.g., `Specs.forIn_list` and leave the inductive step
as a hole.
🔗tactic
mintro
Like `intro`, but introducing stateful hypotheses into the stateful context of the `Std.Do.SPred`
proof mode.
That is, given a stateful goal `(hᵢ : Hᵢ)* ⊢ₛ P → T`, `mintro h` transforms
into `(hᵢ : Hᵢ)*, (h : P) ⊢ₛ T`.
Furthermore, `mintro ∀s` is like `intro s`, but preserves the stateful goal.
That is, `mintro ∀s` brings the topmost state variable `s:σ` in scope and transforms
`(hᵢ : Hᵢ)* ⊢ₛ T` (where the entailment is in `Std.Do.SPred (σ::σs)`) into
`(hᵢ : Hᵢ s)* ⊢ₛ T s` (where the entailment is in `Std.Do.SPred σs`).
Beyond that, `mintro` supports the full syntax of `mcases` patterns
(`mintro pat = (mintro h; mcases h with pat`), and can perform multiple
introductions in sequence.
🔗tactic
mexact
`mexact` is like `exact`, but operating on a stateful `Std.Do.SPred` goal.
example (Q : SPred σs) : Q ⊢ₛ Q := by
mstart
mintro HQ
mexact HQ
🔗tactic
massumption
`massumption` is like `assumption`, but operating on a stateful `Std.Do.SPred` goal.
example (P Q : SPred σs) : Q ⊢ₛ P → Q := by
mintro _ _
massumption
🔗tactic
mrefine
Like `refine`, but operating on stateful `Std.Do.SPred` goals.
example (P Q R : SPred σs) : (P ∧ Q ∧ R) ⊢ₛ P ∧ R := by
mintro ⟨HP, HQ, HR⟩
mrefine ⟨HP, HR⟩
example (ψ : Nat → SPred σs) : ψ 42 ⊢ₛ ∃ x, ψ x := by
mintro H
mrefine ⟨⌜42⌝, H⟩
🔗tactic
mconstructor
`mconstructor` is like `constructor`, but operating on a stateful `Std.Do.SPred` goal.
example (Q : SPred σs) : Q ⊢ₛ Q ∧ Q := by
mintro HQ
mconstructor <;> mexact HQ
🔗tactic
mleft
`mleft` is like `left`, but operating on a stateful `Std.Do.SPred` goal.
example (P Q : SPred σs) : P ⊢ₛ P ∨ Q := by
mintro HP
mleft
mexact HP
🔗tactic
mright
`mright` is like `right`, but operating on a stateful `Std.Do.SPred` goal.
example (P Q : SPred σs) : P ⊢ₛ Q ∨ P := by
mintro HP
mright
mexact HP
🔗tactic
mexists
`mexists` is like `exists`, but operating on a stateful `Std.Do.SPred` goal.
example (ψ : Nat → SPred σs) : ψ 42 ⊢ₛ ∃ x, ψ x := by
mintro H
mexists 42
🔗tactic
mpure_intro
`mpure_intro` operates on a stateful `Std.Do.SPred` goal of the form `P ⊢ₛ ⌜φ⌝`.
It leaves the stateful proof mode (thereby discarding `P`), leaving the regular goal `φ`.
theorem simple : ⊢ₛ (⌜True⌝ : SPred σs) := by
mpure_intro
exact True.intro
🔗tactic
mexfalso
`mexfalso` is like `exfalso`, but operating on a stateful `Std.Do.SPred` goal.
example (P : SPred σs) : ⌜False⌝ ⊢ₛ P := by
mintro HP
mexfalso
mexact HP
#### 14.5.26.1.3. Manipulating Stateful Hypotheses🔗
🔗tactic
mclear
`mclear` is like `clear`, but operating on a stateful `Std.Do.SPred` goal.
example (P Q : SPred σs) : P ⊢ₛ Q → Q := by
mintro HP
mintro HQ
mclear HP
mexact HQ
🔗tactic
mdup
Duplicate a stateful `Std.Do.SPred` hypothesis.
🔗tactic
mhave
`mhave` is like `have`, but operating on a stateful `Std.Do.SPred` goal.
example (P Q : SPred σs) : P ⊢ₛ (P → Q) → Q := by
mintro HP HPQ
mhave HQ : Q := by mspecialize HPQ HP; mexact HPQ
mexact HQ
🔗tactic
mreplace
`mreplace` is like `replace`, but operating on a stateful `Std.Do.SPred` goal.
example (P Q : SPred σs) : P ⊢ₛ (P → Q) → Q := by
mintro HP HPQ
mreplace HPQ : Q := by mspecialize HPQ HP; mexact HPQ
mexact HPQ
🔗tactic
mspecialize
`mspecialize` is like `specialize`, but operating on a stateful `Std.Do.SPred` goal.
It specializes a hypothesis from the stateful context with hypotheses from either the pure
or stateful context or pure terms.
example (P Q : SPred σs) : P ⊢ₛ (P → Q) → Q := by
mintro HP HPQ
mspecialize HPQ HP
mexact HPQ
example (y : Nat) (P Q : SPred σs) (Ψ : Nat → SPred σs) (hP : ⊢ₛ P) : ⊢ₛ Q → (∀ x, P → Q → Ψ x) → Ψ (y + 1) := by
mintro HQ HΨ
mspecialize HΨ (y + 1) hP HQ
mexact HΨ
🔗tactic
mspecialize_pure
`mspecialize_pure` is like `mspecialize`, but it specializes a hypothesis from the
pure context with hypotheses from either the pure or stateful context or pure terms.
example (y : Nat) (P Q : SPred σs) (Ψ : Nat → SPred σs) (hP : ⊢ₛ P) (hΨ : ∀ x, ⊢ₛ P → Q → Ψ x) : ⊢ₛ Q → Ψ (y + 1) := by
mintro HQ
mspecialize_pure (hΨ (y + 1)) hP HQ => HΨ
mexact HΨ
🔗tactic
mcases
Like `rcases`, but operating on stateful `Std.Do.SPred` goals.
Example: Given a goal `h : (P ∧ (Q ∨ R) ∧ (Q → R)) ⊢ₛ R`,
`mcases h with ⟨-, ⟨hq | hr⟩, hqr⟩` will yield two goals:
`(hq : Q, hqr : Q → R) ⊢ₛ R` and `(hr : R) ⊢ₛ R`.
That is, `mcases h with pat` has the following semantics, based on `pat`:
`pat=□h'` renames `h` to `h'` in the stateful context, regardless of whether `h` is pure
`pat=⌜h'⌝` introduces `h' : φ`  to the pure local context if `h : ⌜φ⌝`
(c.f. `Lean.Elab.Tactic.Do.ProofMode.IsPure`)
`pat=h'` is like `pat=⌜h'⌝` if `h` is pure
(c.f. `Lean.Elab.Tactic.Do.ProofMode.IsPure`), otherwise it is like `pat=□h'`.
`pat=_` renames `h` to an inaccessible name
`pat=-` discards `h`
`⟨pat₁, pat₂⟩` matches on conjunctions and existential quantifiers and recurses via
`pat₁` and `pat₂`.
`⟨pat₁ | pat₂⟩` matches on disjunctions, matching the left alternative via `pat₁` and the right
alternative via `pat₂`.
🔗tactic
mrename_i
`mrename_i` is like `rename_i`, but names inaccessible stateful hypotheses in a `Std.Do.SPred` goal.
🔗tactic
mpure
`mpure` moves a pure hypothesis from the stateful context into the pure context.
example (Q : SPred σs) (ψ : φ → ⊢ₛ Q): ⌜φ⌝ ⊢ₛ Q := by
mintro Hφ
mpure Hφ
mexact (ψ Hφ)
🔗tactic
mframe
`mframe` infers which hypotheses from the stateful context can be moved into the pure context.
This is useful because pure hypotheses "survive" the next application of modus ponens
(`Std.Do.SPred.mp`) and transitivity (`Std.Do.SPred.entails.trans`).
It is used as part of the `mspec` tactic.
example (P Q : SPred σs) : ⊢ₛ ⌜p⌝ ∧ Q ∧ ⌜q⌝ ∧ ⌜r⌝ ∧ P ∧ ⌜s⌝ ∧ ⌜t⌝ → Q := by
mintro _
mframe
/- `h : p ∧ q ∧ r ∧ s ∧ t` in the pure context -/
mcases h with hP
mexact h

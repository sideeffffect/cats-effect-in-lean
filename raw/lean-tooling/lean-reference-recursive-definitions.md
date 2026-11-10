# Lean reference: Recursive Definitions (partial_fixpoint, coinductive predicates, partial)

> Source: https://lean-lang.org/doc/reference/latest/Definitions/Recursive-Definitions/
> Collected: 2026-11-10
> Published: Unknown (reference for latest toolchain, fetched 2026-11-10)

# 7.6. Recursive Definitions🔗

Allowing arbitrary recursive function definitions would make Lean's logic inconsistent.
General recursion makes it possible to write circular proofs: “proposition `P` is true because proposition `P` is true”.
Outside of proofs, an infinite loop could be assigned the type `Empty`, which can be used with ``Lean.Parser.Term.nomatch : term``Empty match/ex falso. `nomatch e` is of arbitrary type `α : Sort u` if
Lean can show that an empty set of patterns is exhaustive given `e`'s type,
e.g. because it has no constructors.```nomatch` or `Empty.rec` to prove any theorem.

Banning recursive function definitions outright would render Lean far less useful: inductive types are key to defining both predicates and data, and they have a recursive structure.
Furthermore, most useful recursive functions do not threaten soundness, and infinite loops usually indicate mistakes in definitions rather than intentional behavior.
Instead of banning recursive functions, Lean requires that each recursive function is defined safely.
While elaborating recursive definitions, the Lean elaborator also produces a justification that the function being defined is safe.Marginal noteShow marginal noteThe section on the elaborator's output in the overview of elaboration contextualizes the elaboration of recursive definitions in the overall context of the elaborator.

There are six main kinds of recursive functions that can be defined:
Structurally recursive functions
Structurally recursive functions take an argument such that the function makes recursive calls only on strict sub-components of said argument.Marginal noteShow marginal noteStrictly speaking, arguments whose types are indexed families are grouped together with their indices, with the whole collection considered as a unit.
The elaborator translates the recursion into uses of the argument's recursor.
Because every type-correct use of a recursor is guaranteed to avoid infinite regress, this translation is evidence that the function terminates.
Applications of functions defined via recursors are definitionally equal to the result of the recursion, and are typically relatively efficient inside the kernel.
Recursion over well-founded relations
Many functions are also difficult to convert to structural recursion; for instance, a function may terminate because the difference between an array index and the size of the array decreases as the index increases, but `Nat.rec` isn't applicable because the index that increases is the function's argument.
Here, there is a measure of termination that decreases at each recursive call, but the measure is not itself an argument to the function.
In these cases, well-founded recursion can be used to define the function.
Well-founded recursion is a technique for systematically transforming recursive functions with a decreasing measure into recursive functions over proofs that every sequence of reductions to the measure eventually terminates at a minimum.
Applications of functions defined via well-founded recursion are not necessarily definitionally equal to their return values, but this equality can be proved as a proposition.
Even when definitional equalities exist, these functions are frequently slow to compute with because they require reducing proof terms that are often very large.
Recursive functions as partial fixpoints
The definition of a function can be understood as an equation that specifies its behavior.
In certain cases, the existence of a function that satisfies this specification can be proven even when the recursive function does not necessarily terminate for all inputs.
This strategy is even applicable in some cases where the function definition does not necessarily terminate for all inputs.
These partial functions emerge as fixed points of these equations are called partial fixpoints.

In particular, any function whose return type is in certain monads (e.g. `Option`) can be defined using this strategy.
Lean generates additional partial correctness theorems for these monadic functions.
As with well-founded recursion, applications of functions defined as partial fixpoints are not definitionally equal to their return values, but Lean generates theorems that propositionally equate the function to its unfolding and to the reduction behavior specified in its definition.
Coinductive and inductive predicates as fixpoints
Recursive `Prop`-valued functions can be defined as greatest or least fixpoints of monotone operators on complete lattices.
Coinductive predicates, defined using ``Lean.Parser.Command.declaration : command```coinductive_fixpoint` or the ``Lean.Parser.Command.declaration : command```coinductive` command, describe potentially infinite behavior such as infinite sequences or bisimulation.
Inductive predicates, defined using ``Lean.Parser.Command.declaration : command```inductive_fixpoint`, provide an alternative to standard inductive types that is compatible with mixed inductive-coinductive mutual blocks.
Partial functions with nonempty codomains
For many applications, it's not important to reason about the implementation of certain functions.
A recursive function might be used only as part of the implementation of proof automation steps, or it might be an ordinary program that will never be formally proved correct.
In these cases, the Lean kernel does not need either definitional or propositional equalities to hold for the definition; it suffices that soundness is maintained.
Functions marked ``Lean.Parser.Command.declaration : command```partial` are treated as opaque constants by the kernel and are neither unfolded nor reduced.
All that is required for soundness is that their return type is inhabited.
Partial functions may still be used in compiled code as usual, and they may appear in propositions and proofs; their equational theory in Lean's logic is simply very weak.
Unsafe recursive definitions
Unsafe definitions have none of the restrictions of partial definitions.
They may freely make use of general recursion, and they may use features of Lean that break assumptions about its equational theory, such as primitives for casting (`unsafeCast`), checking pointer equality (`ptrAddrUnsafe`), and observing reference counts (`isExclusiveUnsafe`).
However, any declaration that refers to an unsafe definition must itself be marked ``Lean.Parser.Command.declaration : command```unsafe`, making it clear when logical soundness is not guaranteed.
Unsafe operations can be used to replace the implementations of other functions with more efficient variants in compiled code, while the kernel still uses the original definition.
The replaced function may be opaque, which results in the function name having a trivial equational theory in the logic, or it may be an ordinary function, in which case the function is used in the logic.
Use this feature with care: logical soundness is not at risk, but the behavior of programs written in Lean may diverge from their verified logical models if the unsafe implementation is incorrect.

As described in the overview of the elaborator's output, elaboration of recursive functions proceeds in two phases:

- 
The definition is elaborated as if Lean's core type theory had recursive definitions.
Aside from using recursion, this provisional definition is fully elaborated.
The compiler generates code from these provisional definitions.

- 
A termination analysis attempts to use the five techniques to justify the function to Lean's kernel.
If the definition is marked ``Lean.Parser.Command.declaration : command```unsafe` or ``Lean.Parser.Command.declaration : command```partial`, then that technique is used.
If an explicit ``Lean.Parser.Command.declaration : command```termination_by`, ``Lean.Parser.Command.declaration : command```partial_fixpoint`, ``Lean.Parser.Command.declaration : command```coinductive_fixpoint`, or ``Lean.Parser.Command.declaration : command```inductive_fixpoint` clause is present, then the indicated technique is the only one attempted.
If there is no such clause, then the elaborator performs a search, testing each parameter to the function as a candidate for structural recursion, and attempting to find a measure with a well-founded relation that decreases at each recursive call.

This section describes the rules that govern recursive functions.
After a description of mutual recursion, each of the five kinds of recursive definitions is specified, along with the tradeoffs between reasoning power and flexibility that go along with each.

[...omitted: 7.6.1–7.6.3 mutual, structural and well-founded recursion details...]
## 7.6.4. Partial Fixpoint Recursion🔗

All definitions are fundamentally equations: the new constant being defined is equal to the right-hand side of the definition.
For functions defined by structural recursion, this equation holds definitionally, and there is a unique value returned by application of the function.
For functions defined by well-founded recursion, the equation may hold only propositionally, but all type-correct applications of the function to arguments are equal to the respective values prescribed by the definition.
In both cases, the fact that the function terminates for all inputs means that the value computed by applying the function is always uniquely determined.

In some cases where a function does not terminate for all arguments, the equation may not uniquely determine the function's return value for each input, but there are nonetheless functions for which the defining equation holds.
In these cases, a definition as a partial fixpoint may still be possible.
Any function that satisfies the defining equation can be used to demonstrate that the equation does not create a logical contradiction, and the equation can then be proven as a theorem about this function.
As with the other strategies for defining recursive functions, compiled code uses the function as it was originally written; like definitions in terms of eliminators or recursion over accessibility proofs, the function used to define the partial fixpoint is used only to justify the function's equations in Lean's logic for purposes of mathematical reasoning.

The term partial fixpoint is specific to Lean.
Functions declared ``Lean.Parser.Command.declaration : command```partial` do not require termination proofs, so long as the type of their return values is inhabited, but they are completely opaque from the perspective of Lean's logic.
Partial fixpoints, on the other hand, can be rewritten using their defining equations while writing proofs.
Logically speaking, partial fixpoints are total functions that don't reduce definitionally when applied, but for which equational rewrite rule are provided.
They are partial in the sense that the defining equation does not necessarily specify a value for all possible arguments.

While partial fixpoints do allow functions to be defined that cannot be expressed using structural or well-founded recursion, the technique is also useful in other cases.
Even in cases where the defining equation fully describes the function's behavior and a termination proof using well-founded recursion would be possible, it may simply be more convenient to define the function as a partial fixpoint to avoid a having to write a termination proof.

Defining recursive functions as partial fixpoints only occurs when explicitly requested by annotating the definition with ``Lean.Parser.Command.declaration : command```partial_fixpoint`.

There are two classes of functions that can be defined as partial fixpoints:

- 
Tail-recursive functions whose return type is inhabited type

- 
Functions that return values in a suitable monad, such as the `Option` monad

Both classes are backed by the same theory and construction: least fixpoints of monotone equations in chain-complete partial orders.

Just as with structural and well-founded recursion, Lean allows mutually recursive functions to be defined as partial fixpoints.
To use this feature, every function definition in a mutual block must be annotated with the ``Lean.Parser.Command.declaration : command```partial_fixpoint` modifier.
Definition by Partial Fixpoint

The following function finds the least natural number for which the predicate `p` holds.
If `p` never holds, then this equation does not specify the behavior: the function `find` could return `42` or any other `Nat` in that case and still satisfy the equation.
`def find (p : Nat → Bool) (i : Nat := 0) : Nat :=
if p i then
i
else
find p (i + 1)
partial_fixpoint
`
The elaborator can prove that functions satisfying the equation exist.
Within Lean's logic, `find` is defined to be an arbitrary such function.

Live ↪

### 7.6.4.1. Tail-Recursive Functions🔗

A recursive function can be defined as a partial fixpoint if the following two conditions hold:

- 
The function's return type is inhabited (as with functions marked ``Lean.Parser.Command.declaration : command```partial`)—either a `Nonempty` or `Inhabited` instance works.

- 
All recursive calls are in tail position of the function.

An expression is in tail position in the function body if it is:

- 
the function body itself,

- 
the branches of a ``Lean.Parser.Term.match : term``Pattern matching. `match e, ... with | p, ... => f | ...` matches each given
term `e` against each pattern `p` of a match alternative. When all patterns
of an alternative match, the `match` term evaluates to the value of the
corresponding right-hand side `f` with the pattern variables bound to the
respective matched values.
If used as `match h : e, ... with | p, ... => f | ...`, `h : e = p` is available
within `f`.

When not constructing a proof, `match` does not automatically substitute variables
matched on in dependent variables' types. Use `match (generalizing := true) ...` to
enforce this.

Syntax quotations can also be used in a pattern match.
This matches a `Syntax` value against quotations, pattern variables, or `_`.

Quoted identifiers only match identical identifiers - custom matching such as by the preresolved
names only should be done explicitly.

`Syntax.atom`s are ignored during matching by default except when part of a built-in literal.
For users introducing new atoms, we recommend wrapping them in dedicated syntax kinds if they
should participate in matching.
For example, in
```lean
syntax "c" ("foo" <|> "bar") ...
```
`foo` and `bar` are indistinguishable during matching, but in
```lean
syntax foo := "foo"
syntax "c" (foo <|> "bar") ...
```
they are not.```match` expression that is in tail position,

- 
the branches of an ``termIfThenElse : term```if c then t else e` is notation for `ite c t e`, "if-then-else", which decides to
return `t` or `e` depending on whether `c` is true or false. The explicit argument
`c : Prop` does not have any actual computational content, but there is an additional
`[Decidable c]` argument synthesized by typeclass inference which actually
determines how to evaluate `c` to true or false. Write `if h : c then t else e`
instead for a "dependent if-then-else" `dite`, which allows `t`/`e` to use the fact
that `c` is true/false.

Conventions for notations in identifiers:

* The recommended spelling of `if c then t else e` in identifiers is `ite` (use `left` for `t` and `right` for `e`).```if` expression that is in tail position, and

- 
the body of a ``Lean.Parser.Term.let : term```let` is used to declare a local definition. Example:
```
let x := 1
let y := x + 1
x + y
```
Since functions are first class citizens in Lean, you can use `let` to declare
local functions too.
```
let double := fun x => 2*x
double (double 3)
```
For recursive definitions, you should use `let rec`.
You can also perform pattern matching using `let`. For example,
assume `p` has type `Nat × Nat`, then you can write
```
let (x, y) := p
x + y
```

The *anaphoric let* `let := v` defines a variable called `this`.```let` expression that is in tail position.

In particular, the discriminant of a ``Lean.Parser.Term.match : term``Pattern matching. `match e, ... with | p, ... => f | ...` matches each given
term `e` against each pattern `p` of a match alternative. When all patterns
of an alternative match, the `match` term evaluates to the value of the
corresponding right-hand side `f` with the pattern variables bound to the
respective matched values.
If used as `match h : e, ... with | p, ... => f | ...`, `h : e = p` is available
within `f`.

When not constructing a proof, `match` does not automatically substitute variables
matched on in dependent variables' types. Use `match (generalizing := true) ...` to
enforce this.

Syntax quotations can also be used in a pattern match.
This matches a `Syntax` value against quotations, pattern variables, or `_`.

Quoted identifiers only match identical identifiers - custom matching such as by the preresolved
names only should be done explicitly.

`Syntax.atom`s are ignored during matching by default except when part of a built-in literal.
For users introducing new atoms, we recommend wrapping them in dedicated syntax kinds if they
should participate in matching.
For example, in
```lean
syntax "c" ("foo" <|> "bar") ...
```
`foo` and `bar` are indistinguishable during matching, but in
```lean
syntax foo := "foo"
syntax "c" (foo <|> "bar") ...
```
they are not.```match` expression, the condition of an ``termIfThenElse : term```if c then t else e` is notation for `ite c t e`, "if-then-else", which decides to
return `t` or `e` depending on whether `c` is true or false. The explicit argument
`c : Prop` does not have any actual computational content, but there is an additional
`[Decidable c]` argument synthesized by typeclass inference which actually
determines how to evaluate `c` to true or false. Write `if h : c then t else e`
instead for a "dependent if-then-else" `dite`, which allows `t`/`e` to use the fact
that `c` is true/false.

Conventions for notations in identifiers:

* The recommended spelling of `if c then t else e` in identifiers is `ite` (use `left` for `t` and `right` for `e`).```if` expression and the arguments of functions are not tail positions.
Loops are Tail Recursive Functions

Because the function body itself is a tail position, the infinitely looping function `loop` is tail recursive.
It can be defined as a partial fixpoint.
`def loop (x : Nat) : Nat := loop (x + 1)
partial_fixpoint
`
Live ↪Tail Recursion with Branching

`Array.find` could also be constructed using well-founded recursion with a termination proof, but may be more convenient to define using ``Lean.Parser.Command.declaration : command```partial_fixpoint`, where no termination proof is needed.
`def Array.find (xs : Array α) (p : α → Bool)
(i : Nat := 0) : Option α :=
if h : i < xs.size then
if p xs[i] then
some xs[i]
else
Array.find xs p (i + 1)
else
none
partial_fixpoint
`
If the result of the recursive call is not just returned, but passed to another function, it is not in tail position and this definition fails.
`def List.findIndex (xs : List α) (p : α → Bool) : Int :=
match xs with
| [] => -1
| x::ys =>
if p x then
0
else
have r := `Could not prove 'List.findIndex' to be monotone in its recursive calls:
Cannot eliminate recursive call `List.findIndex ys p` enclosed in
if ys✝.findIndex p = -1 then -1 else ys✝.findIndex p + 1
Tried to apply 'monotone_ite', but failed.
Possible cause: A missing `MonoBind` instance.
Use `set_option trace.Elab.Tactic.monotonicity true` to debug.`List.findIndex ys p
if r = -1 then -1 else r + 1
partial_fixpoint
`
The error message on the recursive call is:

Could not prove 'List.findIndex' to be monotone in its recursive calls:
Cannot eliminate recursive call `List.findIndex ys p` enclosed in
if ys✝.findIndex p = -1 then -1 else ys✝.findIndex p + 1
Tried to apply 'monotone_ite', but failed.
Possible cause: A missing `MonoBind` instance.
Use `set_option trace.Elab.Tactic.monotonicity true` to debug.

Live ↪

### 7.6.4.2. Monadic functions🔗

Defining a function as a partial fixpoint is more powerful if the function's return type is a monad that is an instance of `Lean.Order.MonoBind`, such as `Option`.
In this case, recursive call are not restricted to tail-positions, but may also occur inside higher-order monadic functions such as `bind` and `List.mapM`.

The set of higher-order functions for which this works is extensible, so no exhaustive list is given here.
The aspiration is that a monadic recursive function definition that is built using abstract monadic operations like `bind`, but that does not open the abstraction of the monad (e.g. by matching on the `Option` value), is accepted.
In particular, using ``Lean.Parser.Term.do : term```do`-notation should work.
Monadic functions

The following function implements the Ackermann function in the `Option` monad, and is accepted without an (explicit or implicit) termination proof:
`def ack : (n m : Nat) → Option Nat
| 0,   y   => some (y+1)
| x+1, 0   => ack x 1
| x+1, y+1 => do ack x (← ack (x+1) y)
partial_fixpoint
`
Recursive calls may also occur within higher-order functions such as `List.mapM`, if they are set up appropriately, and ``Lean.Parser.Term.do : term```do`-notation:
`structure Tree where cs : List Tree

def Tree.rev (t : Tree) : Option Tree := do
Tree.mk (← t.cs.reverse.mapM (Tree.rev ·))
partial_fixpoint

def Tree.rev' (t : Tree) : Option Tree := do
let mut cs := []
for c in t.cs do
cs := (← c.rev') :: cs
return Tree.mk cs
partial_fixpoint
`
Pattern matching on the result of the recursive call will prevent the definition by partial fixpoint from going through:
`def List.findIndex (xs : List α) (p : α → Bool) : Option Nat :=
match xs with
| [] => none
| x::ys =>
if p x then
some 0
else
match `Could not prove 'List.findIndex' to be monotone in its recursive calls:
Cannot eliminate recursive call `List.findIndex ys p` enclosed in
match ys✝.findIndex p with
| none => none
| some r => some (r + 1)
`List.findIndex ys p with
| none => none
| some r => some (r + 1)
partial_fixpoint
`
Could not prove 'List.findIndex' to be monotone in its recursive calls:
Cannot eliminate recursive call `List.findIndex ys p` enclosed in
match ys✝.findIndex p with
| none => none
| some r => some (r + 1)

In this particular case, using `Functor.map` instead of explicit pattern matching helps:
`def List.findIndex (xs : List α) (p : α → Bool) : Option Nat :=
match xs with
| [] => none
| x::ys =>
if p x then
some 0
else
(· + 1) <$> List.findIndex ys p
partial_fixpoint
`
Live ↪

### 7.6.4.3. Partial Correctness Theorems🔗

For every function defined as a partial fixpoint, Lean proves that the defining equation is satisfied.
This enables proofs by rewriting.
However, these equational theorems are not sufficient for reasoning about the behavior of the function on arguments for which the function specification does not terminate.
Code paths that lead to infinite recursion at runtime would end up as infinite chains of rewrites in a potential proof.

Partial fixpoints in suitable monads, on the other hand, provide additional theorems that map the undefined values from non-termination to suitable values in the monad.
In the `Option` monad, then partial fixpoint equals `Option.none` on all function inputs for which the defining equation specifies non-termination.
From this fact, Lean proves a partial correctness theorem for the function which allows facts to be concluded when the function's result is `Option.some`.
Partial Correctness Theorem

Recall `List.findIndex` from an earlier example:
`def List.findIndex (xs : List α) (p : α → Bool) : Option Nat :=
match xs with
| [] => none
| x::ys =>
if p x then
some 0
else
(· + 1) <$> List.findIndex ys p
partial_fixpoint
`
With this function definition, Lean automatically proves the following partial correctness theorem:
`List.findIndex.partial_correctness.{u_1} {α : Type u_1}
(p : α → Bool)
(motive : List α → Nat → Prop)
(h :
∀ (findIndex : List α → Option Nat),
(∀ (xs : List α) (r : Nat), findIndex xs = some r → motive xs r) →
∀ (xs : List α) (r : Nat),
(match xs with
| [] => none
| x :: ys =>
if p x = true then some 0
else (fun x => x + 1) <$> findIndex ys) = some r →
motive xs r)
(xs : List α) (r : Nat) :
xs.findIndex p = some r →
motive xs r`

Here, the motive is a relation between the parameter and return types of `List.findIndex`, with the `Option` removed from the return type.
If, when given an arbitrary partial function with a signature that's compatible with `List.findIndex`, the following hold:

- 
the motive is satisfied for all inputs for which the arbitrary function returns a value (rather than `none`),

- 
taking one rewriting step with the defining equation, in which the recursive calls are replaced by the arbitrary function, also implies the satisfaction of the motive

then the motive is satisfied for all inputs for which the `List.findIndex` returns `some`.

The partial correctness theorem is a reasoning principle.
It can be used to prove that the resulting number is a valid index in the list and that the predicate holds for that index:
`theorem List.findIndex_implies_pred
(xs : List α) (p : α → Bool) :
xs.findIndex p = some i →
∃x, xs[i]? = some x ∧ p x := byα:Type u_1i:Natxs:List αp:α → Bool⊢ xs.findIndex p = some i → ∃ x, xs[i]? = some x ∧ p x = true
apply List.findIndex.partial_correctness
(motive := fun xs i => ∃ x, xs[i]? = some x ∧ p x)α:Type u_1i:Natxs:List αp:α → Bool⊢ ∀ (findIndex : List α → Option Nat),
(∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = true) →
∀ (xs : List α) (r : Nat),
(match xs with
| [] => none
| x :: ys => if p x = true then some 0 else (fun x => x + 1) <$> findIndex ys) =
some r →
∃ x, xs[r]? = some x ∧ p x = true
intro findIndex ih xs r hsomeα:Type u_1i:Natxs✝:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truexs:List αr:Nathsome:(match xs with
| [] => none
| x :: ys => if p x = true then some 0 else (fun x => x + 1) <$> findIndex ys) =
some r⊢ ∃ x, xs[r]? = some x ∧ p x = true
split at hsomeh_1α:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αhsome:none = some r⊢ ∃ x, [][r]? = some x ∧ p x = trueh_2α:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx✝:αys✝:List αhsome:(if p x✝ = true then some 0 else (fun x => x + 1) <$> findIndex ys✝) = some r⊢ ∃ x, (x✝ :: ys✝)[r]? = some x ∧ p x = true
next =>α:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αhsome:none = some r⊢ ∃ x, [][r]? = some x ∧ p x = true contradictionAll goals completed! 🐙
next x ys =>α:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx:αys:List αhsome:(if p x✝ = true then some 0 else (fun x => x + 1) <$> findIndex ys✝) = some r⊢ ∃ x, (x✝ :: ys✝)[r]? = some x ∧ p x = true
split at hsomeisTrueα:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx:αys:List αh✝:p x = truehsome:some 0 = some r⊢ ∃ x, (x✝ :: ys✝)[r]? = some x ∧ p x = trueisFalseα:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx:αys:List αh✝:¬p x = truehsome:(fun x => x + 1) <$> findIndex ys = some r⊢ ∃ x, (x✝ :: ys✝)[r]? = some x ∧ p x = true
next =>α:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx:αys:List αh✝:p x = truehsome:some 0 = some r⊢ ∃ x, (x✝ :: ys✝)[r]? = some x ∧ p x = true
have : r = 0 := byα:Type u_1i:Natxs:List αp:α → Bool⊢ xs.findIndex p = some i → ∃ x, xs[i]? = some x ∧ p x = true simp_allα:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx:αys:List αh✝:p x = truehsome:some 0 = some rthis:r = 0⊢ ∃ x_1, (x :: ys)[r]? = some x_1 ∧ p x_1 = true
simp_allAll goals completed! 🐙
next =>α:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx:αys:List αh✝:¬p x = truehsome:(fun x => x + 1) <$> findIndex ys = some r⊢ ∃ x, (x✝ :: ys✝)[r]? = some x ∧ p x = true
simp only [Option.map_eq_map, Option.map_eq_some_iff] at hsomeα:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truer:Natxs✝:List αx:αys:List αh✝:¬p x = truehsome:∃ a, findIndex ys = some a ∧ a + 1 = r⊢ ∃ x, (x✝ :: ys✝)[r]? = some x ∧ p x = true
obtain ⟨r', hr, rfl⟩ := hsomeα:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natih:∀ (xs : List α) (r : Nat), findIndex xs = some r → ∃ x, xs[r]? = some x ∧ p x = truexs✝:List αx:αys:List αh✝:¬p x = truer':Nathr:findIndex ys = some r'⊢ ∃ x_1, (x :: ys)[r' + 1]? = some x_1 ∧ p x_1 = true
specialize ih _ _ hrα:Type u_1i:Natxs:List αp:α → BoolfindIndex:List α → Option Natxs✝:List αx:αys:List αh✝:¬p x = truer':Natih:∃ x, ys[r']? = some x ∧ p x = truehr:findIndex ys = some r'⊢ ∃ x_1, (x :: ys)[r' + 1]? = some x_1 ∧ p x_1 = true
simpaAll goals completed! 🐙
`
Live ↪

### 7.6.4.4. Mutual Recursion with Partial Fixpoints🔗

Lean supports the definition of mutually recursive functions using partial fixpoint.
Mutual recursion may be introduced using a mutual block, but it also results from ``Lean.Parser.Term.letrec : term```let rec` expressions and ``Lean.Parser.Command.declaration : command```where` blocks.
The rules for mutual recursion with partial fixpoints are applied to a group of actually mutually recursive, lifted definitions, that results from the elaboration steps for mutual groups.

If all functions in the mutual group have the ``Lean.Parser.Command.declaration : command```partial_fixpoint` clause, then this strategy is used.

[...omitted: 7.6.4.5 theory and construction...]
## 7.6.5. Coinductive and Inductive Predicates🔗

Lean's type theory does not support coinductive types directly.
However, coinductive predicates, that is, recursive definitions valued in `Prop`, can be defined using the complete lattice structure on propositions.
These predicates provide a coinductive reasoning principle, where something can be shown to satisfy a predicate by showing that it satisfies some smaller predicate that is itself consistent with the definition of the coinductive predicate.
This is the dual of inductive reasoning, in which a known fact can be decomposed via a potentially recursive case analysis.
Coinductive predicates allow infinite domains to be specified and reasoned about.
Some examples from computer science include:

- 
bisimilarity of state transition systems that admit cycles

- 
divergence of small-step operational semantics

- 
liveness properties

Dually, inductive predicates can also be defined via least fixpoints using the same machinery.
Because it uses the same underlying mechanisms, this alternative to ordinary inductive types is compatible with mixed inductive-coinductive mutual blocks.
Infinite Sequences

Given a relation `R` on `α` (that is, with type `α → α → Prop`), there is an infinite sequence of values in `α` starting at `x` if:

- 
there exists some `y` such that `R x y`, and

- 
there exists an infinite sequence from `y`.

This is a quintessential coinductive predicate: it describes a potentially infinite behavior that can be presented as a single inference rule with no base cases.

This recursive specification is well-defined, but it cannot be defined as an ordinary recursive function because the recursive part of the definition does not decrease.
However, it is a perfectly sensible coinductive definition:
`coinductive InfSeq (R : α → α → Prop) : α → Prop where
| step (y : α) : R x y →  InfSeq R y → InfSeq R x
`
The coinductive reasoning principle takes a predicate `pred`.
To prove that `a` is the start of an infinite `R`-sequence, it suffices to show that `R` relates each element that satisfies `pred` to some other such element.
In other words, it that the presence of an infinite sequence can be demonstrated by providing one:
`InfSeq.coinduct (R : α → α → Prop) (pred : α → Prop) :
(∀ (a : α), pred a → ∃ y, R a y ∧ pred y) →
∀ (a : α), pred a → InfSeq R a`
Live ↪
There are two ways to define coinductive predicates in Lean:

- 
Using the ``Lean.Parser.Command.declaration : command```coinductive_fixpoint` termination clause on a recursive ``Lean.Parser.Command.declaration : command```def` valued in `Prop`, which takes the greatest fixpoint. Equivalently, the ``Lean.Parser.Command.declaration : command```inductive_fixpoint` clause defines inductive predicates as least fixpoints.

- 
Using the ``Lean.Parser.Command.coinductive```coinductive` command, which provides a declarative syntax mirroring ``Lean.Parser.Command.inductive``In Lean, every concrete type other than the universes
and every type constructor other than dependent arrows
is an instance of a general family of type constructions known as inductive types.
It is remarkable that it is possible to construct a substantial edifice of mathematics
based on nothing more than the type universes, dependent arrow types, and inductive types;
everything else follows from those.
Intuitively, an inductive type is built up from a specified list of constructors.
For example, `List α` is the list of elements of type `α`, and is defined as follows:
```
inductive List (α : Type u) where
| nil
| cons (head : α) (tail : List α)
```
A list of elements of type `α` is either the empty list, `nil`,
or an element `head : α` followed by a list `tail : List α`.
See [Inductive types](https://lean-lang.org/theorem_proving_in_lean4/inductive_types.html)
for more information.```inductive` declarations.

### 7.6.5.1. Fixpoint Termination Clauses🔗

A recursive `Prop`-valued function can be defined as a fixpoint by annotating it with ``Lean.Parser.Command.declaration : command```coinductive_fixpoint` for coinductive definitions (greatest fixpoint) or ``Lean.Parser.Command.declaration : command```inductive_fixpoint` for inductive definitions (least fixpoint).
These termination clauses play the same role as ``Lean.Parser.Command.declaration : command```partial_fixpoint` but use the complete lattice structure on `Prop` to compute the appropriate fixpoint.

[...omitted: fixpoint termination clause examples...]
### 7.6.5.3. The `coinductive` Command🔗

The ``Lean.Parser.Command.declaration : command```coinductive` command provides a syntax for defining coinductive predicates that mirrors the syntax of ``Lean.Parser.Command.declaration : command```inductive` declarations.
Rather than writing a recursive function with ``Lean.Parser.Command.declaration : command```coinductive_fixpoint`, the declaration is written in terms of constructors, just as it would be for an inductive type.

syntaxCoinductive Predicates

command ::= ...
| ```declModifiers` is the collection of modifiers on a declaration:
* a doc comment `/-- ... -/`
* a list of attributes `@[attr1, attr2]`
* a visibility specifier, `private` or `public`
* `protected`
* `noncomputable`
* `unsafe`
* `partial` or `nonrec`

All modifiers are optional, and have to come in the listed order.

`nestedDeclModifiers` is the same as `declModifiers`, but attributes are printed
on the same line as the declaration. It is used for declarations nested inside other syntax,
such as inductive constructors, structure projections, and `let rec` / `where` definitions.``coinductive ```declId` matches `foo` or `foo.{u,v}`: an identifier possibly followed by a list of universe names``declId ```optDeclSig` matches the signature of a declaration with optional type: a list of binders and then possibly `: type```(ident | ``A *hole* (or *placeholder term*), which stands for an unknown term that is expected to be inferred based on context.
For example, in `@id _ Nat.zero`, the `_` must be the type of `Nat.zero`, which is `Nat`.

The way this works is that holes create fresh metavariables.
The elaborator is allowed to assign terms to metavariables while it is checking definitional equalities.
This is often known as *unification*.

Normally, all holes must be solved for. However, there are a few contexts where this is not necessary:
* In `match` patterns, holes are catch-all patterns.
* In some tactics, such as `refine'` and `apply`, unsolved-for placeholders become new goals.

Related concept: implicit parameters are automatically filled in with holes during the elaboration process.

See also `?m` syntax (synthetic holes).``hole | bracketedBinder)* : term where
ctor*

The ``Lean.Parser.Command.declaration : command```coinductive` command defines a coinductive predicate by specifying its constructors.
It can only be used to define predicates, that is, types valued in `Prop`.

The ``Lean.Parser.Command.declaration : command```coinductive` command defines the same predicate as the corresponding ``Lean.Parser.Command.declaration : command```coinductive_fixpoint` definition.
It additionally generates constructors and a case analysis principle, much like an ordinary ``Lean.Parser.Command.declaration : command```inductive` declaration.
Coinductive Predicate via `coinductive`

The predicate `InfSeq` from prior examples can equivalently be defined using the ``Lean.Parser.Command.coinductive```coinductive` command:
`variable (α : Type)

coinductive InfSeq (r : α → α → Prop) : α → Prop where
| step : r a b → InfSeq r b → InfSeq r a
`
This generates a constructor and a coinduction principle:
`InfSeq.step (α : Type) (r : α → α → Prop) {a b : α} :
r a b → InfSeq α r b → InfSeq α r a``InfSeq.coinduct (α : Type) (r : α → α → Prop) (pred : α → Prop) :
(∀ (a : α), pred a → ∃ b, r a b ∧ pred b) →
∀ (a : α), pred a → InfSeq α r a`
A case analysis principle is also generated:
`InfSeq.casesOn (α : Type) (r : α → α → Prop)
{motive : (a : α) → InfSeq α r a → Prop} {a : α} (t : InfSeq α r a) :
(∀ {a b} (a_1 : r a b) (a_2 : InfSeq α r b),
motive a (InfSeq.step α r a_1 a_2)) →
motive a t`
Case analysis can be used in proofs via the `cases` tactic:
`theorem InfSeq.casesOnTest (r : α → α → Prop)
(a : α) : InfSeq α r a → ∃ b, r a b := byα:Typer:α → α → Propa:α⊢ InfSeq α r a → ∃ b, r a b
intro hα:Typer:α → α → Propa:αh:InfSeq α r a⊢ ∃ b, r a b
cases hstepα:Typer:α → α → Propa:αb✝:αa✝¹:InfSeq α r b✝a✝:r a b✝⊢ ∃ b, r a b
case step b _ hr =>α:Typer:α → α → Propa:αb:αa✝:InfSeq α r b✝hr:r a b✝⊢ ∃ b, r a b exists bAll goals completed! 🐙
`
Live ↪

#### 7.6.5.3.1. Elaboration🔗

Under the hood, the ``Lean.Parser.Command.declaration : command```coinductive` command is elaborated in several steps.
First, it is processed as if it were an ordinary ``Lean.Parser.Command.declaration : command```inductive` declaration.
Before registering the types with the kernel, however, a flat inductive (also called a functor) is created: each recursive occurrence of the coinductive predicate in the premises of a constructor is replaced by an explicit parameter.
Flat Inductive

This example uses the coinductive specification of infinite sequences:
`coinductive InfSeq (r : α → α → Prop) : α → Prop where
| step : r a b → InfSeq r b → InfSeq r a
`
For `InfSeq`, the generated flat inductive is:
`InfSeq._functor : (α : Type) → (α → α → Prop) → (α → Prop) → α → Prop`
Its constructor takes the predicate parameter in place of recursive calls:
`set_option pp.proofs true in
`inductive InfSeq._functor : (α : Type) → (α → α → Prop) → (α → Prop) → α → Prop
number of parameters: 3
constructors:
InfSeq._functor.step : ∀ (α : Type) (r : α → α → Prop) (InfSeq._functor.call : α → Prop) {a b : α},
r a b → InfSeq._functor.call b → InfSeq._functor α r InfSeq._functor.call a`#print InfSeq._functor
`
inductive InfSeq._functor : (α : Type) → (α → α → Prop) → (α → Prop) → α → Prop
number of parameters: 3
constructors:
InfSeq._functor.step : ∀ (α : Type) (r : α → α → Prop) (InfSeq._functor.call : α → Prop) {a b : α},
r a b → InfSeq._functor.call b → InfSeq._functor α r InfSeq._functor.call a

Live ↪
An equivalent existential form is then constructed, expressing each constructor as a disjunction of dependent products (that is, existential quantifiers and conjunctions).
This form is used for monotonicity checking and for generating readable coinduction principles.
Existential Form
`coinductive InfSeq (r : α → α → Prop) : α → Prop where
| step : r a b → InfSeq r b → InfSeq r a
``set_option pp.proofs true in
`def InfSeq._functor.existential : (α : Type) → (α → α → Prop) → (α → Prop) → α → Prop :=
fun α r InfSeq._functor.call a => ∃ b, r a b ∧ InfSeq._functor.call b`#print InfSeq._functor.existential
`
def InfSeq._functor.existential : (α : Type) → (α → α → Prop) → (α → Prop) → α → Prop :=
fun α r InfSeq._functor.call a => ∃ b, r a b ∧ InfSeq._functor.call b

The two forms are connected by an equivalence theorem:
``InfSeq._functor.existential_equiv : ∀ (α : Type) (r : α → α → Prop) (InfSeq._functor.call : α → Prop) (a : α),
InfSeq._functor α r InfSeq._functor.call a ↔ ∃ b, r a b ∧ InfSeq._functor.call b`#check @InfSeq._functor.existential_equiv
`
InfSeq._functor.existential_equiv : ∀ (α : Type) (r : α → α → Prop) (InfSeq._functor.call : α → Prop) (a : α),
InfSeq._functor α r InfSeq._functor.call a ↔ ∃ b, r a b ∧ InfSeq._functor.call b

Live ↪
The existential form is then registered as a coinductive predicate using the partial fixpoint machinery with the `Lean.Order.ReverseImplicationOrder` complete lattice instance.
Using the correspondence between the flat inductive and the existential form, constructors and a case analysis eliminator are generated, just as for regular inductive types.

The following declarations are generated for a coinductive predicate named `P`:

- 
`P._functor`: the flat inductive

- 
`P._functor.existential`: the existential form

- 
`P._functor.existential_equiv`: equivalence between the two forms

- 
`P.functor_unfold`: theorem connecting the coinductive predicate to its flat inductive

- 
Constructors (e.g., `P.step`): corresponding to each constructor in the declaration

- 
`P.casesOn`: case analysis principle

- 
`P.coinduct`: coinduction principle

#### 7.6.5.3.2. Mutual Coinductive and Inductive Blocks🔗

In a mutual block containing ``Lean.Parser.Command.coinductive```coinductive` definitions, the ``Lean.Parser.Command.inductive``In Lean, every concrete type other than the universes
and every type constructor other than dependent arrows
is an instance of a general family of type constructions known as inductive types.
It is remarkable that it is possible to construct a substantial edifice of mathematics
based on nothing more than the type universes, dependent arrow types, and inductive types;
everything else follows from those.
Intuitively, an inductive type is built up from a specified list of constructors.
For example, `List α` is the list of elements of type `α`, and is defined as follows:
```
inductive List (α : Type u) where
| nil
| cons (head : α) (tail : List α)
```
A list of elements of type `α` is either the empty list, `nil`,
or an element `head : α` followed by a list `tail : List α`.
See [Inductive types](https://lean-lang.org/theorem_proving_in_lean4/inductive_types.html)
for more information.```inductive` keyword is reinterpreted: instead of being registered as an ordinary kernel inductive type, it is elaborated via the lattice-theoretic inductive fixpoint machinery.
This allows mixing coinductive and inductive predicates in the same mutual block.
Mutual Coinductive-Inductive Block

The predicates `Tick` and `Tock` are defined mutually, with `Tick` as a coinductive predicate and `Tock` as an inductive predicate:
`mutual
coinductive Tick : Prop where
| mk : ¬Tock → Tick

inductive Tock : Prop where
| mk : ¬Tick → Tock
end
`
Both constructors are available:
``Tick.mk : ¬Tock → Tick`#check @Tick.mk
`
Tick.mk : ¬Tock → Tick
``Tock.mk : ¬Tick → Tock`#check @Tock.mk
`
Tock.mk : ¬Tick → Tock

A mutual induction principle is generated:
``Tick.mutual_induct : ∀ (pred_1 pred_2 : Prop),
(pred_1 → pred_2 → False) → ((pred_1 → False) → pred_2) → (pred_1 → Tick) ∧ (Tock → pred_2)`#check @Tick.mutual_induct
`
Tick.mutual_induct : ∀ (pred_1 pred_2 : Prop),
(pred_1 → pred_2 → False) → ((pred_1 → False) → pred_2) → (pred_1 → Tick) ∧ (Tock → pred_2)

Live ↪

#### 7.6.5.3.3. Restrictions🔗

The ``Lean.Parser.Command.declaration : command```coinductive` command has the following restrictions:

- 
It can only define predicates, that is, types valued in `Prop`.
Attempting to define a coinductive type in `Type` or higher universes results in an error.

- 
The predicate being defined may not have macro scopes.

- 
Pattern matching via ``Lean.Parser.Term.match : term``Pattern matching. `match e, ... with | p, ... => f | ...` matches each given
term `e` against each pattern `p` of a match alternative. When all patterns
of an alternative match, the `match` term evaluates to the value of the
corresponding right-hand side `f` with the pattern variables bound to the
respective matched values.
If used as `match h : e, ... with | p, ... => f | ...`, `h : e = p` is available
within `f`.

When not constructing a proof, `match` does not automatically substitute variables
matched on in dependent variables' types. Use `match (generalizing := true) ...` to
enforce this.

Syntax quotations can also be used in a pattern match.
This matches a `Syntax` value against quotations, pattern variables, or `_`.

Quoted identifiers only match identical identifiers - custom matching such as by the preresolved
names only should be done explicitly.

`Syntax.atom`s are ignored during matching by default except when part of a built-in literal.
For users introducing new atoms, we recommend wrapping them in dedicated syntax kinds if they
should participate in matching.
For example, in
```lean
syntax "c" ("foo" <|> "bar") ...
```
`foo` and `bar` are indistinguishable during matching, but in
```lean
syntax foo := "foo"
syntax "c" (foo <|> "bar") ...
```
they are not.```match` is not yet supported; use the `cases` tactic instead.
Restriction to Predicates

Attempting to define a coinductive type that is not a predicate results in an error:
`coinductive ``coinductive` keyword can only be used to define predicates`MyNat where
| zero : MyNat
| succ : MyNat → MyNat
`
`coinductive` keyword can only be used to define predicates

[...omitted: lattice theory...]
## 7.6.6. Partial and Unsafe Definitions🔗

While most Lean functions can be reasoned about in Lean's type theory as well as compiled and run, definitions marked `partial` or `unsafe` cannot be meaningfully reasoned about.
From the perspective of the logic, `partial` functions are opaque constants, and theorems that refer to `unsafe` definitions are summarily rejected.
In exchange for the inability to use these functions for reasoning, there are far fewer requirements placed on them; this can make it possible to write programs that would be impractical or cost-prohibitive to prove anything about, while not giving up formal reasoning for the rest.
In essence, the `partial` subset of Lean is a traditional functional programming language that is nonetheless deeply integrated with the theorem proving features, and the `unsafe` subset features the ability to break Lean's runtime invariants in certain rare situations, at the cost of less integration with Lean's theorem-proving features.
Analogously, `noncomputable` definitions may use features that don't make sense in programs, but are meaningful in the logic.

### 7.6.6.1. Partial Functions🔗

The `partial` modifier may only be applied to function definitions.
Partial functions are not required to demonstrate termination, and Lean does not attempt to do so.
These functions are “partial” in the sense that they do not necessarily specify a mapping from each element of the domain to an element of the codomain, because they might fail to terminate for some or all elements of the domain.
They are elaborated into pre-definitions that contain explicit recursion, and type checked using the kernel; however, they are subsequently treated as opaque constants by the logic.

The function's return type must be inhabited; this ensures soundness.
Otherwise, a partial function could have a type such as `Unit → Empty`.
Together with `Empty.elim`, the existence of such a function could be used to prove `False` even if it does not reduce.

With partial definitions, the kernel is responsible for the following:

- 
It ensures that the pre-definition's type is indeed a well-formed type.

- 
It checks that the pre-definition's type is a function type.

- 
It ensures that the function's codomain is inhabited by demanding a `Nonempty` or `Inhabited` instance.

- 
It checks that the resulting term would be type-correct if Lean had recursive definitions.

Even though recursive definitions are not part of the kernel's type theory, the kernel can still be used to check that the body of the definition has the right type.
This works the same way as in other functional languages: uses of recursion are type checked by checking the body in an environment in which the definition is already associated with its type.
Having ensured that it type checks, the body is discarded and only the opaque constant is retained by the kernel.
As with all Lean functions, the compiler generates code from the elaborated pre-definition.

Even though partial functions are not unfolded by the kernel, it is still possible to reason about other functions that call them so long as this reasoning doesn't depend on the implementation of the partial function itself.
Partial Functions in Proofs

The recursive function `nextPrime` inefficiently computes the next prime number after a given number by repeatedly testing candidates with trial division.
Because there are infinitely many prime numbers, it always terminates; however, formulating this proof would be nontrivial.
It is thus marked `partial`.
`def isPrime (n : Nat) : Bool := Id.run do
for i in [2:n] do
if i * i > n then return true
if n % i = 0 then return false
return true

partial def nextPrime (n : Nat) : Nat :=
let n := n + 1
if isPrime n then n else nextPrime n
`
It is nonetheless possible to prove that the following two functions are equal:
`def answerUser (n : Nat) : String :=
s!"The next prime is {nextPrime n}"

def answerOtherUser (n : Nat) : String :=
" ".intercalate [
"The",
"next",
"prime",
"is",
toString (nextPrime n)
]
`
In fact, the proof is by `rfl`:
`theorem answer_eq_other : answerUser = answerOtherUser := by⊢ answerUser = answerOtherUser
rflAll goals completed! 🐙
`
Live ↪

[...omitted: unsafe definitions, reducibility...]

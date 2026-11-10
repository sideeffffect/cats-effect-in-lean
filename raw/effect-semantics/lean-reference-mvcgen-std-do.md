# Lean 4 reference: the mvcgen tactic - Overview and Enabling mvcgen for Monads (v4.34.0)

> Source: https://lean-lang.org/doc/reference/4.34.0/The--mvcgen--tactic/Overview/ ; https://lean-lang.org/doc/reference/4.34.0/The--mvcgen--tactic/Enabling--mvcgen--For-Monads/
> Collected: 2026-11-10
> Published: Unknown

## Overview
Overview

              17.1. Overview

              The workflow of mvcgen consists of the following:

                  Monadic programs are re-interpreted according to a predicate transformer semantics.
   An instance of WP determines the monad's interpretation.
   Each program is interpreted as a mapping from arbitrary postconditions to the weakest precondition that would ensure the postcondition.
   This step is invisible to most users, but library authors who want to enable their monads to work with mvcgen need to understand it.

                  Programs are composed from smaller programs.
   Each statement in a Lean.Parser.Term.do : termdo-block is associated with a predicate transformer, and there are general-purpose rules for combining these statements with sequencing and control-flow operators.
   A statement with its pre- and postconditions is called a Hoare triple.
   In a program, the postcondition of each statement should suffice to prove the precondition of the next one, and loops require a specified loop invariant, which is a statement that must be true at the beginning of the loop and at the end of each iteration.
   Designated specification lemmas associate functions with Hoare triples that specify them.

                  Applying the weakest-precondition semantics of a monadic program to a desired proof goal results in the precondition that must hold in order to prove the goal.
   Any missing steps such as loop invariants or proofs that a statement's precondition implies its postcondition become new subgoals.
   These missing steps are called the verification conditions.
   The mvcgen tactic performs this transformation, replacing the goal with its verification conditions.
   During this transformation, mvcgen uses specification lemmas to discharge proofs about individual statements.

                  After supplying loop invariants, many verification conditions can in practice be discharged automatically.
   Those that cannot can be proven using either a special proof mode or ordinary Lean tactics, depending on whether they are expressed in the logic of program assertions or as ordinary propositions.

## Enabling mvcgen For Monads
Enabling  mvcgen  For Monads

              17.4. Enabling mvcgen For Monads

              If a monad is implemented in terms of monad transformers that are provided by the Lean standard library, such as ExceptT and StateT, then it should not require additional instances.
Other monads will require instances of WP, LawfulMonad, and WPMonad.
The tactic has been designed to support monads that model single-threaded control with state that might be interrupted; in other words, the effects that are present in ordinary imperative programming.
More exotic effects have not yet been investigated.

              Once the basic instances are provided, the next step is to prove an adequacy lemma.
This lemma should show that the weakest precondition for running the monadic computation and asserting a desired predicate is in fact sufficient to prove the predicate.

              In addition to the definition of the monad, typical libraries provide a set of primitive operators.
Each of these should be provided with a specification lemma.
It may additionally be useful to make the internals of the state private, and export a carefully-designed set of assertion operators.

              The specification lemmas for the library's primitive operators should ideally be precise specifications of the operators as predicate transformers.
While it's often easier to think in terms of how the operator transforms an input state into an output state, verification condition generation will work more reliably when postconditions are completely free.
This allows automation to instantiate the postcondition with the exact precondition of the next statement, rather than needing to show an entailment.
In other words, specifications that specify the precondition as a function of the postcondition work better in practice than specifications that merely relate the pre- and postconditions.
            Schematic Postconditions

                  The function double doubles a natural number state:
                def double : StateM Nat Unit := do
  modify (2 * ·)

                  Thinking chronologically, a reasonable specification is that value of the output state is twice that of the input state.
This is expressed using a schematic variable that stands for the initial state:
                theorem double_spec :
    ⦃ fun s => ⌜s = n⌝ ⦄ double ⦃ _»-29856">⇓ () s _»-29856">=> ⌜s = 2 * n⌝ ⦄ := byn:Nat⊢ ⦃fun s => ⌜s = n⌝⦄ double ⦃PostCond.noThrow fun x s => ⌜s = 2 * n⌝⦄
  simp [double]n:Nat⊢ ⦃fun s => ⌜s = n⌝⦄ modify fun x => 2 * x ⦃PostCond.noThrow fun x s => ⌜s = 2 * n⌝⦄
  mvcgen with grindAll goals completed! 🐙

                  However, an equivalent specification that treats the postcondition schematically will lead to smaller verification conditions when double is used in other functions:
                @[spec]
theorem better_double_spec {Q : PostCond Unit (.arg Nat .pure)} :
    ⦃ fun s => Q.1 () (2 * s) ⦄ double ⦃ Q ⦄ := byQ:PostCond Unit (PostShape.arg Nat PostShape.pure)⊢ ⦃fun s => Q.fst () (2 * s)⦄ double ⦃Q⦄
  simp [double]Q:PostCond Unit (PostShape.arg Nat PostShape.pure)⊢ ⦃fun s => Q.fst () (2 * s)⦄ modify fun x => 2 * x ⦃Q⦄
  mvcgen with grindAll goals completed! 🐙

                  The first projection of the postcondition is its stateful assertion.
Now, the precondition merely states that the postcondition should hold for double the initial state.

                  Live ↪

              A Logging Monad

                  The monad LogM maintains an append-only log during a computation:
                structure LogM (β : Type u) (α : Type v) : Type (max u v) where
  log : Array β
  value : α

instance : Monad (LogM β) where
  pure x := ⟨#[], x⟩
  bind x f :=
    let { log, value } := f x.value
    { log := x.log ++ log, value }

                  It has a LawfulMonad instance as well.

                  The log can be written to using log, and a value and the associated log can be computed using LogM.run.
                def log (v : β) : LogM β Unit := { log := #[v], value := () }

def LogM.run (x : LogM β α) : α × Array β := (x.value, x.log)

                  Rather than writing it from scratch, the WP instance uses PredTrans.pushArg.
This operator was designed to model state monads, but LogM can be seen as a state monad that can only append to the state.
This appending is visible in the body of the instance, where the initial state and the log that resulted from the action are appended:
                instance : WP (LogM β) (.arg (Array β) .pure) where
  wp
    | { log, value } =>
      PredTrans.pushArg (fun s => PredTrans.pure (value, s ++ log))

                  The WPMonad instance also benefits from the conceptual model as a state monad and admits very short proofs:
                instance : WPMonad (LogM β) (.arg (Array β) .pure) where
  wp_pure x := byα:Type ?u.5σ:List (Type u)ps:PostShapex✝:PredTrans ps αy:PredTrans ps αQ:Assertion psβ:Type ?u.20α✝:Type ?u.20x:α✝⊢ wp (pure x) = pure x
    extα:Type ?u.5σ:List (Type u)ps:PostShapex✝:PredTrans ps αy:PredTrans ps αQ:Assertion psβ:Type ?u.20α✝:Type ?u.20x:α✝Q✝:PostCond α✝ (PostShape.arg (Array β) PostShape.pure)s✝:Array β⊢ (wp⟦pure x⟧ Q✝ s✝).down ↔ ((pure x).apply Q✝ s✝).down
    simp [wp, pure]All goals completed! 🐙

  wp_bind _ _ := byα:Type ?u.5σ:List (Type u)ps:PostShapex:PredTrans ps αy:PredTrans ps αQ:Assertion psβ:Type ?u.20α✝:Type ?u.20β✝:Type ?u.20x✝¹:LogM β α✝x✝:α✝ → LogM β β✝⊢ (wp do
    let a ← x✝¹
    x✝ a) =
  do
  let a ← wp x✝¹
  wp (x✝ a)
    extα:Type ?u.5σ:List (Type u)ps:PostShapex:PredTrans ps αy:PredTrans ps αQ:Assertion psβ:Type ?u.20α✝:Type ?u.20β✝:Type ?u.20x✝¹:LogM β α✝x✝:α✝ → LogM β β✝Q✝:PostCond β✝ (PostShape.arg (Array β) PostShape.pure)s✝:Array β⊢ (wp⟦do
        let a ← x✝¹
        x✝ a⟧
      Q✝ s✝).down ↔
  ((do
          let a ← wp x✝¹
          wp (x✝ a)).apply
      Q✝ s✝).down
    simp [wp, bind]All goals completed! 🐙

                  The adequacy lemma has one important detail: the result of the weakest precondition transformation is applied to the empty array.
This is necessary because the logging computation has been modeled as an append-only state, so there must be some initial state.
Semantically, the empty array is the correct choice so as to not place items in a log that don't come from the program; technically, it must also be a value that commutes with the append operator on arrays.
                theorem LogM.of_wp_run_eq {x : α × Array β} {prog : LogM β α}
    (h : LogM.run prog = x) (P : α × Array β → Prop) :
    (⊢ₛ wp⟦prog⟧ (_»-33094">⇓ v l _»-33094">=> ⌜P (v, l)⌝) #[]) → P x := byα:Type u_1β:Type u_1x:α × Array βprog:LogM β αh:prog.run = xP:α × Array β → Prop⊢ (⊢ₛ wp⟦prog⟧ (PostCond.noThrow fun v l => ⌜P (v, l)⌝) #[]) → P x
  rw [← hα:Type u_1β:Type u_1x:α × Array βprog:LogM β αh:prog.run = xP:α × Array β → Prop⊢ (⊢ₛ wp⟦prog⟧ (PostCond.noThrow fun v l => ⌜P (v, l)⌝) #[]) → P prog.run]α:Type u_1β:Type u_1x:α × Array βprog:LogM β αh:prog.run = xP:α × Array β → Prop⊢ (⊢ₛ wp⟦prog⟧ (PostCond.noThrow fun v l => ⌜P (v, l)⌝) #[]) → P prog.run
  intro h'α:Type u_1β:Type u_1x:α × Array βprog:LogM β αh:prog.run = xP:α × Array β → Proph':⊢ₛ wp⟦prog⟧ (PostCond.noThrow fun v l => ⌜P (v, l)⌝) #[]⊢ P prog.run
  simp [wp] at h'α:Type u_1β:Type u_1x:α × Array βprog:LogM β αh:prog.run = xP:α × Array β → Proph':P (prog.value, prog.log)⊢ P prog.run
  exact h'All goals completed! 🐙

                  Next, each operator in the library should be provided with a specification lemma.
There is only one: log.
For new monads, these proofs must often break the abstraction boundaries of Hoare triples and weakest preconditions; the specifications that they provide can then be used abstractly by clients of the library.
                theorem log_spec {x : β} :
    ⦃ fun s => ⌜s = s'⌝ ⦄ log x ⦃ _»-33609">⇓ () s _»-33609">=> ⌜s = s'.push x⌝ ⦄ := byβ:Types':Array βx:β⊢ ⦃fun s => ⌜s = s'⌝⦄ log x ⦃PostCond.noThrow fun x_1 s => ⌜s = s'.push x⌝⦄
  simp [log, Triple, wp]All goals completed! 🐙

                  A better specification for log uses a schematic postcondition:
                variable {Q : PostCond Unit (.arg (Array β) .pure)}

@[spec]
theorem log_spec_better {x : β} :
    ⦃ fun s => Q.1 () (s.push x) ⦄ log x ⦃ Q ⦄ := byβ:TypeQ:PostCond Unit (PostShape.arg (Array β) PostShape.pure)x:β⊢ ⦃fun s => Q.fst () (s.push x)⦄ log x ⦃Q⦄
  simp [log, Triple, wp]All goals completed! 🐙

                  A function logUntil that logs all the natural numbers up to some bound will always result in a log whose length is equal to its argument:
                def logUntil (n : Nat) : LogM Nat Unit := do
  for i in 0...n do
    log i

theorem logUntil_length : (logUntil n).run.2.size = n := byn:Nat⊢ (logUntil n).run.snd.size = n
  generalize h : (logUntil n).run = xn:Natx:Unit × Array Nath:(logUntil n).run = x⊢ x.snd.size = n
  unfold logUntil at hn:Natx:Unit × Array Nath:(do
      forIn (0...n) PUnit.unit fun i __s => do
          log i
          pure (ForInStep.yield PUnit.unit)
      pure ()).run =
  x⊢ x.snd.size = n
  apply LogM.of_wp_run_eq hn:Natx:Unit × Array Nath:(do
      forIn (0...n) PUnit.unit fun i __s => do
          log i
          pure (ForInStep.yield PUnit.unit)
      pure ()).run =
  x⊢ ⊢ₛ
  wp⟦do
      forIn (0...n) PUnit.unit fun i __s => do
          log i
          pure (ForInStep.yield PUnit.unit)
      pure ()⟧
    (PostCond.noThrow fun v l => ⌜(v, l).snd.size = n⌝) #[]
  mvcgen invariants
  · _»-34352">⇓⟨xs, _⟩ s _»-34352">=> ⌜xs.pos = s.size⌝
  with
    simp_all [List.Cursor.pos]All goals completed! 🐙 <;>
    grind [Std.PRange.Nat.size_rco, Std.Rco.length_toList]

                  Live ↪

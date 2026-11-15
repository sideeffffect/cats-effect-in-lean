import CatsEffectInLean.Proofs.Phase6.MemoizeStuck

/-!
# `memoize` properties: satisfiability witnesses and non-forgeable observations

Decisions 53 and 54 (`wiki/methodology/agent-workflow.md`, "Satisfiable hypotheses").

## Decision 53: the hypotheses hold, and the interesting case happens

The only hypothesis of `memoizeNoStuckGet`, `memoizeGetsAgree` and `memoizeAtMostOnce` is
`WellFormed memoLib [] (env fa u) fa`. The refutation witness of CE-0030 (`fa = IO.canceled`,
`MemoizeStuck.fa_wf`) already satisfies it for `memoizeNoStuckGet`. Here, `fa = IO.cede` and no
user code:

* `getsAgree_sat`: `fa` is well-formed; after 40 micro-steps (FIFO) the memo is
  `Evaluating(d, 2)` (the second `get` subscribed while `fa` runs: two concurrent `get`s); the
  root completes with `(Succeeded(()), Succeeded(()))`, so the conclusion `oa = ob` is reached.
* `atMostOnce_sat`: the same for `countedTwoGets`: `Evaluating(d, 2)` in cell 1 after 45
  micro-steps, the root completes, the counter is 1 (`fa` started once, a `get` came during the
  evaluation).

## Decision 54: user code cannot forge what the statements read

The statements read the memo cell (`Ref` 0 of `twoGets`, `Ref` 1 of `countedTwoGets`) and the
counter (`Ref` 0 of `countedTwoGets`). These cells are made by library-side code (the mirror's
`refThunk`, the harness `newCounter`). User code gets no handle to them: the mirror passes
`fa` no argument, and the `get` value (which holds `ref r`) goes only to the harness closures
(`TLam`). So `WellFormed` with `H0 = []` forbids every write: a user `writeRef` needs a held
`Ref` (`WF.ResultOK`), and a program that names a library closure that captures the cell is not
`progOK` (clause 3). The theorems below check clause 3 on the closures that write the cells: the
counter increment, `tryComplete`, the `unsubscribe` modify, the `flatModifyFull` modify, and a
forged `get` of cell 0.
-/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeSat

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase6.Memoize
open CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness (userR u)

/-! ### `WellFormed` for any `fa` that holds no handle and calls no user code -/

theorem callV_even (fa : IO) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (env fa u).callV id a v = userR := by
  have h1 : isLibId id = false := by simp [isLibId, hid]
  show CatsEffectInLean.Props.Phase6.Memoize.dispatch fa u id a v = _
  simp [CatsEffectInLean.Props.Phase6.Memoize.dispatch, CatsEffectInLean.Model.Memoize.MLam.ofId?,
    bracketLeaf?, Bracket.BLam.ofId?_even hid, timeoutOf?, TLam.ofId?, h1, u]

theorem wellFormed (fa : IO) (hp : WF.progOK memoLib (fun h => ([] : List Handle).contains h) fa = true) :
    WellFormed memoLib [] (env fa u) fa := by
  refine ⟨hp, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, ?_⟩
  · rw [callV_even fa id hid, callV_even fa id hid]
  · rw [callV_even fa id hid]; simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]
  · refine WF.pollOpaque_of_const (env fa u) (fun _ => userR) [] userR
      (fun id arg v hid => callV_even fa id hid arg v) (by decide) (fun _ _ _ => rfl) ?_ (fun _ _ => rfl)
    intro σ _ k hk
    simp at hk

/-! ### Decision 53 -/

/-- At least two subscribers in memo cell `r` (a `get` subscribed during the evaluation). -/
def subscribers2 {M : Type} (s : Sched M) (r : Nat) : Bool :=
  match CatsEffectInLean.Model.Memoize.St.ofVal (s.liveHeap.refs.getD r .unit) with
  | .evaluating _ n => 2 ≤ n
  | _ => false

theorem cede_wf : WellFormed memoLib [] (env .cede u) .cede := wellFormed _ (by decide)

/-- `memoizeGetsAgree` is not vacuous: its hypothesis holds, two `get`s run at the same time, and
the root completes with a pair. -/
theorem getsAgree_sat :
    WellFormed memoLib [] (env .cede u) .cede ∧
    subscribers2 (run .cede u 40 [] (twoGets 0)) 0 = true ∧
    (run .cede u 200 [] (twoGets 0)).halt =
      some (.done (.succeeded (.pair (.ocSucceeded .unit) (.ocSucceeded .unit)))) :=
  ⟨cede_wf, by decide +kernel, by decide +kernel⟩

/-- `memoizeAtMostOnce` is not vacuous: its hypothesis holds, a `get` comes during the
evaluation, the root completes, and the counter is 1. -/
theorem atMostOnce_sat :
    WellFormed memoLib [] (env .cede u) .cede ∧
    subscribers2 (run .cede u 45 [] (countedTwoGets 0)) 1 = true ∧
    (run .cede u 200 [] (countedTwoGets 0)).halt =
      some (.done (.succeeded (.pair (.ocSucceeded .unit) (.ocSucceeded .unit)))) ∧
    counter (run .cede u 200 [] (countedTwoGets 0)) = 1 :=
  ⟨cede_wf, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-! ### Decision 54: programs that name the observed cells are not well-formed -/

/-- The program of a user `fa` with no handle in scope. -/
def okFa (p : IO) : Bool := WF.progOK memoLib (fun h => ([] : List Handle).contains h) p

theorem forged_counter : okFa (.delay (TLam.incr 0).fn) = false := by decide +kernel
theorem forged_tryComplete :
    okFa (CatsEffectInLean.Model.Memoize.tryIO 0 0 (.right .none)) = false := by decide +kernel
theorem forged_unsubscribe : okFa (CatsEffectInLean.Model.Memoize.unsubIO 0 0) = false := by
  decide +kernel
theorem forged_modify :
    okFa (.delay (CatsEffectInLean.Model.Memoize.MLam.modifyThunk 0 faSrc 0 1 0 0).fn) = false := by
  decide +kernel
theorem forged_get : okFa (CatsEffectInLean.Model.Memoize.getIO 0 faSrc 0) = false := by
  decide +kernel

/-! ### Decision 58 (review 9, R1 survey): `fa` is named by a reference, not by a number -/

/-- A user `fa` that memoizes the tested action by its source code (to run it outside the tested
`memoize`) is not well-formed: `faSrc` is an odd reference that user code does not hold. -/
theorem forged_source : okFa (CatsEffectInLean.Model.Memoize.memoizeIO faSrc 0) = false := by
  decide +kernel

/-- The old data code `0` names nothing any more (`srcIO` gives a fatal error), so a `memoize`
with source `0` cannot run `fa`. -/
theorem old_code_not_fa (fa : IO) : srcIO fa (.nat 0) = .error { code := 999999, kind := .fatal } := rfl

/-- The test-program closure `_ => fa` is not public. -/
theorem forged_constFa : okFa (.flatMap (.pure .unit) TLam.constFa.fn) = false := by decide +kernel

/-- An honest `fa` (here `IO.cede`) is accepted. -/
theorem honest_fa : okFa .cede = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeSat

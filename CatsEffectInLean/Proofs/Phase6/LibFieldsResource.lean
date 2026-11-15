import CatsEffectInLean.Model.LibProbe
import CatsEffectInLean.Model.Resource

/-!
# `Resource.lib`: the function fields are complete (probe check, `Model/LibProbe.lean`)

`fields_complete`: every sample passes `LibProbe.sampleOK` with the real `Resource.lib` and the
real `Resource.cloCall`. The `REnv` of the test answers user function `k` with `IO.delay(2 * k)`
(program id, `uid k`); its `bind`, `acquire` and `release` hold only the handles of their argument,
as `REnv.WellFormed` requires. `covers`: every `Clo`, `RelFn` and `AllocFn` constructor has a
sample. `idFree_fails`: a list without fields fails.
-/

namespace CatsEffectInLean.Proofs.Phase6.LibFieldsResource

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.LibProbe

/-- User function number of probe `i` (`probe i = 2 * q i`). -/
def q (i : Nat) : Nat := probe i / 2

/-- The `REnv` of the test. -/
def probeEnv : REnv where
  user := { call := fun k _ _ => { out := .prog (.delay (.user (2 * k))) } }
  bind := fun _ a => .ok (.pure a)
  acquire := fun _ => .pure .unit
  release := fun _ a => .ok (.pure a)

/-- The four `RelFn` shapes, with probes from `i` (two per shape). -/
def rels (i : Nat) : List RelFn :=
  [.unit, .const (q i) (.nat (q (i + 1))), .user (q i), .guarantee (.user (q i)) (.user (q (i + 1)))]

/-- The `AllocFn` shapes. -/
def allocs (i : Nat) : List AllocFn := [.user (q i), .make (q i) (q (i + 1))]

/-- The stacks: empty, and two frames. -/
def stacks (i : Nat) : List Stack := [[], [q i, q (i + 1)]]

/-- One sample per constructor, over the `RelFn`, `AllocFn` and stack shapes. -/
def samples : List Clo :=
  ((rels 0).flatMap fun r => (stacks 2).flatMap fun s =>
    [Clo.evalK s r, Clo.allocK s r (.poll 1 2)] ++ (allocs 4).map fun a => Clo.allocBody a s r) ++
  (rels 0).map Clo.onErrorH ++
  [.raiseK { code := 5 }, .handleUnit, .makePair (q 0), .applyPair, .spin]

/-- Argument shapes of `allocK` (`(b, rel)` with each `RelFn` shape, probe-free) and of
`applyPair` (`(a, release(a))`). -/
def moreArgs : List Val :=
  [RelFn.unit, .const 3 .unit, .user 3].map (fun r => Val.pair .unit r.toVal) ++
  [.pair .unit (ioRelease 3 .unit)]

/-- The test with a given library. -/
def check (lib : Lib) : Bool :=
  samples.all (sampleOK lib (args ++ moreArgs) Clo.toVal fun c a => cloCall probeEnv c a {})

/-- The function fields of `Resource.lib` are complete for every sample. -/
theorem fields_complete : check Resource.lib = true := by decide +kernel

/-- Every `Clo` constructor has a sample. -/
theorem covers_clo : ∀ c : Clo, c.ctorIdx ∈ samples.map Clo.ctorIdx := by
  have h : ∀ i, i < 9 → i ∈ samples.map Clo.ctorIdx := by decide +kernel
  intro c; apply h; cases c <;> simp only [Clo.ctorIdx] <;> decide

/-- Every `RelFn`, `AllocFn` constructor has a sample in each position. -/
theorem covers_rel : ∀ r : RelFn, ∀ i, r.ctorIdx ∈ (rels i).map RelFn.ctorIdx := by
  intro r i; cases r <;> simp [rels, RelFn.ctorIdx]

theorem covers_alloc : ∀ a : AllocFn, ∀ i, a.ctorIdx ∈ (allocs i).map AllocFn.ctorIdx := by
  intro a i; cases a <;> simp [allocs, AllocFn.ctorIdx]

/-- Wrong-function test: no fields (`Lib.idFree`) fails the check. -/
theorem idFree_fails : check (Lib.idFree isLib) = false := by decide +kernel

/-- Wrong-function test: `fields` without the `AllocFn.user` field fails the check. -/
theorem wrong_fields :
    check { ok := isLib, fields := fun c =>
      ((Clo.ofVal c).map fun
        | .evalK _ r | .onErrorH r | .allocBody _ _ r | .allocK _ r _ => r.fnIds
        | _ => []).getD [] } = false := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.LibFieldsResource

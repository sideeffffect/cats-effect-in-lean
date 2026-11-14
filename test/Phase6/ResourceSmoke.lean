import CatsEffectInLean.Proofs.Phase6.ResourceBoth
import CatsEffectInLean.Model.EnumP

/-!
# Smoke tests of the `Resource` statements (Phase 6, track Res)

`#guard` checks (compiled evaluation, not kernel proofs). Run:
`lake env lean test/Phase6/ResourceSmoke.lean` (about 15 min).

Every instance satisfies the hypotheses of its statement (decision 53): the environment is the
witness environment `ResourceWitnessEnv.W` (its hypotheses are proven in
`Proofs/Phase6/ResourceWitness.lean` and `ResourceBoth.lean`) extended with more constant user
functions; the extra functions are checked here (part 0) where the hypothesis is decidable.

0. Hypotheses: no user function of the smoke table mentions a harness name; only the markers
   emit marker values; the use functions and release rests are not harness names. The review
   batch 5 forgeries are detected by `mentionsIO`.
1. CE-0020 schedule family: the 600 single-deviation schedules and 1,500 pseudo-random schedules
   with preemption, of `Resource.both(A, B).use(f)`. v3.7.1 (`bothRes`) has a run where the
   release of `B` does not run; the fixed twin (`fixedBothRes`, decision 39) has none.
2. `useReleaseOnce`, `flatMapReleaseOrder`: releases `unit`/`raise`/`canceled`, bodies
   `unit`/`raise`/`canceled`/`cede`, directly and under the harness parent (decision 50), on 900
   schedules: no run violates the statement.
3. `resourceEvalPreservesCancelable` (decision 41): `alloc` computed by `allocatedCase`; exact
   `EqvP` sets for 4 programs `fa`: the implication holds; the over-masking `Eval` (wrong
   function) breaks it for `IO.canceled`.
-/

namespace CatsEffectInLean.Test.Phase6.ResourceSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Props.Phase6.HarnessNames
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

def family : List (List PChoice) :=
  (List.range 300).flatMap fun k => [1, 2].map fun d => List.replicate k (PChoice.pick 0) ++ [.pick d]

/-- Pseudo-random schedules (a linear congruential generator): at each choice `pick 0`, `pick 1`,
`pick 2` or `preempt`, 400 choices each. -/
def randomScheds (n : Nat) : List (List PChoice) :=
  (List.range n).map fun i =>
    (List.range 400).map fun j =>
      let x := (i * 7919 + j * 104729 + i * j * 31 + 12345) * 1103515245 % 2147483648 / 65536
      match x % 8 with
      | 0 => .pick 1 | 1 => .pick 2 | 2 => .preempt | _ => .pick 0

/-! ## 0. The smoke environment and its hypotheses -/

/-- `userR` plus 9 `_ => IO.canceled`, 11 `_ => IO.cede >> IO.unit` (not 10: program id 20 is the
harness resource code `nat 20`). -/
def userS (k : Nat) : UserResult :=
  match k with
  | 9 => { out := .prog .canceled }
  | 11 => { out := .prog (.flatMap .cede (uid 6)) }
  | k => userR k

/-- `W` with the smoke table and the release rest `qa` of side A (5 raise, 6 unit, 9 canceled). -/
def WS (qa : Nat) (two withBind : Bool) : UEnv :=
  { r := { user := { call := fun k _ _ => userS k }
           bind := (W false two withBind).r.bind
           acquire := (W false two withBind).r.acquire
           release := fun k a => if k == 0 then .ok (.flatMap (.delay (uid 3)) (uid qa))
             else (W false two withBind).r.release k a }
    resOf := (W false two withBind).resOf }

#guard [badUse, badBoth, badFlat].all fun bad => (List.range 14).all fun n => !mentionsR bad (userS n)
#guard [5, 6, 9, 11].all fun f => [badUse, badBoth, badFlat].all fun bad => !mentionsV bad (.nat (2 * f))
#guard (List.range 14).all fun n => n ∈ [1, 2, 3, 4] || (userS n).effects.isEmpty
#guard [badUse, badBoth, badFlat].all fun bad => [5, 6, 9].all fun q => !mentionsV bad (.nat (2 * q))
-- the forgeries of review batch 5 are names of the harness
#guard mentionsIO badUse (.map (.pure .unit) (ULam.allocFn (.user 3)).fn)
#guard mentionsIO badUse (.map (.pure .unit) (ULam.allocFn (.make 0 0)).fn)
#guard mentionsIO badUse (.flatMap (.pure .unit) (Bracket.BLam.thenUse (ULam.allocFn (.user 3)).id .unit).fn)
#guard mentionsIO badUse (.flatMap (.pure .unit) (cloFn (.makePair 0)))
#guard mentionsIO badBoth (Race.bothIO (USrc.fold (.nat 21) OnOut.pure.toVal OnRel.apply.toVal).toVal (.nat 0))

/-! ## 1. CE-0020: v3.7.1 and the fixed twin -/

def WB : UEnv := W true true false

def runsOf (U : UEnv) (p : IO) : List Obs :=
  (family ++ randomScheds 1500).filterMap fun cs => runObsP {} counterMaskModel (envH U) 6000 cs p

def okBoth (o : Obs) : Bool :=
  match o.summary with
  | .done _ => o.out.count RA == o.out.count A && o.out.count RB == o.out.count B
  | _ => true

#guard !(runsOf WB (useOf WB 14 (bothRes (.nat 20) (.nat 21)))).all okBoth
#guard (runsOf WB (useOf WB 14 (fixedBothRes (.nat 20) (.nat 21)))).all okBoth

/-! ## 2. `use` releases once, `flatMap` releases in LIFO order -/

/-- `out` newest first: the release of `A` is before (newer than) the release of `B`. -/
def lifo (o : Obs) : Bool :=
  !(o.out.contains RA && o.out.contains RB) || o.out.idxOf RA < o.out.idxOf RB

def scheds : List (List PChoice) := family ++ randomScheds 300

def checkUse (qa f : Nat) (viaParent : Bool) : Bool :=
  let U := WS qa false false
  let p := withParent viaParent (useOf U (2 * f) (Res.make 0 0))
  scheds.all fun cs => match runObsP {} counterMaskModel (envH U) 6000 cs p with
    | some o => match o.summary with
      | .done _ => o.out.count RA == o.out.count A
      | _ => true
    | none => true

def checkFlat (qa f : Nat) (viaParent : Bool) : Bool :=
  let U := WS qa true true
  let p := withParent viaParent (useOf U (2 * f) ((Res.make 0 0).flatMap 9))
  scheds.all fun cs => match runObsP {} counterMaskModel (envH U) 6000 cs p with
    | some o => okBoth o && lifo o
    | none => true

#guard [5, 6, 9].all fun qa => [5, 6, 9, 11].all fun f => [false, true].all fun b => checkUse qa f b
#guard [5, 6, 9].all fun qa => [5, 6, 9, 11].all fun f => [false, true].all fun b => checkFlat qa f b

/-! ## 3. Decision 41: the cancelable direction of CE-0002 -/

/-- 2 thunk emit 1, 3 `_ => canceled`, 4 `_ => emit 1` program. -/
def fas : List IO :=
  [.canceled, .flatMap (.delay (uid 2)) (uid 3), .flatMap (.start (IO.cancelOf 0 none)) (uid 4), .pure (.nat 1)]

/-- The over-masking wrong function (`Eval(fa) => F.uncancelable(_ => fa.flatMap(...))`, not
Cats Effect code): user function 7 returns the v3.7.1 `alloc`. -/
def overMasked : IO := .uncancelable (uid 7)

/-- User code (index `k`): 0 `_ => fa`, 1 `_ => alloc`, 2-4 as `fas`, 6 `_ => overMasked`,
7 `_ => alloc`. `alloc` is `allocatedCase r (Res.evalOf fa)`, computed with the same `REnv` (its
`bind`/`acquire`/`release` do not depend on `user`). -/
def renvBase : REnv where
  user := { call := fun _ _ _ => { out := .throw { code := 0 } } }
  bind := fun _ _ => .error { code := 0 }
  acquire := fun _ => .pure .unit
  release := fun _ _ => .error { code := 0 }

def allocOf (fa : IO) : IO :=
  match allocatedCase renvBase (Res.evalOf fa) with
  | .ok a => a
  | .error e => .error e

def renvE (fa : IO) : REnv :=
  { renvBase with user := { call := fun k _ _ => match k with
    | 0 => { out := .prog fa }
    | 1 => { out := .prog (allocOf fa) }
    | 2 => { effects := [.emit (.nat 1)], out := .ret .unit }
    | 3 => { out := .prog .canceled }
    | 4 => { out := .prog (.delay (uid 2)) }
    | 6 => { out := .prog overMasked }
    | 7 => { out := .prog (allocOf fa) }
    | _ => { out := .throw { code := 0 } } } }

-- `allocatedCase` with `renvE fa` gives the same `alloc` (it does not call `user`)
#guard fas.all fun fa => match allocatedCase (renvE fa) (Res.evalOf fa) with
  | .ok a => a == allocOf fa
  | .error _ => false

/-- `¬ EqvP fa (unc fa) → ¬ EqvP alloc (unc alloc)`, checked with exact sets. -/
def implies (fa : IO) (overMask : Bool) : Bool :=
  let env := (renvE fa).toEnv
  let alloc := if overMask then overMasked else allocOf fa
  let u2 := if overMask then 6 else 1
  !(checkNotEqvP {} counterMaskModel env 400 fa (.uncancelable (uid 0))) ||
    checkNotEqvP {} counterMaskModel env 400 alloc (.uncancelable (uid u2))

#guard fas.all fun fa => implies fa false
#guard !(implies .canceled true)
-- the premise is not vacuous: masking `IO.canceled` changes it
#guard checkNotEqvP {} counterMaskModel (renvE .canceled).toEnv 400 .canceled (.uncancelable (uid 0))

end CatsEffectInLean.Test.Phase6.ResourceSmoke

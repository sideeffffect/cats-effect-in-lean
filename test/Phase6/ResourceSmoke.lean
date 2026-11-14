import CatsEffectInLean.Proofs.Phase6.ResourceBoth
import CatsEffectInLean.Model.EnumP

/-!
# Smoke tests of the `Resource` statements (Phase 6, track Res)

`#guard` checks (compiled evaluation, not kernel proofs). Run:
`lake env lean test/Phase6/ResourceSmoke.lean`.

1. CE-0020 schedule family: all schedules "FIFO for `k` choices, then `pick d`" (`k < 300`,
   `d ∈ {1, 2}`) and 1,500 pseudo-random schedules with preemption, of the witness program `Resource.both(A, B).use(f)`. v3.7.1 (`bothRes`) has
   a run where the release of `B` does not run; the fixed twin (`fixedBothRes`, decision 39)
   has none, and in every run of the fixed twin that ends, each release ran once.
2. `useReleaseOnce`, `flatMapReleaseOrder`: `make(A).use(f)` and
   `make(A).flatMap(_ => make(B)).use(f)` with releases `unit`/`raise`/`canceled` and bodies
   `unit`/`raise`/`canceled`/`cede`, directly and under the parent fiber (decision 50), on the
   same schedules: no run violates the statement.
3. `resourceEvalPreservesCancelable` (decision 41): exact `EqvP` sets for 4 programs `fa`
   (`IO.canceled`, `emit 1 >> IO.canceled`, `start(cancel fiber 0) >> emit 1`, `pure 1`): the
   implication holds; the over-masking `Eval` (wrong function) breaks it for `IO.canceled`.
-/

namespace CatsEffectInLean.Test.Phase6.ResourceSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

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

def fixedProg : IO := useOf U (2 * 7) (fixedBothRes (.nat 0) (.nat 1))

/-- The runs that end with a root outcome and where a release count differs from its acquire
count (marker values: acquire `1`, `2`; release `101`, `102`). -/
def violations (p : IO) : List (List PChoice) :=
  (family ++ randomScheds 1500).filter fun cs =>
    match runObsP {} counterMaskModel U.toEnv 6000 cs p with
    | some { summary := .done _, out, .. } =>
      out.count (.nat 101) != out.count (.nat 1) || out.count (.nat 102) != out.count (.nat 2)
    | _ => false

#guard (violations prog).length > 0
#guard (violations fixedProg).length == 0

/-! ## 2. `use` releases once, `flatMap` releases in LIFO order -/

open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Props.Phase6.Bracket (PLam parent)

/-- User code (index `k`, program id `2 * k`): 1, 2 acquire `map` markers (emit 1 / 2); 3, 4
release markers (emit 101 / 102); 5 `_ => raise`; 6 `_ => unit`; 9 `_ => canceled`;
10 `_ => cede >> unit`; and the parent lambdas (`Bracket.PLam`). -/
def userS (k : Nat) (a : Val) (v : View) : UserResult :=
  match k with
  | 1 => { effects := [.emit (.nat 1)], out := .ret .unit }
  | 2 => { effects := [.emit (.nat 2)], out := .ret .unit }
  | 3 => { effects := [.emit (.nat 101)], out := .ret .unit }
  | 4 => { effects := [.emit (.nat 102)], out := .ret .unit }
  | 5 => { out := .prog (.error { code := 5 }) }
  | 6 => { out := .prog (.pure .unit) }
  | 9 => { out := .prog .canceled }
  | 10 => { out := .prog (.flatMap .cede (uid 6)) }
  | _ =>
    if k == Codec.valToNat PLam.cancelJoin.toVal then PLam.cancelJoin.call a v
    else match (Codec.natToVal k).bind Codec.ofCloVal with
      | some (8, 1, [.fiber f]) => (PLam.thenJoin f).call a v
      | _ => { out := .throw { code := 0 } }

/-- `make(unit.map(mark A))(_ => delay(mark RA) >> q)` for `k = 0` (A) and `k = 1` (B); `q` =
`qa`, `qb`; the `flatMap` function `7` gives `make` B. -/
def US (qa qb : Nat) : UEnv where
  r := { user := { call := fun k a refs => userS k a { refs }, callV := userS },
         bind := fun k _ => if k == 7 then .ok (Res.make 1 1) else .error { code := 0 },
         acquire := fun k => if k == 0 then .map (.pure .unit) (uid 1) else .map (.pure .unit) (uid 2),
         release := fun k _ => if k == 0 then .ok (.flatMap (.delay (uid 3)) (uid qa))
           else .ok (.flatMap (.delay (uid 4)) (uid qb)) }
  resOf := fun _ => none

def okRun (A RA B RB : Nat) (o : Obs) : Bool :=
  match o.summary with
  | .done _ => o.out.count (.nat RA) == o.out.count (.nat A) && o.out.count (.nat RB) == o.out.count (.nat B)
  | _ => true

/-- `out` newest first: the release of `A` (101) is before (newer than) the release of `B` (102). -/
def lifo (o : Obs) : Bool :=
  !(o.out.contains (.nat 101) && o.out.contains (.nat 102)) || o.out.idxOf (.nat 101) < o.out.idxOf (.nat 102)

def scheds : List (List PChoice) := family ++ randomScheds 300

def checkUse (qa : Nat) (f : Nat) (viaParent : Bool) : Bool :=
  let U := US qa 6
  let p := withParent viaParent (useOf U (2 * f) (Res.make 0 0))
  scheds.all fun cs => match runObsP {} counterMaskModel U.toEnv 6000 cs p with
    | some o => okRun 1 101 2 102 o
    | none => true

def checkFlat (qa qb : Nat) (f : Nat) (viaParent : Bool) : Bool :=
  let U := US qa qb
  let p := withParent viaParent (useOf U (2 * f) ((Res.make 0 0).flatMap 7))
  scheds.all fun cs => match runObsP {} counterMaskModel U.toEnv 6000 cs p with
    | some o => okRun 1 101 2 102 o && lifo o
    | none => true

#guard [5, 6, 9].all fun qa => [5, 6, 9, 10].all fun f => [false, true].all fun b => checkUse qa f b
#guard [5, 6].all fun qa => [6, 9].all fun qb => [5, 6, 9, 10].all fun f => [false, true].all fun b =>
  checkFlat qa qb f b

/-! ## 3. Decision 41: the cancelable direction of CE-0002 -/

/-- User code of the old `REnv` (index `k`): 0 `_ => fa` with `fa` = `fas[i]`, 1 `_ => alloc`,
2 thunk emit 1, 3 `_ => canceled`, 4 `_ => emit 1` program. -/
def fas : List IO :=
  [.canceled, .flatMap (.delay (uid 2)) (uid 3), .flatMap (.start (IO.cancelOf 0 none)) (uid 4), .pure (.nat 1)]

/-- `alloc` of v3.7.1 and of the over-masking wrong function
(`Eval(fa) => F.uncancelable(_ => fa.flatMap(...))`, not Cats Effect code). -/
def allocOf (fa : IO) (overMask : Bool) : IO :=
  let a := IO.flatMap fa (cloFn (.evalK [] .unit))
  if overMask then .uncancelable (uid 5) else a

def renvE (fa : IO) : REnv where
  user := { call := fun k _ _ => match k with
    | 0 => { out := .prog fa }
    | 1 => { out := .prog (allocOf fa false) }
    | 2 => { effects := [.emit (.nat 1)], out := .ret .unit }
    | 3 => { out := .prog .canceled }
    | 4 => { out := .prog (.delay (uid 2)) }
    | 5 => { out := .prog (allocOf fa false) }
    | 6 => { out := .prog (allocOf fa true) }
    | _ => { out := .throw { code := 0 } } }
  bind := fun _ _ => .error { code := 0 }
  acquire := fun _ => .pure .unit
  release := fun _ _ => .error { code := 0 }

/-- `¬ EqvP fa (unc fa) → ¬ EqvP alloc (unc alloc)`, checked with exact sets. -/
def implies (fa : IO) (overMask : Bool) : Bool :=
  let env := (renvE fa).toEnv
  let alloc := allocOf fa overMask
  let u2 := if overMask then 6 else 1
  !(checkNotEqvP {} counterMaskModel env 400 fa (.uncancelable (uid 0))) ||
    checkNotEqvP {} counterMaskModel env 400 alloc (.uncancelable (uid u2))

#guard fas.all fun fa => implies fa false
#guard !(implies .canceled true)

end CatsEffectInLean.Test.Phase6.ResourceSmoke

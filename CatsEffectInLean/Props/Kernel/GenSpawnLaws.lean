import CatsEffectInLean.Kernel.GenSpawn
import CatsEffectInLean.Props.Kernel.MonadCancelLaws

/-!
# `GenSpawn` laws, generic over the instance (Phase 4 step 2)

Each non-deprecated law of `laws/shared/src/main/scala/cats/effect/laws/GenSpawnLaws.scala`
(`L/` below) at Cats Effect `v3.7.1`, as a `Prop` over `M : GenSpawnOps F E` and an
equivalence `Eqv`. Conventions as in `CatsEffectInLean.Props.Kernel.MonadCancelLaws`.

- Where Scala infers `Nothing` for a type argument (`F.never` with no type argument on
  the left of `>>` or `forceR`), we use `Empty`.
- Not stated: `raceCanceledIdentityLeft/Right` (`L/GenSpawnLaws.scala:90-98`, deprecated
  since 3.5.0, not checked by `GenSpawnTests`), the commented-out `raceLeftCedeYields` and
  `raceRightCedeYields` (`L/GenSpawnLaws.scala:109-113`), and the `UniqueLaws` parent.
- PLACEHOLDER: "`IO` satisfies law X" needs the `IO` instance of `GenSpawnOps` from the
  model and the outcome-set `Eqv`. They come later. Do not add a fake instance.
-/

namespace CatsEffectInLean.Props.Kernel.GenSpawnLaws

open CatsEffectInLean.Kernel

variable {F : Type → Type} {E : Type}

/-- The `results` term of `raceDerivesFromRacePairLeft/Right` (`L/GenSpawnLaws.scala:29-54`
and `60-85`; the two bodies are the same, only the `racePair` arguments differ). It is
written out from the law file, not taken from `GenSpawn.Default.race`, because the law
compares the two. -/
def raceFromRacePair {A B : Type} (M : GenSpawnOps F E) (fa : F A) (fb : F B) :
    F (Sum A B) :=
  M.uncancelable fun poll =>
    M.flatMap (M.racePair fa fb) fun
      | .inl (oc, f) =>
        match oc with
        | .succeeded fa => M.productR f.cancel (M.map fa Sum.inl)
        | .errored ea => M.productR f.cancel (M.raiseError ea)
        | .canceled =>
          M.flatMap (M.productR f.cancel f.join) fun
            | .succeeded fb => M.map fb Sum.inr
            | .errored eb => M.raiseError eb
            | .canceled => M.productR (poll.apply M.canceled) M.never
      | .inr (f, oc) =>
        match oc with
        | .succeeded fb => M.productR f.cancel (M.map fb Sum.inr)
        | .errored eb => M.productR f.cancel (M.raiseError eb)
        | .canceled =>
          M.flatMap (M.productR f.cancel f.join) fun
            | .succeeded fa => M.map fa Sum.inl
            | .errored ea => M.raiseError ea
            | .canceled => M.productR (poll.apply M.canceled) M.never

/-- `L/GenSpawnLaws.scala:28-57`: `F.race(fa, F.never[B]) <-> results`, where `results`
is `raceFromRacePair M fa M.never`. Note: unlike `race` (`K/GenSpawn.scala:403`), the law
does not wrap `racePair` in `poll`. -/
def raceDerivesFromRacePairLeft (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A B : Type) (fa : F A),
    Eqv (M.race fa (M.never (A := B))) (raceFromRacePair M fa (M.never (A := B)))

/-- `L/GenSpawnLaws.scala:59-88`: `F.race(F.never[A], fb) <-> results`. -/
def raceDerivesFromRacePairRight (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A B : Type) (fb : F B),
    Eqv (M.race (M.never (A := A)) fb) (raceFromRacePair M (M.never (A := A)) fb)

/-- `L/GenSpawnLaws.scala:100-102`:
`F.race(F.never[Unit], fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_))) <->
fa.flatMap(r => F.pure(r.asRight[Unit])).handleErrorWith(F.raiseError(_))`. -/
def raceNeverNoncanceledIdentityLeft (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.race (M.never (A := Unit)) (M.handleErrorWith (M.flatMap fa M.pure) M.raiseError))
      (M.handleErrorWith (M.flatMap fa (fun r => M.pure (Sum.inr r))) M.raiseError)

/-- `L/GenSpawnLaws.scala:104-106`:
`F.race(fa.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_)), F.never[Unit]) <->
fa.flatMap(r => F.pure(r.asLeft[Unit])).handleErrorWith(F.raiseError(_))`. -/
def raceNeverNoncanceledIdentityRight (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.race (M.handleErrorWith (M.flatMap fa M.pure) M.raiseError) (M.never (A := Unit)))
      (M.handleErrorWith (M.flatMap fa (fun r => M.pure (Sum.inl r))) M.raiseError)

/-- `L/GenSpawnLaws.scala:115-116`:
`F.start(F.pure(a)).flatMap(_.join) <-> F.pure(Outcome.Succeeded(F.pure(a)))`. -/
def fiberPureIsOutcomeCompletedPure (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (a : A),
    Eqv (M.flatMap (M.start (M.pure a)) (fun f => f.join))
      (M.pure (Outcome.succeeded (M.pure a)))

/-- `L/GenSpawnLaws.scala:118-119`:
`F.start(F.raiseError[Unit](e)).flatMap(_.join) <-> F.pure(Outcome.Errored(e))`. -/
def fiberErrorIsOutcomeErrored (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (e : E),
    Eqv (M.flatMap (M.start (M.raiseError (A := Unit) e)) (fun f => f.join))
      (M.pure (Outcome.errored e))

/-- `L/GenSpawnLaws.scala:121-122`:
`F.start(F.never[Unit]).flatMap(f => f.cancel >> f.join) <-> F.pure(Outcome.Canceled())`. -/
def fiberCancelationIsOutcomeCanceled (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv (M.flatMap (M.start (M.never (A := Unit))) (fun f => M.flatMap f.cancel (fun _ => f.join)))
    (M.pure Outcome.canceled)

/-- `L/GenSpawnLaws.scala:124-125`:
`F.start(F.canceled).flatMap(_.join) <-> F.pure(Outcome.Canceled())`. -/
def fiberCanceledIsOutcomeCanceled (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv (M.flatMap (M.start M.canceled) (fun f => f.join)) (M.pure Outcome.canceled)

/-- `L/GenSpawnLaws.scala:127-128`:
`F.start(F.never[Unit]).flatMap(_.join) <-> F.never[Outcome[F, E, Unit]]`. -/
def fiberNeverIsNever (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv (M.flatMap (M.start (M.never (A := Unit))) (fun f => f.join))
    (M.never (A := Outcome F E Unit))

/-- `L/GenSpawnLaws.scala:130-131`: `F.start(F.never[Unit]).void <-> F.unit`. -/
def fiberStartOfNeverIsUnit (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv (M.void (M.start (M.never (A := Unit)))) M.unit

/-- `L/GenSpawnLaws.scala:133-141`.

```scala
val fa = fa0.flatMap(F.pure(_)).handleErrorWith(F.raiseError(_))
F.start(fa)
  .flatMap(_.join)
  .flatMap(oc => F.guarantee(oc.embed(F.canceled >> F.never[A]), f(oc))) <->
  F.guaranteeCase(fa)(f)
```
-/
def fiberJoinIsGuaranteeCase (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa0 : F A) (f : Outcome F E A → F Unit),
    let fa := M.handleErrorWith (M.flatMap fa0 M.pure) M.raiseError
    Eqv (M.flatMap (M.flatMap (M.start fa) (fun fib => fib.join)) (fun oc =>
          M.guarantee (oc.embed M.toMonadCancelOps
            (M.flatMap M.canceled (fun _ => M.never (A := A)))) (f oc)))
      (M.guaranteeCase fa f)

/-- `L/GenSpawnLaws.scala:143-144`: `F.never >> fa <-> F.never[A]`. -/
def neverDominatesOverFlatMap (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.flatMap (M.never (A := Empty)) (fun _ => fa)) (M.never (A := A))

/-- `L/GenSpawnLaws.scala:146-147`:
`F.uncancelable(_ => F.race(F.never[Unit], F.canceled)).void <-> F.never[Unit]`. -/
def uncancelableRaceNotInherited (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv (M.void (M.uncancelable (fun _ => M.race (M.never (A := Unit)) M.canceled)))
    (M.never (A := Unit))

/-- `L/GenSpawnLaws.scala:149-151`:
`F.start(F.never[Unit]).flatMap(f => F.uncancelable(_ => f.cancel) >> f.join) <->
F.pure(Outcome.Canceled())`. -/
def uncancelableCancelCancels (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv (M.flatMap (M.start (M.never (A := Unit))) (fun f =>
        M.flatMap (M.uncancelable (fun _ => f.cancel)) (fun _ => f.join)))
    (M.pure Outcome.canceled)

/-- `L/GenSpawnLaws.scala:153-155`:
`F.uncancelable(_ => F.start(F.never[Unit]).flatMap(f => f.cancel >> f.join)) <->
F.pure(Outcome.Canceled())`. -/
def uncancelableStartIsCancelable (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv (M.uncancelable (fun _ => M.flatMap (M.start (M.never (A := Unit))) (fun f =>
        M.flatMap f.cancel (fun _ => f.join))))
    (M.pure Outcome.canceled)

/-- `L/GenSpawnLaws.scala:157-158`: `F.forceR(F.never)(fa) <-> F.never`. -/
def forceRNeverIsNever (M : GenSpawnOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.forceR (M.never (A := Empty)) fa) (M.never (A := A))

/-- The laws that `GenSpawnTests.spawn` checks for `M`
(`laws/shared/src/main/scala/cats/effect/laws/GenSpawnTests.scala:195-216`), with the
`MonadCancel` parent laws. -/
def lawsFor (M : GenSpawnOps F E) (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  MonadCancelLaws.lawsFor M.toMonadCancelOps Eqv ∧
  raceDerivesFromRacePairLeft M Eqv ∧
  raceDerivesFromRacePairRight M Eqv ∧
  raceNeverNoncanceledIdentityLeft M Eqv ∧
  raceNeverNoncanceledIdentityRight M Eqv ∧
  fiberPureIsOutcomeCompletedPure M Eqv ∧
  fiberErrorIsOutcomeErrored M Eqv ∧
  fiberCancelationIsOutcomeCanceled M Eqv ∧
  fiberCanceledIsOutcomeCanceled M Eqv ∧
  fiberNeverIsNever M Eqv ∧
  fiberStartOfNeverIsUnit M Eqv ∧
  fiberJoinIsGuaranteeCase M Eqv ∧
  neverDominatesOverFlatMap M Eqv ∧
  uncancelableRaceNotInherited M Eqv ∧
  uncancelableCancelCancels M Eqv ∧
  uncancelableStartIsCancelable M Eqv ∧
  forceRNeverIsNever M Eqv

end CatsEffectInLean.Props.Kernel.GenSpawnLaws

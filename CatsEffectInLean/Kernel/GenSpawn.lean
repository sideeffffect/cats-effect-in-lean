import CatsEffectInLean.Kernel.MonadCancel

/-!
# `GenSpawn`, generic over `F` (Phase 4 step 1)

The typeclass `GenSpawn[F, E]` (`K/GenSpawn.scala:171`) as a Lean structure that extends
`MonadCancelOps`, and mirrors of its derived method bodies. Same design as
`CatsEffectInLean.Kernel.MonadCancel`. `K/` is
`kernel/shared/src/main/scala/cats/effect/kernel/` at Cats Effect `v3.7.1`.

Not modelled here:
- `background` (`K/GenSpawn.scala:216-217`): it needs a `Resource` model.
- `Unique#unique` (the `Unique[F]` parent): no law in scope uses it.
- `applicative` (`K/GenSpawn.scala:174`): it is `this`.
- The default `racePair` of `GenConcurrent` (`K/GenConcurrent.scala:339`). Here
  `racePair` is a field, so an instance gives its own.
-/

namespace CatsEffectInLean.Kernel

/-- The result type of `racePair` (`K/GenSpawn.scala:354-355`):
`Either[(Outcome[F, E, A], Fiber[F, E, B]), (Fiber[F, E, A], Outcome[F, E, B])]`. -/
abbrev RacePairResult (F : Type → Type) (E A B : Type) : Type :=
  Sum (Outcome F E A × Fiber F E B) (Fiber F E A × Outcome F E B)

/-- The operations of a `GenSpawn[F, E]` instance (`K/GenSpawn.scala:171`).

Abstract in `GenSpawn`: `start`, `never`, `cede`, `racePair`. Derived (default bodies in
`GenSpawn.Default`): `cancelable`, `raceOutcome`, `race`, `bothOutcome`, `both`.
`rootCancelScope` is `final` and `Cancelable` (`K/GenSpawn.scala:176`): this is the type
invariant `rootCancelScope_eq`. -/
structure GenSpawnOps (F : Type → Type) (E : Type) extends MonadCancelOps F E where
  /-- `K/GenSpawn.scala:176`: `final def rootCancelScope = CancelScope.Cancelable`. -/
  rootCancelScope_eq : rootCancelScope = .cancelable
  /-- `K/GenSpawn.scala:191`. -/
  start : {A : Type} → F A → F (Fiber F E A)
  /-- `K/GenSpawn.scala:297`. (`Async` overrides it: `K/Async.scala:168`.) -/
  never : {A : Type} → F A
  /-- `K/GenSpawn.scala:337`. -/
  cede : F Unit
  /-- `K/GenSpawn.scala:354`. -/
  racePair : {A B : Type} → F A → F B → F (RacePairResult F E A B)
  /-- `K/GenSpawn.scala:264`. -/
  cancelable : {A : Type} → F A → F Unit → F A
  /-- `K/GenSpawn.scala:370`. -/
  raceOutcome : {A B : Type} → F A → F B → F (Sum (Outcome F E A) (Outcome F E B))
  /-- `K/GenSpawn.scala:401`. -/
  race : {A B : Type} → F A → F B → F (Sum A B)
  /-- `K/GenSpawn.scala:442`. -/
  bothOutcome : {A B : Type} → F A → F B → F (Outcome F E A × Outcome F E B)
  /-- `K/GenSpawn.scala:474`. -/
  both : {A B : Type} → F A → F B → F (A × B)

variable {F : Type → Type} {E : Type}

/-- `Outcome#embedNever` (`K/Outcome.scala:76-77`): `embed(F.never)`. -/
def Outcome.embedNever {A : Type} (M : GenSpawnOps F E) (oc : Outcome F E A) : F A :=
  oc.embed M.toMonadCancelOps M.never

/-- `Fiber#joinWithNever` (`K/Fiber.scala:73-74`): `joinWith(F.never)`. -/
def Fiber.joinWithNever {A : Type} (M : GenSpawnOps F E) (f : Fiber F E A) : F A :=
  f.joinWith M.toMonadCancelOps M.never

namespace GenSpawn.Default

/-- `GenSpawn#cancelable` (`K/GenSpawn.scala:264-271`).

```scala
uncancelable { poll =>
  start(fa) flatMap { fiber =>
    poll(fiber.join)
      .onCancel(fin.guarantee(fiber.cancel))
      .flatMap(_.embed(poll(canceled *> never)))
  }
}
```
-/
def cancelable {A : Type} (M : GenSpawnOps F E) (fa : F A) (fin : F Unit) : F A :=
  M.uncancelable fun poll =>
    M.flatMap (M.start fa) fun fiber =>
      M.flatMap
        (M.onCancel (poll.apply fiber.join) (M.guarantee fin fiber.cancel))
        (fun oc => oc.embed M.toMonadCancelOps
          (poll.apply (M.productR M.canceled M.never)))

/-- `GenSpawn#raceOutcome` (`K/GenSpawn.scala:370-376`).

```scala
uncancelable { poll =>
  poll(racePair(fa, fb)).flatMap {
    case Left((oc, f)) => f.cancel.as(Left(oc))
    case Right((f, oc)) => f.cancel.as(Right(oc))
  }
}
```
-/
def raceOutcome {A B : Type} (M : GenSpawnOps F E) (fa : F A) (fb : F B) :
    F (Sum (Outcome F E A) (Outcome F E B)) :=
  M.uncancelable fun poll =>
    M.flatMap (poll.apply (M.racePair fa fb)) fun
      | .inl (oc, f) => M.as f.cancel (Sum.inl oc)
      | .inr (f, oc) => M.as f.cancel (Sum.inr oc)

/-- `GenSpawn#race` (`K/GenSpawn.scala:401-427`). `x *> y` is `productR(x)(y)`.
`f.cancel *> f.join flatMap {...}` is `(f.cancel *> f.join) flatMap {...}`: an
alphanumeric infix operator has the lowest precedence in Scala.

```scala
uncancelable { poll =>
  poll(racePair(fa, fb)).flatMap {
    case Left((oc, f)) =>
      oc match {
        case Outcome.Succeeded(fa) => f.cancel *> fa.map(Left(_))
        case Outcome.Errored(ea) => f.cancel *> raiseError(ea)
        case Outcome.Canceled() =>
          f.cancel *> f.join flatMap {
            case Outcome.Succeeded(fb) => fb.map(Right(_))
            case Outcome.Errored(eb) => raiseError(eb)
            case Outcome.Canceled() => poll(canceled) *> never
          }
      }
    case Right((f, oc)) => (mirror image)
  }
}
```
-/
def race {A B : Type} (M : GenSpawnOps F E) (fa : F A) (fb : F B) : F (Sum A B) :=
  M.uncancelable fun poll =>
    M.flatMap (poll.apply (M.racePair fa fb)) fun
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

/-- `GenSpawn#bothOutcome` (`K/GenSpawn.scala:442-448`).

```scala
uncancelable { poll =>
  poll(racePair(fa, fb)).flatMap {
    case Left((oc, f)) => poll(f.join).onCancel(f.cancel).tupleLeft(oc)
    case Right((f, oc)) => poll(f.join).onCancel(f.cancel).tupleRight(oc)
  }
}
```
-/
def bothOutcome {A B : Type} (M : GenSpawnOps F E) (fa : F A) (fb : F B) :
    F (Outcome F E A × Outcome F E B) :=
  M.uncancelable fun poll =>
    M.flatMap (poll.apply (M.racePair fa fb)) fun
      | .inl (oc, f) => M.tupleLeft (M.onCancel (poll.apply f.join) f.cancel) oc
      | .inr (f, oc) => M.tupleRight (M.onCancel (poll.apply f.join) f.cancel) oc

/-- `GenSpawn#both` (`K/GenSpawn.scala:474-500`). `fa.product(fb)` is `product(fa, fb)`.
`f.cancel *> poll(canceled) *> never` is left-associative:
`(f.cancel *> poll(canceled)) *> never`.

```scala
uncancelable { poll =>
  poll(racePair(fa, fb)).flatMap {
    case Left((oc, f)) =>
      oc match {
        case Outcome.Succeeded(fa) =>
          poll(f.join).onCancel(f.cancel).flatMap {
            case Outcome.Succeeded(fb) => fa.product(fb)
            case Outcome.Errored(eb) => raiseError(eb)
            case Outcome.Canceled() => poll(canceled) *> never
          }
        case Outcome.Errored(ea) => f.cancel *> raiseError(ea)
        case Outcome.Canceled() => f.cancel *> poll(canceled) *> never
      }
    case Right((f, oc)) => (mirror image)
  }
}
```
-/
def both {A B : Type} (M : GenSpawnOps F E) (fa : F A) (fb : F B) : F (A × B) :=
  M.uncancelable fun poll =>
    M.flatMap (poll.apply (M.racePair fa fb)) fun
      | .inl (oc, f) =>
        match oc with
        | .succeeded fa =>
          M.flatMap (M.onCancel (poll.apply f.join) f.cancel) fun
            | .succeeded fb => M.product fa fb
            | .errored eb => M.raiseError eb
            | .canceled => M.productR (poll.apply M.canceled) M.never
        | .errored ea => M.productR f.cancel (M.raiseError ea)
        | .canceled => M.productR (M.productR f.cancel (poll.apply M.canceled)) M.never
      | .inr (f, oc) =>
        match oc with
        | .succeeded fb =>
          M.flatMap (M.onCancel (poll.apply f.join) f.cancel) fun
            | .succeeded fa => M.product fa fb
            | .errored ea => M.raiseError ea
            | .canceled => M.productR (poll.apply M.canceled) M.never
        | .errored eb => M.productR f.cancel (M.raiseError eb)
        | .canceled => M.productR (M.productR f.cancel (poll.apply M.canceled)) M.never

end GenSpawn.Default

/-- The instance `M` does not override the derived `GenSpawn` methods. -/
structure GenSpawnOps.UsesKernelDefaults (M : GenSpawnOps F E) : Prop where
  cancelable : ∀ {A : Type} (fa : F A) (fin : F Unit),
    M.cancelable fa fin = GenSpawn.Default.cancelable M fa fin
  raceOutcome : ∀ {A B : Type} (fa : F A) (fb : F B),
    M.raceOutcome fa fb = GenSpawn.Default.raceOutcome M fa fb
  race : ∀ {A B : Type} (fa : F A) (fb : F B),
    M.race fa fb = GenSpawn.Default.race M fa fb
  bothOutcome : ∀ {A B : Type} (fa : F A) (fb : F B),
    M.bothOutcome fa fb = GenSpawn.Default.bothOutcome M fa fb
  both : ∀ {A B : Type} (fa : F A) (fb : F B),
    M.both fa fb = GenSpawn.Default.both M fa fb

end CatsEffectInLean.Kernel

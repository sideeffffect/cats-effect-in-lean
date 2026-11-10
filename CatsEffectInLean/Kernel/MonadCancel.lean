/-!
# `MonadCancel`, generic over `F` (Phase 4 step 1)

The typeclass `MonadCancel[F, E]` as a Lean structure of operations over an abstract
`F : Type → Type`, and mirrors of the derived (non-abstract) method bodies.

Citations are `<path>:<line>` at Cats Effect `v3.7.1`. `K/` is
`kernel/shared/src/main/scala/cats/effect/kernel/`. `cats/` is `cats-core` 2.13.0
(the version that Cats Effect v3.7.1 uses, `build.sbt:323`).

Design (see `wiki/cats-effect/kernel-typeclasses-model.md`):

- Scala has virtual dispatch: an instance can override a derived method, and a derived
  body calls the instance's methods. So each method that a body or a law calls is a
  field of `MonadCancelOps`, abstract or not. An instance gives all fields.
- The default bodies are separate definitions in `MonadCancel.Default` and
  `Cats.Default`. Each takes the whole instance `M` and calls `M`'s fields, the same
  calls in the same nesting as the Scala body.
- "The instance does not override method `m`" is the hypothesis
  `M.m = MonadCancel.Default.m M`. It is not built in.
- Laws are not in this file. They are `Prop`s in `CatsEffectInLean.Props.Kernel`.

Not modelled here: `tailRecM` (stack safety only), `ap`, `productL`, `redeem*`,
`adaptError`, `rethrow`, the `MonadError` laws, and the transformer instances
(`OptionT`, `EitherT`, ...).

A Scala `throw` in user code (for example in `use` of `bracketFull`) has no generic
counterpart: a user function returns an `F` value. An instance models a throw with its
own error value.
-/

namespace CatsEffectInLean.Kernel

/-- `CancelScope` (`K/CancelScope.scala:19-23`). -/
inductive CancelScope where
  /-- `CancelScope.Cancelable` (`K/CancelScope.scala:22`). -/
  | cancelable
  /-- `CancelScope.Uncancelable` (`K/CancelScope.scala:23`). -/
  | uncancelable
  deriving DecidableEq, Repr

/-- `Outcome[F, E, A]` (`K/Outcome.scala:70`, cases at `K/Outcome.scala:252-254`). -/
inductive Outcome (F : Type → Type) (E A : Type) : Type where
  /-- `Succeeded(fa)` (`K/Outcome.scala:252`). -/
  | succeeded (fa : F A)
  /-- `Errored(e)` (`K/Outcome.scala:253`). -/
  | errored (e : E)
  /-- `Canceled()` (`K/Outcome.scala:254`). -/
  | canceled

/-- `Outcome#fold` (`K/Outcome.scala:90-95`). Same case order as Scala. -/
def Outcome.fold {F : Type → Type} {E A B : Type} (oc : Outcome F E A)
    (canceled : B) (errored : E → B) (completed : F A → B) : B :=
  match oc with
  | .canceled => canceled
  | .errored e => errored e
  | .succeeded fa => completed fa

/-- `Poll[F]`, a natural transformation `F ~> F` (`K/Poll.scala:25`). -/
structure Poll (F : Type → Type) where
  apply : {A : Type} → F A → F A

/-- `Fiber[F, E, A]` (`K/Fiber.scala:28`). `cancel` (`K/Fiber.scala:48`) and `join`
(`K/Fiber.scala:54`) are abstract. -/
structure Fiber (F : Type → Type) (E A : Type) where
  cancel : F Unit
  join : F (Outcome F E A)

/-- The operations of a `MonadCancel[F, E]` instance (`K/MonadCancel.scala:210`).

Field groups:
1. Abstract in `cats`: `pure`, `flatMap`, `raiseError`, `handleErrorWith`.
2. Concrete in `cats`, but an instance can override them (`IO` overrides most). The
   `cats` default bodies are in `Cats.Default`.
3. Abstract in `MonadCancel`: `rootCancelScope`, `forceR`, `uncancelable`, `canceled`,
   `onCancel`.
4. Concrete in `MonadCancel` (derived): `guarantee`, `guaranteeCase`, `bracket`,
   `bracketCase`, `bracketFull`. Default bodies in `MonadCancel.Default`.

`Either[E, A]` is `Sum E A` (`Left` is `inl`). A `PartialFunction[E, F[Unit]]` is
`E → Option (F Unit)`. Two-argument Scala functions are curried. -/
structure MonadCancelOps (F : Type → Type) (E : Type) where
  -- 1. abstract in cats
  /-- `Applicative#pure`. -/
  pure : {A : Type} → A → F A
  /-- `FlatMap#flatMap`. -/
  flatMap : {A B : Type} → F A → (A → F B) → F B
  /-- `ApplicativeError#raiseError`. -/
  raiseError : {A : Type} → E → F A
  /-- `ApplicativeError#handleErrorWith`. -/
  handleErrorWith : {A : Type} → F A → (E → F A) → F A
  -- 2. concrete in cats, overridable
  /-- `Functor#map` (default `cats/Monad.scala:34`). -/
  map : {A B : Type} → F A → (A → B) → F B
  /-- `Applicative#unit` (default `cats/Applicative.scala:68`). -/
  unit : F Unit
  /-- `Functor#as` (default `cats/Functor.scala:143`). -/
  as : {A B : Type} → F A → B → F B
  /-- `Functor#void` (default `cats/Functor.scala:102`). -/
  void : {A : Type} → F A → F Unit
  /-- `Apply#productR`, alias `*>` (default `cats/FlatMap.scala:119`). -/
  productR : {A B : Type} → F A → F B → F B
  /-- `Apply#map2` (default `cats/FlatMap.scala:113`). -/
  map2 : {A B Z : Type} → F A → F B → (A → B → Z) → F Z
  /-- `Semigroupal#product` (default `cats/FlatMap.scala:107`). -/
  product : {A B : Type} → F A → F B → F (A × B)
  /-- `Functor#tupleLeft` (default `cats/Functor.scala:157`). -/
  tupleLeft : {A B : Type} → F A → B → F (B × A)
  /-- `Functor#tupleRight` (default `cats/Functor.scala:171`). -/
  tupleRight : {A B : Type} → F A → B → F (A × B)
  /-- `FlatMap#flatTap` (default `cats/FlatMap.scala:172`). -/
  flatTap : {A B : Type} → F A → (A → F B) → F A
  /-- `ApplicativeError#handleError` (default `cats/ApplicativeError.scala:105`). -/
  handleError : {A : Type} → F A → (E → A) → F A
  /-- `ApplicativeError#onError` (default `cats/ApplicativeError.scala:261`). -/
  onError : {A : Type} → F A → (E → Option (F Unit)) → F A
  /-- `ApplicativeError#attempt` (default `cats/ApplicativeError.scala:135`). -/
  attempt : {A : Type} → F A → F (Sum E A)
  -- 3. abstract in MonadCancel
  /-- `K/MonadCancel.scala:219`. -/
  rootCancelScope : CancelScope
  /-- `K/MonadCancel.scala:224`. -/
  forceR : {A B : Type} → F A → F B → F B
  /-- `K/MonadCancel.scala:272`. -/
  uncancelable : {A : Type} → (Poll F → F A) → F A
  /-- `K/MonadCancel.scala:292`. -/
  canceled : F Unit
  /-- `K/MonadCancel.scala:324`. -/
  onCancel : {A : Type} → F A → F Unit → F A
  -- 4. derived in MonadCancel, overridable
  /-- `K/MonadCancel.scala:344`. -/
  guarantee : {A : Type} → F A → F Unit → F A
  /-- `K/MonadCancel.scala:365`. -/
  guaranteeCase : {A : Type} → F A → (Outcome F E A → F Unit) → F A
  /-- `K/MonadCancel.scala:397`. -/
  bracket : {A B : Type} → F A → (A → F B) → (A → F Unit) → F B
  /-- `K/MonadCancel.scala:423`. -/
  bracketCase : {A B : Type} → F A → (A → F B) → (A → Outcome F E B → F Unit) → F B
  /-- `K/MonadCancel.scala:447`. -/
  bracketFull : {A B : Type} →
    (Poll F → F A) → (A → F B) → (A → Outcome F E B → F Unit) → F B

variable {F : Type → Type} {E : Type}

/-- `Outcome#embed` (`K/Outcome.scala:73-74`): `fold(onCancel, F.raiseError, identity)`. -/
def Outcome.embed {A : Type} (M : MonadCancelOps F E) (oc : Outcome F E A)
    (onCancel : F A) : F A :=
  oc.fold onCancel M.raiseError id

/-- `Fiber#joinWith` (`K/Fiber.scala:63-64`): `join.flatMap(_.embed(onCancel))`. -/
def Fiber.joinWith {A : Type} (M : MonadCancelOps F E) (f : Fiber F E A)
    (onCancel : F A) : F A :=
  M.flatMap f.join (fun oc => oc.embed M onCancel)

/-- `Fiber#joinWithUnit` (`K/Fiber.scala:83-86`): `joinWith(F.unit.asInstanceOf[F[A]])`.
Simplification: Scala allows any `A` with `Unit <:< A`; here `A = Unit`. -/
def Fiber.joinWithUnit (M : MonadCancelOps F E) (f : Fiber F E Unit) : F Unit :=
  f.joinWith M M.unit

namespace Cats.Default

/-- `cats/Monad.scala:34-35`: `flatMap(fa)(a => pure(f(a)))`. -/
def map {A B : Type} (M : MonadCancelOps F E) (fa : F A) (f : A → B) : F B :=
  M.flatMap fa (fun a => M.pure (f a))

/-- `cats/Applicative.scala:68`: `pure(())`. -/
def unit (M : MonadCancelOps F E) : F Unit :=
  M.pure ()

/-- `cats/Functor.scala:143`: `map(fa)(_ => b)`. -/
def as {A B : Type} (M : MonadCancelOps F E) (fa : F A) (b : B) : F B :=
  M.map fa (fun _ => b)

/-- `cats/Functor.scala:102`: `as(fa, ())`. -/
def void {A : Type} (M : MonadCancelOps F E) (fa : F A) : F Unit :=
  M.as fa ()

/-- `cats/FlatMap.scala:119-120`: `flatMap(fa)(_ => fb)`. -/
def productR {A B : Type} (M : MonadCancelOps F E) (fa : F A) (fb : F B) : F B :=
  M.flatMap fa (fun _ => fb)

/-- `cats/FlatMap.scala:113-114`: `flatMap(fa)(a => map(fb)(b => f(a, b)))`. -/
def map2 {A B Z : Type} (M : MonadCancelOps F E) (fa : F A) (fb : F B)
    (f : A → B → Z) : F Z :=
  M.flatMap fa (fun a => M.map fb (fun b => f a b))

/-- `cats/FlatMap.scala:107-108`: `flatMap(fa)(a => map(fb)(b => (a, b)))`. -/
def product {A B : Type} (M : MonadCancelOps F E) (fa : F A) (fb : F B) : F (A × B) :=
  M.flatMap fa (fun a => M.map fb (fun b => (a, b)))

/-- `cats/Functor.scala:157`: `map(fa)(a => (b, a))`. -/
def tupleLeft {A B : Type} (M : MonadCancelOps F E) (fa : F A) (b : B) : F (B × A) :=
  M.map fa (fun a => (b, a))

/-- `cats/Functor.scala:171`: `map(fa)(a => (a, b))`. -/
def tupleRight {A B : Type} (M : MonadCancelOps F E) (fa : F A) (b : B) : F (A × B) :=
  M.map fa (fun a => (a, b))

/-- `cats/FlatMap.scala:172-173`: `flatMap(fa)(a => as(f(a), a))`. -/
def flatTap {A B : Type} (M : MonadCancelOps F E) (fa : F A) (f : A → F B) : F A :=
  M.flatMap fa (fun a => M.as (f a) a)

/-- `cats/ApplicativeError.scala:105`: `handleErrorWith(fa)(f.andThen(pure))`. -/
def handleError {A : Type} (M : MonadCancelOps F E) (fa : F A) (f : E → A) : F A :=
  M.handleErrorWith fa (fun e => M.pure (f e))

/-- `cats/ApplicativeError.scala:261-262`:
`handleErrorWith(fa)(e => pf.andThen(map2(_, raiseError[A](e))((_, b) => b)).applyOrElse(e, raiseError))`. -/
def onError {A : Type} (M : MonadCancelOps F E) (fa : F A) (pf : E → Option (F Unit)) : F A :=
  M.handleErrorWith fa (fun e =>
    match pf e with
    | some fu => M.map2 fu (M.raiseError e) (fun _ b => b)
    | none => M.raiseError e)

/-- `cats/ApplicativeError.scala:135-138`:
`handleErrorWith(map(fa)(Right(_)))(e => pure(Left(e)))`. -/
def attempt {A : Type} (M : MonadCancelOps F E) (fa : F A) : F (Sum E A) :=
  M.handleErrorWith (M.map fa Sum.inr) (fun e => M.pure (Sum.inl e))

end Cats.Default

namespace MonadCancel.Default

/-- `MonadCancel#guarantee` (`K/MonadCancel.scala:344-345`): `guaranteeCase(fa)(_ => fin)`. -/
def guarantee {A : Type} (M : MonadCancelOps F E) (fa : F A) (fin : F Unit) : F A :=
  M.guaranteeCase fa (fun _ => fin)

/-- `MonadCancel#guaranteeCase` (`K/MonadCancel.scala:365-372`).

```scala
uncancelable { poll =>
  val finalized = onCancel(poll(fa), fin(Outcome.canceled))
  val handled = onError(finalized) {
    case e => handleError(fin(Outcome.errored(e)))(_ => ())
  }
  flatTap(handled)(a => fin(Outcome.succeeded(pure(a))))
}
```
-/
def guaranteeCase {A : Type} (M : MonadCancelOps F E) (fa : F A)
    (fin : Outcome F E A → F Unit) : F A :=
  M.uncancelable fun poll =>
    let finalized := M.onCancel (poll.apply fa) (fin .canceled)
    let handled := M.onError finalized (fun e =>
      some (M.handleError (fin (.errored e)) (fun _ => ())))
    M.flatTap handled (fun a => fin (.succeeded (M.pure a)))

/-- `MonadCancel#bracket` (`K/MonadCancel.scala:397-398`):
`bracketCase(acquire)(use)((a, _) => release(a))`. -/
def bracket {A B : Type} (M : MonadCancelOps F E) (acquire : F A) (use : A → F B)
    (release : A → F Unit) : F B :=
  M.bracketCase acquire use (fun a _ => release a)

/-- `MonadCancel#bracketCase` (`K/MonadCancel.scala:423-425`):
`bracketFull(_ => acquire)(use)(release)`. -/
def bracketCase {A B : Type} (M : MonadCancelOps F E) (acquire : F A) (use : A → F B)
    (release : A → Outcome F E B → F Unit) : F B :=
  M.bracketFull (fun _ => acquire) use release

/-- `MonadCancel#bracketFull` (`K/MonadCancel.scala:447-455`).

```scala
uncancelable { poll =>
  acquire(poll).flatMap { a =>
    guaranteeCase(poll(unit >> use(a)))(release(a, _))
  }
}
```
`unit >> use(a)` is the `cats` syntax `flatMap(unit)(_ => use(a))`
(`cats/syntax/flatMap.scala:54`), not `productR`. -/
def bracketFull {A B : Type} (M : MonadCancelOps F E) (acquire : Poll F → F A)
    (use : A → F B) (release : A → Outcome F E B → F Unit) : F B :=
  M.uncancelable fun poll =>
    M.flatMap (acquire poll) fun a =>
      M.guaranteeCase (poll.apply (M.flatMap M.unit (fun _ => use a))) (fun oc => release a oc)

end MonadCancel.Default

/-- The instance `M` does not override the derived `MonadCancel` methods: each field is
its default body from `MonadCancel.Default`. An instance can satisfy some of these
equations and not others; use the single fields as hypotheses. -/
structure MonadCancelOps.UsesKernelDefaults (M : MonadCancelOps F E) : Prop where
  guarantee : ∀ {A : Type} (fa : F A) (fin : F Unit),
    M.guarantee fa fin = MonadCancel.Default.guarantee M fa fin
  guaranteeCase : ∀ {A : Type} (fa : F A) (fin : Outcome F E A → F Unit),
    M.guaranteeCase fa fin = MonadCancel.Default.guaranteeCase M fa fin
  bracket : ∀ {A B : Type} (acquire : F A) (use : A → F B) (release : A → F Unit),
    M.bracket acquire use release = MonadCancel.Default.bracket M acquire use release
  bracketCase : ∀ {A B : Type} (acquire : F A) (use : A → F B)
      (release : A → Outcome F E B → F Unit),
    M.bracketCase acquire use release = MonadCancel.Default.bracketCase M acquire use release
  bracketFull : ∀ {A B : Type} (acquire : Poll F → F A) (use : A → F B)
      (release : A → Outcome F E B → F Unit),
    M.bracketFull acquire use release = MonadCancel.Default.bracketFull M acquire use release

/-- `MonadCancel.Uncancelable` (`K/MonadCancel.scala:593-610`): the mixin for monads
without cancelation (for example `SyncIO`). The instance `M` uses its four bodies:
`rootCancelScope = Uncancelable`, `canceled = unit`, `onCancel(fa, fin) = fa`,
`uncancelable(body) = body(IdPoll)` with `IdPoll(fa) = fa` (`K/MonadCancel.scala:595-597`). -/
structure MonadCancelOps.IsUncancelableMixin (M : MonadCancelOps F E) : Prop where
  rootCancelScope : M.rootCancelScope = .uncancelable
  canceled : M.canceled = M.unit
  onCancel : ∀ {A : Type} (fa : F A) (fin : F Unit), M.onCancel fa fin = fa
  uncancelable : ∀ {A : Type} (body : Poll F → F A),
    M.uncancelable body = body ⟨fun fa => fa⟩

end CatsEffectInLean.Kernel

import CatsEffectInLean.Model.Outcomes
import CatsEffectInLean.Kernel.MonadCancel

/-!
# The `IO` operations of the kernel typeclasses (Phase 4)

The `MonadCancel[IO, Throwable]` operations as the model builds them: each operation is the
`IO` constructor (or the `IO.scala` body) that `IO.asyncForIO` (`IOAsync`, `IO.scala:1996`)
calls at `v3.7.1`. `IO` below is `core/shared/src/main/scala/cats/effect/IO.scala`.

## How `F[A]` maps to the model

* `F[A]` is `Model.IO`. The type parameter `A` is erased: all values are untyped `Val` (user
  decision 1, `wiki/methodology/project-plan.md`).
* `E` (`Throwable`) is `Err`.
* A Scala lambda (`A => IO[B]`, `Poll[IO] => IO[A]`, `Throwable => IO[A]`, `A => B`) is user
  code: a `Fn.user id` in the term, and the user environment `env : UserEnv` gives its
  behaviour. The law statements quantify over `env` and over the ids, and take as a hypothesis
  that `env` runs each id as the Scala lambda of the law (`Lam.*` below). So a program is a
  closed `IO` term plus the user environment.
* `Poll[IO]` is the value `Val.poll id fiber` that the `Uncancelable` branch passes to the body
  (`IOFiber.scala:562-567`). `poll(ioa)` is `UnmaskRunLoop(ioa, id, fiber)`
  (`IOFiber.scala:564-567`), so the lambda `poll => poll(fa)` returns `.unmaskRunLoop fa id fiber`.

## Why this is not an instance of `Kernel.MonadCancelOps`

`MonadCancelOps F E` (`CatsEffectInLean/Kernel/MonadCancel.lean`) needs
`F : Type → Type`, `pure : {A : Type} → A → F A`, and Lean functions `A → F B` as arguments.

1. The model is untyped. `pure a` for an arbitrary Lean type `A` (for example `Nat → Nat`)
   needs an injection `A → Val`. It does not exist for all `A` (`Val` is countable). A choice
   of an injection for the countable types is noncomputable, and it makes every
   `map`/`flatMap` decode values. The decoded result of a term that is not well-typed is
   undefined.
2. A typed deep embedding (an inductive family `Tm : Type → Type` with
   `flatMap : Tm B → (B → Tm A) → Tm A`) quantifies over `B : Type` in a constructor, so it
   lives in `Type 1`, not in `Type`.
3. The model syntax is first-order (`Fn.user id`), by design (kernel evaluation). A Lean
   closure must become an id plus an environment entry. The closures of the term that a
   closure returns depend on the run-time argument, so their ids must encode run-time values.

So the `IO` laws are stated directly over these first-order operations (`Props/IO/`). The
statement of each law uses the same calls, in the same nesting, as the generic law in
`CatsEffectInLean/Props/Kernel/MonadCancelLaws.lean`, with the `IO` body of each call.
-/

namespace CatsEffectInLean.Model.IOI

/-! ## Operations -/

/-- `IOAsync.pure` (`IO.scala:2017-2018`) → `IO.pure` (`IO.scala:1640`) = `Pure(value)`. -/
def pure (v : Val) : IO := .pure v

/-- `IOAsync.raiseError` (`IO.scala:2048-2049`) → `IO.raiseError` (`IO.scala:1652`) =
`Error(t)`. -/
def raiseError (e : Err) : IO := .error e

/-- `IOAsync.flatMap` (`IO.scala:2101-2102`) → `IO#flatMap` (`IO.scala:469-470`) =
`FlatMap(this, f, event)`. Also the cats syntax `fa >> fb`, which is
`F.flatMap(fa)(_ => fb)` (`cats/syntax/flatMap.scala:54`), with `f` the lambda `_ => fb`. -/
def flatMap (fa : IO) (f : Fn) : IO := .flatMap fa f

/-- `IOAsync.map` (`IO.scala:2098-2099`) → `IO#map` (`IO.scala:579`) = `Map(this, f, event)`. -/
def map (fa : IO) (f : Fn) : IO := .map fa f

/-- `IOAsync.unit` (`IO.scala:2020-2021`) → `IO.unit` (`IO.scala:1720`) = `Pure(())`
(`IO.scala:1715`). -/
def unit : IO := .pure .unit

/-- `IOAsync.as` (`IO.scala:2008-2009`) → `IO#as` (`IO.scala:182-183`) = `map(_ => b)`.
`k` is the lambda `_ => b` (`Lam.constVal`). -/
def as (fa : IO) (k : Fn) : IO := map fa k

/-- `IOAsync.void` (`IO.scala:2152`) → `IO#void` (`IO.scala:961-962`) = `map(_ => ())`. The
lambda is the runtime closure `RtFn.voidK`. -/
def void (fa : IO) : IO := map fa (.rt .voidK)

/-- `IOAsync.productR` (`IO.scala:2081-2082`) → `IO#productR` (`IO.scala:903-904`) =
`flatMap(_ => that)`. `k` is the lambda `_ => that` (`Lam.constProg`). -/
def productR (fa : IO) (k : Fn) : IO := flatMap fa k

/-- `IOAsync.attempt` (`IO.scala:2011-2012`) → `IO#attempt` (`IO.scala:200-201`) =
`Attempt(this)`. -/
def attempt (fa : IO) : IO := .attempt fa

/-- `IOAsync.handleErrorWith` (`IO.scala:2045-2046`) → `IO#handleErrorWith`
(`IO.scala:549-550`) = `HandleErrorWith(this, f, event)`. -/
def handleErrorWith (fa : IO) (f : Fn) : IO := .handleErrorWith fa f

/-- `IOAsync.handleError` (`IO.scala:2029-2030`) → `IO#handleError` (`IO.scala:532-533`) =
`handleErrorWith(t => IO.pure(f(t)))`. `h` is the lambda `t => IO.pure(f(t))`. -/
def handleError (fa : IO) (h : Fn) : IO := handleErrorWith fa h

/-- `IOAsync.canceled` (`IO.scala:2073-2074`) → `IO.canceled` (`IO.scala:1501`) = `Canceled`. -/
def canceled : IO := .canceled

/-- `IOAsync.onCancel` (`IO.scala:2059-2060`) → `IO#onCancel` (`IO.scala:590-591`) =
`OnCancel(this, fin)`. -/
def onCancel (fa fin : IO) : IO := .onCancel fa fin

/-- `IOAsync.uncancelable` (`IO.scala:2095-2096`) → `IO.uncancelable` (`IO.scala:1712-1713`)
= `Uncancelable(body, event)`. -/
def uncancelable (body : Fn) : IO := .uncancelable body

/-- `IOAsync.forceR` (`IO.scala:2014-2015`) → `IO#forceR` (`IO.scala:452-454`) =
`asInstanceOf[IO[Unit]].handleError(_ => ()).productR(that)`. `h` is the `handleError` lambda
`t => IO.pure(())` (`IO.scala:532-533` with `f = _ => ()`); `k` is the `productR` lambda
`_ => that`. -/
def forceR (fa : IO) (h k : Fn) : IO := productR (handleError fa h) k

/-- `IOAsync.rootCancelScope`: `GenSpawn` makes it `Cancelable` (`K/GenSpawn.scala:176`). -/
def rootCancelScope : CatsEffectInLean.Kernel.CancelScope := .cancelable

/-! ## Lambdas of the laws

Each `Lam.*` says that user function `id` behaves as one Scala lambda. The run loop calls
user code with `UserEnv.callV` (`CatsEffectInLean/Model/Step.lean`, `callUser`). The lambdas of
the laws have no side effects. -/

namespace Lam

/-- `_ => p`: returns program `p` for each argument (the `>>` and `productR` lambdas, and the
`uncancelable` bodies that ignore `poll`). -/
def constProg (env : UserEnv) (id : Nat) (p : IO) : Prop :=
  ∀ (a : Val) (v : View), env.callV id a v = { out := .prog p }

/-- `_ => b`: returns value `b` for each argument (the `as` lambda). -/
def constVal (env : UserEnv) (id : Nat) (b : Val) : Prop :=
  ∀ (a : Val) (v : View), env.callV id a v = { out := .ret b }

/-- `poll => poll(fa)`: for the `Poll` value `Val.poll m s` it returns
`UnmaskRunLoop(fa, m, s)` (`IOFiber.scala:564-567`). -/
def pollApply (env : UserEnv) (id : Nat) (fa : IO) : Prop :=
  ∀ (m s : Nat) (v : View), env.callV id (.poll m s) v = { out := .prog (.unmaskRunLoop fa m s) }

end Lam

end CatsEffectInLean.Model.IOI

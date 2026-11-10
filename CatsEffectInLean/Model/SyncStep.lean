import CatsEffectInLean.Model.SyncIO
import CatsEffectInLean.Model.Run
import CatsEffectInLean.Kernel.MonadCancel

/-!
# `IO#syncStep` with `G = SyncIO`

Phase 5 (CE-0001). A mirror of `SyncStep.interpret` and `IO#syncStep` at `v3.7.1`
(`core/shared/src/main/scala/cats/effect/IO.scala`, cited as `IO.scala`):

* `IO#syncStep(limit)` = `IO.asyncForIO.syncStep[SyncIO, A](this, limit)` (`IO.scala:1161-1162`)
  = `G.map(SyncStep.interpret(fa, limit, SyncStep.MaxSteps))(_.map(_._1))` (`IO.scala:2173-2178`).
* `SyncStep.interpret(io, limit, stepsUntilDefer)` (`IO.scala:2348-2402`), branch by branch,
  with `G = SyncIO`. The `SyncIO` operations that `interpret` calls build these nodes:
  `G.pure` = `Pure` (`SyncIO.scala:595-596`), `G.raiseError` = `Error` (`SyncIO.scala:598-599`),
  `G.delay(t)` = `suspend(Delay)(t)` (`kernel/shared/src/main/scala/cats/effect/kernel/Sync.scala:52-53`)
  = `Suspend` (`SyncIO.scala:613-614`), `G.defer(t)` = `flatMap(delay(t))(x => x)` (`Sync.scala:61-62`),
  `G.realTime`/`G.monotonic` = `RealTime`/`Monotonic` (`SyncIO.scala:607-611`), `flatMap` =
  `FlatMap` (`SyncIO.scala:604-605`), `handleErrorWith` = `HandleErrorWith` (`SyncIO.scala:601-602`),
  `map` = `flatMap(fa)(a => pure(f(a)))` (cats-core 2.13.0 `cats/Monad.scala:34-35`), and
  `handleError(fa)(f)` = `handleErrorWith(fa)(f.andThen(pure))` (cats-core 2.13.0
  `cats/ApplicativeError.scala:105`).
* The root cancel scope of `SyncIO` is `Uncancelable`: `SyncIOSync` mixes in
  `MonadCancel.Uncancelable` (`SyncIO.scala:590-593`), whose `rootCancelScope` is
  `CancelScope.Uncancelable` (`kernel/shared/src/main/scala/cats/effect/kernel/MonadCancel.scala:599`).
  So the `IO.Uncancelable` and `IO.OnCancel` branches (`IO.scala:2390-2397`) are taken.

`IdPoll`. The `Uncancelable` branch calls the body with `new Poll[IO] { def apply(ioc) = ioc }`
(`IO.scala:2391-2393`). User code is first-order (`Fn`), so it gets a `Val`: `idPollVal`.
A real `poll` of `IOFiber` is `Val.poll id self` with `id ≥ 1` (the mask models give ids from 1;
`CatsEffectInLean/Model/Fiber.lean`). So user code can tell `idPollVal` (mask id 0) apart, and
`poll(fa)` with it means `fa`.

Throws. `interpret` has no `try`. A body that throws in the `Uncancelable` branch throws out
of `interpret`: out of `IO#syncStep` itself (when `interpret` runs at once), or out of a
`SyncIO` closure (when a `flatMap`/`handleErrorWith` closure runs it); there `SyncIO` catches a
non-fatal throw (`SyncIO.scala:369-372`).

The stepped program. `steppedRest` runs `fa.syncStep(limit).unsafeRunSync()` on the caller
thread, then picks the `IO` that the law runs next: `Left(io) => io`, `Right(a) => IO.pure(a)`
(`laws/shared/src/main/scala/cats/effect/laws/AsyncLaws.scala:84-88`). A throw gives
`IO.raiseError(e)`. This is the use pattern of the Cats Effect test
`tests/shared/src/test/scala/cats/effect/IOSuite.scala:2685`
(`syncStep(Int.MaxValue).unsafeRunSync() match { ... }`).
-/

namespace CatsEffectInLean.Model

/-- `Sync[SyncIO].rootCancelScope` (`MonadCancel.scala:599`, `SyncIO.scala:590-593`). -/
def syncIORootCancelScope : Kernel.CancelScope := .uncancelable

/-- `SyncStep.MaxSteps = 512` (`IO.scala:2341`). -/
def SyncStep.maxSteps : Int := 512

/-- The `IdPoll` of the `Uncancelable` branch (`IO.scala:2391-2393`) as a value. Mask id 0 is
never the id of a real `poll`. -/
def idPollVal : Val := .poll 0 0

/-- The result of `interpret`: a `SyncIO`, a throw, out of fuel, or an abort. -/
inductive IRes (M : Type) where
  | ok (s : SyncIO) (x : Exec M)
  | thrown (e : Err) (x : Exec M)
  | outOfFuel
  | abort (a : Abort)

namespace SyncStep
variable {M : Type} (mm : MaskModel M) (env : UserEnv)

/-- `IRes` after `.map`/`.flatMap`/`.handleErrorWith` on the `SyncIO` result. -/
@[inline] def IRes.wrap (k : SyncIO → SyncIO) : IRes M → IRes M
  | .ok s x => .ok (k s) x
  | .thrown e x => .thrown e x
  | .outOfFuel => .outOfFuel
  | .abort a => .abort a

/-- `SyncStep.interpret(io, limit, stepsUntilDefer)` with `G = SyncIO` (`IO.scala:2348-2402`).
Structural on `fuel` (one unit per call); the `Uncancelable` branch recurses on a program
that user code returns, so the recursion is not structural on `io`. -/
def interpret : (fuel : Nat) → IO → (limit : Int) → (steps : Int) → Exec M → IRes M
  | 0, _, _, _, _ => .outOfFuel
  | fuel + 1, io, limit, steps, x =>
    -- IO.scala:2350-2351
    if limit ≤ 0 then .ok (.pure (.left (.io io))) x
    -- IO.scala:2352-2353: `G.defer(interpret(io, limit, MaxSteps))`
    else if steps ≤ 0 then .ok (.flatMap (.suspend .delay (.deferInterpret io limit)) .flattenId) x
    else
      match io with
      -- IO.scala:2356 `G.pure(Right((a, limit)))`
      | .pure a => .ok (.pure (.right (.pair (.val a) (.int limit)))) x
      -- IO.scala:2357 `G.raiseError(t)`
      | .error t => .ok (.error t) x
      -- IO.scala:2358 `G.delay(thunk()).map(a => Right((a, limit)))`
      | .delay thunk =>
        .ok (.flatMap (.suspend .delay (.ioThunk thunk)) (.pureMap (.rightLimit limit))) x
      -- IO.scala:2359 `G.realTime.map(a => Right((a, limit)))`
      | .realTime => .ok (.flatMap .realTime (.pureMap (.rightLimit limit))) x
      -- IO.scala:2360 `G.monotonic.map(a => Right((a, limit)))`
      | .monotonic => .ok (.flatMap .monotonic (.pureMap (.rightLimit limit))) x
      -- IO.scala:2362-2366
      | .map ioe f =>
        IRes.wrap (fun s => .flatMap s (.pureMap (.mapSel f)))
          (interpret fuel ioe (limit - 1) (steps - 1) x)
      -- IO.scala:2368-2372
      | .flatMap ioe f =>
        IRes.wrap (fun s => .flatMap s (.flatMapSel f steps))
          (interpret fuel ioe (limit - 1) (steps - 1) x)
      -- IO.scala:2374-2380
      | .attempt ioe =>
        IRes.wrap (fun s => .handleErrorWith (.flatMap s (.pureMap .attemptSel)) (.attemptHandler limit))
          (interpret fuel ioe (limit - 1) (steps - 1) x)
      -- IO.scala:2382-2388
      | .handleErrorWith ioe f =>
        IRes.wrap
          (fun s => .handleErrorWith (.flatMap s (.pureMap (.hewSel f))) (.hewHandler f limit steps))
          (interpret fuel ioe (limit - 1) (steps - 1) x)
      -- IO.scala:2390-2394: `case IO.Uncancelable(body, _) if G.rootCancelScope == Uncancelable`
      | .uncancelable body =>
        if syncIORootCancelScope == .uncancelable then
          -- `val ioa = body(IdPoll)`: no `try`; a throw leaves `interpret`
          match callUser mm env body idPollVal x with
          | .error a => .abort a
          | .ok (.prog ioa, x) => interpret fuel ioa limit steps x
          | .ok (.throw e, x) => .thrown e x
          | .ok (.ret _, _) => .abort .illTyped
        else .ok (.pure (.left (.io io))) x
      -- IO.scala:2396-2397: `case IO.OnCancel(ioa, _) if G.rootCancelScope == Uncancelable`;
      -- the finalizer is dropped
      | .onCancel ioa _ =>
        if syncIORootCancelScope == .uncancelable then interpret fuel ioa limit steps x
        else .ok (.pure (.left (.io io))) x
      -- IO.scala:2399 `case _ => G.pure(Left(io))`
      | _ => .ok (.pure (.left (.io io))) x

/-- The result of a pure function `g` of `SFn.pureMap`. -/
inductive MRes (M : Type) where
  | ok (v : SVal) (x : Exec M)
  | thrown (e : Err) (x : Exec M)
  | abort (a : Abort)

/-- Apply `g` (`SMap`). A Scala `MatchError` (a value of the wrong shape) cannot happen in
well-typed code; the model aborts with `illTyped`. -/
def applyMap (g : SMap) (arg : SVal) (x : Exec M) : MRes M :=
  match g with
  -- IO.scala:2358-2360 `a => Right((a, limit))`
  | .rightLimit limit => .ok (.right (.pair arg (.int limit))) x
  -- IO.scala:2363-2366
  | .mapSel f =>
    match arg with
    | .left (.io io) => .ok (.left (.io (.map io f))) x -- `io.map(f)` = `IO.Map` (IO.scala:579)
    | .right (.pair (.val a) (.int limit)) =>
      -- `f(a)`: user code; a throw goes to the `try` of `flatMapK` (SyncIO.scala:369-372)
      match callUser mm env f a x with
      | .error ab => .abort ab
      | .ok (.ret b, x) => .ok (.right (.pair (.val b) (.int limit))) x
      | .ok (.throw e, x) => .thrown e x
      | .ok (.prog _, _) => .abort .illTyped
    | _ => .abort .illTyped
  -- IO.scala:2376-2379
  | .attemptSel =>
    match arg with
    | .left (.io io) => .ok (.left (.io (.attempt io))) x -- `io.attempt` = `IO.Attempt` (IO.scala:200-201)
    | .right (.pair (.val a) (.int limit)) => .ok (.right (.pair (.val (.right a)) (.int limit))) x
    | _ => .abort .illTyped
  -- IO.scala:2384-2387
  | .hewSel f =>
    match arg with
    -- `io.handleErrorWith(f)` = `IO.HandleErrorWith` (IO.scala:549-550)
    | .left (.io io) => .ok (.left (.io (.handleErrorWith io f))) x
    | .right r => .ok (.right r) x
    | _ => .abort .illTyped
  -- IO.scala:2177 `_.map(_._1)`
  | .dropLimit =>
    match arg with
    | .left l => .ok (.left l) x
    | .right (.pair a _) => .ok (.right a) x
    | _ => .abort .illTyped

/-- `IRes` as the result of a `SyncIO` closure that returns a `SyncIO`. -/
@[inline] def IRes.toCall : IRes M → SCall M
  | .ok s x => .ok (.prog s) x
  | .thrown e x => .thrown e x
  | .outOfFuel => .outOfFuel
  | .abort a => .abort a

/-- The meaning of the closures (`SFn`) that `interpret` puts into `SyncIO` nodes. -/
def callS (fuel : Nat) (f : SFn) (arg : SVal) (x : Exec M) : SCall M :=
  match f with
  -- IO.scala:2358 the thunk of `G.delay(thunk())`
  | .ioThunk thunk =>
    match callUser mm env thunk .unit x with
    | .error a => .abort a
    | .ok (.ret v, x) => .ok (.ret (.val v)) x
    | .ok (.throw e, x) => .thrown e x
    | .ok (.prog _, _) => .abort .illTyped
  -- IO.scala:2353 the thunk of `G.defer(interpret(io, limit, MaxSteps))`
  | .deferInterpret io limit =>
    match interpret mm env fuel io limit maxSteps x with
    | .ok s x => .ok (.ret (.sio s)) x
    | .thrown e x => .thrown e x
    | .outOfFuel => .outOfFuel
    | .abort a => .abort a
  -- Sync.scala:62 `x => x`
  | .flattenId =>
    match arg with
    | .sio s => .ok (.prog s) x
    | _ => .abort .illTyped
  -- cats/Monad.scala:35 `a => pure(f(a))`
  | .pureMap g =>
    match applyMap mm env g arg x with
    | .ok v x => .ok (.prog (.pure v)) x
    | .thrown e x => .thrown e x
    | .abort a => .abort a
  -- IO.scala:2369-2372
  | .flatMapSel f steps =>
    match arg with
    -- `case Left(io) => G.pure(Left(io.flatMap(f)))`; `io.flatMap(f)` = `IO.FlatMap` (IO.scala:469-470)
    | .left (.io io) => .ok (.prog (.pure (.left (.io (.flatMap io f))))) x
    -- `case Right((a, limit)) => interpret(f(a), limit - 1, stepsUntilDefer - 1)`
    | .right (.pair (.val a) (.int limit)) =>
      match callUser mm env f a x with
      | .error ab => .abort ab
      | .ok (.prog p, x) => IRes.toCall (interpret mm env fuel p (limit - 1) (steps - 1) x)
      | .ok (.throw e, x) => .thrown e x
      | .ok (.ret _, _) => .abort .illTyped
    | _ => .abort .illTyped
  -- IO.scala:2380 `t => (t.asLeft, limit - 1).asRight`, then `pure` (ApplicativeError.scala:105)
  | .attemptHandler limit =>
    match arg with
    | .err t => .ok (.prog (.pure (.right (.pair (.val (.left (.err t))) (.int (limit - 1)))))) x
    | _ => .abort .illTyped
  -- IO.scala:2388 `t => interpret(f(t), limit - 1, stepsUntilDefer - 1)`
  | .hewHandler f limit steps =>
    match arg with
    | .err t =>
      match callUser mm env f (.err t) x with
      | .error ab => .abort ab
      | .ok (.prog p, x) => IRes.toCall (interpret mm env fuel p (limit - 1) (steps - 1) x)
      | .ok (.throw e, x) => .thrown e x
      | .ok (.ret _, _) => .abort .illTyped
    | _ => .abort .illTyped

/-- The closure meaning as a `SyncIOEnv`. -/
def senv : SyncIOEnv M where
  call := callS mm env

/-- `fa.syncStep(limit)`: `G.map(interpret(fa, limit, MaxSteps))(_.map(_._1))`
(`IO.scala:1161-1162`, `IO.scala:2173-2178`). `interpret` runs now, on the caller thread. -/
def syncStep (fuel : Nat) (fa : IO) (limit : Int) (x : Exec M) : IRes M :=
  IRes.wrap (fun s => .flatMap s (.pureMap .dropLimit)) (interpret mm env fuel fa limit maxSteps x)

/-- The world of the caller thread before any fiber exists: the heap with `Ref` cells `refs`
and no fibers. `fib` is a placeholder (fiber id 0, never started); only rare runtime
closures (`Fn.rt`) read it. -/
def prefixExec (refs : List Val) : Exec M :=
  { fib := Fiber.new mm 0 .unit 0 .endFiber none, heap := { refs := refs }, fibers := [] }

/-- The law's selector (`AsyncLaws.scala:85-87`): `Left(fa) => fa`, `Right(a) => F.pure(a)`. -/
def select : SVal → Option IO
  | .left (.io p) => some p
  | .right (.val a) => some (.pure a)
  | _ => none

/-- `fa.syncStep(limit).unsafeRunSync()` (`SyncIO.scala:226`), then the law's selector. The
result is the `IO` to run next and the heap, or (`.error`) a model stop as a `Summary`
(`outOfFuel` or `aborted`). A throw gives `IO.raiseError(e)` (`Error`, `IO.scala:2210-2212`). -/
def steppedRest (fuel : Nat) (fa : IO) (limit : Int) (refs : List Val) :
    Except Summary (IO × Heap) :=
  match syncStep mm env fuel fa limit (prefixExec mm refs) with
  | .outOfFuel => .error .outOfFuel
  | .abort a => .error (.aborted a)
  | .thrown e x => .ok (.error e, x.heap)
  | .ok s x =>
    match SyncIO.unsafeRunSync (senv mm env) fuel s x with
    | .value v x =>
      match select v with
      | some p => .ok (p, x.heap)
      | none => .error (.aborted .illTyped)
    | .thrown e x => .ok (.error e, x.heap)
    | .outOfFuel => .error .outOfFuel
    | .abort a => .error (.aborted a)

end SyncStep

/-! ## Observations of a run

A run of the single-fiber driver (`CatsEffectInLean/Model/Run.lean`) under a schedule
`cs : List SoloChoice`. The schedule decides the `observe` flag of each step and when
another fiber cancels the root fiber (external cancel is a schedule choice). The names are in namespace `SyncStepObs`. -/

namespace SyncStepObs

/-- What a run shows: the summary (outcome or model stop), the `Ref` cells, and the values
that user code emitted. -/
abbrev Obs := Summary × List Val × List Val

/-- Does a summary make a claim about Cats Effect? `outOfFuel` and `aborted` do not
(`AGENTS.md`: out of fuel is never a Cats Effect outcome; an abort is a model limit). -/
def isClaim : Summary → Bool
  | .outOfFuel | .aborted _ | .taskLimit => false
  | _ => true

/-- The observation of a single-fiber state. -/
def ofSolo {M : Type} (s : Solo M) : Obs := (s.summary, s.heap.refs, s.heap.out)

/-- The root fiber of `io` on heap `h` (fiber id 0, `ExecutionContext` 0, the `root`
callback), not yet started. Same as `Solo.init` but with a full heap. -/
def rootOn {M : Type} (mm : MaskModel M) (io : IO) (h : Heap) : Solo M :=
  let root := Fiber.new mm 0 .unit 0 io (some .root)
  .parked { fib := root, heap := h, fibers := [root] }

section
variable (env : UserEnv)

/-- The direct run: `fa` as the root fiber with `Ref` cells `refs`, under schedule `cs`. The
`IOFiber` mirror: `counterMaskModel`, default `Config` (`TestControl` uses the default). -/
def directObs (fa : IO) (refs : List Val) (cs : List SoloChoice) : Obs :=
  ofSolo (Solo.exec {} counterMaskModel env cs (Solo.init counterMaskModel fa refs))

/-- The stepped run: `fa.syncStep(limit).unsafeRunSync()` with fuel `fuel`, then the selected
`IO` as the root fiber on the heap that the `SyncIO` part left, under schedule `cs`. -/
def steppedObs (fa : IO) (limit : Int) (refs : List Val) (fuel : Nat) (cs : List SoloChoice) :
    Obs :=
  match SyncStep.steppedRest counterMaskModel env fuel fa limit refs with
  | .error s => (s, refs, [])
  | .ok (p, h) => ofSolo (Solo.exec {} counterMaskModel env cs (rootOn counterMaskModel p h))

end

end SyncStepObs

end CatsEffectInLean.Model

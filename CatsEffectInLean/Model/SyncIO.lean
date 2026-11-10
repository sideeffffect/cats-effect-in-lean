import CatsEffectInLean.Model.Step

/-!
# `SyncIO` syntax and its run loop

Phase 5 (CE-0001). A mirror of `SyncIO` at `v3.7.1`
(`core/shared/src/main/scala/cats/effect/SyncIO.scala`, cited as `SIO`):

* `SyncIO`: one constructor per Scala case class, in tag order (`SIO:637-681`).
* `SyncIO.runLoop`: the run loop of `unsafeRunSync` (`SIO:226-385`), with `succeeded`,
  `failed`, `mapK`, `flatMapK` and `handleErrorWithK`, branch by branch.

Values. A `SyncIO` value can be an `IO` (the `Left(io)` of `syncStep`) or a `SyncIO` (the
thunk result of `Sync.defer`). `Val` cannot hold these, so `SVal` wraps `Val` and adds them.

Functions. The `SyncIO` nodes that `SyncStep.interpret` builds hold closures. Each closure is
one `SFn` constructor (first-order, as `RtFn` in `CatsEffectInLean/Model/Syntax.lean`).
The run loop does not give them a meaning: it takes a `SyncIOEnv` parameter that applies a
closure. `CatsEffectInLean/Model/SyncStep.lean` gives the meaning.

Fuel. The run loop is structural on a `Nat` fuel. Each `runLoop` iteration uses one unit.
"Out of fuel" is a separate result. It is never a `SyncIO` result.

Not modelled: the `ByteStack`/`ArrayStack` growth (lists here), and the `@tailrec` /
JVM stack. `null` values do not exist in Lean.
-/

namespace CatsEffectInLean.Model

/-- A pure function `g` inside `SFn.pureMap`. -/
inductive SMap where
  /-- `a => Right((a, limit))` (`IO.scala:2358-2360`). -/
  | rightLimit (limit : Int)
  /-- `{ case Left(io) => Left(io.map(f)); case Right((a, limit)) => Right((f(a), limit)) }`
  (`IO.scala:2363-2366`). `f` is user code. -/
  | mapSel (f : Fn)
  /-- `{ case Left(io) => Left(io.attempt); case Right((a, limit)) =>
  Right((a.asRight[Throwable], limit)) }` (`IO.scala:2376-2379`). -/
  | attemptSel
  /-- `{ case Left(io) => Left(io.handleErrorWith(f)); case r @ Right(_) => r }`
  (`IO.scala:2384-2387`). -/
  | hewSel (f : Fn)
  /-- `_.map(_._1)` of `asyncForIO.syncStep` (`IO.scala:2177`). -/
  | dropLimit
  deriving DecidableEq, Repr

/-- A closure inside a `SyncIO` node. Each case is one Scala lambda. The meaning is
`SyncStep.callS` (`CatsEffectInLean/Model/SyncStep.lean`). `IO.scala` is
`core/shared/src/main/scala/cats/effect/IO.scala`. -/
inductive SFn where
  /-- The `Suspend` thunk of `G.delay(thunk())` (`IO.scala:2358`): calls the `IO.Delay` thunk. -/
  | ioThunk (thunk : Fn)
  /-- The `Suspend` thunk of `G.defer(interpret(io, limit, MaxSteps))` (`IO.scala:2353`).
  It returns a `SyncIO`. -/
  | deferInterpret (io : IO) (limit : Int)
  /-- `x => x`, the `flatMap` function of `Sync.defer` (`Sync.scala:62`). -/
  | flattenId
  /-- `a => pure(g(a))`: `G.map(fa)(g)` is `Monad.map` = `flatMap(fa)(a => pure(f(a)))`
  (cats-core 2.13.0 `cats/Monad.scala:34-35`; `SyncIOSync` does not override `map`,
  `SIO:590-631`). -/
  | pureMap (g : SMap)
  /-- The `flatMap` function of the `IO.FlatMap` branch (`IO.scala:2369-2372`). `steps` is
  the `stepsUntilDefer` of that `interpret` call. -/
  | flatMapSel (f : Fn) (steps : Int)
  /-- `t => pure((t.asLeft, limit - 1).asRight)`: the `handleError` of the `IO.Attempt`
  branch (`IO.scala:2380`); `handleError(fa)(f) = handleErrorWith(fa)(f.andThen(pure))`
  (cats-core 2.13.0 `cats/ApplicativeError.scala:105`). -/
  | attemptHandler (limit : Int)
  /-- `t => interpret(f(t), limit - 1, stepsUntilDefer - 1)`: the `handleErrorWith` of the
  `IO.HandleErrorWith` branch (`IO.scala:2388`). -/
  | hewHandler (f : Fn) (limit : Int) (steps : Int)
  deriving DecidableEq, Repr

mutual

/-- A value inside the `SyncIO` run loop. -/
inductive SVal where
  /-- An ordinary value of the `IO` world. -/
  | val (v : Val)
  /-- A value of type `IO[A]` (the `Left(io)` of `SyncStep.interpret`, `IO.scala:2351`). -/
  | io (p : IO)
  /-- A value of type `SyncIO[A]` (the thunk result of `Sync.defer`,
  `kernel/shared/src/main/scala/cats/effect/kernel/Sync.scala:61-62`). -/
  | sio (s : SyncIO)
  /-- `Left(a)`. -/
  | left (a : SVal)
  /-- `Right(a)`. -/
  | right (a : SVal)
  /-- A pair `(a, b)`. -/
  | pair (a b : SVal)
  /-- An `Int` (the `limit` in `Right((a, limit))`, `IO.scala:2356`). -/
  | int (i : Int)
  /-- A `Throwable` as a value (the `Left(error)` of `AttemptK`, `SIO:343`). -/
  | err (e : Err)

/-- The `SyncIO` ADT. One constructor per Scala case class, in tag order. -/
inductive SyncIO where
  /-- Tag 0. `Pure(value)` (`SIO:637-640`). -/
  | pure (value : SVal)
  /-- Tag 1. `Suspend(hint, thunk)` (`SIO:642-644`). -/
  | suspend (hint : SyncType) (thunk : SFn)
  /-- Tag 2. `Error(t)` (`SIO:646-648`). -/
  | error (t : Err)
  /-- Tag 3. `Map(ioe, f)` (`SIO:650-652`). -/
  | map (ioe : SyncIO) (f : SFn)
  /-- Tag 4. `FlatMap(ioe, f)` (`SIO:654-656`). -/
  | flatMap (ioe : SyncIO) (f : SFn)
  /-- Tag 5. `HandleErrorWith(ioa, f)` (`SIO:658-661`). -/
  | handleErrorWith (ioa : SyncIO) (f : SFn)
  /-- Tag 6. `Success(value)` (`SIO:663-665`). Internal: only `succeeded` makes it. -/
  | success (value : SVal)
  /-- Tag 7. `Failure(t)` (`SIO:667-669`). Internal: only `failed` makes it. -/
  | failure (t : Err)
  /-- Tag 8. `Attempt(ioa)` (`SIO:671-673`). -/
  | attempt (ioa : SyncIO)
  /-- Tag 9. `RealTime` (`SIO:675-677`). -/
  | realTime
  /-- Tag 10. `Monotonic` (`SIO:679-681`). -/
  | monotonic

end

deriving instance DecidableEq for SVal, SyncIO
deriving instance Repr for SVal, SyncIO

/-- The Scala tag of each constructor (`def tag`, `SIO:637-681`). -/
def SyncIO.tag : SyncIO → Nat
  | .pure _ => 0
  | .suspend _ _ => 1
  | .error _ => 2
  | .map _ _ => 3
  | .flatMap _ _ => 4
  | .handleErrorWith _ _ => 5
  | .success _ => 6
  | .failure _ => 7
  | .attempt _ => 8
  | .realTime => 9
  | .monotonic => 10

/-- The continuation bytes of `unsafeRunSync`
(`core/jvm/src/main/java/cats/effect/SyncIOConstants.java:21-28`). -/
inductive SContK where
  /-- `MapK = 0`. -/
  | mapK
  /-- `FlatMapK = 1`. -/
  | flatMapK
  /-- `HandleErrorWithK = 2`. -/
  | handleErrorWithK
  /-- `RunTerminusK = 3`. -/
  | runTerminusK
  /-- `AttemptK = 4`. -/
  | attemptK
  deriving DecidableEq, Repr

/-- `MaxStackDepth = 512` (`SyncIOConstants.java:23`). -/
def SyncIO.maxStackDepth : Nat := 512

/-- What a closure gives. -/
inductive SOut where
  /-- A value (a `Suspend` thunk, a `Map` function). -/
  | ret (v : SVal)
  /-- A `SyncIO` (a `FlatMap` or `HandleErrorWith` function). -/
  | prog (s : SyncIO)
  deriving DecidableEq, Repr

/-- The result of one closure call. `M` is the mask model of the `Exec` (only the heap is
used; see `SyncStep.prefixExec`). -/
inductive SCall (M : Type) where
  /-- The closure returned. -/
  | ok (out : SOut) (x : Exec M)
  /-- The closure threw `e` (fatal or not). -/
  | thrown (e : Err) (x : Exec M)
  /-- The model ran out of fuel inside the closure. -/
  | outOfFuel
  /-- The model stops (`Abort`). -/
  | abort (a : Abort)

/-- How the run loop applies a closure: `call fuel f arg x`. `fuel` is the fuel that is left. -/
structure SyncIOEnv (M : Type) where
  /-- Apply closure `f` to `arg` with the world `x`. -/
  call : Nat → SFn → SVal → Exec M → SCall M
  /-- Not Cats Effect v3.7.1: the switch of the CE-0004 fixed twin (decision 39). If `true`,
  the `Error` branch throws a fatal error out of `unsafeRunSync`, as `IOFiber` does
  (`IOFiber.scala:265-269`). Cats Effect v3.7.1 is `false`. -/
  fixFatalRaise : Bool := false

/-- The state of one `unsafeRunSync` call (`SIO:229-232`). -/
structure SRun (M : Type) where
  /-- `conts: ByteStack`; head = top. -/
  conts : List SContK
  /-- `objectState: ArrayStack[AnyRef]`; head = top. It holds only functions. -/
  objs : List SFn
  /-- The heap (refs, clock, output) and the user view. -/
  x : Exec M

/-- The result of `unsafeRunSync` (`SIO:226`). -/
inductive SRes (M : Type) where
  /-- It returned `v` (`case 6`, `SIO:285-287`). -/
  | value (v : SVal) (x : Exec M)
  /-- It threw `e`: `throw cur.t` (`case 7`, `SIO:289-291`), or a fatal error that no
  `catch { case t if UnsafeNonFatal(t) => ... }` caught. -/
  | thrown (e : Err) (x : Exec M)
  /-- Out of fuel. Never a `SyncIO` result. -/
  | outOfFuel
  /-- The model stops (`Abort`). Never a `SyncIO` result. -/
  | abort (a : Abort)

/-- What `succeeded`/`failed` give back to `runLoop`: the next `SyncIO`, or a stop. -/
inductive SNext (M : Type) where
  /-- `runLoop(next)`. -/
  | next (cur : SyncIO) (r : SRun M)
  /-- A stop (a fatal throw, out of fuel, or an abort). -/
  | stop (res : SRes M)

namespace SyncIO
variable {M : Type} (senv : SyncIOEnv M)

/-- Pop one function from `objectState`. -/
def popObj (r : SRun M) : Option (SFn × SRun M) :=
  match r.objs with
  | f :: os => some (f, { r with objs := os })
  | [] => none

mutual

/-- `succeeded(result, depth)` (`SIO:305-318`), with `mapK` (`SIO:347-364`) and `flatMapK`
(`SIO:366-373`) inlined. Structural on `conts`: each branch pops one byte first, as
`ByteStack.pop(conts)`; the list argument is the stack without that byte. -/
def succeeded (fuel : Nat) (r : SRun M) (result : SVal) (depth : Nat) :
    List SContK → SNext M
  -- an empty `ByteStack` cannot happen: `RunTerminusK` is at the bottom (`SIO:232`)
  | [] => .stop (.abort .emptyConts)
  | k :: rest =>
    let r := { r with conts := rest }
    match k with
    -- SIO:309 `mapK(result, depth)`
    | .mapK =>
      match popObj r with
      | none => .stop (.abort .badObjectState)
      | some (f, r) =>
        -- SIO:350-355: `try f(result) catch { case t if UnsafeNonFatal(t) => error = t }`
        match senv.call fuel f result r.x with
        | .ok (.ret transformed) x =>
          let r := { r with x := x }
          -- SIO:357-363: hand back to `runLoop` at depth > MaxStackDepth
          if depth > maxStackDepth then .next (.pure transformed) r
          else succeeded fuel r transformed (depth + 1) rest
        | .ok (.prog _) _ => .stop (.abort .illTyped)
        | .thrown e x =>
          let r := { r with x := x }
          if e.isNonFatal then
            if depth > maxStackDepth then .next (.error e) r
            else failed fuel r e (depth + 1) rest
          -- a fatal error is not caught: it leaves `unsafeRunSync`
          else .stop (.thrown e x)
        | .outOfFuel => .stop .outOfFuel
        | .abort a => .stop (.abort a)
    -- SIO:310 `flatMapK(result, depth)`
    | .flatMapK =>
      match popObj r with
      | none => .stop (.abort .badObjectState)
      | some (f, r) =>
        -- SIO:369-372: `try f(result) catch { case t if UnsafeNonFatal(t) => failed(t, depth + 1) }`
        match senv.call fuel f result r.x with
        | .ok (.prog next) x => .next next { r with x := x }
        | .ok (.ret _) _ => .stop (.abort .illTyped)
        | .thrown e x =>
          if e.isNonFatal then failed fuel { r with x := x } e (depth + 1) rest
          else .stop (.thrown e x)
        | .outOfFuel => .stop .outOfFuel
        | .abort a => .stop (.abort a)
    -- SIO:311-315 `handleErrorWithK`: `objectState.pop()`; `succeeded(result, depth)`
    | .handleErrorWithK =>
      match popObj r with
      | some (_, r) => succeeded fuel r result depth rest
      | none => .stop (.abort .badObjectState)
    -- SIO:316 `SyncIO.Success(result)`
    | .runTerminusK => .next (.success result) r
    -- SIO:317 `succeeded(Right(result), depth + 1)`
    | .attemptK => succeeded fuel r (.right result) (depth + 1) rest
  termination_by structural cs => cs

/-- `failed(error, depth)` (`SIO:320-345`), with `handleErrorWithK` (`SIO:375-382`)
inlined. The pre-scan in the comment (`SIO:321-336`) is dead code. -/
def failed (fuel : Nat) (r : SRun M) (error : Err) (depth : Nat) : List SContK → SNext M
  | [] => .stop (.abort .emptyConts)
  | k :: rest =>
    let r := { r with conts := rest }
    match k with
    -- SIO:338-340: `case 0 | 1 => objectState.pop(); failed(error, depth)`
    | .mapK | .flatMapK =>
      match popObj r with
      | some (_, r) => failed fuel r error depth rest
      | none => .stop (.abort .badObjectState)
    -- SIO:341 `handleErrorWithK(error, depth)`
    | .handleErrorWithK =>
      match popObj r with
      | none => .stop (.abort .badObjectState)
      | some (f, r) =>
        -- SIO:378-381: `try f(t) catch { case t if UnsafeNonFatal(t) => failed(t, depth + 1) }`
        match senv.call fuel f (.err error) r.x with
        | .ok (.prog next) x => .next next { r with x := x }
        | .ok (.ret _) _ => .stop (.abort .illTyped)
        | .thrown e x =>
          if e.isNonFatal then failed fuel { r with x := x } e (depth + 1) rest
          else .stop (.thrown e x)
        | .outOfFuel => .stop .outOfFuel
        | .abort a => .stop (.abort a)
    -- SIO:342 `SyncIO.Failure(error)`
    | .runTerminusK => .next (.failure error) r
    -- SIO:343 `succeeded(Left(error), depth + 1)`
    | .attemptK => succeeded fuel r (.left (.err error)) (depth + 1) rest
  termination_by structural cs => cs

end

/-- `runLoop(cur0)` (`SIO:234-303`). Structural on `fuel`: each iteration uses one unit.
`succeeded`/`failed` give the next `SyncIO` (`runLoop(next)`) or a stop. -/
def runLoop : (fuel : Nat) → SyncIO → SRun M → SRes M
  | 0, _, _ => .outOfFuel
  | fuel + 1, cur, r =>
    let go : SNext M → SRes M := fun
      | .next c r => runLoop fuel c r
      | .stop res => res
    match cur with
    -- SIO:237-239 `case 0`: `runLoop(succeeded(cur.value, 0))`
    | .pure v => go (succeeded senv fuel r v 0 r.conts)
    -- SIO:241-255 `case 1`: `try cur.thunk() catch { case t if UnsafeNonFatal(t) => ... }`
    | .suspend _ thunk =>
      match senv.call fuel thunk (.val .unit) r.x with
      | .ok (.ret v) x =>
        let r := { r with x := x }
        go (succeeded senv fuel r v 0 r.conts)
      | .ok (.prog _) _ => .abort .illTyped
      | .thrown e x =>
        let r := { r with x := x }
        if e.isNonFatal then go (failed senv fuel r e 0 r.conts)
        -- a fatal error is not caught: it leaves `unsafeRunSync`
        else .thrown e x
      | .outOfFuel => .outOfFuel
      | .abort a => .abort a
    -- SIO:257-259 `case 2`: `runLoop(failed(cur.t, 0))`; no fatal check (CE-0004). The
    -- `fixFatalRaise` twin throws a fatal `t` out of `unsafeRunSync`.
    | .error t =>
      if senv.fixFatalRaise && !t.isNonFatal then .thrown t r.x
      else go (failed senv fuel r t 0 r.conts)
    -- SIO:261-267 `case 3`: push `f`, push `MapK`, `runLoop(cur.ioe)`
    | .map ioe f => runLoop fuel ioe { r with objs := f :: r.objs, conts := .mapK :: r.conts }
    -- SIO:269-275 `case 4`: push `f`, push `FlatMapK`, `runLoop(cur.ioe)`
    | .flatMap ioe f =>
      runLoop fuel ioe { r with objs := f :: r.objs, conts := .flatMapK :: r.conts }
    -- SIO:277-283 `case 5`: push `f`, push `HandleErrorWithK`, `runLoop(cur.ioa)`
    | .handleErrorWith ioa f =>
      runLoop fuel ioa { r with objs := f :: r.objs, conts := .handleErrorWithK :: r.conts }
    -- SIO:285-287 `case 6`: return the value
    | .success v => .value v r.x
    -- SIO:289-291 `case 7`: `throw cur.t`
    | .failure t => .thrown t r.x
    -- SIO:293-297 `case 8`: push `AttemptK`, `runLoop(cur.ioa)`
    | .attempt ioa => runLoop fuel ioa { r with conts := .attemptK :: r.conts }
    -- SIO:299-300 `case 9`: `System.currentTimeMillis()`; the model clock, as `IO.RealTime`
    | .realTime => go (succeeded senv fuel r (.val (.nat r.x.heap.clock)) 0 r.conts)
    -- SIO:302-303 `case 10`: `System.nanoTime()`; the model clock, as `IO.Monotonic`
    | .monotonic => go (succeeded senv fuel r (.val (.nat r.x.heap.clock)) 0 r.conts)

/-- `sio.unsafeRunSync()` (`SIO:226-385`): `conts` starts with `RunTerminusK` (`SIO:232`). -/
def unsafeRunSync (fuel : Nat) (sio : SyncIO) (x : Exec M) : SRes M :=
  runLoop senv fuel sio { conts := [.runTerminusK], objs := [], x := x }

end SyncIO

end CatsEffectInLean.Model

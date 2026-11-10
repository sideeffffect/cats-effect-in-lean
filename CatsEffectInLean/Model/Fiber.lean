import CatsEffectInLean.Model.Syntax

/-!
# Fiber state

Phase 2 step 3. The fields of `IOFiber`
(`core/shared/src/main/scala/cats/effect/IOFiber.scala:68-107` at `v3.7.1`), the
continuation and resume tags (`core/jvm/src/main/java/cats/effect/IOFiberConstants.java:28-49`),
the `ContState` cell (`core/shared/src/main/scala/cats/effect/ContState.scala:25-56`), and two
mask models side by side (user decision 3, `wiki/methodology/project-plan.md`).

Short names in citations: `FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala`,
`CONST` = `core/jvm/src/main/java/cats/effect/IOFiberConstants.java`.
-/

namespace CatsEffectInLean.Model

/-- Continuation tags, the bytes on the `conts` stack (`CONST:28-38`). The order of the
constructors is the byte value (`ContK.toNat`). `failed` drops `MapK` and `FlatMapK`
(`FIB:1298-1300`). -/
inductive ContK where
  /-- `MapK = 0` (`CONST:29`). An `f` is on `objectState`. -/
  | mapK
  /-- `FlatMapK = 1` (`CONST:30`). An `f` is on `objectState`. -/
  | flatMapK
  /-- `CancelationLoopK = 2` (`CONST:31`). Runs the next finalizer (`FIB:1465-1490`). -/
  | cancelationLoopK
  /-- `RunTerminusK = 3` (`CONST:32`). Bottom of the stack; calls `done` (`FIB:1492-1500`). -/
  | runTerminusK
  /-- `EvalOnK = 4` (`CONST:33`). The old `ExecutionContext` is on `objectState`
  (`FIB:991-993`, `FIB:1502-1536`). -/
  | evalOnK
  /-- `HandleErrorWithK = 5` (`CONST:34`). An `f` is on `objectState` (`FIB:526-527`). -/
  | handleErrorWithK
  /-- `OnCancelK = 6` (`CONST:35`). Pops one finalizer on normal exit (`FIB:1254-1256`). -/
  | onCancelK
  /-- `UncancelableK = 7` (`CONST:36`). Unmasks on exit (`FIB:1258-1260`). -/
  | uncancelableK
  /-- `UnmaskK = 8` (`CONST:37`). Masks again on exit (`FIB:1262-1264`). -/
  | unmaskK
  /-- `AttemptK = 9` (`CONST:38`). Wraps the result in `Right`/`Left` (`FIB:1266-1267`,
  `FIB:1329`). -/
  | attemptK
  deriving DecidableEq, Repr

/-- The byte value of a continuation tag (`CONST:29-38`). -/
def ContK.toNat : ContK → Nat
  | .mapK => 0
  | .flatMapK => 1
  | .cancelationLoopK => 2
  | .runTerminusK => 3
  | .evalOnK => 4
  | .handleErrorWithK => 5
  | .onCancelK => 6
  | .uncancelableK => 7
  | .unmaskK => 8
  | .attemptK => 9

/-- Resume tags: what `run()` does when the fiber is next scheduled (`CONST:40-49`,
dispatch at `FIB:121-131`). -/
inductive ResumeTag where
  /-- `ExecR = 0`: first run; `execR` (`FIB:1386-1401`). -/
  | execR
  /-- `AsyncContinueSuccessfulR = 1` (`FIB:1403-1406`). -/
  | asyncContinueSuccessfulR
  /-- `AsyncContinueFailedR = 2` (`FIB:1408-1411`). -/
  | asyncContinueFailedR
  /-- `AsyncContinueCanceledR = 3` (`FIB:1413-1416`). -/
  | asyncContinueCanceledR
  /-- `AsyncContinueCanceledWithFinalizerR = 4` (`FIB:1418-1422`). -/
  | asyncContinueCanceledWithFinalizerR
  /-- `BlockingR = 5` (`FIB:1424-1451`). -/
  | blockingR
  /-- `CedeR = 6` (`FIB:1453-1455`). -/
  | cedeR
  /-- `AutoCedeR = 7` (`FIB:1457-1461`). Also used by `EvalOn` (`FIB:995`). -/
  | autoCedeR
  /-- `DoneR = 8`: `run()` does nothing (`FIB:130`). -/
  | doneR
  deriving DecidableEq, Repr

/-- The byte value of a resume tag (`CONST:41-49`). -/
def ResumeTag.toNat : ResumeTag → Nat
  | .execR => 0
  | .asyncContinueSuccessfulR => 1
  | .asyncContinueFailedR => 2
  | .asyncContinueCanceledR => 3
  | .asyncContinueCanceledWithFinalizerR => 4
  | .blockingR => 5
  | .cedeR => 6
  | .autoCedeR => 7
  | .doneR => 8

/-- One entry of `objectState: ArrayStack[AnyRef]` (`FIB:87`). In Scala the stack is untyped;
these are all the kinds of object that `IOFiber` pushes. -/
inductive ObjEntry where
  /-- A `map`, `flatMap` or `handleErrorWith` function (`FIB:383`, `FIB:452`, `FIB:526`). -/
  | fn (f : Fn)
  /-- An async or blocking result (`FIB:684`, `FIB:1444`, `FIB:1512`). -/
  | val (v : Val)
  /-- An async or blocking error (`FIB:681`, `FIB:1447`, `FIB:1530`). -/
  | err (e : Err)
  /-- The previous `ExecutionContext` before `EvalOn` (`FIB:991`). -/
  | ec (id : Nat)
  /-- The canceller callback for the cancelation loop (`FIB:159`, `FIB:1142`): the
  `ContState` id of the `IO.async_` in `_cancel`, or `none` for Scala `null`. -/
  | cancelCb (state : Option Nat)
  /-- A fiber-monitor handle (stack tracing only; `FIB:1000`, `FIB:1081`). -/
  | monitorHandle
  deriving DecidableEq, Repr

/-- The callbacks in `callbacks: CallbackStack[OutcomeIO[A]]` (`FIB:89`). Each is a closure
that the runtime makes. -/
inductive OutcomeCb where
  /-- The callback given to the root fiber (for example by `unsafeRunAsync` or
  `TestControl`). -/
  | root
  /-- `oc => cb(Right(oc))` from `_join` (`FIB:182`); `state` is the `ContState` of the
  joiner's `IOCont`. -/
  | join (state : Nat)
  /-- `oc => cb(Right(Left((oc, fiberB))))` (`FIB:934`). -/
  | raceLeft (state : Nat) (other : Nat)
  /-- `oc => cb(Right(Right((fiberA, oc))))` (`FIB:935`). -/
  | raceRight (state : Nat) (other : Nat)
  /-- The callback that `unsafeRunFiber` gives to a fiber that the test harness starts from
  outside (`core/shared/src/main/scala/cats/effect/IO.scala:1117-1148`), for example the
  external canceller of the difftest runner (`difftest/.../Runner.scala`, `f.cancel.unsafeRunFiber`).
  It has no effect on the model. -/
  | ext
  deriving DecidableEq, Repr

/-- The value in a `ContState` cell (`core/shared/src/main/scala/cats/effect/ContState.scala:25-37`). -/
inductive ContVal where
  /-- "initial": `get() == null`. -/
  | initial
  /-- "waiting": `get() eq waitingSentinel`; `get` arrived first and suspended. -/
  | waiting
  /-- "result": the callback stored `Either[Throwable, Any]` (as `Val.ofExcept`). -/
  | result (r : Val)
  deriving DecidableEq, Repr

/-- `ContState` (`ContState.scala:38-45`): the cell shared by `cb`, `get` and `cancel` of
one `IOCont`. -/
structure ContState where
  /-- The fiber that runs the `IOCont` (the closure captures it, `FIB:642-757`). -/
  fiber : Nat
  /-- The atomic reference value (`ContState.scala:39`). -/
  value : ContVal := .initial
  /-- `var wasFinalizing` (`ContState.scala:38`); set at `FIB:642` and `FIB:800`. -/
  wasFinalizing : Bool
  deriving DecidableEq, Repr

/-! ## Two mask models

`IOFiber` uses a counter. The scaladoc of `MonadCancel` and `PureConc` use a fresh id per
`uncancelable`. Both share the `MaskModel` interface below. The step function takes a
`MaskModel M` as a parameter; only the mask and `poll` branches use it. -/

/-- The operations that the run loop does on the mask state. -/
structure MaskModel (M : Type) where
  /-- The mask state of a new fiber. -/
  init : M
  /-- `isUnmasked()` (`FIB:1175-1176`). -/
  isUnmasked : M → Bool
  /-- `Uncancelable` branch: mask once more and give the id for the new `poll`
  (`FIB:562-563`). -/
  enter : M → M × Nat
  /-- `UnmaskRunLoop` test: does `poll` with this id unmask now? The caller also checks
  `self eq cur.self` (`FIB:593`). -/
  pollMatches : M → Nat → Bool
  /-- `UnmaskRunLoop` when `pollMatches`: unmask (`FIB:594`). -/
  unmask : M → M
  /-- `UnmaskK` continuation: mask again (`FIB:1263`, `FIB:1326`). -/
  remask : M → M
  /-- `UncancelableK` continuation: leave the region (`FIB:1259`, `FIB:1322`). -/
  exit : M → M
  /-- `prepareFiberForCancelation`: suppress later cancelation (`FIB:1145`). -/
  finalizeMask : M → M
  /-- `done`: reset the masks (`FIB:1107-1110`). -/
  reset : M → M

/-- The `IOFiber` mask state: `private[this] var masks: Int = 0` (`FIB:103`). -/
structure CounterMask where
  /-- `masks`. A `Nat`: the run loop never makes it negative (each `-= 1` pairs with an
  earlier `+= 1`). -/
  masks : Nat := 0
  deriving DecidableEq, Repr

/-- The mirror of `IOFiber` masking. -/
def counterMaskModel : MaskModel CounterMask where
  init := {}
  isUnmasked m := m.masks == 0                 -- FIB:1176
  enter m := ({ masks := m.masks + 1 }, m.masks + 1)  -- FIB:562-563: masks += 1; id = masks
  pollMatches m id := m.masks == id            -- FIB:593: masks == cur.id
  unmask m := { masks := m.masks - 1 }         -- FIB:594
  remask m := { masks := m.masks + 1 }         -- FIB:1263
  exit m := { masks := m.masks - 1 }           -- FIB:1259
  finalizeMask m := { masks := m.masks + 1 }   -- FIB:1145
  reset _ := { masks := 0 }                    -- FIB:1110

/-- The spec mask state: a stack of mask ids, a fresh-id supply, and the ids that active
`poll` calls removed.

Mirrors `PureConc` (`kernel-testkit/shared/src/main/scala/cats/effect/kernel/testkit/pure.scala`):
`FiberCtx.masks: List[MaskId]` (`pure.scala:44-47`), a fresh `new MaskId` per `uncancelable`
(`pure.scala:297`), and `poll` drops its own id only when it is at the head
(`masks.dropWhile(mask === _)`, `pure.scala:302`). `PureConc` restores the old mask list
when `poll` ends (`localCtx`, `pure.scala:303`); `saved` does the same with the shared
`UnmaskK` continuation.

Differences from `CounterMask`:
1. Ids are never reused. An escaped `poll` used inside a later `uncancelable` of the same
   depth unmasks in `IOFiber` (equal counter) but not here.
2. `prepareFiberForCancelation` has no `PureConc` twin; here `finalizeMask` pushes the
   reserved id `0` (never given to a `poll`), so the fiber stays masked.
3. `IOFiber` also checks `self eq cur.self`; ids here are per fiber, so the caller keeps
   that check the same in both models. -/
structure SpecMask where
  /-- Active mask ids, innermost first (`FiberCtx.masks`). -/
  stack : List Nat := []
  /-- The next fresh id. Starts at 1; 0 is reserved for `finalizeMask`. -/
  fresh : Nat := 1
  /-- Ids removed by active `poll` calls, innermost first; `remask` puts the head back. -/
  saved : List Nat := []
  deriving DecidableEq, Repr

/-- The spec (fresh-id) mask model. -/
def specMaskModel : MaskModel SpecMask where
  init := {}
  isUnmasked m := m.stack.isEmpty              -- pure.scala:202 (masks.isEmpty)
  enter m := ({ m with stack := m.fresh :: m.stack, fresh := m.fresh + 1 }, m.fresh)
  pollMatches m id := m.stack.head? == some id -- pure.scala:302 (dropWhile at the head)
  unmask m := match m.stack with
    | i :: rest => { m with stack := rest, saved := i :: m.saved }
    | [] => m
  remask m := match m.saved with
    | i :: rest => { m with stack := i :: m.stack, saved := rest }
    | [] => m
  exit m := { m with stack := m.stack.tail }
  finalizeMask m := { m with stack := 0 :: m.stack }
  reset m := { m with stack := [], saved := [] }

/-- The state of one `IOFiber`, generic in the mask model `M`.

Fields not modelled: `runtime` and `tracingEvents` (`FIB:92-94`; configuration and tracing
only), and the `cancelationIterations`/`autoCedeIterations` arguments of `runLoop`
(`FIB:211-240`): they are fields of `Loop` (`CatsEffectInLean/Model/Step.lean`); an
auto-yield gives a `yielded` result and the scheduler decides when the fiber runs again. `_cancel` and `_join` (`FIB:142`,
`FIB:179`) change to `IO.unit`/`IO.pure(oc)` in `done` (`FIB:1094-1095`); they follow from
`outcome`, so they are not fields. -/
structure Fiber (M : Type) where
  /-- The fiber id (object identity in Scala). -/
  id : Nat
  /-- `localState: IOLocalState` (`FIB:85`). -/
  localState : Val := .unit
  /-- `currentCtx: ExecutionContext` (`FIB:86`), an `ExecutionContext` id. -/
  currentCtx : Nat := 0
  /-- `objectState: ArrayStack[AnyRef]` (`FIB:87`); head = top. -/
  objectState : List ObjEntry := []
  /-- `finalizers: ArrayStack[IO[Unit]]` (`FIB:88`); head = top. -/
  finalizers : List IO := []
  /-- `callbacks: CallbackStack[OutcomeIO[A]]` (`FIB:89`) as (handle, callback) pairs, newest
  first. Handle 0 is the constructor callback (the `callback` field of `CallbackStack`,
  `core/jvm-native/src/main/scala/cats/effect/CallbackStack.scala`); `push` gives fresh handles
  from `Heap.handles`. `clearHandle` removes by handle. -/
  callbacks : List (Nat × OutcomeCb) := []
  /-- `resumeTag: Byte = ExecR` (`FIB:90`). -/
  resumeTag : ResumeTag := .execR
  /-- `resumeIO: IO[Any]` (`FIB:91`); `none` for Scala `null`. -/
  resumeIO : Option IO
  /-- `conts: ByteStack.T` (`FIB:100`); head = top. -/
  conts : List ContK := []
  /-- `canceled: Boolean = false` (`FIB:102`). -/
  canceled : Bool := false
  /-- The mask state; in `IOFiber`, `masks: Int = 0` (`FIB:103`). -/
  mask : M
  /-- `finalizing: Boolean = false` (`FIB:104`). -/
  finalizing : Bool := false
  /-- `@volatile outcome: OutcomeIO[A]` (`FIB:106-107`); `none` for `null`. -/
  outcome : Option Outcome := none
  /-- The `suspended: AtomicBoolean` self type (`FIB:77-78`); the initial value is `false`
  (`core/jvm-native/src/main/scala/cats/effect/IOFiberPlatform.scala:24`). -/
  suspended : Bool := false
  deriving DecidableEq, Repr

/-- A new fiber, as the `IOFiber` constructor makes it (`FIB:68-107`): `startIO` in
`resumeIO`, resume tag `ExecR`, and one callback when `cb` is not `null`. `Start` and
`RacePair` pass `null` (`FIB:894-900`, `FIB:918-932`). -/
def Fiber.new {M : Type} (mm : MaskModel M) (id : Nat) (localState : Val) (ec : Nat)
    (startIO : IO) (cb : Option OutcomeCb) : Fiber M where
  id := id
  localState := localState
  currentCtx := ec
  callbacks := match cb with
    | some c => [(0, c)]
    | none => []
  resumeIO := some startIO
  mask := mm.init

end CatsEffectInLean.Model

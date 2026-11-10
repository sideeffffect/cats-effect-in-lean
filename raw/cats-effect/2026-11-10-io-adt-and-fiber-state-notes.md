# IO ADT, IOFiber state and NonFatal handling at v3.7.1 (research note)

> Source: https://github.com/typelevel/cats-effect/tree/v3.7.1 (local checkout ~/Projects/cats-effect at v3.7.1): `core/shared/src/main/scala/cats/effect/IO.scala`, `IOFiber.scala`, `ContState.scala`, `IODeferred.scala`, `unsafe/UnsafeNonFatal.scala`, `core/jvm/src/main/java/cats/effect/IOFiberConstants.java`, `core/jvm/src/main/java/cats/effect/tracing/TracingConstants.java`, `kernel-testkit/.../testkit/pure.scala`, `kernel/.../kernel/Sync.scala`
> Collected: 2026-11-10
> Published: 2026-08-23

Own notes, written for Phase 2 steps 1-3 (data definitions). `FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala`. `CONST` = `core/jvm/src/main/java/cats/effect/IOFiberConstants.java`.

## IO constructors (IO.scala, tag order)

| Tag | Constructor | Line | Fields |
|---|---|---|---|
| 0 | `Pure` | 2205 | `value` |
| 1 | `Error` | 2210 | `t: Throwable` |
| 2 | `Delay` | 2214 | `thunk`, `event` |
| 3 | `RealTime` | 2219 | — |
| 4 | `Monotonic` | 2223 | — |
| 5 | `ReadEC` | 2227 | — |
| 6 | `Map` | 2231 | `ioe`, `f`, `event` |
| 7 | `FlatMap` | 2236 | `ioe`, `f`, `event` |
| 8 | `Attempt` | 2244 | `ioa` |
| 9 | `HandleErrorWith` | 2248 | `ioa`, `f`, `event` |
| 10 | `Canceled` | 2256 | — |
| 11 | `OnCancel` | 2260 | `ioa`, `fin` |
| 12 | `Uncancelable` | 2264 | `body: Poll[IO] => IO[A]`, `event` |
| 13 | `Uncancelable.UnmaskRunLoop` (internal) | 2272 | `ioa`, `id: Int`, `self: IOFiber` |
| 14 | `IOCont` | 2278 | `body: Cont`, `event` |
| 15 | `IOCont.Get` (internal) | 2284 | `state: ContState` |
| 16 | `Cede` | 2289 | — |
| 17 | `Start` | 2293 | `ioa` |
| 18 | `RacePair` | 2297 | `ioa`, `iob` |
| 19 | `Sleep` | 2302 | `delay` |
| 20 | `EvalOn` | 2306 | `ioa`, `ec` |
| 21 | `Blocking` | 2310 | `hint: Sync.Type`, `thunk`, `event` |
| 22 | `Local` | 2318 | `f: IOLocalState => (IOLocalState, A)` |
| 23 | `IOTrace` | 2323 | — |
| 24 | `ReadRT` | 2327 | — |
| -1 | `EndFiber` (internal) | 2332 | — |

26 constructors (25 with tags 0-24, plus `EndFiber`). The project plan said 25.

## Continuation tags (CONST:28-38)

`MapK=0`, `FlatMapK=1`, `CancelationLoopK=2`, `RunTerminusK=3`, `EvalOnK=4`, `HandleErrorWithK=5`, `OnCancelK=6`, `UncancelableK=7`, `UnmaskK=8`, `AttemptK=9`. `MaxStackDepth = 512` (CONST:26).

## Resume tags (CONST:40-49, dispatch FIB:121-131)

`ExecR=0`, `AsyncContinueSuccessfulR=1`, `AsyncContinueFailedR=2`, `AsyncContinueCanceledR=3`, `AsyncContinueCanceledWithFinalizerR=4`, `BlockingR=5`, `CedeR=6`, `AutoCedeR=7`, `DoneR=8`.

## IOFiber fields

| Field | Line | Notes |
|---|---|---|
| `suspended: AtomicBoolean` (self type) | 77-78 | init `false` (`IOFiberPlatform.scala:24`) |
| `localState: IOLocalState` | 85 | |
| `currentCtx: ExecutionContext` | 86 | |
| `objectState: ArrayStack[AnyRef]` | 87 | functions, results, errors, old EC, cancel callback, monitor handles |
| `finalizers: ArrayStack[IO[Unit]]` | 88 | |
| `callbacks: CallbackStack[OutcomeIO[A]]` | 89 | `null` callback for `Start`/`RacePair` children |
| `resumeTag: Byte = ExecR` | 90 | |
| `resumeIO: IO[Any] = startIO` | 91 | |
| `runtime`, `tracingEvents` | 92-94 | config/tracing |
| `conts: ByteStack.T` | 100 | |
| `canceled: Boolean` | 102 | |
| `masks: Int` | 103 | |
| `finalizing: Boolean` | 104 | |
| `@volatile outcome` | 106-107 | |
| `_cancel`, `_join` | 142, 179 | swapped to `IO.unit` / `IO.pure(oc)` in `done` (1094-1095) |

## ContState (ContState.scala:25-56)

Three states in an `AtomicReference[Either[Throwable, Any]]`: initial (`null`), waiting (private sentinel `Right(null)`), result. Extra fields `wasFinalizing` (var) and `handle` (tracing).

## NonFatal facts

- The run loop uses `UnsafeNonFatal` (`unsafe/UnsafeNonFatal.scala:37-41`): fatal = `VirtualMachineError | ThreadDeath | LinkageError | ControlThrowable`. `InterruptedException` is non-fatal here (unlike `scala.util.control.NonFatal`).
- A fatal throwable from user code (thunk, `map`/`flatMap`/`handleErrorWith` function, `uncancelable` body, `IOCont` body, blocking thunk) calls `onFatalFailure` (FIB:1597-1647): it shuts down all runtimes, calls fiber error callbacks, and rethrows. No fiber `Outcome` is produced.
- `IO.raiseError(fatal)` also calls `onFatalFailure` (FIB:263-269).
- `Local` (tag 22, FIB:1058-1063) calls `cur.f(localState)` with no `try`. A throw there escapes the run loop.

## Other facts found

- `execR` (FIB:1386-1390): a fiber canceled before its first run calls `done(Canceled)` and never runs its program (#4488).
- `succeeded` trampolines: when `depth > MaxStackDepth` (512) after a `map`, it returns `IO.Pure`/`IO.Error` to the run loop (FIB:1226-1229). This adds one run-loop iteration, so one more cancelation check.
- Finalizer errors in the cancelation loop go to `reportFailure` and the loop goes on (FIB:1487-1490).
- `done` sets `masks = 0` (FIB:1107-1110) to stop spinning callbacks.
- `Get` pushes an extra no-op finalizer and `OnCancelK` when stack tracing is on (FIB:802-810). Tracing mode is `cached` by default (`TracingConstants.java:38-43`), so this is the default path.
- `RacePair` and `Sleep` expand into `IO.async` with runtime closures (FIB:908-981). `Sleep(0)` is `IO.cede`.
- `Blocking` with hint `Blocking` runs inline on a WSTP worker, else falls back to the blocking pool (`BlockingR`); interruptible hints go to `interruptibleImpl` (FIB:1005-1056).
- `PureConc` masks: `FiberCtx.masks: List[MaskId]` (pure.scala:44-47); fresh `MaskId` per `uncancelable` (297); `poll` does `masks.dropWhile(mask === _)` (302) and restores via `localCtx` (303).
- `IODeferred` fields: `cell` (58), `callbacks` (59), `clearCounter` (60).

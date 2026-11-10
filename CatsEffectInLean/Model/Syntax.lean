import CatsEffectInLean.Model.Val

/-!
# `IO` syntax and user code

Phase 2 step 2. One inductive `IO` with all constructors of the Scala `IO` ADT, in tag
order (`core/shared/src/main/scala/cats/effect/IO.scala:2205-2334` at `v3.7.1`).

User code (thunks, `map`/`flatMap` functions, `uncancelable` bodies, `IOCont` bodies,
`IOLocal` functions) is not a Lean function inside the syntax. A constructor holds a `Fn`:
either a user function id (`Fn.user`), resolved by a `UserEnv` parameter, or a closure that
the runtime itself makes (`Fn.rt`). This keeps `IO` first-order, with derived
`DecidableEq`, and kernel-evaluable (`wiki/lean/kernel-evaluation.md`, design rules).

Not modelled: `TracingEvent` arguments (`Delay`, `Map`, `FlatMap`, `HandleErrorWith`,
`Uncancelable`, `IOCont`, `Blocking`). They only feed stack tracing.
-/

namespace CatsEffectInLean.Model

/-- `Sync.Type`, the hint of `Blocking`
(`kernel/shared/src/main/scala/cats/effect/kernel/Sync.scala:289-296`).
`Delay` never reaches the `Blocking` constructor in `IO`, but we keep the full type. -/
inductive SyncType where
  /-- `Sync.Type.Delay` (`Sync.scala:292`). -/
  | delay
  /-- `Sync.Type.Blocking` (`Sync.scala:293`). -/
  | blocking
  /-- `Sync.Type.InterruptibleOnce` (`Sync.scala:294`). -/
  | interruptibleOnce
  /-- `Sync.Type.InterruptibleMany` (`Sync.scala:295`). -/
  | interruptibleMany
  deriving DecidableEq, Repr

mutual

/-- The `IO` ADT. One constructor per Scala case class, in tag order.
`IO.tag` gives the Scala tag number. Citations: `core/shared/src/main/scala/cats/effect/IO.scala`. -/
inductive IO where
  /-- Tag 0. `Pure(value)` (`IO.scala:2205-2208`). -/
  | pure (value : Val)
  /-- Tag 1. `Error(t)` (`IO.scala:2210-2212`). -/
  | error (t : Err)
  /-- Tag 2. `Delay(thunk, event)` (`IO.scala:2214-2217`). The thunk gets `Val.unit`. -/
  | delay (thunk : Fn)
  /-- Tag 3. `RealTime` (`IO.scala:2219-2221`). -/
  | realTime
  /-- Tag 4. `Monotonic` (`IO.scala:2223-2225`). -/
  | monotonic
  /-- Tag 5. `ReadEC` (`IO.scala:2227-2229`). -/
  | readEC
  /-- Tag 6. `Map(ioe, f, event)` (`IO.scala:2231-2234`). `f` returns a value. -/
  | map (ioe : IO) (f : Fn)
  /-- Tag 7. `FlatMap(ioe, f, event)` (`IO.scala:2236-2242`). `f` returns a program. -/
  | flatMap (ioe : IO) (f : Fn)
  /-- Tag 8. `Attempt(ioa)` (`IO.scala:2244-2246`). -/
  | attempt (ioa : IO)
  /-- Tag 9. `HandleErrorWith(ioa, f, event)` (`IO.scala:2248-2254`). `f` gets `Val.err e`
  and returns a program. -/
  | handleErrorWith (ioa : IO) (f : Fn)
  /-- Tag 10. `Canceled` (`IO.scala:2256-2258`). -/
  | canceled
  /-- Tag 11. `OnCancel(ioa, fin)` (`IO.scala:2260-2262`). -/
  | onCancel (ioa : IO) (fin : IO)
  /-- Tag 12. `Uncancelable(body, event)` (`IO.scala:2264-2269`). `body` gets a
  `Val.poll id fiber` and returns a program. -/
  | uncancelable (body : Fn)
  /-- Tag 13. `Uncancelable.UnmaskRunLoop(ioa, id, self)` (`IO.scala:2272-2274`). Internal:
  only `poll` makes it (`IOFiber.scala:564-567`). `self` is a fiber id. -/
  | unmaskRunLoop (ioa : IO) (id : Nat) (self : Nat)
  /-- Tag 14. `IOCont(body, event)` (`IO.scala:2278-2281`). `body` gets `Val.cont state`
  (the `cb` and `get` pair, `IOFiber.scala:642-761`) and returns a program. -/
  | ioCont (body : Fn)
  /-- Tag 15. `IOCont.Get(state)` (`IO.scala:2284-2286`). Internal: the `get` of one
  `IOCont`. `state` is the id of its `ContState` cell. -/
  | contGet (state : Nat)
  /-- Tag 16. `Cede` (`IO.scala:2289-2291`). -/
  | cede
  /-- Tag 17. `Start(ioa)` (`IO.scala:2293-2295`). -/
  | start (ioa : IO)
  /-- Tag 18. `RacePair(ioa, iob)` (`IO.scala:2297-2300`). -/
  | racePair (ioa : IO) (iob : IO)
  /-- Tag 19. `Sleep(delay)` (`IO.scala:2302-2304`). `delay` is in virtual-time units. -/
  | sleep (delay : Nat)
  /-- Tag 20. `EvalOn(ioa, ec)` (`IO.scala:2306-2308`). `ec` is an `ExecutionContext` id. -/
  | evalOn (ioa : IO) (ec : Nat)
  /-- Tag 21. `Blocking(hint, thunk, event)` (`IO.scala:2310-2316`). -/
  | blocking (hint : SyncType) (thunk : Fn)
  /-- Tag 22. `Local(f)` (`IO.scala:2318-2321`). `f` gets the `IOLocalState` (a `Val`) and
  returns `Val.pair newState result`. -/
  | local (f : Fn)
  /-- Tag 23. `IOTrace` (`IO.scala:2323-2325`). -/
  | ioTrace
  /-- Tag 24. `ReadRT` (`IO.scala:2327-2329`). -/
  | readRT
  /-- Tag -1. `EndFiber` (`IO.scala:2331-2334`). Internal: the terminal state of the run loop. -/
  | endFiber

/-- A function in the syntax: user code, or a closure that the runtime makes. -/
inductive Fn where
  /-- User code, resolved by `UserEnv.call`. -/
  | user (id : Nat)
  /-- A closure that `IOFiber` itself builds. -/
  | rt (k : RtFn)

/-- Closures that the run loop builds inside `IO` values. Each one mirrors one Scala lambda.
The step function (Phase 2 step 5) gives their meaning. More cases come with the step
function; each needs a citation. -/
inductive RtFn where
  /-- The finalizer that `Get` pushes: `IO { state.compareAndSet(state.waiting, null) }`
  (`IOFiber.scala:781-784`). -/
  | contGetFin (state : Nat)
  /-- The extra finalizer `IO { state.handle.deregister() }` that `Get` pushes when stack
  tracing is on (`IOFiber.scala:802-810`). It has no observable effect, but it changes the
  size of the `finalizers` stack. Tracing is on by default (mode `cached`,
  `core/jvm/src/main/java/cats/effect/tracing/TracingConstants.java:38-43`). -/
  | monitorDeregister (state : Nat)
  /-- The body of `_cancel` of fiber `fiber`: `IO uncancelable { _ => ... }`
  (`IOFiber.scala:142-175`). It gets the `poll` and ignores it. -/
  | cancel (fiber : Nat)
  /-- The `Cont` body of `_join` of fiber `fiber`: `_join` is `IO.asyncCheckAttempt { cb => ... }`
  (`IOFiber.scala:179-195`), and the body is `(resume, get, lift) => G.uncancelable { poll => ... }`
  (`core/shared/src/main/scala/cats/effect/IO.scala:1355-1364`). It gets `Val.cont state`. -/
  | join (fiber : Nat)
  /-- `poll => lift(k(resume)) flatMap { ... }` inside the `_join` body
  (`IO.scala:1357-1363`). `state` is the `ContState` of the joiner. It gets the `poll`. -/
  | joinUnc (fiber : Nat) (state : Nat)
  /-- `k(cb)` of `_join`: the thunk `IO { if (outcome == null) { callbacks.push(...) ... } }`
  (`IOFiber.scala:180-194`). It returns `Right(outcome)` as `Val.right oc`, or
  `Left(Some(IO { callbacks.clearHandle(handle) }))` as `Val.left (Val.some (Val.nat handle))`:
  a `Val` cannot hold an `IO`, so `joinSel` builds the `IO` again from the handle. -/
  | joinReg (fiber : Nat) (state : Nat)
  /-- The `flatMap` function of the `_join` body (`IO.scala:1358-1362`):
  `Right(a) => G.pure(a)`, `Left(Some(fin)) => G.onCancel(poll(get), lift(fin))`,
  `Left(None) => get`. `maskId`/`self` are the `poll` (`IOFiber.scala:564-567`). -/
  | joinSel (fiber : Nat) (state : Nat) (maskId : Nat) (self : Nat)
  /-- `IO { callbacks.clearHandle(handle); () }` (`IOFiber.scala:189`): the thunk of the
  finalizer that `_join` registers on the target fiber `fiber`. -/
  | joinClear (fiber : Nat) (handle : Nat)
  /-- The `Cont` body of `IO.async_[Unit] { fin => ... }` in `_cancel` (`IOFiber.scala:155-161`;
  `IO.async_` at `IO.scala:1473-1481`). It gets `Val.cont state`. -/
  | cancelAsync (fiber : Nat)
  /-- `_ => lift(IO.delay(k(resume))).flatMap(_ => get)` inside the `IO.async_` body of
  `_cancel` (`IO.scala:1476`). -/
  | cancelAsyncUnc (fiber : Nat) (state : Nat)
  /-- `k(resume)` of the `IO.async_` in `_cancel` (`IOFiber.scala:156-160`): the canceller
  takes over the target `fiber` and schedules it. `state` is the canceller's `ContState`
  (the `fin` callback). -/
  | cancelAsyncK (fiber : Nat) (state : Nat)
  /-- `_ => get` (`IO.scala:1476`): returns `IOCont.Get(state)`. -/
  | getK (state : Nat)
  /-- `_ => ()`: the function of `void` (`IO.scala:961-962`). -/
  | voidK
  /-- The `IO.async` registration that `RacePair` runs (`IOFiber.scala:912-950`). -/
  | racePairRegister (ioa : IO) (iob : IO)
  /-- The `IO.async` registration that `Sleep` runs when `delay > 0`
  (`IOFiber.scala:960-977`). -/
  | sleepRegister (delay : Nat)

end

deriving instance DecidableEq for IO, Fn, RtFn
deriving instance Repr for IO, Fn, RtFn

/-- The Scala tag of each constructor (`def tag` in `IO.scala:2206-2333`). -/
def IO.tag : IO → Int
  | .pure _ => 0
  | .error _ => 1
  | .delay _ => 2
  | .realTime => 3
  | .monotonic => 4
  | .readEC => 5
  | .map _ _ => 6
  | .flatMap _ _ => 7
  | .attempt _ => 8
  | .handleErrorWith _ _ => 9
  | .canceled => 10
  | .onCancel _ _ => 11
  | .uncancelable _ => 12
  | .unmaskRunLoop _ _ _ => 13
  | .ioCont _ => 14
  | .contGet _ => 15
  | .cede => 16
  | .start _ => 17
  | .racePair _ _ => 18
  | .sleep _ => 19
  | .evalOn _ _ => 20
  | .blocking _ _ => 21
  | .local _ => 22
  | .ioTrace => 23
  | .readRT => 24
  | .endFiber => -1

/-! ## User code

User functions are parameters (`AGENTS.md`, "Formalization method", step 1). A user function
can return a value, return a program, or throw. Before it returns, it can write `Ref` cells
and call an `IOCont` callback zero, one or more times, now or later. It sees the `Ref` cells
through a snapshot of the heap. -/

/-- One side effect of a user function call. Effects apply in list order, before the
result (`UserOut`) is used. -/
inductive UserEffect where
  /-- Write `v` into `Ref` cell `ref` (`Ref.set`; the `AtomicReference` write of `SyncRef`). -/
  | writeRef (ref : Nat) (v : Val)
  /-- Call the callback `cb` of the `IOCont` with cell `state` now, with `result`
  (`Val.ofExcept`; `IOFiber.scala:644-755`). The second and later calls are no-ops
  in `stateLoop` (`IOFiber.scala:733-734`); the step function models that
  (`contCallback`), not the user code. -/
  | invokeCb (state : Nat) (result : Val)
  /-- Keep a call of the callback of cell `state` for later: `ec.execute(task)`, where the
  task calls `cb` (another thread calls `cb`). The task goes to the end of the ready list
  (`Task.cb`, `CatsEffectInLean/Model/Step.lean`). -/
  | deferCb (state : Nat) (result : Val)
  /-- Append `v` to the observable output (`Heap.out`). Not a Cats Effect operation: it is the
  trace of a test program (for example the difftest `h.emit`). -/
  | emit (v : Val)
  /-- Allocate a new `Ref` cell with value `v` (`Ref.unsafe`, a `Delay` thunk,
  `core/shared/src/main/scala/cats/effect/IO.scala:1822-1824`). Its id is the length of the
  `Ref` list before this effect, so user code can compute it from its snapshot. -/
  | allocRef (v : Val)
  deriving DecidableEq, Repr

/-- The result of a user function call. There is no "always succeeds" case: `throw` is
always possible. -/
inductive UserOut where
  /-- The function returned a value (thunks, `map` functions). -/
  | ret (v : Val)
  /-- The function returned a program (`flatMap`, `handleErrorWith`, `uncancelable` and
  `IOCont` bodies). -/
  | prog (p : IO)
  /-- The function threw `e`. Fatal errors go to `onFatalFailure`
  (`IOFiber.scala:282-285`); `Local` does not catch at all (`IOFiber.scala:1058-1063`). -/
  | throw (e : Err)
  deriving DecidableEq, Repr

/-- The full result of one user function call: effects, then the output. -/
structure UserResult where
  /-- Side effects, in order. -/
  effects : List UserEffect := []
  /-- The output. -/
  out : UserOut
  deriving DecidableEq, Repr

/-- What user code can read when it runs: a snapshot of the shared state. -/
structure View where
  /-- The contents of the `Ref` cells (index = `Ref` id). -/
  refs : List Val := []
  /-- The outcome of each fiber (index = fiber id; `none` = not completed). User code reads it
  when it builds `fib.join` or `fib.cancel`: these read the fields `_join`/`_cancel`, and
  `done` swaps them for `IO.pure(oc)`/`IO.unit` (`IOFiber.scala:1094-1095`, `IOFiber.scala:197-207`). -/
  outcomes : List (Option Outcome) := []
  deriving DecidableEq, Repr

/-- The environment of user code: a structure of functions passed as a parameter
(`wiki/lean/kernel-evaluation.md`, design rule "User code").

`call id arg refs`: run user function `id` on `arg`, with `refs` the current contents of the
`Ref` cells (index = `Ref` id). The same function can give different results on different
heaps, so a thunk that runs twice can see different states.

The run loop calls `callV`. Its default ignores the fiber outcomes, so environments that only
need `Ref` cells give only `call`. -/
structure UserEnv where
  /-- Run user function `id` on argument `arg` with heap snapshot `refs`. -/
  call : (id : Nat) → (arg : Val) → (refs : List Val) → UserResult
  /-- Run user function `id` on argument `arg` with the full snapshot `view`. -/
  callV : (id : Nat) → (arg : Val) → (view : View) → UserResult :=
    fun id arg view => call id arg view.refs

/-- `fiber.join` of fiber `t` (`IOFiber.scala:203-207`): `readBarrier(); _join`. Before `done`,
`_join` is `IO.asyncCheckAttempt { ... }` (`IOFiber.scala:179-195`), which is
`IOCont(body)` (`IO.scala:1353-1368`). `done` swaps it for `IO.pure(oc)` (`IOFiber.scala:1094`).
`oc` is what the reader sees (`View.outcomes`). -/
def IO.joinOf (t : Nat) : Option Outcome → IO
  | some oc => .pure oc.toVal
  | none => .ioCont (.rt (.join t))

/-- `fiber.cancel` of fiber `t` (`IOFiber.scala:197-201`): `readBarrier(); _cancel`. Before
`done`, `_cancel` is `IO uncancelable { _ => ... }` (`IOFiber.scala:142`). `done` swaps it for `IO.unit`
(`IOFiber.scala:1095`), which is `IO.pure(())`. -/
def IO.cancelOf (t : Nat) : Option Outcome → IO
  | some _ => .pure .unit
  | none => .uncancelable (.rt (.cancel t))

/-- The outcome of fiber `t` in a view (`none` if the fiber does not exist or is not done). -/
def View.outcome (v : View) (t : Nat) : Option Outcome :=
  match v.outcomes[t]? with
  | some o => o
  | none => none

end CatsEffectInLean.Model

import CatsEffectInLean.Model.Sched

/-!
# Hand examples for the multi-fiber scheduler

Each example is the `IO` term that the difftest interpreter builds for one difftest case
(`difftest/src/main/scala/cats/effect/difftest/Interp.scala`; cases in
`difftest/cases/basic.jsonl` and `difftest/cases/sched.jsonl`), written by hand with the same
constructor nesting. Each example checks the outcome, the emitted trace, the number of tasks
and the schedule log against the Scala replay result (`difftest/cases/*.expected.jsonl`), by
`decide +kernel`. Both mask models give the same results here; the examples use
`counterMaskModel` (the `IOFiber` mirror), and some also `specMaskModel`.

`FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala` at `v3.7.1`.

## Encoding of closures

User code is first-order (`Fn.user id`). A closure with captured values is one id:
`enc tag a b c = tag + 100 * (a + 100 * (b + 100 * c))` (`tag`, `a`, `b` < 100).

## Emitted trace (`UserEffect.emit`), as a stand-in for the difftest events

* `call(fn, k)`: `pair (nat fn) (nat k)`;
* `fin` of `onCancel` with tag `t`: `left (nat t)`; `fin` of `async`: `right (nat t)`;
* `asyncReg` with `ContState` `s`: `some (nat s)`; a `sync` callback `i`: `some (pair s i)`.

A `later` callback emits its `cb` event in Scala when the task runs. Here the task is not user
code, so the model trace has no `cb` event for it; the schedule log shows the task.
-/

namespace CatsEffectInLean.Model.SchedExamples

open CatsEffectInLean.Model

/-- One closure id with captured values. -/
def enc (tag : Nat) (a b c : Nat := 0) : Nat := tag + 100 * (a + 100 * (b + 100 * c))

/-- A user closure with captured values. -/
def fn (tag : Nat) (a b c : Nat := 0) : Fn := .user (enc tag a b c)

/-- `UserError(4)`. -/
def e4 : Err := { code := 4 }

/-- `IO.delay(call(f, nat k))` (difftest `delay`). -/
def callT (f k : Nat) : IO := .delay (fn 5 f k)
/-- `_ => P j x y` (the `flatMap(_ => ...)` of `seq` and `*>`). -/
def K (j : Nat) (x y : Nat := 0) : Fn := fn 6 j x y
/-- `IO.cede.as(VUnit)`. -/
def cedeU : IO := .map .cede (fn 1)
/-- `IO.never` = `IO.async(_ => IO.pure(Some(IO.unit)))` (`IO.scala:1560`, `IO.scala:2198`,
`kernel/shared/src/main/scala/cats/effect/kernel/Async.scala:168`) = `IOCont(body)`. -/
def never : IO := .ioCont (fn 8)
/-- `run(e).start.map(f => VFiber(handle f))`. -/
def startH (e : IO) : IO := .map (.start e) (fn 2)
/-- `fib.join.flatMap(ocVal)`; `fib.join` reads `_join` now (`IO.joinOf`). -/
def joinO (t : Nat) (v : View) : IO := .flatMap (IO.joinOf t (v.outcome t)) (fn 4)
/-- `fib.cancel.as(VUnit)`; `fib.cancel` reads `_cancel` now (`IO.cancelOf`). -/
def cancelU (t : Nat) (v : View) : IO := .map (IO.cancelOf t (v.outcome t)) (fn 1)
/-- `IO.executionContext.flatMap(ec => IO.async(k_j))`. -/
def asyncT (j : Nat) : IO := .flatMap .readEC (fn 11 j)
/-- The `onCancel` finalizer of the difftest: `IO.delay(emit fin) *> run(fin).void`. -/
def ocFin (tag j : Nat) : IO := .flatMap (.delay (fn 16 tag)) (K j)

/-- The `async` finalizer of config `j`: `IO.delay(emit fin) *> run(fin).void`. -/
def asyncFin : Nat → IO
  | 1 => .flatMap (.delay (fn 17 5)) (K 48)
  | 3 => .flatMap (.delay (fn 17 4)) (K 48)
  | _ => .pure .unit

/-- The program table. `x`, `y` are captured fiber ids; `v` is what user code reads. -/
def P (j x y : Nat) (v : View) : IO :=
  match j with
  -- `two-fibers-*`: bind a (start T1) (bind b (start T3) (seq [join a, join b]))
  | 0 => .flatMap (startH (P' 1)) (fn 7 2)
  | 2 => .flatMap (startH (P' 5)) (fn 7 6 y)
  | 6 => .flatMap (joinO x v) (K 8 x y)
  | 8 => joinO y v
  -- `start-join`: bind f (start (delay 0 5)) (join f)
  | 10 => .flatMap (startH (callT 0 5)) (fn 7 11)
  | 11 => joinO y v
  -- `cancel-child-oncancel` and `cancel-child-masked`: seq [cede, cancel f, join f]
  | 20 => .flatMap (startH (P' 21)) (fn 7 22)
  | 22 => .flatMap (.flatMap cedeU (K 24 y)) (K 25 y)
  | 24 => cancelU x v
  | 25 => joinO x v
  | 30 => .flatMap (startH (P' 31)) (fn 7 22)
  | 36 => .flatMap (startH (.uncancelable (K 32))) (fn 7 22)
  | _ => P' j
where
  /-- The entries that do not read the view. -/
  P' : Nat → IO
  -- T1 = seq [delay 0 1, cede, delay 0 2]
  | 1 => .flatMap (.flatMap (callT 0 1) (K 3)) (K 4)
  | 3 => cedeU
  | 4 => callT 0 2
  -- T3 = seq [delay 0 3, cede, delay 0 4]
  | 5 => .flatMap (.flatMap (callT 0 3) (K 3)) (K 7)
  | 7 => callT 0 4
  -- onCancel never (delay 1 9) tag 1
  | 21 => .onCancel never (ocFin 1 23)
  | 23 => .map (callT 1 9) (fn 1)
  -- seq [uncancelable p (seq [cede, delay 0 1]), delay 0 2]
  | 31 => .flatMap (.uncancelable (K 32)) (K 33)
  | 32 => .flatMap cedeU (K 34)
  | 33 => callT 0 2
  | 34 => callT 0 1
  -- async cases
  | 40 => asyncT 0
  | 41 => asyncT 1
  | 42 => asyncT 2
  | 43 => asyncT 3
  -- `external-cancel-root`: onCancel never (delay 1 9) tag 2
  | 44 => .onCancel never (ocFin 2 23)
  | 45 => never
  | 46 => .pure (.nat 1)
  -- `fuel`: seq [cede, cede, cede, cede, cede]
  | 47 => .flatMap (.flatMap (.flatMap (.flatMap cedeU (K 3)) (K 3)) (K 3)) (K 3)
  | 48 => .map (callT 1 0) (fn 1)
  -- `async-later-error-first`: attempt (async [later err 4, sync ok 1])
  | 49 => .map (.attempt (asyncT 4)) (fn 18)
  | _ => .pure .unit

/-- The `async` registration of config `j` with `ContState` `s` (difftest `async`):
emit `asyncReg`, then each callback in order (`sync`: emit `cb` and call now; `later`:
`ec.execute` a task), then return the finalizer option (`some unit` marks `Some(fin)`). -/
def asyncReg (j s : Nat) : UserResult :=
  match j with
  -- `async-later-twice`: [later ok 1, later err 4]
  | 0 => { effects := [.emit (.some (.nat s)), .deferCb s (.right (.nat 1)),
                       .deferCb s (.left (.err e4))], out := .ret .none }
  -- `async-later-cancel`: [later ok 1], fin (delay 1 0) tag 5
  | 1 => { effects := [.emit (.some (.nat s)), .deferCb s (.right (.nat 1))],
           out := .ret (.some .unit) }
  -- `async-sync-once`: [sync ok 1]
  | 2 => { effects := [.emit (.some (.nat s)), .emit (.some (.pair (.nat s) (.nat 0))),
                       .invokeCb s (.right (.nat 1))], out := .ret .none }
  -- `async-later-error-first`: [later err 4, sync ok 1]
  | 4 => { effects := [.emit (.some (.nat s)), .deferCb s (.left (.err e4)),
                       .emit (.some (.pair (.nat s) (.nat 1))), .invokeCb s (.right (.nat 1))],
           out := .ret .none }
  -- `async-no-cb-external-cancel`: [], fin (delay 1 0) tag 4
  | _ => { effects := [.emit (.some (.nat s))], out := .ret (.some .unit) }

/-- The user environment of all examples. -/
def env : UserEnv where
  call _ _ _ := { out := .ret .unit }
  callV id arg v :=
    let tag := id % 100
    let a := id / 100 % 100
    let b := id / 10000 % 100
    let c := id / 1000000
    match tag, arg with
    -- `_ => ()` (`as(VUnit)`, `void`)
    | 1, _ => { out := .ret .unit }
    -- `f => VFiber(handle f)`
    | 2, f => { out := .ret f }
    -- `VSucceeded(_)`
    | 3, r => { out := .ret (.ocSucceeded r) }
    -- `ocVal(oc)`: `Succeeded(fa) => fa.map(VSucceeded(_))`, else `IO.pure(...)`
    | 4, .ocSucceeded r => { out := .prog (.map (.pure r) (fn 3)) }
    | 4, r => { out := .prog (.pure r) }
    -- `call(a, nat b)`: emit, then apply (`id` for 0, `unit` for 1)
    | 5, _ => { effects := [.emit (.pair (.nat a) (.nat b))],
                out := .ret (if a == 0 then .nat b else .unit) }
    | 6, _ => { out := .prog (P a b c v) }
    -- `v => run(k, env + v)` for a fiber handle
    | 7, .fiber f => { out := .prog (P a b f v) }
    -- `IO.never` body: `G.uncancelable { poll => ... }` (`IO.scala:1418-1431`)
    | 8, .cont s => { out := .prog (.uncancelable (fn 9 s)) }
    | 9, .poll m p => { out := .prog (.flatMap (.pure (.some .unit)) (fn 10 a m p)) }
    | 10, .some _ => { out := .prog (.onCancel (.unmaskRunLoop (.contGet a) b c) (.pure .unit)) }
    | 10, _ => { out := .prog (.contGet a) }
    -- `IO.async(k)` body (`IO.scala:1418-1431`)
    | 11, _ => { out := .prog (.ioCont (fn 12 a)) }
    | 12, .cont s => { out := .prog (.uncancelable (fn 13 a s)) }
    | 13, .poll m p => { out := .prog (.flatMap (.delay (fn 14 a b)) (fn 15 a b (m + 10 * p))) }
    | 14, _ => asyncReg a b
    | 15, .some _ =>
      { out := .prog (.onCancel (.unmaskRunLoop (.contGet b) (c % 10) (c / 10)) (asyncFin a)) }
    | 15, _ => { out := .prog (.contGet b) }
    -- `IO.delay(emit fin)` of `onCancel` and `async`
    | 16, _ => { effects := [.emit (.left (.nat a))], out := .ret .unit }
    | 17, _ => { effects := [.emit (.right (.nat a))], out := .ret .unit }
    -- `attempt.map { Right(v) => VRight(v); Left(UserError(c)) => VLeft(VNat(c)) }`
    | 18, .right r => { out := .ret (.right r) }
    | 18, .left (.err e) => { out := .ret (.left (.nat e.code)) }
    | _, _ => { out := .ret .unit }

/-- Run program `j` with replay choices `cs` (the counter mask model). -/
def run (j : Nat) (cs : List RChoice := []) (maxTasks : Nat := 10000) : Sched CounterMask :=
  runSchedState {} counterMaskModel env maxTasks 400 cs (Sched.init counterMaskModel (P j 0 0 {}))

/-- The same with the spec mask model. -/
def runS (j : Nat) (cs : List RChoice := []) (maxTasks : Nat := 10000) : Sched SpecMask :=
  runSchedState {} specMaskModel env maxTasks 400 cs (Sched.init specMaskModel (P j 0 0 {}))

/-- The tasks in run order: `some i` for fiber `i`, `none` for a callback task; external
cancels show the canceller fiber. -/
def tasksOf {M : Type} (s : Sched M) : List (Option Nat) :=
  (s.log.filterMap fun
    | .pick _ (.fiber i) => some (some i)
    | .pick _ (.cb _ _) => some none
    | .cancel _ c => some (some c)
    | .cancelSkipped _ => none).reverse

/-- Summary, emitted trace (oldest first), number of tasks, task order, and the number of
tasks left in the ready list (`pending` of the difftest output; no timers here). -/
def obs {M : Type} (s : Sched M) : Summary × List Val × Nat × List (Option Nat) × Nat :=
  (s.summary, s.liveHeap.out.reverse, s.tasks, tasksOf s, s.liveHeap.ready.length)

/-- The emitted `call(f, k)` event. -/
def c (f k : Nat) : Val := .pair (.nat f) (.nat k)

/-- `[0, 1, 0, 1, 0, 1, 0, 1]`, the choices of `two-fibers-chosen`. -/
def alt : List RChoice := [.pick 0, .pick 1, .pick 0, .pick 1, .pick 0, .pick 1, .pick 0, .pick 1]

/-! ## Two fibers (`two-fibers-fifo`, `two-fibers-chosen` in `basic.jsonl`)

Scala: tasks `f0 f1 f2 f1 f2 f0`, trace `1 3 2 4` (FIFO); tasks `f0 f2 f1 f1 f2 f0`, trace
`3 1 2 4` (choices). Root outcome `Succeeded(VSucceeded(4))`, 6 steps, nothing pending.
`join a` suspends the root (`_join` registration, `Get`); `a` completes in task 4 and its
`done` resumes the root (`FIB:1099`, `FIB:693`). `join b` reads `_join = IO.pure(oc)`. -/

example : obs (run 0) = (.done (.succeeded (.ocSucceeded (.nat 4))),
    [c 0 1, c 0 3, c 0 2, c 0 4], 6, [some 0, some 1, some 2, some 1, some 2, some 0], 0) := by
  decide +kernel
example : obs (run 0 alt) = (.done (.succeeded (.ocSucceeded (.nat 4))),
    [c 0 3, c 0 1, c 0 2, c 0 4], 6, [some 0, some 2, some 1, some 1, some 2, some 0], 0) := by
  decide +kernel
example : obs (runS 0 alt) = obs (run 0 alt) := by decide +kernel

/-! ## `start` + `join` (`start-join` in `sched.jsonl`)

Scala: `Succeeded(VSucceeded(5))`, tasks `f0 f1 f0`, trace `call(0, 5)`. -/

example : obs (run 10) = (.done (.succeeded (.ocSucceeded (.nat 5))), [c 0 5], 3,
    [some 0, some 1, some 0], 0) := by decide +kernel

/-! ## Cancel of a child that runs finalizers (`cancel-child-oncancel`)

The child waits in `never`. The root cancels it: the child is suspended and unmasked, so the
canceller takes over its run loop (`FIB:148-161`) and waits in `IO.async_`. The child runs the
`Get` finalizers and the user finalizer, then calls the canceller's callback (`FIB:1474-1477`)
and completes `Canceled`. Scala: `Succeeded(VCanceled)`, tasks `f0 f1 f0 f1 f0`, trace
`fin onCancel 1`, `call(1, 9)`. -/

example : obs (run 20) = (.done (.succeeded .ocCanceled), [.left (.nat 1), c 1 9], 5,
    [some 0, some 1, some 0, some 1, some 0], 0) := by decide +kernel
example : obs (runS 20) = obs (run 20) := by decide +kernel

/-! ## Cancel while masked (`cancel-child-masked`)

The child is in `uncancelable` and in the ready list (not suspended), so `cancel` takes the
`join.void` branch (`FIB:173`): the canceller waits until the child completes. The child
ends its region (`call(0, 1)`) and is canceled at the next `flatMap`, before `call(0, 2)`.
Scala: `Succeeded(VCanceled)`, tasks `f0 f1 f0 f1 f0`, trace `call(0, 1)`. -/

example : obs (run 30) = (.done (.succeeded .ocCanceled), [c 0 1], 5,
    [some 0, some 1, some 0, some 1, some 0], 0) := by decide +kernel

-- `cancel-child-masked-end`: the same, but nothing follows the region. `succeeded` unwinds
-- `UncancelableK` and `RunTerminusK` in one iteration, so no cancelation check comes: the
-- child completes `Succeeded(1)` although it was canceled. Scala: `Succeeded(VSucceeded(1))`.
example : obs (run 36) = (.done (.succeeded (.ocSucceeded (.nat 1))), [c 0 1], 5,
    [some 0, some 1, some 0, some 1, some 0], 0) := by decide +kernel

/-! ## `async` callbacks (`async-*` in `basic.jsonl` and `sched.jsonl`) -/

-- `async-later-twice`: the second callback task finds a result and does nothing
-- (FIB:733-734). Scala: `Succeeded(1)`, tasks `f0 cb0.0 cb0.1 f0`.
example : obs (run 40) = (.done (.succeeded (.nat 1)), [.some (.nat 0)], 4,
    [some 0, none, none, some 0], 0) := by decide +kernel

-- `async-sync-once`: the callback runs inside the registration; `Get` finds the result
-- (FIB:843-874). Scala: `Succeeded(1)`, one task.
example : obs (run 42) = (.done (.succeeded (.nat 1)),
    [.some (.nat 0), .some (.pair (.nat 0) (.nat 0))], 1, [some 0], 0) := by decide +kernel

-- `async-later-error-first`: [later err 4, sync ok 1]: the sync call wins; the later task
-- stays in the ready list. Scala: `Succeeded(Right(1))`, one task, 1 pending.
example : obs (run 49) = (.done (.succeeded (.right (.nat 1))),
    [.some (.nat 0), .some (.pair (.nat 0) (.nat 1))], 1, [some 0], 1) := by decide +kernel

-- `async-later-cancel` (choices `[0, cancel 0]`): callback after cancel. The canceller takes
-- over the root; the callback task then finds the root not suspended and canceled, and does
-- nothing (FIB:701-715). The root runs the `async` finalizer and completes `Canceled`.
-- Scala: `Canceled`, tasks `f0 x0 cb0.0 f0`, 1 pending (the canceller, resumed).
example : obs (run 41 [.pick 0, .cancel 0]) = (.done .canceled,
    [.some (.nat 0), .right (.nat 5), c 1 0], 4, [some 0, some 1, none, some 0], 1) := by
  decide +kernel

-- `async-no-cb-external-cancel`. Scala: `Canceled`, tasks `f0 x0 f0`, 1 pending.
example : obs (run 43 [.pick 0, .cancel 0]) = (.done .canceled,
    [.some (.nat 0), .right (.nat 4), c 1 0], 3, [some 0, some 1, some 0], 1) := by
  decide +kernel

/-! ## `never`, external cancel of the root, limits -/

-- `external-cancel-root`: `onCancel(never, fin)` and `cancel 0`. Scala: `Canceled`, tasks
-- `f0 x0 f0`, trace `fin onCancel 2`, `call(1, 9)`, 1 pending.
example : obs (run 44 [.pick 0, .cancel 0]) = (.done .canceled, [.left (.nat 2), c 1 9], 3,
    [some 0, some 1, some 0], 1) := by decide +kernel
example : obs (runS 44 [.pick 0, .cancel 0]) = obs (run 44 [.pick 0, .cancel 0]) := by
  decide +kernel

-- `never-blocked`. Scala: `blocked`, one task.
example : obs (run 45) = (.blocked, [], 1, [some 0], 0) := by decide +kernel

-- `external-cancel-root-before-start` (choices `[cancel 0]`): the root is in the ready list,
-- so the canceller joins it (FIB:173); the root sees `canceled` in `execR` (FIB:1388-1389).
-- Scala: `Canceled`, tasks `x0 f0`, 1 pending (the canceller, resumed by `done`).
example : obs (run 46 [.cancel 0]) = (.done .canceled, [], 2, [some 1, some 0], 1) := by
  decide +kernel

-- `fuel` (`maxSteps = 3`, five `cede`s). Scala: `fuel`, tasks `f0 f0 f0`, 1 pending.
example : obs (run 47 [] 3) = (.taskLimit, [], 3, [some 0, some 0, some 0], 1) := by
  decide +kernel

end CatsEffectInLean.Model.SchedExamples

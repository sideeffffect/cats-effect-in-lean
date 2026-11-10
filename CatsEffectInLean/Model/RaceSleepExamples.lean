import CatsEffectInLean.Model.SchedExamples

/-!
# Hand examples for `RacePair` and `Sleep` on the scheduler

Each example is the `IO` term that the difftest interpreter builds for one case of
`difftest/cases/racesleep.jsonl` (`difftest/src/main/scala/cats/effect/difftest/Interp.scala`),
written by hand with the same constructor nesting. Each example checks the outcome, the
emitted trace, the number of tasks, the schedule (tasks and time advances), the pending count
(ready tasks + timers) and the final time against the Scala replay result
(`difftest/cases/racesleep.expected.jsonl`), by `decide +kernel`.

`FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala` at `v3.7.1`.

Closure encoding and trace events as in `CatsEffectInLean/Model/SchedExamples.lean`
(`enc`, `fn`, `call(f, k)` = `pair (nat f) (nat k)`, `fin` of `onCancel` = `left (nat tag)`).
-/

namespace CatsEffectInLean.Model.RaceSleepExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SchedExamples (enc fn c)

/-- `IO.delay(call(f, nat k))` (difftest `delay`). -/
def callT (f k : Nat) : IO := .delay (fn 5 f k)
/-- `_ => P j` (the `flatMap(_ => ...)` of `seq`). -/
def K (j : Nat) (a : Nat := 0) : Fn := fn 6 j a
/-- `IO.sleep(ms.millis).as(VUnit)`: `Sleep(ms)` (`IO.scala:1692-1696`), then `map`. -/
def sleepU (ms : Nat) : IO := .map (.sleep ms) (fn 1)
/-- `run(e).start.map(f => VFiber(handle f))`. -/
def startH (e : IO) : IO := .map (.start e) (fn 2)
/-- `IO.never` = `IOCont(body)` (`IO.scala:1418-1431`, `IO.scala:2198`). -/
def never : IO := .ioCont (fn 9)
/-- The `onCancel` finalizer of the difftest with tag `tag`:
`IO.delay(emit fin) *> run(delay 1 9).void`. -/
def ocFin (tag : Nat) : IO := .flatMap (.delay (fn 16 tag)) (K 90)
/-- `IO.racePair(a, b).flatMap { Left((oc, fb)) => ...; Right((fa, oc)) => ... }`. -/
def raceT (a b : IO) : IO := .flatMap (.racePair a b) (fn 20)
/-- `ocVal(oc)` (`Interp.scala`). -/
def ocValT : Val → IO
  | .ocSucceeded r => .map (.pure r) (fn 3)
  | r => .pure r

/-- The program table. `a` is a captured fiber id; `v` is what user code reads. -/
def P (j a : Nat) (v : View) : IO :=
  match j with
  -- `sleep-order`: seq [start (seq [sleep 20, delay 0 1]), start (seq [sleep 10, delay 0 2]),
  -- start (seq [sleep 10, delay 0 3]), sleep 30]
  | 0 => .flatMap (.flatMap (.flatMap (startH (.flatMap (sleepU 20) (K 4))) (K 1)) (K 2)) (K 3)
  | 1 => startH (.flatMap (sleepU 10) (K 5))
  | 2 => startH (.flatMap (sleepU 10) (K 6))
  | 3 => sleepU 30
  | 4 => callT 0 1
  | 5 => callT 0 2
  | 6 => callT 0 3
  -- `race-sleep`: racePair (sleep 10) (sleep 5)
  | 10 => raceT (sleepU 10) (sleepU 5)
  -- `race-loser-cancel`: bind r (racePair (pure 1) (onCancel never (delay 1 9) tag 1))
  -- (case r of Left (o, f) => seq [cancel f, join f] | Right ...)
  | 20 => .flatMap (raceT (.pure (.nat 1)) (.onCancel never (ocFin 1))) (fn 7 21)
  -- `seq [cancel f, join f]`: `cancel` and `join` read `_cancel`/`_join` now
  | 21 => .flatMap (.map (IO.cancelOf a (v.outcome a)) (fn 1)) (K 22 a)
  | 22 => .flatMap (IO.joinOf a (v.outcome a)) (fn 4)
  -- `sleep-external-cancel`: onCancel (sleep 100) (delay 1 9) tag 3
  | 30 => .onCancel (sleepU 100) (ocFin 3)
  -- `run(delay 1 9).void`
  | 90 => .map (callT 1 9) (fn 1)
  | _ => .pure .unit

/-- The user environment of these examples. -/
def env : UserEnv where
  call _ _ _ := { out := .ret .unit }
  callV id arg v :=
    let tag := id % 100
    let a := id / 100 % 100
    let b := id / 10000 % 100
    let d := id / 1000000
    match tag, arg with
    -- `_ => ()` (`as(VUnit)`, `void`)
    | 1, _ => { out := .ret .unit }
    -- `f => VFiber(handle f)`
    | 2, f => { out := .ret f }
    -- `VSucceeded(_)`
    | 3, r => { out := .ret (.ocSucceeded r) }
    -- `ocVal` as a `flatMap` function
    | 4, r => { out := .prog (ocValT r) }
    -- `call(a, nat b)`: emit, then apply (`id` for 0, `unit` for 1)
    | 5, _ => { effects := [.emit (.pair (.nat a) (.nat b))],
                out := .ret (if a == 0 then .nat b else .unit) }
    | 6, _ => { out := .prog (P a b v) }
    -- `bind r ... (case r ...)`: split the `racePair` result, keep the loser
    | 7, .left (.pair _ (.fiber f)) => { out := .prog (P a f v) }
    | 7, .right (.pair (.fiber f) _) => { out := .prog (P a f v) }
    -- `IO.never` body (`IO.scala:1418-1431`)
    | 9, .cont s => { out := .prog (.uncancelable (fn 10 s)) }
    | 10, .poll m p => { out := .prog (.flatMap (.pure (.some .unit)) (fn 11 a m p)) }
    | 11, .some _ => { out := .prog (.onCancel (.unmaskRunLoop (.contGet a) b d) (.pure .unit)) }
    | 11, _ => { out := .prog (.contGet a) }
    -- `IO.delay(emit fin)` of `onCancel`
    | 16, _ => { effects := [.emit (.left (.nat a))], out := .ret .unit }
    -- the `racePair` result function: `ocVal(oc).map(o => VLeft(VPair(o, VFiber(fb))))`, ...
    | 20, .left (.pair oc (.fiber f)) => { out := .prog (.map (ocValT oc) (fn 21 f)) }
    | 20, .right (.pair (.fiber f) oc) => { out := .prog (.map (ocValT oc) (fn 22 f)) }
    | 21, o => { out := .ret (.left (.pair o (.fiber a))) }
    | 22, o => { out := .ret (.right (.pair (.fiber a) o)) }
    | _, _ => { out := .ret .unit }

/-- Run program `j` with replay choices `cs` (the counter mask model). -/
def run (j : Nat) (cs : List RChoice := []) : Sched CounterMask :=
  runSchedState {} counterMaskModel env 10000 600 cs (Sched.init counterMaskModel (P j 0 {}))

/-- One entry of the schedule, as the Scala `schedule` log shows it. -/
inductive Ent where
  /-- A fiber task (`f<k>`; an external canceller `x<k>` shows its model fiber id). -/
  | f (id : Nat)
  /-- A callback task (`cb<a>.<i>`). -/
  | cb
  /-- A timer task `t<k>`. -/
  | t (k : Nat)
  /-- `{"advance":ms,"woken":[t<k>…]}`. -/
  | adv (ms : Nat) (woken : List Nat)
  deriving DecidableEq, Repr

/-- The schedule in run order. -/
def sched {M : Type} (s : Sched M) : List Ent :=
  (s.log.filterMap fun
    | .pick _ (.fiber i) => some (.f i)
    | .pick _ (.cb _ _) => some .cb
    | .pick _ (.timer k _) => some (.t k)
    | .cancel _ c => some (.f c)
    | .cancelSkipped _ => none
    | .advance ms w => some (.adv ms w)).reverse

/-- Summary, emitted trace (oldest first), number of tasks, schedule, pending (ready tasks +
timers, as Scala `ec.ready.size + timers.size`), and the final time in ms. -/
def obs {M : Type} (s : Sched M) : Summary × List Val × Nat × List Ent × Nat × Nat :=
  (s.summary, s.liveHeap.out.reverse, s.tasks, sched s,
   s.liveHeap.ready.length + s.liveHeap.timers.length, s.liveHeap.clock)

/-! ## Timers (`sleep-order`, `sleep-external-cancel`) -/

-- `sleep-order`. The root starts three children, then sleeps 30 ms: timer `t0` (due 30) is
-- made first. The children make `t1` (20), `t2` (10), `t3` (10). Time moves only when nothing is
-- ready; `t2` and `t3` have the same due time and wake in creation order. Scala: tasks
-- `f0 f1 f2 f3 [10: t2 t3] t2 t3 f2 f3 [20: t1] t1 f1 [30: t0] t0 f0`, trace `2 3 1`, time 30.
example : obs (run 0) = (.done (.succeeded .unit), [c 0 2, c 0 3, c 0 1], 12,
    [.f 0, .f 1, .f 2, .f 3, .adv 10 [2, 3], .t 2, .t 3, .f 2, .f 3, .adv 20 [1], .t 1, .f 1,
     .adv 30 [0], .t 0, .f 0], 0, 30) := by
  decide +kernel

-- `sleep-external-cancel` (choices `[0, cancel 0]`). The root sleeps; the canceller takes over
-- its run loop (FIB:148-161). The `Get` finalizers run, then the `IO.async` finalizer
-- `IO(cancel.run())` (FIB:973) removes the timer, then the user finalizer. Time never moves.
-- Scala: `Canceled`, tasks `f0 x0 f0`, 1 pending (the canceller), time 0.
example : obs (run 30 [.pick 0, .cancel 0]) = (.done .canceled, [.left (.nat 3), c 1 9], 3,
    [.f 0, .f 1, .f 0], 1, 0) := by
  decide +kernel

/-! ## `RacePair` (`race-sleep`, `race-loser-cancel`) -/

-- `race-sleep`. `RacePair` makes fibers 1 (A) and 2 (B) and schedules A, then B (FIB:937-938).
-- B's timer is due first; B's `done` calls its race callback (FIB:935), which resumes the root.
-- The root completes before A wakes: A's timer stays (1 pending), the loser is not canceled.
-- Scala: `Right((fiber 1, Succeeded(())))`, tasks `f0 f1 f2 [5: t1] t1 f2 f0`, time 5.
example : obs (run 10) = (.done (.succeeded (.right (.pair (.fiber 1) (.ocSucceeded .unit)))), [],
    6, [.f 0, .f 1, .f 2, .adv 5 [1], .t 1, .f 2, .f 0], 1, 5) := by
  decide +kernel

-- `race-loser-cancel`. A wins at once; B waits in `never`. The program cancels B: the canceller
-- (the root) takes over B's run loop, B runs its finalizers and completes `Canceled`; its race
-- callback finds the race cell already done (FIB:733-734). `join` gives `Canceled`.
-- Scala: `Succeeded(VCanceled)`, tasks `f0 f1 f2 f0 f2 f0`, trace `fin onCancel 1`, `call(1, 9)`.
example : obs (run 20) = (.done (.succeeded .ocCanceled), [.left (.nat 1), c 1 9], 6,
    [.f 0, .f 1, .f 2, .f 0, .f 2, .f 0], 0, 0) := by
  decide +kernel

end CatsEffectInLean.Model.RaceSleepExamples

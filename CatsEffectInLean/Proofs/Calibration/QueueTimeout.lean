import CatsEffectInLean.Props.Calibration.QueueTimeout

/-!
# Refutation of `takeTimeoutNoLostElement` (CE-0003)

Counterexample: program A of `reproducers/CE-0003/Repro.scala` with the reproducer values:
one element `42`, timeout `1000` (1 second in ms), sleep `1` (1 ms).

Schedule: the empty choice list, so the replay scheduler always runs ready task 0 (FIFO).
Tasks (fiber ids: `f0` root, `f1` consumer, `f2` = `take` racer, `f3` = `sleep` racer,
`f4`/`f5` = the cancel fibers of the `racePair` finalizer):

1. `f0`: `Queue.unbounded`, `start` the consumer, `IO.sleep(1)` suspends (timer `t0`).
2. `f1`: `timeoutTo` enters `poll(racePair(take, sleep 1000))`; `RacePair` starts `f2`, `f3`;
   `f1` suspends in `Get` (cancelable: inside `poll`).
3. `f2`: `take` finds the buffer empty, registers as a taker and suspends in `wait`.
4. `f3`: `IO.sleep(1000)` suspends (timer `t1`).
5. Time moves to 1: `t0` resumes `f0`.
6. `f0`: `offer(42)` puts `42` in the buffer, and `notifyOne` resumes `f2`. Then
   `consumer.cancel`: `f1` is suspended, so the canceller takes it over and schedules it
   (`IOFiber.scala:155-161`); `f0` waits.
7. `f2`: `poll(take)` takes `42` from the buffer; `f2` completes `Succeeded(42)`; its race
   callback calls the `ContState` of `f1`, but `f1` is canceled: the callback loses
   (`IOFiber.scala:711-715`), and the outcome `Succeeded(42)` is dropped.
8. `f1`: runs its finalizers: the `racePair` finalizer cancels `f2` (already done) and `f3`
   (`IOFiber.scala:940-946`, fibers `f4`, `f5`). `f1` completes `Canceled`.
9. `f0`: `consumer.join` gives `Canceled`; `tryTake` gives `None`.

The root completes `Succeeded(())`. The trace has `Canceled` and `None`: `42` is not returned
and not in the queue. Upstream seeds of the reproducer show the same loss (328 of 500 seeds in
program A under `TestControl`).

A schedule that runs `f1` and then `f4` before `f2` (choices `pick 0` ×6, `pick 1`, `pick 1`)
gives `Canceled` and `Some(42)`: the model does not lose the element on every schedule.

Wrong-function test (argument, not run): if the `racePair` finalizer handed a completed child
outcome to the caller (the upstream "lossless cancelation" idea, draft PR #4710), `join` would
give `Succeeded(42)` on this schedule, `returned` would be `[42]`, and `cx_not_perm` would
fail. The schedule with `pick 1, pick 1` above shows that the statement can tell a lossless
run from a lossy one.
-/

namespace CatsEffectInLean.Proofs.Calibration.QueueTimeout

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Calibration.QueueTimeout

/-- The observation of the counterexample run. -/
def cxObs : Obs where
  summary := .done (.succeeded .unit)
  out := [.none, .ocCanceled]
  refs := [.none, .pair (.nat 1) .none, .none]
  reports := []

/-- The FIFO run of program A (`[42]`, timeout `1000`, sleep `1`) for 200 micro-steps ends
with `cxObs`. -/
theorem cx_run : runObs {} counterMaskModel env 200 [] (progA [42] 1000 1) = some cxObs := by
  decide +kernel

/-- `cxObs` is in the outcome set of program A. -/
theorem cx_outcome : outcomes {} counterMaskModel env (progA [42] 1000 1) cxObs :=
  ⟨200, [], by simp, cx_run⟩

/-- Nothing came back: the consumer got `Canceled` and the drain got `None`. -/
theorem cx_not_perm : ¬ (returned cxObs.out).Perm [42] := by
  intro h
  have := h.length_eq
  simp [returned, cxObs] at this

/-- CE-0003: `Queue.take.timeout` in a canceled fiber loses an element. -/
theorem takeTimeoutNoLostElement_refuted : ¬ takeTimeoutNoLostElement := by
  intro h
  exact cx_not_perm (h [42] 1000 1 cxObs cx_outcome .unit rfl)

end CatsEffectInLean.Proofs.Calibration.QueueTimeout

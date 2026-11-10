# `RacePair` and `Sleep` mirrored; all replay ops run on the model (own note)

> Source: own work in this repository (`CatsEffectInLean/Model/{Syntax,Step,Sched,StepExamples,SchedExamples,RaceSleepExamples}.lean`, `tools/Difftest/{Replay,Translate,Env,Tests}.lean`, `difftest/cases/gen_{deferred,racesleep}.py`, `.github/workflows/ci.yml`), Lean v4.35.0, runs against Cats Effect 3.7.1 (`difftest/run.sh`); Scala sources read at v3.7.1: `IOFiber.scala:113-207`, `:908-981`, `:1092-1126`, `:1205-1207`, `:1333-1376`; `IO.scala:1418-1431`, `:1692-1696`, `:1817-1821`; `CallbackStack.scala` (jvm-native) `:53-55`; own runner `difftest/src/main/scala/cats/effect/difftest/Runner.scala` (`replay`)
> Collected: 2026-11-10
> Published: 2026-11-10

## What the Scala code does

### `RacePair` (`IOFiber.scala:908-952`)

- The branch runs `IO.async { cb => IO { … } }`. `IO.async` is `IOCont(body)`; `body` is `G.uncancelable { poll => lift(k(resume)).flatMap { Some(fin) => G.onCancel(poll(get), lift(fin)); None => get } }` (`IO.scala:1418-1431`).
- The thunk makes `fiberA`, then `fiberB` (constructor callback `null`), then sets their callbacks with `setCallback` (`unsafeSetCallback`: the constructor slot of the `CallbackStack`, `CallbackStack.scala:53-55`). A: `oc => cb(Right(Left((oc, fiberB))))`. B: `oc => cb(Right(Right((fiberA, oc))))`.
- It schedules A, then B (`scheduleFiber`, `:937-938`). The parent goes on and suspends in `Get`.
- The finalizer `cancel` is a `for`: `fiberA.cancel.start`, `fiberB.cancel.start`, `cancelA.join`, `cancelB.join`. `fiberA.cancel` is read when the thunk runs. `fiberB.cancel`, `cancelA.join` and `cancelB.join` are read later, inside the `flatMap` functions. When the parent is canceled, the race starts two new canceller fibers (seen as `f3`, `f4` in `race-root-canceled`).
- The loser is not canceled by `racePair`. The user gets its fiber.

### `Sleep` (`IOFiber.scala:954-981`)

- `delay.length > 0`: `IO.async[Unit] { cb => IO { … Some(cancelIO) } }`. The difftest scheduler is not a `WorkStealingThreadPool`, so the thunk calls `scheduler.sleep(delay, () => cb(RightUnit))` and the finalizer is `IO(cancel.run())`.
- `delay.length == 0`: `IO.cede`. No timer.
- `IO.sleep(d)` is `Sleep(d)` for a finite `d` (`IO.scala:1692-1696`).

### Difftest replay `Scheduler` (`Runner.scala`, `replay`)

- `sleep` appends `(now + delay, CbTask("t<k>", …))` to a list; `k` counts timers. It returns a `Runnable` that removes the entry.
- Time moves only when the ready list is empty (and not on a cancel choice): all timers with the minimum due time go to the ready list in creation order, `now` jumps, and the log gets `{"advance":ms,"woken":[…]}`. Then the pick of the same loop turn runs.
- Output: `time = now / 1e6` (ms); `pending = ready.size + timers.size`.

## Model changes

- `RtFn` (Syntax.lean): `racePairBody`, `racePairUnc`, `racePairRegister` (now with the `ContState` id), `racePairSel`, `racePairCancelB`, `racePairJoinA`, `racePairJoinB`; `sleepBody`, `sleepUnc`, `sleepRegister` (now with the `ContState` id), `sleepSel`, `sleepCancel`. The two old constructors got one more argument. Nothing outside the owned files used them.
- `Task.timer id state`, `Timer` (id, due, state), `Heap.timers`, `Heap.timerCount` (Step.lean). The clock unit is the `sleep` unit (ms in the difftest).
- `runOutcomeCb`: `raceLeft`/`raceRight` call the race `ContState` callback with `Right(Left((oc, other)))` / `Right(Right((other, oc)))`. Before this they marked the run broken.
- `dispatch`: `RacePair` → `IOCont(racePairBody)`; `Sleep d` → `IOCont(sleepBody d)` if `d > 0`, else `Cede`.
- `Sched`: `LogEntry.advance`, `Sched.advance`, `runTask (.timer …)`. An advance is its own micro-step (no task, no choice used). Nothing runs between it and the next pick in Scala, so the observable order is the same.
- Replay glue: label `t<k>` for timer tasks, the `advance` log entry, `time` from the model clock, `pending` adds the timers. `unsupportedReason` is now empty: every replay op runs.
- `StepExamples` Ex 16: `Sleep 1` now suspends in the single-fiber driver (no timers there); `Sleep 0` is `Cede`.

## Results

`drive.py run --modes replay`, max size 40 unless noted, all nine fields compared.

| run | cases | agree | unsupported | mismatch |
|-----|------:|------:|------------:|---------:|
| seed 1, n 10000 | 10000 | 10000 | 0 | 0 |
| seed 2, n 10000 | 10000 | 10000 | 0 | 0 |
| seed 3, n 10000 | 10000 | 10000 | 0 | 0 |
| seed 4, n 10000 | 10000 | 10000 | 0 | 0 |
| seed 5, n 10000 | 10000 | 10000 | 0 | 0 |
| seeds 11-20, n 10000, max size 80 | 100000 | 100000 | 0 | 0 |
| fixed files (`basic`, `sched`, `deferred`, `racesleep`) | 53 | 51 | 2 (testcontrol) | 0 |

- Seed 1 (10,000 cases): 496 cases with `racePair` (outcome succeeded 179, errored 97, canceled 93, blocked 118, fuel 9; 408 print a race fiber handle), 1,318 with `sleep` (270 move time; 462 end with a pending timer).
- 150,000 generated replay cases agree. Speed: 10,000 cases in about 3 s on each side.

## Model bugs found

None. All cases agreed on the first run. The corpus stays empty.

Mutation test (plant one bug, rebuild `cediff`, seed 1, n 10000):

| mutant | mismatches |
|--------|-----------:|
| `RacePair` schedules B before A | 263 |
| race cancel does not cancel B | 9 |
| race cancel does not join | 7 |
| race callback of A names A as the other fiber | 163 |
| race without the `onCancel` finalizer | 17 |
| `IO(cancel.run())` does not remove the timer | 26 |
| `Sleep 0` makes a timer (no `cede`) | 133 |
| timer due at `delay` (not `now + delay`) | 13 |
| B has no race callback | 119 |
| advance wakes only the first due timer | 0 |
| advance wakes due timers newest first | 0 |
| `complete` resumes Deferred waiters oldest first | 0 |

The last three survive the generated cases: no generated case has two timers with the same due time, or two waiters on one `Deferred` (the gap of the first-agreement note). The fixed files close both gaps: `sleep-order` kills both advance mutants (trace, schedule), and `deferred.jsonl` kills the `complete` mutant (5 of 7 cases).

## Fixed case files

- `difftest/cases/deferred.jsonl` (`gen_deferred.py`, 7 cases): 2 or 3 waiters on one `Deferred`, FIFO and chosen wait order, a waiter canceled by the program or by an external cancel before `complete`, the root as a waiter, two `complete` calls.
  - Scala: `complete` resumes the newest waiter first (`deferred-two-waiters-fifo`: trace `complete`, `call(4)`, `call(2)`; with the order of waits swapped: `call(2)`, `call(4)`).
- `difftest/cases/racesleep.jsonl` (`gen_racesleep.py`, 13 cases): winner left/right, loser cancel, left error, root canceled during the race, race of two sleeps, timer order, `sleep(0)`, sleep + external cancel, sleep + child cancel, and the error-reporting twins below.
- Hand examples (`RaceSleepExamples.lean`, `decide +kernel`): `sleep-order`, `sleep-external-cancel`, `race-sleep`, `race-loser-cancel` (outcome, trace, tasks, schedule with advances, pending, time).
- CI runs `check` and the Lean decoder on the two new files.

## Surprises in Cats Effect (observations, not bug records)

1. **A failed `racePair` loser is never reported.** `start(fa)` that fails with nobody joined: `done` calls `reportFailure` (`IOFiber.scala:1099-1104`, `reportUnhandledFiberErrors`). A `racePair` loser that fails after the race is decided: its race callback (`:934-935`) is the constructor callback, so `callbacks(oc, false)` returns `true` and nothing is reported, although the callback only writes a `ContState` that already has a result. Scala: `start-error-reported` gives `failures = ["UserError: UserError(5)"]`; `race-loser-error-lost` gives `failures = []`. The model mirrors it (agrees). This is a twin difference (source (a) of `AGENTS.md`). Not checked yet: the docs of `racePair` and `reportUnhandledFiberErrors`, and duplicates in the CE issue tracker.
2. `racePair` does not cancel the loser: in `race-sleep` the loser's timer is still pending when the root completes.
3. `IO.sleep(0)` is `IO.cede`: a yield to the back of the ready list, not a no-op (`sleep-zero`: 2 tasks).
4. Canceling the parent during `racePair` starts two more fibers (one per `cancel`), so a canceled race takes more tasks than the two racers (`race-root-canceled`: 12 tasks).

## Open points

- Testcontrol mode (decision 15) is the last `unsupported` part.
- Generator: no template makes 2+ timers with one due time or 2+ `Deferred` waiters. The fixed files cover them; gen.py belongs to another agent.
- Triage of surprise 1: read the docs, search issues, then decide if it is a bug candidate.

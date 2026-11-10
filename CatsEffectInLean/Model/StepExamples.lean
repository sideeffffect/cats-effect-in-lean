import CatsEffectInLean.Model.Run

/-!
# Hand examples for the single-fiber run loop

Small programs with the expected result, checked by `decide +kernel` on both mask models
(`counterMaskModel` mirrors `IOFiber`, `specMaskModel` is the fresh-id spec model).
Each example names the source of its expectation. `FIB` =
`core/shared/src/main/scala/cats/effect/IOFiber.scala` at `v3.7.1`; "semantics" =
`wiki/cats-effect/semantics.md`; "laws" = `raw/effect-semantics/ce3-monadcancel-laws.md`.

User code is first-order: a closure that captures a `poll` is a function id that encodes
the `poll` id (ids `1000 + k` and `2000 + k` below).
-/

namespace CatsEffectInLean.Model.StepExamples

open CatsEffectInLean.Model

/-- A non-fatal exception. -/
def e1 : Err := { code := 1 }
/-- A fatal exception (for example `OutOfMemoryError`). -/
def eFatal : Err := { code := 2, kind := .fatal }

/-- `refs[0] := (refs[0], k)`: an append-only log in `Ref` 0. Returns `()`. -/
def logK (k : Nat) (refs : List Val) : UserResult :=
  { effects := [.writeRef 0 (.pair (refs.headD .unit) (.nat k))], out := .ret .unit }

/-- The user functions of all examples.

* 0: `_ => 1`; 1: `n => n + 1`; 2: throws `e1`; 3: throws the fatal `eFatal`.
* 4: `_ => IO.pure(2)`; 5: `_ => IO.pure(1)`; 6: `e => IO.pure(7)` (an error handler).
* 7: `poll => poll(IO.canceled)`; 8: `poll => IO.pure(poll)` (the `poll` escapes).
* 9: `p1 => IO.uncancelable(_ => p1(IO.canceled))` (via id `1000 + id`).
* 10–19: log `id - 10` in `Ref` 0 (thunks, finalizers, `map` functions).
* 20: `IOLocal` function `s => (s, s)`; 21: an `IOLocal` function that throws `e1`.
* 22: `_ => IO.canceled`; 23: `_ => IO.canceled >> IO.pure(1)`.
* 24: `_ => IO(log 1)`; 25: `_ => IO(log 0) >> IO(log 1)`; 26: `_ => IO(log 2)`.
* Other ids return `()` (ill-typed where a program is needed: `Abort.illTyped`).
* 30: `p => IO.uncancelable(_ => p(IO.canceled) >> IO.pure(1))` (via id `2000 + id`).
* 31: `p => (IO.canceled.onCancel(p(log 0))).onCancel(log 1)` (the escaped `poll` is used
  inside a finalizer).
* 1000 + k: `_ => poll_k(IO.canceled)`; 2000 + k: `_ => poll_k(IO.canceled) >> IO.pure(1)`. -/
def env : UserEnv where
  call id arg refs :=
    if id ≥ 2000 then
      { out := .prog (.flatMap (.unmaskRunLoop .canceled (id - 2000) 0) (.user 5)) }
    else if id ≥ 1000 then
      { out := .prog (.unmaskRunLoop .canceled (id - 1000) 0) }
    else if 10 ≤ id ∧ id < 20 then logK (id - 10) refs
    else
      match id, arg with
      | 0, _ => { out := .ret (.nat 1) }
      | 1, .nat n => { out := .ret (.nat (n + 1)) }
      | 2, _ => { out := .throw e1 }
      | 3, _ => { out := .throw eFatal }
      | 4, _ => { out := .prog (.pure (.nat 2)) }
      | 5, _ => { out := .prog (.pure (.nat 1)) }
      | 6, .err _ => { out := .prog (.pure (.nat 7)) }
      | 7, .poll k f => { out := .prog (.unmaskRunLoop .canceled k f) }
      | 8, p => { out := .prog (.pure p) }
      | 9, .poll k _ => { out := .prog (.uncancelable (.user (1000 + k))) }
      | 20, s => { out := .ret (.pair s s) }
      | 21, _ => { out := .throw e1 }
      | 22, _ => { out := .prog .canceled }
      | 23, _ => { out := .prog (.flatMap .canceled (.user 5)) }
      | 24, _ => { out := .prog (.delay (.user 11)) }
      | 25, _ => { out := .prog (.flatMap (.delay (.user 10)) (.user 24)) }
      | 26, _ => { out := .prog (.delay (.user 12)) }
      | 30, .poll k _ => { out := .prog (.uncancelable (.user (2000 + k))) }
      | 31, .poll k f =>
        { out := .prog (.onCancel (.onCancel .canceled (.unmaskRunLoop (.delay (.user 10)) k f))
                                  (.delay (.user 11))) }
      -- Other calls return `()`.
      | _, _ => { out := .ret .unit }

/-- Run with the default config, 200 steps, no external cancel, one `Ref` cell. -/
def runC (io : IO) : Solo CounterMask := runSolo {} counterMaskModel env 200 io [.unit]
/-- The same with the spec mask model. -/
def runS (io : IO) : Solo SpecMask := runSolo {} specMaskModel env 200 io [.unit]

/-- Run a schedule with config `cfg` and mask model `mm`, one `Ref` cell. -/
def runWith {M : Type} (cfg : Config) (mm : MaskModel M) (sched : List SoloChoice) (io : IO) :
    Solo M :=
  Solo.exec cfg mm env sched (Solo.init mm io [.unit])

/-- Summary and `Ref` 0 of a state. -/
def obs {M : Type} (s : Solo M) : Summary × Val := (s.summary, s.heap.refs.headD .unit)

/-- `n` steps that see a pending cancel (`observe = true`). -/
def go (n : Nat) : List SoloChoice := List.replicate n (.step true)
/-- `n` steps that do not see a pending cancel (`observe = false`). -/
def blind (n : Nat) : List SoloChoice := List.replicate n (.step false)

/-- Summary and `Ref` 0 under both mask models. -/
def both (io : IO) : (Summary × Val) × (Summary × Val) :=
  (((runC io).summary, (runC io).heap.refs.headD .unit),
   ((runS io).summary, (runS io).heap.refs.headD .unit))

/-- The same result `r` under both mask models. -/
def same (r : Summary × Val) : (Summary × Val) × (Summary × Val) := (r, r)

/-- `Ref` 0 after logging `ks` in order. -/
def logged (ks : List Nat) : Val := ks.foldl (fun v k => .pair v (.nat k)) .unit

/-! ## Values, errors, user code -/

-- Ex 1. `IO.pure(1)` succeeds with 1 (FIB:259-261, FIB:1492-1495).
example : both (.pure (.nat 1)) = same (.done (.succeeded (.nat 1)), .unit) := by decide +kernel

-- Ex 2. `IO.raiseError(e1)` is `Errored(e1)` (FIB:263-269, FIB:1497-1500).
example : both (.error e1) = same (.done (.errored e1), .unit) := by decide +kernel

-- Ex 3. `IO.delay(log 0)` runs the thunk once and succeeds with `()` (FIB:271-292).
example : both (.delay (.user 10)) = same (.done (.succeeded .unit), logged [0]) := by
  decide +kernel

-- Ex 4. A thunk that throws a non-fatal error is `Errored` (FIB:282-283, FIB:290).
example : both (.delay (.user 2)) = same (.done (.errored e1), .unit) := by decide +kernel

-- Ex 5. A thunk that throws a fatal error calls `onFatalFailure`: no outcome
-- (FIB:284-285, FIB:1597; UnsafeNonFatal.scala:37-41).
example : both (.delay (.user 3)) = same (.fatal eFatal, .unit) := by decide +kernel

-- Ex 6. `IO.raiseError(fatal)` is also fatal: the `Error` branch checks `UnsafeNonFatal`
-- (FIB:266-267).
example : both (.error eFatal) = same (.fatal eFatal, .unit) := by decide +kernel

-- Ex 7. `IO.pure(1).map(_ + 1)` is 2 (fast path `Map` over `Pure`, FIB:337-339).
example : both (.map (.pure (.nat 1)) (.user 1)) = same (.done (.succeeded (.nat 2)), .unit) := by
  decide +kernel

-- Ex 8. `map` over an error never calls the function (FIB:341-347, FIB:1298-1300).
example : both (.map (.error e1) (.user 10)) = same (.done (.errored e1), .unit) := by
  decide +kernel

-- Ex 9. `IO.delay(1).flatMap(n => IO.pure(2))` (fast path `FlatMap` over `Delay`,
-- FIB:420-437).
example : both (.flatMap (.delay (.user 0)) (.user 4)) = same (.done (.succeeded (.nat 2)), .unit) := by
  decide +kernel

-- Ex 10. `attempt` of an error is `Right(Left(e1))` (FIB:467-475).
example : both (.attempt (.error e1)) = same (.done (.succeeded (.left (.err e1))), .unit) := by
  decide +kernel

-- Ex 11. `attempt` of a deep error goes through `AttemptK` (FIB:1329); `attempt` of a
-- value is `Right` (FIB:1266-1267).
example : both (.attempt (.flatMap (.pure .unit) (.user 2)))
    = same (.done (.succeeded (.left (.err e1))), .unit) := by decide +kernel
example : both (.attempt (.map (.delay (.user 0)) (.user 1)))
    = same (.done (.succeeded (.right (.nat 2))), .unit) := by decide +kernel

-- Ex 12. `handleErrorWith` catches a raised error (FIB:1306-1315).
example : both (.handleErrorWith (.flatMap (.pure .unit) (.user 2)) (.user 6))
    = same (.done (.succeeded (.nat 7)), .unit) := by decide +kernel

-- Ex 13. `handleErrorWith` does not catch cancelation (semantics: Outcome; FIB:532-537).
example : both (.handleErrorWith .canceled (.user 6)) = same (.done .canceled, .unit) := by
  decide +kernel

-- Ex 14. `IOLocal`: `Local` without `try` (FIB:1058-1063). A throw leaves the run loop:
-- no outcome, the fiber never completes.
example : both (.local (.user 20)) = same (.done (.succeeded .unit), .unit) := by decide +kernel
example : both (.local (.user 21)) = same (.uncaught e1, .unit) := by decide +kernel

-- Ex 15. An ill-typed program (a `flatMap` function that returns a value) stops the model;
-- it is never a Cats Effect outcome.
example : both (.flatMap (.pure .unit) (.user 0)) = same (.aborted .illTyped, .unit) := by
  decide +kernel

-- Ex 16. `Cede` yields and the single-fiber driver runs the fiber again (`cedeR`,
-- FIB:1453-1455). `Sleep` with a positive delay registers a timer and suspends
-- (FIB:959-978); the single-fiber driver has no timers, so the fiber stays suspended.
-- `Sleep(0)` is `IO.cede` (FIB:979).
example : both .cede = same (.done (.succeeded .unit), .unit) := by decide +kernel
example : both (.flatMap (.sleep 1) (.user 4)) = same (.suspended, .unit) := by
  decide +kernel
example : both (.flatMap (.sleep 0) (.user 4)) = same (.done (.succeeded (.nat 2)), .unit) := by
  decide +kernel

/-! ## Cancelation and masking -/

-- Ex 17. `IO.canceled` alone is `Canceled` (FIB:532-537, FIB:1154-1162).
example : both .canceled = same (.done .canceled, .unit) := by decide +kernel

-- Ex 18. `IO.uncancelable(_ => IO.canceled >> IO.pure(1))` succeeds with 1 (semantics:
-- inside a mask `canceled` acts as `unit`; FIB:538-539). The flag stays set, but no
-- run-loop iteration follows the unmask: `UncancelableK` and `RunTerminusK` are popped in
-- one `succeeded` call (FIB:1258-1260, FIB:1492).
example : both (.uncancelable (.user 23)) = same (.done (.succeeded (.nat 1)), .unit) := by
  decide +kernel

-- Ex 19. The same with a `flatMap` after the region is `Canceled` (laws:
-- `uncancelableCanceledAssociatesRightOverFlatMap`). The `flatMap` function still runs; the
-- check comes at the next iteration (FIB:242).
example : both (.flatMap (.uncancelable (.user 22)) (.user 4)) = same (.done .canceled, .unit) := by
  decide +kernel

-- Ex 20. But a `map` after the region is NOT a boundary: `f` runs and the fiber
-- succeeds. So `fa.map(f)` and `fa.flatMap(a => IO.pure(f(a)))` give different outcomes
-- for `fa = IO.uncancelable(_ => IO.canceled)` (see the wiki: a twin to difftest).
example : both (.map (.uncancelable (.user 22)) (.user 10))
    = same (.done (.succeeded .unit), logged [0]) := by decide +kernel

-- Ex 21. `IO.uncancelable(poll => poll(IO.canceled))` is `Canceled` (semantics; FIB:593-600).
example : both (.uncancelable (.user 7)) = same (.done .canceled, .unit) := by decide +kernel

-- Ex 22. `onCancel`: the finalizer runs on cancel (semantics: finalizers; FIB:542-553,
-- FIB:1132-1149), and not on success (FIB:1254-1256).
example : both (.onCancel .canceled (.delay (.user 10))) = same (.done .canceled, logged [0]) := by
  decide +kernel
example : both (.onCancel (.pure (.nat 1)) (.delay (.user 10)))
    = same (.done (.succeeded (.nat 1)), .unit) := by decide +kernel

-- Ex 23. Finalizers run LIFO (semantics; laws: `canceledSequencesOnCancelInOrder`).
example : both (.onCancel (.onCancel .canceled (.delay (.user 11))) (.delay (.user 12)))
    = same (.done .canceled, logged [1, 2]) := by decide +kernel

-- Ex 24. An error in a finalizer is reported and the next finalizer still runs
-- (FIB:1487-1490). The outcome stays `Canceled`.
example : both (.onCancel (.onCancel .canceled (.error e1)) (.delay (.user 12)))
    = same (.done .canceled, logged [2]) := by decide +kernel
example : (runC (.onCancel (.onCancel .canceled (.error e1)) (.delay (.user 12)))).heap.trace
    = [.outcomeCb .root .canceled, .reportFailure e1] := by decide +kernel

-- Ex 25. `handleErrorWith` and `attempt` do not catch cancelation.
example : both (.attempt .canceled) = same (.done .canceled, .unit) := by decide +kernel

-- Ex 26. Nested regions: `poll` of the outer region inside the inner one is a no-op
-- ("the outer block wins", FIB:589-593; semantics). Both mask models agree.
example : both (.uncancelable (.user 9)) = same (.done (.succeeded .unit), .unit) := by
  decide +kernel
example : both (.flatMap (.uncancelable (.user 9)) (.user 4)) = same (.done .canceled, .unit) := by
  decide +kernel

/-! ## The two mask models differ on an escaped `poll` -/

-- Ex 27. `IO.uncancelable(p => IO.pure(p)).flatMap(p => IO.uncancelable(_ =>
-- p(IO.canceled) >> IO.pure(1)))`. Counter model (`IOFiber`): the new region has the same
-- counter value, so the escaped `poll` unmasks it and the fiber is `Canceled`. Spec model
-- (fresh ids, `PureConc`): the `poll` is stale, `canceled` is masked, result 1.
example : both (.flatMap (.uncancelable (.user 8)) (.user 30))
    = ((.done .canceled, .unit), (.done (.succeeded (.nat 1)), .unit)) := by decide +kernel

-- Ex 28. An escaped `poll` used inside a finalizer. Counter model: `poll` with id 1 matches
-- the mask that `prepareFiberForCancelation` added (FIB:1145), unmasks the finalizer
-- region, and the next iteration finalizes again (FIB:242-243). `finalizing` is already
-- set, so the rest of the finalizers are popped one per iteration and none of their bodies
-- runs (FIB:1133-1149). Spec model: both finalizers run, LIFO.
example : both (.flatMap (.uncancelable (.user 8)) (.user 31))
    = ((.done .canceled, .unit), (.done .canceled, logged [0, 1])) := by decide +kernel

/-! ## External cancel (`IOFiber.cancel`) -/

/-- `IO(log 0) >> IO(log 1)`. -/
def p1 : IO := .flatMap (.delay (.user 10)) (.user 24)
/-- `IO.uncancelable(_ => IO(log 0) >> IO(log 1)) >> IO(log 2)`. -/
def p2 : IO := .flatMap (.uncancelable (.user 25)) (.user 26)

-- Ex 29. Cancel before the first run: `execR` sees `canceled` and calls `done(Canceled)`;
-- nothing runs, no finalizer was registered (FIB:1388-1389; semantics: #4488).
example : obs (runWith {} counterMaskModel (.cancel 9 :: go 20) p1) = (.done .canceled, .unit) := by
  decide +kernel

-- Ex 30. Cancel of a running fiber. With a visible write (`observe`), the next iteration
-- finalizes (FIB:242). Without a read barrier the fiber can finish first: `Succeeded`.
example : obs (runWith {} counterMaskModel (go 2 ++ .cancel 9 :: go 20) p1)
    = (.done .canceled, logged [0]) := by decide +kernel
example : obs (runWith {} counterMaskModel (go 1 ++ .cancel 9 :: blind 20) p1)
    = (.done (.succeeded .unit), logged [0, 1]) := by decide +kernel

-- Ex 31. Cancel inside a mask is held until the region ends (semantics: masking rule).
-- Both thunks of the region run; the `flatMap` after it is a boundary; `log 2` never runs.
example : obs (runWith {} counterMaskModel (go 3 ++ .cancel 9 :: go 20) p2)
    = (.done .canceled, logged [0, 1]) := by decide +kernel
example : obs (runWith {} specMaskModel (go 3 ++ .cancel 9 :: go 20) p2)
    = (.done .canceled, logged [0, 1]) := by decide +kernel

/-! ## Scheduler-visible counters -/

/-- Small thresholds: read barrier every 2 iterations, auto-yield every 4. -/
def small : Config := { cancelationCheckThreshold := 2, autoYieldThreshold := 4 }

/-- 0 = running, 1 = parked (new or yielded), 2 = done, 3 = other. -/
def kind {M : Type} : Solo M → Nat
  | .running _ => 0
  | .parked _ => 1
  | .done _ _ => 2
  | _ => 3

/-- `IO(log 0) >> IO(log 1) >> IO(log 2) >> IO(log 2)`. -/
def p3 : IO := .flatMap (.flatMap (.flatMap (.delay (.user 10)) (.user 24)) (.user 26)) (.user 26)

-- Ex 32. Auto-yield (FIB:226-239): with thresholds 2/4 the fiber parks after every 4
-- iterations; the scheduler resumes it with `autoCedeR` (FIB:1457-1461). The result is the
-- same as with the default thresholds.
example : (List.range 12).map (fun n => kind (runWith small counterMaskModel (go n) p3))
    = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 2, 2] := by decide +kernel
example : obs (runWith small counterMaskModel (go 30) p3) = obs (runWith {} counterMaskModel (go 30) p3) := by
  decide +kernel

/-- `n` maps of `_ + 1` after `IO.uncancelable(_ => IO.canceled >> IO.pure(1))`. -/
def mapChain : Nat → IO
  | 0 => .uncancelable (.user 23)
  | n + 1 => .map (mapChain n) (.user 1)

-- Ex 33. The depth hand-back in `succeeded` (FIB:1226-1228) is an observable cancelation
-- point. With `maxStackDepth = 2`: 2 maps finish in one `succeeded` call (`Succeeded(3)`);
-- with 3 maps the third returns `IO.Pure` to the run loop, which then sees `canceled`.
example : obs (runWith { maxStackDepth := 2 } counterMaskModel (go 30) (mapChain 2))
    = (.done (.succeeded (.nat 3)), .unit) := by decide +kernel
example : obs (runWith { maxStackDepth := 2 } counterMaskModel (go 30) (mapChain 3))
    = (.done .canceled, .unit) := by decide +kernel

-- Ex 34. The same with the real constant 512: 512 maps succeed, 513 maps are canceled.
set_option maxRecDepth 100000 in
example : obs (runWith {} counterMaskModel (go 1100) (mapChain 512))
    = (.done (.succeeded (.nat 513)), .unit) := by decide +kernel
set_option maxRecDepth 100000 in
example : obs (runWith {} counterMaskModel (go 1100) (mapChain 513)) = (.done .canceled, .unit) := by
  decide +kernel

end CatsEffectInLean.Model.StepExamples

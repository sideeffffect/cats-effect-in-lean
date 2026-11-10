import CatsEffectInLean.Model.State

/-!
# Hand examples for the data definitions

Checks that programs are well-formed values, that `DecidableEq` works in the kernel
(`decide +kernel`), and that the two mask models differ on an escaped `poll`.
No step function exists yet.
-/

namespace CatsEffectInLean.Model.Examples

open CatsEffectInLean.Model

/-- `IO.delay(f0()).flatMap(f1).handleErrorWith(f2)`. -/
def prog1 : IO :=
  .handleErrorWith (.flatMap (.delay (.user 0)) (.user 1)) (.user 2)

/-- `IO.uncancelable(f3).onCancel(IO.unit)` started on a fiber and raced with `IO.sleep(5)`. -/
def prog2 : IO :=
  .racePair (.start (.onCancel (.uncancelable (.user 3)) (.pure .unit))) (.sleep 5)

/-- A user environment: function 0 writes `Ref` 0 and returns its old value; function 1
throws a fatal error; function 2 calls a callback twice; others return `()`. -/
def env : UserEnv where
  call id arg refs :=
    match id with
    | 0 => { effects := [.writeRef 0 (.nat 1)], out := .ret (refs.headD .unit) }
    | 1 => { out := .throw { code := 7, kind := .fatal } }
    | 2 => { effects := [.invokeCb 0 (.right arg), .invokeCb 0 (.right arg)],
             out := .prog (.contGet 0) }
    | _ => { out := .ret .unit }

example : prog1 ≠ prog2 := by decide +kernel
example : prog1 = .handleErrorWith (.flatMap (.delay (.user 0)) (.user 1)) (.user 2) := by
  decide +kernel
example : (IO.unmaskRunLoop .cede 1 0) ≠ (IO.unmaskRunLoop .cede 2 0) := by decide +kernel
example : (IO.delay (.rt (.contGetFin 3))) ≠ (IO.delay (.user 3)) := by decide +kernel

-- Tags follow `IO.scala:2206-2333`.
example : prog1.tag = 9 ∧ prog2.tag = 18 ∧ IO.endFiber.tag = -1 ∧ IO.readRT.tag = 24 := by
  decide +kernel
example : ContK.attemptK.toNat = 9 ∧ ResumeTag.doneR.toNat = 8 := by decide +kernel

-- User code can write a `Ref`, throw a fatal error, and call a callback twice.
example : (env.call 0 .unit [.nat 5]).out = .ret (.nat 5) := by decide +kernel
example : (env.call 1 .unit []).out = .throw { code := 7, kind := .fatal } := by decide +kernel
example : (env.call 2 (.nat 4) []).effects.length = 2 := by decide +kernel
example : (Err.isNonFatal { code := 1, kind := .interrupted }) = true := by decide +kernel

/-- An escaped `poll`: enter `uncancelable` (poll id `p`), leave it, enter a new
`uncancelable` at the same depth, then test `p`. -/
def escapedPollMatches {M : Type} (mm : MaskModel M) : Bool :=
  let (m1, p) := mm.enter mm.init
  let m2 := mm.exit m1
  let (m3, _) := mm.enter m2
  mm.pollMatches m3 p

-- The counter model (`IOFiber`) reuses the id, so the escaped `poll` unmasks the new region.
example : escapedPollMatches counterMaskModel = true := by decide +kernel
-- The spec model (`PureConc`, fresh ids) does not.
example : escapedPollMatches specMaskModel = false := by decide +kernel

-- Both models agree on plain nesting: the inner `poll` matches, the outer one does not.
example : (let (m1, p1) := counterMaskModel.enter counterMaskModel.init
           let (m2, p2) := counterMaskModel.enter m1
           (counterMaskModel.pollMatches m2 p2, counterMaskModel.pollMatches m2 p1))
          = (true, false) := by decide +kernel
example : (let (m1, p1) := specMaskModel.enter specMaskModel.init
           let (m2, p2) := specMaskModel.enter m1
           (specMaskModel.pollMatches m2 p2, specMaskModel.pollMatches m2 p1))
          = (true, false) := by decide +kernel

-- Initial states are decidable values.
example : (State.init counterMaskModel prog2).ready = [0] := by decide +kernel
example : State.init counterMaskModel prog1 ≠ State.init counterMaskModel prog2 := by
  decide +kernel
example : (State.init specMaskModel prog1).fibers.map (·.resumeTag) = [.execR] := by
  decide +kernel

end CatsEffectInLean.Model.Examples

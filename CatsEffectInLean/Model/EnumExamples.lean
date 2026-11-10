import CatsEffectInLean.Model.Enum
import CatsEffectInLean.Model.IOInstance
import CatsEffectInLean.Model.SchedExamples

/-!
# Bounded enumeration: examples and cost

Kernel-checked uses of the enumerator (`CatsEffectInLean/Model/Enum.lean`).

Cost on the two-fiber program `two-fibers` of `SchedExamples` (program `P 0`; about 40
micro-steps per run; alphabet `picks 3`), measured 2026-11-10 on the developer machine:

| depth | lists | distinct observations | `decide +kernel` | `decide_cbv` |
|---|---|---|---|---|
| 2 | 13 | 2 | 0.5 s | |
| 3 | 40 | 4 | 1.9 s | 3.8 s |
| 4 | 121 | 6 | 5.5 s | 4.5 s |
| 5 | 364 | 6 | 16.4 s | 7.2 s |
| 6 | 1,093 | 6 | | 14 s, 2 GB |
| 7 | 3,280 | 6 | | heartbeat timeout (200,000) after 19 s |

`decide +kernel` costs about 45 ms per run (×3 per depth). `decide_cbv` grows about ×2 per
depth: it shares equal subterms, but the plain enumeration does not share run prefixes.
-/

namespace CatsEffectInLean.Model.EnumExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SchedExamples (P env)

/-- `two-fibers`: every schedule with at most 3 decisions over 3 ready tasks ends with
`Succeeded(VSucceeded(4))`. -/
theorem twoFibers_depth3_allSucceeded :
    (enumResults {} counterMaskModel env 400 (picks 3) 3 (P 0 0 0 {})).all
      (fun o => o.summary == .done (.succeeded (.ocSucceeded (.nat 4)))) = true := by
  decide +kernel

/-- `two-fibers`: the bound gives 4 distinct observations (the traces differ in the order of
the `emit` events of the two children). -/
theorem twoFibers_depth3_count :
    (enumResults {} counterMaskModel env 400 (picks 3) 3 (P 0 0 0 {})).eraseDups.length = 4 := by
  decide +kernel

/-- A test environment for the law smoke tests: user function `100 + n` emits `n`; function
`1` is `_ => fa.void` for `fa = emit 7`. -/
def lawEnv : UserEnv where
  call _ _ _ := { out := .ret .unit }
  callV id _ _ :=
    if 100 ≤ id then { effects := [.emit (.nat (id - 100))], out := .ret .unit }
    else if id = 1 then { out := .prog (IOI.void (.delay (.user 107))) }
    else { out := .ret .unit }

/-- `canceledAssociatesLeftOverFlatMap` for `fa = emit 7`, in the bound: both sides give the
same observations (one: `Canceled`, empty trace). -/
theorem canceledLeft_emit7_bounded :
    enumAgree {} counterMaskModel lawEnv 50 (picks 2) 3
      (IOI.flatMap IOI.canceled (.user 1)) IOI.canceled = true := by
  decide +kernel

/-- The wrong-function check of the same law: with `canceled` replaced by `unit`, the two
sides differ (the left side emits 7). -/
theorem canceledLeft_wrongFunction_differs :
    enumAgree {} counterMaskModel lawEnv 50 (picks 2) 3
      (IOI.flatMap IOI.unit (.user 1)) IOI.unit = false := by
  decide +kernel

end CatsEffectInLean.Model.EnumExamples

import CatsEffectInLean.Model.ResourceFixed
import CatsEffectInLean.Model.EnumP

/-!
# Fixed-twin check of CE-0002 (decision 39): the domain

Rule (decision 39): a refutation is FAITHFUL only if the mirrored upstream fix satisfies the
property. Here the fix is PR #4630, mirrored as `allocatedCaseFixed`
(`CatsEffectInLean/Model/ResourceFixed.lean`).

The property (`resourceEvalPreservesUncancelable`) for one program `g`:
`alloc <-> IO.uncancelable(_ => alloc)` with `alloc` the allocation of
`Resource.eval(IO.uncancelable(_ => g))`, and `<->` = `EqvP` (all fuel values, all schedules,
with a preemption at any run-loop iteration).

## Bounded domain

Nine programs `g` (`gFamily`), with the user code of `fenv g`:

| `g` | what it tests |
|---|---|
| `IO.canceled` | the CE-0002 witness (case C) |
| `emit 1` | plain success |
| `raiseError(boom)` | error |
| `IO.canceled >> emit 1` | self-cancel, then more work under the mask |
| `start(emit 9) >> emit 1` | a child fiber that runs in parallel |
| `start(emit 9).flatMap(_.cancel)` | cancel of a child |
| `start(emit 9).flatMap(_.join)` | join of a child |
| `start(emit 9) >> IO.canceled` | a child and a self-cancel |
| `start(emit 9) >> emit 1 >> emit 2` | a child and two emits (more interleavings) |

For each `g`, `exploreP` computes all reachable states of both sides (34 to 322 states). Each
list is closed under every choice, so the outcome sets are exact: they hold for every fuel and
every choice list, not only in a bound. `decide +kernel` checks the results, one declaration per check (one `decide` for the
whole family runs out of memory at 8 GB; the largest single check takes about 30 s).

## Results

* `fixedTwin_holds` (`ResourceEvalFixed.lean`): the fixed twin satisfies the equation for all
  nine `g`.
* `old_*` (`ResourceEvalFixedOld.lean`): v3.7.1 fails it for the three `g` with a self-cancel (`IO.canceled`,
  `IO.canceled >> emit 1`, `start(emit 9) >> IO.canceled`) and satisfies it for the other six.
  So the statement separates the bug from the fix. The programs with child fibers agree for
  v3.7.1 too: under `EqvP` the extra run-loop iteration of the right side is not observed.
* `v371_fails` (`ResourceEvalFixedOld.lean`): the CE-0002 witness `g = IO.canceled` in this domain.
-/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

/-- The error of `raiseError` in the family. -/
def boom : Err := { code := 5 }

/-- `fa = IO.uncancelable(_ => g)`; the body is user function 0. -/
def fa : IO := .uncancelable (uid 0)

/-- `Resource.eval(fa).allocatedCase` at v3.7.1 (`Resource.scala:526-527`). -/
def allocOld : IO := .flatMap fa (cloFn (.evalK [] .unit))

/-- The user lambdas of the family that do not read the heap. -/
def callPure (g : IO) (id : Nat) : UserResult :=
  match id with
  -- `_ => g`, the body of `fa`
  | 0 => { out := .prog g }
  -- `_ => alloc` for the fixed twin and for v3.7.1
  | 1 => { out := .prog (allocatedCaseFixed 0) }
  | 2 => { out := .prog allocOld }
  -- thunks: `emit 1`, `emit 2`, `emit 9`
  | 3 => { effects := [.emit (.nat 1)], out := .ret .unit }
  | 4 => { effects := [.emit (.nat 2)], out := .ret .unit }
  | 5 => { effects := [.emit (.nat 9)], out := .ret .unit }
  -- `_ => IO(emit 1)`, `_ => IO(emit 2)`, `_ => IO.canceled`
  | 6 => { out := .prog (.delay (uid 3)) }
  | 7 => { out := .prog (.delay (uid 4)) }
  | 9 => { out := .prog .canceled }
  | _ => { out := .throw { code := 0 } }

/-- User code: `callPure`, and `f => f.cancel` (8), `f => f.join` (10), which read the
`_cancel`/`_join` field of the fiber they get (`View.outcome`). -/
def userOf (g : IO) : UserEnv where
  call id _ _ := callPure g id
  callV id arg v := match id, arg with
    | 8, .fiber f => { out := .prog (IO.cancelOf f (v.outcome f)) }
    | 10, .fiber f => { out := .prog (IO.joinOf f (v.outcome f)) }
    | id, _ => callPure g id

/-- The twin environment for `g`: the resource of `FClo.body` is `Resource.eval(fa)`. -/
def fenv (g : IO) : FEnv where
  base := { user := userOf g, bind := fun _ _ => .error { code := 0 },
            acquire := fun _ => .pure .unit, release := fun _ _ => .ok (.pure .unit) }
  res _ := .evalOf fa

def env (g : IO) : UserEnv := (fenv g).toEnv

/-- `start(emit 9)`. -/
def child : IO := .start (.delay (uid 5))

/-- The bounded domain of `g` (module doc). -/
def gFamily : List IO :=
  [ .canceled, .delay (uid 3), .error boom, .flatMap .canceled (uid 6),
    .flatMap child (uid 6), .flatMap child (uid 8), .flatMap child (uid 10),
    .flatMap child (uid 9), .flatMap (.flatMap child (uid 6)) (uid 7) ]

/-- The v3.7.1 allocation of the family is `allocOld` (`allocatedCase` of the mirror). -/
theorem allocatedCase_old (g : IO) :
    allocatedCase (fenv g).base (Res.evalOf fa) = .ok allocOld := rfl

/-- The search bound (more than the largest state count, 322). -/
def bound : Nat := 400

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

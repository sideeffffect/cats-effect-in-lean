import CatsEffectInLean.Model.ResourceUse
import CatsEffectInLean.Model.Outcomes

/-!
# Examples of the `Resource` use/allocated/both mirror (track Res)

Small runs of `Model/ResourceUse.lean` on the scheduler with preemption (`runObsP`, default
`Config`, `counterMaskModel`, FIFO schedule). Each check is `decide +kernel`. `out` is newest
first. Acquire markers emit `1`, `2`; release markers emit `101`, `102`.
-/

namespace CatsEffectInLean.Model.ResourceUseExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse

def boom : Err := { code := 5 }

/-- `REnv`-level user code (index `k` = program id `2 * k`): 1, 2 acquire thunks (emit 1 / 2,
return the value); 3, 4 release thunks (emit 101 / 102); 6 `_ => IO.raiseError(boom)`;
7 `_ => IO.unit`. -/
def userR : Nat → UserResult
  | 1 => { effects := [.emit (.nat 1)], out := .ret (.nat 1) }
  | 2 => { effects := [.emit (.nat 2)], out := .ret (.nat 2) }
  | 3 => { effects := [.emit (.nat 101)], out := .ret .unit }
  | 4 => { effects := [.emit (.nat 102)], out := .ret .unit }
  | 6 => { out := .prog (.error boom) }
  | 7 => { out := .prog (.pure .unit) }
  | _ => { out := .throw { code := 0 } }

/-- `make(delay(emit 1; 1))(_ => delay(emit 101) [*> raise boom])` (k = 0), and
`make(delay(emit 2; 2))(_ => delay(emit 102))` (k = 1); `Bind` function 9 gives the second. -/
def renv (failA : Bool) : REnv where
  user := { call := fun k _ _ => userR k }
  bind := fun k _ => if k == 9 then .ok (Res.make 1 1) else .error { code := 0 }
  acquire := fun k => if k == 0 then .delay (uid 1) else .delay (uid 2)
  release := fun k _ =>
    if k == 0 then .ok (if failA then .flatMap (.delay (uid 3)) (uid 6) else .delay (uid 3))
    else .ok (.delay (uid 4))

def U (failA : Bool) : UEnv where
  r := renv failA
  resOf := fun c => match c with
    | .nat 0 => some (Res.make 0 0)
    | .nat 1 => some (Res.make 1 1)
    | .nat 2 => some ((Res.make 0 0).flatMap 9)
    | _ => none

def build (x : List UserEffect × Except Err IO) : IO :=
  match x.2 with
  | .ok io => io
  | .error e => .error e

def run (U : UEnv) (p : IO) : Option (Summary × List Val) :=
  (runObsP {} counterMaskModel U.toEnv 4000 [] p).map fun o => (o.summary, o.out)

/-- `Resource.both(A, B).use_` (FIFO): both acquired, both released (concurrently: A's
release runs first on this schedule). -/
example : run (U false) (build (useUnitIO (U false) (U false).userCall (bothRes (.nat 0) (.nat 1)) {})) =
    some (.done (.succeeded .unit), [.nat 102, .nat 101, .nat 2, .nat 1]) := by decide +kernel

/-- The same with a release of A that raises: on FIFO both releases run; the error is the
outcome (on other schedules B's release is skipped: CE-0020). -/
example : run (U true) (build (useUnitIO (U true) (U true).userCall (bothRes (.nat 0) (.nat 1)) {})) =
    some (.done (.errored boom), [.nat 102, .nat 101, .nat 2, .nat 1]) := by decide +kernel

/-- `make(A).flatMap(_ => make(B)).use_`: LIFO release (B, then A). -/
example : run (U false) (build (useUnitIO (U false) (U false).userCall ((Res.make 0 0).flatMap 9) {})) =
    some (.done (.succeeded .unit), [.nat 101, .nat 102, .nat 2, .nat 1]) := by decide +kernel

/-- `make(A).flatMap(_ => make(B)).use(_ => raise)`: both released, error outcome. -/
example : run (U false) (build (useIO (U false) (U false).userCall (2 * 6) ((Res.make 0 0).flatMap 9) {})) =
    some (.done (.errored boom), [.nat 101, .nat 102, .nat 2, .nat 1]) := by decide +kernel

/-- `allocated` of `make(A).flatMap(_ => make(B))`: both acquired, no release yet. -/
example : (run (U false) (allocatedIO (.nat 2))).map Prod.snd = some [.nat 2, .nat 1] := by decide +kernel

/-- `allocated`, then the release value (`rel2` applied to `Succeeded`, the `IO#guarantee` chain):
LIFO release. User function 20 runs the release (`srcU`). -/
def user4R (k : Nat) (a : Val) : UserResult :=
  if k == 20 then match a with
    | .pair _ d => { out := .prog (srcU (U false) d) }
    | _ => { out := .throw { code := 0 } }
  else userR k

def U4 : UEnv := { U false with r := { renv false with user := { call := fun k a _ => user4R k a } } }

example : run U4 (.flatMap (allocatedIO (.nat 2)) (uid 20)) =
    some (.done (.succeeded .unit), [.nat 101, .nat 102, .nat 2, .nat 1]) := by decide +kernel

end CatsEffectInLean.Model.ResourceUseExamples

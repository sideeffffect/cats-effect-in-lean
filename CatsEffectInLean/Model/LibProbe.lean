import CatsEffectInLean.Model.WellFormed

/-!
# Probe check of `Lib.fields` (decision 56 follow-up)

`Lib.fields c` lists the closure ids that a library closure value `c` keeps in number fields.
`WF.captured` follows them, so a closure that names another closure by number holds what that
closure captured. A missing entry hides handles from `WellFormed` (review batch 7, defect D;
track G `ptLibDeep` first missed the `srcAction` codes). This module makes the lists hard to get
wrong: a kernel-checked test runs the library's own step function (`call`) and checks the list
against what `call` does.

## The test

A **probe** is an even (user) closure id that captured exactly one fresh `Ref` handle,
`.ref (probeBase + i)` (`probe i`). A **sample** is a library closure value whose number leaves
are all distinct probes (`probedOK`: each `.nat` leaf is a probe or a small tag (`< 256`, closure
headers and constructor tags); also inside nested codes, for example a `Src` code in a `Bracket`
closure). The test runs `call` on the
sample for each argument shape of `args`, with a user environment `recUC` that answers a call of
user function `k` with the program `IO.delay(k)` (so the id that `call` used appears in the
output), and checks the output with the real clause 5 (`resultOK`: `WF.progOK` and the handles of
the effects and the value) against the held handles `WF.captured lib id ++ arg.handles` (and the
identity poll, `libMade`).

A number field that `call` uses as a function id (directly, through a decoded leaf, or by putting
it into a new library closure whose own `fields` list it) brings the probe's `Ref` into the
output. That passes only if `lib.fields` lists the field, so that `WF.captured` holds the `Ref`.
A field that `fields` lists but `call` never uses makes `captured` larger: sound (stricter).

Why one sample per constructor is enough: the mirrors do not branch on the value of a user id
(only on its parity and on `ofId?`, which is `none` for an even id). So the probe stands for every
user closure in that field. An odd (library) closure in the field is followed by `WF.captured`
through the same entry of `fields`.

What the test does not cover: a field that `call` uses as a function only in a branch that no
argument of `args` reaches, and scalar number fields that must be small (they look like a closure
header and are skipped). Each library check states its coverage lemma: every constructor of its
lambda type (and of each nested code type) has a sample (`ctorIdx`).
-/

namespace CatsEffectInLean.Model.LibProbe

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.WF

/-- The first `Ref` id of the probes. Larger than every `Ref` id in `args`. -/
def probeBase : Nat := 1000

/-- Probe `i`: an even (user) closure id that captured exactly `Ref` `probeBase + i`. -/
def probe (i : Nat) : Nat := 2 * valToNat (.ref (probeBase + i))

/-- Is `n` a probe? -/
def isProbe (n : Nat) : Bool :=
  n % 2 == 0 &&
    match natToVal (n / 2) with
    | some (.ref r) => probeBase ≤ r
    | _ => false

/-- A small number: a closure header (namespace, tag) or a constructor tag, not a probe. -/
def headerNat (n : Nat) : Bool := n < 256

/-- The number leaves of a value (structural fuel). -/
def leaves : Nat → Val → List Nat
  | 0, _ => []
  | f + 1, v =>
    match v with
    | .nat n => [n]
    | .pair a b => leaves f a ++ leaves f b
    | .left x | .right x | .some x | .ocSucceeded x => leaves f x
    | _ => []

/-- A probe leaf: a probe id, or the user function number `k` of probe id `2 * k` (a model
whose fields name user function `k` by its `REnv` number, `Resource.RelFn.user k`). -/
def probeLeaf (n : Nat) : Bool := isProbe n || isProbe (2 * n)

/-- Every number leaf of a sample value is a probe (or a small tag, `headerNat`), and the probes
are distinct. -/
def probedOK (c : Val) : Bool :=
  let ls := (leaves 64 c).filter (! headerNat ·)
  (leaves 64 c).all (fun n => headerNat n || probeLeaf n) && ls.length == ls.eraseDups.length

/-- The user environment of the test: a call of user function `k` returns `IO.delay(k)`. -/
def recUC (k : Nat) (_ : Val) (_ : View) : UserResult := { out := .prog (.delay (.user k)) }

/-- The handles that an effect shows (other than an allocation). -/
def effHandles : UserEffect → List Handle
  | .writeRef i x => .ref i :: x.handles
  | .invokeCb s x | .deferCb s x => .cont s :: x.handles
  | .emit x | .allocRef x => x.handles
  | .allocDeferred | .report _ => []

/-- Clause 5 on the output, with held handles `mem`. -/
def outOK (lib : Lib) (mem : Handle → Bool) : UserOut → Bool
  | .prog p => progOK lib mem p
  | .ret x => sub mem x.handles
  | .throw _ => true

/-- Clause 5 (`WF.EffectsOK`) as a test: the effects in order, then the output; a new cell is held
after its allocation (`nr`, `nd`: the ids of the next new `Ref` and `Deferred`). -/
def effectsOK (lib : Lib) (out : UserOut) : (Handle → Bool) → Nat → Nat → List UserEffect → Bool
  | mem, _, _, [] => outOK lib mem out
  | mem, nr, nd, .allocRef x :: es =>
    sub mem x.handles && effectsOK lib out (fun h => mem h || h == .ref nr) (nr + 1) nd es
  | mem, nr, nd, .allocDeferred :: es =>
    effectsOK lib out (fun h => mem h || h == .deferred nd) nr (nd + 1) es
  | mem, nr, nd, e :: es => sub mem (effHandles e) && effectsOK lib out mem nr nd es

/-- Clause 5 on one result, with held handles `mem`, in the empty view (the test runs every call
with `{}`, so the first new `Ref` and `Deferred` have id `0`). -/
def resultOK (lib : Lib) (mem : Handle → Bool) (r : UserResult) : Bool :=
  effectsOK lib r.out mem 0 0 r.effects

/-- The argument shapes of the test. No probe `Ref` in them. -/
def args : List Val :=
  [.unit, .nat 3, .poll 1 2, .err { code := 7 }, .ocCanceled, .ocErrored { code := 7 },
   .ocSucceeded .unit, .pair .unit .ocCanceled, .pair .unit (.ocErrored { code := 7 }),
   .pair .unit (.ocSucceeded .unit), .pair .unit .unit, .left .unit, .right .unit]

/-- Handles that a library closure makes itself: the identity poll `IdPoll` (mask id `0`,
decision 37; `Bracket.srcIO` of the fixed twin source `pollDefer` builds `deferEv use a 0 0`). It is
no capability: `IO.applyPoll fa 0 s = fa`. -/
def libMade : List Handle := [.poll 0 0]

/-- The library with every odd id allowed: the output of a library closure may name internal
library closures that user code may not name (`Lib.ok` restricts user programs only). The test
checks the captured handles (`fields`), not `ok`. -/
def anyOk (lib : Lib) : Lib := { lib with ok := fun _ => true }

/-- The test for one sample `s` (closure value `toVal s`, odd id `2 * valToNat (toVal s) + 1`):
`run s arg` is the library's `call` on `s` with `recUC`, for each argument of `as` (`args`, and
argument shapes that the library needs). -/
def sampleOK {α : Type} (lib : Lib) (as : List Val) (toVal : α → Val) (run : α → Val → UserResult)
    (s : α) : Bool :=
  probedOK (toVal s) &&
    let id := 2 * valToNat (toVal s) + 1
    as.all fun a =>
      resultOK (anyOk lib) (fun h => (libMade ++ captured lib id ++ a.handles).contains h) (run s a)

end CatsEffectInLean.Model.LibProbe

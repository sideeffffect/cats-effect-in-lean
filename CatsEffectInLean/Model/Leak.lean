import CatsEffectInLean.Model.EnumP

/-!
# Leak observation: live `racePair` children of a fiber (Phase 6, track R)

`Obs` stops at root completion and does not see live fibers (decision 33). This file defines a
separate, minimal observation for the combinators that `race`, `raceOutcome`, `both`,
`bothOutcome` and `timeout` build on `racePair`.

## Definition

`RacePair` makes two fibers A and B (`IOFiber.scala:918-938`, `Model/Step.lean`
`racePairRegister`). Each gets a race callback in the constructor slot (handle 0):
`raceLeft s b` / `raceRight s a`, where `s` is the `ContState` of the `IO.async` that the
racing fiber waits on. `ContState.fiber` is the racing fiber. `done` clears the callbacks
(`FIB:1099`), so a fiber that still has such a callback and no outcome is a live race child.

* `raceChildOf h r f`: fiber `f` has no outcome and a race callback in slot 0 whose `ContState`
  belongs to fiber `r`.
* `liveRaceChildren s r`: the ids of such fibers in the live fiber table of state `s`.
* A leak of fiber `r` at a state: `r` has an outcome (its combinator returned, or it ended
  canceled or errored), but `liveRaceChildren s r ≠ []`.

The cut is the root completion (`halt = done oc`), as in `Obs`. A property that names the
racing fiber `r` states: when the root completes, `liveRaceChildren s r = []`.

Only the two children of a `racePair` are tracked. The canceller fibers of the `racePair`
finalizer (`fiberA.cancel.start`, `FIB:942-946`) are joined by the same finalizer. Fibers that
user code starts inside `fa` or `fb` (`start`) are not the combinator's fibers: Cats Effect
fibers are not structured, so they may outlive the combinator by design.

## What the real runtime shows

The Scala runner prints `pending` = ready tasks + timers at the end (`Runner.scala`). A live
fiber that waits on a callback that never comes (`IO.never`) is in neither list, so `pending`
does not show it. The observable proxy is the trace: a side with a finalizer
(`guaranteeCase`/`onCancel`, events `fin`) emits the event before the root completes if and only
if the side ended (or was canceled) before that point. The difftest compares traces and
`pending`, so agreement covers the proxy; `liveRaceChildren` is the direct model notion.

## Bounded checker

`leakFreeP bound io r`: the exact search of `exploreP` is closed and holds the start state, and
no listed state with `halt = done _` has a live race child of `r`. `leakFreeP_sound`: then this
holds for every fuel value and every `PChoice` list.
-/

namespace CatsEffectInLean.Model

section
variable {M : Type}

/-- Fiber `f` is a live race child of fiber `r` (module doc). -/
def raceChildOf (h : Heap) (r : Nat) (f : Fiber M) : Bool :=
  f.outcome.isNone && f.callbacks.any fun
    | (0, .raceLeft s _) | (0, .raceRight s _) => (h.conts[s]?.map (·.fiber)) == some r
    | _ => false

/-- The ids of the live race children of fiber `r` in state `s`. -/
def liveRaceChildren (s : Sched M) (r : Nat) : List Nat :=
  ((s.liveFibers).filter (raceChildOf s.liveHeap r)).map (·.id)

/-- The root completed (`Summary.done`). -/
def Sched.rootDone (s : Sched M) : Bool :=
  match s.halt with
  | some (.done _) => true
  | _ => false

end

section
variable {M : Type} [DecidableEq M] (cfg : Config) (mm : MaskModel M) (env : UserEnv)

/-- Bounded leak check (module doc). `false` if the search bound is too small. -/
def leakFreeP (bound : Nat) (io : IO) (r : Nat) : Bool :=
  let L := (exploreP cfg mm env bound io).map Prod.fst
  ClosedP cfg mm env L && L.contains (Sched.init mm io) &&
    L.all fun s => !s.rootDone || (liveRaceChildren s r).isEmpty

theorem leakFreeP_sound {bound : Nat} {io : IO} {r : Nat}
    (h : leakFreeP cfg mm env bound io r = true) (fuel : Nat) (cs : List PChoice) :
    (runSchedStateP cfg mm env fuel cs (Sched.init mm io)).rootDone = true →
      liveRaceChildren (runSchedStateP cfg mm env fuel cs (Sched.init mm io)) r = [] := by
  simp only [leakFreeP, Bool.and_eq_true, List.contains_iff_mem] at h
  obtain ⟨⟨hS, h0⟩, hall⟩ := h
  have hm := runSchedStateP_mem cfg mm env hS fuel cs _ h0
  have := List.all_eq_true.mp hall _ hm
  intro hd
  simp only [hd, Bool.not_true, Bool.false_or, List.isEmpty_iff] at this
  exact this

/-- A violation witness: some reachable state has the root done and a live race child of `r`
(with its choice list). Used for wrong-function tests. -/
def leakWitnessP (bound : Nat) (io : IO) (r : Nat) : Option (List PChoice) :=
  ((exploreP cfg mm env bound io).find? fun x =>
    x.1.rootDone && !(liveRaceChildren x.1 r).isEmpty).map (·.2.reverse)

end

end CatsEffectInLean.Model

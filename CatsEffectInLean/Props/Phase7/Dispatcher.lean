import CatsEffectInLean.Std.Dispatcher
import CatsEffectInLean.Model.SchedP
import CatsEffectInLean.Model.WellFormed

/-!
# `std.Dispatcher`: properties (Phase 7, track P7D)

Mirror: `Std/Dispatcher.lean`. `DP` = `std/shared/src/main/scala/cats/effect/std/Dispatcher.scala`
at `v3.7.1`.

## Promise

Scaladoc (`DP:44-58`, `:62-89`, `:130-200`):

> `unsafeToFutureCancelable`: Submits an effect to be executed, returning a `Future` that holds
> the result of its evaluation, along with a cancelation token that can be used to cancel the
> original effect. `unsafeRunAndForget`: Submits an effect to be executed with fire-and-forget
> semantics.
>
> `parallel(await)` / `sequential(await)`: Once the resource scope exits, depending on the
> termination policy all active effects will be canceled or awaited, and attempts to submit new
> effects will throw an exception. ... `sequential`: any actions submitted to
> [[Dispatcher.unsafeRunAndForget]] are guaranteed to run in exactly the order submitted, and
> subsequent actions will not start evaluation until previous actions are completed. ...
> `await`: true - wait for the completion of the active fibers; false - cancel the active fibers.

Read in context (and with issue #3506, closed as fixed in 3.4.9: an effect submitted before the
scope exits is awaited with `await = true`; the `sequential` "await work queue drain on shutdown"
test, `tests/.../DispatcherSuite.scala:45-58`): a submitted effect runs at most once; with
`await = true` every accepted submission runs to its end before `use` returns; a submission after
the close throws and never runs; `sequential` runs effects in submission order, one at a time;
`await = false` cancels running effects; a cancel of a started effect cancels it; no deadlock.

## Test program (harness)

Inputs: `par` (`parallel` or `sequential`), `aw`, `n` workers (`Cpus`), `cs` the worker choices
(`ThreadLocalRandom`), user programs `ws` (one per task), the submitter `ps[j]` of task `j`
(`0` = the `use` body, `1` = a fiber the body starts after its own submissions, `late` = the root
after `use` returned), the mode `ms[j]` (`0` = `unsafeToFutureCancelable`, `1` =
`unsafeRunAndForget`), the tasks `cn` that the body cancels (after its submissions), a user
program `c` that the concurrent fiber runs first, a user program `b` that the body runs last, and
`sw`: the body waits until each task started, cancels it, and waits until the cancel's `Future`
completed (statement 8).

1. Allocate the harness cells: `Ref` 0 = status list, 1 = user-code starts, 2 = finalizer runs,
   3 = "submission threw `IllegalStateException`" flags, 5 = the start order (a list of task
   numbers), 6 = the submission results (all lists), 4 = the dispatcher value.
2. `Dispatcher.use(d => body)` (the mirror `useIO'`), then submit the `late` tasks.
3. Task `j` = `IO.uncancelable(poll => enter(j) *> poll(ws[j].attempt).onCancel(fin(j)) *>
   mark(j, 2))`: `enter` adds 1 to the starts, sets status 1 and appends `j` to the start order;
   `fin` adds 1 to the finalizer runs and sets status 3.
4. A submission is `IO(unsafeToFutureCancelable(task j))` or `IO(unsafeRunAndForget(task j))`
   (`Dispatcher.submitIO`), `.attempt`; an `IllegalStateException` sets flag `j`; a result goes
   to cell 6. A cancel is `IO(cancel())` (`Dispatcher.cancelIO`), `.attempt`.

The user programs get no handle (not the dispatcher, not a harness cell, not a future); the
library of the statements is the `IO.never` closures (`dispLib`). Schedules: every `PChoice`
list and fuel; the `Supervisor` map order is any permutation `ho`; any worker choices `cs`.

## Statements (`XV v`: statement X with mirror variant `v`; `X = XV 0`)

1. `dispRunsOnce`: in every state each task started its user code at most once and its
   finalizer ran at most once.
2. `dispAwaitDrains`: `aw = true`, the body submits pure tasks (`IO.pure(())`), no cancel: a done
   root is `Succeeded(())` and every task has status 2. Refuted for `parallel`: CE-0091.
3. `dispNoLostSubmission`: `aw = true`, pure tasks from the body and the concurrent fiber, no
   cancel: when the root is done, every task either threw (flag) or has status 2. Refuted:
   CE-0090 (and CE-0091).
4. `dispClosedRejects`: in every state, a task whose submission threw never started; when the
   root is done `Succeeded(())`, every `late` task threw.
5. `dispSeqFifo`: `sequential`, tasks from the body only: in every state the start order is
   increasing and at most one task has status 1.
6. `dispCancels`: `aw = false`, tasks that sleep (`d ≥ 1`), body `IO.pure(())` or `IO.cede`, no
   cancel: when the root is done, no task finished its sleep (status 2).
7. `dispNoDeadlock`: pure tasks from the body, any cancels, pure body: the run is never blocked.
8. `dispCancelStops`: `parallel`, tasks that sleep (`d ≥ 1`) from the body, `sw`: when the root
   is done, every task has status 3 (its cancel, made after it started, canceled it).
-/

namespace CatsEffectInLean.Props.Phase7.Dispatcher

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.Dispatcher (DL DC dispOf? submitIO cancelIO cancelOf? useIO')

/-- The namespace of the harness closures (track P7D: 90..99). -/
def hns : Nat := 92

/-- The submitter number of a `late` task. -/
def late : Nat := 1000000

/-- The harness lambdas. `d` is the dispatcher value. -/
inductive HLam where
  /-- The thunk that allocates `Ref` 0-6. -/
  | newCells (k : Nat)
  /-- `_ => Dispatcher.use(body).flatMap(lateK)`. -/
  | afterCells (par aw : Bool) (n v : Nat) (cs : Val)
  /-- The `use` function `d => body`. -/
  | body
  /-- The thunk that saves `d` in cell 4. -/
  | saveD (d : Val)
  /-- `_ => submit the body's tasks from `j``. -/
  | subs (d : Val) (p j : Nat)
  /-- The source of task `j` (a closure reference: user code never holds it). -/
  | src (j : Nat)
  /-- `x => record the result of submitting task `j`, then the next submissions`. -/
  | rej (d : Val) (p j : Nat)
  /-- Thunk: flag of `j` := 1. -/
  | flag (j : Nat)
  /-- Thunk: result of `j` := `x`. -/
  | save (j : Nat) (x : Val)
  /-- `_ => the cancels of the body from index `i` of `cn`, then the concurrent fiber, then `b``. -/
  | cancels (d : Val) (i : Nat)
  /-- `_ => start(concurrent fiber) *> b.attempt.void`. -/
  | tail (d : Val)
  /-- `_ => submissions of the concurrent fiber`. -/
  | conc (d : Val)
  /-- `_ => b.attempt.void`. -/
  | bUser
  /-- `_ => ()`. -/
  | unitK
  /-- `poll => enter(j) *> ...` of task `j`. -/
  | cBody (j : Nat)
  /-- `_ => poll(ws[j].attempt).onCancel(fin(j)) *> mark(j, 2)`. -/
  | cRun (j m pp : Nat)
  /-- `_ => mark(j, 2)`. -/
  | cDone (j : Nat)
  /-- Thunk: starts of `j` + 1, status 1, start order `++ [j]`. -/
  | enter (j : Nat)
  /-- Thunk: finalizer runs of `j` + 1, status 3. -/
  | fin (j : Nat)
  /-- Thunk: status of `j` := `x`. -/
  | mark (j x : Nat)
  /-- `_ => cell 4`, after `use` returned. -/
  | getD
  /-- The thunk that reads cell 4. -/
  | readD
  /-- `d => submit the late tasks`. -/
  | lateK
  /-- `_ => wait until task `j` started (status ≥ 1), cancel it, wait for its cancel future`. -/
  | spinStart (d : Val) (j : Nat)
  /-- Thunk: the status of `j`. -/
  | readStatus (j : Nat)
  /-- `s => if s ≥ 1 then cancel j else cede *> spinStart`. -/
  | selStart (d : Val) (j : Nat)
  /-- `_ => spinStart d j`. -/
  | againStart (d : Val) (j : Nat)
  /-- `x => wait for the cancel future in `x`` (`pair (ref p) _` or an error). -/
  | spinCancel (d : Val) (j : Nat)
  /-- Thunk: is promise cell `p` completed? -/
  | readDone (p : Nat)
  /-- `b => if b then next task else cede *> wait`. -/
  | selDone (d : Val) (j p : Nat)
  /-- `_ => wait for `p``. -/
  | againDone (d : Val) (j p : Nat)
  deriving DecidableEq, Repr

def HLam.toVal : HLam → Val
  | .newCells k => cloVal hns 0 [.nat k]
  | .afterCells par aw n v cs => cloVal hns 1 [.bool par, .bool aw, .nat n, .nat v, cs]
  | .body => cloVal hns 2 []
  | .saveD d => cloVal hns 3 [d]
  | .subs d p j => cloVal hns 4 [d, .nat p, .nat j]
  | .src j => cloVal hns 5 [.nat j]
  | .rej d p j => cloVal hns 6 [d, .nat p, .nat j]
  | .flag j => cloVal hns 7 [.nat j]
  | .save j x => cloVal hns 8 [.nat j, x]
  | .cancels d i => cloVal hns 9 [d, .nat i]
  | .tail d => cloVal hns 10 [d]
  | .conc d => cloVal hns 11 [d]
  | .bUser => cloVal hns 12 []
  | .unitK => cloVal hns 13 []
  | .cBody j => cloVal hns 14 [.nat j]
  | .cRun j m pp => cloVal hns 15 [.nat j, .poll m pp]
  | .cDone j => cloVal hns 16 [.nat j]
  | .enter j => cloVal hns 17 [.nat j]
  | .fin j => cloVal hns 18 [.nat j]
  | .mark j x => cloVal hns 19 [.nat j, .nat x]
  | .getD => cloVal hns 20 []
  | .readD => cloVal hns 21 []
  | .lateK => cloVal hns 22 []
  | .spinStart d j => cloVal hns 24 [d, .nat j]
  | .readStatus j => cloVal hns 25 [.nat j]
  | .selStart d j => cloVal hns 26 [d, .nat j]
  | .againStart d j => cloVal hns 27 [d, .nat j]
  | .spinCancel d j => cloVal hns 28 [d, .nat j]
  | .readDone p => cloVal hns 29 [.ref p]
  | .selDone d j p => cloVal hns 30 [d, .nat j, .ref p]
  | .againDone d j p => cloVal hns 31 [d, .nat j, .ref p]

def HLam.ofFields : Nat → List Val → Option HLam
  | 0, [.nat k] => some (.newCells k)
  | 1, [.bool par, .bool aw, .nat n, .nat v, cs] => some (.afterCells par aw n v cs)
  | 2, [] => some .body
  | 3, [d] => some (.saveD d)
  | 4, [d, .nat p, .nat j] => some (.subs d p j)
  | 5, [.nat j] => some (.src j)
  | 6, [d, .nat p, .nat j] => some (.rej d p j)
  | 7, [.nat j] => some (.flag j)
  | 8, [.nat j, x] => some (.save j x)
  | 9, [d, .nat i] => some (.cancels d i)
  | 10, [d] => some (.tail d)
  | 11, [d] => some (.conc d)
  | 12, [] => some .bUser
  | 13, [] => some .unitK
  | 14, [.nat j] => some (.cBody j)
  | 15, [.nat j, .poll m pp] => some (.cRun j m pp)
  | 16, [.nat j] => some (.cDone j)
  | 17, [.nat j] => some (.enter j)
  | 18, [.nat j] => some (.fin j)
  | 19, [.nat j, .nat x] => some (.mark j x)
  | 20, [] => some .getD
  | 21, [] => some .readD
  | 22, [] => some .lateK
  | 24, [d, .nat j] => some (.spinStart d j)
  | 25, [.nat j] => some (.readStatus j)
  | 26, [d, .nat j] => some (.selStart d j)
  | 27, [d, .nat j] => some (.againStart d j)
  | 28, [d, .nat j] => some (.spinCancel d j)
  | 29, [.ref p] => some (.readDone p)
  | 30, [d, .nat j, .ref p] => some (.selDone d j p)
  | 31, [d, .nat j, .ref p] => some (.againDone d j p)
  | _, _ => none

/-- The closure id (odd: library side, not public). -/
def HLam.id (l : HLam) : Nat := 2 * valToNat l.toVal + 1

def HLam.fn (l : HLam) : Fn := .user l.id

def HLam.ofId? (id : Nat) : Option HLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == hns then HLam.ofFields tag fs else none
    | none => none
  else none

/-! ## Harness programs -/

/-- The list in a value (`[]` for another shape). -/
def lst (x : Val) : List Val := (unlistV x).getD []

/-- A number in list cell `c` at index `j` (`0` for another shape). -/
def natIn (refs : List Val) (c j : Nat) : Nat :=
  match (lst (refs.getD c .unit))[j]? with
  | some (.nat x) => x
  | _ => 0

/-- Set index `j` of list cell `c` to `x`. -/
def setIn (refs : List Val) (c j : Nat) (x : Val) : UserEffect :=
  .writeRef c (listV ((lst (refs.getD c .unit)).set j x))

/-- The inputs of the harness. -/
structure Inp where
  ws : List IO
  ps : List Nat
  ms : List Nat
  cn : List Nat
  c : IO
  b : IO
  sw : Bool
  deriving DecidableEq, Repr

/-- Task `j`. -/
def taskIO (j : Nat) : IO := .uncancelable (HLam.cBody j).fn

/-- Submit task `j` on the dispatcher `d` (its mode `ms[j]`), `.attempt`. -/
def submitOf (x : Inp) (d : Val) (j : Nat) : IO :=
  match dispOf? d with
  | some dc => .attempt (submitIO dc (.fn (HLam.src j).id) (x.ms.getD j 0 == 1))
  | none => .error CatsEffectInLean.Std.Dispatcher.illErr

/-- Submit the tasks `j' ≥ j` of submitter `p`, then go on (`after`). -/
def subsIO (x : Inp) (d : Val) (p : Nat) (after : IO) : (fuel j : Nat) → IO
  | 0, _ => after
  | fuel + 1, j =>
    if j < x.ws.length then
      if x.ps.getD j 0 == p then .flatMap (submitOf x d j) (HLam.rej d p j).fn
      else subsIO x d p after fuel (j + 1)
    else after

/-- What comes after the submissions of submitter `p`. -/
def afterSubs (d : Val) (p : Nat) : IO :=
  if p == 0 then .flatMap (.pure .unit) (HLam.cancels d 0).fn else .pure .unit

/-- The submissions of `p` from `j`. -/
def subsFrom (x : Inp) (d : Val) (p j : Nat) : IO := subsIO x d p (afterSubs d p) x.ws.length j

/-- Run a harness closure. -/
def HLam.call (x : Inp) (h : HLam) (arg : Val) (w : View) : UserResult :=
  let bad : UserResult := { out := .throw CatsEffectInLean.Std.Dispatcher.illErr }
  let k := x.ws.length
  match h, arg with
  | .newCells k', _ =>
    let z := listV (List.replicate k' (.nat 0))
    { effects := [.allocRef z, .allocRef z, .allocRef z, .allocRef z, .allocRef .unit, .allocRef .unit,
        .allocRef (listV (List.replicate k' .unit))], out := .ret .unit }
  | .afterCells par aw n v cs, _ =>
    { out := .prog (.flatMap (.flatMap (useIO' par aw n v HLam.body.id cs) HLam.getD.fn) HLam.lateK.fn) }
  | .getD, _ => { out := .prog (.delay HLam.readD.fn) }
  | .readD, _ => { out := .ret (w.refs.getD 4 .unit) }
  | .lateK, d => { out := .prog (subsFrom x d late 0) }
  | .body, d => { out := .prog (.flatMap (.delay (HLam.saveD d).fn) (HLam.subs d 0 0).fn) }
  | .saveD d, _ => { effects := [.writeRef 4 d], out := .ret .unit }
  | .subs d p j, _ => { out := .prog (subsFrom x d p j) }
  | .src _, _ => bad
  | .rej d p j, r =>
    match r with
    | .left (.err e) =>
      if e == CatsEffectInLean.Std.Dispatcher.iseErr then
        { out := .prog (.flatMap (.delay (HLam.flag j).fn) (HLam.subs d p (j + 1)).fn) }
      else { out := .prog (subsFrom x d p (j + 1)) }
    | .right v => { out := .prog (.flatMap (.delay (HLam.save j v).fn) (HLam.subs d p (j + 1)).fn) }
    | _ => { out := .prog (subsFrom x d p (j + 1)) }
  | .flag j, _ => { effects := [setIn w.refs 3 j (.nat 1)], out := .ret .unit }
  | .save j v, _ => { effects := [setIn w.refs 6 j v], out := .ret .unit }
  | .cancels d i, _ =>
    if x.sw then
      -- statement 8: for each task in order, wait until it started, cancel it, wait for the future
      if i < k then { out := .prog (.flatMap (.pure .unit) (HLam.spinStart d i).fn) }
      else { out := .prog (.flatMap (.pure .unit) (HLam.tail d).fn) }
    else
      -- `IO(cancel()).attempt` of task `j` (its submission result in cell 6, read now), if it has one
      match x.cn[i]? with
      | some j =>
        match (lst (w.refs.getD 6 .unit))[j]? with
        | some (.pair (.ref _) c) =>
          match cancelOf? c with
          | some (dc, st) => { out := .prog (.flatMap (.attempt (cancelIO dc st)) (HLam.cancels d (i + 1)).fn) }
          | none => bad
        | _ => { out := .prog (.flatMap (.pure .unit) (HLam.cancels d (i + 1)).fn) }
      | none => { out := .prog (.flatMap (.pure .unit) (HLam.tail d).fn) }
  | .tail d, _ =>
    { out := .prog (.flatMap (.start (.flatMap (.attempt x.c) (HLam.conc d).fn)) HLam.bUser.fn) }
  | .conc d, _ => { out := .prog (subsFrom x d 1 0) }
  | .bUser, _ => { out := .prog (.map (.attempt x.b) HLam.unitK.fn) }
  | .unitK, _ => { out := .ret .unit }
  | .cBody j, .poll m pp => { out := .prog (.flatMap (.delay (HLam.enter j).fn) (HLam.cRun j m pp).fn) }
  | .cRun j m pp, _ =>
    { out := .prog (.flatMap (.onCancel (IO.applyPoll (.attempt (x.ws.getD j (.pure .unit))) m pp)
        (.delay (HLam.fin j).fn)) (HLam.cDone j).fn) }
  | .cDone j, _ => { out := .prog (.delay (HLam.mark j 2).fn) }
  | .enter j, _ =>
    { effects := [setIn w.refs 1 j (.nat (natIn w.refs 1 j + 1)), setIn w.refs 0 j (.nat 1),
        .writeRef 5 (listV (lst (w.refs.getD 5 .unit) ++ [.nat j]))], out := .ret .unit }
  | .fin j, _ =>
    { effects := [setIn w.refs 2 j (.nat (natIn w.refs 2 j + 1)), setIn w.refs 0 j (.nat 3)], out := .ret .unit }
  | .mark j v, _ => { effects := [setIn w.refs 0 j (.nat v)], out := .ret .unit }
  | .spinStart d j, _ => { out := .prog (.flatMap (.delay (HLam.readStatus j).fn) (HLam.selStart d j).fn) }
  | .readStatus j, _ => { out := .ret (.nat (natIn w.refs 0 j)) }
  | .selStart d j, .nat s =>
    if s ≥ 1 then
      match (lst (w.refs.getD 6 .unit))[j]? with
      | some (.pair (.ref _) c) =>
        match cancelOf? c with
        | some (dc, st) => { out := .prog (.flatMap (.attempt (cancelIO dc st)) (HLam.spinCancel d j).fn) }
        | none => bad
      | _ => { out := .prog (.flatMap (.pure .unit) (HLam.cancels d (j + 1)).fn) }
    else { out := .prog (.flatMap .cede (HLam.againStart d j).fn) }
  | .againStart d j, _ => { out := .prog (.flatMap (.pure .unit) (HLam.spinStart d j).fn) }
  | .spinCancel d j, r =>
    match r with
    | .right (.pair (.ref p) _) => { out := .prog (.flatMap (.delay (HLam.readDone p).fn) (HLam.selDone d j p).fn) }
    | _ => { out := .prog (.flatMap (.pure .unit) (HLam.cancels d (j + 1)).fn) }
  | .readDone p, _ =>
    match w.refs.getD p .unit with
    | .pair _ (.some _) => { out := .ret (.bool true) }
    | _ => { out := .ret (.bool false) }
  | .selDone d j _, .bool true => { out := .prog (.flatMap (.pure .unit) (HLam.cancels d (j + 1)).fn) }
  | .selDone d j p, _ => { out := .prog (.flatMap .cede (HLam.againDone d j p).fn) }
  | .againDone d j p, _ => { out := .prog (.flatMap (.delay (HLam.readDone p).fn) (HLam.selDone d j p).fn) }
  | _, _ => bad

/-- The test program (`v = 0`: Cats Effect v3.7.1). -/
def prog (par aw : Bool) (n : Nat) (cs : Val) (k : Nat) (v : Nat := 0) : IO :=
  .flatMap (.delay (HLam.newCells k).fn) (HLam.afterCells par aw n v cs).fn

/-! ## Environment and run -/

/-- The external sources of the mirror: a harness source `src j` is task `j`; nothing else names
a program. -/
def ioOf : Val → IO
  | .fn id =>
    match HLam.ofId? id with
    | some (.src j) => taskIO j
    | _ => .error CatsEffectInLean.Std.Dispatcher.illErr
  | _ => .error CatsEffectInLean.Std.Dispatcher.illErr

/-- Harness closures, then user code `u`. -/
def harnessed (x : Inp) (u : UserEnv) : UserEnv where
  call id arg refs := match HLam.ofId? id with
    | some h => h.call x arg { refs }
    | none => u.call id arg refs
  callV id arg w := match HLam.ofId? id with
    | some h => h.call x arg w
    | none => u.callV id arg w

/-- The user environment of the statements: the mirror (with `Supervisor`, `Bracket`, `Race`,
`Timeout`), the harness, user code `u`; map order `ho`. -/
def env (ho : List Val → List Val) (x : Inp) (u : UserEnv) : UserEnv :=
  CatsEffectInLean.Std.Dispatcher.env ho ioOf (harnessed x u)

/-- The final state: `fuel` micro-steps of the preemptive scheduler with choices `cs`. -/
def run (ho : List Val → List Val) (par aw : Bool) (n : Nat) (wc : Val) (x : Inp) (u : UserEnv)
    (fuel : Nat) (cs : List PChoice) (v : Nat := 0) : Sched CounterMask :=
  runSchedStateP {} counterMaskModel (env ho x u) fuel cs
    (Sched.init counterMaskModel (prog par aw n wc x.ws.length v))

/-! ## Observations (harness cells) -/

/-- The status of task `j` (`Ref` 0). -/
def status {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 0 j
/-- The user-code starts of task `j` (`Ref` 1). -/
def runs {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 1 j
/-- The finalizer runs of task `j` (`Ref` 2). -/
def fins {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 2 j
/-- Did the submission of task `j` throw `IllegalStateException` (`Ref` 3)? -/
def rejected {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 3 j
/-- The start order (`Ref` 5). -/
def order {M : Type} (s : Sched M) : List Nat :=
  (lst (s.liveHeap.refs.getD 5 .unit)).map fun v => match v with | .nat j => j | _ => 0

/-- A list of numbers is strictly increasing. -/
def Increasing : List Nat → Prop
  | a :: b :: r => a < b ∧ Increasing (b :: r)
  | _ => True

/-- Is `id` one of the `IO.never` closures (`Timeout.neverIO`)? -/
def isNeverClo (id : Nat) : Bool :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) =>
      if k == Timeout.ns then
        match Timeout.TLam.ofFields tag fs with
        | some .neverBody | some (.neverUnc _) | some (.neverSel _ _ _) | some .constNever => true
        | _ => false
      else false
    | none => false
  else false

/-- The library of the statements: the `IO.never` closures only (as track V's `supLib`). A
harness source is a closure reference, so user code cannot name a task, the dispatcher or a
future unless it holds it, and it holds none. -/
@[reducible] def dispLib : Lib := Lib.idFree isNeverClo

/-- The user programs are well-formed (decision 27), for every map order. -/
def AllWF (ho : List Val → List Val) (x : Inp) (u : UserEnv) : Prop :=
  ∀ p ∈ x.b :: x.c :: x.ws, WellFormed dispLib [] (env ho x u) p

/-- `ho` is a map order: a permutation of the entries. -/
def IsOrder (ho : List Val → List Val) : Prop := ∀ es, (ho es).Perm es

/-- The shared hypotheses: a map order, at least one worker, well-formed user programs, modes 0
or 1, submitters 0, 1 or `late`. -/
def Hyp (ho : List Val → List Val) (n : Nat) (x : Inp) (u : UserEnv) : Prop :=
  IsOrder ho ∧ 1 ≤ n ∧ AllWF ho x u ∧ (∀ m ∈ x.ms, m ≤ 1) ∧ (∀ p ∈ x.ps, p = 0 ∨ p = 1 ∨ p = late) ∧
    x.ms.length = x.ws.length ∧ x.ps.length = x.ws.length

/-- Pure tasks from submitters `ps` (all `unsafeToFutureCancelable` or as `ms`). -/
def pureInp (ps ms cn : List Nat) (c b : IO) : Inp :=
  { ws := List.replicate ps.length (.pure .unit), ps, ms, cn, c, b, sw := false }

/-- Tasks that sleep `ds` from the body (mode `ms`), body `b`, no cancel. -/
def sleepInp (ds ms : List Nat) (b : IO) : Inp :=
  { ws := ds.map Model.IO.sleep, ps := List.replicate ds.length 0, ms, cn := [], c := .pure .unit, b, sw := false }

/-- Tasks that sleep `ds` from the body (`unsafeToFutureCancelable`); the body waits until each
started, cancels it and waits for the cancel's future (statement 8). -/
def cancelInp (ds : List Nat) : Inp :=
  { ws := ds.map Model.IO.sleep, ps := List.replicate ds.length 0, ms := List.replicate ds.length 0, cn := [],
    c := .pure .unit, b := .pure .unit, sw := true }

/-! ## Statements (with a mirror variant `v`; `v = 0` is Cats Effect v3.7.1) -/

/-- Statement 1 (variant `v`): at most once. -/
def dispRunsOnceV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (par aw : Bool) (n : Nat) (wc : Val) (x : Inp),
    Hyp ho n x u →
    ∀ (fuel : Nat) (cs : List PChoice) (j : Nat),
      runs (run ho par aw n wc x u fuel cs v) j ≤ 1 ∧ fins (run ho par aw n wc x u fuel cs v) j ≤ 1

/-- Statement 2 (variant `v`): `await = true` runs every task submitted in the scope. -/
def dispAwaitDrainsV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (par : Bool) (n : Nat) (wc : Val) (ms : List Nat),
    Hyp ho n (pureInp (List.replicate ms.length 0) ms [] (.pure .unit) (.pure .unit)) u →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run ho par true n wc (pureInp (List.replicate ms.length 0) ms [] (.pure .unit) (.pure .unit)) u fuel cs v).halt
        = some (.done oc) →
      oc = .succeeded .unit ∧ ∀ j < ms.length,
        status (run ho par true n wc (pureInp (List.replicate ms.length 0) ms [] (.pure .unit) (.pure .unit)) u fuel cs v) j = 2

/-- Statement 3 (variant `v`): no lost submission (`await = true`, concurrent submitter). -/
def dispNoLostSubmissionV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (par : Bool) (n : Nat) (wc : Val) (ps ms : List Nat) (c : IO),
    Hyp ho n (pureInp ps ms [] c (.pure .unit)) u → (∀ p ∈ ps, p ≤ 1) →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run ho par true n wc (pureInp ps ms [] c (.pure .unit)) u fuel cs v).halt = some (.done oc) →
      ∀ j < ps.length,
        rejected (run ho par true n wc (pureInp ps ms [] c (.pure .unit)) u fuel cs v) j = 1 ∨
        status (run ho par true n wc (pureInp ps ms [] c (.pure .unit)) u fuel cs v) j = 2

/-- Statement 4 (variant `v`): a submission after the close throws and never runs. -/
def dispClosedRejectsV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (par aw : Bool) (n : Nat) (wc : Val) (x : Inp),
    Hyp ho n x u →
    ∀ (fuel : Nat) (cs : List PChoice) (j : Nat),
      (rejected (run ho par aw n wc x u fuel cs v) j = 1 → runs (run ho par aw n wc x u fuel cs v) j = 0) ∧
      ((run ho par aw n wc x u fuel cs v).halt = some (.done (.succeeded .unit)) →
        x.ps.getD j 0 = late → j < x.ws.length → rejected (run ho par aw n wc x u fuel cs v) j = 1)

/-- Statement 5 (variant `v`): `sequential` runs the body's tasks in order, one at a time. -/
def dispSeqFifoV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (aw : Bool) (wc : Val) (x : Inp),
    Hyp ho 1 x u → (∀ p ∈ x.ps, p = 0) → x.cn = [] →
    ∀ (fuel : Nat) (cs : List PChoice),
      Increasing (order (run ho false aw 1 wc x u fuel cs v)) ∧
      ((List.range x.ws.length).filter fun j => status (run ho false aw 1 wc x u fuel cs v) j == 1).length ≤ 1

/-- Statement 6 (variant `v`): `await = false` cancels the running tasks. -/
def dispCancelsV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (par : Bool) (n : Nat) (wc : Val) (ds ms : List Nat) (b : IO),
    (∀ d ∈ ds, 1 ≤ d) → (b = .pure .unit ∨ b = .cede) → Hyp ho n (sleepInp ds ms b) u →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run ho par false n wc (sleepInp ds ms b) u fuel cs v).halt = some (.done oc) →
      ∀ j, status (run ho par false n wc (sleepInp ds ms b) u fuel cs v) j ≠ 2

/-- Statement 7 (variant `v`): no deadlock (pure tasks from the body, any cancels). -/
def dispNoDeadlockV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (par aw : Bool) (n : Nat) (wc : Val) (ms cn : List Nat),
    Hyp ho n (pureInp (List.replicate ms.length 0) ms cn (.pure .unit) (.pure .unit)) u →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run ho par aw n wc (pureInp (List.replicate ms.length 0) ms cn (.pure .unit) (.pure .unit)) u fuel cs v).halt
        ≠ some .blocked

/-- Statement 8 (variant `v`): a cancel made after the task started cancels it. -/
def dispCancelStopsV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (aw : Bool) (n : Nat) (wc : Val) (ds : List Nat),
    (∀ d ∈ ds, 1 ≤ d) → Hyp ho n (cancelInp ds) u →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run ho true aw n wc (cancelInp ds) u fuel cs v).halt = some (.done oc) →
      ∀ j < ds.length, status (run ho true aw n wc (cancelInp ds) u fuel cs v) j = 3

def dispRunsOnce : Prop := dispRunsOnceV 0
def dispAwaitDrains : Prop := dispAwaitDrainsV 0
def dispNoLostSubmission : Prop := dispNoLostSubmissionV 0
def dispClosedRejects : Prop := dispClosedRejectsV 0
def dispSeqFifo : Prop := dispSeqFifoV 0
def dispCancels : Prop := dispCancelsV 0
def dispNoDeadlock : Prop := dispNoDeadlockV 0
def dispCancelStops : Prop := dispCancelStopsV 0

end CatsEffectInLean.Props.Phase7.Dispatcher

import CatsEffectInLean.Std.Supervisor
import CatsEffectInLean.Model.SchedP
import CatsEffectInLean.Model.WellFormed

/-!
# `std.Supervisor`: properties (Phase 7, track V)

Mirror: `Std/Supervisor.lean`. `SV` = `std/shared/src/main/scala/cats/effect/std/Supervisor.scala`
at `v3.7.1`.

## Promise

Scaladoc (`SV:28-36`, `:95-103`, `:109-127`):

> A fiber-based supervisor that monitors the lifecycle of all fibers that are started via its
> interface. The lifecycles of all these spawned fibers are bound to the lifecycle of the
> [[Supervisor]] itself. ... The fibers started via the supervisor are guaranteed to be terminated
> when the supervisor is terminated. When a supervisor is finalized, all active and queued fibers
> will be safely finalized before finalization of the supervisor is complete.
>
> `supervise`: Starts the supplied effect `fa` on the supervisor. Trying to start an effect with
> this method on an already finalized supervisor results in an error (inside `F`).
>
> `apply(await)`: Creates a `Resource` scope within which fibers can be monitored. When this
> scope exits, all supervised fibers will be finalized. ... `await` the termination policy:
> true - wait for the completion of the active fibers; false - cancel the active fibers.

Read in context: when `use` returns, no supervised fiber still runs (`await = false`: canceled;
`await = true`: joined after a `Succeeded` body; after an `Errored` or `Canceled` body the code
cancels, `SV:169-172`); a `supervise` after the close raises and never runs `fa`; `fa` runs once
(no restart without `checkRestart`); a finished child leaves the state (no unbounded growth,
`SV:316-319`); no deadlock. The restart path (`checkRestart = Some(_ => true)`, Dispatcher's
`always`, `std/.../Dispatcher.scala:254`) must also stop at the close.

## Test program (harness)

Inputs: `aw` (await), `r` (`checkRestart = Some(_ => true)` or `None`), `cv` (state kind: 0 =
`applyForAsync`, the one `IO` takes; 1 = `applyForConcurrent`), user programs `ws` (one per child),
parents `ps` (child `j` is supervised by the root body if `ps[j] = 0`, by child `i` after its user
code if `ps[j] = i + 1` with `i < j`; otherwise never), and a user program `b` of the body.

1. Allocate the harness cells: `Ref` 0 = status list, 1 = user-code starts, 2 = finalizer runs,
   3 = "supervise raised `IllegalStateException`" flags (all lists of `k` zeros), 4 = the
   supervisor value (for the state observation).
2. `Supervisor.use(s => body)`, then supervise the late children on the saved supervisor (the mirror `useIO`); `body` = save `s` in cell 4, supervise the
   children with parent 0 (each `supervise(child j).attempt`; an `IllegalStateException` sets
   flag `j`), then `b.attempt`, then `()`.
3. Child `j` = `IO.uncancelable(poll => enter(j) *> poll(ws[j].attempt).onCancel(fin(j)) *>
   mark(j, 2))` then supervise its own children. `enter` adds 1 to the starts and sets status 1;
   `fin` adds 1 to the finalizer runs and sets status 3.

The user programs get no handle (not the supervisor, not a harness cell, not a fiber); the
library of the statements is empty (`supLib`): user code builds its own programs only, so it can
not name a source code of the harness (a harness source is a closure reference). User programs
can raise, cancel themselves, wait forever, and start their own fibers. Schedules: every
`PChoice` list and fuel; the map order of `allFibers` is any permutation `ho`.

## Statements

1. `supNoLeak`: if the root is done, no child has status 1 (no child runs user code after the
   supervisor closed). Any `aw`, `r`, `cv`. Wrong functions: the finalizer drops its cancel/join
   (variant 7); the restart ignores `canceled` and `done` (variant 11).
2. `supClosedNoRun`: in every state, a child whose `supervise` raised `IllegalStateException`
   never started its user code; and when the root is done `Succeeded(())`, every late child
   (supervised after `use` returned) got `IllegalStateException`. Wrong function: `add` ignores
   the shutdown (variant 9).
3. `supRunsOnce`: without restart, in every state, each child started its user code at most
   once and its finalizer ran at most once. Wrong function: `supervise` doubles (variant 4).
4. `supAwaitJoins` (decision 63 companion): `aw = true`, no restart, flat (`ps` all 0), all user
   programs `IO.pure(())`: a done root is `Succeeded(())` and every child has status 2. Wrong
   functions: `supervise` raises or drops, the factory raises, `await = true` cancels.
5. `supNoDeadlock`: all user programs `IO.pure(())`, no restart, any `aw`, `cv`, `ps`: the run is
   never blocked. Wrong functions: `supervise` or the factory never returns.
6. `supRemoved`: without restart, in a blocked state, the supervisor map holds no fiber that
   has terminated. Wrong function: `remove` never removes (variant 10).

7. `supCancels`: `await = false`, children that sleep (`d ≥ 1`), pure body, no restart: when the
   root is done, no child finished its sleep. Wrong function: `await = false` joins (variant 8).

`supXV v` is statement X with mirror variant `v` (`supX = supXV 0`).
-/

namespace CatsEffectInLean.Props.Phase7.Supervisor

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.Supervisor (SLam Sup)

/-- The namespace of the harness closures (track V: 80..89). -/
def hns : Nat := 82

/-- The harness lambdas. `s` is the supervisor value. -/
inductive HLam where
  /-- The thunk that allocates `Ref` 0-3 (`k` zeros each) and `Ref` 4. -/
  | newCells (k : Nat)
  /-- `_ => Supervisor.use(body)`. -/
  | afterCells (aw r : Bool) (cv v : Nat)
  /-- The `use` function `s => body`. -/
  | body
  /-- `_ => supervise the children of the root, then b.attempt`. -/
  | bKids (s : Val)
  /-- `_ => b.attempt.void`. -/
  | bUser
  /-- `_ => ()`. -/
  | unitK
  /-- The thunk that saves `s` in cell 4. -/
  | saveSup (s : Val)
  /-- The source of child `j` of supervisor `s` (a closure reference: user code never holds it). -/
  | src (s : Val) (j : Nat)
  /-- `{ case Left(e) => ...; case Right(_) => ... }` after `supervise(child j).attempt`; `p` the
  parent (0 = root), then the next children from `j + 1`. -/
  | rej (s : Val) (p j : Nat)
  /-- `poll => enter(j) *> ...` of child `j`. -/
  | cBody (j : Nat)
  /-- `_ => poll(ws[j].attempt).onCancel(fin(j)) *> mark(j, 2)`. -/
  | cRun (j m pp : Nat)
  /-- `_ => mark(j, 2)`. -/
  | cDone (j : Nat)
  /-- `_ => supervise the children of child j`. -/
  | cKids (s : Val) (j : Nat)
  /-- Thunk: starts of `j` + 1, status 1. -/
  | enter (j : Nat)
  /-- Thunk: finalizer runs of `j` + 1, status 3. -/
  | fin (j : Nat)
  /-- Thunk: status of `j` := `x`. -/
  | mark (j x : Nat)
  /-- Thunk: flag of `j` := 1. -/
  | flag (j : Nat)
  /-- `_ => true` (`checkRestart = Some(_ => true)`). -/
  | always
  /-- `_ => the next children of parent p from j + 1`. -/
  | next (s : Val) (p j : Nat)
  /-- `_ => cell 4` (the supervisor value), after `use` returned. -/
  | getSup
  /-- `s => supervise the late children (parent `late`)`. -/
  | lateK
  /-- The thunk that reads cell 4. -/
  | readSup
  deriving DecidableEq, Repr

def HLam.toVal : HLam → Val
  | .newCells k => cloVal hns 0 [.nat k]
  | .afterCells aw r cv v => cloVal hns 1 [.bool aw, .bool r, .nat cv, .nat v]
  | .body => cloVal hns 2 []
  | .bKids s => cloVal hns 3 [s]
  | .bUser => cloVal hns 4 []
  | .unitK => cloVal hns 5 []
  | .saveSup s => cloVal hns 6 [s]
  | .src s j => cloVal hns 7 [s, .nat j]
  | .rej s p j => cloVal hns 8 [s, .nat p, .nat j]
  | .cBody j => cloVal hns 9 [.nat j]
  | .cRun j m pp => cloVal hns 10 [.nat j, .poll m pp]
  | .cDone j => cloVal hns 11 [.nat j]
  | .cKids s j => cloVal hns 12 [s, .nat j]
  | .enter j => cloVal hns 13 [.nat j]
  | .fin j => cloVal hns 14 [.nat j]
  | .mark j x => cloVal hns 15 [.nat j, .nat x]
  | .flag j => cloVal hns 16 [.nat j]
  | .always => cloVal hns 17 []
  | .next s p j => cloVal hns 18 [s, .nat p, .nat j]
  | .getSup => cloVal hns 19 []
  | .lateK => cloVal hns 20 []
  | .readSup => cloVal hns 21 []

def HLam.ofFields : Nat → List Val → Option HLam
  | 0, [.nat k] => some (.newCells k)
  | 1, [.bool aw, .bool r, .nat cv, .nat v] => some (.afterCells aw r cv v)
  | 2, [] => some .body
  | 3, [s] => some (.bKids s)
  | 4, [] => some .bUser
  | 5, [] => some .unitK
  | 6, [s] => some (.saveSup s)
  | 7, [s, .nat j] => some (.src s j)
  | 8, [s, .nat p, .nat j] => some (.rej s p j)
  | 9, [.nat j] => some (.cBody j)
  | 10, [.nat j, .poll m pp] => some (.cRun j m pp)
  | 11, [.nat j] => some (.cDone j)
  | 12, [s, .nat j] => some (.cKids s j)
  | 13, [.nat j] => some (.enter j)
  | 14, [.nat j] => some (.fin j)
  | 15, [.nat j, .nat x] => some (.mark j x)
  | 16, [.nat j] => some (.flag j)
  | 17, [] => some .always
  | 18, [s, .nat p, .nat j] => some (.next s p j)
  | 19, [] => some .getSup
  | 20, [] => some .lateK
  | 21, [] => some .readSup
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
def setIn (refs : List Val) (c j x : Nat) : UserEffect :=
  .writeRef c (listV ((lst (refs.getD c .unit)).set j (.nat x)))

/-- The parent number of a late child: supervised by the root after `use` returned. -/
def late : Nat := 1000000

/-- Child `j`: `IO.uncancelable(cBody j)`, then its own children. -/
def childIO (s : Val) (j : Nat) : IO := .flatMap (.uncancelable (HLam.cBody j).fn) (HLam.cKids s j).fn

/-- `supervise(child j)` on `s` (the mirror), with source `src s j`. -/
def superviseOf (s : Val) (j : Nat) : IO :=
  match CatsEffectInLean.Std.Supervisor.supOf? s with
  | some sp => CatsEffectInLean.Std.Supervisor.superviseIO sp (.fn (HLam.src s j).id)
  | none => .error CatsEffectInLean.Std.Supervisor.illErr

/-- Supervise the children `j' ≥ j` whose parent is `p` (`ps[j'] = p`; a child parent must be
an earlier child), each `supervise(child).attempt`, then `()`. -/
def kidsIO (ps : List Nat) (s : Val) (p : Nat) : (fuel j : Nat) → IO
  | 0, _ => .pure .unit
  | fuel + 1, j =>
    if j < ps.length then
      if ps.getD j 0 == p && (p == 0 || p == late || p ≤ j) then
        .flatMap (.attempt (superviseOf s j)) (HLam.rej s p j).fn
      else kidsIO ps s p fuel (j + 1)
    else .pure .unit

/-- The children of parent `p` from index `j`. -/
def kidsFrom (ps : List Nat) (s : Val) (p j : Nat) : IO := kidsIO ps s p ps.length j

/-- Run a harness closure. -/
def HLam.call (ws : List IO) (ps : List Nat) (b : IO) (h : HLam) (arg : Val) (w : View) : UserResult :=
  let bad : UserResult := { out := .throw CatsEffectInLean.Std.Supervisor.illErr }
  match h, arg with
  | .newCells k', _ =>
    let z := listV (List.replicate k' (.nat 0))
    { effects := [.allocRef z, .allocRef z, .allocRef z, .allocRef z, .allocRef .unit], out := .ret .unit }
  | .afterCells aw r cv v, _ =>
    let rs : Val := if r then .some (.fn HLam.always.id) else .none
    { out := .prog (.flatMap (.flatMap (CatsEffectInLean.Std.Supervisor.useIO aw rs cv v HLam.body.id)
        HLam.getSup.fn) HLam.lateK.fn) }
  | .getSup, _ => { out := .prog (.delay HLam.readSup.fn) }
  | .readSup, _ => { out := .ret (w.refs.getD 4 .unit) }
  | .lateK, s => { out := .prog (kidsFrom ps s late 0) }
  | .body, s => { out := .prog (.flatMap (.delay (HLam.saveSup s).fn) (HLam.bKids s).fn) }
  | .bKids s, _ => { out := .prog (.flatMap (kidsFrom ps s 0 0) HLam.bUser.fn) }
  | .bUser, _ => { out := .prog (.map (.attempt b) HLam.unitK.fn) }
  | .unitK, _ => { out := .ret .unit }
  | .saveSup s, _ => { effects := [.writeRef 4 s], out := .ret .unit }
  | .src _ _, _ => bad
  | .rej s p j, x =>
    match x with
    | .left (.err e) =>
      if e == CatsEffectInLean.Std.Supervisor.iseErr then
        { out := .prog (.flatMap (.delay (HLam.flag j).fn) (HLam.next s p j).fn) }
      else { out := .prog (kidsFrom ps s p (j + 1)) }
    | _ => { out := .prog (kidsFrom ps s p (j + 1)) }
  | .next s p j, _ => { out := .prog (kidsFrom ps s p (j + 1)) }
  | .cBody j, .poll m pp => { out := .prog (.flatMap (.delay (HLam.enter j).fn) (HLam.cRun j m pp).fn) }
  | .cRun j m pp, _ =>
    { out := .prog (.flatMap (.onCancel (IO.applyPoll (.attempt (ws.getD j (.pure .unit))) m pp)
        (.delay (HLam.fin j).fn)) (HLam.cDone j).fn) }
  | .cDone j, _ => { out := .prog (.delay (HLam.mark j 2).fn) }
  | .cKids s j, _ => { out := .prog (kidsFrom ps s (j + 1) 0) }
  | .enter j, _ =>
    { effects := [setIn w.refs 1 j (natIn w.refs 1 j + 1), setIn w.refs 0 j 1], out := .ret .unit }
  | .fin j, _ =>
    { effects := [setIn w.refs 2 j (natIn w.refs 2 j + 1), setIn w.refs 0 j 3], out := .ret .unit }
  | .mark j x, _ => { effects := [setIn w.refs 0 j x], out := .ret .unit }
  | .flag j, _ => { effects := [setIn w.refs 3 j 1], out := .ret .unit }
  | .always, _ => { out := .ret (.bool true) }
  | _, _ => bad

/-- The test program (`v = 0`: Cats Effect v3.7.1). -/
def prog (aw r : Bool) (cv : Nat) (k : Nat) (v : Nat := 0) : IO :=
  .flatMap (.delay (HLam.newCells k).fn) (HLam.afterCells aw r cv v).fn

/-! ## Environment and run -/

/-- The external sources of the mirror: a harness source `src s j` is child `j`; nothing else
names a program. -/
def ioOf : Val → IO
  | .fn id =>
    match HLam.ofId? id with
    | some (.src s j) => childIO s j
    | _ => .error CatsEffectInLean.Std.Supervisor.illErr
  | _ => .error CatsEffectInLean.Std.Supervisor.illErr

/-- Harness closures, then user code `u`. -/
def harnessed (ws : List IO) (ps : List Nat) (b : IO) (u : UserEnv) : UserEnv where
  call id arg refs := match HLam.ofId? id with
    | some h => h.call ws ps b arg { refs }
    | none => u.call id arg refs
  callV id arg w := match HLam.ofId? id with
    | some h => h.call ws ps b arg w
    | none => u.callV id arg w

/-- The user environment of the statements: the mirror (with `Bracket`, `Race`, `Timeout`), the
harness, user code `u`; map order `ho`. -/
def env (ho : List Val → List Val) (ws : List IO) (ps : List Nat) (b : IO) (u : UserEnv) : UserEnv :=
  CatsEffectInLean.Std.Supervisor.env ho ioOf (harnessed ws ps b u)

/-- The final state: `fuel` micro-steps of the preemptive scheduler with choices `cs`. -/
def run (ho : List Val → List Val) (aw r : Bool) (cv : Nat) (ws : List IO) (ps : List Nat) (b : IO)
    (u : UserEnv) (fuel : Nat) (cs : List PChoice) (v : Nat := 0) : Sched CounterMask :=
  runSchedStateP {} counterMaskModel (env ho ws ps b u) fuel cs
    (Sched.init counterMaskModel (prog aw r cv ws.length v))

/-! ## Observations (harness cells, and the supervisor state for `supRemoved`) -/

/-- The status of child `j` (`Ref` 0). -/
def status {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 0 j
/-- The user-code starts of child `j` (`Ref` 1). -/
def runs {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 1 j
/-- The finalizer runs of child `j` (`Ref` 2). -/
def fins {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 2 j
/-- Did `supervise(child j)` raise `IllegalStateException` (`Ref` 3)? -/
def rejected {M : Type} (s : Sched M) (j : Nat) : Nat := natIn s.liveHeap.refs 3 j

/-- The fibers in the supervisor map (empty if no supervisor yet, or `null`). -/
def mapFibers {M : Type} (s : Sched M) : List Val :=
  match CatsEffectInLean.Std.Supervisor.supOf? (s.liveHeap.refs.getD 4 .unit) with
  | some sp =>
    match CatsEffectInLean.Std.Supervisor.mapOf? (s.liveHeap.refs.getD sp.m .unit) with
    | some (_, es) => es.map CatsEffectInLean.Std.Supervisor.entryFiber
    | none => []
  | none => []

/-- Has fiber value `x` terminated? -/
def terminated {M : Type} (s : Sched M) (x : Val) : Bool :=
  match x with
  | .fiber t => ((s.liveFibers.map (·.outcome))[t]?).any Option.isSome
  | _ => false

/-- The library of the statements: empty. User programs build their own programs only (they
cannot name a mirror closure; a mirror closure that resolves a source would let user code run a
harness child). -/
@[reducible] def supLib : Lib := Lib.idFree (fun _ => false)

/-- The user programs are well-formed (decision 27), for every map order. -/
def AllWF (ho : List Val → List Val) (ws : List IO) (ps : List Nat) (b : IO) (u : UserEnv) : Prop :=
  ∀ p ∈ b :: ws, WellFormed supLib [] (env ho ws ps b u) p

/-- `ho` is a map order: a permutation of the entries. -/
def IsOrder (ho : List Val → List Val) : Prop := ∀ es, (ho es).Perm es

/-! ## Statements (with a mirror variant `v`; `v = 0` is Cats Effect v3.7.1) -/

/-- Statement 1 (variant `v`). -/
def supNoLeakV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (aw r : Bool) (cv : Nat) (ws : List IO) (ps : List Nat)
    (b : IO), IsOrder ho → cv ≤ 1 → AllWF ho ws ps b u →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run ho aw r cv ws ps b u fuel cs v).halt = some (.done oc) →
      ∀ j, status (run ho aw r cv ws ps b u fuel cs v) j ≠ 1

/-- Statement 2 (variant `v`). -/
def supClosedNoRunV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (aw r : Bool) (cv : Nat) (ws : List IO) (ps : List Nat)
    (b : IO), IsOrder ho → cv ≤ 1 → AllWF ho ws ps b u →
    ∀ (fuel : Nat) (cs : List PChoice) (j : Nat),
      (rejected (run ho aw r cv ws ps b u fuel cs v) j = 1 →
        runs (run ho aw r cv ws ps b u fuel cs v) j = 0) ∧
      ((run ho aw r cv ws ps b u fuel cs v).halt = some (.done (.succeeded .unit)) →
        ps.getD j 0 = late → j < ws.length →
        rejected (run ho aw r cv ws ps b u fuel cs v) j = 1)

/-- Statement 3 (variant `v`). -/
def supRunsOnceV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (aw : Bool) (cv : Nat) (ws : List IO) (ps : List Nat)
    (b : IO), IsOrder ho → cv ≤ 1 → AllWF ho ws ps b u →
    ∀ (fuel : Nat) (cs : List PChoice) (j : Nat),
      runs (run ho aw false cv ws ps b u fuel cs v) j ≤ 1 ∧
      fins (run ho aw false cv ws ps b u fuel cs v) j ≤ 1

/-- Statement 4 (variant `v`). -/
def supAwaitJoinsV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (cv k : Nat),
    IsOrder ho → cv ≤ 1 →
    AllWF ho (List.replicate k (.pure .unit)) (List.replicate k 0) (.pure .unit) u →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run ho true false cv (List.replicate k (.pure .unit)) (List.replicate k 0) (.pure .unit) u fuel cs v).halt
        = some (.done oc) →
      oc = .succeeded .unit ∧
      ∀ j < k, status (run ho true false cv (List.replicate k (.pure .unit)) (List.replicate k 0) (.pure .unit)
        u fuel cs v) j = 2

/-- Statement 5 (variant `v`). -/
def supNoDeadlockV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (aw : Bool) (cv k : Nat) (ps : List Nat),
    IsOrder ho → cv ≤ 1 →
    AllWF ho (List.replicate k (.pure .unit)) ps (.pure .unit) u →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run ho aw false cv (List.replicate k (.pure .unit)) ps (.pure .unit) u fuel cs v).halt ≠ some .blocked

/-- Statement 6 (variant `v`). -/
def supRemovedV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (aw : Bool) (cv : Nat) (ws : List IO) (ps : List Nat)
    (b : IO), IsOrder ho → cv ≤ 1 → AllWF ho ws ps b u →
    ∀ (fuel : Nat) (cs : List PChoice),
      (run ho aw false cv ws ps b u fuel cs v).halt = some .blocked →
      ∀ x ∈ mapFibers (run ho aw false cv ws ps b u fuel cs v),
        terminated (run ho aw false cv ws ps b u fuel cs v) x = false

/-- Statement 7 (variant `v`): `await = false` cancels. Children whose user program is a
`sleep(d)` with `d ≥ 1`, a pure body, no restart: when the root is done, no child finished its
sleep (status 2): the close canceled each child that was still sleeping. -/
def supCancelsV (v : Nat) : Prop :=
  ∀ (u : UserEnv) (ho : List Val → List Val) (cv : Nat) (ds : List Nat) (ps : List Nat),
    IsOrder ho → cv ≤ 1 → (∀ d ∈ ds, 1 ≤ d) →
    AllWF ho (ds.map Model.IO.sleep) ps (.pure .unit) u →
    ∀ (fuel : Nat) (cs : List PChoice) (oc : Outcome),
      (run ho false false cv (ds.map Model.IO.sleep) ps (.pure .unit) u fuel cs v).halt = some (.done oc) →
      ∀ j, status (run ho false false cv (ds.map Model.IO.sleep) ps (.pure .unit) u fuel cs v) j ≠ 2

def supNoLeak : Prop := supNoLeakV 0
def supClosedNoRun : Prop := supClosedNoRunV 0
def supRunsOnce : Prop := supRunsOnceV 0
def supAwaitJoins : Prop := supAwaitJoinsV 0
def supNoDeadlock : Prop := supNoDeadlockV 0
def supRemoved : Prop := supRemovedV 0
def supCancels : Prop := supCancelsV 0

end CatsEffectInLean.Props.Phase7.Supervisor

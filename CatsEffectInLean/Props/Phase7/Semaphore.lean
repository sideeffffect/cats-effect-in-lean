import CatsEffectInLean.Model.Mutex
import CatsEffectInLean.Model.WellFormed
import CatsEffectInLean.Model.Outcomes

/-!
# `Semaphore` and `Mutex`: permits, exclusion, FIFO, liveness, twin (Phase 7, track S)

Models: `CatsEffectInLean/Model/Semaphore.lean` (`std/shared/src/main/scala/cats/effect/std/Semaphore.scala`,
`S` below) and `CatsEffectInLean/Model/Mutex.lean` (`std/.../Mutex.scala`, `std/.../LockQueue.scala`), at
v3.7.1. Promises:

* `S:28-35`: "A semaphore has a non-negative number of permits available. Acquiring a permit
  decrements the current number of permits and releasing a permit increases the current number of
  permits. An acquire that occurs when there are no permits available results in fiber blocking
  until a permit becomes available."
* `S:38-53`: `available` "Returns the number of permits currently available. Always non-negative";
  `count` "Like [[available]] when permits are available but returns the number of permits callers
  are waiting for when there are no permits available."
* `S:56-67` (`acquireN`): "acquires are statisfied in strict FIFO order ... This method is
  interruptible, and in case of interruption it will take care of restoring any permits it has
  acquired."
* `S:105-109` (`permit`): "acquires a permit, holds it for the lifetime of the resource, then
  releases the permit."
* `Mutex.scala:24-28`: "A mutex is a concurrency primitive that can be used to give access to a
  resource to only one fiber at a time"; `docs/std/mutex.md:6-7`: "Basically, it's a `Semaphore`
  with a single available permit."

## The harness (namespace 62)

Each statement runs one test program (`lockRoot`). The root first allocates the counter cell
(`Ref` 0, the harness token: no later cell gets id 0, and user code never receives it), then makes
the lock (`Semaphore[IO](k)` or `Mutex[IO]`), starts one fiber per `Use`, and then runs the `Act`s
of the parent in order: `cancel i` / `join i` of fiber `i`, `release n` (`s.releaseN(n)`), `cede`.
At the end a semaphore root returns `(available, count)` and a mutex root runs `lock.use(_ =>
IO.unit)` once more (the lock must be free) and returns `()`.

A `Use` is what one fiber does with the lock (Scala code that a user writes):

* `permit g`: `s.permit.use(g)` / `m.lock.use(g)`; `g` is a user function (`Val.fn g`).
* `acqRel n`: `IO.uncancelable(poll => poll(s.acquireN(n)) *> s.releaseN(n))` (semaphore only).
* `tryRel n`: `IO.uncancelable(_ => s.tryAcquireN(n).flatMap(b => if (b) s.releaseN(n) else IO.unit))`.
* `counted g`: `permit` with the use function `_ => IO.uncancelable(poll => enter *>
  poll(IO.unit.flatMap(g)).attempt.onCancel(exit).flatMap(x => exit *> x.liftTo[IO]))`: `enter` and
  `exit` count the fibers inside the permit in the counter cell `(running, highest)`. The masked
  region makes `enter`/`exit` exact under cancelation (as `parTraverseNAtMostN`).

The lock objects, the counter cell and every closure that holds them are outside the public
library (`semLib`), so `WellFormed` (decision 58, `WF.avail`) keeps user code from naming them and
from writing the lock state or the counter (Scala: the state `Ref` is private; the harness never
passes the lock or the counter to user code). User code may make and use its own semaphores and
mutexes (the public operations `SL.op*`, `ML.op*`) and the `Bracket` combinators.

After `join i` the parent writes the join outcome into the trace (`joinRecV i oc`, harness tag 62).
Only statements 2 and 5 read it; they have no user code, so nothing else can emit such a record.

Behaviour tables (statements 2, 5, 6): `BUse.permit k b` is `permit` with `g = _ => IO.cede`
`k` times, then the base action `b` (`pure`, `raiseError`, `canceled`). This is Scala code that
holds no handle, so these statements need no `WellFormed` hypothesis.

All statements quantify over all fuel values and all `PChoice` schedules (`outcomesP`: preemption
at any run-loop iteration).
-/

namespace CatsEffectInLean.Props.Phase7.Semaphore

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Semaphore
open CatsEffectInLean.Model.Mutex

/-- The harness namespace (track S: 60..69). -/
def hns : Nat := 62

/-- The lock of a root. -/
inductive Lock where
  /-- `Semaphore[IO](k)`. -/
  | sem (k : Nat)
  /-- `Mutex[IO]`. -/
  | mutex
  /-- `Semaphore[IO](1)` used as a mutex: only `permit.use`, and the root ends as a mutex root
  (`permit.use(_ => IO.unit)`, result `()`). The twin of `mutex` (statement 8). -/
  | semMutex
  deriving DecidableEq, Repr

def Lock.toVal : Lock → Val
  | .sem k => .some (.nat k)
  | .mutex => .none
  | .semMutex => .unit

def Lock.ofVal : Val → Option Lock
  | .some (.nat k) => some (.sem k)
  | .none => some .mutex
  | .unit => some .semMutex
  | _ => none

/-- What one fiber does with the lock. -/
inductive Use where
  | permit (g : Nat)
  | acqRel (n : Nat)
  | tryRel (n : Nat)
  | counted (g : Nat)
  deriving DecidableEq, Repr

def Use.toVal : Use → Val
  | .permit g => .pair (.nat 0) (.fn g)
  | .acqRel n => .pair (.nat 1) (.nat n)
  | .tryRel n => .pair (.nat 2) (.nat n)
  | .counted g => .pair (.nat 3) (.fn g)

def Use.ofVal : Val → Option Use
  | .pair (.nat 0) (.fn g) => some (.permit g)
  | .pair (.nat 1) (.nat n) => some (.acqRel n)
  | .pair (.nat 2) (.nat n) => some (.tryRel n)
  | .pair (.nat 3) (.fn g) => some (.counted g)
  | _ => none

/-- One step of the parent. -/
inductive Act where
  | cancel (i : Nat)
  | join (i : Nat)
  | release (n : Nat)
  | cede
  deriving DecidableEq, Repr

def Act.toVal : Act → Val
  | .cancel i => .pair (.nat 0) (.nat i)
  | .join i => .pair (.nat 1) (.nat i)
  | .release n => .pair (.nat 2) (.nat n)
  | .cede => .pair (.nat 3) .unit

def Act.ofVal : Val → Option Act
  | .pair (.nat 0) (.nat i) => some (.cancel i)
  | .pair (.nat 1) (.nat i) => some (.join i)
  | .pair (.nat 2) (.nat n) => some (.release n)
  | .pair (.nat 3) .unit => some .cede
  | _ => none

def usesV (us : List Use) : Val := listV (us.map Use.toVal)
def actsV (as : List Act) : Val := listV (as.map Act.toVal)
def usesOf (v : Val) : List Use := ((unlistV v).getD []).filterMap Use.ofVal
def actsOf (v : Val) : List Act := ((unlistV v).getD []).filterMap Act.ofVal

/-- The harness closures (test harness, not Cats Effect code). `c` is the counter cell, `l` the
lock object (a closure id held as `Val.fn l`), `fs` the started fibers (a list of `Val.fiber`). -/
inductive HS where
  /-- The thunk `Ref.unsafe((0, 0))`: the counter cell (the token). Public. -/
  | newCell
  /-- `cell => lock.flatMap(l => ...)`. Public (holds no handle). -/
  | afterCell (lk : Val) (us as : Val)
  /-- `l => start the fibers, then the acts`. -/
  | withLock (c : Nat) (lk : Val) (us as : Val)
  /-- `fiber => start the next fiber, or run the acts`; `fs` the fibers started so far. -/
  | started (c : Nat) (lk : Val) (l : Nat) (rest as fs : Val)
  /-- `_ => the rest of the acts`. -/
  | next (c : Nat) (lk : Val) (l : Nat) (as fs : Val)
  /-- `poll => poll(s.acquireN(n)) *> s.releaseN(n)` of `acqRel`. -/
  | acqRelBody (l n : Nat)
  /-- `_ => s.releaseN(n)` (`*>`). -/
  | constRel (l n : Nat)
  /-- `_ => s.tryAcquireN(n).flatMap(...)` of `tryRel`. -/
  | tryBody (l n : Nat)
  /-- `b => if (b) s.releaseN(n) else IO.unit`. -/
  | ifRel (l n : Nat)
  /-- `available => count.map(c => (available, c))`. -/
  | thenCount (l : Nat)
  /-- `c => (a, c)`. -/
  | pairWith (a : Val)
  /-- `_ => IO.unit` (the last `lock.use` of a mutex root). -/
  | unitUse
  /-- The counted use function `a => IO.uncancelable(...)`. -/
  | cbody (c g : Nat)
  /-- `poll => enter *> ...`. -/
  | cunc (c : Nat) (a : Val) (g : Nat)
  /-- The thunk `enter`: `(r, h) => (r + 1, max(h, r + 1))`. -/
  | enter (c : Nat)
  /-- `_ => poll(IO.unit.flatMap(g)).attempt.onCancel(exit).flatMap(fin)`. -/
  | run (c : Nat) (a : Val) (g m s : Nat)
  /-- The thunk `exit`: `(r, h) => (r - 1, h)`. -/
  | exit (c : Nat)
  /-- `x => exit *> rethrow(x)`. -/
  | fin (c : Nat)
  /-- `_ => x.liftTo[IO]`. -/
  | rethrow (x : Val)
  /-- `oc => record(i, oc) *> the rest of the acts`: after `join i`, the harness records the join
  outcome in the trace (`joinRec i oc`), then goes on (review batch 11b, W1). -/
  | joinRec (c : Nat) (lk : Val) (l i : Nat) (as fs : Val)
  deriving DecidableEq, Repr

def HS.toVal : HS → Val
  | .newCell => cloVal hns 0 []
  | .afterCell lk us as => cloVal hns 1 [lk, us, as]
  | .withLock c lk us as => cloVal hns 2 [.ref c, lk, us, as]
  | .started c lk l rest as fs => cloVal hns 3 [.ref c, lk, .fn l, rest, as, fs]
  | .next c lk l as fs => cloVal hns 4 [.ref c, lk, .fn l, as, fs]
  | .acqRelBody l n => cloVal hns 5 [.fn l, .nat n]
  | .constRel l n => cloVal hns 6 [.fn l, .nat n]
  | .tryBody l n => cloVal hns 7 [.fn l, .nat n]
  | .ifRel l n => cloVal hns 8 [.fn l, .nat n]
  | .thenCount l => cloVal hns 9 [.fn l]
  | .pairWith a => cloVal hns 10 [a]
  | .unitUse => cloVal hns 11 []
  | .cbody c g => cloVal hns 12 [.ref c, .fn g]
  | .cunc c a g => cloVal hns 13 [.ref c, a, .fn g]
  | .enter c => cloVal hns 14 [.ref c]
  | .run c a g m s => cloVal hns 15 [.ref c, a, .fn g, .poll m s]
  | .exit c => cloVal hns 16 [.ref c]
  | .fin c => cloVal hns 17 [.ref c]
  | .rethrow x => cloVal hns 18 [x]
  | .joinRec c lk l i as fs => cloVal hns 19 [.ref c, lk, .fn l, .nat i, as, fs]

def HS.ofFields : Nat → List Val → Option HS
  | 0, [] => some .newCell
  | 1, [lk, us, as] => some (.afterCell lk us as)
  | 2, [.ref c, lk, us, as] => some (.withLock c lk us as)
  | 3, [.ref c, lk, .fn l, rest, as, fs] => some (.started c lk l rest as fs)
  | 4, [.ref c, lk, .fn l, as, fs] => some (.next c lk l as fs)
  | 5, [.fn l, .nat n] => some (.acqRelBody l n)
  | 6, [.fn l, .nat n] => some (.constRel l n)
  | 7, [.fn l, .nat n] => some (.tryBody l n)
  | 8, [.fn l, .nat n] => some (.ifRel l n)
  | 9, [.fn l] => some (.thenCount l)
  | 10, [a] => some (.pairWith a)
  | 11, [] => some .unitUse
  | 12, [.ref c, .fn g] => some (.cbody c g)
  | 13, [.ref c, a, .fn g] => some (.cunc c a g)
  | 14, [.ref c] => some (.enter c)
  | 15, [.ref c, a, .fn g, .poll m s] => some (.run c a g m s)
  | 16, [.ref c] => some (.exit c)
  | 17, [.ref c] => some (.fin c)
  | 18, [x] => some (.rethrow x)
  | 19, [.ref c, lk, .fn l, .nat i, as, fs] => some (.joinRec c lk l i as fs)
  | _, _ => none

def HS.id (l : HS) : Nat := 2 * valToNat l.toVal + 1
def HS.fn (l : HS) : Fn := .user l.id

def HS.ofId? (id : Nat) : Option HS :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == hns then HS.ofFields tag fs else none
    | none => none
  else none

/-- The counter cell `(running, highest)`. -/
def cntOf (v : View) (c : Nat) : Nat × Nat :=
  match v.refs[c]? with
  | some (.pair (.nat r) (.nat h)) => (r, h)
  | _ => (0, 0)

/-- The `IO` of one use (`Use`) of lock `l` (`lk` says which kind). -/
def useIO (lk : Lock) (c l : Nat) : Use → IO
  | .permit g => match lk with
    | .sem _ | .semMutex => permitUseIO l g
    | .mutex => lockUseIO l g
  | .counted g => match lk with
    | .sem _ | .semMutex => permitUseIO l (HS.cbody c g).id
    | .mutex => lockUseIO l (HS.cbody c g).id
  | .acqRel n => .uncancelable (HS.acqRelBody l n).fn
  | .tryRel n => .uncancelable (HS.tryBody l n).fn

/-- The fiber of index `i` (`fs` holds the started fibers in order). -/
def fiberAt (fs : Val) (i : Nat) : Option Nat :=
  match ((unlistV fs).getD [])[i]? with
  | some (.fiber t) => some t
  | _ => none

/-- The trace record of `join i` with outcome `oc` (harness tag 62). -/
def joinRecV (i : Nat) (oc : Val) : Val := .pair (.nat 62) (.pair (.nat i) oc)

/-- The rest of the parent after the fibers started, in view `v`. -/
def actsIO (c : Nat) (lk : Lock) (l : Nat) (fs : Val) (v : View) : List Act → IO
  | [] => match lk with
    | .sem _ => .flatMap (availableIO l) (HS.thenCount l).fn
    | .mutex => lockUseIO l HS.unitUse.id
    | .semMutex => permitUseIO l HS.unitUse.id
  | a :: rest =>
    let k := (HS.next c lk.toVal l (actsV rest) fs).fn
    match a with
    | .cancel i => match fiberAt fs i with
      | some t => .flatMap (IO.cancelOf t (v.outcome t)) k
      | none => .flatMap (.pure .unit) k
    | .join i => match fiberAt fs i with
      | some t => .flatMap (IO.joinOf t (v.outcome t)) (HS.joinRec c lk.toVal l i (actsV rest) fs).fn
      | none => .flatMap (.pure .unit) k
    | .release n => match lk with
      | .sem _ | .semMutex => .flatMap (releaseNIO l n) k
      | .mutex => .flatMap (.pure .unit) k
    | .cede => .flatMap .cede k

private def illT : UserResult := { out := .throw { code := illCode, kind := .fatal } }

/-- Run harness closure `l`. -/
def HS.call (h : HS) (arg : Val) (v : View) : UserResult :=
  match h with
  | .newCell => { effects := [.allocRef (.pair (.nat 0) (.nat 0))], out := .ret (.ref v.refs.length) }
  | .afterCell lk us as =>
    match arg, Lock.ofVal lk with
    | .ref c, some (.sem k) => { out := .prog (.flatMap (Semaphore.newIO k) (HS.withLock c lk us as).fn) }
    | .ref c, some .mutex => { out := .prog (.flatMap Mutex.newIO (HS.withLock c lk us as).fn) }
    | .ref c, some .semMutex => { out := .prog (.flatMap (Semaphore.newIO 1) (HS.withLock c lk us as).fn) }
    | _, _ => illT
  | .withLock c lk us as =>
    match arg, Lock.ofVal lk with
    | .fn l, some lock =>
      match usesOf us with
      | [] => { out := .prog (actsIO c lock l (listV []) v (actsOf as)) }
      | u0 :: rest =>
        { out := .prog (.flatMap (.start (useIO lock c l u0)) (HS.started c lk l (usesV rest) as (listV [])).fn) }
    | _, _ => illT
  | .started c lk l rest as fs =>
    match Lock.ofVal lk with
    | some lock =>
      let fs' := listV (((unlistV fs).getD []) ++ [arg])
      match usesOf rest with
      | [] => { out := .prog (actsIO c lock l fs' v (actsOf as)) }
      | u0 :: rest' =>
        { out := .prog (.flatMap (.start (useIO lock c l u0)) (HS.started c lk l (usesV rest') as fs').fn) }
    | none => illT
  | .next c lk l as fs =>
    match Lock.ofVal lk with
    | some lock => { out := .prog (actsIO c lock l fs v (actsOf as)) }
    | none => illT
  | .acqRelBody l n =>
    match arg with
    | .poll m s => { out := .prog (.flatMap (IO.applyPoll (acquireNIO l n) m s) (HS.constRel l n).fn) }
    | _ => illT
  | .constRel l n => { out := .prog (releaseNIO l n) }
  | .tryBody l n => { out := .prog (.flatMap (tryAcquireNIO l n) (HS.ifRel l n).fn) }
  | .ifRel l n =>
    match arg with
    | .bool true => { out := .prog (releaseNIO l n) }
    | .bool false => { out := .prog (.pure .unit) }
    | _ => illT
  | .thenCount l => { out := .prog (.map (countIO l) (HS.pairWith arg).fn) }
  | .pairWith a => { out := .ret (.pair a arg) }
  | .unitUse => { out := .prog (.pure .unit) }
  | .cbody c g => { out := .prog (.uncancelable (HS.cunc c arg g).fn) }
  | .cunc c a g =>
    match arg with
    | .poll m s => { out := .prog (.flatMap (.delay (HS.enter c).fn) (HS.run c a g m s).fn) }
    | _ => illT
  | .enter c =>
    let (r, hi) := cntOf v c
    { effects := [.writeRef c (.pair (.nat (r + 1)) (.nat (max hi (r + 1))))], out := .ret .unit }
  | .run c a g m s =>
    { out := .prog (.flatMap (.onCancel (.attempt (IO.applyPoll (.flatMap (.pure a) (.user g)) m s))
        (.delay (HS.exit c).fn)) (HS.fin c).fn) }
  | .exit c =>
    let (r, hi) := cntOf v c
    { effects := [.writeRef c (.pair (.nat (r - 1)) (.nat hi))], out := .ret .unit }
  | .fin c => { out := .prog (.flatMap (.delay (HS.exit c).fn) (HS.rethrow arg).fn) }
  | .joinRec c lk l i as fs =>
    match Lock.ofVal lk with
    | some lock => { effects := [.emit (joinRecV i arg)], out := .prog (actsIO c lock l fs v (actsOf as)) }
    | none => illT
  | .rethrow x =>
    match x with
    | .left (.err e) => { out := .prog (.error e) }
    | .right b => { out := .prog (.pure b) }
    | _ => illT

/-- User code `u` with the harness closures, the `Semaphore`/`Mutex` mirrors and `Bracket`. -/
def harnessed (u : UserEnv) : UserEnv where
  call id a refs := match HS.ofId? id with
    | some h => h.call a { refs }
    | none => u.call id a refs
  callV id a v := match HS.ofId? id with
    | some h => h.call a v
    | none => u.callV id a v

/-- The environment of the statements. -/
def env (u : UserEnv) : UserEnv := Mutex.env (harnessed u)

/-- The root: allocate the counter cell, make the lock, start the uses, run the acts. -/
def lockRoot (lk : Lock) (us : List Use) (as : List Act) : IO :=
  .flatMap (.delay HS.newCell.fn) (HS.afterCell lk.toVal (usesV us) (actsV as)).fn

/-! ## The library of the statements -/

/-- The public operations of the mirrors: `Semaphore[IO](k)`, `s.acquireN`, ... (`SL.op*`) and
`Mutex[IO]`, `m.lock.use(f)` (`ML.op*`). The other closures of the mirrors are internal. -/
def SL.public : SL → Bool
  | .opNew _ | .opAcquireN _ _ | .opReleaseN _ _ | .opTryAcquireN _ _ | .opAvailable _ | .opCount _
  | .opPermitUse _ _ => true
  | _ => false

def ML.public : ML → Bool
  | .opNew | .opLockUse _ _ => true
  | _ => false

/-- The public harness closures: `newCell` and `afterCell` (they hold no handle). -/
def HS.public : HS → Bool
  | .newCell | .afterCell _ _ _ => true
  | _ => false

/-- The `Lib` of the statements with user code: the `Bracket` combinators, the public operations
of the two mirrors, and the public harness closures. -/
def semLib : Lib :=
  { ok := fun id => Bracket.isLib id || ((SL.ofId? id).map SL.public).getD false ||
      ((ML.ofId? id).map ML.public).getD false || ((HS.ofId? id).map HS.public).getD false }

/-! ## Observations -/

/-- `(available, count)` of a semaphore root. -/
def availOf : Val → Option Nat
  | .pair (.nat a) _ => some a
  | _ => none

def countOf : Val → Option Int
  | .pair _ (.int c) => some c
  | _ => none

/-- The highest count in the final heap. -/
def highest (o : Obs) : Option Nat :=
  match (o.refs[0]? : Option Val) with
  | some (.pair _ (.nat h)) => some h
  | _ => none

/-- The permits that the parent releases. -/
def released : List Act → Nat
  | [] => 0
  | .release n :: rest => n + released rest
  | _ :: rest => released rest

/-- Every fiber `i < m` is canceled or joined by the parent. -/
def AllEnded (m : Nat) (as : List Act) : Prop :=
  ∀ i < m, Act.cancel i ∈ as ∨ Act.join i ∈ as

/-- The number of permits a use asks for (`permit`, `counted`: 1). -/
def Use.need : Use → Nat
  | .permit _ | .counted _ => 1
  | .acqRel n | .tryRel n => n

/-! ## Behaviour tables (statements 2, 6, 7; namespace 63) -/

def bns : Nat := 63

/-- The last action of a critical section. -/
inductive Base where
  | ok (v : Val)
  | err (e : Err)
  | canc
  deriving DecidableEq, Repr

def Base.io : Base → IO
  | .ok v => .pure v
  | .err e => .error e
  | .canc => .canceled

def Base.toVal : Base → Val
  | .ok v => .left v
  | .err e => .right (.err e)
  | .canc => .none

def Base.ofVal : Val → Option Base
  | .left v => some (.ok v)
  | .right (.err e) => some (.err e)
  | .none => some .canc
  | _ => none

/-- `body k b`: `_ => IO.cede` `k` times, then `b` (a harness user function, no handle). -/
inductive BH where
  | body (k : Nat) (b : Val)
  deriving DecidableEq, Repr

def BH.toVal : BH → Val
  | .body k b => cloVal bns 0 [.nat k, b]

/-- Behaviour closures are even ids (user code that Scala can write; they hold no handle). -/
def BH.id (l : BH) : Nat := 2 * valToNat l.toVal

def BH.ofId? (id : Nat) : Option BH :=
  if id % 2 == 0 then
    match (cloOfId id).bind ofCloVal with
    | some (63, 0, [.nat k, b]) => some (.body k b)
    | _ => none
  else none

def BH.call (h : BH) : UserResult :=
  match h with
  | .body 0 b => match Base.ofVal b with
    | some b' => { out := .prog b'.io }
    | none => illT
  | .body (k + 1) b => { out := .prog (.flatMap .cede (.user (BH.body k b).id)) }

/-- The behaviour environment: only `BH` closures (no other user code). -/
def behaved : UserEnv where
  call id _ _ := match BH.ofId? id with
    | some h => h.call
    | none => illT

/-- A use with a behaviour table in place of user code. -/
inductive BUse where
  | permit (k : Nat) (b : Base)
  | acqRel (n : Nat)
  | tryRel (n : Nat)
  deriving DecidableEq, Repr

def BUse.toUse : BUse → Use
  | .permit k b => .permit (BH.body k b.toVal).id
  | .acqRel n => .acqRel n
  | .tryRel n => .tryRel n

def BUse.need : BUse → Nat
  | .permit _ _ => 1
  | .acqRel n | .tryRel n => n

/-! ## Statements -/

/-- Statement 1 (`std.Semaphore.noLostPermit`): when every user fiber has ended (canceled or
joined), `available` is the initial number of permits plus the permits the parent released: no
use (permit, acquire/release with cancelation, tryAcquire), no cancelation at any point and no user
code loses or adds a permit. -/
def semNoLostPermit : Prop :=
  ∀ (u : UserEnv) (k : Nat) (us : List Use) (as : List Act),
    AllEnded us.length as →
    WellFormed semLib [] (env u) (lockRoot (.sem k) us as) →
    ∀ o, outcomesP {} counterMaskModel (env u) (lockRoot (.sem k) us as) o →
      ∀ v, o.summary = .done (.succeeded v) → availOf v = some (k + released as)

/-- A use whose own code ends with a value (no error, no self-cancel): it must succeed. -/
def BUse.succeeds : BUse → Bool
  | .permit _ (.ok _) => true
  | .permit _ _ => false
  | .acqRel _ | .tryRel _ => true

/-- Fiber `i` is joined, never canceled by the parent, and its use must succeed. -/
def OkJoined (bus : List BUse) (as : List Act) (i : Nat) : Prop :=
  ∃ b, bus[i]? = some b ∧ b.succeeds = true ∧ Act.join i ∈ as ∧ Act.cancel i ∉ as

/-- Statement 2 (`std.Semaphore.noDeadlock`): with critical sections that end (behaviour tables)
and requests that the permits can meet (`need ≤ k`), every run that stops either ends `Succeeded`
with `available = k + released` (no deadlock, no lost wakeup, no lost permit) and a `Succeeded`
join record for every joined, not canceled use whose own code succeeds (a granted request is
served, review batch 11b W1), or ends `fatal` (a critical section raised a fatal error).

History. Review batch 11b (H1): the first form ("every stopped run ends `Succeeded`") was false for
every implementation, because a fatal error stops the whole run with `Summary.fatal`
(`Model/Sched.lean:120`; `IOFiber` `onFatalFailure`). The 11b form ("not `blocked`" plus claims on
`Succeeded` runs) let a root that ends `Errored` pass: an `available` that always raises met it
(review batch 12, H2). This form rejects every summary except `Succeeded` and `fatal`. For a correct
semaphore the root never raises: its own steps (`cancel`, `join`, `releaseN`, `cede`, `available`,
`count`) do not raise, and a join returns the outcome. Regressions and the wrong-function battery
(decision 63): `Proofs/Phase7/SemaphoreWitness.lean`, `Proofs/Phase7/SemaphoreBattery.lean`. -/
def semNoDeadlock : Prop :=
  ∀ (k : Nat) (bus : List BUse) (as : List Act),
    AllEnded bus.length as → (∀ b ∈ bus, b.need ≤ k) →
    ∀ o, outcomesP {} counterMaskModel (env behaved) (lockRoot (.sem k) (bus.map BUse.toUse) as) o →
      (∃ v, o.summary = .done (.succeeded v) ∧ availOf v = some (k + released as) ∧
        ∀ i, OkJoined bus as i → ∃ x, joinRecV i (.ocSucceeded x) ∈ o.out) ∨
      (∃ e, o.summary = .fatal e)

/-- Statement 3 (`std.Semaphore.permit.atMostK`): at most `k` fibers hold a permit of
`Semaphore(k)` at once (the counted fibers; other uses also take permits). -/
def semAtMostK : Prop :=
  ∀ (u : UserEnv) (k : Nat) (us : List Use) (as : List Act),
    (∀ a ∈ as, ∀ n, a ≠ .release n) →
    WellFormed semLib [] (env u) (lockRoot (.sem k) us as) →
    ∀ o, outcomesP {} counterMaskModel (env u) (lockRoot (.sem k) us as) o →
      ∃ h, highest o = some h ∧ h ≤ k

/-- Statement 4 (`std.Mutex.lock.mutualExclusion`): at most one fiber holds the lock at once. -/
def mutexMutualExclusion : Prop :=
  ∀ (u : UserEnv) (us : List Use) (as : List Act),
    WellFormed semLib [] (env u) (lockRoot .mutex us as) →
    ∀ o, outcomesP {} counterMaskModel (env u) (lockRoot .mutex us as) o →
      ∃ h, highest o = some h ∧ h ≤ 1

/-- Statement 5 (`std.Mutex.lock.noDeadlock`): with critical sections that end, every run that stops
either ends `Succeeded(())` (the last `lock.use` gets the lock, no waiter is lost) with a `Succeeded`
join record for every joined, not canceled use whose own code succeeds, or ends `fatal`. Only
`permit` uses (a mutex has no `acquireN`). History as statement 2: review batch 11b (H1, the first
form was false with a fatal error) and review batch 12 (W2, "not `blocked`" let a root `Errored`
pass). -/
def mutexNoDeadlock : Prop :=
  ∀ (bus : List BUse) (as : List Act),
    AllEnded bus.length as → (∀ b ∈ bus, ∃ k bb, b = .permit k bb) →
    ∀ o, outcomesP {} counterMaskModel (env behaved) (lockRoot .mutex (bus.map BUse.toUse) as) o →
      (o.summary = .done (.succeeded .unit) ∧
        ∀ i, OkJoined bus as i → ∃ x, joinRecV i (.ocSucceeded x) ∈ o.out) ∨
      (∃ e, o.summary = .fatal e)

/-- Statement 6 (`std.Semaphore.count.atRest`): when every user fiber has ended, nobody waits, so
`count` equals `available` (`S:48-52`: `count` is "Like [[available]] when permits are available but
returns the number of permits callers are waiting for when there are no permits available"). -/
def semCountAtRest : Prop :=
  ∀ (k : Nat) (bus : List BUse) (as : List Act),
    AllEnded bus.length as →
    ∀ o, outcomesP {} counterMaskModel (env behaved) (lockRoot (.sem k) (bus.map BUse.toUse) as) o →
      ∀ v, o.summary = .done (.succeeded v) → ∃ a, availOf v = some a ∧ countOf v = some (a : Int)

/-! ### FIFO (statement 7, namespace 64)

`acquireN` (`S:58-61`): "acquires are statisfied in strict FIFO order, so given `s: Semaphore[F]`
with 2 permits available, an `acquireN(3)` will always be satisfied before a later call to
`acquireN(1)`."

The root: `Semaphore[IO](0)`; for each `n_i` in order, start fiber `F_i = s.acquireN(n_i)`, then
spin on `count` (`cede` between reads) until `count = -(n_1 + ... + n_i)` (so `F_i` is in the queue
before `F_{i+1}` calls `acquireN`). Then `s.releaseN(r)`, then join `F_1 .. F_j`, where `j` is the
longest prefix with `n_1 + ... + n_j ≤ r`, then read `count`. With strict FIFO the first `j`
requests get their permits and the others wait, so every run that stops ends `Succeeded(count)`
with `count = r - (n_1 + ... + n_m)`. A later request served first leaves some `F_i` (`i ≤ j`)
waiting: its join blocks (`blocked`). No user code. -/

def fns : Nat := 64

inductive FL where
  /-- `s => start F_1 ...` (the root continuation). -/
  | afterSem (reqs : Val) (r : Nat)
  /-- `fiber => spin until count = target, then the next fiber`. -/
  | started (s : Nat) (reqs rest : Val) (r : Nat) (fs : Val) (target : Nat)
  /-- `c => if (c == -target) next else cede *> spin`. -/
  | check (s : Nat) (reqs rest : Val) (r : Nat) (fs : Val) (target : Nat)
  /-- `_ => count.flatMap(check)` (after a `cede`). -/
  | spin (s : Nat) (reqs rest : Val) (r : Nat) (fs : Val) (target : Nat)
  /-- `_ => join F_1 .. F_j, then count`. -/
  | joins (s : Nat) (fs : Val) (j : Nat)
  deriving DecidableEq, Repr

def FL.toVal : FL → Val
  | .afterSem reqs r => cloVal fns 0 [reqs, .nat r]
  | .started s reqs rest r fs t => cloVal fns 1 [.fn s, reqs, rest, .nat r, fs, .nat t]
  | .check s reqs rest r fs t => cloVal fns 2 [.fn s, reqs, rest, .nat r, fs, .nat t]
  | .spin s reqs rest r fs t => cloVal fns 3 [.fn s, reqs, rest, .nat r, fs, .nat t]
  | .joins s fs j => cloVal fns 4 [.fn s, fs, .nat j]

def FL.id (l : FL) : Nat := 2 * valToNat l.toVal + 1
def FL.fn (l : FL) : Fn := .user l.id

def FL.ofId? (id : Nat) : Option FL :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (64, 0, [reqs, .nat r]) => some (.afterSem reqs r)
    | some (64, 1, [.fn s, reqs, rest, .nat r, fs, .nat t]) => some (.started s reqs rest r fs t)
    | some (64, 2, [.fn s, reqs, rest, .nat r, fs, .nat t]) => some (.check s reqs rest r fs t)
    | some (64, 3, [.fn s, reqs, rest, .nat r, fs, .nat t]) => some (.spin s reqs rest r fs t)
    | some (64, 4, [.fn s, fs, .nat j]) => some (.joins s fs j)
    | _ => none
  else none

def natsOf (v : Val) : List Nat := ((unlistV v).getD []).filterMap fun | .nat n => some n | _ => none

/-- The longest prefix of `reqs` whose sum is at most `r`. -/
def prefixLen : List Nat → Nat → Nat
  | [], _ => 0
  | n :: rest, r => if n ≤ r then prefixLen rest (r - n) + 1 else 0

/-- Start the next fiber, or release and join. -/
def fifoNext (s : Nat) (reqs rest : Val) (r : Nat) (fs : Val) (target : Nat) : IO :=
  match natsOf rest with
  | n :: rest' => .flatMap (.start (acquireNIO s n)) (FL.started s reqs (listV (rest'.map Val.nat)) r fs (target + n)).fn
  | [] => .flatMap (releaseNIO s r) (FL.joins s fs (prefixLen (natsOf reqs) r)).fn

def FL.call (h : FL) (arg : Val) (v : View) : UserResult :=
  match h with
  | .afterSem reqs r =>
    match arg with
    | .fn s => { out := .prog (fifoNext s reqs reqs r (listV []) 0) }
    | _ => illT
  | .started s reqs rest r fs t =>
    let fs' := listV (((unlistV fs).getD []) ++ [arg])
    { out := .prog (.flatMap (countIO s) (FL.check s reqs rest r fs' t).fn) }
  | .check s reqs rest r fs t =>
    if arg == .int (-(t : Int)) then { out := .prog (fifoNext s reqs rest r fs t) }
    else { out := .prog (.flatMap .cede (FL.spin s reqs rest r fs t).fn) }
  | .spin s reqs rest r fs t => { out := .prog (.flatMap (countIO s) (FL.check s reqs rest r fs t).fn) }
  | .joins s fs j =>
    match j, (unlistV fs).getD [] with
    | j' + 1, .fiber t :: rest => { out := .prog (.flatMap (IO.joinOf t (v.outcome t)) (FL.joins s (listV rest) j').fn) }
    | _, _ => { out := .prog (countIO s) }

/-- The FIFO root: `Semaphore[IO](0).flatMap(s => ...)`. -/
def fifoRoot (reqs : List Nat) (r : Nat) : IO :=
  .flatMap (Semaphore.newIO 0) (FL.afterSem (listV (reqs.map Val.nat)) r).fn

/-- The FIFO harness environment (no user code). -/
def fifoEnv : UserEnv :=
  Mutex.env {
    call := fun id a refs => match FL.ofId? id with
      | some h => h.call a { refs }
      | none => illT
    callV := fun id a v => match FL.ofId? id with
      | some h => h.call a v
      | none => illT }

/-- Statement 7 (`std.Semaphore.acquireN.fifo`): requests are served in strict FIFO order: every
run that stops ends `Succeeded(r - (n_1 + ... + n_m))` (as the `count` value). -/
def semFifo : Prop :=
  ∀ (reqs : List Nat) (r : Nat),
    ∀ o, outcomesP {} counterMaskModel fifoEnv (fifoRoot reqs r) o →
      o.summary = .done (.succeeded (.int ((r : Int) - (reqs.foldl (· + ·) 0 : Nat))))

/-! ### The twin (statement 8): `Mutex` and `Semaphore(1).permit` -/

/-- The part of an observation that both locks share: the root outcome and the user trace (the
final heap holds the lock state, which differs). -/
def core (o : Obs) : Summary × List Val := (o.summary, o.out)

/-- Statement 8 (`std.Mutex.lock.semaphoreTwin`): `Mutex[IO]` and `Semaphore[IO](1)` used through
`lock.use(g)` / `permit.use(g)` (and counted uses) give the same outcomes and traces, over all
schedules (`docs/std/mutex.md:6-7`). One direction only: every outcome of the mutex program is an
outcome of the semaphore program. The converse (every `Semaphore(1)` outcome is a mutex outcome) is
a different claim and is not registered. The smoke test samples only this direction, and a sampled
miss is printed but not counted as a failure (sampling cannot show that an outcome is missing). -/
def mutexSemaphoreTwin : Prop :=
  ∀ (u : UserEnv) (gs : List Use) (as : List Act),
    (∀ x ∈ gs, ∃ g, x = .permit g ∨ x = .counted g) →
    (∀ a ∈ as, ∀ n, a ≠ .release n) →
    WellFormed semLib [] (env u) (lockRoot .mutex gs as) →
    WellFormed semLib [] (env u) (lockRoot .semMutex gs as) →
    ∀ o, outcomesP {} counterMaskModel (env u) (lockRoot .mutex gs as) o →
      ∃ o', outcomesP {} counterMaskModel (env u) (lockRoot .semMutex gs as) o' ∧ core o' = core o

end CatsEffectInLean.Props.Phase7.Semaphore

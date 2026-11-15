import CatsEffectInLean.Std.QueueFactory
import CatsEffectInLean.Model.Outcomes

/-!
# `Queue`: no lost element, no duplicated element, FIFO, no deadlock, taker liveness (Phase 7, track Q)

Models: `Std/QueueConcurrent.lean` (`BoundedQueue`, `DroppingQueue`, `CircularBufferQueue`,
`Synchronous`), `Std/QueueAsync.lean` (`BoundedAsyncQueue`, `DroppingAsyncQueue`,
`UnboundedAsyncQueue`, under sequential consistency), `Std/QueueFactory.lean` (the factories,
`F = IO`). `Q` = `std/shared/src/main/scala/cats/effect/std/Queue.scala` at `v3.7.1`.

## The test harness (namespace 54)

A queue never calls user code: its only inputs are the elements (opaque values) and the calls of
its methods from fibers, which can be canceled at any point. So the statements quantify over
programs of the shape below, with all inputs as data, and over all `PChoice` schedules
(`outcomesP`: every interleaving at run-loop-iteration granularity, so a cancel can land between
any two run-loop iterations of the target). The harness holds no user code, so no `WellFormed`
hypothesis is needed (as `parTraverseN` statements 5-7).

`rootIO k scripts plan mode`:

1. `q <- factory(k)`.
2. Start one fiber per script. A script is a list of operations, each run in the documented
   atomic pattern (the QueueSuite test "not lose data on canceled take",
   `tests/shared/src/test/scala/cats/effect/std/QueueSuite.scala:793-850`):
   `IO.uncancelable(poll => poll(op).map(r => record(r)))`. `record` appends an event to the trace
   (`UserEffect.emit`): `offered x` after `offer(x)` returned, `took x` after `take`,
   `tryTook r` after `tryTake`, `tryOffered (x, b)` after `tryOffer(x)`, `size n`. An `offer`
   also records `offerStart x` inside the masked region, before `poll(offer(x))`. Each event
   carries the index of its script (review batch 11a). `cede` is `IO.cede`.
3. The cancel plan: for each `(n, i)`, `IO.cede` `n` times, then `fiber_i.cancel`.
4. Mode `cancelAll`: cancel every fiber (in start order); mode `join js`: join the fibers with
   index in `js` (in order), then cancel every fiber.
5. Drain: `tryTake` until `None`, each element recorded as `drained x`.

The trace (`Obs.out`, newest first) gives: `offeredOf` (the elements of returned `offer`s and of
`tryOffer`s that returned `true`) and `removedOf` (the elements of `took`, `tryTook (Some x)`,
`drained`).

## Statements

Per family (twins: the `Concurrent` and the `Async` implementations of the same factory):

1. `noLoss` (no lost element): in every run that ends `Succeeded`, every recorded offered
   element is removed (`SubMulti offeredOf removedOf`: multisets). Kinds that never drop by design:
   `bounded`, `unbounded`, `synchronous` (the dropping and circular-buffer queues discard by
   design, `Q:184-228`).
2. `noDup` (no duplicated or invented element): every run that stops removes a sub-multiset of the
   elements that the scripts offer (all kinds).
3. `fifo`: for every remover (each script, and the root drain) and every producing script, the
   remover removes that script's elements in the script's offer order (a `Sublist`), all kinds.
   The events of different fibers are recorded in record order, which is not the dequeue order, so
   the order is stated per remover and per producer (review batch 11a F1: the old hypothesis "at
   most one script takes" is gone). Elements are distinct
   (`Nodup`): the queue never inspects elements, so distinct values only make them traceable.
   Scaladoc: "insertion and retrieval of elements of type `A` in a first-in-first-out (FIFO)
   manner" (`Q:31-33`).
4. `noDeadlock`: in mode `cancelAll` every run that stops ends `Succeeded`: canceling waiting
   offerers and takers never hangs, and nothing else blocks.
5. `takerLiveness` (no lost wakeup): scripts are pure producers (`offer` only) and pure
   consumers (`take` only), the plan cancels only consumers, the root joins all consumers. Every
   run that stops ends `Succeeded`, or stops `blocked` only when the queue has nothing to give
   (`QuietBlock`: every recorded offered element was removed, and every started `offer` returned).
   So a waiting taker is woken when an element is there or an offerer waits. No count hypothesis
   (review batch 11a L1: it counted the takes of canceled consumers). Kinds that never drop.
   `outcomesP` observes only runs that stop, so a livelock (a run that never stops) is not seen
   (review batch 11a D5).

Twin statement (one statement for both families):

6. `twinSeq`: the two implementations of one factory agree on sequential use. For every capacity
   `2 <= cap < 65534` and the pairs `(boundedForConcurrent(cap), bounded(cap))`,
   `(droppingForConcurrent(cap), dropping(cap))`, `(unboundedForConcurrent, unbounded)`, and every
   script run by one fiber that the root joins: the two sides have the same set of
   (summary, trace) results. `Queue.bounded` picks the family by the class of the instance and by
   the capacity (`Q:74-91`); the Scaladoc of `bounded`, `dropping`, `unbounded` (`Q:63-73`,
   `Q:152-159`, `Q:184-195`) does not depend on the family.
-/

namespace CatsEffectInLean.Props.Phase7.Queue

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.QueueFactory

/-- The harness namespace (track Q: 50..59). -/
def hns : Nat := 54

/-! ## Operations and events -/

/-- One operation of a script. -/
inductive Op where
  | offer (x : Val)
  | tryOffer (x : Val)
  | take
  | tryTake
  | size
  | cede
  deriving DecidableEq, Repr

def Op.toVal : Op → Val
  | .take => .nat 0
  | .tryTake => .nat 1
  | .cede => .nat 2
  | .size => .nat 3
  | .offer x => .pair (.nat 4) x
  | .tryOffer x => .pair (.nat 5) x

def Op.ofVal? : Val → Option Op
  | .nat 0 => some .take
  | .nat 1 => some .tryTake
  | .nat 2 => some .cede
  | .nat 3 => some .size
  | .pair (.nat 4) x => some (.offer x)
  | .pair (.nat 5) x => some (.tryOffer x)
  | _ => none

/-- The mode of the end of the root. -/
inductive Mode where
  | cancelAll
  | join (js : List Nat)
  deriving DecidableEq, Repr

def Mode.toVal : Mode → Val
  | .cancelAll => .none
  | .join js => .some (listV (js.map .nat))

def Mode.ofVal? : Val → Option Mode
  | .none => some .cancelAll
  | .some l => (unlistV l).bind fun xs => (xs.mapM fun | Val.nat n => some n | _ => none).map Mode.join
  | _ => none

/-- Event tags in the trace. -/
def evOffered : Nat := 0
def evTook : Nat := 1
def evTryTook : Nat := 2
def evTryOffered : Nat := 3
def evDrained : Nat := 4
def evSize : Nat := 5
/-- An `offer` started (recorded inside the masked region, before `poll(offer)`). -/
def evOfferStart : Nat := 6

/-! ## Closures (namespace `hns`) -/

inductive QH where
  /-- `q => start scripts ...`. -/
  | afterNew (scripts plan mode : Val)
  /-- `fiber => ...`: remember the fiber, start the next script or go on with the plan. -/
  | startNext (o : Nat) (fs rest plan mode : Val)
  /-- `_ => fiber_i.cancel` after the `cede`s of a plan step. -/
  | planCancel (o : Nat) (fs : Val) (i : Nat) (plan mode : Val)
  /-- `_ => (rest of the plan)`. -/
  | planNext (o : Nat) (fs plan mode : Val)
  /-- `_ => join the next fiber of `js``. -/
  | joinNext (o : Nat) (fs js : Val)
  /-- `_ => cancel the next fiber`. -/
  | cancelNext (o : Nat) (todo : Val)
  /-- `r => r match { Some(x) => record drained x; tryTake again; None => () }`. -/
  | drainK (o : Nat)
  /-- `_ => drain` after a recorded element. -/
  | drainAgain (o : Nat)
  /-- `_ => (rest of script `i`)`. -/
  | next (o i : Nat) (rest : Val)
  /-- `poll => poll(op).map(record)` in script `i` (an `offer` first records `offerStart`). -/
  | opBody (o i : Nat) (op : Val)
  /-- `r => record (tag, i, r)`. -/
  | recK (i tag : Nat)
  /-- `_ => record (tag, i, x)`. -/
  | recC (i tag : Nat) (x : Val)
  /-- `b => record (tryOffered, i, (x, b))`. -/
  | recTO (i : Nat) (x : Val)
  /-- `_ => poll(q.offer(x)).map(record offered)` after the `offerStart` event. -/
  | offerPoll (o i : Nat) (x : Val) (m p : Nat)
  /-- `_ => ()`: the end of a `cede` chain. -/
  | unitK
  deriving DecidableEq, Repr

def QH.toVal : QH → Val
  | .afterNew s p m => cloVal hns 0 [s, p, m]
  | .startNext o fs r p m => cloVal hns 1 [.fn o, fs, r, p, m]
  | .planCancel o fs i p m => cloVal hns 2 [.fn o, fs, .nat i, p, m]
  | .planNext o fs p m => cloVal hns 3 [.fn o, fs, p, m]
  | .joinNext o fs js => cloVal hns 4 [.fn o, fs, js]
  | .cancelNext o t => cloVal hns 5 [.fn o, t]
  | .drainK o => cloVal hns 6 [.fn o]
  | .drainAgain o => cloVal hns 7 [.fn o]
  | .next o i r => cloVal hns 8 [.fn o, .nat i, r]
  | .opBody o i op => cloVal hns 9 [.fn o, .nat i, op]
  | .recK i t => cloVal hns 10 [.nat i, .nat t]
  | .recC i t x => cloVal hns 11 [.nat i, .nat t, x]
  | .recTO i x => cloVal hns 12 [.nat i, x]
  | .offerPoll o i x m p => cloVal hns 14 [.fn o, .nat i, x, .poll m p]
  | .unitK => cloVal hns 13 []

def QH.ofFields : Nat → List Val → Option QH
  | 0, [s, p, m] => some (.afterNew s p m)
  | 1, [.fn o, fs, r, p, m] => some (.startNext o fs r p m)
  | 2, [.fn o, fs, .nat i, p, m] => some (.planCancel o fs i p m)
  | 3, [.fn o, fs, p, m] => some (.planNext o fs p m)
  | 4, [.fn o, fs, js] => some (.joinNext o fs js)
  | 5, [.fn o, t] => some (.cancelNext o t)
  | 6, [.fn o] => some (.drainK o)
  | 7, [.fn o] => some (.drainAgain o)
  | 8, [.fn o, .nat i, r] => some (.next o i r)
  | 9, [.fn o, .nat i, op] => some (.opBody o i op)
  | 10, [.nat i, .nat t] => some (.recK i t)
  | 11, [.nat i, .nat t, x] => some (.recC i t x)
  | 12, [.nat i, x] => some (.recTO i x)
  | 14, [.fn o, .nat i, x, .poll m p] => some (.offerPoll o i x m p)
  | 13, [] => some .unitK
  | _, _ => none

def QH.id (l : QH) : Nat := 2 * valToNat l.toVal + 1
def QH.fn (l : QH) : Fn := .user l.id

def QH.ofId? (id : Nat) : Option QH :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == hns then QH.ofFields tag fs else none
    | none => none
  else none

/-! ## Terms -/

/-- `IO.cede` `n` times (`IO.cede *> ... *> IO.unit`). -/
def cedes : Nat → IO
  | 0 => .pure .unit
  | n + 1 => .flatMap .cede (QH.next 0 0 (listV (List.replicate n (Op.toVal .cede)))).fn

/-- The program of one operation of script `i` on queue `o`. -/
def opIO (o i : Nat) (op : Op) : IO :=
  match op with
  | .cede => .cede
  | op => .uncancelable (QH.opBody o i op.toVal).fn

/-- Script `i`: its operations in sequence. -/
def scriptIO (o i : Nat) : List Val → IO
  | [] => .pure .unit
  | op :: rest =>
    match Op.ofVal? op with
    | some op => .flatMap (opIO o i op) (QH.next o i (listV rest)).fn
    | none => .error { code := 999999, kind := .fatal }

/-- Drain: `tryTake` until `None`. -/
def drainIO (o : Nat) : IO := .flatMap (tryTakeIO o) (QH.drainK o).fn

/-- Cancel the fibers `todo` in order, then drain. The `cancel` term reads the fiber outcome
(`IO.cancelOf`, `IOFiber.scala:197-201`). -/
def cancelAllIO (v : View) (o : Nat) : List Val → IO
  | [] => drainIO o
  | .fiber f :: rest => .flatMap (IO.cancelOf f (v.outcome f)) (QH.cancelNext o (listV rest)).fn
  | _ :: rest => .flatMap (.pure .unit) (QH.cancelNext o (listV rest)).fn

/-- The end of the root after the plan. -/
def endIO (v : View) (o : Nat) (fs : List Val) : Mode → IO
  | .cancelAll => cancelAllIO v o fs
  | .join js => .flatMap (.pure .unit) (QH.joinNext o (listV fs) (listV (js.map .nat))).fn

/-- The plan, then the end. -/
def planIO (v : View) (o : Nat) (fs : List Val) (plan : List Val) (mode : Val) : IO :=
  match plan with
  | [] =>
    match Mode.ofVal? mode with
    | some m => endIO v o fs m
    | none => .error { code := 999999, kind := .fatal }
  | .pair (.nat n) (.nat i) :: rest =>
    .flatMap (cedes n) (QH.planCancel o (listV fs) i (listV rest) mode).fn
  | _ => .error { code := 999999, kind := .fatal }

/-- The root program. `scripts`: one list of operations per fiber; `plan`: `(cedes, fiber index)`
pairs. -/
def rootIO (k : QKind) (scripts : List (List Op)) (plan : List (Nat × Nat)) (mode : Mode) : IO :=
  .flatMap (newIO k)
    (QH.afterNew (listV (scripts.map fun s => listV (s.map Op.toVal)))
      (listV (plan.map fun (n, i) => .pair (.nat n) (.nat i))) mode.toVal).fn

private def ret (v : Val) (es : List UserEffect := []) : UserResult := { effects := es, out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
def illTyped : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- An event value: tag, script index (`0` for the drain), value. -/
def ev (tag i : Nat) (x : Val) : Val := .pair (.nat tag) (.pair (.nat i) x)

/-- Run one harness closure. -/
def QH.call (l : QH) (arg : Val) (v : View) : UserResult :=
  match l with
  | .afterNew s p m =>
    match arg, unlistV s with
    | .fn o, some [] => prog (planIO v o [] ((unlistV p).getD []) m)
    | .fn o, some (s0 :: rest) =>
      prog (.flatMap (.start (scriptIO o 0 ((unlistV s0).getD []))) (QH.startNext o (listV []) (listV rest) p m).fn)
    | _, _ => illTyped
  | .startNext o fs r p m =>
    let fs' := (unlistV fs).getD [] ++ [arg]
    match unlistV r with
    | some [] => prog (planIO v o fs' ((unlistV p).getD []) m)
    | some (s :: rest) =>
      prog (.flatMap (.start (scriptIO o fs'.length ((unlistV s).getD []))) (QH.startNext o (listV fs') (listV rest) p m).fn)
    | none => illTyped
  | .planCancel o fs i p m =>
    match ((unlistV fs).getD [])[i]? with
    | some (.fiber f) => prog (.flatMap (IO.cancelOf f (v.outcome f)) (QH.planNext o fs p m).fn)
    | _ => prog (planIO v o ((unlistV fs).getD []) ((unlistV p).getD []) m)
  | .planNext o fs p m => prog (planIO v o ((unlistV fs).getD []) ((unlistV p).getD []) m)
  | .joinNext o fs js =>
    match unlistV js with
    | some (.nat j :: rest) =>
      match ((unlistV fs).getD [])[j]? with
      | some (.fiber f) => prog (.flatMap (IO.joinOf f (v.outcome f)) (QH.joinNext o fs (listV rest)).fn)
      | _ => prog (.flatMap (.pure .unit) (QH.joinNext o fs (listV rest)).fn)
    | _ => prog (cancelAllIO v o ((unlistV fs).getD []))
  | .cancelNext o t => prog (cancelAllIO v o ((unlistV t).getD []))
  | .drainK o =>
    match arg with
    | .some x => { effects := [.emit (ev evDrained 0 x)], out := .prog (drainIO o) }
    | _ => prog (.pure .unit)
  | .drainAgain o => prog (drainIO o)
  | .next o i r => prog (scriptIO o i ((unlistV r).getD []))
  | .opBody o i op =>
    match arg, Op.ofVal? op with
    | .poll m p, some (.offer x) =>
      prog (.flatMap (.delay (QH.recC i evOfferStart x).fn) (QH.offerPoll o i x m p).fn)
    | .poll m p, some (.tryOffer x) => prog (.map (IO.applyPoll (tryOfferIO o x) m p) (QH.recTO i x).fn)
    | .poll m p, some .take => prog (.map (IO.applyPoll (takeIO o) m p) (QH.recK i evTook).fn)
    | .poll m p, some .tryTake => prog (.map (IO.applyPoll (tryTakeIO o) m p) (QH.recK i evTryTook).fn)
    | .poll m p, some .size => prog (.map (IO.applyPoll (sizeIO o) m p) (QH.recK i evSize).fn)
    | _, _ => illTyped
  | .offerPoll o i x m p => prog (.map (IO.applyPoll (offerIO o x) m p) (QH.recC i evOffered x).fn)
  | .recK i t => ret .unit [.emit (ev t i arg)]
  | .recC i t x => ret .unit [.emit (ev t i x)]
  | .recTO i x => ret .unit [.emit (ev evTryOffered i (.pair x arg))]
  | .unitK => ret .unit

/-- The environment: queue closures, harness closures; any other id throws (no user code). -/
def henv : UserEnv :=
  env { call := fun id arg refs =>
          match QH.ofId? id with
          | some l => l.call arg { refs }
          | none => illTyped
        callV := fun id arg v =>
          match QH.ofId? id with
          | some l => l.call arg v
          | none => illTyped }

/-! ## Reading the trace -/

/-- The events of a trace in emission order: (tag, script index, value). -/
def events (out : List Val) : List (Nat × Nat × Val) :=
  out.reverse.filterMap fun
    | .pair (.nat t) (.pair (.nat i) x) => some (t, i, x)
    | _ => none

/-- The elements that offers put in (`offer` returned, `tryOffer` returned `true`), in order. -/
def offeredOf (out : List Val) : List Val :=
  (events out).filterMap fun
    | (0, _, x) => some x
    | (3, _, .pair x (.bool true)) => some x
    | _ => none

/-- The elements of the `offer`s that started (`offerStart` events). -/
def startedOf (out : List Val) : List Val :=
  (events out).filterMap fun
    | (6, _, x) => some x
    | _ => none

/-- The elements that left the queue (`take`, `tryTake` with `Some`, drain), in order. -/
def removedOf (out : List Val) : List Val :=
  (events out).filterMap fun
    | (1, _, x) => some x
    | (2, _, .some x) => some x
    | (4, _, x) => some x
    | _ => none

/-- The remover of an element: script `i` (`take`, `tryTake`), or the root drain (`none`). -/
def removedBy (out : List Val) (c : Option Nat) : List Val :=
  (events out).filterMap fun
    | (1, i, x) => if c = some i then some x else none
    | (2, i, .some x) => if c = some i then some x else none
    | (4, _, x) => if c = none then some x else none
    | _ => none

/-- All elements that the scripts offer (`offer`, `tryOffer`). -/
def offersOf (s : List Op) : List Val :=
  s.filterMap fun
    | .offer x => some x
    | .tryOffer x => some x
    | _ => none

def allOffers (scripts : List (List Op)) : List Val := (scripts.map offersOf).flatten

/-- Does a script remove elements (`take`, `tryTake`)? -/
def takes (s : List Op) : Bool := s.any fun | .take | .tryTake => true | _ => false

/-- The number of `take`s of a script. -/
def takeCount (s : List Op) : Nat := (s.filter fun | .take => true | _ => false).length

/-- A pure producer: only `offer`s. -/
def producer (s : List Op) : Prop := ∀ op ∈ s, ∃ x, op = .offer x

/-- A pure consumer: only `take`s. -/
def consumer (s : List Op) : Prop := ∀ op ∈ s, op = .take

/-! ## The kinds of each family -/

/-- The `Concurrent` kinds that never drop: `boundedForConcurrent(cap)` (cap ≥ 1, `Q:515`),
`unboundedForConcurrent`, `synchronous`. -/
def ConcKeep (k : QKind) : Prop :=
  (∃ cap, 1 ≤ cap ∧ k = .boundedConc cap) ∨ k = .unboundedConc ∨ k = .synchronous

/-- The `Async` kinds that never drop: `bounded(cap)` with `1 < cap < 65534` (`BoundedAsyncQueue`,
`Q:78-81`), `unbounded` (`UnboundedAsyncQueue`). -/
def AsyncKeep (k : QKind) : Prop :=
  (∃ cap, 1 < cap ∧ cap < asyncLimit ∧ k = .bounded cap) ∨ k = .unbounded

/-- All `Concurrent` kinds (dropping and circular buffer with cap ≥ 1, `Q:236-240`). -/
def ConcAny (k : QKind) : Prop :=
  ConcKeep k ∨ (∃ cap, 1 ≤ cap ∧ (k = .droppingConc cap ∨ k = .circular cap))

/-- All `Async` kinds (`DroppingAsyncQueue` with `1 < cap < 65534`). -/
def AsyncAny (k : QKind) : Prop :=
  AsyncKeep k ∨ (∃ cap, 1 < cap ∧ cap < asyncLimit ∧ k = .dropping cap)

/-- The outcome set of a harness root. -/
def runs (k : QKind) (scripts : List (List Op)) (plan : List (Nat × Nat)) (mode : Mode) (o : Obs) : Prop :=
  outcomesP {} counterMaskModel henv (rootIO k scripts plan mode) o

/-! ## Statements -/

/-- `l₁` is a sub-multiset of `l₂`: each value occurs in `l₂` at least as often as in `l₁`. -/
def SubMulti (l₁ l₂ : List Val) : Prop := ∀ x ∈ l₁, l₁.count x ≤ l₂.count x

/-- Statement 1 for a family `fam`: no lost element. -/
def NoLoss (fam : QKind → Prop) : Prop :=
  ∀ k scripts plan, fam k → ∀ o, runs k scripts plan .cancelAll o →
    o.summary = .done (.succeeded .unit) → SubMulti (offeredOf o.out) (removedOf o.out)

/-- Statement 2: no duplicated or invented element. -/
def NoDup (fam : QKind → Prop) : Prop :=
  ∀ k scripts plan mode, fam k → ∀ o, runs k scripts plan mode o →
    SubMulti (removedOf o.out) (allOffers scripts)

/-- Statement 3: FIFO per remover and per producer. -/
def Fifo (fam : QKind → Prop) : Prop :=
  ∀ k scripts plan, fam k → (allOffers scripts).Nodup →
    ∀ o, runs k scripts plan .cancelAll o →
      ∀ c : Option Nat, ∀ s ∈ scripts, ((removedBy o.out c).filter (· ∈ offersOf s)).Sublist (offersOf s)

/-- Statement 4: canceling all fibers never hangs. -/
def NoDeadlock (fam : QKind → Prop) : Prop :=
  ∀ k scripts plan, fam k → ∀ o, runs k scripts plan .cancelAll o → o.summary = .done (.succeeded .unit)

/-- A run that stops `blocked` is allowed only when the queue has nothing to give: every recorded
offered element was removed, and every started `offer` returned. -/
def QuietBlock (o : Obs) : Prop :=
  o.summary = .blocked ∧ SubMulti (offeredOf o.out) (removedOf o.out) ∧ SubMulti (startedOf o.out) (offeredOf o.out)

/-- Statement 5: a waiting taker is woken when an element is there (no lost wakeup). -/
def TakerLiveness (fam : QKind → Prop) : Prop :=
  ∀ k scripts plan, fam k →
    (∀ s ∈ scripts, producer s ∨ consumer s) →
    (∀ p ∈ plan, ∀ s, scripts[p.2]? = some s → consumer s) →
    ∀ o, runs k scripts plan (.join ((List.range scripts.length).filter fun i =>
        match scripts[i]? with | some s => takes s | none => false)) o →
      o.summary = .done (.succeeded .unit) ∨ QuietBlock o

/-- The registered statements. -/
def concNoLoss : Prop := NoLoss ConcKeep
def asyncNoLoss : Prop := NoLoss AsyncKeep
def concNoDup : Prop := NoDup ConcAny
def asyncNoDup : Prop := NoDup AsyncAny
def concFifo : Prop := Fifo ConcAny
def asyncFifo : Prop := Fifo AsyncAny
def concNoDeadlock : Prop := NoDeadlock ConcAny
def asyncNoDeadlock : Prop := NoDeadlock AsyncAny
def concTakerLiveness : Prop := TakerLiveness ConcKeep
def asyncTakerLiveness : Prop := TakerLiveness AsyncKeep

/-- The twin pairs of statement 6: (`Concurrent`, `Async`) with the same factory arguments. -/
def twinPairs (cap : Nat) : List (QKind × QKind) :=
  [(.boundedConc cap, .bounded cap), (.droppingConc cap, .dropping cap), (.unboundedConc, .unbounded)]

/-- One side's results are results of the other side (same summary, same trace). -/
def SameResults (a b : QKind) (s : List Op) : Prop :=
  ∀ o, runs a [s] [] (.join [0]) o → ∃ o', runs b [s] [] (.join [0]) o' ∧ o'.summary = o.summary ∧ o'.out = o.out

/-- Statement 6: the `Concurrent` and the `Async` implementation of one factory agree on sequential
use (one fiber, all scripts, all schedules). -/
def twinSeq : Prop :=
  ∀ cap, 2 ≤ cap → cap < asyncLimit → ∀ p ∈ twinPairs cap, ∀ s,
    SameResults p.1 p.2 s ∧ SameResults p.2 p.1 s

end CatsEffectInLean.Props.Phase7.Queue

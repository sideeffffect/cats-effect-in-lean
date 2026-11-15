import CatsEffectInLean.Model.Bracket

/-!
# `std.Semaphore` (mirror; Phase 7, track S)

`Semaphore[IO](n)` (`std/shared/src/main/scala/cats/effect/std/Semaphore.scala`, `S` below) at
`v3.7.1`. There is one implementation (`impl`, `S:145-282`); `Semaphore.in` (`S:139-143`) builds
the same `impl` with `Ref.in`. `MapKSemaphore` (`S:284-297`) only maps each operation with a
natural transformation; it is not mirrored. The lazy cancelation design (canceled waiters stay in
the queue until a release reaches them) came with PR #4648 (merged 2026-08-22, in v3.7.1).

```scala
def apply[F[_]](n: Long)(implicit F: GenConcurrent[F, ?]): F[Semaphore[F]] = {   // S:130-133
  val impl = new impl[F](n)
  F.ref(impl.initialState).map(impl.semaphore)
}
case class Request(requested: Long, remaining: Long, gate: Deferred[F, Unit]) {     // S:151-157
  def sameAs(r: Request) = r.gate eq gate
  def sunk = requested - remaining
  def withRemaining(newN: Long) = copy(remaining = newN)
  def wait_ = gate.get
  def complete = gate.complete(())
}
case class State(permits: Long, waiting: Q[Request])                                 // S:163
private[this] def reclaim(req: Request): F[Unit] =                                   // S:168-177
  state.flatModify {
    case State(permits, waiting) =>
      waiting.dequeueOption match {
        case Some((head, tail)) if head sameAs req => State(permits, tail) -> releaseN(head.sunk)
        case _ => State(permits, waiting) -> F.unit
      }
  }
def acquireN(n: Long): F[Unit] = {                                                   // S:179-207
  requireNonNegative(n)
  if (n == 0) F.unit
  else
    F.uncancelable { poll =>
      F.deferred[Unit].flatMap { gate =>
        val req = Request(n, n, gate)
        val cleanup = req.complete.flatMap { won => if (won) reclaim(req) else releaseN(n) }
        val await = poll(req.wait_).onCancel(cleanup)
        state.modify {
          case State(permits, waiting) =>
            if (waiting.nonEmpty) State(0, waiting.enqueue(req)) -> await
            else {
              val diff = permits - n
              if (diff >= 0) State(diff, Q()) -> F.unit
              else State(0, req.withRemaining(diff.abs).pure[Q]) -> await
            }
        }.flatten
      }
    }
}
def releaseN(n: Long): F[Unit] = {                                                   // S:209-254
  requireNonNegative(n)
  @tailrec def fulfil(n, requests, wakeup) = {                                       // S:212-227
    val (req, tail) = requests.dequeue
    if (n < req.remaining) (0, req.withRemaining(req.remaining - n) +: tail, wakeup)
    else {
      val newN = n - req.remaining
      val newWakeup = wakeup.enqueue(req)
      if (tail.isEmpty || newN == 0) (newN, tail, newWakeup)
      else fulfil(newN, tail, newWakeup)
    }
  }
  if (n == 0) F.unit
  else
    state.flatModify {
      case State(permits, waiting) =>
        if (waiting.isEmpty) State(permits + n, waiting) -> F.unit
        else {
          val (newN, waitingNow, wakeup) = fulfil(n, waiting, Q())
          val wake = wakeup.traverse_ { req =>
            req.complete.flatMap { won => if (won) F.unit else releaseN(req.requested) } }
          val sweep = waitingNow.headOption.traverse_ { req =>
            req.gate.tryGet.flatMap { case Some(_) => reclaim(req); case None => F.unit } }
          State(newN, waitingNow) -> (wake *> sweep)
        }
    }
}
def available: F[Long] = state.get.map(_.permits)                                    // S:256
def count: F[Long] = state.get.map { case State(permits, waiting) =>                 // S:258-263
  if (waiting.nonEmpty) -waiting.foldMap(_.remaining) else permits }
def permit: Resource[F, Unit] =                                                      // S:265-266
  Resource.makeFull { (poll: Poll[F]) => poll(acquire) } { _ => release }
def tryAcquireN(n: Long): F[Boolean] = {                                             // S:268-277
  requireNonNegative(n)
  if (n == 0) F.pure(true)
  else state.modify { state =>
    val permits = state.permits
    if (permits >= n) state.copy(permits = permits - n) -> true else state -> false }
}
```

`acquire` = `acquireN(1)` (`S:76`), `release` = `releaseN(1)` (`S:103`), `tryAcquire` =
`tryAcquireN(1)` (`S:90`).

## The operations of `F = IO`

`F` is `IO.asyncForIO` (`IOAsync`, `core/shared/src/main/scala/cats/effect/IO.scala:1996-2180`,
`IO.scala` below):

* `F.ref(a)` = `IO.ref(a)` = `IO(Ref.unsafe(a))` (`IO.scala:2161`, `:1822`): one `Delay`;
  `F.deferred` = `IO.deferred` = `IO(new IODeferred)` (`IO.scala:2163`, `:1824`): one `Delay`.
* `Ref` = `SyncRef` (`kernel/jvm-native/src/main/scala/cats/effect/kernel/SyncRef.scala`): `get` =
  `F.delay(ar.get)` (`:30`); `modify` = `F.delay(spin)` (`:86-95`). One model step is atomic, so
  the CAS loop succeeds at once. `flatModify(f)` = `F.uncancelable(_ => F.flatten(modify(f)))`
  (`kernel/shared/src/main/scala/cats/effect/kernel/Ref.scala:123-124`).
* `flatten` (`F.flatten` and the `.flatten` syntax) = `flatMap(ffa)(fa => fa)` (cats-core 2.13.0
  `cats/FlatMap.scala:58-59`; `IOAsync` does not override it): one `FlatMap`.
* `Deferred` = `IODeferred` (`core/shared/src/main/scala/cats/effect/IODeferred.scala`): `get` =
  `cell.get()` (`:71`), read when the `IO` value is built (`IO.deferredGetOf`); `complete` (`:62-69`,
  `RtFn.deferredComplete`); `tryGet` = `IO { ... }` (`:73-79`).
* `F.unit` = `IO.unit` = `Pure(())` (`IO.scala:2020-2021`, `:1715-1720`); `F.pure` = `Pure`
  (`IO.scala:1640`); `F.uncancelable` = `Uncancelable` (`IO.scala:2095-2096`, `:1712-1713`);
  `onCancel` = `OnCancel` (`IO.scala:2059-2060`, `:590-591`); `poll(fa)` = `UnmaskRunLoop`
  (`IO.applyPoll`); `map` = `Map` (`IO.scala:579`); `flatMap` = `FlatMap`.
* `*>` = `F.productR` = `IO#productR` = `flatMap(_ => that)` (`IO.scala:2081-2082`, `:903-904`;
  `that` is built first).
* `wakeup.traverse_(f)` on a `scala.collection.immutable.Queue`: cats-core 2.13.0
  `cats/instances/queue.scala:136-138` with a `StackSafeMonad` (`IOAsync` is one) is
  `Traverse.traverseVoidDirectly` (`cats/Traverse.scala:299-309`): empty → `G.unit`; else
  `G.void(rest.foldLeft(f(first))((g, a) => G.productR(g)(f(a))))`. `f(a)` is called while the
  fold runs (strict). `G.void` = `IO#void` = `map(_ => ())` (`IO.scala:2152`, `:961-962`).
* `waitingNow.headOption.traverse_(f)` on an `Option`: the `Foldable` default
  (`cats/Foldable.scala:591-596`; `cats/instances/option.scala` overrides only `foldRight`,
  `:145-149`): `None` → `G.unit`; `Some(a)` → `G.map2Eval(f(a), Always(G.unit))((_, _) => ())`,
  and `IOAsync.map2Eval` (`IO.scala:2165-2171`) is `f(a).flatMap(_ => G.unit.map(_ => ()))`.
* `permit.use(f)`: `Resource.makeFull(acquire)(release)` = `Allocate(poll => acquire(poll).map(a =>
  (a, _ => release(a))))` (`kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala:942-944`,
  `:879-880`); `use(f)` = `fold(f, _.apply(_))` (`Resource.scala:207-208`); `fold` of an
  `Allocate` with an empty stack is `F.bracketFull(resource) { case (a, _) => onOutput(a) }
  { case ((_, release), outcome) => onRelease(release, ExitCase.fromOutcome(outcome)) }`
  (`Resource.scala:156-196`), and `F.bracketFull` = `IO.bracketFull` (track G mirror
  `Model/Bracket.lean`, `Bracket.bracketFullIO`).

## Encoding

* Closures `SL` (namespace `ns = 60`); each Scala lambda is one case, its captured values are its
  fields. User function ids are even; the mirror calls them through the dispatcher `uc`.
* The semaphore object (`new Semaphore[F] { ... }`, `S:167`) is the value `semV q`: a reference
  (`Val.fn`) to the library closure `SL.obj q`, where `q` is the `Ref` cell of the `State`. The
  operations capture the object (as the Scala lambdas capture `self`), not the cell. User code that
  holds a semaphore holds only the reference: `WellFormed` (`WF.avail`) does not let it reach the
  cell, so it cannot write the state (decision 58; Scala: `state` is private).
* `State(permits, waiting)` = `pair (nat permits) (listV reqs)`; a `Request` =
  `pair (pair (nat requested) (nat remaining)) (deferred gate)`. `Long` values are non-negative
  here (`requireNonNegative`, `S:148-149`): the model takes `n : Nat`.
* An `IO` held as a value (`await`, `F.unit`, the `releaseN(...)` that `modify` returns, `wake *>
  sweep`) is a descriptor `Val` (`cloVal ns 90..96`); `flattenK`/`thenK` rebuild the term.
* `count` is a `Long` that may be negative: `.int`.
-/

namespace CatsEffectInLean.Model.Semaphore

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of these closures (track S: 60..69). -/
def ns : Nat := 60

/-- Error code of an ill-typed argument (impossible in Scala). -/
def illCode : Nat := 999999

/-- The closures of the mirror. Fields: `q` the state cell, `s` the semaphore object (a closure
id, held as `Val.fn s`), `n` a number of permits, `g` a gate `Deferred`, `m pp` a poll, `f` a user
function, `d` a descriptor. -/
inductive SL where
  /-- The semaphore object `new Semaphore[F] { ... }` (`S:166-281`) over state cell `q`. A value. -/
  | obj (q : Nat)
  /-- `IO(Ref.unsafe(x))` thunk (`IO.scala:1822`). -/
  | newRef (x : Val)
  /-- `impl.semaphore` (`S:166`): `state => new Semaphore[F] {...}`. -/
  | mkSem
  /-- `poll => F.deferred[Unit].flatMap(gate => ...)` of `acquireN` (`S:184-185`). -/
  | acqBody (s n : Nat)
  /-- `IO(new IODeferred)` thunk (`IO.scala:1824`). -/
  | newDeferred
  /-- `gate => { val req = ...; val cleanup = ...; val await = ...; state.modify {...}.flatten }`
  (`S:185-205`). -/
  | acqGate (s n m pp : Nat)
  /-- The `modify` thunk of `acquireN` (`S:195-204`, `SyncRef.scala:86-95`). -/
  | modAcq (s n g m pp : Nat)
  /-- `fa => fa` of `flatten` (`cats/FlatMap.scala:58-59`); the argument is a descriptor. -/
  | flattenK
  /-- `won => if (won) reclaim(req) else releaseN(n)` of `cleanup` (`S:188-191`). -/
  | wonK (s n g : Nat)
  /-- `_ => F.flatten(modify(f))` of `flatModify` in `releaseN` (`Ref.scala:123-124`, `S:231`). -/
  | relBody (s n : Nat)
  /-- The `modify` thunk of `releaseN` (`S:231-253`). -/
  | modRel (s n : Nat)
  /-- `_ => that` of `productR` (`IO.scala:903-904`): `that` is the descriptor `d`. -/
  | thenK (d : Val)
  /-- `won => if (won) F.unit else releaseN(req.requested)` of `wake` (`S:238-241`). -/
  | wakeWon (s rq : Nat)
  /-- `tryGet` thunk of gate `g` (`IODeferred.scala:73-79`). -/
  | tryGet (g : Nat)
  /-- `{ case Some(_) => reclaim(req); case None => F.unit }` of `sweep` (`S:245-248`). -/
  | sweepSel (s g : Nat)
  /-- `a => G.unit.map(b => ())` of `IOAsync.map2Eval` (`IO.scala:2165-2171`) in the `Option`
  `traverse_` of `sweep`. -/
  | m2k
  /-- `_ => ()` (`void`, `IO.scala:961-962`; the `(_, _) => ()` of `traverse_`). -/
  | voidK
  /-- `_ => F.flatten(modify(f))` of `flatModify` in `reclaim` (`S:169`). -/
  | recBody (s g : Nat)
  /-- The `modify` thunk of `reclaim` (`S:169-177`). -/
  | modRec (s g : Nat)
  /-- `state.get` thunk (`SyncRef.scala:30`). -/
  | getThunk (s : Nat)
  /-- `_.permits` of `available` (`S:256`). -/
  | availK
  /-- The `map` function of `count` (`S:259-263`). -/
  | countK
  /-- The `modify` thunk of `tryAcquireN` (`S:272-276`). -/
  | modTry (s n : Nat)
  /-- The `Allocate` function of `permit`: `poll => poll(acquire).map(a => (a, _ => release(a)))`
  (`S:266`, `Resource.scala:942-944`). -/
  | permitAcq (s : Nat)
  /-- `a => (a, _ => release(a))` of `makeFull` (`Resource.scala:944`). -/
  | pairRel (s : Nat)
  /-- `_ => release(a)` of `makeFull` with `release = { _ => release }` (`S:266`): `releaseN(1)`. -/
  | relEc (s : Nat)
  /-- The `use` function of `fold` for an `Allocate`: `{ case (a, _) => stack match {...} }`
  (`Resource.scala:174-180`). `frame = false`: empty stack, `onOutput(a)` = `f(a)`; `frame =
  true`: one `map(_ => ())` frame (`Mutex.lock` is `....void`), so `onOutput(())`. -/
  | useOut (f : Nat) (frame : Bool)
  /-- The release function of `fold`: `{ case ((_, release), outcome) => onRelease(release,
  ExitCase.fromOutcome(outcome)) }` with `onRelease = _.apply(_)` (`Resource.scala:181-184`,
  `:207-208`, `:1229-1234`). -/
  | useRel
  /-- Public operations for user code (decision 58): `_ => op` closures that hold the semaphore
  object, as Scala code `x => s.op(...)`. `opNew k`: `_ => Semaphore[IO](k)`. -/
  | opNew (k : Nat)
  | opAcquireN (s n : Nat)
  | opReleaseN (s n : Nat)
  | opTryAcquireN (s n : Nat)
  | opAvailable (s : Nat)
  | opCount (s : Nat)
  /-- `_ => s.permit.use(f)`. -/
  | opPermitUse (s f : Nat)
  deriving DecidableEq, Repr

/-- `ExitCase.fromOutcome` (`Resource.scala:1229-1234`): `Succeeded`, `Errored(e)`, `Canceled`. -/
def exitCaseOf : Val → Val
  | .ocSucceeded _ => .ocSucceeded .unit
  | .ocErrored e => .ocErrored e
  | _ => .ocCanceled

def SL.toVal : SL → Val
  | .obj q => cloVal ns 0 [.ref q]
  | .newRef x => cloVal ns 1 [x]
  | .mkSem => cloVal ns 2 []
  | .acqBody s n => cloVal ns 3 [.fn s, .nat n]
  | .newDeferred => cloVal ns 4 []
  | .acqGate s n m pp => cloVal ns 5 [.fn s, .nat n, .poll m pp]
  | .modAcq s n g m pp => cloVal ns 6 [.fn s, .nat n, .deferred g, .poll m pp]
  | .flattenK => cloVal ns 7 []
  | .wonK s n g => cloVal ns 8 [.fn s, .nat n, .deferred g]
  | .relBody s n => cloVal ns 9 [.fn s, .nat n]
  | .modRel s n => cloVal ns 10 [.fn s, .nat n]
  | .thenK d => cloVal ns 11 [d]
  | .wakeWon s rq => cloVal ns 12 [.fn s, .nat rq]
  | .tryGet g => cloVal ns 13 [.deferred g]
  | .sweepSel s g => cloVal ns 14 [.fn s, .deferred g]
  | .m2k => cloVal ns 15 []
  | .voidK => cloVal ns 16 []
  | .recBody s g => cloVal ns 17 [.fn s, .deferred g]
  | .modRec s g => cloVal ns 18 [.fn s, .deferred g]
  | .getThunk s => cloVal ns 19 [.fn s]
  | .availK => cloVal ns 20 []
  | .countK => cloVal ns 21 []
  | .modTry s n => cloVal ns 22 [.fn s, .nat n]
  | .permitAcq s => cloVal ns 23 [.fn s]
  | .pairRel s => cloVal ns 24 [.fn s]
  | .relEc s => cloVal ns 25 [.fn s]
  | .useOut f fr => cloVal ns 26 [.fn f, .bool fr]
  | .useRel => cloVal ns 27 []
  | .opNew k => cloVal ns 40 [.nat k]
  | .opAcquireN s n => cloVal ns 41 [.fn s, .nat n]
  | .opReleaseN s n => cloVal ns 42 [.fn s, .nat n]
  | .opTryAcquireN s n => cloVal ns 43 [.fn s, .nat n]
  | .opAvailable s => cloVal ns 44 [.fn s]
  | .opCount s => cloVal ns 45 [.fn s]
  | .opPermitUse s f => cloVal ns 46 [.fn s, .fn f]

def SL.ofFields : Nat → List Val → Option SL
  | 0, [.ref q] => some (.obj q)
  | 1, [x] => some (.newRef x)
  | 2, [] => some .mkSem
  | 3, [.fn s, .nat n] => some (.acqBody s n)
  | 4, [] => some .newDeferred
  | 5, [.fn s, .nat n, .poll m pp] => some (.acqGate s n m pp)
  | 6, [.fn s, .nat n, .deferred g, .poll m pp] => some (.modAcq s n g m pp)
  | 7, [] => some .flattenK
  | 8, [.fn s, .nat n, .deferred g] => some (.wonK s n g)
  | 9, [.fn s, .nat n] => some (.relBody s n)
  | 10, [.fn s, .nat n] => some (.modRel s n)
  | 11, [d] => some (.thenK d)
  | 12, [.fn s, .nat rq] => some (.wakeWon s rq)
  | 13, [.deferred g] => some (.tryGet g)
  | 14, [.fn s, .deferred g] => some (.sweepSel s g)
  | 15, [] => some .m2k
  | 16, [] => some .voidK
  | 17, [.fn s, .deferred g] => some (.recBody s g)
  | 18, [.fn s, .deferred g] => some (.modRec s g)
  | 19, [.fn s] => some (.getThunk s)
  | 20, [] => some .availK
  | 21, [] => some .countK
  | 22, [.fn s, .nat n] => some (.modTry s n)
  | 23, [.fn s] => some (.permitAcq s)
  | 24, [.fn s] => some (.pairRel s)
  | 25, [.fn s] => some (.relEc s)
  | 26, [.fn f, .bool fr] => some (.useOut f fr)
  | 27, [] => some .useRel
  | 40, [.nat k] => some (.opNew k)
  | 41, [.fn s, .nat n] => some (.opAcquireN s n)
  | 42, [.fn s, .nat n] => some (.opReleaseN s n)
  | 43, [.fn s, .nat n] => some (.opTryAcquireN s n)
  | 44, [.fn s] => some (.opAvailable s)
  | 45, [.fn s] => some (.opCount s)
  | 46, [.fn s, .fn f] => some (.opPermitUse s f)
  | _, _ => none

def SL.id (l : SL) : Nat := 2 * valToNat l.toVal + 1
def SL.fn (l : SL) : Fn := .user l.id

def SL.ofId? (id : Nat) : Option SL :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then SL.ofFields tag fs else none
    | none => none
  else none

/-- The semaphore value over state cell `q`: a reference to the object closure. -/
def semV (q : Nat) : Val := .fn (SL.obj q).id

/-- The id of the semaphore object over cell `q`. -/
def semId (q : Nat) : Nat := (SL.obj q).id

/-- The state cell of a semaphore object id. -/
def semRef? (s : Nat) : Option Nat :=
  match SL.ofId? s with
  | some (.obj q) => some q
  | _ => none

/-! ## State -/

/-- A `Request(requested, remaining, gate)`. -/
def reqV (rq rm g : Nat) : Val := .pair (.pair (.nat rq) (.nat rm)) (.deferred g)

/-- A request: `(requested, remaining, gate)`. -/
def reqOf : Val → Option (Nat × Nat × Nat)
  | .pair (.pair (.nat rq) (.nat rm)) (.deferred g) => some (rq, rm, g)
  | _ => none

/-- `State(permits, waiting)`. -/
def stateV (p : Nat) (w : List (Nat × Nat × Nat)) : Val :=
  .pair (.nat p) (listV (w.map fun (rq, rm, g) => reqV rq rm g))

/-- The state of cell `q` in view `v`. -/
def stateOf (v : View) (q : Nat) : Option (Nat × List (Nat × Nat × Nat)) :=
  match v.refs[q]? with
  | some (.pair (.nat p) w) =>
    match unlistV w with
    | some l =>
      let rs := l.filterMap reqOf
      if rs.length = l.length then some (p, rs) else none
    | none => none
  | _ => none

/-- `fulfil(n, requests, wakeup)` (`S:212-227`), structural on the request list. Precondition
(`S:235`): `requests` is not empty. An empty list (impossible) gives `(n, [], wakeup)`. -/
def fulfil (n : Nat) : List (Nat × Nat × Nat) → List (Nat × Nat × Nat) → Nat × List (Nat × Nat × Nat) × List (Nat × Nat × Nat)
  | [], wakeup => (n, [], wakeup)
  | (rq, rm, g) :: tail, wakeup =>
    if n < rm then (0, (rq, rm - n, g) :: tail, wakeup)
    else
      let newN := n - rm
      let newWakeup := wakeup ++ [(rq, rm, g)]
      if tail.isEmpty || newN == 0 then (newN, tail, newWakeup)
      else fulfil newN tail newWakeup

/-! ## Descriptors of `IO` values held in values -/

/-- `F.unit`. -/
def dUnit : Val := cloVal ns 90 []
/-- `await = poll(req.wait_).onCancel(cleanup)` (`S:193`): `gate` was just made, so `get` read
`initial`. -/
def dAwait (s n g m pp : Nat) : Val := cloVal ns 91 [.fn s, .nat n, .deferred g, .poll m pp]
/-- `releaseN(k)` (the `F[Unit]` that `reclaim` returns, `S:173`). -/
def dRelease (s k : Nat) : Val := cloVal ns 92 [.fn s, .nat k]
/-- `wake *> sweep` (`S:237-251`) for the woken gates `wakeup` (requested, gate) and the head of
`waitingNow` (`some gate` or `none`). -/
def dWakeSweep (s : Nat) (wakeup : List (Nat × Nat)) (head : Option Nat) : Val :=
  cloVal ns 93 [.fn s, listV (wakeup.map fun (rq, g) => .pair (.nat rq) (.deferred g)),
    match head with | some g => .some (.deferred g) | none => .none]
/-- `sweep` (`S:244-249`). -/
def dSweep (s : Nat) (head : Option Nat) : Val :=
  cloVal ns 94 [.fn s, match head with | some g => .some (.deferred g) | none => .none]
/-- `f(req)` of `wake`: `req.complete.flatMap {...}` (`S:238-241`). -/
def dWakeOne (s rq g : Nat) : Val := cloVal ns 95 [.fn s, .nat rq, .deferred g]

/-! ## Terms -/

/-- `deferred.complete(x)` (`IODeferred.scala:62-69`). -/
def completeIO (d : Nat) (x : Val) : IO := .delay (.rt (.deferredComplete d x))

/-- `Semaphore[IO](k)` (`S:130-133`): `F.ref(State(k, Q())).map(impl.semaphore)`. -/
def newIO (k : Nat) : IO := .map (.delay (SL.newRef (stateV k [])).fn) SL.mkSem.fn

/-- `s.acquireN(n)` (`S:179-207`). -/
def acquireNIO (s n : Nat) : IO :=
  if n == 0 then .pure .unit else .uncancelable (SL.acqBody s n).fn

/-- `s.releaseN(n)` (`S:209-254`): `state.flatModify {...}` = `F.uncancelable(_ => F.flatten(modify(...)))`. -/
def releaseNIO (s n : Nat) : IO :=
  if n == 0 then .pure .unit else .uncancelable (SL.relBody s n).fn

/-- `reclaim(req)` (`S:168-177`), `req` named by its gate (`sameAs` compares gates). -/
def reclaimIO (s g : Nat) : IO := .uncancelable (SL.recBody s g).fn

/-- `s.tryAcquireN(n)` (`S:268-277`). -/
def tryAcquireNIO (s n : Nat) : IO :=
  if n == 0 then .pure (.bool true) else .delay (SL.modTry s n).fn

/-- `s.available` (`S:256`). -/
def availableIO (s : Nat) : IO := .map (.delay (SL.getThunk s).fn) SL.availK.fn

/-- `s.count` (`S:258-263`). -/
def countIO (s : Nat) : IO := .map (.delay (SL.getThunk s).fn) SL.countK.fn

/-- `s.permit.use(f)` (`S:265-266`, `Resource.scala:156-208`, `:942-944`): `IO.bracketFull`
(track G mirror). -/
def permitUseIO (s f : Nat) : IO :=
  Bracket.bracketFullIO (SL.permitAcq s).id (SL.useOut f false).id SL.useRel.id

/-- `cleanup` (`S:188-191`). -/
def cleanupIO (s n g : Nat) : IO := .flatMap (completeIO g .unit) (SL.wonK s n g).fn

/-- `f(req)` of `wake` (`S:238-241`). -/
def wakeOneIO (s rq g : Nat) : IO := .flatMap (completeIO g .unit) (SL.wakeWon s rq).fn

/-- `wakeup.traverse_(f)` (`traverseVoidDirectly`, `cats/Traverse.scala:299-309`). -/
def wakeIO (s : Nat) : List (Nat × Nat) → IO
  | [] => .pure .unit
  | (rq, g) :: rest =>
    .map (rest.foldl (fun acc (rq', g') => .flatMap acc (SL.thenK (dWakeOne s rq' g')).fn)
      (wakeOneIO s rq g)) SL.voidK.fn

/-- `sweep` (`S:244-249`): the `Option` `traverse_` (`cats/Foldable.scala:591-596`). -/
def sweepIO (s : Nat) : Option Nat → IO
  | none => .pure .unit
  | some g => .flatMap (.flatMap (.delay (SL.tryGet g).fn) (SL.sweepSel s g).fn) SL.m2k.fn

/-- The `IO` of a descriptor. -/
def descIO (d : Val) : IO :=
  match ofCloVal d with
  | some (60, 90, []) => .pure .unit
  | some (60, 91, [.fn s, .nat n, .deferred g, .poll m pp]) =>
    .onCancel (IO.applyPoll (IO.deferredGetOf g none) m pp) (cleanupIO s n g)
  | some (60, 92, [.fn s, .nat k]) => releaseNIO s k
  | some (60, 93, [.fn s, wk, hd]) =>
    let wakeup := ((unlistV wk).getD []).filterMap fun
      | .pair (.nat rq) (.deferred g) => some (rq, g)
      | _ => none
    let head := match hd with | .some (.deferred g) => some g | _ => none
    .flatMap (wakeIO s wakeup) (SL.thenK (dSweep s head)).fn
  | some (60, 94, [.fn s, hd]) =>
    sweepIO s (match hd with | .some (.deferred g) => some g | _ => none)
  | some (60, 95, [.fn s, .nat rq, .deferred g]) => wakeOneIO s rq g
  | _ => .error { code := illCode, kind := .fatal }

/-! ## The closures -/

private def ret (v : Val) : UserResult := { out := .ret v }
private def prog (p : IO) : UserResult := { out := .prog p }
def illTyped : UserResult := { out := .throw { code := illCode, kind := .fatal } }

/-- Run closure `l` on `arg` in view `v`. `uc` is the full dispatcher (user code and the other
mirrors): `useOut` calls the user function `f`, `useRel` applies the release function value. -/
def call (uc : Nat → Val → View → UserResult) (l : SL) (arg : Val) (v : View) : UserResult :=
  match l with
  | .obj _ => illTyped
  | .newRef x => { effects := [.allocRef x], out := .ret (.ref v.refs.length) }
  | .mkSem =>
    match arg with
    | .ref q => ret (semV q)
    | _ => illTyped
  | .acqBody s n =>
    match arg with
    | .poll m pp => prog (.flatMap (.delay SL.newDeferred.fn) (SL.acqGate s n m pp).fn)
    | _ => illTyped
  | .newDeferred => { effects := [.allocDeferred], out := .ret (.deferred v.deferreds.length) }
  | .acqGate s n m pp =>
    match arg with
    | .deferred g => prog (.flatMap (.delay (SL.modAcq s n g m pp).fn) SL.flattenK.fn)
    | _ => illTyped
  | .modAcq s n g m pp =>
    match semRef? s with
    | some q =>
      match stateOf v q with
      | some (permits, waiting) =>
        if !waiting.isEmpty then
          { effects := [.writeRef q (stateV 0 (waiting ++ [(n, n, g)]))], out := .ret (dAwait s n g m pp) }
        else if n ≤ permits then
          { effects := [.writeRef q (stateV (permits - n) [])], out := .ret dUnit }
        else
          { effects := [.writeRef q (stateV 0 [(n, n - permits, g)])], out := .ret (dAwait s n g m pp) }
      | none => illTyped
    | none => illTyped
  | .flattenK => prog (descIO arg)
  | .wonK s n g =>
    match arg with
    | .bool true => prog (reclaimIO s g)
    | .bool false => prog (releaseNIO s n)
    | _ => illTyped
  | .relBody s n => prog (.flatMap (.delay (SL.modRel s n).fn) SL.flattenK.fn)
  | .modRel s n =>
    match semRef? s with
    | some q =>
      match stateOf v q with
      | some (permits, []) =>
        { effects := [.writeRef q (stateV (permits + n) [])], out := .ret dUnit }
      | some (_, waiting) =>
        let (newN, waitingNow, wakeup) := fulfil n waiting []
        { effects := [.writeRef q (stateV newN waitingNow)],
          out := .ret (dWakeSweep s (wakeup.map fun (rq, _, g) => (rq, g)) (waitingNow.head?.map fun (_, _, g) => g)) }
      | none => illTyped
    | none => illTyped
  | .thenK d => prog (descIO d)
  | .wakeWon s rq =>
    match arg with
    | .bool true => prog (.pure .unit)
    | .bool false => prog (releaseNIO s rq)
    | _ => illTyped
  | .tryGet g => ret (match v.deferred g with | some x => .some x | none => .none)
  | .sweepSel s g =>
    match arg with
    | .some _ => prog (reclaimIO s g)
    | .none => prog (.pure .unit)
    | _ => illTyped
  | .m2k => prog (.map (.pure .unit) SL.voidK.fn)
  | .voidK => ret .unit
  | .recBody s g => prog (.flatMap (.delay (SL.modRec s g).fn) SL.flattenK.fn)
  | .modRec s g =>
    match semRef? s with
    | some q =>
      match stateOf v q with
      | some (permits, (rq, rm, g') :: tail) =>
        if g' == g then
          { effects := [.writeRef q (stateV permits tail)], out := .ret (dRelease s (rq - rm)) }
        else
          { effects := [.writeRef q (stateV permits ((rq, rm, g') :: tail))], out := .ret dUnit }
      | some (permits, []) =>
        { effects := [.writeRef q (stateV permits [])], out := .ret dUnit }
      | none => illTyped
    | none => illTyped
  | .getThunk s =>
    match semRef? s with
    | some q => ret (v.refs.getD q .unit)
    | none => illTyped
  | .availK =>
    match arg with
    | .pair (.nat p) _ => ret (.nat p)
    | _ => illTyped
  | .countK =>
    match arg with
    | .pair (.nat p) w =>
      match unlistV w with
      | some [] => ret (.int p)
      | some l => ret (.int (-(((l.filterMap reqOf).map fun (_, rm, _) => rm).foldl (· + ·) 0 : Nat)))
      | none => illTyped
    | _ => illTyped
  | .modTry s n =>
    match semRef? s with
    | some q =>
      match stateOf v q with
      | some (permits, waiting) =>
        if n ≤ permits then
          { effects := [.writeRef q (stateV (permits - n) waiting)], out := .ret (.bool true) }
        else
          { effects := [.writeRef q (stateV permits waiting)], out := .ret (.bool false) }
      | none => illTyped
    | none => illTyped
  | .permitAcq s =>
    match arg with
    | .poll m pp => prog (.map (IO.applyPoll (acquireNIO s 1) m pp) (SL.pairRel s).fn)
    | _ => illTyped
  | .pairRel s => ret (.pair arg (.fn (SL.relEc s).id))
  | .relEc s => prog (releaseNIO s 1)
  | .useOut f fr =>
    match arg with
    | .pair a _ => uc f (if fr then .unit else a) v
    | _ => illTyped
  | .useRel =>
    match arg with
    | .pair (.pair _ (.fn r)) oc => uc r (exitCaseOf oc) v
    | _ => illTyped
  | .opNew k => prog (newIO k)
  | .opAcquireN s n => prog (acquireNIO s n)
  | .opReleaseN s n => prog (releaseNIO s n)
  | .opTryAcquireN s n => prog (tryAcquireNIO s n)
  | .opAvailable s => prog (availableIO s)
  | .opCount s => prog (countIO s)
  | .opPermitUse s f => prog (permitUseIO s f)
end CatsEffectInLean.Model.Semaphore

import CatsEffectInLean.Std.Supervisor

/-!
# `std.Dispatcher` (mirror; Phase 7, track P7D)

`DP` = `std/shared/src/main/scala/cats/effect/std/Dispatcher.scala` at `v3.7.1`;
`UU` = `std/shared/src/main/scala/cats/effect/std/UnsafeUnbounded.scala`;
`R` = `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`;
`IO.scala` = `core/shared/src/main/scala/cats/effect/IO.scala`; cats-core 2.13.0 (`cats/...`).
The `Supervisor` calls use track V's mirror `Std/Supervisor.lean` (`useIO`, `superviseIO`).

## Scope

`Dispatcher.parallel(await)` = `impl(true, await, true)` (`DP:165-166`) and
`Dispatcher.sequential(await)` = `impl(false, await, false)` (`DP:201-202`); the overloads without
`await` (`DP:121`, `:128`) and the deprecated `apply` (`DP:114`) pass `false`.
`sequentialCancelable` (`DP:205-207`, `Executor.sequential` `DP:509-613`) is `private[std]` and only
the Cats Effect tests call it: not reachable through the public API, not mirrored.

## `Resource` fold (`R:156-196`) of `impl(...).use(f)` with `F = IO`

`R#fold` is plain Scala on `Bind`/`Pure`; only `Eval` (`fa.flatMap(a => continue(pure(a), stack))`)
and `Allocate` (`F.bracketFull(resource)(...)(...)`) make `IO` nodes. `map`/`flatMap`/`flatMapN`
(`flatMap2`, `cats/syntax/TupleSemigroupalSyntax.scala:43`) and `replicateA` (`Resource` is a
`StackSafeMonad`, `R:1566`; `traverse` left to right) only add `Bind`/`Pure`. So the fold is the
nesting, in acquire order:

1. `Supervisor[F](await, checkRestart = always)` (`DP:250-254`): `Supervisor.useIO aw always`.
2. `Resource.make(Concurrent[F].deferred[Unit])(_.complete(()).void)` (`DP:260`).
3. `Resource.make(Sync[F].delay(new AtomicBoolean(false)))(doneR => Sync[F].delay(doneR.set(true)))`
   (`DP:257-258`).
4. The executor (`DP:263-269`): `parallel` → `Executor.parallel(await)` = `Supervisor[F](await)`
   (`DP:615-621`, `checkRestart = None`); `sequential` → `Resource.pure(Executor.inplace)` (no node).
5. For each worker `i < n` (`n = Cpus` for `parallel`, `1` for `sequential`; `DP:274-279`):
   `Worker.apply` = `Supervisor[F](false)` then `Resource.make(initF)(w => Sync[F].delay(w.queue
   .unsafeOffer(PoisonPill())))` (`DP:475-488`).
6. `evalMap(workers => Async[F].executionContext.flatMap(ec => launchAll.as(dispatcher)))`
   (`DP:281-287`): `Eval` = `fa.flatMap(a => continue(Resource.pure(a), Nil))` = `fa.flatMap(f)`.

`Resource.make(acquire)(release)` = `Allocate(_ => acquire.map(a => a -> release(a)).map { case (a,
release) => (a, (_: ExitCase) => release) })` (`R:826-831`, `:849-850`, `:879-880`, `:900-902`).
The `use` continuation of `bracketFull` is `continue(head(a), tail)` (`R:175-180`); the release is
`onRelease(release, ExitCase.fromOutcome(outcome))` = `release(exitCase)` (`R:181-184`, `:207-208`;
track V's closure `Supervisor.SLam.relK`).

## Impure code

`unsafeToFutureCancelable`, the returned `cancel` and `unsafeRunAndForget` are impure. The mirror
runs each call as **one** `IO.delay` thunk (`submitIO`, `cancelIO`): one atomic step of the caller
thread. In the difftest the Scala program calls them in an `IO(...)` thunk too. `Promise`/`Future`
are `Ref` cells (`pair forget result`); `Future#value` reads the cell. `unsafeRunAndForget`
registers `onComplete { case Failure(ex) => reportFailure(ex) }` on the parasitic EC (`DP:85-89`):
completing the promise with a failure then runs `ec.reportFailure(ex)` (`DP:374-375`) at once
(`UserEffect.report`). `Promise#success`/`failure` on a completed promise throws
`IllegalStateException` (`trySuccess` is not used).

`ThreadLocalRandom.current().nextInt(Cpus)` (`DP:327`) is an input: the cell `ws` holds the list of
worker choices; each `parallel` registration takes the head (`0` when the list is empty), modulo `n`.

## Encoding

* Registration (`DP:393-401`): `Primary(stateR)` = `left (ref st)`, `Finalizer(action)` =
  `right action` (a descriptor), `PoisonPill()` = `none`.
* `RegState` (`DP:384-391`) in cell `st`: `null` = `unit`, `Unstarted(action)` = `left action`,
  `Running(cancel)` = `right cancel`, `CancelRequested(latch)` = `some (ref p)`, `Completed` = `none`.
* `UnsafeAsyncQueue` (`DP:627-655`) = one cell `q` holding `pair buffer latch`: the `UnsafeUnbounded`
  buffer as a FIFO list (`UU:38-86`; one model step is atomic, so `take` throws `FailureSignal` only
  when the list is empty) and `latchR` (`none` = `null`, `cont s` = the callback `k` of the `cont`
  with cell `s`).
* The dispatcher object is the closure reference `Val.fn (DL.obj c).id` (odd id, decision 58):
  `c = listV [bool parallel, ref doneR, ref ws, nat n, nat v, listV queues]`. A call with
  `pair (nat 0) src` is `IO(unsafeToFutureCancelable(fa))`, with `pair (nat 1) src`
  `IO(unsafeRunAndForget(fa))` (the `IO(...)` is the caller's). The result of a submission is
  `pair (ref result) cancelRef`, where `cancelRef = Val.fn (DL.cancelObj c st).id`; a call of
  `cancelRef` (any argument) is `IO(cancel())`, its result `pair (ref latch) unit`.
* A worker is `w = listV [ref q, ref wd, sup wsup, ex, deferred latch, nat v]` (`DP:403-409`):
  queue, worker `doneR`, the worker's `Supervisor(false)`, the executor (`none` = `inplace`,
  `some sup` = the `parallel` executor supervisor), `terminationLatch`, variant.
* An `IO` that Scala holds as a value is a descriptor (`E`, namespace `effNs`); `eIO` rebuilds it.

## Variants (`v ≠ 0` is not Cats Effect code)

Fixed twins (decision 39): `30` (CE-0090): the `Worker` finalizer sets the dispatcher `doneR`
before it offers the `PoisonPill`; `31` (CE-0091): after the pill the `Worker` finalizer waits
until the worker has taken it (so the worker hands every earlier registration to the executor
while the executor is still open; for `parallel` only: with `sequential` it would wait for the
queued effects instead of canceling them); `32` = `30` + `31`. The others are wrong functions for the battery
(decision 63): `1`/`2`/`3`/`4` `unsafeToFutureCancelable` raises / never returns / drops (returns
a future, offers nothing) / doubles (offers a second registration of the same effect);
`5`/`6`/`7`/`8` the cancel action raises / never returns / drops (returns a completed future,
changes nothing) / doubles (cancels twice: the effect of a `Running` cancel is submitted twice);
`9`/`10`/`11`/`12` `unsafeRunAndForget` raises / never returns / drops / doubles; `13`/`14` the
factory raises / never returns (`use` fails or hangs before the body); `15` the release drops
(no `PoisonPill`, `doneR` never set); `16` the factory does not await (`await` is ignored: always
`false`); `18` `sequential` takes the `parallel` executor (effects overlap); `19`
`unsafeToFutureCancelable` skips the closed check (`DP:293-295`). `20` the factory always awaits (`await = false` acts
as `true`).
-/

namespace CatsEffectInLean.Std.Dispatcher

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std.Supervisor (Sup supVal superviseIO useIO supOf? snapVal dsnapVal dsnapOf)

/-- The namespace of the closures (track P7D, Phase 7: namespaces 90..99). -/
def ns : Nat := 90
/-- The namespace of the descriptor codes. -/
def effNs : Nat := 91

/-- `IllegalStateException("Dispatcher already closed")` (`DP:294`). -/
def iseErr : Err := { code := 9000001 }
/-- `AssertionError` of the worker (`DP:310`, `:436`, `:444`, `:451`). -/
def aeErr : Err := { code := 9000002 }
/-- `IllegalStateException("Promise already completed.")` of `Promise#complete`. -/
def promErr : Err := { code := 9000003 }
/-- `FailureSignal` of `UnsafeUnbounded.take` (`UU:83`, `FailureSignal.scala:19`): `NonFatal`. -/
def signalErr : Err := { code := 9000004 }
/-- An argument of the wrong shape: impossible in a well-typed Scala program. -/
def illErr : Err := { code := 999999, kind := .fatal }
/-- The error of the battery variants that raise (not Cats Effect code). -/
def battErr : Err := { code := 9000010 }

/-! ## Values -/

/-- The dispatcher fields captured by the dispatcher object and the cancel actions. -/
structure DC where
  par : Bool
  dn : Nat
  ws : Nat
  n : Nat
  v : Nat
  qs : List Nat
  deriving DecidableEq, Repr

def DC.toVal (c : DC) : Val :=
  listV [.bool c.par, .ref c.dn, .ref c.ws, .nat c.n, .nat c.v, listV (c.qs.map .ref)]

def refsOf : List Val → Option (List Nat)
  | [] => some []
  | .ref r :: xs => (refsOf xs).map (r :: ·)
  | _ => none

def DC.ofVal? (x : Val) : Option DC :=
  match unlistV x with
  | some [.bool par, .ref dn, .ref ws, .nat n, .nat v, qs] =>
    match (unlistV qs).bind refsOf with
    | some qs => some { par, dn, ws, n, v, qs }
    | none => none
  | _ => none

/-- A worker (`DP:403-409`). -/
structure W where
  q : Nat
  wd : Nat
  sup : Sup
  ex : Option Sup
  lt : Nat
  v : Nat
  deriving DecidableEq, Repr

def W.toVal (w : W) : Val :=
  listV [.ref w.q, .ref w.wd, w.sup.toVal, (match w.ex with | some s => .some s.toVal | none => .none),
    .deferred w.lt, .nat w.v]

def W.ofVal? (x : Val) : Option W :=
  match unlistV x with
  | some [.ref q, .ref wd, s, ex, .deferred lt, .nat v] =>
    match Sup.ofVal? s with
    | some sup =>
      match ex with
      | .none => some { q, wd, sup, ex := none, lt, v }
      | .some e => (Sup.ofVal? e).map fun es => { q, wd, sup, ex := some es, lt, v }
      | _ => none
    | none => none
  | _ => none

/-- The empty queue cell. -/
def emptyQ : Val := .pair .unit .none

/-- A promise cell: `forget` (an `onComplete` that reports a failure is registered) and the result. -/
def promV (forget : Bool) (r : Val) : Val := .pair (.bool forget) r

/-! ## Descriptors -/

/-- `IO` values that Scala code holds (namespace `effNs`). `src` is a source code: a descriptor of
this mirror, of `Supervisor`, or of the caller (`ioOf`). -/
inductive E where
  /-- The `promisory` (`DP:300-321`) of cell `st`, effect `src`, promise `res`. -/
  | prom (st : Nat) (src : Val) (res : Nat)
  /-- `completeState` (`DP:302-315`). -/
  | cst (st : Nat)
  /-- `Worker#run` (`DP:411-470`). -/
  | run (w : Val)
  /-- `cancelF.guarantee(Sync[F].delay { latch.success(()); () })` (`DP:426-429`). -/
  | cancelG (cf : Val) (p : Nat)
  /-- `Sync[F].delay { latch.success(()); () }` (`DP:426-429`). -/
  | succ (p : Nat)
  /-- `fiber.cancel` of an `IOFiber`, read when `_cancel` held `snap` (`DP:619`). -/
  | fibCancel (t : Nat) (snap : Val)
  /-- `d.get` of `Executor.inplace`, read when the cell held `snap` (`DP:503`). -/
  | dget (d : Nat) (snap : Val)
  /-- `registerCancel(cf) *> task` of `Executor.inplace` (`DP:503`). -/
  | regThen (w : Val) (st : Nat) (u cf task : Val)
  /-- `d.complete(()).void` (`DP:503`). -/
  | dcomplete (d : Nat)
  /-- `F.unit`. -/
  | unit
  /-- `supervisor.supervise(cancelF.guarantee(...)).void` (`DP:425-430`). -/
  | supVoid (s : Val) (cf : Val) (p : Nat)
  /-- `Sync[F].delay(latch.success(())).void` (`DP:454`). -/
  | succVoid (p : Nat)
  /-- `executor(action)(registerCancel)` (`DP:417-448`). -/
  | exec (w : Val) (st : Nat) (u : Val)
  /-- `throw new AssertionError(...)` inside `Sync[F].defer` (`DP:436`, `:444`, `:451`). -/
  | raise (e : Err)
  /-- `Sync[F].delay(doneR.set(true))` (`DP:258`). -/
  | setTrue (r : Nat)
  /-- `Sync[F].delay(w.queue.unsafeOffer(PoisonPill()))` (`DP:487`); `dn` for the fixed twin. -/
  | pill (q dn v : Nat)
  deriving DecidableEq, Repr

def E.toVal : E → Val
  | .prom st src res => cloVal effNs 0 [.ref st, src, .ref res]
  | .cst st => cloVal effNs 1 [.ref st]
  | .run w => cloVal effNs 2 [w]
  | .cancelG cf p => cloVal effNs 3 [cf, .ref p]
  | .succ p => cloVal effNs 4 [.ref p]
  | .fibCancel t snap => cloVal effNs 5 [.fiber t, snap]
  | .dget d snap => cloVal effNs 6 [.deferred d, snap]
  | .regThen w st u cf task => cloVal effNs 7 [w, .ref st, u, cf, task]
  | .dcomplete d => cloVal effNs 8 [.deferred d]
  | .unit => cloVal effNs 9 []
  | .supVoid s cf p => cloVal effNs 10 [s, cf, .ref p]
  | .succVoid p => cloVal effNs 11 [.ref p]
  | .exec w st u => cloVal effNs 12 [w, .ref st, u]
  | .raise e => cloVal effNs 13 [.err e]
  | .setTrue r => cloVal effNs 14 [.ref r]
  | .pill q dn v => cloVal effNs 15 [.ref q, .ref dn, .nat v]

def E.ofVal? (c : Val) : Option E :=
  match ofCloVal c with
  | some (k, tag, fs) =>
    if k != effNs then none else
    match tag, fs with
    | 0, [.ref st, src, .ref res] => some (.prom st src res)
    | 1, [.ref st] => some (.cst st)
    | 2, [w] => some (.run w)
    | 3, [cf, .ref p] => some (.cancelG cf p)
    | 4, [.ref p] => some (.succ p)
    | 5, [.fiber t, snap] => some (.fibCancel t snap)
    | 6, [.deferred d, snap] => some (.dget d snap)
    | 7, [w, .ref st, u, cf, task] => some (.regThen w st u cf task)
    | 8, [.deferred d] => some (.dcomplete d)
    | 9, [] => some .unit
    | 10, [s, cf, .ref p] => some (.supVoid s cf p)
    | 11, [.ref p] => some (.succVoid p)
    | 12, [w, .ref st, u] => some (.exec w st u)
    | 13, [.err e] => some (.raise e)
    | 14, [.ref r] => some (.setTrue r)
    | 15, [.ref q, .ref dn, .nat v] => some (.pill q dn v)
    | _, _ => none
  | none => none

/-! ## Closures -/

/-- The lambdas (library closures, odd ids, namespace `ns`). `v` is the variant. -/
inductive DL where
  /-- `Some((_: Outcome[F, Throwable, ?]) => true)` (`DP:250`). -/
  | always
  /-- `supervisor => ...` after the outer `Supervisor` (`DP:254-262`): the `Allocate` of
  `awaitTermination`. `f` is the `use` function; `n` workers. -/
  | kOuter (par aw : Bool) (n v f : Nat) (cs : Val)
  /-- `_ => Concurrent[F].deferred[Unit].map(f1).map(f2)` of `Resource.make` (`DP:260`). -/
  | acqLatch
  /-- `a => a -> release(a)`, `release = _.complete(()).void` (`DP:260`, `R:902`). -/
  | pairLatch
  /-- `{ case (a, release) => (a, (_: ExitCase) => release) }` (`R:828-830`). -/
  | pairRel
  /-- `(_: ExitCase) => release` (`R:830`). -/
  | constRel (rel : Val)
  /-- The `use` of `awaitTermination` (`R:175-180`): the `Allocate` of `termination`. -/
  | kLatch (os : Val) (par aw : Bool) (n v f : Nat) (cs : Val)
  /-- The thunk of `new AtomicBoolean(false)` (`DP:257`). -/
  | newBool
  /-- `_ => Sync[F].delay(new AtomicBoolean(false)).map(f1).map(f2)` (`DP:257`). -/
  | acqTerm
  /-- `a => a -> release(a)`, `release = doneR => Sync[F].delay(doneR.set(true))` (`DP:258`). -/
  | pairTerm
  /-- The thunk of `doneR.set(true)` (`DP:258`). -/
  | setTrue (r : Nat)
  /-- The `use` of `termination` (`DP:262-273`): the executor, then the workers. -/
  | kTerm (os : Val) (lt : Nat) (par aw : Bool) (n v f : Nat) (cs : Val)
  /-- `supervisor => new Executor { ... }` of `Executor.parallel` (`DP:616`), then the workers. -/
  | kExec (os : Val) (lt dn : Nat) (n v f : Nat) (cs : Val)
  /-- `supervisor => Resource.make(initF)(...)` of `Worker.apply` (`DP:479`): worker `i`. -/
  | kWSup (os : Val) (ex : Val) (lt dn : Nat) (par : Bool) (n v f : Nat) (ws : Val) (cs : Val)
  /-- `_ => initF.map(f1).map(f2)` of the worker `Resource.make` (`DP:480-487`). -/
  | acqWorker (sup ex : Val) (lt dn v : Nat)
  /-- The thunk of `initF` (`DP:480-485`): a new queue and a new worker `doneR`. -/
  | newWorker (sup ex : Val) (lt v : Nat)
  /-- `w => w -> release(w)`, `release = w => Sync[F].delay(w.queue.unsafeOffer(PoisonPill()))`
  (`DP:487`). `dn` is used only by the fixed twin (`v = 30`). -/
  | pairWorker (dn : Nat)
  /-- The thunk of `w.queue.unsafeOffer(PoisonPill())` (`DP:487`). -/
  | pill (q dn v : Nat)
  /-- The `use` of worker `i`'s `Resource.make` (`R:175-180`): the next worker, or the `evalMap`. -/
  | kWorker (os : Val) (ex : Val) (lt dn : Nat) (par : Bool) (n v f : Nat) (ws : Val) (cs : Val)
  /-- `ec => launchAll.as(new Dispatcher { ... })` (`DP:282-287`). -/
  | kEc (os : Val) (ws : Val) (dn : Nat) (par : Bool) (n v : Nat) (cs : Val)
  /-- `_ => supervisor.supervise(workers(i).run)` of `traverse_` (`DP:283-285`). -/
  | thenLaunch (os w : Val)
  /-- `_ => x`. -/
  | constV (x : Val)
  /-- The dispatcher object (`DP:287-376`). -/
  | obj (c : Val)
  /-- The thunk of `IO(unsafeToFutureCancelable(fa))` (`forget = false`) or
  `IO(unsafeRunAndForget(fa))` (`DP:288-372`, `:85-89`). -/
  | submit (c : Val) (src : Val) (forget : Bool)
  /-- The cancel action `cancel _` (`DP:340-366`) of cell `st`. -/
  | cancelObj (c : Val) (st : Nat)
  /-- The thunk of `IO(cancel())` (`DP:340-364`). -/
  | cancelThunk (c : Val) (st : Nat)
  /-- `poll => poll(fe.guarantee(completeState)).redeemWith(...).void` (`DP:300-321`). -/
  | promBody (st : Nat) (src : Val) (res : Nat)
  /-- The thunk of `completeState` (`DP:302-315`). -/
  | cstThunk (st : Nat)
  /-- `_.fold(recover, bind)` of `redeemWith` (`IO.scala:724-725`) with `recover = e =>
  Sync[F].delay(result.failure(e))`, `bind = a => Sync[F].delay(result.success(a))` (`DP:317-319`). -/
  | redeemK (res : Nat)
  /-- The thunk of `result.failure(e)` / `result.success(a)` (`DP:318-319`); `x` = `left (err e)`
  or `right a`. -/
  | complete (res : Nat) (x : Val)
  /-- The thunk of `latch.success(()); ()` (`DP:306`, `:427`, `:454`). -/
  | succThunk (p : Nat)
  /-- The thunk of `doneR.get()` of the worker (`DP:469`). -/
  | wdGet (wd : Nat)
  /-- `if (_) terminationLatch.get >> Spawn[F].cede else step >> run` (`DP:469`). -/
  | runSel (w : Val)
  /-- `_ => Spawn[F].cede` of `>>` (`DP:469`). -/
  | thenCede
  /-- `_ => run` of `>>` (`DP:469`). -/
  | thenRun (w : Val)
  /-- `reg => ...` of `step` (`DP:412-463`). -/
  | stepSel (w : Val)
  /-- The thunk of `Sync[F].defer { reg.stateR.get() match ... }` (`DP:414-456`). -/
  | primThunk (w : Val) (st : Nat)
  /-- `ioa => ioa` of `flatten` in `IO.defer` (`IO.scala:1296-1297`, `:472`), on a descriptor. -/
  | flattenK
  /-- The thunk of `Sync[F].defer { if (CAS(u, Running(cancelF))) ... }` (`DP:418-447`). -/
  | regThunk (w : Val) (st : Nat) (u cf : Val)
  /-- `cancelF => Sync[F].defer {...}` = `registerCancel` (`DP:417-448`) applied to `fiber.cancel`
  of `Executor.parallel` (`DP:619`). -/
  | regFib (w : Val) (st : Nat) (u : Val)
  /-- `d => (registerCancel(d.get) *> task).guarantee(d.complete(()).void)` (`DP:502-504`). -/
  | inplK (w : Val) (st : Nat) (u task : Val)
  /-- `_ => task` of `*>` (`DP:503`). -/
  | thenSrc (task : Val)
  /-- `_ => ()` of `voidError` = `handleError(_ => ())` (`cats/ApplicativeError.scala:126`,
  `IO.scala:532-533`, `:2029-2030`): `t => IO.pure(())`. -/
  | unitK
  /-- The thunk of `doneR.set(true)` of the worker (`DP:462`). -/
  | wdSet (wd : Nat)
  /-- The `cont` body of `UnsafeAsyncQueue.take` (`DP:638-653`); gets `cont s`. -/
  | takeBody (q : Nat)
  /-- The thunk of `buffer.take()` (`DP:641`, `UU:52-86`). -/
  | bufTake (q : Nat)
  /-- `_ => setLatchG *> (takeG <* unsetLatchG).handleErrorWith {...}` (`DP:645-649`). -/
  | h1 (q s : Nat)
  /-- The thunk of `latchR.set(k)` (`DP:642`). -/
  | setLatch (q s : Nat)
  /-- `_ => (takeG <* unsetLatchG).handleErrorWith {...}` of `*>` (`DP:646`). -/
  | thenH (q s : Nat)
  /-- `a => unsetLatchG.as(a)` of `<*` (`IO.scala:900-901`). -/
  | keepK (q : Nat)
  /-- The thunk of `latchR.lazySet(null)` (`DP:643`). -/
  | unsetLatch (q : Nat)
  /-- `_ => get *> unsetLatchG *> lift(take)` (`DP:646-647`). -/
  | h2 (q s : Nat)
  /-- `_ => unsetLatchG` of the first `*>` (`DP:647`). -/
  | thenUnset (q : Nat)
  /-- `_ => lift(take)` of the second `*>` (`DP:647`). -/
  | thenTake (q : Nat)
  /-- `d => f(d)`: `onOutput` = the `use` function, after the `Eval` of `evalMap`
  (`R:191-192`, `:186-188`). -/
  | useOut (f : Nat)
  /-- Fixed twins 31, 32 (not Cats Effect code): `_ => wait until the worker `doneR` is set`. -/
  | waitWd (wd : Nat)
  /-- Fixed twins 31, 32 (not Cats Effect code): `b => if (b) unit else cede >> wait`. -/
  | selWd (wd : Nat)
  deriving DecidableEq, Repr

def DL.toVal : DL → Val
  | .always => cloVal ns 0 []
  | .kOuter par aw n v f cs => cloVal ns 1 [.bool par, .bool aw, .nat n, .nat v, .fn f, cs]
  | .acqLatch => cloVal ns 2 []
  | .pairLatch => cloVal ns 3 []
  | .pairRel => cloVal ns 4 []
  | .constRel rel => cloVal ns 5 [rel]
  | .kLatch os par aw n v f cs => cloVal ns 6 [os, .bool par, .bool aw, .nat n, .nat v, .fn f, cs]
  | .newBool => cloVal ns 7 []
  | .acqTerm => cloVal ns 8 []
  | .pairTerm => cloVal ns 9 []
  | .setTrue r => cloVal ns 10 [.ref r]
  | .kTerm os lt par aw n v f cs => cloVal ns 11 [os, .deferred lt, .bool par, .bool aw, .nat n, .nat v, .fn f, cs]
  | .kExec os lt dn n v f cs => cloVal ns 12 [os, .deferred lt, .ref dn, .nat n, .nat v, .fn f, cs]
  | .kWSup os ex lt dn par n v f ws cs => cloVal ns 13 [os, ex, .deferred lt, .ref dn, .bool par, .nat n, .nat v, .fn f, ws, cs]
  | .acqWorker sup ex lt dn v => cloVal ns 14 [sup, ex, .deferred lt, .ref dn, .nat v]
  | .newWorker sup ex lt v => cloVal ns 15 [sup, ex, .deferred lt, .nat v]
  | .pairWorker dn => cloVal ns 16 [.ref dn]
  | .pill q dn v => cloVal ns 17 [.ref q, .ref dn, .nat v]
  | .kWorker os ex lt dn par n v f ws cs => cloVal ns 18 [os, ex, .deferred lt, .ref dn, .bool par, .nat n, .nat v, .fn f, ws, cs]
  | .kEc os ws dn par n v cs => cloVal ns 19 [os, ws, .ref dn, .bool par, .nat n, .nat v, cs]
  | .thenLaunch os w => cloVal ns 20 [os, w]
  | .constV x => cloVal ns 21 [x]
  | .obj c => cloVal ns 23 [c]
  | .submit c src forget => cloVal ns 24 [c, src, .bool forget]
  | .cancelObj c st => cloVal ns 25 [c, .ref st]
  | .cancelThunk c st => cloVal ns 26 [c, .ref st]
  | .promBody st src res => cloVal ns 27 [.ref st, src, .ref res]
  | .cstThunk st => cloVal ns 28 [.ref st]
  | .redeemK res => cloVal ns 29 [.ref res]
  | .complete res x => cloVal ns 30 [.ref res, x]
  | .succThunk p => cloVal ns 31 [.ref p]
  | .wdGet wd => cloVal ns 32 [.ref wd]
  | .runSel w => cloVal ns 33 [w]
  | .thenCede => cloVal ns 34 []
  | .thenRun w => cloVal ns 35 [w]
  | .stepSel w => cloVal ns 36 [w]
  | .primThunk w st => cloVal ns 37 [w, .ref st]
  | .flattenK => cloVal ns 38 []
  | .regThunk w st u cf => cloVal ns 39 [w, .ref st, u, cf]
  | .regFib w st u => cloVal ns 40 [w, .ref st, u]
  | .inplK w st u task => cloVal ns 41 [w, .ref st, u, task]
  | .thenSrc task => cloVal ns 42 [task]
  | .unitK => cloVal ns 43 []
  | .wdSet wd => cloVal ns 44 [.ref wd]
  | .takeBody q => cloVal ns 45 [.ref q]
  | .bufTake q => cloVal ns 46 [.ref q]
  | .h1 q s => cloVal ns 47 [.ref q, .cont s]
  | .setLatch q s => cloVal ns 48 [.ref q, .cont s]
  | .thenH q s => cloVal ns 49 [.ref q, .cont s]
  | .keepK q => cloVal ns 50 [.ref q]
  | .unsetLatch q => cloVal ns 51 [.ref q]
  | .h2 q s => cloVal ns 52 [.ref q, .cont s]
  | .thenUnset q => cloVal ns 53 [.ref q]
  | .thenTake q => cloVal ns 54 [.ref q]
  | .useOut f => cloVal ns 55 [.fn f]
  | .waitWd wd => cloVal ns 56 [.ref wd]
  | .selWd wd => cloVal ns 57 [.ref wd]

def DL.ofFields : Nat → List Val → Option DL
  | 0, [] => some .always
  | 1, [.bool par, .bool aw, .nat n, .nat v, .fn f, cs] => some (.kOuter par aw n v f cs)
  | 2, [] => some .acqLatch
  | 3, [] => some .pairLatch
  | 4, [] => some .pairRel
  | 5, [rel] => some (.constRel rel)
  | 6, [os, .bool par, .bool aw, .nat n, .nat v, .fn f, cs] => some (.kLatch os par aw n v f cs)
  | 7, [] => some .newBool
  | 8, [] => some .acqTerm
  | 9, [] => some .pairTerm
  | 10, [.ref r] => some (.setTrue r)
  | 11, [os, .deferred lt, .bool par, .bool aw, .nat n, .nat v, .fn f, cs] => some (.kTerm os lt par aw n v f cs)
  | 12, [os, .deferred lt, .ref dn, .nat n, .nat v, .fn f, cs] => some (.kExec os lt dn n v f cs)
  | 13, [os, ex, .deferred lt, .ref dn, .bool par, .nat n, .nat v, .fn f, ws, cs] => some (.kWSup os ex lt dn par n v f ws cs)
  | 14, [sup, ex, .deferred lt, .ref dn, .nat v] => some (.acqWorker sup ex lt dn v)
  | 15, [sup, ex, .deferred lt, .nat v] => some (.newWorker sup ex lt v)
  | 16, [.ref dn] => some (.pairWorker dn)
  | 17, [.ref q, .ref dn, .nat v] => some (.pill q dn v)
  | 18, [os, ex, .deferred lt, .ref dn, .bool par, .nat n, .nat v, .fn f, ws, cs] => some (.kWorker os ex lt dn par n v f ws cs)
  | 19, [os, ws, .ref dn, .bool par, .nat n, .nat v, cs] => some (.kEc os ws dn par n v cs)
  | 20, [os, w] => some (.thenLaunch os w)
  | 21, [x] => some (.constV x)
  | 23, [c] => some (.obj c)
  | 24, [c, src, .bool forget] => some (.submit c src forget)
  | 25, [c, .ref st] => some (.cancelObj c st)
  | 26, [c, .ref st] => some (.cancelThunk c st)
  | 27, [.ref st, src, .ref res] => some (.promBody st src res)
  | 28, [.ref st] => some (.cstThunk st)
  | 29, [.ref res] => some (.redeemK res)
  | 30, [.ref res, x] => some (.complete res x)
  | 31, [.ref p] => some (.succThunk p)
  | 32, [.ref wd] => some (.wdGet wd)
  | 33, [w] => some (.runSel w)
  | 34, [] => some .thenCede
  | 35, [w] => some (.thenRun w)
  | 36, [w] => some (.stepSel w)
  | 37, [w, .ref st] => some (.primThunk w st)
  | 38, [] => some .flattenK
  | 39, [w, .ref st, u, cf] => some (.regThunk w st u cf)
  | 40, [w, .ref st, u] => some (.regFib w st u)
  | 41, [w, .ref st, u, task] => some (.inplK w st u task)
  | 42, [task] => some (.thenSrc task)
  | 43, [] => some .unitK
  | 44, [.ref wd] => some (.wdSet wd)
  | 45, [.ref q] => some (.takeBody q)
  | 46, [.ref q] => some (.bufTake q)
  | 47, [.ref q, .cont s] => some (.h1 q s)
  | 48, [.ref q, .cont s] => some (.setLatch q s)
  | 49, [.ref q, .cont s] => some (.thenH q s)
  | 50, [.ref q] => some (.keepK q)
  | 51, [.ref q] => some (.unsetLatch q)
  | 52, [.ref q, .cont s] => some (.h2 q s)
  | 53, [.ref q] => some (.thenUnset q)
  | 54, [.ref q] => some (.thenTake q)
  | 55, [.fn f] => some (.useOut f)
  | 56, [.ref wd] => some (.waitWd wd)
  | 57, [.ref wd] => some (.selWd wd)
  | _, _ => none

/-- The closure id (odd: a library closure). -/
def DL.id (l : DL) : Nat := 2 * valToNat l.toVal + 1

/-- The closure as a `Fn`. -/
def DL.fn (l : DL) : Fn := .user l.id

/-- The closure of an id, if it is one of this mirror. -/
def DL.ofId? (id : Nat) : Option DL :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == ns then DL.ofFields tag fs else none
    | none => none
  else none

/-! ## Builders -/

/-- `checkRestart = always` (`DP:250`). -/
def alwaysV : Val := .some (.fn DL.always.id)

/-- `x.void` = `map(_ => ())` (`IO.scala:961-962`). -/
def voidIO (x : IO) : IO := .map x (.rt .voidK)

/-- `Sync[F].defer(thunk)` = `IO.defer` = `delay(thunk).flatten` (`IO.scala:1296-1297`, `:472`):
the thunk returns a descriptor, `flattenK` builds the `IO`. -/
def deferIO (thunk : DL) : IO := .flatMap (.delay thunk.fn) DL.flattenK.fn

/-- `UnsafeAsyncQueue.take` (`DP:638-653`) = `Async[F].cont(...)` = `IOCont(body)` (`IO.scala:1548-1549`,
`:2051`). -/
def takeIO (q : Nat) : IO := .ioCont (DL.takeBody q).fn

/-- `Worker#run` (`DP:469`): `Sync[F].delay(doneR.get()).ifM(...)`; `ifM` = `flatMap(if (_) ... else
...)` (`cats/FlatMap.scala:142-143`, `cats/syntax/flatMap.scala:119`). -/
def runIO (w : W) : IO := .flatMap (.delay (DL.wdGet w.wd).fn) (DL.runSel w.toVal).fn

/-- `step` (`DP:412`): `queue.take flatMap { ... }`. -/
def stepIO (w : W) : IO := .flatMap (takeIO w.q) (DL.stepSel w.toVal).fn

/-- The dispatcher value. -/
def dispVal (c : DC) : Val := .fn (DL.obj c.toVal).id

/-- The dispatcher fields of a dispatcher value. -/
def dispOf? : Val → Option DC
  | .fn id =>
    match DL.ofId? id with
    | some (.obj c) => DC.ofVal? c
    | _ => none
  | _ => none

/-- `IO(unsafeToFutureCancelable(fa))` (`forget = false`) and `IO(unsafeRunAndForget(fa))`
(`forget = true`). Variants 2 and 10 never return (battery, not Cats Effect code). -/
def submitIO (c : DC) (src : Val) (forget : Bool) : IO :=
  if (!forget && c.v == 2) || (forget && c.v == 10) then Timeout.neverIO
  else .delay (DL.submit c.toVal src forget).fn

/-- The cancel action value of a submission. -/
def cancelVal (c : DC) (st : Nat) : Val := .fn (DL.cancelObj c.toVal st).id

/-- `IO(cancel())`. Variant 6 never returns (battery, not Cats Effect code). -/
def cancelIO (c : DC) (st : Nat) : IO :=
  if c.v == 6 then Timeout.neverIO else .delay (DL.cancelThunk c.toVal st).fn

/-- The cancel action of a cancel value. -/
def cancelOf? : Val → Option (DC × Nat)
  | .fn id =>
    match DL.ofId? id with
    | some (.cancelObj c st) => (DC.ofVal? c).map (·, st)
    | _ => none
  | _ => none

/-- `Dispatcher.parallel(aw)` (`par = true`, `n` workers) or `Dispatcher.sequential(aw)`
(`par = false`, `n = 1`), then `.use(f)` (`R:207-208`). Variants 13, 14 replace the factory, 16
ignores `await`, 20 always awaits (battery). `cs` is the list of worker choices (`ThreadLocalRandom`). -/
def useIO' (par aw : Bool) (n v f : Nat) (cs : Val := .unit) : IO :=
  if v == 13 then .error battErr
  else if v == 14 then Timeout.neverIO
  else
    let aw := if v == 16 then false else if v == 20 then true else aw
    Supervisor.useIO aw alwaysV 0 0 (DL.kOuter par aw (if par then n else 1) v f cs).id

/-- `Dispatcher.parallel(aw).use(f)` with `n` workers. -/
def parallelUseIO (aw : Bool) (n : Nat) (f : Nat) (v : Nat := 0) (cs : Val := .unit) : IO := useIO' true aw n v f cs

/-- `Dispatcher.sequential(aw).use(f)`. -/
def sequentialUseIO (aw : Bool) (f : Nat) (v : Nat := 0) : IO := useIO' false aw 1 v f

/-- The outcome of a snapshot (`snapVal`). -/
def ocOfSnap : Val → Option Outcome
  | .some (.ocSucceeded x) => some (.succeeded x)
  | .some (.ocErrored e) => some (.errored e)
  | .some .ocCanceled => some .canceled
  | _ => none

/-- The `IO` of a descriptor. `src` codes of other mirrors and of the caller go to `ioOf`. -/
def eIO : E → IO
  | .prom st src res => .uncancelable (DL.promBody st src res).fn
  | .cst st => .delay (DL.cstThunk st).fn
  | .run w =>
    match W.ofVal? w with
    | some w => runIO w
    | none => .error illErr
  | .cancelG cf p =>
    -- `IO#guarantee` (`IO.scala:496-501`, `Bracket.guaranteeIO`)
    Bracket.guaranteeIO (.ext cf) (.ext (E.succ p).toVal)
  | .succ p => .delay (DL.succThunk p).fn
  | .fibCancel t snap => IO.cancelOf t (ocOfSnap snap)
  | .dget d snap => IO.deferredGetOf d (dsnapOf snap)
  | .regThen w st u cf task => .flatMap (deferIO (DL.regThunk w st u cf)) (DL.thenSrc task).fn
  | .dcomplete d => voidIO (.delay (.rt (.deferredComplete d .unit)))
  | .unit => .pure .unit
  | .supVoid s cf p =>
    match Sup.ofVal? s with
    | some s => voidIO (superviseIO s (E.cancelG cf p).toVal)
    | none => .error illErr
  | .succVoid p => voidIO (.delay (DL.succThunk p).fn)
  | .exec w st u =>
    match W.ofVal? w, u with
    | some wk, .left action =>
      match wk.ex with
      -- `supervisor.supervise(task).flatMap(fiber => registerCancel(fiber.cancel))` (`DP:618-619`)
      | some es => .flatMap (superviseIO es action) (DL.regFib w st u).fn
      -- `Concurrent[F].deferred[Unit].flatMap { d => ... }` (`DP:502`)
      | none => .flatMap (Supervisor.newDeferredIO) (DL.inplK w st u action).fn
    | _, _ => .error illErr
  | .raise e => .error e
  | .setTrue r => .delay (DL.setTrue r).fn
  | .pill q dn v =>
    -- fixed twins 31, 32 (not Cats Effect code): after the pill, wait until the worker took it
    -- (the worker `doneR` cell is `q + 1`, `newWorker`), so it has taken every registration
    -- before it, while the executor is still open
    if v == 31 || v == 32 then .flatMap (.delay (DL.pill q dn v).fn) (DL.waitWd (q + 1)).fn
    else .delay (DL.pill q dn v).fn

/-- The sources of the other mirrors (`Bracket`, `Supervisor`): this mirror's descriptors, then
`Supervisor`'s, then `ioOf`. -/
def srcOf (ioOf : Val → IO) (c : Val) : IO :=
  match E.ofVal? c with
  | some e => eIO e
  | none => Supervisor.srcOf ioOf c

/-! ## The calls -/

private def ret (x : Val) : UserResult := { out := .ret x }
private def prog (p : IO) : UserResult := { out := .prog p }
private def illTyped : UserResult := { out := .throw illErr }

/-- `Resource.make(acquire)(release)` with the fold continuation `use` (`R:173-184`). -/
def makeIO (acq use : DL) : IO :=
  Bracket.bracketFullIO acq.id use.id Supervisor.SLam.relK.id

/-- The workers stage of the fold: worker `i = ws.length` (`Worker.apply`, `DP:475-488`), or the
`evalMap` when all `n` workers are acquired. -/
def workersIO (os ex : Val) (lt dn : Nat) (par : Bool) (n v f : Nat) (cs : Val) (ws : List Val) : IO :=
  if ws.length < n then
    Supervisor.useIO false .none 0 0 (DL.kWSup os ex lt dn par n v f (listV ws) cs).id
  else
    -- `Eval(Async[F].executionContext.flatMap(ec => ...))`: `fa.flatMap(a => continue(pure(a), Nil))`
    .flatMap (.flatMap .readEC (DL.kEc os (listV ws) dn par n v cs).fn) (DL.useOut f).fn

/-- The promise cell `p` completed with `x` (`left (err e)` or `right a`): the effects, or the
`IllegalStateException` of a completed promise. `forget` reports a failure (`DP:85-89`). -/
def completeP (v : View) (p : Nat) (x : Val) : UserResult :=
  match v.refs.getD p .unit with
  | .pair (.bool fg) .none =>
    let rep : List UserEffect := match fg, x with
      | true, .left (.err e) => [.report e]
      | _, _ => []
    { effects := [.writeRef p (promV fg (.some x))] ++ rep, out := .ret .unit }
  | .pair (.bool _) (.some _) => { out := .throw promErr }
  | _ => illTyped

/-- `unsafeOffer(a)` (`DP:632-636`): `buffer.put(a)`, then `back(RightUnit)` if `latchR` is set. -/
def offerEff (v : View) (q : Nat) (a : Val) : List UserEffect :=
  match v.refs.getD q emptyQ with
  | .pair buf l =>
    let buf' := listV ((unlistV buf).getD [] ++ [a])
    [.writeRef q (.pair buf' l)] ++ (match l with
      | .cont s => [.invokeCb s (.right .unit)]
      | _ => [])
  | _ => []

/-- Pick a worker queue (`DP:325-329`): the head of the choice list (`ThreadLocalRandom`) modulo
`n` for `parallel`; worker 0 for `sequential`. -/
def pickQ (v : View) (c : DC) : List UserEffect × Nat :=
  if c.par then
    match unlistV (v.refs.getD c.ws .unit) with
    | some (.nat k :: rest) => ([.writeRef c.ws (listV rest)], c.qs.getD (k % max c.n 1) 0)
    | _ => ([], c.qs.getD 0 0)
  else ([], c.qs.getD 0 0)

/-- `inner(fe, result, finalizer)` (`DP:289-368`) with the promise `res` already allocated:
the effects (from `v` with `base` new `Ref` cells before) and the cancel action, or a throw. -/
def innerEff (v : View) (base : Nat) (c : DC) (src : Val) (res : Nat) (finalizer : Bool) :
    Option (List UserEffect × Val) :=
  -- `if (doneR.get()) throw new IllegalStateException(...)` (`DP:293-295`)
  if v.refs.getD c.dn (.bool false) == .bool true && c.v != 19 then none
  else
    -- `val stateR = new AtomicReference[RegState[F]]`; `stateR.set(Unstarted(promisory))`
    let st := v.refs.length + base
    let action := (E.prom st src res).toVal
    let (sel, q) := pickQ v c
    let v' : View := { v with refs := v.refs ++ List.replicate (base + 1) .unit }
    if finalizer then
      -- `worker.queue.unsafeOffer(Registration.Finalizer(promisory))`; `() => Future.failed(...)`
      some ([.allocRef (.left action)] ++ sel ++ offerEff v' q (.right action), .unit)
    else
      -- `worker.queue.unsafeOffer(new Registration.Primary(stateR))`; `cancel _`
      let offer := if c.v == 3 || c.v == 11 then [] else offerEff v' q (.left (.ref st))
      some ([.allocRef (.left action)] ++ sel ++ offer, cancelVal c st)

/-- The `Ref` writes and allocations of `effs` applied to `v` (battery variants 4, 8, 12 only). -/
def applyRefEffects (v : View) : List UserEffect → View
  | [] => v
  | .writeRef r x :: es => applyRefEffects { v with refs := v.refs.set r x } es
  | .allocRef x :: es => applyRefEffects { v with refs := v.refs ++ [x] } es
  | _ :: es => applyRefEffects v es

/-- Run closure `l` on `arg` with view `v`. `uf` calls the user functions (the `use` function `f`),
`ioOf` builds the caller's sources. -/
def call (uf : Nat → Val → View → UserResult) (ioOf : Val → IO) (l : DL) (arg : Val) (v : View) :
    UserResult :=
  match l with
  | .always => ret (.bool true)
  -- `supervisor => (awaitTermination, termination) flatMapN { ... }`: the `Allocate` of
  -- `awaitTermination` (`DP:260-262`)
  | .kOuter par aw n vr f cs =>
    -- the fields of the supervisor (`Sup.toVal`), not its object reference: a closure code that
    -- embeds another closure code doubles its size (track V, "Codec cost")
    match supOf? arg with
    | some os => prog (makeIO .acqLatch (.kLatch os.toVal par aw n vr f cs))
    | none => illTyped
  | .acqLatch => prog (.map (.map Supervisor.newDeferredIO DL.pairLatch.fn) DL.pairRel.fn)
  | .pairLatch =>
    match arg with
    | .deferred d => ret (.pair arg (E.dcomplete d).toVal)
    | _ => illTyped
  | .pairRel =>
    match arg with
    | .pair a rel => ret (.pair a (.fn (DL.constRel rel).id))
    | _ => illTyped
  | .constRel rel => prog (srcOf ioOf rel)
  | .kLatch os par aw n vr f cs =>
    match arg with
    | .pair (.deferred lt) _ => prog (makeIO .acqTerm (.kTerm os lt par aw n vr f cs))
    | _ => illTyped
  | .newBool => { effects := [.allocRef (.bool false)], out := .ret (.ref v.refs.length) }
  | .acqTerm => prog (.map (.map (.delay DL.newBool.fn) DL.pairTerm.fn) DL.pairRel.fn)
  | .pairTerm =>
    match arg with
    -- `doneR => Sync[F].delay(doneR.set(true))`: an `IO` value; a `Delay` of `setTrue`
    | .ref r => ret (.pair arg (E.setTrue r).toVal)
    | _ => illTyped
  | .setTrue r => { effects := [.writeRef r (.bool true)], out := .ret .unit }
  | .kTerm os lt par aw n vr f cs =>
    match arg with
    | .pair (.ref dn) _ =>
      if par then
        -- `Executor.parallel[F](await)` = `Supervisor[F](await = await) map { ... }` (`DP:615-621`)
        prog (Supervisor.useIO aw .none 0 0 (DL.kExec os lt dn n vr f cs).id)
      -- variant 18 (not Cats Effect code): `sequential` with the `parallel` executor
      else if vr == 18 then prog (Supervisor.useIO aw .none 0 0 (DL.kExec os lt dn 1 vr f cs).id)
      -- `Resource.pure[F, Executor[F]](Executor.inplace[F])` (`DP:269`): no node
      else prog (workersIO os .none lt dn false 1 vr f cs [])
    | _ => illTyped
  | .kExec os lt dn n vr f cs =>
    match supOf? arg with
    | some es => prog (workersIO os (.some es.toVal) lt dn (vr != 18) n vr f cs [])
    | none => illTyped
  | .kWSup os ex lt dn par n vr f ws cs =>
    match supOf? arg with
    | some ws' => prog (makeIO (.acqWorker ws'.toVal ex lt dn vr) (.kWorker os ex lt dn par n vr f ws cs))
    | none => illTyped
  | .acqWorker sup ex lt dn vr => prog (.map (.map (.delay (DL.newWorker sup ex lt vr).fn) (DL.pairWorker dn).fn) DL.pairRel.fn)
  | .newWorker sup ex lt vr =>
    -- `new Worker(new UnsafeAsyncQueue, supervisor, executor, terminationLatch)`: the queue cell,
    -- then the worker `doneR` (`DP:409`, `:482`)
    let q := v.refs.length
    match Sup.ofVal? sup, (match ex with | .none => some none | .some e => (Sup.ofVal? e).map some | _ => none) with
    | some s, some exs =>
      { effects := [.allocRef emptyQ, .allocRef (.bool false)],
        out := .ret (W.toVal { q, wd := q + 1, sup := s, ex := exs, lt, v := vr }) }
    | _, _ => illTyped
  | .pairWorker dn =>
    match W.ofVal? arg with
    | some w => ret (.pair arg (E.pill w.q dn w.v).toVal)
    | none => illTyped
  | .pill q dn vr =>
    -- fixed twins 30, 32 (not Cats Effect code): the dispatcher `doneR` is set before the pill
    let pre : List UserEffect := if vr == 30 || vr == 32 then [.writeRef dn (.bool true)] else []
    if vr == 15 then { out := .ret .unit }
    else { effects := pre ++ offerEff v q .none, out := .ret .unit }
  | .kWorker os ex lt dn par n vr f ws cs =>
    match arg, unlistV ws with
    | .pair w _, some ws =>
      prog (workersIO os ex lt dn par n vr f cs (ws ++ [w]))
    | _, _ => illTyped
  | .kEc os ws dn par n vr cs =>
    match Sup.ofVal? os, unlistV ws with
    | some osup, some wl =>
      let wks := wl.filterMap W.ofVal?
      let c : DC := { par, dn, ws := v.refs.length, n, v := vr, qs := wks.map (·.q) }
      -- the choice cell (input; not Cats Effect state) is made here, then
      -- `launchAll = workers traverse_ { w => supervisor.supervise(w.run) }` (`DP:283-285`);
      -- `traverse_` = `void(foldLeft(f(first))(productR))` (`cats/Traverse.scala:299-309`)
      let launch : IO := match wl with
        | [] => .pure .unit
        | w0 :: rest =>
          voidIO (rest.foldl (fun acc w => .flatMap acc (DL.thenLaunch os w).fn)
            (superviseIO osup (E.run w0).toVal))
      { effects := [.allocRef cs], out := .prog (.map launch (DL.constV (dispVal c)).fn) }
    | _, _ => illTyped
  | .thenLaunch os w =>
    match Sup.ofVal? os with
    | some osup => prog (superviseIO osup (E.run w).toVal)
    | none => illTyped
  | .constV x => ret x
  | .obj c =>
    match DC.ofVal? c, arg with
    | some dc, .pair (.nat 0) src => prog (submitIO dc src false)
    | some dc, .pair (.nat 1) src => prog (submitIO dc src true)
    | _, _ => illTyped
  | .submit c src forget =>
    match DC.ofVal? c with
    | none => illTyped
    | some dc =>
      if (!forget && dc.v == 1) || (forget && dc.v == 9) then { out := .throw battErr }
      else
      -- `val result = Promise[A]()` (`DP:370`)
      let res := v.refs.length
      let v1 : View := { v with refs := v.refs ++ [promV forget .none] }
      match innerEff v1 0 dc src res false with
      | none => { effects := [.allocRef (promV forget .none)], out := .throw iseErr }
      | some (effs, cancel) =>
        -- variants 4 and 12 offer a second registration of the same effect (battery)
        let extra : List UserEffect :=
          if (!forget && dc.v == 4) || (forget && dc.v == 12) then
            let v2 : View := applyRefEffects v1 (effs.filter fun e => match e with | .allocRef _ => false | _ => true)
              |> fun w => { w with refs := w.refs ++ [.unit] }
            match innerEff v2 0 dc src res false with
            | some (e2, _) => e2
            | none => []
          else []
        { effects := [.allocRef (promV forget .none)] ++ effs ++ extra,
          out := .ret (if forget then .unit else .pair (.ref res) cancel) }
  | .cancelObj c st =>
    match DC.ofVal? c with
    | some dc => prog (cancelIO dc st)
    | none => illTyped
  | .cancelThunk c st =>
    match DC.ofVal? c with
    | none => illTyped
    | some dc =>
      if dc.v == 5 then { out := .throw battErr }
      else if dc.v == 7 then
        { effects := [.allocRef (promV false (.some (.right .unit)))], out := .ret (.pair (.ref v.refs.length) .unit) }
      else
      let once (v : View) : UserResult :=
        match v.refs.getD st .unit with
        -- `case u: Unstarted => val latch = Promise[Unit](); CAS(u, CancelRequested(latch))`
        | .left _ =>
          let p := v.refs.length
          { effects := [.allocRef (promV false .none), .writeRef st (.some (.ref p))],
            out := .ret (.pair (.ref p) .unit) }
        -- `case r: Running => val latch = Promise[Unit](); inner(cancel, latch, true)`
        | .right cf =>
          let p := v.refs.length
          let v1 : View := { v with refs := v.refs ++ [promV false .none] }
          match innerEff v1 0 dc cf p true with
          | some (effs, _) => { effects := [.allocRef (promV false .none)] ++ effs, out := .ret (.pair (.ref p) .unit) }
          | none => { effects := [.allocRef (promV false .none)], out := .throw iseErr }
        -- `case r: CancelRequested => r.latch.future`
        | .some (.ref p) => ret (.pair (.ref p) .unit)
        -- `case Completed => Future.successful(())`
        | .none =>
          { effects := [.allocRef (promV false (.some (.right .unit)))], out := .ret (.pair (.ref v.refs.length) .unit) }
        | _ => illTyped
      let r1 := once v
      if dc.v == 8 then
        -- variant 8 (not Cats Effect code): the cancel protocol runs twice
        match r1.out with
        | .ret x =>
          let v' := applyRefEffects v r1.effects
          let r2 := once v'
          { effects := r1.effects ++ r2.effects, out := match r2.out with | .throw e => .throw e | _ => .ret x }
        | _ => r1
      else r1
  | .promBody st src res =>
    match arg with
    -- `poll(fe.guarantee(completeState)).redeemWith(...).void`; `redeemWith` =
    -- `attempt.flatMap(_.fold(recover, bind))` (`IO.scala:724-725`, `:2157-2160`)
    | .poll m p =>
      prog (voidIO (.flatMap (.attempt (IO.applyPoll (Bracket.guaranteeIO (.ext src) (.ext (E.cst st).toVal)) m p))
        (DL.redeemK res).fn))
    | _ => illTyped
  | .cstThunk st =>
    -- `stateR.getAndSet(RegState.Completed) match { ... }` (`DP:302-315`)
    match v.refs.getD st .unit with
    | .some (.ref p) =>
      let r := completeP v p (.right .unit)
      { r with effects := .writeRef st .none :: r.effects }
    | .none => { effects := [.writeRef st .none], out := .throw aeErr }
    | _ => { effects := [.writeRef st .none], out := .ret .unit }
  | .redeemK res =>
    match arg with
    | .left (.err e) => prog (.delay (DL.complete res (.left (.err e))).fn)
    | .right a => prog (.delay (DL.complete res (.right a)).fn)
    | _ => illTyped
  | .complete res x => completeP v res x
  | .succThunk p => completeP v p (.right .unit)
  | .wdGet wd => ret (v.refs.getD wd (.bool false))
  | .runSel w =>
    match W.ofVal? w, arg with
    -- `terminationLatch.get >> Spawn[F].cede`
    | some wk, .bool true => prog (.flatMap (IO.deferredGetOf wk.lt (v.deferred wk.lt)) DL.thenCede.fn)
    -- `step >> run`
    | some wk, .bool false => prog (.flatMap (stepIO wk) (DL.thenRun w).fn)
    | _, _ => illTyped
  | .thenCede => prog .cede
  | .thenRun w =>
    match W.ofVal? w with
    | some wk => prog (runIO wk)
    | none => illTyped
  | .stepSel w =>
    match W.ofVal? w, arg with
    -- `case reg: Registration.Primary[F] => Sync[F] defer { ... }`
    | some _, .left (.ref st) => prog (deferIO (DL.primThunk w st))
    -- `case Registration.Finalizer(action) => supervisor.supervise(action).void.voidError`
    | some wk, .right action =>
      prog (.handleErrorWith (voidIO (superviseIO wk.sup action)) DL.unitK.fn)
    -- `case Registration.PoisonPill() => Sync[F].delay(doneR.set(true))`
    | some wk, .none => prog (.delay (DL.wdSet wk.wd).fn)
    | _, _ => illTyped
  | .primThunk w st =>
    match v.refs.getD st .unit with
    -- `case u @ RegState.Unstarted(action) => executor(action) { cancelF => ... }`
    | .left action => ret (E.exec w st (.left action)).toVal
    -- `case s @ (RegState.Running(_) | RegState.Completed) => throw new AssertionError`
    | .right _ | .none => { out := .throw aeErr }
    -- `case RegState.CancelRequested(latch) => Sync[F].delay(latch.success(())).void`
    | .some (.ref p) => ret (E.succVoid p).toVal
    | _ => illTyped
  | .flattenK =>
    match E.ofVal? arg with
    | some e => prog (eIO e)
    | none => illTyped
  | .regThunk w st u cf =>
    -- `if (reg.stateR.compareAndSet(u, RegState.Running(cancelF))) Applicative[F].unit else ...`
    let cur := v.refs.getD st .unit
    if cur == u then { effects := [.writeRef st (.right cf)], out := .ret E.unit.toVal }
    else
      match cur, W.ofVal? w with
      -- `case cr @ CancelRequested(latch) => CAS(cr, Running(cancelF)); supervisor.supervise(...)`
      | .some (.ref p), some wk =>
        { effects := [.writeRef st (.right cf)], out := .ret (E.supVoid wk.sup.toVal cf p).toVal }
      -- `case RegState.Completed => Applicative[F].unit`
      | .none, _ => ret E.unit.toVal
      -- `case s => throw new AssertionError(s"b => $s")`
      | _, _ => { out := .throw aeErr }
  | .regFib w st u =>
    match arg with
    -- `fiber => registerCancel(fiber.cancel)`: `fiber.cancel` reads `_cancel` now
    | .fiber t => prog (deferIO (DL.regThunk w st u (E.fibCancel t (snapVal (v.outcome t))).toVal))
    | _ => illTyped
  | .inplK w st u task =>
    match arg with
    -- `(registerCancel(d.get) *> task).guarantee(d.complete(()).void)` (`DP:503`)
    | .deferred d =>
      let cf := (E.dget d (dsnapVal (v.deferred d))).toVal
      prog (Bracket.guaranteeIO (.ext (E.regThen w st u cf task).toVal) (.ext (E.dcomplete d).toVal))
    | _ => illTyped
  | .thenSrc task => prog (srcOf ioOf task)
  | .unitK => prog (.pure .unit)
  | .wdSet wd => { effects := [.writeRef wd (.bool true)], out := .ret .unit }
  | .takeBody q =>
    match arg with
    -- `takeG.handleErrorWith { _ => ... }` (`DP:645`); `lift` = the identity (`IOFiber`, `G = IO`)
    | .cont s => prog (.handleErrorWith (.delay (DL.bufTake q).fn) (DL.h1 q s).fn)
    | _ => illTyped
  | .bufTake q =>
    match v.refs.getD q emptyQ with
    | .pair buf l =>
      match unlistV buf with
      | some (a :: rest) => { effects := [.writeRef q (.pair (listV rest) l)], out := .ret a }
      | some [] => { out := .throw signalErr }
      | none => illTyped
    | _ => illTyped
  -- `setLatchG *> (takeG <* unsetLatchG).handleErrorWith { ... }`; `*>` = `flatMap(_ => that)`
  -- (`IO.scala:138-139`, `:903-904`, `:2081-2082`)
  | .h1 q s => prog (.flatMap (.delay (DL.setLatch q s).fn) (DL.thenH q s).fn)
  | .setLatch q s =>
    match v.refs.getD q emptyQ with
    | .pair buf _ => { effects := [.writeRef q (.pair buf (.cont s))], out := .ret .unit }
    | _ => illTyped
  -- `takeG <* unsetLatchG` = `takeG.flatMap(a => unsetLatchG.as(a))` (`IO.scala:900-901`, `:182-183`)
  | .thenH q s => prog (.handleErrorWith (.flatMap (.delay (DL.bufTake q).fn) (DL.keepK q).fn) (DL.h2 q s).fn)
  | .keepK q => prog (.map (.delay (DL.unsetLatch q).fn) (DL.constV arg).fn)
  | .unsetLatch q =>
    match v.refs.getD q emptyQ with
    | .pair buf _ => { effects := [.writeRef q (.pair buf .none)], out := .ret .unit }
    | _ => illTyped
  -- `get *> unsetLatchG *> lift(take)` = `(get *> unsetLatchG) *> take`
  | .h2 q s => prog (.flatMap (.flatMap (.contGet s) (DL.thenUnset q).fn) (DL.thenTake q).fn)
  | .thenUnset q => prog (.delay (DL.unsetLatch q).fn)
  | .thenTake q => prog (takeIO q)
  | .useOut f => uf f arg v
  | .waitWd wd => prog (.flatMap (.delay (DL.wdGet wd).fn) (DL.selWd wd).fn)
  | .selWd wd =>
    match arg with
    | .bool true => prog (.pure .unit)
    | _ => prog (.flatMap .cede (DL.waitWd wd).fn)

/-- The closures of this mirror. -/
def isLib (id : Nat) : Bool := (DL.ofId? id).isSome

/-- This mirror, else the user functions `u`. -/
def dispatchD (ioOf : Val → IO) (u : UserEnv) (id : Nat) (arg : Val) (v : View) : UserResult :=
  match DL.ofId? id with
  | some l => call u.callV ioOf l arg v
  | none => u.callV id arg v

/-- The environment with this mirror and the `Supervisor` mirror (and through it `Bracket`,
`Race`, `Timeout`). `ho` is the `Supervisor` map order, `ioOf` builds the caller's sources. -/
def env (ho : List Val → List Val) (ioOf : Val → IO) (u : UserEnv) : UserEnv :=
  let inner : UserEnv := { call := fun id arg refs => dispatchD (srcOf ioOf) u id arg { refs },
                           callV := dispatchD (srcOf ioOf) u }
  let sup := Supervisor.env ho (srcOf ioOf) inner
  -- this mirror first (one decode of the id for its own closures), then `Supervisor` and the rest
  { call := fun id arg refs => match DL.ofId? id with
      | some l => call u.callV (srcOf ioOf) l arg { refs }
      | none => sup.call id arg refs
    callV := fun id arg v => match DL.ofId? id with
      | some l => call u.callV (srcOf ioOf) l arg v
      | none => sup.callV id arg v }

end CatsEffectInLean.Std.Dispatcher

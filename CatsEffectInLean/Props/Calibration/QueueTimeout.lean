import CatsEffectInLean.Std.Queue
import CatsEffectInLean.Model.Timeout
import CatsEffectInLean.Model.Outcomes

/-!
# No lost element: `Queue.take.timeout` canceled from outside (CE-0003)

Program A of `reproducers/CE-0003/Repro.scala` (upstream issue typelevel/cats-effect#4571),
with the list of offered elements, the timeout and the sleep as parameters:

```scala
for {
  q        <- Queue.unbounded[IO, Int]
  consumer <- q.take.timeout(d).start
  _        <- IO.sleep(s)
  _        <- q.offer(x1); ...; _ <- q.offer(xn)
  _        <- consumer.cancel
  oc       <- consumer.join
  r1       <- q.tryTake; ...; rn <- q.tryTake       // drain: n = number of offers
} yield ...
```

## Promise

"No lost element" (`AGENTS.md`, properties, source (b)): an element that `offer` put into the
queue is returned to a caller of `take`, or it is still in the queue. Support:

* Scaladoc of `IO#timeout` (`core/shared/src/main/scala/cats/effect/IO.scala:800-802` at
  `v3.7.1`): "The resulting effect will always wait for the source effect to complete (and to
  complete its finalizers), and will return the source's outcome over raising a
  `TimeoutException`."
* `std/shared/src/main/scala/cats/effect/std/Queue.scala:365-366` (design comment): "it's the
  taker-cancelation situation where we must take extra care to ensure atomicity."

## Statement

* For all lists `xs` of elements, all timeouts `d` and all sleeps `s` (no hypotheses; `Nat`
  is the `Sleep` unit, milliseconds in the reproducer), and for all schedules of the replay
  scheduler (`outcomes`: all fuel values and all `pick` lists; the cancel is part of the
  program, so no outside cancel is needed).
* The program uses only handles it received (decision 22): `q` from `Queue.unbounded`,
  `consumer` from `start`.
* Observation: the program emits the outcome of `consumer.join` and each `tryTake` result
  (`UserEffect.emit`, the trace of the test program). The elements that came back are the
  value of a `Succeeded` outcome and the values of the `Some` results (`returned`).
* Claim: if the root fiber ends `Succeeded`, the returned elements are a permutation of `xs`
  (none lost, none duplicated). A run that ends another way (model abort, out of fuel) makes
  no claim.

The drain uses `n = xs.length` calls of `tryTake`. After `consumer.join` no other fiber can
change the queue: `racePair` waits for its cancel fibers (`IOFiber.scala:940-946`), so the
racers are done; the root is the only fiber that runs code on `q`.

Model (all mirrored code, nothing written as a specification):
`Std/Queue.lean` (`UnboundedAsyncQueue`, `UnsafeUnbounded`), `Model/Timeout.lean`
(`timeout`, `timeoutTo`, `IO.never`), the `IOFiber` mirror with `RacePair`, `Sleep`, `Start`,
`_cancel`, `_join` (`Model/Step.lean`, `Model/Sched.lean`), `counterMaskModel`, default
`Config`.
-/

namespace CatsEffectInLean.Props.Calibration.QueueTimeout

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- The namespace of the program closures in `Codec.cloVal`. -/
def ns : Nat := 3

/-- The lambdas of the `for` of program A. This is user code: each lambda is a user closure
(even id, `Codec.userFn`) that captures the handles it got before (`q`, `c`). Fields: `q` =
queue, `c` = consumer fiber, `n` = drain count, `xs` = the elements still to offer. -/
inductive PLam where
  /-- `q => q.take.timeout(d).start.flatMap(...)`. -/
  | afterQueue (xs : List Nat) (d s : Nat)
  /-- `consumer => IO.sleep(s).flatMap(...)`. -/
  | afterStart (q : Nat) (xs : List Nat) (s : Nat)
  /-- `_ => q.offer(x).flatMap(...)` for the next `x`, or `_ => consumer.cancel.flatMap(...)`. -/
  | offerNext (q c n : Nat) (xs : List Nat)
  /-- `_ => consumer.join.flatMap(...)`. -/
  | afterCancel (q c n : Nat)
  /-- `oc => ...`: emit `oc`, then drain `n`. -/
  | afterJoin (q n : Nat)
  /-- `r => ...`: emit the `tryTake` result `r`, then drain `k` more. -/
  | afterTryTake (q k : Nat)
  deriving DecidableEq, Repr

/-- A list of elements as a `Val`. -/
def natsV (xs : List Nat) : Val := listV (xs.map .nat)

/-- The inverse of `natsV`. -/
def ofNatsV (v : Val) : Option (List Nat) :=
  (unlistV v).bind fun l => l.mapM fun | .nat n => some n | _ => none

/-- The closure value (`Codec.cloVal`, namespace `ns`). The handles `q` and `c` are captured
as `Val.ref q` and `Val.fiber c`. -/
def PLam.toVal : PLam → Val
  | .afterQueue xs d s => cloVal ns 0 [natsV xs, .nat d, .nat s]
  | .afterStart q xs s => cloVal ns 1 [.ref q, natsV xs, .nat s]
  | .offerNext q c n xs => cloVal ns 2 [.ref q, .fiber c, .nat n, natsV xs]
  | .afterCancel q c n => cloVal ns 3 [.ref q, .fiber c, .nat n]
  | .afterJoin q n => cloVal ns 4 [.ref q, .nat n]
  | .afterTryTake q k => cloVal ns 5 [.ref q, .nat k]

/-- The inverse of `PLam.toVal` on the tag and the fields (namespace already checked). -/
def PLam.ofFields : Nat → List Val → Option PLam
  | 0, [xs, .nat d, .nat s] => (ofNatsV xs).map fun xs => .afterQueue xs d s
  | 1, [.ref q, xs, .nat s] => (ofNatsV xs).map fun xs => .afterStart q xs s
  | 2, [.ref q, .fiber c, .nat n, xs] => (ofNatsV xs).map fun xs => .offerNext q c n xs
  | 3, [.ref q, .fiber c, .nat n] => some (.afterCancel q c n)
  | 4, [.ref q, .nat n] => some (.afterJoin q n)
  | 5, [.ref q, .nat k] => some (.afterTryTake q k)
  | _, _ => none

/-- The closure as a `Fn`: a user closure (even id, `Codec.userFn`). -/
def PLam.fn (l : PLam) : Fn := userFn l.toVal

/-- `n` more `q.tryTake` calls, each result emitted. -/
def drain (q : Nat) : Nat → IO
  | 0 => .pure .unit
  | k + 1 => .flatMap (Std.Queue.tryTakeIO q) (PLam.afterTryTake q k).fn

private def prog (p : IO) (effects : List UserEffect := []) : UserResult := { effects, out := .prog p }
private def illTyped : UserResult := { out := .throw { code := 999999, kind := .fatal } }

/-- Run one program closure. -/
def call (l : PLam) (arg : Val) (v : View) : UserResult :=
  match l with
  | .afterQueue xs d s =>
    match arg with
    -- `consumer <- q.take.timeout(d).start` (`IO#start` = `Start`, `IO.scala:1092-1093`)
    | .ref q => prog (.flatMap (.start (Timeout.timeoutIO (.ref q) d)) (PLam.afterStart q xs s).fn)
    | _ => illTyped
  | .afterStart q xs s =>
    match arg with
    -- `_ <- IO.sleep(s)` (`IO.scala:1692-1696`)
    | .fiber c => prog (.flatMap (.sleep s) (PLam.offerNext q c xs.length xs).fn)
    | _ => illTyped
  | .offerNext q c n xs =>
    match xs with
    -- `_ <- q.offer(x)`
    | x :: rest => prog (.flatMap (Std.Queue.offerIO q (.nat x)) (PLam.offerNext q c n rest).fn)
    -- `_ <- consumer.cancel`
    | [] => prog (.flatMap (IO.cancelOf c (v.outcome c)) (PLam.afterCancel q c n).fn)
  | .afterCancel q c n =>
    -- `oc <- consumer.join`
    prog (.flatMap (IO.joinOf c (v.outcome c)) (PLam.afterJoin q n).fn)
  | .afterJoin q n => prog (drain q n) [.emit arg]
  | .afterTryTake q k => prog (drain q k) [.emit arg]

/-- The source of `timeout`: `Val.ref q` is `q.take`. -/
def srcIO : Val → IO
  | .ref q => Std.Queue.takeIO q
  | _ => .error { code := 999999, kind := .fatal }

/-- Dispatch a closure id (`Codec` convention): an odd id is a library closure (namespace
`Std.Queue.ns` or `Timeout.ns`), an even id is a program closure (namespace `ns`). Other ids
never occur. -/
def dispatch (id : Nat) (arg : Val) (v : View) : UserResult :=
  match (cloOfId id).bind ofCloVal with
  | some (k, tag, fs) =>
    if isLibId id then
      if k == Std.Queue.ns then
        match Std.Queue.QLam.ofFields tag fs with
        | some q => Std.Queue.call q arg v
        | none => illTyped
      else if k == Timeout.ns then
        match Timeout.TLam.ofFields tag fs with
        | some t => Timeout.call srcIO t arg v
        | none => illTyped
      else illTyped
    else if k == ns then
      match PLam.ofFields tag fs with
      | some p => call p arg v
      | none => illTyped
    else illTyped
  | none => illTyped

/-- The user environment of program A. -/
def env : UserEnv where
  call id arg refs := dispatch id arg { refs }
  callV := dispatch

/-- Program A with elements `xs`, timeout `d` and sleep `s`. -/
def progA (xs : List Nat) (d s : Nat) : IO :=
  .flatMap Std.Queue.newIO (PLam.afterQueue xs d s).fn

/-- The elements that came back, from the emitted trace: the value of a `Succeeded` outcome
of `consumer.join`, and the value of each `Some` result of `tryTake`. -/
def returned : List Val → List Nat
  | [] => []
  | .ocSucceeded (.nat x) :: r => x :: returned r
  | .some (.nat x) :: r => x :: returned r
  | _ :: r => returned r

/-- No lost element (`Queue.take.timeout(d)` in a fiber that another fiber cancels): over all
elements, timeouts, sleeps and schedules, a run of program A that ends `Succeeded` returned
each offered element exactly once (to the consumer or to the drain). -/
def takeTimeoutNoLostElement : Prop :=
  ∀ (xs : List Nat) (d s : Nat) (o : Obs),
    outcomes {} counterMaskModel env (progA xs d s) o →
    ∀ v, o.summary = .done (.succeeded v) →
    (returned o.out).Perm xs

end CatsEffectInLean.Props.Calibration.QueueTimeout

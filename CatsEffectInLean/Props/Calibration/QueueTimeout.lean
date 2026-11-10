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

/-- The namespace of the program closures in `Codec.nsFn`. -/
def ns : Nat := 3

/-- The lambdas of the `for` of program A. Fields: `q` = queue, `c` = consumer fiber,
`n` = drain count, `xs` = the elements still to offer (`Codec.encList`). -/
inductive PLam where
  /-- `q => q.take.timeout(d).start.flatMap(...)`. -/
  | afterQueue (xs d s : Nat)
  /-- `consumer => IO.sleep(s).flatMap(...)`. -/
  | afterStart (q xs s : Nat)
  /-- `_ => q.offer(x).flatMap(...)` for the next `x`, or `_ => consumer.cancel.flatMap(...)`. -/
  | offerNext (q c n xs : Nat)
  /-- `_ => consumer.join.flatMap(...)`. -/
  | afterCancel (q c n : Nat)
  /-- `oc => ...`: emit `oc`, then drain `n`. -/
  | afterJoin (q n : Nat)
  /-- `r => ...`: emit the `tryTake` result `r`, then drain `k` more. -/
  | afterTryTake (q k : Nat)
  deriving DecidableEq, Repr

/-- The fields of a closure (tag first). -/
def PLam.toList : PLam → List Nat
  | .afterQueue xs d s => [0, xs, d, s]
  | .afterStart q xs s => [1, q, xs, s]
  | .offerNext q c n xs => [2, q, c, n, xs]
  | .afterCancel q c n => [3, q, c, n]
  | .afterJoin q n => [4, q, n]
  | .afterTryTake q k => [5, q, k]

/-- The inverse of `PLam.toList`. -/
def PLam.ofList : List Nat → Option PLam
  | [0, xs, d, s] => some (.afterQueue xs d s)
  | [1, q, xs, s] => some (.afterStart q xs s)
  | [2, q, c, n, xs] => some (.offerNext q c n xs)
  | [3, q, c, n] => some (.afterCancel q c n)
  | [4, q, n] => some (.afterJoin q n)
  | [5, q, k] => some (.afterTryTake q k)
  | _ => none

/-- The closure as a `Fn`. -/
def PLam.fn (l : PLam) : Fn := nsFn ns l.toList

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
    | .ref q => prog (.flatMap (.start (Timeout.timeoutIO q d)) (PLam.afterStart q xs s).fn)
    | _ => illTyped
  | .afterStart q xs s =>
    match arg with
    -- `_ <- IO.sleep(s)` (`IO.scala:1692-1696`)
    | .fiber c => prog (.flatMap (.sleep s) (PLam.offerNext q c (decList xs).length xs).fn)
    | _ => illTyped
  | .offerNext q c n xs =>
    match decList xs with
    -- `_ <- q.offer(x)`
    | x :: rest => prog (.flatMap (Std.Queue.offerIO q (.nat x)) (PLam.offerNext q c n (encList rest)).fn)
    -- `_ <- consumer.cancel`
    | [] => prog (.flatMap (IO.cancelOf c (v.outcome c)) (PLam.afterCancel q c n).fn)
  | .afterCancel q c n =>
    -- `oc <- consumer.join`
    prog (.flatMap (IO.joinOf c (v.outcome c)) (PLam.afterJoin q n).fn)
  | .afterJoin q n => prog (drain q n) [.emit arg]
  | .afterTryTake q k => prog (drain q k) [.emit arg]

/-- Dispatch a closure id to its namespace: the queue, the timeout and the program closures.
Ids outside these namespaces never occur. -/
def dispatch (id : Nat) (arg : Val) (v : View) : UserResult :=
  match decList id with
  | 1 :: l => match Std.Queue.QLam.ofList l with
    | some q => Std.Queue.call q arg v
    | none => illTyped
  | 2 :: l => match Timeout.TLam.ofList l with
    | some t => Timeout.call Std.Queue.takeIO t arg v
    | none => illTyped
  | 3 :: l => match PLam.ofList l with
    | some p => call p arg v
    | none => illTyped
  | _ => illTyped

/-- The user environment of program A. -/
def env : UserEnv where
  call id arg refs := dispatch id arg { refs }
  callV := dispatch

/-- Program A with elements `xs`, timeout `d` and sleep `s`. -/
def progA (xs : List Nat) (d s : Nat) : IO :=
  .flatMap Std.Queue.newIO (PLam.afterQueue (encList xs) d s).fn

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

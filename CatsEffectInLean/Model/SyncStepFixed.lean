import CatsEffectInLean.Model.SyncStep
import CatsEffectInLean.Model.Codec

/-!
# Fixed twin of `SyncStep.interpret`: upstream PR #4700 (CE-0001, decision 39)

Not Cats Effect v3.7.1. A mirror of the fix in typelevel/cats-effect PR #4700 "Keep
uncancelable and onCancel on the syncStep remainder" (head `0c6f3c05`, open, base
`series/3.7.x`), file `core/shared/src/main/scala/cats/effect/IO.scala` of that PR (cited as
`PR:IO.scala`, the hunk at `SyncStep.interpret`, lines 2359-2469 of the PR head). The PR does
not change `IOFiber`, so the `IOFiber` mirror (`Model/Step.lean`) runs the rest as before.

The changes against v3.7.1 (`IO.scala:2348-2402`, `Model/SyncStep.lean`):

* `Uncancelable(body)`: the body gets a `DeferredPoll`, not `IdPoll`. A non-fatal throw from the
  body becomes `IO.raiseError(t)`. If the walk stops inside the body, the rest is
  `Uncancelable(Bind(deferred, rest))`.
* `Uncancelable(Bind(deferred, rest))` (a region that an earlier step rebuilt): walk `rest`
  and rebuild again.
* `OnCancel(ioa, fin)`: if the walk stops inside `ioa`, the rest is `rest.onCancel(fin)`.
* `FlatMap(Local(Unmask(deferred, ioc)), _)` (a `poll(ioc)` of a `DeferredPoll`): walk `ioc`;
  if the walk stops, the rest is `deferred(rest)`.
* These cases use `stepsUntilDefer - 1`.

`DeferredPoll` (`PR:IO.scala`, class `DeferredPoll` and object `DeferredPoll`):

* `poll(ioc) = IO.Local(Unmask(this, ioc)).flatten`. `Unmask(s) = (s, if (poll == null) ioc
  else poll(ioc))`, where `poll = local.getOrDefault(s)` is the real `Poll` bound in the
  running fiber's `IOLocal` state, or `null`.
* `Bind(deferred, rest)(poll) = local.getAndSet(poll).flatMap { previous =>
  (rest.attempt <* restore).rethrow }`, with `restore = if (previous == null) local.reset else
  local.set(previous)`.

## Model encoding

* A `DeferredPoll` is the value `Val.poll 0 (d + 1)`: mask id `0` like `IdPoll`, and `d` is its
  identity. `new DeferredPoll` (a fresh object with a fresh `IOLocalImpl` key) takes a fresh
  `Deferred` cell id as `d` (an unused cell; observations do not include `Deferred` cells).
* The `IOLocal` state is a list of pairs `(d, poll)` (`listV`); the default state `()` is the
  empty list.
* `applyPollT poll io` is `Poll.apply` for all three kinds of `Poll`: the run loop's poll
  (`UnmaskRunLoop`, `IO.applyPoll`), `IdPoll` (`Val.poll 0 0`: `io`) and `DeferredPoll`
  (`deferredApply`). User code applies a poll only through it.
* The closures of `DeferredPoll` are library closures (odd ids, namespace `fixNs`); `fixEnv`
  adds their meaning to a user environment. They capture `IO` values, so `ioV` encodes a
  program as a `Val`. `IO.Local` returns a `Val`, not an `IO`, so `Unmask(...).flatten` is
  `Local(unmask d).flatMap(applyK ioc)`: the `Local` reads the bound poll, `applyK` applies it.
-/

namespace CatsEffectInLean.Model

open Codec

namespace SyncStepFixed

/-! ## Programs as values -/

/-- A function as a value (only user and library closures; runtime closures are not needed). -/
def fnV : Fn → Val
  | .user id => .left (.nat id)
  | .rt _ => .right .unit

/-- The inverse of `fnV`. -/
def ofFnV : Val → Option Fn
  | .left (.nat id) => some (.user id)
  | _ => none

/-- A program as a value. -/
def ioV : IO → Val
  | .pure v => .pair (.nat 0) v
  | .error e => .pair (.nat 1) (.err e)
  | .delay f => .pair (.nat 2) (fnV f)
  | .realTime => .pair (.nat 3) .unit
  | .monotonic => .pair (.nat 4) .unit
  | .readEC => .pair (.nat 5) .unit
  | .map p f => .pair (.nat 6) (.pair (ioV p) (fnV f))
  | .flatMap p f => .pair (.nat 7) (.pair (ioV p) (fnV f))
  | .attempt p => .pair (.nat 8) (ioV p)
  | .handleErrorWith p f => .pair (.nat 9) (.pair (ioV p) (fnV f))
  | .canceled => .pair (.nat 10) .unit
  | .onCancel p q => .pair (.nat 11) (.pair (ioV p) (ioV q))
  | .uncancelable f => .pair (.nat 12) (fnV f)
  | .unmaskRunLoop p m s => .pair (.nat 13) (.pair (ioV p) (.pair (.nat m) (.nat s)))
  | .ioCont f => .pair (.nat 14) (fnV f)
  | .contGet s => .pair (.nat 15) (.nat s)
  | .cede => .pair (.nat 16) .unit
  | .start p => .pair (.nat 17) (ioV p)
  | .racePair p q => .pair (.nat 18) (.pair (ioV p) (ioV q))
  | .sleep d => .pair (.nat 19) (.nat d)
  | .evalOn p ec => .pair (.nat 20) (.pair (ioV p) (.nat ec))
  | .blocking _ _ => .pair (.nat 21) .none
  | .local f => .pair (.nat 22) (fnV f)
  | .ioTrace => .pair (.nat 23) .unit
  | .readRT => .pair (.nat 24) .unit
  | .endFiber => .pair (.nat 25) .unit

/-- The inverse of `ioV` (`none` for `blocking` and runtime closures). -/
def ofIoV : Val → Option IO
  | .pair (.nat 0) v => some (.pure v)
  | .pair (.nat 1) (.err e) => some (.error e)
  | .pair (.nat 2) f => (ofFnV f).map .delay
  | .pair (.nat 3) _ => some .realTime
  | .pair (.nat 4) _ => some .monotonic
  | .pair (.nat 5) _ => some .readEC
  | .pair (.nat 6) (.pair p f) => do let p ← ofIoV p; let f ← ofFnV f; pure (.map p f)
  | .pair (.nat 7) (.pair p f) => do let p ← ofIoV p; let f ← ofFnV f; pure (.flatMap p f)
  | .pair (.nat 8) p => (ofIoV p).map .attempt
  | .pair (.nat 9) (.pair p f) => do
    let p ← ofIoV p; let f ← ofFnV f; pure (.handleErrorWith p f)
  | .pair (.nat 10) _ => some .canceled
  | .pair (.nat 11) (.pair p q) => do let p ← ofIoV p; let q ← ofIoV q; pure (.onCancel p q)
  | .pair (.nat 12) f => (ofFnV f).map .uncancelable
  | .pair (.nat 13) (.pair p (.pair (.nat m) (.nat s))) =>
    (ofIoV p).map fun p => .unmaskRunLoop p m s
  | .pair (.nat 14) f => (ofFnV f).map .ioCont
  | .pair (.nat 15) (.nat s) => some (.contGet s)
  | .pair (.nat 16) _ => some .cede
  | .pair (.nat 17) p => (ofIoV p).map .start
  | .pair (.nat 18) (.pair p q) => do let p ← ofIoV p; let q ← ofIoV q; pure (.racePair p q)
  | .pair (.nat 19) (.nat d) => some (.sleep d)
  | .pair (.nat 20) (.pair p (.nat ec)) => (ofIoV p).map fun p => .evalOn p ec
  | .pair (.nat 22) f => (ofFnV f).map .local
  | .pair (.nat 23) _ => some .ioTrace
  | .pair (.nat 24) _ => some .readRT
  | .pair (.nat 25) _ => some .endFiber
  | _ => none

/-! ## `DeferredPoll` and its closures -/

/-- The namespace of the closures of the fixed twin (`Codec.cloVal`). -/
def fixNs : Nat := 9

/-- The library closures of `DeferredPoll` (`PR:IO.scala`, object `DeferredPoll`). -/
inductive FixLam where
  /-- The `IO.Local` function of `Unmask(deferred d, _)`: read the bound poll. -/
  | unmask (d : Nat)
  /-- `.flatten` after `Unmask`: apply the poll it read to `ioc` (`null`: `ioc` unchanged). -/
  | applyK (ioc : Val)
  /-- `Bind(deferred d, rest)`: the body of the rebuilt `Uncancelable`. -/
  | bind (d : Nat) (rest : Val)
  /-- The `IO.Local` function of `local.getAndSet(poll)` (`IOLocal.scala:195-196`). -/
  | getAndSet (d : Nat) (poll : Val)
  /-- `previous => (rest.attempt <* restore).rethrow`. -/
  | bindK (d : Nat) (rest : Val)
  /-- `a => restore.as(a)` of `<*` (`IO.scala:127-128`, `IO.scala:900-901`, `IO.scala:182-183`). -/
  | restoreK (d : Nat) (previous : Val)
  /-- The `IO.Local` function of `local.reset` / `local.set(previous)` (`IOLocal.scala:158-165`). -/
  | setLocal (d : Nat) (previous : Val)
  /-- `_ => a` (`as(a)` = `map(_ => a)`, `IO.scala:182-183`). -/
  | constK (a : Val)
  /-- `rethrow` = `flatMap(a => IO.fromEither(a))` (`IO.scala:667-668`, `IO.scala:1938-1942`). -/
  | rethrowK

/-- The closure value of a `FixLam`. -/
def FixLam.toVal : FixLam → Val
  | .unmask d => cloVal fixNs 0 [.nat d]
  | .applyK c => cloVal fixNs 1 [c]
  | .bind d c => cloVal fixNs 2 [.nat d, c]
  | .getAndSet d p => cloVal fixNs 3 [.nat d, p]
  | .bindK d c => cloVal fixNs 4 [.nat d, c]
  | .restoreK d p => cloVal fixNs 5 [.nat d, p]
  | .setLocal d p => cloVal fixNs 6 [.nat d, p]
  | .constK a => cloVal fixNs 7 [a]
  | .rethrowK => cloVal fixNs 8 []

/-- The inverse of `FixLam.toVal` on the tag and the fields. -/
def FixLam.ofFields : Nat → List Val → Option FixLam
  | 0, [.nat d] => some (.unmask d)
  | 1, [c] => some (.applyK c)
  | 2, [.nat d, c] => some (.bind d c)
  | 3, [.nat d, p] => some (.getAndSet d p)
  | 4, [.nat d, c] => some (.bindK d c)
  | 5, [.nat d, p] => some (.restoreK d p)
  | 6, [.nat d, p] => some (.setLocal d p)
  | 7, [a] => some (.constK a)
  | 8, [] => some .rethrowK
  | _, _ => none

/-- A closure as a `Fn` (library closure, odd id). -/
def FixLam.fn (l : FixLam) : Fn := libFn l.toVal

/-- Decode a closure id of the fixed twin. -/
def fixLamOf (id : Nat) : Option FixLam :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (k, tag, fs) => if k == fixNs then FixLam.ofFields tag fs else none
    | none => none
  else none

/-- The poll bound to deferred `d` in an `IOLocal` state (`getOrDefault`; `none` = `null`). -/
def lookupLocal (d : Nat) : Val → Val
  | .pair (.pair (.nat d') p) rest => if d' == d then .some p else lookupLocal d rest
  | _ => .none

/-- The state without the binding of `d` (`reset`). -/
def removeLocal (d : Nat) : Val → Val
  | .pair (.pair (.nat d') p) rest =>
    if d' == d then removeLocal d rest else .pair (.pair (.nat d') p) (removeLocal d rest)
  | _ => .unit

/-- `set(state, a)` for `a = Some(poll)`, `reset(state)` for `a = None`. -/
def setLocalVal (d : Nat) (a : Val) (st : Val) : Val :=
  match a with
  | .some p => .pair (.pair (.nat d) p) (removeLocal d st)
  | _ => removeLocal d st

/-- `deferred.apply(ioc)` = `IO.Local(Unmask(deferred, ioc)).flatten`. -/
def deferredApply (d : Nat) (ioc : IO) : IO :=
  .flatMap (.local (FixLam.unmask d).fn) (FixLam.applyK (ioV ioc)).fn

/-- The `DeferredPoll` value with identity `d`. -/
def deferredPollVal (d : Nat) : Val := .poll 0 (d + 1)

/-- `poll(io)` for every kind of `Poll` value: a real poll of the run loop (mask id `≥ 1`),
`IdPoll` (`Val.poll 0 0`) and a `DeferredPoll` (`Val.poll 0 (d + 1)`). -/
def applyPollT (poll : Val) (io : IO) : IO :=
  match poll with
  | .poll 0 0 => io
  | .poll 0 (d + 1) => deferredApply d io
  | .poll m s => .unmaskRunLoop io m s
  | _ => io

/-- A model abort as a user result (a closure got a value of the wrong shape). -/
def badShape : UserResult := { out := .throw { code := 999998, kind := .fatal } }

/-- The meaning of the closures of the fixed twin. -/
def fixCall (l : FixLam) (arg : Val) : UserResult :=
  match l with
  -- `Unmask.apply(s) = (s, ...)`: the `Local` returns the bound poll (or `None`)
  | .unmask d => { out := .ret (.pair arg (lookupLocal d arg)) }
  -- `if (poll == null) ioc else poll(ioc)`, then `flatten`
  | .applyK c =>
    match ofIoV c with
    | some ioc =>
      match arg with
      | .some (.poll m s) => { out := .prog (IO.applyPoll ioc m s) }
      | _ => { out := .prog ioc }
    | none => badShape
  -- `Bind.apply(poll) = local.getAndSet(poll).flatMap { previous => ... }`
  | .bind d c => { out := .prog (.flatMap (.local (FixLam.getAndSet d arg).fn) (FixLam.bindK d c).fn) }
  -- `IO.Local(state => (set(state, value), getOrDefault(state)))`
  | .getAndSet d p => { out := .ret (.pair (setLocalVal d (.some p) arg) (lookupLocal d arg)) }
  -- `(rest.attempt <* restore).rethrow`
  | .bindK d c =>
    match ofIoV c with
    | some rest =>
      { out := .prog (.flatMap (.flatMap (.attempt rest) (FixLam.restoreK d arg).fn) FixLam.rethrowK.fn) }
    | none => badShape
  -- `a => restore.as(a)`; `restore = if (previous == null) local.reset else local.set(previous)`
  | .restoreK d p => { out := .prog (.map (.local (FixLam.setLocal d p).fn) (FixLam.constK arg).fn) }
  | .setLocal d p => { out := .ret (.pair (setLocalVal d p arg) .unit) }
  | .constK a => { out := .ret a }
  -- `IO.fromEither`: `Right(a) => pure(a)`, `Left(err) => raiseError(err)`
  | .rethrowK =>
    match arg with
    | .right v => { out := .prog (.pure v) }
    | .left (.err e) => { out := .prog (.error e) }
    | _ => badShape

/-- `env` with the closures of the fixed twin. -/
def fixEnv (env : UserEnv) : UserEnv where
  call id arg refs := match fixLamOf id with
    | some l => fixCall l arg
    | none => env.call id arg refs
  callV id arg v := match fixLamOf id with
    | some l => fixCall l arg
    | none => env.callV id arg v

/-! ## `interpret` of PR #4700 -/

/-- The rewrap of a `Left` rest (`.map { case Left(rest) => Left(...); case r => r }`). -/
def rewrapApply : Rewrap → IO → IO
  -- `Left(IO.Uncancelable(new DeferredPoll.Bind(deferred, rest), event))`
  | .unc d, rest => .uncancelable (FixLam.bind d (ioV rest)).fn
  -- `Left(rest.onCancel(fin))` (`IO.scala:590-591`)
  | .onCancel fin, rest => .onCancel rest fin
  -- `Left(unmask.deferred(rest))`
  | .deferred d, rest => deferredApply d rest

variable {M : Type} (mm : MaskModel M) (env : UserEnv)

/-- `applyMap` with the rewrap maps of the twin. -/
def applyMapFixed (g : SMap) (arg : SVal) (x : Exec M) : SyncStep.MRes M :=
  match g with
  | .rewrap k =>
    match arg with
    | .left (.io rest) => .ok (.left (.io (rewrapApply k rest))) x
    | .right r => .ok (.right r) x
    | _ => .abort .illTyped
  | g => SyncStep.applyMap mm env g arg x

/-- Wrap a `SyncIO` result with a rewrap map. -/
@[inline] def rewrapRes (k : Rewrap) : IRes M → IRes M :=
  SyncStep.IRes.wrap (fun s => .flatMap s (.pureMap (.rewrap k)))

/-- `SyncStep.interpret` of PR #4700 with `G = SyncIO`. `env` must be a `fixEnv`. -/
def interpretFixed : (fuel : Nat) → IO → (limit : Int) → (steps : Int) → Exec M → IRes M
  | 0, _, _, _, _ => .outOfFuel
  | fuel + 1, io, limit, steps, x =>
    if limit ≤ 0 then .ok (.pure (.left (.io io))) x
    else if steps ≤ 0 then .ok (.flatMap (.suspend .delay (.deferInterpret io limit)) .flattenId) x
    else
      -- PR: `case IO.Uncancelable(body, event)`: `val deferred = new DeferredPoll`; the body
      -- runs in a `try` that turns a non-fatal throw into `IO.raiseError(t)`; the rest goes into
      -- `Uncancelable(Bind(deferred, rest))`
      let fresh : Fn → IRes M := fun body =>
        let d := x.heap.deferreds.length
        let x := { x with heap := { x.heap with deferreds := x.heap.deferreds ++ [{}] } }
        match callUser mm env body (deferredPollVal d) x with
        | .error a => .abort a
        | .ok (.prog ioa, x) => rewrapRes (.unc d) (interpretFixed fuel ioa limit (steps - 1) x)
        | .ok (.throw e, x) =>
          if e.isNonFatal then
            rewrapRes (.unc d) (interpretFixed fuel (.error e) limit (steps - 1) x)
          else .thrown e x
        | .ok (.ret _, _) => .abort .illTyped
      let general : Unit → IRes M := fun _ =>
        match io with
        | .pure a => .ok (.pure (.right (.pair (.val a) (.int limit)))) x
        | .error t => .ok (.error t) x
        | .delay thunk =>
          .ok (.flatMap (.suspend .delay (.ioThunk thunk)) (.pureMap (.rightLimit limit))) x
        | .realTime => .ok (.flatMap .realTime (.pureMap (.rightLimit limit))) x
        | .monotonic => .ok (.flatMap .monotonic (.pureMap (.rightLimit limit))) x
        | .map ioe f =>
          SyncStep.IRes.wrap (fun s => .flatMap s (.pureMap (.mapSel f)))
            (interpretFixed fuel ioe (limit - 1) (steps - 1) x)
        | .flatMap ioe f =>
          SyncStep.IRes.wrap (fun s => .flatMap s (.flatMapSel f steps))
            (interpretFixed fuel ioe (limit - 1) (steps - 1) x)
        | .attempt ioe =>
          SyncStep.IRes.wrap (fun s => .handleErrorWith (.flatMap s (.pureMap .attemptSel)) (.attemptHandler limit))
            (interpretFixed fuel ioe (limit - 1) (steps - 1) x)
        | .handleErrorWith ioe f =>
          SyncStep.IRes.wrap
            (fun s => .handleErrorWith (.flatMap s (.pureMap (.hewSel f))) (.hewHandler f limit steps))
            (interpretFixed fuel ioe (limit - 1) (steps - 1) x)
        | .uncancelable body =>
          if syncIORootCancelScope == .uncancelable then
            match body with
            -- PR: `case IO.Uncancelable(bind: DeferredPoll.Bind[?], event)`: walk the rest
            | .user id =>
              match fixLamOf id with
              | some (.bind d c) =>
                match ofIoV c with
                | some rest => rewrapRes (.unc d) (interpretFixed fuel rest limit (steps - 1) x)
                | none => .abort .illTyped
              | _ => fresh body
            | _ => fresh body
          else .ok (.pure (.left (.io io))) x
        -- PR: `case IO.OnCancel(ioa, fin)`: rewrap the rest in `onCancel(fin)`
        | .onCancel ioa fin =>
          if syncIORootCancelScope == .uncancelable then
            rewrapRes (.onCancel fin) (interpretFixed fuel ioa limit (steps - 1) x)
          else .ok (.pure (.left (.io io))) x
        | _ => .ok (.pure (.left (.io io))) x
      match io with
      -- PR: `case IO.FlatMap(IO.Local(unmask: DeferredPoll.Unmask[?]), _, _)`: step `ioc`, rewrap
      | .flatMap (.local (.user u)) (.user a) =>
        match fixLamOf u, fixLamOf a with
        | some (.unmask d), some (.applyK c) =>
          match ofIoV c with
          | some ioc => rewrapRes (.deferred d) (interpretFixed fuel ioc limit (steps - 1) x)
          | none => .abort .illTyped
        | _, _ => general ()
      | _ => general ()

/-- `SyncStep.callS` with `interpretFixed` and `applyMapFixed` (the `SyncIO` closures are the
same as in v3.7.1; only the `interpret` they call and the new rewrap maps differ). -/
def callSFixed (fuel : Nat) (f : SFn) (arg : SVal) (x : Exec M) : SCall M :=
  match f with
  -- IO.scala:2358 the thunk of `G.delay(thunk())`
  | .ioThunk thunk =>
    match callUser mm env thunk .unit x with
    | .error a => .abort a
    | .ok (.ret v, x) => .ok (.ret (.val v)) x
    | .ok (.throw e, x) => .thrown e x
    | .ok (.prog _, _) => .abort .illTyped
  -- IO.scala:2353 the thunk of `G.defer(interpret(io, limit, MaxSteps))`
  | .deferInterpret io limit =>
    match interpretFixed mm env fuel io limit SyncStep.maxSteps x with
    | .ok s x => .ok (.ret (.sio s)) x
    | .thrown e x => .thrown e x
    | .outOfFuel => .outOfFuel
    | .abort a => .abort a
  -- Sync.scala:62 `x => x`
  | .flattenId =>
    match arg with
    | .sio s => .ok (.prog s) x
    | _ => .abort .illTyped
  -- cats/Monad.scala:35 `a => pure(f(a))`
  | .pureMap g =>
    match applyMapFixed mm env g arg x with
    | .ok v x => .ok (.prog (.pure v)) x
    | .thrown e x => .thrown e x
    | .abort a => .abort a
  -- IO.scala:2369-2372
  | .flatMapSel f steps =>
    match arg with
    -- `case Left(io) => G.pure(Left(io.flatMap(f)))`; `io.flatMap(f)` = `IO.FlatMap` (IO.scala:469-470)
    | .left (.io io) => .ok (.prog (.pure (.left (.io (.flatMap io f))))) x
    -- `case Right((a, limit)) => interpret(f(a), limit - 1, stepsUntilDefer - 1)`
    | .right (.pair (.val a) (.int limit)) =>
      match callUser mm env f a x with
      | .error ab => .abort ab
      | .ok (.prog p, x) => SyncStep.IRes.toCall (interpretFixed mm env fuel p (limit - 1) (steps - 1) x)
      | .ok (.throw e, x) => .thrown e x
      | .ok (.ret _, _) => .abort .illTyped
    | _ => .abort .illTyped
  -- IO.scala:2380 `t => (t.asLeft, limit - 1).asRight`, then `pure` (ApplicativeError.scala:105)
  | .attemptHandler limit =>
    match arg with
    | .err t => .ok (.prog (.pure (.right (.pair (.val (.left (.err t))) (.int (limit - 1)))))) x
    | _ => .abort .illTyped
  -- IO.scala:2388 `t => interpret(f(t), limit - 1, stepsUntilDefer - 1)`
  | .hewHandler f limit steps =>
    match arg with
    | .err t =>
      match callUser mm env f (.err t) x with
      | .error ab => .abort ab
      | .ok (.prog p, x) => SyncStep.IRes.toCall (interpretFixed mm env fuel p (limit - 1) (steps - 1) x)
      | .ok (.throw e, x) => .thrown e x
      | .ok (.ret _, _) => .abort .illTyped
    | _ => .abort .illTyped

/-- The closure meaning of the twin as a `SyncIOEnv`. -/
def senvFixed : SyncIOEnv M where
  call := callSFixed mm env

/-- `fa.syncStep(limit)` of the twin: `G.map(interpret(fa, limit, MaxSteps))(_.map(_._1))`
(unchanged by the PR). -/
def syncStepFixed (fuel : Nat) (fa : IO) (limit : Int) (x : Exec M) : IRes M :=
  SyncStep.IRes.wrap (fun s => .flatMap s (.pureMap .dropLimit))
    (interpretFixed mm env fuel fa limit SyncStep.maxSteps x)

/-- `fa.syncStep(limit).unsafeRunSync()` of the twin, then the law's selector. -/
def steppedRestFixed (fuel : Nat) (fa : IO) (limit : Int) (refs : List Val) :
    Except Summary (IO × Heap) :=
  SyncStep.steppedRestWith mm (syncStepFixed mm env) (senvFixed mm env) fuel fa limit refs

end SyncStepFixed

end CatsEffectInLean.Model

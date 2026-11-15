import CatsEffectInLean.Props.Phase7.Semaphore

/-!
# Wrong-function battery of `Semaphore` and `Mutex` (decision 63): definitions

Decision 63 (`raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md`): for each
public operation and each variant (raises, hangs, drops, doubles) a wrong function, and a
kernel-checked run on one input that breaks at least one registered statement
(`Proofs/Phase7/SemaphoreBattery.lean`). This module defines the wrong functions and the claims.

## How a wrong function is built

A wrong function replaces one public operation as the test program calls it, and nothing else:
`wrong op var e` wraps the correct environment `e`.

* `acquire`/`acquireN` (`acqRel n`, `n = 1` / `n ≥ 2`), `release`/`releaseN` (the `releaseN(n)` of
  `acqRel n`), `tryAcquire`/`tryAcquireN` (`tryRel n`): the harness closure that builds the call
  (`HS.acqRelBody`, `HS.constRel`, `HS.tryBody`) builds the wrong term instead.
* `available`, `count`, `permit` (`s.permit.use(g)`), `lock` (`m.lock.use(g)`): the term
  (`availableIO`, `countIO`, `permitUseIO`, `lockUseIO`) is replaced wherever a library or harness
  closure returns it (`rw`).

Variants: **raises** = `IO.raiseError(E9)` (non-fatal); **hangs** = an `IOCont` whose callback is
never called (`IO.never`); **drops** = returns without its effect (`acquire`: no permit taken,
`release`: no permit given back, `tryAcquire`: `true` without taking, `permit`/`lock`: the
`Allocate` step takes nothing); **doubles** = the effect twice (`acquireN(2n)`, `releaseN(2n)`,
`tryAcquireN(2n)`, `permit` takes 2 permits, `lock` enqueues itself twice). `available` and `count`
are reads with no effect, so drops/doubles are meaningless for them; the battery checks the variant
**wrong value** (the read returns one more) in their place.

The wrong-function closures `WL` (namespace 66) are not Cats Effect code and not in any `Lib`. The
inner environment `inner` runs them (also when `Bracket` calls them through the dispatcher).
-/

namespace CatsEffectInLean.Proofs.Phase7.SemaphoreBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Semaphore
open CatsEffectInLean.Props.Phase7.Semaphore

/-- The public operations of decision 63. -/
inductive Op where
  | acquire | acquireN | release | releaseN | tryAcquire | tryAcquireN | available | count | permit | lock
  /-- The factories `Semaphore[IO](k)` and `Mutex[IO]` (review batch 13, L3). -/
  | semApply | mutexApply
  deriving DecidableEq, Repr

/-- The variants (`wrongValue` replaces drops/doubles for the reads). -/
inductive Var where
  | raises | hangs | drops | doubles | wrongValue
  /-- A read that is right when nobody waits and wrong while the waiter queue is not empty
  (`available` returns one more, `count` one less; review batch 13, O1). -/
  | contended
  /-- Rule (a) of review batch 13: the honest drop of a try-operation answers `false` and has no
  effect (review batch 14, B1). -/
  | honestDrop
  deriving DecidableEq, Repr

def E9 : Err := { code := 9 }

def wns : Nat := 66

/-- Wrong-function closures. -/
inductive WL where
  /-- The `IOCont` body of `IO.never`: `cont => get` (the callback is never called). -/
  | never
  /-- `permit`'s `Allocate` step that takes nothing (`dbl = false`) or 2 permits (`dbl = true`). -/
  | permitAcq (l : Nat) (dbl : Bool)
  /-- `lock`'s `Allocate` step that makes a cell but does not enqueue it. -/
  | lockAcqDrop (m : Nat)
  /-- `lock`'s `Allocate` step that enqueues twice (the second waits for the first). -/
  | lockAcqDouble (m : Nat)
  /-- `_ => acquire(poll)` again. -/
  | again (m mm pp : Nat)
  /-- `x => x`. -/
  | retK
  /-- A read that returns one more. -/
  | plus1
  /-- `available` that returns `permits + 1` while the waiter queue is not empty. -/
  | availCont
  /-- `count` that returns one less while the waiter queue is not empty. -/
  | countCont
  deriving DecidableEq, Repr

def WL.toVal : WL → Val
  | .never => cloVal wns 0 []
  | .permitAcq l d => cloVal wns 1 [.fn l, .bool d]
  | .lockAcqDrop m => cloVal wns 2 [.fn m]
  | .lockAcqDouble m => cloVal wns 3 [.fn m]
  | .again m mm pp => cloVal wns 4 [.fn m, .poll mm pp]
  | .retK => cloVal wns 5 []
  | .plus1 => cloVal wns 6 []
  | .availCont => cloVal wns 7 []
  | .countCont => cloVal wns 8 []

def WL.id (l : WL) : Nat := 2 * valToNat l.toVal + 1
def WL.fn (l : WL) : Fn := .user l.id

def WL.ofId? (id : Nat) : Option WL :=
  if isLibId id then
    match (cloOfId id).bind ofCloVal with
    | some (66, 0, []) => some .never
    | some (66, 1, [.fn l, .bool d]) => some (.permitAcq l d)
    | some (66, 2, [.fn m]) => some (.lockAcqDrop m)
    | some (66, 3, [.fn m]) => some (.lockAcqDouble m)
    | some (66, 4, [.fn m, .poll mm pp]) => some (.again m mm pp)
    | some (66, 5, []) => some .retK
    | some (66, 6, []) => some .plus1
    | some (66, 7, []) => some .availCont
    | some (66, 8, []) => some .countCont
    | _ => none
  else none

/-- `IO.never`. -/
def hangIO : IO := .ioCont WL.never.fn

/-- `acquire(poll)` of `LockQueue` (`Model/Mutex.lean`, `ML.acq`). -/
def lockAcqIO (m mm pp : Nat) : IO :=
  .flatMap (.delay Mutex.ML.newDeferred.fn) (Mutex.ML.acqCell m mm pp).fn

private def illW : UserResult := { out := .throw { code := illCode, kind := .fatal } }

def WL.call (w : WL) (arg : Val) : UserResult :=
  match w with
  | .never =>
    match arg with
    | .cont s => { out := .prog (.contGet s) }
    | _ => illW
  | .permitAcq l d =>
    match arg with
    | .poll m p =>
      { out := .prog (.map (if d then IO.applyPoll (acquireNIO l 2) m p else .pure .unit) (SL.pairRel l).fn) }
    | _ => illW
  | .lockAcqDrop m =>
    match arg with
    | .poll _ _ => { out := .prog (.map (.delay Mutex.ML.newDeferred.fn) (Mutex.ML.pairRel m).fn) }
    | _ => illW
  | .lockAcqDouble m =>
    match arg with
    | .poll mm pp => { out := .prog (.map (.flatMap (lockAcqIO m mm pp) (WL.again m mm pp).fn) (Mutex.ML.pairRel m).fn) }
    | _ => illW
  | .again m mm pp => { out := .prog (lockAcqIO m mm pp) }
  | .retK => { out := .ret arg }
  | .plus1 =>
    match arg with
    | .nat n => { out := .ret (.nat (n + 1)) }
    | .int i => { out := .ret (.int (i + 1)) }
    | _ => illW
  | .availCont =>
    match arg with
    | .pair (.nat p) w => { out := .ret (.nat (if ((unlistV w).getD []).isEmpty then p else p + 1)) }
    | _ => illW
  | .countCont =>
    match (CatsEffectInLean.Model.Semaphore.call (fun _ _ _ => illW) .countK arg {}).out with
    | .ret (.int c) =>
      match arg with
      | .pair _ w => { out := .ret (.int (if ((unlistV w).getD []).isEmpty then c else c - 1)) }
      | _ => illW
    | _ => illW

/-- The inner environment: the `WL` closures, then `u`. -/
def inner (u : UserEnv) : UserEnv where
  call id a refs := if id % 2 == 0 then u.call id a refs else
    match WL.ofId? id with
    | some w => w.call a
    | none => u.call id a refs
  callV id a v := if id % 2 == 0 then u.callV id a v else
    match WL.ofId? id with
    | some w => w.call a
    | none => u.callV id a v

/-- The wrong term of a variant for a term `io` of the operation. -/
def badOf (var : Var) (io drop dbl : IO) : IO :=
  match var with
  | .raises => .error E9
  | .hangs => hangIO
  | .drops => drop
  | .doubles => dbl
  | .wrongValue | .contended | .honestDrop => io

/-- The replacement of a library term for the operations `available`, `count`, `permit`, `lock`. -/
def repl (op : Op) (var : Var) : IO → Option IO
  | .delay (.user t) =>
    match SL.ofId? t, var with
    | some (.modTry _ n), .honestDrop =>
      if (op == .tryAcquire && n == 1) || (op == .tryAcquireN && 2 ≤ n) then some (.pure (.bool false)) else none
    | _, _ => none
  | io@(.map (.delay (.user g)) (.user k)) =>
    match SL.ofId? g, SL.ofId? k, op with
    | some (.getThunk _), some .availK, .available =>
      some (match var with
        | .raises => .error E9
        | .hangs => hangIO
        | .contended => .map (.delay (.user g)) WL.availCont.fn
        | _ => .map io WL.plus1.fn)
    | some (.getThunk _), some .countK, .count =>
      some (match var with
        | .raises => .error E9
        | .hangs => hangIO
        | .contended => .map (.delay (.user g)) WL.countCont.fn
        | _ => .map io WL.plus1.fn)
    | some (.newRef _), some .mkSem, .semApply =>
      some (match var with
        | .hangs => hangIO
        | _ => .error E9)
    | _, _, _ =>
      match Mutex.ML.ofId? g, Mutex.ML.ofId? k, op with
      | some (.newRef _), some .mkMutex, .mutexApply =>
        some (match var with
          | .hangs => hangIO
          | _ => .error E9)
      | _, _, _ => none
  | io@(.uncancelable (.user b)) =>
    match Bracket.BLam.ofId? b, op with
    | some (.bfBody acq use rel), .permit =>
      match SL.ofId? acq with
      | some (.permitAcq l) =>
        some (badOf var io (Bracket.bracketFullIO (WL.permitAcq l false).id use rel)
          (Bracket.bracketFullIO (WL.permitAcq l true).id use rel))
      | _ => none
    | some (.bfBody acq use rel), .lock =>
      match Mutex.ML.ofId? acq with
      | some (.acq m) =>
        some (badOf var io (Bracket.bracketFullIO (WL.lockAcqDrop m).id use rel)
          (Bracket.bracketFullIO (WL.lockAcqDouble m).id use rel))
      | _ => none
    | _, _ => none
  | _ => none

/-- Replace the operation's terms in a program (structural). -/
def rw (f : IO → Option IO) : IO → IO
  | .map a g => (f (.map a g)).getD (.map (rw f a) g)
  | .flatMap a g => (f (.flatMap a g)).getD (.flatMap (rw f a) g)
  | .handleErrorWith a g => (f (.handleErrorWith a g)).getD (.handleErrorWith (rw f a) g)
  | .attempt a => (f (.attempt a)).getD (.attempt (rw f a))
  | .start a => (f (.start a)).getD (.start (rw f a))
  | .onCancel a b => (f (.onCancel a b)).getD (.onCancel (rw f a) (rw f b))
  | .unmaskRunLoop a m p => (f (.unmaskRunLoop a m p)).getD (.unmaskRunLoop (rw f a) m p)
  | x => (f x).getD x

/-- The wrong function `var` of operation `op`, around the correct environment `e`. -/
def outer (op : Op) (var : Var) (e : UserEnv) : UserEnv where
  call id a refs := e.call id a refs
  callV id a v :=
    if id % 2 == 0 then e.callV id a v else
    let r := e.callV id a v
    let r' : UserResult :=
      match r.out with
      | .prog p => { r with out := .prog (rw (repl op var) p) }
      | _ => r
    match HS.ofId? id with
    | some (.acqRelBody l n) =>
      if (op == .acquire && n == 1) || (op == .acquireN && 2 ≤ n) then
        match a with
        | .poll m s =>
          { out := .prog (.flatMap (IO.applyPoll (badOf var (acquireNIO l n) (.pure .unit) (acquireNIO l (2 * n))) m s)
              (HS.constRel l n).fn) }
        | _ => r'
      else r'
    | some (.constRel l n) =>
      if (op == .release && n == 1) || (op == .releaseN && 2 ≤ n) then
        { out := .prog (badOf var (releaseNIO l n) (.pure .unit) (releaseNIO l (2 * n))) }
      else r'
    | some (.tryBody l n) =>
      if (op == .tryAcquire && n == 1) || (op == .tryAcquireN && 2 ≤ n) then
        { out := .prog (.flatMap (badOf var (tryAcquireNIO l n) (.pure (.bool true)) (tryAcquireNIO l (2 * n)))
            (HS.ifRel l n).fn) }
      else r'
    | _ => r'

/-- The wrong environment of a statement with user code `u`. -/
def wrongEnv (op : Op) (var : Var) (u : UserEnv) : UserEnv :=
  outer op var (Mutex.env (inner (harnessed u)))

/-- The FIFO harness environment of statement 7 (the same closures as `fifoEnv`), with `WL`. -/
def fifoBase : UserEnv where
  call id a refs := match FL.ofId? id with
    | some h => h.call a { refs }
    | none => { out := .throw { code := illCode, kind := .fatal } }
  callV id a v := match FL.ofId? id with
    | some h => h.call a v
    | none => { out := .throw { code := illCode, kind := .fatal } }

def wrongFifo (op : Op) (var : Var) : UserEnv := outer op var (Mutex.env (inner fifoBase))

/-- The sequential root (statements 9 and 10) with a wrong function. -/
def wrongSeq (op : Op) (var : Var) : UserEnv := outer op var (Mutex.env (inner seqU))

/-! ## The claims of the statements as tests (on one observation) -/

/-- The conclusion of `semSeqSpec` (statement 9). -/
def c9 (k : Nat) (ops : List SOp) (o : Obs) : Bool :=
  o.out.reverse == (semSpec k ops).1 &&
    o.summary == (if (semSpec k ops).2 then .blocked else .done (.succeeded .unit))

/-- `OkJoined` as a test. -/
def okJoinedB (bus : List BUse) (as : List Act) (i : Nat) : Bool :=
  match bus[i]? with
  | some b => b.succeeds && as.contains (.join i) && !as.contains (.cancel i)
  | none => false

def joinsOk (bus : List BUse) (as : List Act) (o : Obs) : Bool :=
  (List.range bus.length).all fun i => !okJoinedB bus as i || o.out.any fun x =>
    match x with
    | .pair (.nat 62) (.pair (.nat j) (.ocSucceeded _)) => j == i
    | _ => false

/-- The conclusion of `semNoDeadlock` (statement 2). -/
def c2 (bus : List BUse) (as : List Act) (k : Nat) (o : Obs) : Bool :=
  match o.summary with
  | .done (.succeeded v) => availOf v == some (k + released as) && joinsOk bus as o
  | .fatal _ => true
  | _ => false

/-- The conclusion of `mutexNoDeadlock` (statement 5). -/
def c5 (bus : List BUse) (as : List Act) (o : Obs) : Bool :=
  match o.summary with
  | .done (.succeeded v) => v == .unit && joinsOk bus as o
  | .fatal _ => true
  | _ => false

/-- The conclusion of `semFifo` (statement 7). -/
def c7 (ns : List Nat) (r : Nat) (o : Obs) : Bool :=
  o.summary == .done (.succeeded (.int ((r : Int) - (ns.foldl (· + ·) 0 : Nat))))

/-- The conclusion of `mutexMutualExclusion` (statement 4). -/
def c4 (o : Obs) : Bool :=
  match highest o with
  | some h => h ≤ 1
  | none => false

end CatsEffectInLean.Proofs.Phase7.SemaphoreBattery

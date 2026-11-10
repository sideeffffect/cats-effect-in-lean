import Difftest.Env
import CatsEffectInLean.Model.Sched
import CatsEffectInLean.Model.SyncStep
import Std.Data.HashMap

/-!
# Replay mode: run a case on the model and print the Scala output line

`replayCase tc io` runs the root term on the multi-fiber scheduler (`Model.Sched`, mask model
`counterMaskModel`, default `Config`) and builds the same JSON line as the Scala runner in
replay mode (`difftest/src/main/scala/cats/effect/difftest/Runner.scala`, `replay`).

The scheduler runs one micro-step per `Sched.tick`. This glue watches the state after each
micro-step and keeps the parts of the Scala output that the model does not hold:

* Fiber handles (decision 14). Scala numbers fibers by `h.fiberHandle` (root = 0, then each
  `start` result). The `fiberHandle` closure emits a `handle` event with the model fiber id;
  this glue gives handles in the order of these events. A `{"cancel":h}` choice maps `h` to the
  model id when it is used; an unknown `h` is a skipped cancel, as in Scala. Fiber values in the
  output are printed with their handles.
* Task labels (`ScriptedEC.label`): `f<k>` at the first enqueue of a fiber, `x<k>` for an
  external canceller, `cb<a>.<i>` for a `later` callback task, `t<k>` for a timer task.
* Time: the model clock is in milliseconds (the unit of `sleep`), as the `time` field and the
  `advance` log entries of Scala (`now / 1000000`). `labels` is aligned with the ready
  list (`Heap.ready`): a pick removes one entry, and new entries are appended at the end.
* Async ids: Scala counts `async` registrations (`h.newAsync`); the model events hold the
  `ContState` id. The glue renumbers by the first `asyncReg` event.
* The `cb` event of a `later` callback: in Scala the task emits it before it calls `cb`
  (`Interp.scala`, `fire`). The model task is runtime code (`contCallback`), so the glue adds
  the event when it picks the task.
* `failures`: user `reportFailure` calls (emitted as `TraceEv.failure`) and runtime ones
  (`Model.TraceEv.reportFailure`). Inside one micro-step, runtime ones come last: after a runtime
  `reportFailure` (`done`, `cancelationLoopFailureK`) the iteration runs no more user code.
* `Ref` and queue handles (format v1). The queue mirror keeps its state in model `Ref` cells, so
  a model cell id is not the Scala `Ref` handle. The `refH` and `queueH` events (emitted when
  Scala calls `h.newRef` / `h.newQueue`) give the handles in creation order. A `Val.ref` prints
  as a queue if its cell is a queue buffer, else as the `Ref` handle of the cell.
* Root `syncStep` (format v1): `syncStepInit` runs the `SyncIO` part (`SyncStep.steppedRest`)
  before the scheduler starts; the run starts on the heap it left (its emitted events come
  first in the trace).

This is test glue, not model logic. It never changes the model state.
-/

namespace Difftest

open CatsEffectInLean.Model
open Lean (Json ToJson toJson)

/-- The mask model of the replay run: the `IOFiber` mirror. -/
abbrev RMask := CounterMask

/-- A task label. `cb` holds (async id, callback index) for callback tasks. -/
structure Lbl where
  name : String
  cb : Option (Nat × Nat) := none

/-- The state of one replay run. -/
structure RS where
  s : Sched RMask
  /-- Choices not used yet (Scala handles). -/
  cs : List Choice
  outLen : Nat := 0
  trLen : Nat := 0
  logLen : Nat := 0
  /-- Labels of the ready list, in the same order. -/
  labels : Array Lbl := #[]
  fibLabel : Std.HashMap Nat String := {}
  fc : Nat := 0
  xc : Nat := 0
  /-- Handle → model fiber id. -/
  hids : Array Nat := #[0]
  /-- Model fiber id → handle. -/
  hOf : Std.HashMap Nat Nat := ({} : Std.HashMap Nat Nat).insert 0 0
  /-- Model `Ref` cell id → Scala `Ref` handle. -/
  refOf : Std.HashMap Nat Nat := {}
  /-- Model buffer cell id → Scala queue handle. -/
  qOf : Std.HashMap Nat Nat := {}
  /-- `ContState` id → async id. -/
  asyncIds : Std.HashMap Nat Nat := {}
  /-- `ContState` id → indices of `later` callbacks not yet in the ready list. -/
  later : Std.HashMap Nat (List Nat) := {}
  trace : Array TraceEv := #[]
  failures : Array String := #[]
  log : Array Json := #[]
  fifoFrom : Option Nat := none
  /-- A glue error (an event or a ready list that the glue cannot read). -/
  glueErr : Option String := none

/-- The Scala text of a `reportFailure` argument (`ScriptedEC.reportFailure`). A
`TimeoutException` prints without its message (format v1; the model does not keep it). -/
def errText (e : Err) : String :=
  if e == Timeout.timeoutErr then "TimeoutException" else
  match userCode? e with
  | some c => s!"UserError: UserError({c})"
  | none => if e == typeErr then "TypeError: ?" else s!"ModelError: code {e.code}"

namespace RS

def setErr (r : RS) (m : String) : RS :=
  match r.glueErr with
  | some _ => r
  | none => { r with glueErr := some m }

/-- Read the new emitted events and runtime failures, and label the new ready entries. -/
def absorb (r : RS) : RS := Id.run do
  let h := r.s.liveHeap
  let mut r := r
  -- user events (newest first in `Heap.out`)
  let n := h.out.length
  for v in (h.out.take (n - r.outLen)).reverse do
    match TraceEv.ofVal? v with
    | some (.handle i) =>
      if !r.hOf.contains i then
        r := { r with hOf := r.hOf.insert i r.hids.size, hids := r.hids.push i }
    | some (.asyncReg st) =>
      let a := r.asyncIds.size
      r := { r with asyncIds := r.asyncIds.insert st a, trace := r.trace.push (.asyncReg a) }
    | some (.cb st i) =>
      match r.asyncIds.get? st with
      | some a => r := { r with trace := r.trace.push (.cb a i) }
      | none => r := r.setErr "cb event before asyncReg"
    | some (.cbLater st i) =>
      r := { r with later := r.later.insert st ((r.later.getD st []) ++ [i]) }
    | some (.failure e) => r := { r with failures := r.failures.push (errText e) }
    | some (.refH i) =>
      if !r.refOf.contains i then r := { r with refOf := r.refOf.insert i r.refOf.size }
    | some (.queueH b) =>
      if !r.qOf.contains b then r := { r with qOf := r.qOf.insert b r.qOf.size }
    | some e => r := { r with trace := r.trace.push e }
    | none => r := r.setErr s!"unknown emitted value {repr v}"
  r := { r with outLen := n }
  -- runtime events (newest first in `Heap.trace`)
  let m := h.trace.length
  for e in (h.trace.take (m - r.trLen)).reverse do
    match e with
    | .reportFailure t => r := { r with failures := r.failures.push (errText t) }
    | _ => pure ()
  r := { r with trLen := m }
  -- new ready entries
  let rd := h.ready.toArray
  if rd.size < r.labels.size then
    return r.setErr "ready list shorter than its labels"
  for t in rd.extract r.labels.size rd.size do
    match (t : Task) with
    | .fiber i =>
      match r.fibLabel.get? i with
      | some l => r := { r with labels := r.labels.push { name := l } }
      | none =>
        let l := s!"f{r.fc}"
        r := { r with labels := r.labels.push { name := l }, fibLabel := r.fibLabel.insert i l,
                      fc := r.fc + 1 }
    | .cb st _ =>
      match r.asyncIds.get? st, r.later.getD st [] with
      | some a, i :: rest =>
        r := { r with labels := r.labels.push { name := s!"cb{a}.{i}", cb := some (a, i) },
                      later := r.later.insert st rest }
      | _, _ => r := r.setErr "callback task without a later callback"
    -- a timer task of the virtual-time `Scheduler`: `CbTask(s"t$timerCount", …)`
    | .timer k _ => r := { r with labels := r.labels.push { name := s!"t{k}" } }
  return r

/-- The labels of the ready list as JSON. -/
def readyJson (r : RS) : Json := Json.arr (r.labels.map (fun l => Json.str l.name))

/-- One micro-step of the scheduler, with the glue bookkeeping. -/
def step (cfg : Config) (env : UserEnv) (maxTasks : Nat) (r : RS) : RS :=
  let s := r.s
  if s.cur.isSome then
    let (s', _) := s.tick cfg counterMaskModel env maxTasks []
    absorb { r with s := s' }
  else
    -- between tasks: convert the next choice (handles → model ids)
    let (given, hd) : List RChoice × Option Nat := match r.cs with
      | .pick n :: _ => ([.pick n], none)
      | .cancelFiber h :: _ =>
        match r.hids[h]? with
        | some t => ([.cancel t], some h)
        -- an id that no fiber has: the model logs a skipped cancel
        | none => ([.cancel (s.fibers.length + 1)], some h)
      | [] => ([], none)
    let ready0 := r.readyJson
    let (s', rest) := s.tick cfg counterMaskModel env maxTasks given
    let r := { r with s := s' }
    let r := if rest.length < given.length then { r with cs := r.cs.tail } else r
    if s'.log.length == r.logLen then absorb r
    else
      let r := { r with logLen := s'.log.length }
      let stepNo := s'.tasks - 1
      match s'.log.head? with
      | some (.pick idx _) =>
        let lbl := r.labels[idx]?.getD { name := "?" }
        let r := if given.isEmpty && r.fifoFrom.isNone then { r with fifoFrom := some stepNo } else r
        let r := { r with labels := r.labels.eraseIdxIfInBounds idx,
                          log := r.log.push (Json.mkObj [("step", toJson stepNo), ("ready", ready0),
                            ("pick", toJson idx), ("task", .str lbl.name)]) }
        let r := match lbl.cb with
          | some (a, i) => { r with trace := r.trace.push (.cb a i) }
          | none => r
        let r := if lbl.name == "?" then r.setErr "pick of an unlabeled task" else r
        absorb r
      | some (.cancel _ cid) =>
        let l := s!"x{r.xc}"
        let r := { r with fibLabel := r.fibLabel.insert cid l, xc := r.xc + 1,
                          log := r.log.push (Json.mkObj [("step", toJson stepNo), ("ready", ready0),
                            ("cancel", toJson (hd.getD 0)), ("task", .str l)]) }
        absorb r
      | some (.cancelSkipped _) =>
        absorb { r with log := r.log.push (Json.mkObj [("cancel", toJson (hd.getD 0)),
                                                        ("skipped", .bool true)]) }
      | some (.advance t woken) =>
        -- `{"advance":ms,"woken":[…]}`; the woken timers are now at the end of the ready list
        absorb { r with log := r.log.push (Json.mkObj [("advance", toJson t),
          ("woken", Json.arr (woken.map (fun k => Json.str s!"t{k}")).toArray)]) }
      | none => absorb (r.setErr "empty schedule log")

/-- Run at most `fuel` micro-steps. -/
def run (cfg : Config) (env : UserEnv) (maxTasks : Nat) : (fuel : Nat) → RS → RS
  | 0, r => r
  | fuel + 1, r =>
    match r.s.halt, r.glueErr with
    | none, none => run cfg env maxTasks fuel (step cfg env maxTasks r)
    | _, _ => r

end RS

/-! ## Output -/

/-- An error value (`Json.encodeErr`). -/
def errJson (e : Err) : Json :=
  match userCode? e with
  | some c => Json.mkObj [("t", "errored"), ("code", toJson c)]
  | none => Json.mkObj [("t", "errored"), ("exn", .str (errText e))]

/-- The handle tables of a run: fibers, `Ref`s, queues (model id → Scala handle). -/
structure Ren where
  hOf : Std.HashMap Nat Nat
  refOf : Std.HashMap Nat Nat := {}
  qOf : Std.HashMap Nat Nat := {}

instance : Coe (Std.HashMap Nat Nat) Ren := ⟨fun h => { hOf := h }⟩

/-- A value (`Json.encodeVal`); fiber, `Ref` and queue ids become handles. -/
def valJson (hOf : Ren) : Val → Json
  | .unit => Json.mkObj [("t", "unit")]
  | .bool b => Json.mkObj [("t", "bool"), ("v", .bool b)]
  | .nat n => Json.mkObj [("t", "nat"), ("v", toJson n)]
  | .pair a b => Json.mkObj [("t", "pair"), ("a", valJson hOf a), ("b", valJson hOf b)]
  | .left v => Json.mkObj [("t", "left"), ("v", valJson hOf v)]
  | .right v => Json.mkObj [("t", "right"), ("v", valJson hOf v)]
  | .ocSucceeded v => Json.mkObj [("t", "succeeded"), ("v", valJson hOf v)]
  | .ocErrored e => errJson e
  | .ocCanceled => Json.mkObj [("t", "canceled")]
  | .fiber i => Json.mkObj [("t", "fiber"), ("id", toJson (hOf.hOf.getD i (1000000 + i)))]
  | .ref i =>
    match hOf.qOf.get? i with
    | some q => Json.mkObj [("t", "queue"), ("id", toJson q)]
    | none => Json.mkObj [("t", "ref"), ("id", toJson (hOf.refOf.getD i (1000000 + i)))]
  | .deferred i => Json.mkObj [("t", "deferred"), ("id", toJson i)]
  | v => Json.mkObj [("t", .str s!"model:{(repr v).pretty}")]

/-- The `op` of a format v2 `fin` event. -/
def v2FinOp : Nat → String
  | 0 => "guarantee" | 1 => "bracket" | 2 => "bracketCase" | 3 => "bracketFull" | _ => "?"

/-- A trace event (`Interp.scala` `ev`). -/
def evJson (hOf : Ren) : TraceEv → Json
  | .call fn arg => Json.mkObj [("ev", "call"), ("fn", toJson fn), ("arg", valJson hOf arg)]
  | .finOnCancel tag => Json.mkObj [("ev", "fin"), ("op", "onCancel"), ("tag", toJson tag)]
  | .finAsync tag => Json.mkObj [("ev", "fin"), ("op", "async"), ("tag", toJson tag)]
  | .finGuaranteeCase tag oc =>
    Json.mkObj [("ev", "fin"), ("op", "guaranteeCase"), ("tag", toJson tag), ("oc", valJson hOf oc)]
  | .set ref v =>
    Json.mkObj [("ev", "set"), ("ref", toJson (hOf.refOf.getD ref (1000000 + ref))), ("v", valJson hOf v)]
  | .complete d v ok =>
    Json.mkObj [("ev", "complete"), ("deferred", toJson d), ("v", valJson hOf v), ("ok", .bool ok)]
  | .asyncReg a => Json.mkObj [("ev", "asyncReg"), ("async", toJson a)]
  | .cb a i => Json.mkObj [("ev", "cb"), ("async", toJson a), ("i", toJson i)]
  | .finV2 op tag none =>
    Json.mkObj [("ev", "fin"), ("op", .str (v2FinOp op)), ("tag", toJson tag)]
  | .finV2 op tag (some oc) =>
    Json.mkObj [("ev", "fin"), ("op", .str (v2FinOp op)), ("tag", toJson tag), ("oc", valJson hOf oc)]
  | e => Json.mkObj [("ev", .str s!"internal:{(repr e).pretty}")]

/-- The outcome of a run. A model result that is not a Cats Effect result prints as
`{"t":"model:…"}`, so the driver sees a mismatch. -/
def summaryJson (hOf : Ren) : Summary → Json
  | .done (.succeeded v) => Json.mkObj [("t", "succeeded"), ("v", valJson hOf v)]
  | .done (.errored e) => errJson e
  | .done .canceled => Json.mkObj [("t", "canceled")]
  | .blocked => Json.mkObj [("t", "blocked")]
  | .taskLimit => Json.mkObj [("t", "fuel")]
  | s => Json.mkObj [("t", .str s!"model:{(repr s).pretty}")]

/-- The fields of the output line that the driver compares (all of the Scala replay fields). -/
def comparedFields : List String :=
  ["outcome", "trace", "steps", "time", "schedule", "fifoFrom", "fibers", "pending", "failures"]

/-- Micro-step fuel for `maxSteps` tasks: one task is at most `autoYieldThreshold` iterations
plus the unwinding at its start. -/
def replayFuel (cfg : Config) (maxSteps : Nat) : Nat := (maxSteps + 1) * (cfg.autoYieldThreshold + 64) + 64

/-- Fuel of the `SyncIO` part of a root `syncStep` (`interpret` calls and `SyncIO` run-loop
iterations). Out of fuel prints a `model:` outcome, so the driver sees a mismatch. -/
def syncStepFuel : Nat := 1000000

/-- The start state of a root `syncStep e limit` (`Interp.root`): run
`I(e).syncStep(limit).unsafeRunSync()` on the caller thread (`SyncStep.steppedRest`, no fiber
yet, no `Ref` cells), then the selected `IO` is the root fiber on the heap that the `SyncIO` part
left. `.error s`: the model stops in the `SyncIO` part (`outOfFuel`, `aborted`). -/
def syncStepInit (p : Prog) (io : IO) (limit : Nat) : Except Summary (Sched RMask) :=
  match SyncStep.steppedRest counterMaskModel (userEnv p) syncStepFuel io (limit : Int) [] with
  | .error s => .error s
  | .ok (rest, h) =>
    let s := Sched.init counterMaskModel rest
    .ok { s with heap := { h with ready := h.ready ++ s.heap.ready } }

/-- Run case `tc` from the scheduler state `s0` (the root term on `Sched.init`, or
`syncStepInit`) in replay mode with runtime thresholds `cfg` (case field `runtime`); the output
fields (without `v`, `id`, `mode`). -/
def replayFields (cfg : Config) (p : Prog) (choices : List Choice) (maxSteps : Nat) (s0 : Sched RMask) :
    List (String × Json) :=
  let env := userEnv p
  let r0 : RS := { s := s0, cs := choices }
  let r := RS.run cfg env maxSteps (replayFuel cfg maxSteps) r0.absorb
  let hOf : Ren := { hOf := r.hOf, refOf := r.refOf, qOf := r.qOf }
  let outcome := match r.glueErr with
    | some m => Json.mkObj [("t", .str s!"glue:{m}")]
    | none => summaryJson hOf r.s.summary
  let fibers := Json.mkObj ((r.hids.toList.zipIdx).map fun (i, h) =>
    (toString h, Json.str (r.fibLabel.getD i "?")))
  [("outcome", outcome), ("trace", Json.arr (r.trace.map (evJson hOf))),
   ("steps", toJson r.s.tasks), ("time", toJson r.s.liveHeap.clock), ("schedule", Json.arr r.log),
   ("fifoFrom", match r.fifoFrom with | some n => toJson n | none => .null),
   -- `ec.ready.size + timers.size`
   ("fibers", fibers), ("pending", toJson (r.s.liveHeap.ready.length + r.s.liveHeap.timers.length)),
   ("failures", Json.arr (r.failures.map Json.str)),
   ("compare", Json.arr (comparedFields.map Json.str).toArray)]

end Difftest

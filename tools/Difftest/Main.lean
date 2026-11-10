import Difftest.Replay

/-!
# `lake exe cediff`: Lean side of the difftest

Usage: `lake exe cediff [FILE.jsonl …]` (no file: read stdin).

For each input line (a test case, format v0 or v1) it decodes the case, translates the program
into the root `Model.IO` term, and prints one JSON line (`v` is the version of the input line):

* Replay mode, all ops supported: the model runs the case (`Difftest.Replay`) and the line has
  the fields of the Scala replay output (`outcome`, `trace`, `steps`, `time`, `schedule`,
  `fifoFrom`, `fibers`, `pending`, `failures`), plus `compare`: the fields that the driver
  compares.
* `{"v":0,"id":…,"mode":…,"outcome":"unsupported","size":n,"unsupported":[…]}`: the case is
  accepted, but the model cannot run it: an op that the step function does not mirror
  (`unsupportedReason`), the resource restriction (`resource-reads-state`), or testcontrol
  mode (`mode:testcontrol`, decision 15).
* A root `syncStep e limit` runs `SyncStep.steppedRest` first (`Difftest.syncStepInit`).
* `{"v":0,"id":…,"error":"decode: …"}` or `"error":"translate: …"`: the case is rejected.

Exit code 0 if all cases are accepted, 1 otherwise. A summary goes to stderr.
`partial def` is used only in this I/O glue (the stdin loop).
-/

namespace Difftest

open Lean (Json)

/-- The id of a line, if the line is a JSON object with a string `id`. -/
def lineId (j : Json) : Json :=
  match j.getObjVal? "id" with
  | .ok (.str s) => .str s
  | _ => .null

/-- A JSON object field. -/
def kv (k : String) (v : Json) : String × Json := (k, v)

/-- Result of one line: the output JSON, accepted?, and run on the model? -/
def processLine (line : String) : Json × Bool × Bool :=
  match Json.parse line with
  | .error e =>
    (Json.mkObj [kv "v" 0, kv "id" .null, kv "error" (.str s!"decode: bad JSON: {e}")], false, false)
  | .ok j =>
    match decodeCase j with
    | .error e => (Json.mkObj [kv "v" 0, kv "id" (lineId j), kv "error" (.str s!"decode: {e}")], false, false)
    | .ok tc =>
      let mode : String := match tc.mode with | .replay _ => "replay" | .testcontrol _ => "testcontrol"
      let uns := unsupportedOps tc.prog
      let unsJ := kv "unsupported" (Json.arr (uns.map Json.str).toArray)
      let base := [kv "v" (Lean.toJson tc.version), kv "id" (.str tc.id), kv "mode" (.str mode)]
      match rootTerm tc.prog with
      | .error .typeError =>
        (Json.mkObj (base ++ [kv "error" (.str "translate: TypeError while building the root term")]),
         false, false)
      | .error (.unsupported op) =>
        (Json.mkObj (base ++ [kv "outcome" (.str "unsupported"), kv "size" .null, unsJ,
          kv "reason" (.str s!"{op}: {unsupportedReason op}")]), true, false)
      | .ok io =>
        match tc.mode, uns with
        | .replay choices, [] =>
          match tc.prog with
          | .syncStep _ limit =>
            match syncStepInit tc.prog io limit with
            | .ok s0 => (Json.mkObj (base ++ replayFields tc.prog choices tc.maxSteps s0), true, true)
            | .error sm =>
              (Json.mkObj (base ++ [kv "outcome" (Json.mkObj [kv "t" (.str s!"model:syncStep:{(repr sm).pretty}")]),
                kv "compare" (Json.arr #[.str "outcome"])]), true, true)
          | _ =>
            (Json.mkObj (base ++ replayFields tc.prog choices tc.maxSteps
              (CatsEffectInLean.Model.Sched.init CatsEffectInLean.Model.counterMaskModel io)), true, true)
        | .testcontrol _, [] =>
          (Json.mkObj (base ++ [kv "outcome" (.str "unsupported"), kv "size" (ioSize io),
            kv "unsupported" (Json.arr #[.str "mode:testcontrol"])]), true, false)
        | _, _ =>
          (Json.mkObj (base ++ [kv "outcome" (.str "unsupported"), kv "size" (ioSize io), unsJ]),
           true, false)

/-- Read all lines of a stream. -/
partial def readLines (h : IO.FS.Stream) (acc : Array String := #[]) : IO (Array String) := do
  let l ← h.getLine
  if l.isEmpty then pure acc else readLines h (acc.push l)

end Difftest

open Difftest in
def main (args : List String) : IO UInt32 := do
  let lines ← if args.isEmpty then readLines (← IO.getStdin)
    else args.foldlM (fun acc f => do pure (acc ++ (← IO.FS.lines ⟨f⟩))) #[]
  let lines := lines.map String.trimAscii |>.map (·.toString) |>.filter (!·.isEmpty)
  let out ← IO.getStdout
  let mut accepted := 0
  let mut full := 0
  for l in lines do
    let (j, ok, isFull) := processLine l
    out.putStrLn j.compress
    if ok then accepted := accepted + 1
    if isFull then full := full + 1
  IO.eprintln s!"cediff: {lines.size} cases, {accepted} accepted, {full} run on the model"
  pure (if accepted = lines.size then 0 else 1)

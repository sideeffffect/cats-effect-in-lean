# python-formalization Lean core: Core.lean, Registry.lean, Audit.lean, lakefile, difftest/common.py (verbatim)

> Source: https://github.com/Broyojo/python-formalization/blob/main/lean
> Collected: 2026-11-10
> Published: 2026-10-29

## lean/lean-toolchain

````
leanprover/lean4:v4.35.0
````

## lean/lakefile.toml

````
name = "PyLean"
defaultTargets = ["PyLean", "pydiff"]

[[lean_lib]]
name = "PyLean"
roots = ["PyLean", "PyLean.All"]
# Per-file memory cap (MB), so a runaway elaboration fails instead of
# exhausting the machine.
moreLeanArgs = ["-M8000"]

[[lean_exe]]
name = "pydiff"
root = "DiffMain"
````

## lean/PyLean/Core.lean

````
/-!
Shared vocabulary for CPython models.

* A Python exception is a value of `PyExc`; a model function returns `Py α`.
* Python `int` is Lean `Int` (or `Nat` where the source guarantees `>= 0`).
  There is no wraparound in pure-Python code; C code that narrows to
  `Py_ssize_t` must model that narrowing explicitly with `ssize`.
* Loops are written with explicit fuel. Running out of fuel is reported as
  `PyExc.modelFuel`, which never corresponds to Python behaviour, so properties
  quantify over inputs where the source loop terminates.
-/

namespace PyLean

/-- Exception classes that models raise. The message is compared exactly
by the differential tester, so models copy the source's format string. -/
inductive PyExc where
  | valueError (msg : String)
  | typeError (msg : String)
  | indexError (msg : String)
  | keyError (msg : String)
  | overflowError (msg : String)
  | zeroDivisionError (msg : String)
  | assertionError (msg : String)
  | stopIteration
  /-- A module-defined exception class, e.g. `ipaddress.NetmaskValueError`. -/
  | named (cls : String) (msg : String)
  /-- Not a Python exception: the model's loop fuel ran out. -/
  | modelFuel
  deriving Repr, DecidableEq, Inhabited

/-- Name of the Python exception class, as `type(e).__name__` prints it. -/
def PyExc.className : PyExc → String
  | .valueError _ => "ValueError"
  | .typeError _ => "TypeError"
  | .indexError _ => "IndexError"
  | .keyError _ => "KeyError"
  | .overflowError _ => "OverflowError"
  | .zeroDivisionError _ => "ZeroDivisionError"
  | .assertionError _ => "AssertionError"
  | .stopIteration => "StopIteration"
  | .named cls _ => cls
  | .modelFuel => "<model fuel exhausted>"

def PyExc.message : PyExc → String
  | .valueError m | .typeError m | .indexError m | .keyError m
  | .overflowError m | .zeroDivisionError m | .assertionError m | .named _ m => m
  | .stopIteration | .modelFuel => ""

/-- Result of evaluating Python code: a value or a raised exception. -/
abbrev Py (α : Type) := Except PyExc α

instance {α : Type} [DecidableEq α] : DecidableEq (Py α)
  | .ok a, .ok b => if h : a = b then .isTrue (h ▸ rfl) else .isFalse (fun e => h (Except.ok.inj e))
  | .error a, .error b => if h : a = b then .isTrue (h ▸ rfl) else .isFalse (fun e => h (Except.error.inj e))
  | .ok _, .error _ => .isFalse (fun e => nomatch e)
  | .error _, .ok _ => .isFalse (fun e => nomatch e)

/-- `True` when the computation raised an exception of the given class. -/
def Py.raises {α : Type} (r : Py α) (cls : String) : Prop :=
  ∃ e, r = .error e ∧ e.className = cls

/-- `int.bit_length()` on a non-negative int. -/
def bitLength (n : Nat) : Nat := if n = 0 then 0 else Nat.log2 n + 1

/-- Python `~a & b` for `a b >= 0`. Since `b` has no bits at or above
`bit_length(b)`, complementing `a` within that width is exact. -/
def notAnd (a b : Nat) : Nat := ((2 ^ bitLength b - 1) ^^^ a) &&& b

/-- `Py_ssize_t` on a 64-bit build. -/
def ssizeMin : Int := -(2 ^ 63)
def ssizeMax : Int := 2 ^ 63 - 1

end PyLean
````

## lean/PyLean/Registry.lean

````
import Lean

/-!
Every property gets one registry entry. `Audit.lean` checks that each `thm`
has type exactly `prop` (proven) or `¬ prop` (refuted), and that it depends on
no axioms beyond `propext`, `Classical.choice` and `Quot.sound`.
-/

namespace PyLean.Registry

inductive Status where
  /-- The property holds for every input; `thm : prop`. -/
  | proven
  /-- A counterexample exists; `thm : ¬ prop`. A refutation must also have a
  plain-Python reproducer under `bugs/`. -/
  | refuted
  /-- Stated but neither proven nor refuted yet. The audit counts these, and they
  do not count towards coverage. -/
  | open
  deriving Repr, DecidableEq, Inhabited

structure Entry where
  id : String
  /-- Path relative to CPython's `Lib/` (or `Objects/`, `Modules/` for C). -/
  pyFile : String
  pyFns : List String
  /-- The property in plain English, quantified over all inputs. -/
  statement : String
  /-- Where the promise comes from: docstring, docs page, or "invariant". -/
  source : String
  status : Status
  prop : Lean.Name
  thm : Option Lean.Name := none
  /-- For refutations: the `bugs/*.yaml` id. -/
  bug : Option String := none
  notes : String := ""
  deriving Inhabited

end PyLean.Registry
````

## lean/Audit.lean

````
import PyLean.All

/-!
Registry audit, run with `lake env lean Audit.lean`. Fails on a duplicate id, and unless every entry
marked proven or refuted has a theorem whose type is exactly the registered
property (or its negation) and which uses only the standard axioms. Open
entries are counted, not fatal; only settled entries count towards coverage. A `sorry`
anywhere in a proof shows up here as the axiom `sorryAx`.
-/

open Lean Elab Command PyLean PyLean.Registry


def allowedAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

#eval show CommandElabM Unit from do
  let env ← getEnv
  let mut failures : Array String := #[]
  let mut proven : Nat := 0
  let mut refuted : Nat := 0
  let mut openCount : Nat := 0
  let ids := allEntries.map (·.id)
  for i in ids.eraseDups do
    if ids.count i > 1 then failures := failures.push s!"{i}: duplicate registry id"
  for e in allEntries do
    if e.status == .open then
      openCount := openCount + 1
      continue
    let some thm := e.thm | failures := failures.push s!"{e.id}: no theorem"; continue
    let some info := env.find? thm | failures := failures.push s!"{e.id}: unknown {thm}"; continue
    if env.find? e.prop |>.isNone then
      failures := failures.push s!"{e.id}: unknown property {e.prop}"; continue
    let expected := match e.status with
      | .refuted => mkApp (mkConst ``Not) (mkConst e.prop)
      | _ => mkConst e.prop
    if info.type != expected then
      failures := failures.push s!"{e.id}: {thm} does not state {if e.status == .refuted then "¬ " else ""}{e.prop}"
      continue
    let axs ← liftCoreM (collectAxioms thm)
    let bad := axs.filter (· ∉ allowedAxioms)
    if !bad.isEmpty then
      failures := failures.push s!"{e.id}: {thm} uses {bad.toList}"
      continue
    if e.status == .refuted then
      if e.bug.isNone then failures := failures.push s!"{e.id}: refuted without a bug id"; continue
      refuted := refuted + 1
    else
      proven := proven + 1
  logInfo m!"{allEntries.length} properties: {proven} proven, {refuted} refuted, {openCount} open, {failures.size} failing"
  for f in failures do logInfo m!"FAIL {f}"
  unless failures.isEmpty do throwError "audit failed"
````

## lean/PyLean/DiffCore.lean

````
import Lean.Data.Json
import PyLean.Core

/-!
Helpers shared by the per-module differential-testing handlers
(`PyLean/<Module>/Diff.lean`). A handler receives the case's `fn` name and the
whole JSON case, and returns `none` for a name it does not know.
-/

namespace PyLean.Diff

open Lean

/-- `{"ok": v}` or `{"exc": "<class>", "msg": "<message>"}`. -/
def encPy {α : Type} (enc : α → Json) : Py α → Json
  | .ok v => Json.mkObj [("ok", enc v)]
  | .error e => Json.mkObj [("exc", toJson e.className), ("msg", toJson e.message)]

def field (j : Json) (key : String) : Except String Json := j.getObjVal? key

def getNat (j : Json) (key : String) : Except String Nat := do (← field j key).getNat?
def getInt (j : Json) (key : String) : Except String Int := do (← field j key).getInt?
def getStr (j : Json) (key : String) : Except String String := do (← field j key).getStr?
def getBool (j : Json) (key : String) : Except String Bool := do (← field j key).getBool?

/-- An optional int argument: absent or `null` is `none`. -/
def getOptInt (j : Json) (key : String) : Except String (Option Int) :=
  match j.getObjVal? key with
  | .ok .null | .error _ => .ok none
  | .ok v => some <$> v.getInt?

abbrev Handler := String → Json → Option (Except String Json)

end PyLean.Diff
````

## lean/DiffMain.lean

````
import Lean.Data.Json
import PyLean

/-!
Differential-testing driver. Reads one JSON case per line on stdin,
`{"mod": "<module>", "fn": "<name>", ...args}`, and writes one JSON result per
line: `{"ok": <value>}` or `{"exc": "<class>", "msg": "<message>"}`. Each module
supplies its handler in `PyLean/<Module>/Diff.lean`.
-/

open Lean PyLean.Diff

def handlers : List (String × Handler) := [
  ("ipaddress", PyLean.Ipaddress.handler),
  ("datetime", PyLean.Datetime.handler),
  ("fractions", PyLean.Fractions.handler),
  ("rangeslice", PyLean.RangeSlice.handler),
  ("mathint", PyLean.MathInt.handler),
  ("strsearch", PyLean.StrSearch.handler),
  ("accel", PyLean.Accel.handler),
  ("decimal", PyLean.Decimal.handler),
  ("pyio", PyLean.PyIO.handler),
  ("json", PyLean.JsonMod.handler),
  ("pickle", PyLean.Pickle.handler),
  ("itertools", PyLean.Itertools.handler),
  ("sequences", PyLean.Sequences.handler),
  ("listsort", PyLean.ListSort.handler),
  ("binary64", PyLean.Binary64.handler),
  ("dictset", PyLean.DictSet.handler),
  ("longobj", PyLean.LongObj.handler),
  ("bytesobj", PyLean.BytesObj.handler),
  ("unicodeobj", PyLean.UnicodeObj.handler),
  ("typeobj", PyLean.TypeObj.handler),
  ("bytecode", PyLean.Bytecode.handler),
  ("pygrammar", PyLean.PyGrammar.handler),
  ("textlibs", PyLean.TextLibs.handler),
  ("corelibs", PyLean.CoreLibs.handler)
]

def runCase (j : Json) : Except String Json := do
  let mod ← getStr j "mod"
  let fn ← getStr j "fn"
  let some h := handlers.lookup mod | throw s!"unknown mod {mod}"
  let some r := h fn j | throw s!"unknown fn {mod}.{fn}"
  r

partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let out := match Json.parse line.trimAscii.toString >>= runCase with
    | .ok r => r
    | .error e => Json.mkObj [("harness_error", toJson e)]
  stdout.putStrLn out.compress
  stdout.flush
  loop stdin stdout

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout)
````

## difftest/common.py

````
"""Shared driver for differential tests: Lean model (`pydiff`) vs. the running CPython.

A module's test script supplies `gen_case(rng) -> dict | None` (the dict carries
"mod" and "fn"; None skips) and `run_python(case) -> {"ok": v} | {"exc": cls, "msg": m}`,
then calls `main(gen_case, run_python)`.

Results compare as JSON. An exception matches on class name, and on message
unless the model's message starts with "~" (formatted text the model does not render).
"""

import argparse
import json
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYDIFF = ROOT / "lean" / ".lake" / "build" / "bin" / "pydiff"


def py_result(thunk):
    """Run `thunk()` and encode its value or exception the way the model does."""
    try:
        return {"ok": thunk()}
    except Exception as e:
        return {"exc": type(e).__name__, "msg": str(e)}


def run_lean(cases):
    proc = subprocess.run([str(PYDIFF)], input="".join(json.dumps(c) + "\n" for c in cases),
                          capture_output=True, text=True, check=True)
    out = [json.loads(line) for line in proc.stdout.splitlines()]
    assert len(out) == len(cases), (len(out), len(cases))
    return out


def agree(py, lean):
    if "ok" in py or "ok" in lean:
        return py == lean
    if py["exc"] != lean.get("exc"):
        return False
    return lean["msg"].startswith("~") or py["msg"] == lean["msg"]


def main(gen_case, run_python, default_cases=20000):
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=default_cases)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    cases = []
    while len(cases) < args.cases:
        c = gen_case(rng)
        if c is not None:
            cases.append(c)

    mismatches, by_fn = 0, {}
    for c, lo in zip(cases, run_lean(cases)):
        py = run_python(c)
        ok = "harness_error" not in lo and agree(py, lo)
        tot = by_fn.setdefault(c["fn"], [0, 0])
        tot[0] += 1
        tot[1] += ok
        if not ok:
            mismatches += 1
            if mismatches <= 20:
                print(f"MISMATCH {json.dumps(c)}\n  python: {py}\n  lean:   {lo}", file=sys.stderr)

    for fn, (n, good) in sorted(by_fn.items()):
        print(f"{fn:20s} {good}/{n}")
    print(f"python {sys.version.split()[0]}: {len(cases) - mismatches}/{len(cases)} agree")
    sys.exit(1 if mismatches else 0)
````


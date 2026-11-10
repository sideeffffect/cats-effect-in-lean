import Lean
import CatsEffectInLean.Registry

/-!
# Registry audit

Checks a property registry against a compiled environment and an inventory CSV.
This is meta code (an executable). It is not part of the model and not part of
the `CatsEffectInLean` library. See `wiki/methodology/registry-and-audit.md`.

All checks are syntactic. The audit never unfolds a definition: a theorem whose
type is the unfolded body of `prop` is rejected, even though it is definitionally
equal. This stops a "proof" of a different (for example weaker) statement.
-/

open Lean
open CatsEffectInLean (Entry Status)

namespace Audit

/-- The only axioms that a registered property or theorem may use (AGENTS.md). -/
def allowedAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

structure Config where
  /-- Modules to import. They must contain every `prop` and `thm` of the registry. -/
  imports : Array Name
  registry : List Entry
  /-- Inventory CSV. Needs the columns `id`, `status` and `registry`. -/
  csv : System.FilePath
  /-- Base directory for the `bug` paths. -/
  root : System.FilePath := "."
  /-- Each `prop` must be declared in a module with this prefix. -/
  propModulePrefix : Name
  /-- Each `thm` must be declared in a module with this prefix. -/
  thmModulePrefix : Name

/-! ## CSV (RFC 4180 subset: quotes, doubled quotes, CRLF) -/

/-- Parse CSV text into records. Structural recursion on the character list. -/
def parseCsv (s : String) : List (List String) :=
  go s.toList [] [] "" false
where
  /-- `rows` and `row` are in reverse order. `q` is true inside a quoted field. -/
  go : List Char → List (List String) → List String → String → Bool → List (List String)
    | [], rows, row, f, _ =>
      let rows := if row.isEmpty && f.isEmpty then rows else (f :: row).reverse :: rows
      rows.reverse
    | '"' :: '"' :: cs, rows, row, f, true => go cs rows row (f.push '"') true
    | '"' :: cs, rows, row, f, true => go cs rows row f false
    | '"' :: cs, rows, row, f, false => go cs rows row f true
    | ',' :: cs, rows, row, f, false => go cs rows (f :: row) "" false
    | '\r' :: cs, rows, row, f, false => go cs rows row f false
    | '\n' :: cs, rows, row, f, false => go cs ((f :: row).reverse :: rows) [] "" false
    | c :: cs, rows, row, f, q => go cs rows row (f.push c) q

/-- One inventory row, reduced to the columns that the audit needs. -/
structure Row where
  id : String
  status : String
  /-- Registry entry ids from the `registry` column, separated by `;`. -/
  entries : List String

def readInventory (path : System.FilePath) : IO (Except String (List Row)) := do
  let recs := parseCsv (← IO.FS.readFile path)
  match recs with
  | [] => return .error s!"{path}: empty file"
  | header :: body =>
    let col (n : String) : Except String Nat :=
      match header.idxOf? n with
      | some i => .ok i
      | none => .error s!"{path}: no column `{n}` in the header"
    match col "id", col "status", col "registry" with
    | .ok iId, .ok iSt, .ok iReg =>
      return .ok <| body.map fun r =>
        let get (i : Nat) := r.getD i ""
        { id := get iId, status := get iSt
          entries := ((get iReg).splitOn ";").map (·.trimAscii.toString) |>.filter (!·.isEmpty) }
    | .error e, _, _ | _, .error e, _ | _, _, .error e => return .error e

/-! ## Checks -/

def moduleOf (env : Environment) (n : Name) : Option Name := do
  let idx ← env.getModuleIdxFor? n
  env.header.moduleNames[idx.toNat]?

def axiomsOf (env : Environment) (n : Name) : IO (Array Name) :=
  (collectAxioms n : CoreM _).toIO' { fileName := "<audit>", fileMap := default } { env }

/-- Errors for one declaration that must use only allowed axioms. -/
def checkAxioms (env : Environment) (who : String) (n : Name) : IO (List String) := do
  let bad := (← axiomsOf env n).toList.filter (!allowedAxioms.contains ·)
  return if bad.isEmpty then [] else [s!"{who}: `{n}` uses forbidden axioms {bad}"]

def checkModule (env : Environment) (who : String) (n pfx : Name) : List String :=
  match moduleOf env n with
  | some m => if pfx.isPrefixOf m then [] else
      [s!"{who}: `{n}` is declared in module `{m}`, expected a module under `{pfx}`"]
  | none => [s!"{who}: `{n}` is not from an imported module"]

/-- The exact type that the theorem of an entry must have. -/
def expectedType (prop : Name) : Status → Option Expr
  | .proven => some (.const prop [])
  | .refuted => some (mkApp (.const ``Not []) (.const prop []))
  | .open => none

def checkEntry (cfg : Config) (env : Environment) (e : Entry) : IO (List String) := do
  let who := s!"entry {e.id}"
  let mut errs : List String := []
  if e.id.trimAscii.isEmpty then errs := errs ++ [s!"{who}: empty id"]
  if e.rows.isEmpty then errs := errs ++ [s!"{who}: names no inventory row"]
  -- the property
  match env.find? e.prop with
  | none => errs := errs ++ [s!"{who}: property `{e.prop}` does not exist"]
  | some (.defnInfo d) =>
    if !d.levelParams.isEmpty then
      errs := errs ++ [s!"{who}: property `{e.prop}` has universe parameters"]
    if d.type != .sort .zero then
      errs := errs ++ [s!"{who}: property `{e.prop}` has type `{d.type}`, expected `Prop`"]
    errs := errs ++ checkModule env who e.prop cfg.propModulePrefix
    errs := errs ++ (← checkAxioms env who e.prop)
  | some _ => errs := errs ++ [s!"{who}: property `{e.prop}` is not a `def`"]
  -- the theorem
  match expectedType e.prop e.status, e.thm with
  | none, none => pure ()
  | none, some t => errs := errs ++ [s!"{who}: status open, but theorem `{t}` is given"]
  | some _, none => errs := errs ++ [s!"{who}: status {repr e.status}, but no theorem is given"]
  | some want, some t =>
    match env.find? t with
    | none => errs := errs ++ [s!"{who}: theorem `{t}` does not exist"]
    | some (.thmInfo info) =>
      if !info.levelParams.isEmpty then
        errs := errs ++ [s!"{who}: theorem `{t}` has universe parameters"]
      -- Syntactic equality, no unfolding. Stored theorem types have no metavariables.
      if info.type != want then
        errs := errs ++ [s!"{who}: theorem `{t}` has type `{info.type}`, expected exactly `{want}`"]
      errs := errs ++ checkModule env who t cfg.thmModulePrefix
      errs := errs ++ (← checkAxioms env who t)
    | some _ => errs := errs ++ [s!"{who}: `{t}` is not a `theorem`"]
  -- the bug record
  if e.status == .refuted then
    match e.bug with
    | none => errs := errs ++ [s!"{who}: refuted, but no bug record is given"]
    | some b =>
      unless ← (cfg.root / b).pathExists do
        errs := errs ++ [s!"{who}: bug record `{b}` does not exist"]
  return errs

/-- Cross-check registry entries and inventory rows. A `modelled` row must name at least one
entry that is `proven` or `refuted` (decision 28); `open` entries can name `todo` rows. -/
def checkInventory (reg : List Entry) (rows : List Row) : List String := Id.run do
  let mut errs : List String := []
  let ids := rows.map (·.id)
  for e in reg do
    for r in e.rows do
      unless ids.contains r do
        errs := errs ++ [s!"entry {e.id}: inventory row `{r}` does not exist"]
  for r in rows do
    if r.status == "modelled" && r.entries.isEmpty then
      errs := errs ++ [s!"inventory row {r.id}: status modelled, but no registry entry is named"]
    -- Decision 28: only a settled (proven or refuted) entry makes a row `modelled`.
    -- An `open` entry may name a `todo` row, but it does not count as progress.
    let settled := r.entries.any fun name =>
      match reg.find? (·.id == name) with
      | some e => e.status == .proven || e.status == .refuted
      | none => false
    if r.status == "modelled" && !r.entries.isEmpty && !settled then
      errs := errs ++ [s!"inventory row {r.id}: status modelled, but no named registry entry " ++
        "is proven or refuted"]
    for name in r.entries do
      match reg.find? (·.id == name) with
      | none => errs := errs ++ [s!"inventory row {r.id}: registry entry `{name}` does not exist"]
      | some e =>
        unless e.rows.contains r.id do
          errs := errs ++ [s!"inventory row {r.id}: registry entry `{name}` does not list this row"]
  return errs

/-- Duplicate entry ids. -/
def checkUnique (reg : List Entry) : List String :=
  let ids := reg.map (·.id)
  (ids.eraseDups.filter fun i => ids.count i > 1).map (s!"duplicate entry id {·}")

/-- Run all checks. Print each error. Return exit code 0 (pass) or 1 (fail). -/
def run (cfg : Config) : IO UInt32 := do
  initSearchPath (← findSysroot)
  let env ← importModules (cfg.imports.map ({ module := · })) {}
  let mut errs := checkUnique cfg.registry
  for e in cfg.registry do
    errs := errs ++ (← checkEntry cfg env e)
  let mut nRows := 0
  let mut nModelled := 0
  match ← readInventory cfg.csv with
  | .error msg => errs := errs ++ [msg]
  | .ok rows =>
    nRows := rows.length
    nModelled := (rows.filter (·.status == "modelled")).length
    errs := errs ++ checkInventory cfg.registry rows
  for msg in errs do
    IO.println s!"error: {msg}"
  if errs.isEmpty then
    let count (s : Status) := (cfg.registry.filter (·.status == s)).length
    IO.println (s!"OK: {cfg.registry.length} entries ({count .proven} proven, " ++
      s!"{count .refuted} refuted, {count .open} open); " ++
      s!"{cfg.csv}: {nRows} rows, {nModelled} modelled.")
    return 0
  else
    IO.println s!"FAIL: {errs.length} error(s)."
    return 1

end Audit

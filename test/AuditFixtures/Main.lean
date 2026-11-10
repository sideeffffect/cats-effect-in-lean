import Audit.Core
import AuditFixtures.Proofs

/-!
`lake exe audit_fixture <case>`: run the registry audit on a fixture registry.

`good` must pass. Each other case adds exactly one fault to `good` and must fail.
`scripts/test_audit.sh` runs all cases and checks the exit code and the message.
The case `bad_axiom` needs the generated module `AuditFixtures.Generated.BadAxiom`
(the script writes it, builds it and deletes it), so it names that theorem with a
single backtick (no compile-time check).
-/

open CatsEffectInLean (Entry Status)

namespace AuditFixtures

def dir : System.FilePath := "test/AuditFixtures"

def addZero : Entry :=
  { id := "fx.addZero", rows := ["core.Fx.addZero"], prop := ``Props.addZero
    status := .proven, thm := ``Proofs.addZero_proven }

def subAddCancel : Entry :=
  { id := "fx.subAddCancel", rows := ["core.Fx.subAddCancel"], prop := ``Props.subAddCancel
    status := .refuted, thm := ``Proofs.subAddCancel_refuted
    bug := (dir / "bugs" / "fx-sub-add-cancel.yaml").toString }

def addComm : Entry :=
  { id := "fx.addComm", rows := ["core.Fx.addComm"], prop := ``Props.addComm, status := .open }

def config (reg : List Entry) (csv := dir / "inventory.csv")
    (extra : Array Lean.Name := #[]) : Audit.Config :=
  { imports := #[`AuditFixtures.Proofs] ++ extra
    registry := reg, csv
    propModulePrefix := `AuditFixtures.Props
    thmModulePrefix := `AuditFixtures }

def cases : List (String × Audit.Config) := [
  ("good", config [addZero, subAddCancel, addComm]),
  -- a theorem of a weaker statement, registered as `proven`
  ("wrong_type", config [{ addZero with thm := ``Proofs.addZeroOrTrue_proven }, subAddCancel, addComm]),
  -- a theorem of the unfolded body (definitionally equal, not syntactically)
  ("unfolded", config [{ addZero with thm := ``Proofs.addZero_unfolded }, subAddCancel, addComm]),
  -- `refuted` with a theorem of `prop`, not `¬ prop`
  ("not_negated", config [addZero, subAddCancel,
    { addComm with status := .refuted, thm := ``Proofs.addComm_proven, bug := subAddCancel.bug }]),
  -- `proven` with a theorem of `¬ prop`
  ("negated_as_proven", config [addZero, { subAddCancel with status := .proven }, addComm]),
  -- the theorem depends on a new axiom
  ("bad_axiom", config [{ addZero with thm := `AuditFixtures.Generated.BadAxiom.cheat_proven },
    subAddCancel, addComm] (extra := #[`AuditFixtures.Generated.BadAxiom])),
  ("missing_thm", config [{ addZero with thm := `AuditFixtures.Proofs.noSuchTheorem }, subAddCancel, addComm]),
  ("open_with_thm", config [addZero, subAddCancel, { addComm with thm := ``Proofs.addComm_proven }]),
  ("missing_bug", config [addZero, { subAddCancel with bug := none }, addComm]),
  ("missing_bug_file", config [addZero, { subAddCancel with bug := "bugs/no-such-file.yaml" }, addComm]),
  ("missing_row", config [{ addZero with rows := ["core.Fx.noSuchRow"] }, subAddCancel, addComm]),
  ("unnamed_modelled", config [addZero, subAddCancel, addComm] (csv := dir / "inventory-unnamed.csv")),
  ("duplicate_id", config [addZero, subAddCancel, addComm, addZero])
]

end AuditFixtures

def main (args : List String) : IO UInt32 := do
  match args with
  | [name] =>
    match AuditFixtures.cases.lookup name with
    | some cfg => Audit.run cfg
    | none => IO.eprintln s!"unknown case {name}"; return 2
  | _ =>
    IO.eprintln s!"usage: audit_fixture <case>; cases: {AuditFixtures.cases.map (·.1)}"
    return 2

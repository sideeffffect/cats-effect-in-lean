import Lake
open Lake DSL

package "cats-effect-in-lean" where
  version := v!"0.1.0"

@[default_target]
lean_lib «CatsEffectInLean» where
  -- add library configuration options here

-- Registry audit (meta code, not part of the library): `lake exe audit`.
-- See wiki/methodology/registry-and-audit.md.
lean_lib Audit where
  srcDir := "tools"
  roots := #[`Audit.Core]

lean_exe audit where
  srcDir := "tools"
  root := `Audit.Main

-- Fixtures for the audit self-test (scripts/test_audit.sh). Not a default target,
-- so `lake build`, `lake check` and the axiom audit of the library never see them.
lean_lib AuditFixtures where
  srcDir := "test"
  globs := #[.submodules `AuditFixtures]

lean_exe audit_fixture where
  srcDir := "test"
  root := `AuditFixtures.Main

-- Difftest harness, Lean side (test code, not part of the library): decoder of the
-- JSON program format v0, translation into `Model.IO`, and `lake exe cediff`.
-- See wiki/methodology/difftest-program-format.md ("Lean side").
lean_lib Difftest where
  srcDir := "tools"
  roots := #[`Difftest.Prog, `Difftest.Closure, `Difftest.Translate, `Difftest.Env,
    `Difftest.Tests]

lean_exe cediff where
  srcDir := "tools"
  root := `Difftest.Main

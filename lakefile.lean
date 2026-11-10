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
-- JSON program format (v1; v0 accepted), translation into `Model.IO`, and `lake exe cediff`.
-- See wiki/methodology/difftest-program-format.md ("Lean side").
lean_lib Difftest where
  srcDir := "tools"
  roots := #[`Difftest.Prog, `Difftest.Closure, `Difftest.Translate, `Difftest.Env, `Difftest.Replay,
    `Difftest.Tests]

lean_exe cediff where
  srcDir := "tools"
  root := `Difftest.Main

-- CE-0002 fixed-twin checks (review rule "fixed twin", decision 39). Supporting evidence, not a
-- registered property. One `decide +kernel` here needs up to 13 GB, so these modules are not in
-- the default target: CI builds them in a separate job, one module per Lean process
-- (`scripts/check_twin_checks.sh`), with its own axiom check.
lean_lib TwinChecks where
  roots := #[`CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed,
    `CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedOld,
    -- CE-0005 fixed-twin check and the track G smoke tests (Phase 6): several minutes each,
    -- so not in the default build (decision 45)
    `CatsEffectInLean.Proofs.Phase6.BracketFullFixed,
    `CatsEffectInLean.Proofs.Phase6.BracketSmoke]

-- Leak smoke test of track R (Phase 6): exact bounded search (`exploreP`) of `race`, `both`,
-- `raceOutcome`, `bothOutcome` and `timeout` over a small family of sides, with the leak
-- observation of `Model/Leak.lean`. `lake exe leaksmoke`. Test code, not part of the library.
lean_exe leaksmoke where
  srcDir := "tools"
  root := `LeakSmoke.Main

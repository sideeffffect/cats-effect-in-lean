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
    `CatsEffectInLean.Proofs.Phase6.BracketSmoke,
    -- CE-0030 fixed-twin check (track M, Phase 6)
    `CatsEffectInLean.Proofs.Phase6.MemoizeFixed,
    -- CE-0020 fixed-twin check (track Res, Phase 6; review batch 5)
    `CatsEffectInLean.Proofs.Phase6.ResourceBothFixed]

-- Leak smoke test of track R (Phase 6): exact bounded search (`exploreP`) of `race`, `both`,
-- `raceOutcome`, `bothOutcome` and `timeout` over a small family of sides, with the leak
-- observation of `Model/Leak.lean`. `lake exe leaksmoke`. Test code, not part of the library.
lean_exe leaksmoke where
  srcDir := "tools"
  root := `LeakSmoke.Main

-- Heavy proofs (decision 55): proofs that take more than about 5 minutes. Not a default target,
-- so the main CI job (`lake build`, `lake check`, 60 min) does not build them. Their registry is
-- `CatsEffectInLean/RegistryHeavy.lean`. CI job `heavy-proofs` builds the modules one Lean
-- process at a time and audits both registries (`scripts/check_heavy_proofs.sh`,
-- `lake exe audit_heavy`). The roots must match `CatsEffectInLean.heavyModules`.
lean_lib HeavyProofs where
  roots := #[`CatsEffectInLean.Proofs.Phase6.RaceLaw]

lean_exe audit_heavy where
  srcDir := "tools"
  root := `Audit.MainHeavy

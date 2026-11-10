import Lake
open Lake DSL

-- Kernel-evaluation spike (Phase 0 step 3).
-- Not part of the main library. The root CI build does not compile it.
package "kernel-eval-spike" where
  moreLeanArgs := #["-M8000"]

@[default_target]
lean_lib «KernelEval» where

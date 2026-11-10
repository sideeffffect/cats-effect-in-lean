import Lake
open Lake DSL

package "cats-effect-in-lean" where
  version := v!"0.1.0"

@[default_target]
lean_lib «CatsEffectInLean» where
  -- add library configuration options here

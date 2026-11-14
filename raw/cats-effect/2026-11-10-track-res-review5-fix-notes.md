# Track Res: fixes after review batch 5 (harness names, witnesses)

> Source: `review/2026-11-10-review-batch-5.md`; decisions 53-54 (`raw/project-decisions/2026-11-10-decision-53-satisfiability.md`); own Lean work (`Props/Phase6/HarnessNames.lean`, `Props/Phase6/Resource.lean`, `Proofs/Phase6/ResourceWitnessEnv.lean`, `ResourceWitness.lean`, `ResourceBoth.lean`, `ResourceBothFixed.lean`, `test/Phase6/ResourceSmoke.lean`); scala-cli runs of `reproducers/CE-0020/Repro.scala`
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

## Finding of review batch 5

- `UserMarkersOnly`/`usesId` looked only at direct ids. A user function could return `.map (.pure ()) (ULam.allocFn (.user mR)).fn`; the library closure calls the marker by its index. So the three marker statements were false for every implementation, also the fixed twin (HOLLOW). The bug CE-0020 itself is real.

## Choice: deep name check, not only a captured handle

- Library closures keep function ids in fields as plain `Val.nat` (`Bracket.BLam.thenUse`, `ULam.allocFn`, `Clo.makePair`, `RelFn` values, `USrc.fold` resource codes). `WellFormed` sees only handle values. A handle in the marker's own id does not stop forwarding: the forwarding closure holds the id as a number. So a handle alone can be bypassed.
- `HarnessNames.mentionsV bad v`: `v` contains a value of `bad`, or a number whose closure value (`Codec.cloOfId`) mentions `bad`, recursively (depth 64; at the limit "mentions", conservative). Every number is decoded, also data numbers (conservative). `mentionsIO`, `mentionsFn`, `mentionsRt`, `mentionsEff`, `mentionsR` cover programs, runtime closures (`racePair*` programs, `deferredComplete` values), effects and user results. The scan is structural (fuel), so the kernel evaluates it.
- `NoForge`: user results, user `Bind` results, other acquire and release programs, other resources mention a harness name only if their argument does. Harness names: markers as program ids and `REnv` indices, acquire/release codes, resource codes, the harness `Bind` code. Why the library never gives a harness name to user code in these programs: `f` gets the acquired value (`unit` of the marker), the release rest `q` gets `unit`, the parent gets a fiber; the `Ref` of `both` is not reachable (`WellFormed`).
- The parent fiber of decision 50 is now a harness closure (`HLam`, odd ids, namespace 21, in `isLibH`), not a user function. So no `PollOpaque` proof for view-dependent user code is needed.
- Track G can reuse `HarnessNames` for `Bracket.MarkersOnly`.

## Results

- `bothReleasesBoth_refuted` re-proven under `NoForge` (environment `W true true false`, same schedule FIFO 89 then `pick 1`, trace `[RA, B, A]`). All hypotheses proven; this is also the satisfiability witness of statement 1.
- Satisfiability witnesses (decision 53): `use_sat` and `flat_sat`, each for `viaParent = false` (FIFO) and `true` (three `pick 0`, one `preempt`): all hypotheses, and a run that ends where every acquire and release marker ran once.
- Fixed-twin check (decision 39): `ResourceBothFixed.fixed_satisfies` (kernel, `TwinChecks`): `fixedBothRes` satisfies the conclusion on the witness input for 120 single-deviation schedules around the release phase (60 ≤ k < 120; about 6 s of kernel time per run); `old_violates`: v3.7.1 does not. Smoke (`#guard`) covers all 600 single-deviation and 1,500 random schedules.
- Smoke: the instances are the witness environment plus constant functions; the decidable hypotheses are `#guard`ed (no user function mentions a name; only markers emit); the forgeries are detected; `alloc` of part 3 comes from `allocatedCase`.
- Reproducer: `REPRODUCED` only if v3.7.1 skips a release and the fixed copy does not. Runs: 3.7.1 (319 of 20,000 default-runtime runs), series/3.x de84c01 (345), series/3.7.x 2f94201 (382); TestControl 332 of 1,000 seeds on all three; fixed copy 0.
- Inventory: `kernel.Resource.makeCase`, `kernel.Resource.evalMap` back to `todo` (only the instances inside `both` are mirrored).

## Gotchas

- A well-founded `scanV` (`termination_by`) does not reduce in `decide +kernel`; a structural fuel version does.
- In the parent witness the child finished before the cancel landed (the parent joins `Succeeded`); still all markers ran under the parent program.

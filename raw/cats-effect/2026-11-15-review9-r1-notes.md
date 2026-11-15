# Review batch 9 R1 fix: REnv table entries as references (track Res, 2026-11-15)

Own work, after review batch 9 (branch review9, c7db59c).

## R1

The `Resource` mirror named the `REnv` table entries (`acquire`, `release`, `bind`) by data numbers: `RelFn.const k a`, `AllocFn.make a r`, stack frames, `makePair`, `ioRelease`. A public `Bracket` leaf with an external `USrc` source (`relApp (RelFn.const relA) ...`) made `srcU` run the harness release entry: `forge relA` (no handle) logged a release tag during acquire. So CE-0020 was HOLLOW (the fixed twin also refuted) and use/flatMap false for every implementation.

## Fix (decision 58 applied to table entries)

- Every table index in a value is a `Val.fn k` (`Model/Resource.lean`: `RelFn.toVal`, `allocFnToVal`, `stackToVal`, `Clo.makePair`, `ioRelease`, `applyPair`). `WellFormed` treats it like a closure reference: even index = an entry user code may make (if its captured handles are available), odd = library or harness entry, available only if held.
- `Res.ok` (Phase 5) and `resOK` (Phase 6) check the references of `make` and `bind` (`subA`/`avail`).
- `MarkedMake`: harness acquire and release entries are odd; `flatMapReleaseOrder`: the harness `Bind` entry is odd. The hand-written `Res.idx` exclusion of `Private` is removed (the references do it).
- Witness codes are odd (`code i = 2 * valToNat (...) + 1`, `code_odd`).
- Regression: `forge (code 1)` rejected, `forge 6` (own entry) accepted (`Proofs/Phase6/PrivacyExamples.lean`).

## Wrong-function tests (review batch 9)

`Proofs/Phase6/ResourceWrongFunction.lean`, kernel runs on the witness inputs:
- `use` without release (`acquire.flatMap(f)`): log `[A]`, `count RA = 0 ≠ 1`.
- release order FIFO (reversed nesting `make(B).flatMap(_ => make(A))`): log `[B, A, RA, RB]`, `RB` not before `RA`.

## W1

`hasPoll`/`rnVal` now descend into `Val.fn` (`hasPollRef`, `rnRef`, with fuel `pollFuel = 4096` for the nested values, `hasPollF`/`rnValF`); lemmas `rnValF_of_hasPollF_false`, `hasPollF_rnValF`.

## Other number-named tables (item 7; not changed, other tracks)

- `Race` statements (`Props/Phase6/Race.lean`, `srcIO fa fb`): sources `.nat 0`/`.nat 1` name the statement's programs `fa`/`fb`. User code can build a public `Race`/`Timeout` closure whose source is `.nat 0` and so run `fa` again. `fa`/`fb` are user programs, not harness events, so this is not a marker forgery, but it is a name made from a number (track R).
- `Memoize` statements (`Props/Phase6/Memoize.lean`, `srcIO fa`): `.nat 0` names the memoized action `fa`; `.ref c` (the counter increment) needs the counter handle (structural). A user closure with source `.nat 0` can run `fa` outside `memoize` (track M: check that `atMostOnce` counts only through `.ref c`).
- `Queue` calibration (`Props/Calibration/QueueTimeout.lean`): sources are `.ref q` handles. No number-named table.
- `parTraverseN` (`Model/ParTraverse.lean` `ioOf`): `srcAction f a` (track G switches `f` to `Val.fn`), `srcResGet` (`.deferred r` handle), `srcPar` (fiber/deferred handles). After G's change no number-named table.
- `Bracket` statements (`hioOf`): `.pair (.ref c) (.nat 0)` names the acquire program, but needs the counter handle `.ref c` (structural).
- `Resource` codes (`UEnv.resOf`): keyed by `Val` codes; harness codes hold the token (structural); other codes name user resources that `Private` checks.

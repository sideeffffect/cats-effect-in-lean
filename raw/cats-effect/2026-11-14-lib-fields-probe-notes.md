# Lib.fields probe check (track Res, 2026-11-14)

Own work. Coordinator round 6: make the `Lib.fields` lists hard to get wrong.

## Route taken

Route 2 of the request: a kernel-checked completeness check per library, by testing the real step function. Route 1 (derive `fields` from the codec) was not done: the codec stores a function id as a plain `.nat`, the same as a count or a tag, so the codec alone cannot tell which number is an id. Changing the codec would change every closure id and all kernel witnesses.

## How the check works (`CatsEffectInLean/Model/LibProbe.lean`)

- Probe `i` = even user closure id `2 * valToNat (.ref (1000 + i))`: it captured exactly one fresh `Ref`.
- A sample = a library closure value whose number leaves are all distinct probes, or small tags (`< 256`) (`probedOK`, checked).
- `sampleOK lib as toVal run s`: for each argument shape, run the library's real `call` (or the real dispatcher of the statements) with user code `recUC k = IO.delay(k)`. Check the result with clause 5 (`effectsOK`, with allocation) against `libMade ++ WF.captured lib id ++ arg.handles`. `libMade` = identity poll `(0, 0)`. Odd ids in the output are allowed (`anyOk`: `Lib.ok` limits user programs, not library output).
- A number field that `call` uses as a function (directly, through a decoded leaf, or by putting it into a new closure whose own fields list it) brings the probe's `Ref` into the output. That passes only if `fields` lists it.
- Per library: `fields_complete` (decide +kernel), coverage `covers_*` (`ctorIdx` of every lambda type and nested code type has a sample), and wrong-function tests (`idFree_fails`, an older list fails).

## Libraries checked

- `Bracket.lib`: `Proofs/Phase6/LibFieldsBracket.lean` (60 samples, ~20 s).
- `Resource.lib`: `LibFieldsResource.lean`.
- `ResourceUse.lib` (and so `libH`, same fields; `HLam` harness closures keep only handles and tags): `LibFieldsResourceUse.lean`, ~520 samples over ULam, Bracket with USrc sources, Clo, Race, Timeout; ~3.5 min, split into 10 chunk theorems.
- `ptLibDeep` (track G's library, checked without change): `LibFieldsParTraverse.lean`, 151 samples (PT, TL, and Bracket/Race/Timeout closures with `srcAction`/`srcResGet`/`srcPar` sources). `first_fields_fail`: the first `ptLibDeep` (no `srcAction` fields) fails. Note: putting `srcAction` codes only in `PT` fields did not catch that defect; the `Bracket`/`Race`/`Timeout` samples did.
- Not checked: `limLib` (statement 8, `ptFields` plus `CL` closures), and the id-free claims `raceLib`, `memoLib`, `queueLib` (still argued in their libNote).

## Defects that the check found (fixed)

1. `ResourceUse.fnFields` missed the closure ids inside `USrc` source codes of `Bracket` (`Src.ext`) and `Race`/`Timeout` closures (the mirror builds `Race.bothIO (USrc.relApp finV ec _)` and `Bracket.guaranteeIO (.ext (USrc.relApp ...))`). A user could name such a closure with a forged release function by number. Fix: `srcCodeIds` (structural deep scan for `USrc` codes; `relApp`/`unitThen` release ids, `fold` onOutput id).
2. `ResourceUse.uDisp` did not dispatch `Timeout` closures. `Race.constNever` (`poll(canceled) *> never`) builds `IO.never` (`TLam.neverBody`); the environment sent that id to user code (illTyped throw instead of never). Fix: `tlamOf?` in `uDisp` and in `isLib` (`IO.never` is public API).

## Limits

- A field used as a function only in a branch that no argument shape reaches is not tested.
- Small scalar number fields (< 256) are not probed.
- Function ids inside argument values (for example a `RelFn.user k` code in the `(b, rel)` argument of `Clo.allocK`, or in a `Ref` value) are not followed by `WF` clause 5 (`Val.handles`). Same class as defect D, but for values, not closure fields. Not a harness-privacy gap (`UserPrivate` covers all user ids), but a `WellFormed` gap in general.

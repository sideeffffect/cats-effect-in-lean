# Harness privacy by construction (decision 56, track Res)

> Source: `review/2026-11-14-review-batch-6.md`; decision 56 (`raw/project-decisions/2026-11-14-decision-56-harness-privacy.md`); own Lean work (`Model/WellFormed.lean`, `Model/Bracket.lean`, `Model/Resource.lean`, `Model/ResourceUse.lean`, `Props/Phase6/HarnessPrivacy.lean`, `Props/Phase6/Resource.lean`, `Props/Phase6/Bracket.lean`, `Proofs/Phase6/*`, `test/Phase6/*`)
> Collected: 2026-11-14
> Published: 2026-11-14 (own research note)

## Route: construction

1. `WellFormed` fix (decision 56.5): `lib : Lib` (`ok`, `fields`). `fields c` lists the closure ids that a library closure value keeps in number fields (its function fields). `WF.capturedD` follows them recursively (depth `capDepth = 64`; `none` at the bound, then `capOK` rejects). `fnOK` uses `capOK`; `CallOK` uses `captured` (the deep list) as held handles. A `Nat → Bool` coerces to a `Lib` without fields: same meaning as before. `Bracket.lib`, `Resource.lib`, `ResourceUse.lib` declare their fields (BLam `acq/use/rel/k`, `Src` uses; `AllocFn.user`, `RelFn.user`; `ULam` `allocFn`, `OnOut.user`, `RelFn` values). Only fields known to be function ids are decoded; data numbers in closure fields (durations, cell ids, offered values) are not, so the proofs that quantify over data (QueueTimeout, Race, Memoize) keep working.
2. Shared module `Props/Phase6/HarnessPrivacy.lean`: tokens are harness cells allocated first by the root (empty heap at the start, so their ids are fixed and never reused); harness events capture a token and write the token cell; harness codes are token names (`tokFreeV` false); the one restriction on user code is `UserPrivate`/`Private`: every user result (and the user parts of an `REnv`) is token-free (`tokFreeR`), with no escape clause. `tokFreeV` decodes every number (a number that decodes to a token-holding closure is a token name), depth `capDepth`, "not free" at the bound.
3. Why the class is closed: a harness event runs only if a program term or a library lookup names it. User terms are token-free (or `WellFormed` rejects the held-handle violation, now deep). Library lookups use codes from user values (token-free, so never a harness code), from the runtime (data, never a lookup key), or from the harness itself.

## Track Res harness

- Root `harness = IO.delay(newCells).flatMap(afterCells)`: log cell `Ref` 0 (`listV []`), then the body. `HLam` namespace 21: `newCells`, `afterCells`, `markA c tag` (append tag, return the value), `markT c tag` (append tag), `cancelJoin`, `thenJoin f`. `libH` accepts the public ones, not the event closures.
- Tags A=1, B=2, RA=3, RB=4. The log gives counts and order (LIFO check of `flatMapReleaseOrder`).
- Statements: `BothReleasesBothFor impl`, `useReleaseOnce`, `flatMapReleaseOrder` with `MarkedMake` (codes token names, `a0` token-free) and `Private`.
- Witness environment: codes `code i = 2 * valToNat (cloVal 21 60 [.ref 0, .nat i])`, resource codes `.pair (.ref 0) (.nat 20/21)`.
- CE-0020 re-proven: schedule FIFO 92 then `pick 1` (the harness prologue adds 3 steps), log `[A, B, RA]`, `Errored(boom)`.
- Witnesses: `use_sat`, `flat_sat` (FIFO; parent with 4 `pick 0` + `preempt`, child completes, parent joins `Succeeded`).
- Fixed twin (TwinChecks, kernel): 120 schedules `63 ≤ k < 123`, fixed passes, v3.7.1 fails at `k = 92`.
- Regression examples: `Proofs/Phase6/PrivacyExamples.lean` (batch 4: witnesses exist; batch 5: `ULam.allocFn` forwarding and other fields; batch 6 G: `BLam.thenUse` leaf — shallow `Lib` accepts, `Bracket.lib` rejects; batch 6 Res: clock number output, code as data, `c = .unit` is not a token name).
- Inventory: `kernel.Resource.fold`, `use`, `both` back to `todo`; registry rows of CE-0020 without `makeCase`, `evalMap`.

## Track G

- Statements now use `WellFormed lib` (`Bracket.lib`). The harness was already by construction (counter cells first, events capture them); the gap was the shallow `captured`. Proofs adapted (`BracketWitness`, `BracketFullTwin`, `BracketFullFixed`, `BracketSmoke`, smoke parent).

## Gotchas

- `simp` with `capturedD` and the literal depth 64 loops; use `rw [show capDepth = 63 + 1 from rfl, capturedD, h]`.
- `WF.progOK (fun _ => false) ...` needs a type ascription for the coercion: `((fun _ => false : Nat → Bool) : Lib)`.
- Unfolding a `Lib` constant in `simp` breaks rewriting with lemmas stated for it; keep it folded and give `lib.ok id = true` facts.

## Review batch 7, defect D (parTraverseN)

- `PT.k1 n as f` keeps the user function `f` as a number field; `parTraverseNOrder` uses `ptIsLib` (a `Lib` without fields), so a well-formed `f` that captured the element's result `Deferred` passes. With the deep `captured` and a `Lib` that declares the `PT`/`TL.tag` function fields (`PrivacyExamples.ptLibDeep`), the forgery is rejected (regression `example`s, kernel). Track G must switch the statement to such a `Lib` (its file; not edited here).
- `ParTraverseWitness.neverCaptured` adapted to the new `WF.capOK`.

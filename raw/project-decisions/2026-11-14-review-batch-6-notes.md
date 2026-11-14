# Review batch 6: re-review of 5 Phase 6 entries after the track G and track Res fixes (own note)

> Source: independent read-only review of commit `b12aa58` (`CatsEffectInLean/Registry.lean`, `Props/Phase6/{Bracket,Resource,HarnessNames}.lean`, `Proofs/Phase6/{BracketWitness,ResourceWitnessEnv,ResourceWitness,ResourceBoth,ResourceBothFixed}.lean`, `test/Phase6/BracketSmokeParent.lean`, `Model/{Bracket,WellFormed,Codec,Step,Sched}.lean`, `bugs/CE-0020.yaml`, `reproducers/CE-0020/Repro.scala`, `inventory/inventory.csv`, raw fix notes of tracks G and Res, review batches 4 and 5); Cats Effect source at v3.7.1 (`IO.scala`, `Resource.scala`, `MonadCancel.scala`). Full review: `review/2026-11-14-review-batch-6.md`.
> Collected: 2026-11-14
> Published: 2026-11-14

## Verdicts

- HOLLOW: `core.IO.bracket.releaseOnce`, `core.IO.guarantee.finalizerOnce` (open). False for every implementation.
- HOLLOW as registered: CE-0020 `kernel.Resource.both.releaseOnce` (refuted). Bug and witness real; a correct `both` also refutes the statement.
- HOLLOW: `kernel.Resource.use.releaseOnce`, `kernel.Resource.flatMap.releaseOrder` (open). False for every implementation.
- Fixed since batches 4-5: all five now have kernel-checked satisfiability witnesses whose types contain all hypotheses; the batch-4 contradiction and the batch-5 `ULam.allocFn` forgery are gone; the CE-0020 reproducer checks the fixed copy; the CE-0020 twin domain (one input, 120 schedules) is honestly described.

## Finding A (track G): a handle hidden in a number field

- `WF.captured` reads only top-level handles of a closure value. A closure field that is another closure id is a `Val.nat`.
- `Bracket.BLam.good` accepts a `Bracket` leaf (`constThis`, `constFin`) as a function field without checking what it captures.
- Forgery: user `rel` returns `.flatMap (.pure ()) (BLam.thenUse T ()).fn` with `T = (BLam.constThis (Src.ext (srcAcq 0)).toVal).id`. The `thenUse` closure holds no handle, is `good`, and its call runs `hioOf a0 (srcAcq 0)`, which bumps counter 0 again. Same for `guarantee` with `srcFa 0 _` or `srcFin 1 _`.
- Fix: a deep `captured` (closure ids in fields add their captured handles), or a deep scan for `.ref 0`/`.ref 1` with no escape clause.

## Finding B (track Res): `NoForge` escape clause plus runtime numbers

- `NoForge` clause 1: a user result may mention a harness name if its argument does. The scan treats every number as a possible id.
- `IO.realTime`/`IO.monotonic` return `.nat clock`; `IO.sleep d` moves the clock by `d`. So user code can get the number `2 * mR` from the runtime.
- Forgery on the witness environment: `a0 = sleep 6 >> realTime >>= g`, `g(.nat 6) = IO.delay(marker R)`. All hypotheses hold; `count R = 2 ≠ 1 = count A`. Works for `use`, `flatMap` and every `both` (also `fixedBothRes`).
- Secondary: a resource code `c = .unit` puts `unit` in `bad`, so every `unit` argument "mentions" a name.
- Fix: remove the escape from `NoForge` clauses 1, 2 and 4. The library gives no harness name to user code here, and `userR_clean` already proves the stronger form for the witness.

## Other

- `kernel.Resource.fold`, `use`, `both` still `modelled` with CE-0020; should be `todo` until it passes review. Registry `rows` of CE-0020 still list `makeCase` and `evalMap`.
- Hypotheses judged: even user ids (encoding, type invariant), `WellFormed` (decision 27, type invariant), `MarkedMake`/`EmitsOnly`/`names` (harness definitions), `NoForge` (harness privacy assumption; acceptable once it has no escape clause). None removes the interesting case (cancel at any point, raising or hanging release).
- Lesson: a forgery check must cover every way a value can reach a call position: direct ids, ids in closure fields (track G missed this for handles), and numbers that the runtime computes (track Res missed this for names).

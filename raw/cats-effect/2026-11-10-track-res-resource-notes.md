# Track Res notes: Resource use/allocated/both, CE-0020

> Source: own Lean work (`CatsEffectInLean/Model/ResourceUse.lean`, `Model/ResourceUseExamples.lean`, `Props/Phase6/Resource.lean`, `Proofs/Phase6/ResourceBoth.lean`, `test/Phase6/ResourceSmoke.lean`), difftest format v2 ops `rUse`, `rAllocated`, `rBoth` (`difftest/`, `tools/Difftest/`), scala-cli runs of `reproducers/CE-0020/Repro.scala` on 3.7.1, `3.7.1-89-de84c01` (series/3.x), `3.7.1-15-2f94201` (series/3.7.x); Cats Effect source at v3.7.1 (`Resource.scala:156-314`, `:388-397`, `:464-552`, `:826-993`, `:1229-1234`; `IO.scala:961-962`, `:1822`, `:2152`, `:2161`; `SyncRef.scala:30`, `:65-73`; `Ref.scala:314`; `GenSpawn.scala:476-498`); upstream commit `3af09e6d56` (fix #4627, PR #4630); `gh search` on typelevel/cats-effect
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

## Mirror

- `Model/ResourceUse.lean`, closure namespace 20 (`ULam`, tags 0-18, fixed twin 30-34; source codes `USrc` tags 50-53).
- `fold` (`Resource.scala:156-196`) uses `F.bracketFull` = `IO.bracketFull` (IOAsync override, `IO.scala:2062-2064`); the mirror builds `Bracket.bracketFullIO` with three `ULam` fields (acquire = the `Allocate` function, use = `case (a, _) => ...`, release = `case ((_, release), oc) => onRelease(...)`). So `Resource#use` inherits the CE-0005 behaviour of `IO.bracketFull` (the `use` closure is called inside `IO.defer`).
- `use(f) = fold(f, _.apply(_))`, `use_ = use(_ => F.unit)`, `useEval = use(ev)` (identity on `F[B]` values, which are `USrc` codes in the model).
- `allocated` (`:550-552`): `F.uncancelable(poll => poll(allocatedCase).map { case (b, fin) => (b, fin(Succeeded)) })`. The `F[Unit]` in the result is a `USrc.relApp` code with a view snapshot.
- `rel2` application (`:490`): `rel(ec).guarantee(F.unit >> release(ec))` = `Bracket.guaranteeIO` with source codes. `rel(ec)` is called at once (strict receiver); `release(ec)` in the `>>` lambda.
- `both` (`:286-314`): `makeCase(F.ref((noop, noop)))(release).evalMap(store => F.both(allocate(this), allocate(that)))`. `F.both` = kernel `GenSpawn#both` (track R `Race.bothIO`). `Ref` = `SyncRef`: `IO.ref` = `IO(Ref.unsafe(a))`; `get` = `delay(ar.get)`; `update` = `delay(spin())` (one atomic model step).
- New function values (`e => release(a, e)`, the stored finalizers) are `RelFn.user idx` with a `ULam` id; `UEnv.rx` (an `REnv`) runs them, and runs the `evalMap` lambda as a `Bind` function. Nested `both` is bounded by `bindDepth = 8`.
- No change of `Model/Resource.lean` was needed; `applyRelX` replaces `applyRel` for the new code. The Phase 5 `applyRel` still gives the fatal 900002 for `RelFn.guarantee`, but no new code path calls it with `guarantee`.

## Model bugs found by the difftest

- `use_` first used a library closure as `onOutput`; `outCall` gave it to the program-level user call (even ids only) and threw `illTyped`. Fix: `OnOut.unitFn`. Found by the first `#eval`, before the difftest.
- No mismatch in the difftest after that.

## Difftest (format v2)

- Ops: `rUse` {res, x, k}, `rAllocated` {res, x, k} (`allocated.flatMap { case (x, rel) => k.flatMap(b => rel.as(b)) }`), resource op `rBoth` {a, b} (`a.both(b).map(VPair)`).
- Lean: `renvF` wraps each level with `ResourceUse.UEnv.rx`; `uenvOf p`; `runClo` takes the `UEnv`; `Bracket.call` gets `dispatchRes` (difftest closures + `ULam`); `srcIO`/`bracketSrcIO` fall back to `ResourceUse.srcU` for `USrc` codes; `libClo?` decodes namespace 20.
- Fixed cases: `difftest/cases/resuse.jsonl` (228 cases, `gen_res.py`), all agree. Case `res-both-relfail-sched5-1` (choices `[0,0,0,0,0,1]`) shows CE-0020 on the real runtime and the model: the trace has no `102`.
- Generator weights: `rUse` 0.8, `rAllocated` 0.6, `res_both` 2.0, `tpl_resBoth` 0.8. Selftest: each track Res op in at least 2 % of 400 cases; the other minimums still hold.
- `opcount.py --seeds 21 22 23 --n 80000 --ops rUse rAllocated rBoth --boost rUse=6 rAllocated=8 res_both=16 tpl_resBoth=16 allocatedCase=3`: 240,000 cases, 240,000 agree, 1,879 s. Per op: rUse 87,130 (29,018 / 29,030 / 29,082), rAllocated 51,777 (17,224 / 17,280 / 17,273), rBoth 54,462 (18,120 / 18,181 / 18,161).

## CE-0020

- Found while designing the `both` mirror: the release runs `F.both(thisFin(ec), thatFin(ec))`; `GenSpawn#both` cancels the other side on `Errored`; the finalizer chain of a side is unmasked at its start; a fiber canceled before it starts runs nothing.
- First smoke test (scala-cli, CE 3.7.1): TestControl 665 of 2,000 seeds and 76 of 20,000 default-runtime runs skip the release of B (program with `.attempt`). Reproducer: 332 of 1,000 seeds; 306-360 of 20,000 default-runtime runs; same on series/3.x (de84c01) and series/3.7.x (2f94201). Fixed twin (`attempt` both chains): 0.
- Lean: one schedule (FIFO 89, then `pick 1`) by `decide +kernel`. Fixed twin `fixedBothRes`: no violation on 600 single-deviation schedules and 1,500 random schedules (`#guard`); v3.7.1 has violations there.
- Duplicate search: see `bugs/CE-0020.yaml` (no upstream issue).

## Smoke tests of the open statements (`test/Phase6/ResourceSmoke.lean`, about 15 min)

- `useReleaseOnce`: 3 releases x 4 bodies x {root, parent} x 900 schedules: no violation.
- `flatMapReleaseOrder`: 32 configurations x 900 schedules: no violation of counts or LIFO.
- `resourceEvalPreservesCancelable` (decision 41): exact `EqvP` sets for `IO.canceled`, `emit; canceled`, `start(cancel 0) >> emit`, `pure 1`: the implication holds. The over-masking `Eval` (wrong function) breaks it for `IO.canceled`.
- `outcomesPList` of `both(A, B).use_` with bound 3,000 is not exact (state space too large), so the CE-0020 witness uses one schedule, not the full set.

## Gotchas

- `Bracket.MarkersOnly` restricts all ids, also odd library ids. A library closure that calls a marker function (for example `ULam.allocFn (.user mA)`, or a `BLam.bfBody` with a marker field) emits the marker, so this hypothesis is false for every environment that runs such a closure. Track Res uses `UserMarkersOnly` (even ids only). The track G statements that use `MarkersOnly` may be vacuous (to check in review batch 4).
- The worktree sandbox refuses shell commands with heredocs, pipes into `python3 -c`, `$HOME` expansion or paths that contain `git` (such as `.github`). Use script files in the scratchpad and absolute paths (`/home/ondra/.elan/bin/lake`).
- A `{ s with f := { call := fun k a _ => if ... then match ... } }` structure literal does not parse; put the function in a separate `def`.
- `decide` on `[Val...].Nodup` hits the recursion limit; `decide +kernel` works.

# race, both, raceOutcome, bothOutcome: mirror, difftest v2, leak observation (own note, Phase 6 track R)

> Source: own work in this repository (`CatsEffectInLean/Model/Race.lean`, `Model/Leak.lean`, `Props/Phase6/Race.lean`, `tools/Difftest/*`, `tools/LeakSmoke/Main.lean`, `difftest/src/...`, `difftest/py/gen.py`, `difftest/py/opcount.py`, `spikes/race-leak/LeakSmoke.scala`), Lean v4.35.0; Scala source read at Cats Effect v3.7.1: `core/shared/src/main/scala/cats/effect/IO.scala:228-229`, `:243-244`, `:638-642`, `:1729-1733`, `:1788-1789`, `:1817-1820`, `:1996-2170`; `kernel/shared/src/main/scala/cats/effect/kernel/GenSpawn.scala:354-500`; `laws/shared/src/main/scala/cats/effect/laws/GenSpawnLaws.scala:28-150`; cats-core 2.13.0 `FlatMap.scala:107-108`, `Functor.scala:157`, `:171`
> Collected: 2026-11-10
> Published: 2026-11-10

## Dispatch

- `IOAsync` (`IO.scala:1996-2170`) overrides none of `race`, `raceOutcome`, `both`, `bothOutcome`.
- `IO#race` → `IO.race` → `asyncForIO.race`; `IO#both` → `IO.both` → `asyncForIO.both`; `IO#raceOutcome`, `IO#bothOutcome`, `IO.bothOutcome` → `asyncForIO.*`. All four run the `GenSpawn` kernel default body.
- So no IO-vs-kernel twin exists for these four. The Lean mirror is the kernel body with the `IOAsync` operations.
- `fa.product(fb)` (in `both`) is cats `FlatMap.product` = `flatMap(fa)(a => map(fb)(b => (a, b)))`. `tupleLeft`/`tupleRight` are `Functor` defaults = `map`.

## Difftest format v2

- Ops `race`, `raceOutcome`, `both`, `bothOutcome` (fields `a`, `b`). A v2 op in a v0/v1 case is a decode error (pre-pass `checkNoV2` in both decoders). `Json.FormatVersion` = 2.
- Result conversion in the runner: `race` → `left`/`right`; `raceOutcome` → `ocVal` under `left`/`right`; `both` → `pair`; `bothOutcome` → `pair` of two `ocVal`.
- Lean: sources are codes `raceSrcA`/`raceSrcB` (node, snapshot, env), rebuilt by `Env.srcIO`.
- First 12 hand cases (`difftest/cases/race.jsonl`) agreed at once. No model bug found.
- Generated (`opcount.py`, seeds 1 2 3 × 75,000, weights of the v2 productions × 10): 225,000 cases, 222,250 agree, 2,750 unsupported (`timeoutTo` with a user fallback), 0 mismatch. Agreeing cases per op: race 56,695; raceOutcome 50,782; both 58,367; bothOutcome 51,340; timeout 21,906.
- Default weights: about 4–6 % of cases use each v2 op (`drive.py run --seeds 1 --n 3000`: 2,951 agree, 49 unsupported).

## Leak observation

- `liveRaceChildren s r`: fibers with no outcome and a race callback (`raceLeft`/`raceRight`) in constructor slot 0 whose `ContState` belongs to fiber `r`. `done` clears callbacks, so such a fiber is a live `racePair` child.
- The Scala `pending` (ready tasks + timers) does not show a fiber that waits forever (`IO.never`). Real-runtime proxy: finalizer trace events, or a counter of started-and-not-ended sides.

## Smoke tests

- `lake exe leaksmoke 200`: 4 combinators × 9 × 9 sides + timeout (9 sides × 3 durations), direct and parent-cancel forms, 200 random `PChoice` lists each: 140,400 runs, 115,749 completed, 0 violations of no-leak or "raceOutcome returns the winner's outcome". Wrong function (race without `f.cancel`): 200/200 completed runs leak.
- `spikes/race-leak/LeakSmoke.scala` on CE 3.7.1 (`TestControl`, 6 seeds, 7 sides, 5 combinators incl. `timeout`, direct + 4 parent-cancel timings): 7,350 runs, 7,038 completed, 0 runs with a live side after the combinator returned.
- `uncancelableRaceNotInherited`: random runs of both sides give only `blocked` with empty trace.

## Exact search does not scale

- `exploreP` on the law's left side: 994 states after 800 expansions, not closed (3 fibers, preemption at every iteration). `checkEqvP` by `decide +kernel` (bound 2000) hit the kernel deterministic timeout after about 8 minutes. So the law stays `open`.

## Result

- No bug candidate. All five registry entries are `open`: universal proofs need an invariant over `Step`/`SchedP` ("a racing fiber passes its combinator only after both children are done").

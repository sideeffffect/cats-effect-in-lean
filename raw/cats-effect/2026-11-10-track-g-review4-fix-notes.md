# Track G review batch 4 fixes: harness markers and satisfiability witnesses

> Source: own Lean work after `review/2026-11-10-review-batch-4.md` and decisions 53-54 (`raw/project-decisions/2026-11-10-decision-53-satisfiability.md`); `Props/Phase6/Bracket.lean`, `Proofs/Phase6/BracketWitness.lean`, `test/Phase6/BracketSmokeParent.lean`
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

- Old `MarkersOnly` was unsatisfiable together with `WellFormed` and the release hypothesis (reviewer proof). The statements were vacuous.
- New design: the test program is a harness environment (`henv a0 u`): harness closures `HLam` (namespace 40), the `Bracket` mirror, then user code `u`. The harness makes two `Ref` cells first; markers capture the cell handle. User code holds no handle (`WellFormed ... []`), so it cannot write, name or forward a marker. A good `BLam` accepts only user functions and `Bracket` leaves as function fields; a harness closure is neither.
- Hypotheses left: `use`, `rel` (or `k`, `q`) even; `WellFormed isLib [] (henv a0 u) a0` (user code and `a0`). No `LibEnv`/`ParentEnv` hypotheses: the statement fixes its own environment.
- The release of the bracket test program is `a => IO.delay(markR).flatMap(_ => rel(a))` (lazy call of `rel`), a harness closure. `dropOc relW` is not `good` (odd field), but the harness dispatch runs it; user code cannot name it (it captures the cell).
- Witness runs: `exploreP` stores choice paths newest first; the run lemma needs the reversed list. Found schedules: picks with 3 preemptions; run length 37 and 32 choices.
- `exploreP` sets for the small inputs (two fibers): bracket 7 observations, counts (0,0) or (1,1); guarantee 9 observations, counts (0,0), (0,1) (cancel lands at the poll before `fa` starts) or (1,1).
- Wrong-function variants in `childOf` (`g = 2`: no release, `g = 3`: no finalizer) break the claims on the smoke inputs.
- GenSpawnLaws citation: `uncancelableRaceNotInherited` is at `L/GenSpawnLaws.scala:146-147` at v3.7.1 (`:121-122` is `fiberCancelationIsOutcomeCanceled`).

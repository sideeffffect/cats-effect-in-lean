# Track Res: merge with track M (memoize)

> Source: own merge of `origin/main` 2d931c6 (track M) into the track Res branch; selftest and difftest runs
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

- One format v2: `V2Ops` / `v2Ops` = race, raceOutcome, both, bothOutcome, guarantee, bracket, bracketCase, bracketFull, memoize, memoGet, rUse, rAllocated, rBoth. `Lam.all` has the track M lambdas, then the track Res lambdas.
- `Env.dispatch`: `Bracket.call` gets `dispatchRes` (difftest closures + `ResourceUse` lambdas); `.ures` (namespace 20) and `.memoize` (namespace 30) both in `libClo?`.
- `selftest.py` after the merge failed: `race` in 4.25 % of 400 cases (minimum 5 %). Only the track Res weights were changed: `rUse` 0.8 → 0.5, `rAllocated` 0.6 → 0.4, `tpl_resBoth` 0.8 → 0.5 (`res_both` stays 2.0). Then race 5.00 %, rUse 3.75 %, rAllocated 4.25 %, rBoth 2.00 %, memoize 1.00 %, memoGet 1.00 % (all at or above the minimums; no minimum changed). The margins are small; N = 400 with a fixed seed, so the result is stable but fragile to new weights.

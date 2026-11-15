# Phase 7 track Q results: difftest counts, long smoke, exhaustive runs

> Source: own runs on the track Q branch (commits `23f753e`..`4eac6fe`): `difftest/py/opcount.py`, `lake exe qsmoke`, `lake exe qsmoke exact`
> Collected: 2026-11-15
> Published: 2026-11-15 (own research note)

## Difftest

- `opcount.py --seeds 71 72 73 --n 22000 --chunk 5000 --ops qNew qOffer qTryOffer qTake qTryTake qSize --boost tpl_queue2=11`: 66,000 of 66,000 cases agree. Each of the six ops is in 52,941 agreeing cases: seed 71 17,651, seed 72 17,598, seed 73 17,692. 0 unsupported, 0 mismatch. Run time 37 min (machine load about 11 on 16 cores).
- Kinds of `qNew` in these cases: `bounded(2)` 5,931, `synchronous` 5,904, `bounded(1)` 5,824, `unbounded` 5,755, `unboundedConc` 3,899, `dropping(2)` 3,849, `circularBuffer(2)` 3,847, `boundedConc(2)` 3,806, `bounded(3)` 3,798, `bounded(0)` 2,018, `dropping(1)` 1,942, `circularBuffer(1)` 1,935, `boundedConc(1)` 1,904, `droppingConc(2)` 1,903, `bounded(70000)` 626. 13,291 of these cases have small runtime thresholds.
- `selftest.py` passes with the generator change: blocked + fuel 22.7 % < 25 %, every key run event >= 3.5 %.

## Smoke

- `qsmoke 1500 30 7`: 3,000 harness inputs (safety and liveness), 84,210 stopped runs, 0 violations.
- `qsmoke exact 20000`: exhaustive `outcomesPList` for the inputs `[[take]]`, `[[offer 1, offer 2]]`, `[[offer 1, take]]`, plan `[(0, 0)]` (the root cancels the one fiber at every point), kinds `boundedConc(1|2)`, `unboundedConc`, `synchronous`, `bounded(2|3)`, `unbounded`, `droppingConc(1)`: 0 violations, 8 to 11 observations each, 4 to 55 s each (the run stopped at a 25 min limit before the last kinds). Inputs with two fibers do not close within 3,000 states.

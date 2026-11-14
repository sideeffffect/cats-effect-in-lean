# Track M follow-up (review batch 4, decisions 53-54)

> Source: own Lean work after review batch 4, 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

- Review batch 4: CE-0030 FAITHFUL (caveat: fixed twin checked on one `fa`); getsAgree, atMostOnce FAITHFUL as statements.
- Satisfiability (decision 53), `Proofs/Phase6/MemoizeSat.lean`: `fa = IO.cede`, no user code, FIFO. `twoGets`: memo cell 0 is `Evaluating(d, 2)` after 40 micro-steps (38..60); root done with `(Succeeded(()), Succeeded(()))`. `countedTwoGets`: cell 1 `Evaluating(d, 2)` after 45 (39..62); root done; counter 1.
- Non-forgeability (decision 54): `progOK` with no handles is false for programs with the counter increment, `tryComplete`, `unsubscribe`, the `flatModifyFull` modify, and a `get` of cell 0.
- Fixed-twin family (fuel 200, one preemption at i < 120, FIFO after): v3.7.1 stuck at [35, 36, 37] for canceled, emit >> canceled, start(emit) >> canceled, uncancelable(_ => canceled); [] for pure, raiseError, cede >> canceled. cede >> canceled with two preemptions (i in 30..39, j in 5..19): stuck at (34,12) (34,13) (34,14) (35,11) (35,12) (35,13) (36,11) (36,12) (37,11). Fixed twin: every run ends `done`. FIFO run lengths 70-84 micro-steps.

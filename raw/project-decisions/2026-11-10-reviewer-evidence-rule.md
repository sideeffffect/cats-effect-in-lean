# Reviewer evidence rule (orchestrator)

> Source: own finding after the track R follow-up, 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

- Review batch 4 passed the race/leak statements partly on a wrong-function test that it cited as `Model/RaceSmoke.lean`, `RaceSmoke.noCancel_leaks`. That file never existed: the track R module doc named it, but the file was not written. The reviewer took the doc as evidence.
- Track R then added the test as a kernel-checked theorem (`Proofs/Phase6/RaceWitness.lean`, `noCancel_leaks`).
- Rule: a reviewer cites only evidence it opened. A wrong-function test, a witness or a fixed twin counts only if the reviewer found the file and the declaration (by path and name). A doc comment that names a check is not evidence.

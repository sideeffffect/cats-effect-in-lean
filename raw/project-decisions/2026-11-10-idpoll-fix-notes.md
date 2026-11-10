# idpoll model bug fix and merged-codec seam (orchestrator)

> Source: own work while merging the review-1 fixes and difftest v1, 2026-11-10
> Collected: 2026-11-10
> Published: 2026-11-10

- The difftest v1 agent found a model bug, "idpoll". `IO#syncStep` calls an `uncancelable` body with `IdPoll`, where `apply(ioc) = ioc` (`core/shared/src/main/scala/cats/effect/IO.scala:2391-2393`). The model encodes it as `Val.poll 0 0`. Five mirror sites (`Model/Timeout.lean`, `Model/Resource.lean`, `Std/Queue.lean`) turned every `poll(io)` into `UnmaskRunLoop(io, m, p)`, also for mask id 0. On the root fiber this left the rest of the program masked.
- Example: `syncStep(timeout(canceled, 1ms))` is `canceled` in Scala and was `blocked` in Lean.
- Fix: one helper `IO.applyPoll io m p := if m == 0 then io else .unmaskRunLoop io m p` in `Model/Syntax.lean`, used at all 7 poll sites of the three mirrors. The CE-0001 refutation did not use these mirrors.
- The difftest agent had made CI pass with `--allow-known-model-bugs`. That weakens a gate, so the orchestrator removed it and fixed the bug instead. The 3 shrunk cases are now ordinary regression cases (`difftest/corpus/fixed-idpoll-*.json`, `expect: agree`).
- Merge seam: the fidelity agent merged `Model/Codec.lean` and `Model/ValCodec.lean` into one `Codec` (user closure ids even, library ids odd). The difftest Lean side still used the old `nsFn`/`decList`. Now difftest closures are `Codec.userFn (.nat (Clo.encode c))` and library closures decode through `Codec.cloOfId` + `ofCloVal`.
- Result after the fix, 6 seeds x 10,000 replay cases: 58,957 agree, 0 mismatch, 0 known model bug, 1,043 unsupported (all `timeoutTo` with a user fallback, not mirrored).
- Decision: `Eqv` keeps the cut at root completion (a model run stops when the root fiber completes, like `IOApp` and like CE's `Eq[IO]` in its law tests). Effects of child fibers after that point are not observed. Liveness/leak properties must state child behaviour separately.

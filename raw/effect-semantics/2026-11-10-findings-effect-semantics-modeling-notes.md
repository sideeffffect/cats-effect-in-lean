# Findings: modeling CE3 IO/fibers/cancelation in Lean (research notes)

> Source: own analysis of the files in raw/effect-semantics/ (collector notes, not a primary source)
> Collected: 2026-11-10
> Published: 2026-11-10

## Existing formal work

- Web searches (2026-11-10) found no Coq/Lean/Agda/Isabelle/TLA+ formalization of Cats Effect, ZIO, or Monix. Confidence: medium (absence of evidence).
- The closest artefact is CE3's own `PureConc` (kernel-testkit/pure.scala): a pure model of `GenConcurrent` built from Kleisli + coop `ThreadT` (a free-monad cooperative thread transformer) + MVar. Laws are checked against it with a single deterministic round-robin scheduler (`ThreadT.roundRobin`). It does not explore other interleavings.
- The laws modules (discipline) are: MonadCancelLaws, GenSpawnLaws, GenTemporalLaws, SyncLaws, AsyncLaws, ClockLaws, UniqueLaws. No GenConcurrentLaws file exists on series/3.x.

## Divergences observed by reading code (not run)

1. `PureFiber.cancel = state.tryPut(Outcome.Canceled()).void`. It does not wait for finalization. GenSpawn and Fiber scaladoc say `cancel` "semantically blocks the caller until finalization of the cancellee has completed". Issue #3430 (open since 2023-02-17) shows PureConc does not run `onCancel` finalizers of a fiber parked in `never`. So the reference model used for law checking is known to diverge from the spec. Confidence: high (maintainers agree in #3430).
2. Poll identity. IO: `masks += 1; id = masks`; `poll` unmasks only if `masks == id && self eq cur.self` (IOFiber tag 13). PureConc: each `uncancelable` makes a fresh `MaskId`; poll drops the mask only when the top of the mask stack is that id. Hypothesis (UNVERIFIED): a `poll` that escapes its `uncancelable` (e.g. `uncancelable(p => pure(p))`) and is later applied inside a different `uncancelable` at the same nesting depth will unmask that other block in IO (ids coincide), but not in PureConc. Test this by differential execution before claiming a bug; maintainers may call escaped poll undefined behaviour.
3. IO checks the `canceled` flag on every run-loop step, but issues a read barrier only every `cancelationCheckThreshold` (default 512) iterations. External cancelation is therefore observed with an unbounded-in-model delay. The spec allows this ("Cancelation is advisory").

## Semantics facts to encode

- Outcome = Succeeded | Errored | Canceled; a fiber may also never terminate.
- Masking: cancelation requested while masked is deferred until the fiber is completely unmasked. `poll` undoes only its own `uncancelable`. Nested masks do not count in the user model (outer wins), but IO implements them with a counter.
- No cancelation boundary after a combinator ends (so a `poll` result is not lost). But cancelation is visible right at the end of an `uncancelable` (issue #1744) — the law `onCancelAssociatesOverUncancelableBoundary` documents a deliberate monad-law violation.
- External cancel: masking, backpressure (cancel waits for finalizers), idempotency, terminal (cancel of a finished fiber returns at once). `cancel` is itself uncancelable.
- `canceled` inside `uncancelable` = `unit`, but the cancel flag stays set.
- Since 3.5.0, `async` with `None` finalizer is uncancelable while suspended (`async_` is uncancelable). Laws `asyncRightIsUncancelableSequencedPure` etc. encode it.
- Fiber leaks: `start`/`racePair` are cancelation-unsafe; parents do not cancel children (no structured concurrency in the kernel).

## Haskell comparison

- GHC `mask` + `restore` ≈ CE3 `uncancelable` + `poll`. Differences: GHC has *interruptible* operations (blocking `takeMVar` can receive async exceptions inside `mask`); CE3 has none — a blocked `Deferred.get` inside `uncancelable` without `poll` cannot be canceled (deadlock risk, cf. discussion #1979). GHC `throwTo` is synchronous (returns once delivered); CE3 `cancel` waits for full finalization (stronger).
- Marlow et al. 2001 give a small-step semantics with process soup, "exception in flight" processes, and split evaluation contexts (blocked/unblocked). This is a direct template for a CE3 small-step semantics.

## Lean facts

- Lean `IO` is EStateM over an opaque world token; `Task`/`IO.asTask` are opaque runtime primitives with cooperative cancellation (`IO.checkCanceled`). Nothing in Lean core gives a reasoning model for concurrency. We must build our own model.
- `Std.Do`/`mvcgen` (Lean core) supports monads with WP/LawfulMonad/WPMonad instances; reference says it targets "single-threaded control with state that might be interrupted"; "more exotic effects have not yet been investigated". Useful for per-fiber sequential reasoning, not for interleavings.
- Lean ITree ports exist (boogie-org/lean-itrees, ISTA-PLV/Coinductive, HITrees). All are early or research-grade.

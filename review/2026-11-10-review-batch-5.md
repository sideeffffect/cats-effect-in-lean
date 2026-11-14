# Review batch 5 (2026-11-10): 4 Phase 6 track Res (`Resource`) registry entries

Reviewer: independent agent. It did not write the code. It read the Lean source, the bug record, the reproducer, the smoke tests, the inventory, the wiki, review batch 4 and decisions 53–54. It did not run a build, Lean, a test, sbt or scala-cli. It ran read-only `gh search issues` / `gh search prs` on typelevel/cats-effect and read `Resource.scala` on `origin/series/3.x`.
Reviewed commit: `3e553ed` (track Res, merged with track M).
Rubric: `AGENTS.md` section 5 and `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test, vacuous hypotheses, fixed-twin check of decision 39, satisfiable hypotheses and harness-only markers of decisions 53–54). When unsure, the answer is no.
Scala source: `~/Projects/cats-effect` at `eb0cc258` (tag `v3.7.1`). Short names: `RES` = `kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`, `GS` = `kernel/.../GenSpawn.scala`. Lean paths are relative to `CatsEffectInLean/`.

## Summary

| Registry entry | Status | Verdict |
|---|---|---|
| `kernel.Resource.both.releaseOnce` (CE-0020) | refuted | **HOLLOW** as registered (forgeable markers: a correct `both` also refutes the statement). The bug is real and the witness is genuine. |
| `kernel.Resource.use.releaseOnce` | open | **HOLLOW** (statement false for every implementation; no satisfiability witness) |
| `kernel.Resource.flatMap.releaseOrder` | open | **HOLLOW** (same defect) |
| `kernel.Resource.eval.preservesCancelable` | open | FAITHFUL as a statement (caveats) |

The mirror of `fold`/`use`/`both` is good. The CE-0020 defect is real, reachable through the public API (`Resource#both`, `parTupled`, `parMapN`), and not a duplicate. The problem is the test harness of the three marker statements: `UserMarkersOnly` does not stop user code from running a marker through a library closure. This is the second half of the batch-4 finding, which the author noted as a "Limit" in the doc comment of `UserMarkersOnly`, but did not close.

---

## The shared defect: `UserMarkersOnly` lets user code forward a marker

`Props/Phase6/Resource.lean:61-64`. Clause 1 restricts only even ids. Clause 2 checks `usesId m p` on programs that even ids return. `usesId.fnUses` (`Props/Phase6/Bracket.lean:133-135`) compares only the direct id of a `Fn.user k`. It does not look into the captured fields of an odd library closure.

Concrete forgery (any `both`, `use` or `flatMap` implementation):

- Let the use function `f` (even id `2f`, not in `ms`) return `.map (.pure ()) (ULam.allocFn (.user mR)).fn`.
- `ULam.allocFn (.user idx)` is a library closure of this mirror (`Model/ResourceUse.lean:156`, `:570`). Its call is `U.rx.user.callV idx arg v` = `U.r.user.callV mR arg v` (for `mR` not a `ULam` id, for example even `mR`). By `MarkedMake`, this is the marker: it emits `R` and returns `unit`.
- `WellFormed`: the closure id is odd and `isLib` (`ULam.ofId?` decodes tag 0), and its fields hold no handle (`allocFnToVal (.user k) = tagged 0 (.nat k)`), so `fnOK`/`progOK` accept it (`Model/WellFormed.lean:135-150`). `CallOK` and `PollOpaque` hold for a constant user function.
- `UserMarkersOnly`: clause 1 holds (`2f` emits nothing). Clause 2 holds: the program names only the odd closure id, so `usesId (2 * mR) p = false`.
- Run: the body emits `R` once, and the release emits `R` once. So `count R = 2 ≠ 1 = count A` in a run that ends.

Other vectors with the same effect: `ULam.allocFn (.make acq rel)` with the marked `acq` (emits `A` again); `a0` of `MarkedMake` may contain the same closure (`usesId (2 * mA) a0 = false` does not see it); `Bracket.BLam.thenUse` and the Phase 5 `Clo` closures also forward to user ids.

Consequences:

- Entries 2 and 3 are false for every implementation, including a correct one. They can never be proved. A refutation of them would say nothing.
- Entry 1: `¬ bothReleasesBoth` also holds for the fixed twin `fixedBothRes` (same forgery). So the registered theorem alone does not separate v3.7.1 from a fix. By decision 39 and the batch-2 precedent (CE-0001), the entry is HOLLOW as registered.
- Decision 54 asks for exactly this: markers that user code cannot forge or forward.

---

## 1. `kernel.Resource.both.releaseOnce` (CE-0020, refuted)

- verdict: **HOLLOW as registered**; bug confirmed by reading; witness genuine.

1. MIRROR: yes.
   - `foldLoop` (`Model/ResourceUse.lean:425-442`) = `RES:171-194`: branch order `Allocate`, `Bind`, `Pure`/`Nil`, `Pure`/`Frame`, `Eval`. `Allocate` → `IO.bracketFull` with `foldUse`/`foldRel` (`RES:174-182`). A throwing `Bind` head is a throw of the use lambda (`callU .foldUse`, `:576-588`).
   - `useIO` = `fold(f, _.apply(_))` (`RES:207-208`).
   - `bothRes` = `Bind(Allocate(_ => F.ref((noop, noop)).map(a => (a, e => release(a, e)))), evalMapK)`, which is `makeCase` → `applyCase` → `applyFull` → `Allocate` (`RES:917-920`, `:849-850`, `:879-880`) and `evalMap` = `flatMap(a => eval(f(a)))` (`RES:558-559`).
   - `evalMapRes` builds `F.both(allocate(this, …), allocate(that, …))` eagerly: both `fold`s run now (a `Bind` throw on side A wins), then `Eval(bothIO …)`. Correct: Scala arguments are strict.
   - `updateThunk` = `store.update(_.bimap(f, identity))` / `(identity, f)` (`RES:309-310`), with `f = fin => ec => F.unit >> fin(ec).guarantee(release(ec))` (`RES:295`). `storedFinK` calls `fin(ec)` then `release(ec)` (strict receiver, strict `guarantee` argument), then `IO#guarantee`. Inner resources store first (the inner `bracketFull` with `_.pure[F]` ends first), so the chain is LIFO, as in Scala.
   - `bothRel`/`bothRelK` = `finalizers.get.flatMap { case (thisFin, thatFin) => F.void(F.both(thisFin(ec), thatFin(ec))) }` (`RES:302-306`): both calls now, then `bothIO`, then `.map(_ => ())`.
   - `F.both` = `GS:474-500` (no `IOAsync` override; checked in batch 4). The `Errored(ea)` branch is `f.cancel *> raiseError(ea)` (`GS:485`).
   - `F.ref` = `IO(Ref.unsafe(a))` (`IO.scala:1822`, `:2161`): checked.
   - `origin/series/3.x` `Resource.scala:305` still has `F.void(F.both(thisFin(ec), thatFin(ec)))`.
2. PROPERTY: no, as registered.
   - The promise is sound: the Scaladoc (`RES:248-257`) says both sides' finalizers run, and "each acquired resource is released once" is an undisputed invariant. A release that raises is a legal input: `release: A => F[Unit]` may fail, nothing forbids it, and `flatMap` (nested `bracketFull`) still releases all resources in that case.
   - The witness is ordinary: two `Resource.make`, a release that raises, `use(_ => IO.unit)`, no parent, no forged marker.
   - But the statement is false for a correct `both` (shared defect above). The fixed-twin check of decision 39 holds only on the witness environment (`test/Phase6/ResourceSmoke.lean`, 600 family + 1,500 random schedules), not for the statement.
3. SETTLED: yes, if the statement is fixed.
   - `bothReleasesBoth_refuted` (`Proofs/Phase6/ResourceBoth.lean:151-161`): one run by `decide +kernel`, trace `[101, 2, 1]`, outcome `Errored(boom)`. The type is exactly `¬ P`.
   - The hypotheses are proved for the witness: `markedA`, `markedB`, `markersOnly`, `prog_wf` (`userR_ok`, `calls`, `env_opaque`). This also serves as the satisfiability witness of decision 53 for `viaParent = false`.
   - Reproducer: real `a.both(b)` and `parTupled`; release A sets a flag, then raises. It prints `REPRODUCED` if one TestControl seed of the real `both` misses release B. Recorded: 332/1,000 seeds, 306–360/20,000 default-runtime runs, on v3.7.1, `series/3.x` and `series/3.7.x`. The `FixedBoth` copy gives 0.
   - Bug record: complete. `likelihood: Medium` and `maybe_intended: Unlikely` are honest (a leaked resource with no error; PR #1689 does not discuss errors).
   - Duplicates: my searches (`Resource both release error`, `both finalizer cancel`, `parallel finalizers error`, `Resource both leak`, `parTupled`, PRs `Resource both`, `Resource both finalizers`) found nothing new. #4620 (`Fiber#joinOrCancel`, open) is unrelated.
4. FIXED TWIN: pass on the witness environment only (see 2).

Note: the witness trace has no fiber for B's chain at all. That is the real mechanism: an unmasked `racePair` child that is canceled before its first step runs nothing.

## 2. `kernel.Resource.use.releaseOnce` (open)

- verdict: **HOLLOW**

1. MIRROR: yes (`useIO`, `foldLoop`, `bracketFullIO`; `Res.make` = Phase 5 `AllocFn.make`).
2. PROPERTY: no. The statement is false for every implementation (forgery above). Decision 53: there is no Lean satisfiability witness. The smoke part 2 does not evaluate the hypotheses: `US` has `resOf := fun _ => none`, so `MarkedMake` (which needs `U.resOf c = some (Res.make …)`) is false for every smoke instance, and `UserMarkersOnly` is never checked.
3. SETTLED: open. OK as a status, but no proof can exist for the current statement.
4. WRONG-FUNCTION: "never run release" fails the conclusion on the honest smoke runs. Pass in spirit, but the forgery makes the point moot.

## 3. `kernel.Resource.flatMap.releaseOrder` (open)

- verdict: **HOLLOW**

1. MIRROR: yes. `Res.flatMap` = `Bind`, `fold` nests `bracketFull`.
2. PROPERTY: no, the same as entry 2: forgeable markers, no satisfiability witness, smoke `US` fails `MarkedMake`. The order part (`Before o.out RA RB`) is right: `out` is newest first, so `RA` (outer) newer than `RB` (inner) means LIFO.
3. SETTLED: open.
4. WRONG-FUNCTION: a FIFO release order fails the `lifo` smoke check. Pass in spirit.

## 4. `kernel.Resource.eval.preservesCancelable` (open, decision 41)

- verdict: FAITHFUL as a statement (caveats)

1. MIRROR: yes. It uses the Phase 5 `allocatedCase` mirror (reviewed FAITHFUL in batch 3) on `Res.evalOf fa`.
2. PROPERTY: yes. "Preserves interruptibility of `fa`" (`RES:986-993`), cancelable direction. All hypotheses are lambda definitions, the `allocatedCase` result and `WellFormed`. The premise `¬ EqvP fa (uncancelable fa)` is the antecedent of the claim and holds for `fa = IO.canceled`.
3. SETTLED: open. OK. The proof idea (a masked root never ends `Canceled`, and `alloc` keeps every `Canceled` run of `fa`) is plausible.
4. WRONG-FUNCTION:
   - Over-masking `Eval` fails (smoke). "Always `pure`" fails (masking `pure` changes nothing).
   - "Always `IO.canceled`" satisfies this direction. The companion `preservesUncancelable` (CE-0002) catches it, so the pair is sound. This entry alone is one-directional by design (decision 41).

Caveats:
- Smoke part 3 does not compute `alloc` with `allocatedCase`. `allocOf` is written by hand (`IO.flatMap fa (cloFn (.evalK [] .unit))`). It must be checked against `allocatedCase r (Res.evalOf fa)`, or computed from it.
- Recommended (decision 53 is not strictly triggered): a Lean theorem that the premise holds for `fa = IO.canceled`, so the implication is not vacuous.

## Inventory rows marked `modelled` by CE-0020

| Row | Mirror used by `bothReleasesBoth` | OK |
|---|---|---|
| `kernel.Resource.both` | `bothRes`, `evalMapRes`, `bothRel`/`bothRelK`, `updateThunk`, `storedFin` | yes, when entry 1 is fixed |
| `kernel.Resource.use` | `useIO` | yes, when entry 1 is fixed |
| `kernel.Resource.fold` | `foldLoop` (Allocate, Bind, Eval, Pure/Nil exercised; Pure/Frame not) | yes, when entry 1 is fixed |
| `kernel.Resource.makeCase` | only the instance inside `both` (`bothAlloc`, `mcPair`), inlined; no general `makeCase(acquire)(release)` mirror | **no** |
| `kernel.Resource.evalMap` | only the instance inside `both` (`evalMapK`), inlined; no general `evalMap(f)` mirror | **no** |

Because entry 1 is HOLLOW as registered, all five rows should go back to `todo` until it is fixed. After the fix, `makeCase` and `evalMap` need a general mirror, or they stay `todo`.

## Required fixes

1. Close the forgery (decision 54). Options:
   - Make the markers harness closures that capture a handle that no user code holds, and make `WellFormed` reject a user program or value that holds that handle. The `MarkedMake` releases come from `U.r.release`, which is harness data (an `REnv` Lean function), so the harness can place the closure there.
   - Or a deep `usesId`: decode closure fields recursively (`AllocFn.user/make`, `RelFn`, `Res` codes, `Bracket`, `Race`, `Clo` closures) and reject any user-built program, `a0`, value or `Bind` result that reaches a marker id or a marked acquire/release code.
   After the fix, show (by reading or a short proof) that a correct `use`/`both` cannot emit a marker outside its harness position.
2. Re-prove `bothReleasesBoth_refuted` under the new hypothesis. The witness uses no forgery, so it should carry over.
3. Decision 53: add Lean satisfiability theorems for `useReleaseOnce` and `flatMapReleaseOrder`, for `viaParent = false` and `true`.
4. Smoke: make the instances satisfy the hypotheses (`resOf` must give the `Res.make`), and evaluate the marker hypothesis where it is decidable. Compute `alloc` of part 3 with `allocatedCase`.
5. Inventory: set the five CE-0020 rows back to `todo` until entry 1 passes review. Keep `makeCase` and `evalMap` `todo` unless a general mirror is added.
6. Recommended: the reproducer should print `REPRODUCED` only if the fixed copy misses no release (`m4 == 0`), as CE-0030 does.

## Confidence

- Mirror of `fold`/`use`/`both`: 0.85.
- CE-0020 is a real, public, non-duplicate defect: 0.9.
- The forgery satisfies all hypotheses of entries 1–3: 0.8 (checked by reading `WellFormed.lean` `fnOK`/`progOK`/`captured`, `ResourceUse.callU`, `usesId`; not run).

# guarantee and bracket model, and CE-0005

> Sources: Cats Effect source at v3.7.1 (`IO.scala:338-371`, `:496-530`, `:967-972`, `:1826-1830`, `:2023-2064`; `kernel/.../MonadCancel.scala:344-456`; `laws/.../MonadCancelLaws.scala:28-29`); own Lean work and scala-cli runs, 2026-11-10
> Raw: [Track G notes](../../raw/cats-effect/2026-11-10-track-g-bracket-notes.md); [Review 4 fix notes](../../raw/cats-effect/2026-11-10-track-g-review4-fix-notes.md)

## Overview

Phase 6, track G. The model mirrors `IO#guarantee`, `IO#guaranteeCase`, `IO#bracket`, `IO#bracketCase`, `IO.bracketFull` and `reportError`, and the kernel defaults of `MonadCancel` with the `IO` operations as twins. The twin `IO.bracketFull` vs kernel `bracketFull` is refuted: CE-0005. Four other statements are `open` with smoke tests.

## Files

| File | Content |
|---|---|
| `Model/Bracket.lean` | Mirror (closures `BLam`, namespace 7), sources `Src`, builders, `LibEnv`, `isLib`, lemmas `libEnv_of_dispatch`, `call_congr`; fixed twin `fixedBracketFullIO` (not CE code) |
| `Model/BracketExamples.lean` | Small user environment for smoke tests |
| `Props/Phase6/Bracket.lean` | 5 properties; the harness `henv`/`HLam` of the invariants (counter cells, parent cancel) |
| `Proofs/Phase6/BracketWitness.lean` | Satisfiability witnesses of the 4 open entries (decision 53), kernel-checked, default build |
| `Proofs/Phase6/BracketFullTwin.lean` | `bracketFullIsKernelDefault_refuted` and the well-formed witness |
| `Proofs/Phase6/BracketFullFixed.lean` | Fixed-twin check (decision 39); in `lean_lib TwinChecks` (several minutes), built by `scripts/check_twin_checks.sh` |
| `Proofs/Phase6/BracketSmoke.lean` | In `TwinChecks` (about 6 min). Kernel-checked smoke tests: the law (14 pairs + wrong-function test), the pure-use twin (4) |
| `test/Phase6/BracketSmokeParent.lean` | `#guard` smoke tests of the two invariants (parent cancel, about 3,000 states per program; `decide +kernel` needs about 19 GB, so not in the build). Run: `lake env lean test/Phase6/BracketSmokeParent.lean` |

## Mirror rules

- `F = IO`. Each Scala lambda is a library closure (odd id). A captured `IO` is a source code: `Src.ext s` is the caller's program (`ioOf s`); other `Src` cases are terms the mirror builds.
- A user function (`finalizer`, `acquire`, `use`, `release`) is called inside the lambda body, as in Scala: `finalizer(Outcome.canceled)` runs when the `guaranteeCase` body runs. Effects come first; a throw of the user function is a throw of the lambda.
- Leaf lambdas (`_ => this`, `_ => fin`, `(a, _) => release(a)`, `release(a, _)`) run inline. So the mirror calls user code only on even ids, and an environment without recursion is a `LibEnv` (`libEnv_of_dispatch`).
- `ec.reportFailure(t)` is the user effect `UserEffect.report` (new). It logs `TraceEv.reportFailure`, which `Obs.reports` observes.
- `IO.defer(t)` = `Delay(thunk).flatMap(ev)`: the thunk returns `unit` and `ev` does the work. Same iteration, same `try` (`IOFiber.scala:420-437`).

## Twins

| Pair | Result |
|---|---|
| `IO#guarantee` vs kernel `guarantee` (= `IO#guaranteeCase(_ => fin)`) | the law `guaranteeIsGuaranteeCase`; open, smoke tests agree |
| `IO#guaranteeCase` vs kernel `guaranteeCase` | differ only in `reports`: the kernel drops a finalizer error in the error case, IO reports it. Deliberate; not registered |
| `IO.bracketFull` vs kernel `bracketFull` | refuted (CE-0005) |
| `IO#bracket`/`bracketCase` vs kernel | the kernel calls the virtual `bracketFull` = `IO.bracketFull`: same closures |

## CE-0005

`IO.bracketFull` builds `IO.defer(poll(use(a)))`: `use(a)` is called while the fiber is masked. The kernel builds `poll(unit >> use(a))`: unmask first. With a cancel request during acquire (parent cancel, or `IO.canceled` in acquire) and a `use` that throws, IO ends `Errored(e)` and release gets `Errored(e)`; the kernel ends `Canceled` and release gets `Canceled`. An effectful `use` runs only in IO. The model predicted this before the Scala run. Reproduced on 3.7.1, series/3.x, series/3.7.x. Priority low. Fix: `poll(IO.defer(use(a)))`.

## Properties

| Entry | Status | Note |
|---|---|---|
| `core.IO.bracketFull.kernelDefaultTwin` | refuted | witness: acquire `IO.canceled`, use throws |
| `core.IO.bracketFull.kernelDefaultTwin.pureUse` | open | ordinary inputs; needs a simulation proof |
| `laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO` | open | 14 smoke pairs, wrong-function test |
| `core.IO.bracket.releaseOnce` | open | parent cancels child (decision 50); harness counters: cell 0 acquire done, cell 1 release started; claim cell 1 = cell 0 |
| `core.IO.guarantee.finalizerOnce` | open | same harness; cell 0 `fa` started, cell 1 finalizer started; claim cell 1 ≤ 1 and cell 0 ≤ cell 1 |

### Review batch 4: restated invariants (decisions 53, 54)

The first form of the two invariants was vacuous. Its hypothesis `MarkersOnly` ("no user code other than the markers emits `A`/`R`, and no user program names a marker") never held together with the others: `release` had to name the marker, and a library closure (`BLam.thenUse m a`, good for any even `m`) forwarded a marker emit. A naive fix (check only even ids) would make the guarantee statement false for a correct `guarantee`, because user code could re-run an unprotected marker.

The new form: the test program is a harness (`henv`, closures `HLam`, namespace 40), not a hypothesis on an arbitrary environment. It first makes two counter cells; the markers are harness closures that capture the cell handle. `WellFormed` with no handle at the start makes the cells unreachable for user code: it cannot write them, name a marker, or forward one (a good `BLam` takes only user functions or `Bracket` leaves as function fields). The quantifiers stay the same: all user code `u`, all `WellFormed` acquire programs `a0`, all user `use`/`rel` (`k`/`q`), all schedules. So this fixes the statement; it does not weaken it.

- Satisfiability witnesses (kernel-checked, `BracketWitness.lean`): for each entry one input that meets all hypotheses and reaches the interesting case. The invariants: acquire done (or `fa` started), release run once, child canceled by the parent. `pureUse`: acquire `IO.canceled`, pure `use`, left side `Canceled`. The law: `fa` raises, `fin` emits, left side runs `fin`.
- Smoke (`test/Phase6/BracketSmokeParent.lean`, `#guard`, hypotheses checked too): bracket, 4 acquires x 4 uses plus 2 releases that suspend or cancel themselves; guarantee, 4 x 3. The claim holds for every observation of the exact outcome sets. Wrong-function test: a bracket without release (`childOf` `g = 2`) and a guarantee without finalizer (`g = 3`) break the claims.

Why open: a proof for all programs needs a simulation or a state invariant over `Sched.tickP` and all of `Step.lean`. Not done.

Earlier caveat (track Res, 2026-11-10): `MarkersOnly` also restricted odd (library) ids, so the old invariants could be vacuous. Review batch 4 confirmed it. Resolved by the harness restatement above (no `MarkersOnly` any more).

## Difftest (format v2)

Ops `guarantee`, `bracket`, `bracketCase`, `bracketFull` ([format](../methodology/difftest-program-format.md)). Agreement: per op 51,290 to 55,575 agreeing cases over seeds 1-3 (details in the raw note). The language cannot make a throwing `use`, so CE-0005 is only in the reproducer.

After the merge with tracks R and D (one format v2 with `race`, `raceOutcome`, `both`, `bothOutcome`; D's `runtime` thresholds): `difftest/py/opcount.py --seeds 11 12 13 --n 20000` with all 8 v2 ops: 60,000 cases, all agree. Cases per op: race 3,908, raceOutcome 3,384, both 3,973, bothOutcome 3,475, guarantee 4,152, bracket 3,678, bracketCase 3,687, bracketFull 3,925. The generator weights of the track G ops were lowered (guarantee 1.0, bracket* 0.8, tpl_bracket 1.0), so the v1 and track R coverage minimums of `selftest.py` still hold.

## See Also

- [Kernel typeclasses model](kernel-typeclasses-model.md)
- [Resource model and CE-0002](resource-model.md)
- [Resource use, allocated, both, and CE-0020](resource-use-both-model.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Bug history](bug-history.md)

# Track G notes: guarantee, bracket*, CE-0005

> Source: own Lean work (`CatsEffectInLean/Model/Bracket.lean`, `Model/BracketExamples.lean`, `Props/Phase6/Bracket.lean`, `Proofs/Phase6/BracketFullTwin.lean`, `BracketFullFixed.lean`, `BracketSmoke.lean`), difftest format v2 (`difftest/`, `tools/Difftest/`), scala-cli runs of `reproducers/CE-0005/Repro.scala` on 3.7.1, `3.7.1-89-de84c01` (series/3.x), `3.7.1-15-2f94201` (series/3.7.x); Cats Effect source at v3.7.1 (`IO.scala:338-371`, `:496-530`, `:967-972`, `:1826-1830`, `:2023-2064`; `kernel/.../MonadCancel.scala:344-456`); `gh search` on typelevel/cats-effect
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

## Mirror

- `Model/Bracket.lean`, closure namespace 7 (`Codec.cloVal`; queue 1, timeout 2, difftest 3, test programs 8/9).
- `IO#guarantee`, `IO#guaranteeCase`, `IO#bracket`, `IO#bracketCase`, `IO.bracketFull`, `reportError`; kernel `guarantee`, `guaranteeCase`, `bracketFull` with the IO operations. Kernel `bracket`/`bracketCase` call the virtual `bracketFull`, so for IO they build the same closures as `IO#bracket`/`IO#bracketCase`.
- `ec.reportFailure(t)` needed a new user effect: `UserEffect.report e` (Syntax.lean). `applyEffects` logs `TraceEv.reportFailure e`, so `Obs.reports` sees it. WellFormed: no handle condition.
- Captured `IO` values (`this`, `fin`) are source codes (`Src`): external (`ioOf`, like `Timeout.srcIO`) or internal terms (`IO.defer(poll(use(a)))`, `poll(unit >> use(a))`).
- User functions inside library lambdas are called in the lambda body (`finalizer(Outcome.canceled)` runs when the guaranteeCase body runs, before `poll(this)` runs). Effects first, a throw of the user function is a throw of the lambda.
- Leaf lambdas (`_ => this`, `_ => fin`, `(a, _) => release(a)`, `release(a, _)`) run inline (`callLeaf`, `callFn`). So `call` calls `uc` only on even ids. That makes an environment without recursion a `LibEnv` (`libEnv_of_dispatch`, `call_congr`).
- `IO.defer(poll(use(a)))`: a `Val` cannot hold an `IO`; the thunk returns `unit`, `ev` calls `use(a)`. Same iteration and same `try` (`FlatMap` over `Delay`, IOFiber.scala:420-437).
- Observed difference already known: kernel `guaranteeCase` drops a finalizer error in the error case; IO reports it (`reports = [E4]` vs `[]`). Not registered (deliberate improvement).

## Difftest format v2

- Ops `guarantee`, `bracket`, `bracketCase`, `bracketFull`; fin events `{"ev":"fin","op":"guarantee"|"bracket","tag"}` and `{"ev":"fin","op":"bracketCase"|"bracketFull","tag","oc"}`.
- 3 seeds x 190,000 generated cases, cases with a v2 op kept: 172,746 cases; 167,265 agree, 4,479 unsupported (`timeoutTo`), 2 mismatches. Per op (agree): guarantee 55,575; bracket 51,290; bracketCase 51,581; bracketFull 53,336.
- The 2 mismatches were a harness encoding clash, not a model bug: `handleErrorWith` binds 999998 for a `TimeoutException`; `raise` (fn 3) of that code makes `UserError(999998)`; Lean has one `Err` for both (code 10^6), so a reported one printed `TimeoutException` in Lean and `UserError: UserError(999998)` in Scala. Fix: Scala `reportFailure` prints both as `TimeoutException`. Both cases agree after the fix.
- Fixed cases `difftest/cases/bracket.jsonl` (50, from `gen_v2.py`): all agree.
- The difftest language cannot make a `use` function that throws (building a program never throws except `TypeError`, which generators avoid). CE-0005 is covered by the reproducer only.

## CE-0005

- `IO.bracketFull` = `IO.uncancelable { poll => acquire(poll).flatMap { a => IO.defer(poll(use(a))).guaranteeCase(release(a, _)) } }`. `use(a)` is called while masked.
- Kernel: `poll(unit >> use(a))`: unmask first, so a pending cancel is seen before `use(a)` is called.
- Cancel request during acquire + throwing `use`: IO ends `Errored(e)` and release gets `Errored(e)`; kernel ends `Canceled`, release gets `Canceled`. Effectful `use`: IO calls it, kernel does not.
- Model predicted it before the Scala run; real CE 3.7.1 agrees (also series/3.x, series/3.7.x).
- Fixed twin `poll(IO.defer(use(a)))` agrees with the kernel body (8 programs in Lean, reproducer `fixedBF`).
- Duplicates: none. Related #1535 (throwing use in the old kernel body), PR #2126 (current IO body).

## Gotchas

- `lake exe cediff` rebuilds changed modules. A background difftest run failed when a Lean file was half-edited. Use a copy of the `cediff` binary for long runs.
- `checkEqvP` for 16 one-fiber programs in one module: about 3-11 minutes (CPU shared).

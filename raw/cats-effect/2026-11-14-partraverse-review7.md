# parTraverseN: review 7 fixes (own notes, 2026-11-14)

- Scala 2.13 `immutable.Set`: `Set4.incl(new)` builds a `HashSet`; `HashSet.excl` returns a `HashSet` (it does not shrink back to `Set4`). Only `cancelAll` (`supervision.get.flatMap(_.toList.parTraverse_(...))`) and the final join read the iteration order.
- All fibers start during the traverse (the permit is taken inside the fiber), so the set reaches the input length, independent of `n`. Elements leave it only in the sequence phase.
- Model change: a `HashSet` is `.right (listV xs)`; `toList` is `ho xs`. `ho` is a parameter of `ParTraverse.call/dispatch/env`; the difftest uses `id`; the statements quantify over all `ho` with `(ho xs).Perm xs`. The `setLimitCode` stop and the `as.length ≤ 4` hypotheses are gone.
- New statements 5-7 use a behaviour table (namespace 43 harness): per input, `k` `IO.cede`s, then `pure`/`raiseError`/`canceled`/`never`. No user code, so no `WellFormed` hypothesis.
- Smoke harness gotchas: a `flatMap` continuation must return a program (`.prog`); a `.ret` there is `Abort.illTyped`. A `delay` thunk returns `.ret`.
- Wrong function "no cancelAll on error" only breaks the claim if the erroring input is not the first in the sequence phase: with `f(1)` raising first, `sequence` reads its result first and the traversal raises without `cancelAll`.
- Concurrency limit smoke: `f` counts running actions in `Ref` 0; the mirror's maximum stays `≤ n`; 1000 permits (override of `PT.k2`) exceed `n`.
- resultOrder: the reviewer found that `WellFormed` lets `f` capture the result `Deferred` through a number field of its closure id. Kept open; waits for track Res's fix (decision 56).

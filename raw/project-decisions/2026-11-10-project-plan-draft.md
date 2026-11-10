# Project plan draft (own note)

> Source: user request in a Claude Code session: "Make a detailed step by step plan how to do this whole thing"
> Collected: 2026-11-10
> Published: 2026-11-10

- The plan is synthesized from the existing wiki articles (lessons, agent workflow, differential testing, modeling approaches, bug history, source layout, semantics, toolchain). No new external sources.
- Phases: 0 research gaps (bug status on series/3.x, TestControl schedule replay, kernel-evaluation cost of counterexamples without native_decide, value representation, decisions) → 1 scaffolding (layout, inventory, registry audit) → 2 IOFiber model → 3 difftest → 4 kernel laws → 5 calibration on #4687/#4627/#4571 → 6 derived combinators + Resource → 7 std structures → 8 bug hunt → 9 optional runtime with memory model.
- New point not in earlier notes: refutations must be checked by the kernel (`decide`/`rfl`/`decide_cbv`) because `native_decide` is forbidden, so the cost of kernel evaluation of the model is a main risk and needs a spike before the model design is fixed.
- Status: draft, not approved by the user. Formalization has not started.

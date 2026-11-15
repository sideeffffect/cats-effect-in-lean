# Phase 6 gate passed (2026-11-15)

- Review batch 10 (`review/2026-11-15-review-batch-10.md`): gate PASS with three conditions, no blocker. 25 of 25 Phase 6 entries have FAITHFUL as the latest verdict (1 proven, 3 refuted, 21 open).
- Condition 1: CI run 43709916921 on `1dfe6ce` green (all 7 required checks). CI on `66cb621` green.
- Condition 2: reproducers re-run by track G (`66cb621`): CE-0005, CE-0020, CE-0030 print `REPRODUCED <id>` on v3.7.1 and series/3.x `de84c01`; fixed copies do not reproduce.
- Condition 3: `opcount.py --seeds 81 82 83 --n 20000 --ops rUse rAllocated rBoth --boost rUse=4 rAllocated=4 res_both=2 tpl_resBoth=4 tpl_resource=4 --lean "lake exe cediff"` on tree `c3bf1ec`: 60,000 cases, all agree, 0 unsupported; rUse 9,792, rAllocated 6,081, rBoth 3,060 agreeing. 715 s.
- Low items D1, D3, D4 fixed by track G in `21c5ace`.
- AGENTS.md: Phases 6–8 run without a user gate, so Phase 7 (std structures) starts now.

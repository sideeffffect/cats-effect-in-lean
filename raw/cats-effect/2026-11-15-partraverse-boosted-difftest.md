# parTraverseN: boosted difftest on the new model (track G, 2026-11-15)

Model state: HashSet ghost list `all`, order input `ho all xs`, `rankOrder` by index in `all` (fix of track S case g61-9094).

- `opcount.py --seeds 81 --n 30000 --ops parTraverseN --boost tpl_parTraverse=8 tpl_parTraverseCancel=8 --lean "lake exe cediff"`: 30,000 cases, all agree; parTraverseN 17,515 (2,151 s).
- Seed 82, same options: 30,000 agree; parTraverseN 17,541 (2,001 s).
- Seed 83, same options: 30,000 agree; parTraverseN 17,372 (2,017 s).
- Total: 90,000 cases, all agree; 52,428 agreeing cases use parTraverseN; no unsupported, no other bin.
- Earlier on the same day (Track S settings, seeds 61-63, 60,000 cases, all agree): parTraverseN 4,240.
- The 2 `unsupported` cases of `drive.py check` are `two-fibers-tc-seed1` and `two-fibers-tc-seed2` in `difftest/cases/basic.jsonl`: testcontrol-mode cases (decision 15: testcontrol is unsupported in the model), present since commit 6be4d02 (2026-11-10). Not new.

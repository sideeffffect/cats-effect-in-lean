# Track Q: fixes after review batch 11a

> Source: own Lean work and runs on the track Q branch after merging `origin/main` at `fc60284` (review batch 11a, tracks S and L merged); `review/2026-11-15-review-batch-11a.md`
> Collected: 2026-11-15
> Published: 2026-11-15 (own research note)

## Changes

- F1 `fifo`: events are `(tag, script index, value)`; `Fifo` holds for every remover (`removedBy`: script `i`, or the drain) and every producer; the hypothesis "at most one taking script" is gone. Wrong functions `wLastIfWaiters` / `wLastIfWaitersAsync` (take the last element when another taker waits): input `[[take, take], [take], [take], [offer 1, offer 2]]`, plan `[(1, 1)]`, FIFO schedule: consumer 0 removes `2` then `1`; the mirror meets the claim (kernel-checked, `boundedForConcurrent(2)` and `bounded(3)`).
- L1 `takerLiveness`: the count hypothesis is gone. The harness records `offerStart x` (tag 6) before `poll(offer(x))`. Claim: `Succeeded`, or `QuietBlock` (`blocked`, every recorded offered element removed, every started offer returned). Wrong functions `wNoPassOn` (no `cleanup`/`notifyNextTaker` pass-on) and `wNoAnywayU` (no `notifyAnyway`): `[[take], [take], [offer 1]]`, plan `[(1, 0)]`, join `[0, 1]`: `blocked` with element 1 still in the queue; the mirror ends `Succeeded` (kernel-checked).
- Witnesses re-proved (decision 53): safety runs with the new event format; liveness: the pass-on run (`Succeeded`, takes 2 > offers 1) and a `QuietBlock` run, both families.
- D1: `QC.getState` removed from `isPublic`. D2: `Unsafe*` `put`/`take`/`size` rows removed from the track Q entries; 8 excluded helper rows now `deferred: phase 9 (weak memory model)`. D3: queue template name base 40000. D4: `selftest.py` floor `V2Q_MIN = 3 %` for the six queue ops. D5: livelock note.

## Runs

- `opcount.py --seeds 81 82 83 --n 22000 --boost tpl_queue2=11` on the merged generator (tracks S and L templates present): 66,000 of 66,000 agree; 52,838 agreeing cases per queue op (81: 17,694; 82: 17,627; 83: 17,517).
- `qsmoke 600 20 11` (new claims, no count filter for liveness): 27,600 stopped runs, 0 violations. `qsmoke wrong`: all 15 wrong functions break their claims; the mirror meets each.

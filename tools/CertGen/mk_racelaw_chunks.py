import glob, os, math
base = 'CatsEffectInLean/Proofs/Phase6/'
ns = 'CatsEffectInLean.Proofs.Phase6.RaceLaw'
total = 4441
# extra GB per 100 states, measured per 500-state bucket (BFS certificate, 2026-11-10)
extra = [0.5, 2.1, 1.4, 2.3, 3.0, 3.3, 3.5, 4.8, 5.9]
target = 3.0
chunks = []
for b, e in enumerate(extra):
    lo, hi = b * 500, min(total, b * 500 + 500)
    size = min(250, int(100 * target / max(e, 1.3)))
    k = math.ceil((hi - lo) / size)
    step = math.ceil((hi - lo) / k)
    a = lo
    while a < hi:
        n = min(step, hi - a)
        chunks.append((a, n))
        a += n
assert sum(n for _, n in chunks) == total
per_mod = 5
mods = [chunks[i:i + per_mod] for i in range(0, len(chunks), per_mod)]

for f in glob.glob(base + 'RaceLawChunk*.lean'):
    os.remove(f)

defs = f"""import CatsEffectInLean.Proofs.Lemmas.CertP
import CatsEffectInLean.Props.Phase6.Race
import CatsEffectInLean.Proofs.Phase6.RaceLawCertLhs
import CatsEffectInLean.Proofs.Phase6.RaceLawCertRhs

/-! Definitions for `Proofs/Phase6/RaceLaw.lean`: the decoded certificates and the only
observation of both sides of `uncancelableRaceNotInherited`. -/

namespace {ns}

open CatsEffectInLean.Model
open CatsEffectInLean.Proofs.Lemmas.CertP

/-- The only observation of both sides: blocked, no emit, no `Ref`, no report. -/
def blockedEmpty : Obs := {{ summary := .blocked, out := [], refs := [], reports := [] }}

def lhsInstrs : List (Option PChoice) := RaceLawCertLhs.instrs.map decodeInstr
def rhsInstrs : List (Option PChoice) := RaceLawCertRhs.instrs.map decodeInstr

end {ns}
"""
open(base + 'RaceLawDefs.lean', 'w').write(defs)

idx = 0
for mi, mod in enumerate(mods):
    prev = 'CatsEffectInLean.Proofs.Phase6.RaceLawDefs' if mi == 0 else f'CatsEffectInLean.Proofs.Phase6.RaceLawChunks{mi-1}'
    thms = ""
    for (a, n) in mod:
        thms += f"""set_option maxHeartbeats 0 in
theorem lhs_chunk_{idx} :
    certChunk {{}} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      {a} {n} = true := by
  decide +kernel

"""
        idx += 1
    lo = mod[0][0]
    hi = mod[-1][0] + mod[-1][1] - 1
    src = f"""import {prev}

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states {lo} to {hi}
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace {ns}

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

{thms}end {ns}
"""
    open(base + f'RaceLawChunks{mi}.lean', 'w').write(src)

chain = "edgesUpTo_zero _ _ _ lhs_chunk_0"
for i in range(len(chunks)):
    chain = f"edgesUpTo_chunk _ _ _ ({chain}) lhs_chunk_{i}"

main = f"""import CatsEffectInLean.Proofs.Phase6.RaceLawChunks{len(mods)-1}

/-!
# `GenSpawnLaws.uncancelableRaceNotInherited` for `IO` (Phase 6, track P)

`F.uncancelable(_ => F.race(F.never[Unit], F.canceled)).void <-> F.never[Unit]`
(`laws/shared/src/main/scala/cats/effect/laws/GenSpawnLaws.scala:121-122`), `<->` = `EqvP`.

Proof by certificates (`Proofs/Lemmas/CertP.lean`): the left side has exactly 4,441 states
(closed under `preempt` and every `pick`), the right side 45. On both sides every state with an
observation has the observation `blockedEmpty` (the run stops with no ready task; no emit, no
`Ref`, no report), and some state has it. So both outcome sets are `{{blockedEmpty}}`.

The certificates (`RaceLawCertLhs`, `RaceLawCertRhs`) come from the untrusted generator
`tools/CertGen/RaceLaw.lean`. The kernel checks them with `decide +kernel`. The edges of the
left side are checked in {len(chunks)} chunks (`RaceLawChunks0` .. `RaceLawChunks{len(mods)-1}`).
-/

namespace {ns}

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

theorem rhs_exact :
    certExact {{}} counterMaskModel lawEnv Timeout.neverIO rhsInstrs RaceLawCertRhs.succ = true := by
  decide +kernel

theorem rhs_obs :
    certObsOnly {{}} counterMaskModel lawEnv Timeout.neverIO rhsInstrs blockedEmpty = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_obs :
    certObsOnly {{}} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs blockedEmpty = true := by
  decide +kernel

theorem lhs_succ_length : RaceLawCertLhs.succ.length ≤ {total} := by decide +kernel

theorem lhs_exact :
    certExact {{}} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ =
      true :=
  certExact_of_edgesUpTo _ _ _
    ({chain})
    lhs_succ_length

theorem uncancelableRaceNotInherited_proven : uncancelableRaceNotInherited := by
  intro o
  rw [outcomesP_iff_of_certObsOnly _ _ _ lhs_exact lhs_obs,
    outcomesP_iff_of_certObsOnly _ _ _ rhs_exact rhs_obs]

end {ns}
"""
open(base + 'RaceLaw.lean', 'w').write(main)
print(len(chunks), "chunks in", len(mods), "modules")
print(chunks)

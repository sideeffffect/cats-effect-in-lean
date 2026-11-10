#!/usr/bin/env python3
"""Kernel-evaluation benchmark driver (Phase 0 step 3 spike).

Each case is one Lean file with one theorem, run with
`/usr/bin/time` + `lake env lean -M8000`. Prints one TSV line per case.

usage: python3 bench.py OUTDIR GROUP [GROUP ...]
GROUP: base | run | runcbv | enum | enumcut | enum4 | witness | repr
"""
from __future__ import annotations

import concurrent.futures as cf
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAKE = str(Path.home() / ".elan/bin/lake")
TIMEOUT = int(os.environ.get("TMO", "120"))
JOBS = int(os.environ.get("JOBS", "3"))

HEADER = "import KernelEval\nopen KernelEval\nset_option maxRecDepth 100000\nset_option cbv.maxSteps 100000000\n"


def run_case(outdir: Path, name: str, body: str) -> str:
    f = outdir / f"{name}.lean"
    f.write_text(HEADER + body + "\n")
    cmd = ["timeout", str(TIMEOUT), "/usr/bin/time", "-f", "TIME %e MAXRSS %M",
           LAKE, "env", "lean", "-M8000", "-DmaxHeartbeats=0", str(f)]
    p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    out = p.stdout + p.stderr
    m = re.search(r"TIME ([\d.]+) MAXRSS (\d+)", out)
    if p.returncode == 124 or (m is None and "Command terminated" not in out):
        status = f"TIMEOUT>{TIMEOUT}s"
        t, rss = "-", "-"
    else:
        t = m.group(1) if m else "-"
        rss = f"{int(m.group(2)) // 1024}" if m else "-"
        errs = [l for l in out.splitlines() if "error" in l.lower()]
        status = "OK" if p.returncode == 0 and not errs else "FAIL: " + (errs[0][:140] if errs else out[-140:])
    axioms = re.findall(r"depends on axioms: \[([^\]]*)\]|does not depend on any axioms", out)
    ax = "none" if "does not depend on any axioms" in out else (axioms[0] if axioms else "")
    return f"{name}\t{t}\t{rss}\t{status}\t{ax}"


def thm(name: str, stmt: str, tac: str) -> str:
    return f"theorem {name} : {stmt} := by {tac}\n#print axioms {name}\n"


TACS = {"decide": "decide", "kernel": "decide +kernel", "rfl": "rfl", "cbv": "decide_cbv"}

# (fibers, program builder, n) -> steps to finish, final Ref; computed by #eval in a pre-pass.
RUN_CASES = [(2, "twoChains", n) for n in (2, 3, 8, 16, 32, 64, 200, 400)] + \
            [(3, "threeChains", n) for n in (5, 10, 20, 40, 300)]


def prepass(outdir: Path) -> dict:
    lines = []
    for k, prog, n in RUN_CASES:
        lines.append(
            f"#eval (List.range 8000).find? (fun f => (summary (run code false f (roundRobin {k} f) "
            f"(init ({prog} {n})))).isSome) |>.map (fun f => (f, summary (run code false f (roundRobin {k} f) (init ({prog} {n})))))")
    f = outdir / "prepass.lean"
    f.write_text(HEADER + "\n".join(lines) + "\n")
    p = subprocess.run([LAKE, "env", "lean", str(f)], cwd=HERE, capture_output=True, text=True)
    res = {}
    for (k, prog, n), line in zip(RUN_CASES, [l for l in p.stdout.splitlines() if l.startswith("some")]):
        m = re.match(r"some \((\d+), some \(KernelEval\.Val\.nat (\d+)\)\)", line)
        res[(k, prog, n)] = (int(m.group(1)), int(m.group(2)))
    return res


def cases(group: str, outdir: Path) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    if group == "base":
        out.append(("base_import_only", ""))
    if group in ("run", "runcbv"):
        pre = prepass(outdir)
        tacs = ["cbv"] if group == "runcbv" else ["decide", "kernel", "rfl"]
        for (k, prog, n), (steps, val) in pre.items():
            stmt = f"summary (run code false {steps} (roundRobin {k} {steps}) (init ({prog} {n}))) = some (.nat {val})"
            for t in tacs:
                out.append((f"run_{k}f_{steps}steps_{t}", thm(f"t_{t}", stmt, TACS[t])))
    if group in ("enum", "enumcut", "enum4"):
        fn = "forallSchedCut" if group == "enumcut" else "forallSched"
        cs = "choices2" if group == "enum4" else "choices2NoObs"
        depths = (4, 6, 8, 10) if group == "enum4" else (8, 10, 12, 14, 16, 18, 20)
        for d in depths:
            stmt = f"{fn} code false {cs} atMostOnce {d} (init (cancelProg 4)) = true"
            for t in ("kernel", "decide", "cbv"):
                out.append((f"{group}_{cs}_d{d}_{t}", thm(f"t_{t}", stmt, TACS[t])))
    if group == "cbvscale":
        for cs, depths in (("choices2NoObs", (60, 100)), ("choices2", (30, 60)),
                           ("choices3NoObs", (20, 30, 40, 60))):
            prog = "threeChains 3" if cs == "choices3NoObs" else "cancelProg 4"
            prop = "(fun s => decide (finRuns s ≤ 9))" if cs == "choices3NoObs" else "atMostOnce"
            for d in depths:
                stmt = f"forallSched code false {cs} {prop} {d} (init ({prog})) = true"
                out.append((f"cbvscale_{cs}_d{d}", thm("t_cbv", stmt, TACS["cbv"])))
    if group == "levels":
        for cs, depths in (("choices2NoObs", (16, 30, 60)), ("choices2", (8, 16, 30, 60)),
                           ("choices3NoObs", (12, 30))):
            prog = "threeChains 3" if cs == "choices3NoObs" else "cancelProg 4"
            prop = "(fun s => decide (finRuns s ≤ 9))" if cs == "choices3NoObs" else "atMostOnce"
            for d in depths:
                stmt = f"forallLevels code false {cs} {prop} {d} [init ({prog})] = true"
                for t in ("kernel", "cbv"):
                    out.append((f"levels_{cs}_d{d}_{t}", thm(f"t_{t}", stmt, TACS[t])))
    if group == "witness":
        stmt = "∃ cs : List Choice, finRuns (exec code true cs (init (cancelProg 4))) = 2"
        for t in ("decide", "kernel", "rfl", "cbv"):
            tac = TACS[t]
            out.append((f"witness_given_{t}", f"theorem w : {stmt} := ⟨doubleFinSched, by {tac}⟩\n#print axioms w\n"))
        for d in (15, 16):
            s2 = f"(findSched code true choices2 (fun s => decide (finRuns s ≥ 2)) {d} (init (cancelProg 4))).isSome = true"
            for t in ("kernel", "cbv"):
                out.append((f"witness_search_d{d}_{t}", thm("w", s2, TACS[t])))
    return out


def main() -> None:
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    allc = [c for g in sys.argv[2:] for c in cases(g, outdir)]
    print("case\ttime_s\tmaxrss_MB\tstatus\taxioms", flush=True)
    with cf.ThreadPoolExecutor(JOBS) as ex:
        futs = {ex.submit(run_case, outdir, n, b): n for n, b in allc}
        for fu in cf.as_completed(futs):
            print(fu.result(), flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# Compares O3 CPU simulation of the Protea-generated RISC-V ISA with the
# native gem5 RISC-V ISA on the same programs.
#
# Programs: rv32ui/rv32um tests from riscv-tests (built with the SE
# environment in riscv-tests-env/) and the C benchmarks in bench/.
# Each program runs on the O3 CPU in both gem5 builds; the script checks that
# both exit with 0 and commit the same number of instructions, and compares
# timing statistics (cycles, branch mispredictions, store-to-load forwarding).
# It also reports which statistics of stats.txt differ at all (host statistics
# such as simulation speed are ignored).
#
# Usage: gem5/tests/compare_o3.py <gem5 repo root> <riscv-tests root>
#            [--protea build/RISCV/gem5.opt] [--native build/RISCV_NATIVE/gem5.opt]
#            [--no-caches] [--tolerance PERCENT]
# Exits with 1 if a program fails, the committed instruction counts differ,
# or the cycle count differs by more than the tolerance.

import argparse
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TESTS = Path(__file__).resolve().parent
CC = ["riscv64-unknown-elf-gcc", "-march=rv32im_zifencei", "-mabi=ilp32",
      "-nostdlib", "-static", "-mno-relax", "-Wl,-Ttext=0x10000"]

STATS = {
    "insts": "simInsts",
    "cycles": "system.cpu.numCycles",
    "mispred": "system.cpu.commit.branchMispredicts",
    "fwd": "system.cpu.lsq0.forwLoads",
    "violations": "system.cpu.iew.memOrderViolationEvents",
}


def build(rvt: Path, out: Path) -> dict:
    """name -> binary path."""
    progs = {}
    for suite in ("rv32ui", "rv32um"):
        for src in sorted((rvt / "isa" / suite).glob("*.S")):
            if src.stem == "fence_i":  # fence.i is not in the ISA
                continue
            name = f"{suite}/{src.stem}"
            binary = out / name.replace("/", "-")
            subprocess.run(CC + ["-I", str(TESTS / "riscv-tests-env"),
                                 "-I", str(rvt / "isa/macros/scalar"),
                                 str(src), "-o", str(binary)], check=True)
            progs[name] = binary
    for src in sorted((TESTS / "bench").glob("*.c")):
        name = f"bench/{src.stem}"
        binary = out / name.replace("/", "-")
        subprocess.run(CC + ["-O2", "-ffreestanding", "-fno-builtin",
                             str(TESTS / "bench/start.S"), str(src),
                             "-o", str(binary)], check=True)
        progs[name] = binary
    return progs


def run(gem5_bin: Path, binary: Path, outdir: Path, caches: bool) -> dict:
    cmd = [str(gem5_bin), f"--outdir={outdir}", str(TESTS / "se_rv32.py"),
           "o3", str(binary)] + (["--caches"] if caches else [])
    res = subprocess.run(cmd, capture_output=True, text=True)
    m = re.search(r"^EXIT: .* (\d+)$", res.stdout, re.M)
    result = {"exit": int(m.group(1)) if m else None}
    stats = outdir / "stats.txt"
    text = stats.read_text() if stats.exists() else ""
    result["all"] = {m.group(1): m.group(2) for m in
                     re.finditer(r"^(\S+)\s+(\S+)", text, re.M)
                     if not m.group(1).startswith(("host", "---"))}
    for key, stat in STATS.items():
        m = re.search(rf"^{re.escape(stat)}\s+(\d+)", text, re.M)
        result[key] = int(m.group(1)) if m else 0
    return result


def pct(a: int, b: int) -> float:
    return 0.0 if a == b else 100.0 * (a - b) / b if b else float("inf")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("gem5", type=Path)
    ap.add_argument("riscv_tests", type=Path)
    ap.add_argument("--protea", type=Path, default=Path("build/RISCV/gem5.opt"))
    ap.add_argument("--native", type=Path, default=Path("build/RISCV_NATIVE/gem5.opt"))
    ap.add_argument("--no-caches", action="store_true")
    ap.add_argument("--tolerance", type=float, default=5.0,
                    help="allowed cycle count difference, percent (default 5)")
    args = ap.parse_args()
    gem5 = args.gem5.resolve()
    bins = {"protea": gem5 / args.protea, "native": gem5 / args.native}
    caches = not args.no_caches

    out = Path(os.environ.get("TMPDIR", tempfile.gettempdir())) / "protea-o3-compare"
    out.mkdir(parents=True, exist_ok=True)
    progs = build(args.riscv_tests.resolve(), out)

    jobs = {}
    with ThreadPoolExecutor(max_workers=os.cpu_count()) as pool:
        for name, binary in progs.items():
            for side, gem5_bin in bins.items():
                outdir = out / f"m5out-{side}-{name.replace('/', '-')}"
                jobs[name, side] = pool.submit(run, gem5_bin, binary, outdir, caches)
    res = {key: job.result() for key, job in jobs.items()}

    print(f"O3, {'with' if caches else 'without'} L1 caches; values are protea / native\n")
    print(f"{'program':16} {'insts':>8} {'cycles':>17} {'diff':>7} "
          f"{'mispredicts':>13} {'fwd loads':>11}")
    failed, timing, diffs, stat_diffs = [], [], [], {}
    for name in progs:
        p, n = res[name, "protea"], res[name, "native"]
        d = pct(p["cycles"], n["cycles"])
        diffs.append(abs(d))
        print(f"{name:16} {p['insts']:>8} {p['cycles']:>8}/{n['cycles']:<8} {d:>+6.1f}% "
              f"{p['mispred']:>6}/{n['mispred']:<6} {p['fwd']:>5}/{n['fwd']:<5}")
        names = sorted(k for k in p["all"].keys() | n["all"].keys()
                       if p["all"].get(k) != n["all"].get(k))
        if names:
            stat_diffs[name] = names
        if p["exit"] != 0 or n["exit"] != 0:
            failed.append(f"{name}: exit protea={p['exit']} native={n['exit']}")
        elif p["insts"] != n["insts"]:
            failed.append(f"{name}: committed instructions protea={p['insts']} "
                          f"native={n['insts']}")
        elif abs(d) > args.tolerance:
            timing.append(f"{name}: cycles differ by {d:+.1f}%")

    print(f"\nSummary: {len(progs)} programs, cycle difference "
          f"mean {sum(diffs) / len(diffs):.2f}%, max {max(diffs):.2f}%")
    print(f"stats.txt identical in {len(progs) - len(stat_diffs)} of {len(progs)} programs")
    for name, names in stat_diffs.items():
        print(f"  {name}: {', '.join(names[:5])}" + (" ..." if len(names) > 5 else ""))
    for line in failed + timing:
        print("  " + line)
    if failed or timing:
        print(f"{len(failed)} functional and {len(timing)} timing mismatches "
              f"(tolerance {args.tolerance}%)")
        return 1
    print(f"all programs pass, commit the same instructions and are within "
          f"{args.tolerance}% in cycles")
    return 0


if __name__ == "__main__":
    sys.exit(main())

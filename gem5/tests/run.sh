#!/bin/sh
# Builds gem5/tests/check.S and runs it on every gem5 CPU model.
# Usage: gem5/tests/run.sh <gem5 repo root>
# Each run must print "EXIT: ... 0"; a nonzero code is the failed check number.
set -e

GEM5=${1:?usage: $0 <gem5 repo root>}
TESTS=$(cd "$(dirname "$0")" && pwd)
OUT=${TMPDIR:-/tmp}/protea-gem5-tests

mkdir -p "$OUT"
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -static \
    -Wl,-Ttext=0x10000 "$TESTS/check.S" -o "$OUT/check"

for cpu in atomic timing minor o3; do
    printf '%-7s ' "$cpu"
    "$GEM5/build/RISCV/gem5.opt" --outdir="$OUT/m5out-$cpu" \
        "$TESTS/se_rv32.py" "$cpu" "$OUT/check" 2>&1 | grep -E "EXIT|panic|fatal"
done

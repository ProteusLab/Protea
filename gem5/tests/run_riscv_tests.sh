#!/bin/sh
# Builds rv32ui/rv32um tests from riscv-tests with the SE environment in
# riscv-tests-env/ and runs each of them on every gem5 CPU model.
# Usage: gem5/tests/run_riscv_tests.sh <gem5 repo root> <riscv-tests root> [test...]
# Prints a table of exit codes: 0 is a pass, N is the number of a failed test case,
# then a summary of the failed tests. Exits with 1 if any test failed.
set -e

GEM5=${1:?usage: $0 <gem5 repo root> <riscv-tests root> [test...]}
RVT=${2:?usage: $0 <gem5 repo root> <riscv-tests root> [test...]}
shift 2
TESTS=$(cd "$(dirname "$0")" && pwd)
OUT=${TMPDIR:-/tmp}/protea-riscv-tests
CPUS="atomic timing minor o3"

mkdir -p "$OUT"
if [ $# -eq 0 ]; then
    set -- $(cd "$RVT/isa" && ls rv32ui/*.S rv32um/*.S | sed 's/\.S$//')
fi

for t in "$@"; do
    # A stale binary from a previous run must not hide a build failure.
    rm -f "$OUT/$(echo "$t" | tr / -)"
    riscv64-unknown-elf-gcc -march=rv32im_zifencei -mabi=ilp32 -nostdlib -static -mno-relax \
        -Wl,-Ttext=0x10000 -I "$TESTS/riscv-tests-env" \
        -I "$RVT/isa/macros/scalar" "$RVT/isa/$t.S" \
        -o "$OUT/$(echo "$t" | tr / -)" 2> "$OUT/$(echo "$t" | tr / -).build.log" \
        || echo "$t: build failed, see $OUT/$(echo "$t" | tr / -).build.log"
done

failed=""
printf '%-16s' test; for cpu in $CPUS; do printf '%-8s' "$cpu"; done; echo
for t in "$@"; do
    name=$(echo "$t" | tr / -)
    bin="$OUT/$name"
    printf '%-16s' "$t"
    fails=""
    for cpu in $CPUS; do
        if [ ! -f "$bin" ]; then
            code=build
        else
            log="$OUT/$name.$cpu.log"
            # The subshell keeps the shell's "Abort trap" notice for a gem5
            # panic in the log instead of the terminal.
            ("$GEM5/build/RISCV/gem5.opt" --outdir="$OUT/m5out-$cpu" \
                "$TESTS/se_rv32.py" "$cpu" "$bin" || exit $?) > "$log" 2>&1 || true
            code=$(sed -n 's/^EXIT: .* \([0-9][0-9]*\)$/\1/p' "$log")
            if [ -z "$code" ]; then
                code=$(grep -qE "panic|fatal" "$log" && echo crash || echo "?")
            fi
        fi
        printf '%-8s' "$code"
        [ "$code" = 0 ] || fails="$fails $cpu=$code"
    done
    echo
    [ -z "$fails" ] || failed="$failed
$t:$fails"
done

total=$#
nfailed=$(printf '%s' "$failed" | grep -c . || true)
echo
if [ "$nfailed" -eq 0 ]; then
    echo "Summary: all $total tests passed"
    exit 0
fi
echo "Summary: $nfailed of $total tests failed (code: failed case number, crash, build, ?)"
printf '%s\n' "$failed" | sed '/^$/d; s/^/  /'
echo "gem5 logs: $OUT/<test>.<cpu>.log"
exit 1

#!/bin/bash

if [ $# -lt 6 ]; then
    echo "Usage: $0 <src_dir> <bin_dir> <compiler> <qemu> <qemu-log-dir> <compiler_flags>"
    exit 1
fi

SRC_DIR="$1"
BIN_DIR="$2"
COMPILER="$3"
QEMU="$4"
QEMU_LOG_DIR="$5"
COMPILER_FLAGS="$6"

# Compile each .s file
for s_file in "$SRC_DIR"/*.s; do
    if [ -f "$s_file" ]; then
        base=$(basename "$s_file" .s)
        out_file="$BIN_DIR/$base.elf"
        echo "Compiling $s_file -> $out_file"
        $COMPILER $COMPILER_FLAGS "$s_file" -o "$out_file"
        if [ $? -ne 0 ]; then
            echo "Compilation failed for $s_file"
            exit 1
        fi
    fi
done

# Run QEMU on each compiled binary
for bin_file in "$BIN_DIR"/*.elf; do
    if [ -f "$bin_file" ]; then
        echo "Running QEMU on $bin_file"
        base_name="${bin_file##*/}"
        base_name="${base_name%.elf}"
        $QEMU -D "$QEMU_LOG_DIR/$base_name.log" -d cpu "$bin_file"
        if [ $? -ne 0 ]; then
            echo "QEMU failed on $bin_file"
            exit 1
        fi
    fi
done

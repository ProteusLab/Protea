#!/bin/bash

if [ $# -ne 4 ]; then
    echo "Usage: $0 <src_dir> <bin_dir> <compiler> <compiler_flags>"
    exit 1
fi

SRC_DIR="$1"
BIN_DIR="$2"
COMPILER="$3"
COMPILER_FLAGS="$4"

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

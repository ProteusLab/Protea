#!/usr/bin/env python3
"""Smoke-test: read lira.yaml, generate base_ops.h + snippets.h + exec funcs.

Usage:
    python3 gen_py/main.py --lira lira.yaml --output out/
"""
import argparse
from pathlib import Path

from lira import read_arch
from base_ops_gen import generate_base_ops
from snippets_gen import generate_snippets
from cpp_gen import Translator, OpRegistry
import target.rv32i.cpp_ops  # noqa: F401  — RISC-V overrides


def main():
    ap = argparse.ArgumentParser(description="C++ LIRA-based smoke-test codegen")
    ap.add_argument("--ir-path", required=True, type=Path, help="Path to lira.yaml")
    ap.add_argument("--output", type=Path, default=Path("."),
                    help="Output directory (default: .)")
    args = ap.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)

    arch = read_arch(args.ir_path)

    ops_map = {o.name: o for o in arch.operations}

    base_h = generate_base_ops(arch.operations)
    (args.output / "base_ops.h").write_text(base_h)

    OpRegistry.set_ops(ops_map)

    snips_h = generate_snippets(arch.snippets, ops_map)
    (args.output / "snippets.h").write_text(snips_h)

    funcs = []
    for insn in arch.instructions:
        t = Translator(insn.semantic, context="execute", indent=2)
        body = t.translate()
        name = f"do{insn.name.upper()}"
        funcs.append(
            f"void {name}(CPU &cpu, const Instruction &insn) {{\n"
            f"{body}\n"
            f"}}"
        )
    (args.output / "exec_funcs.cc").write_text("\n\n".join(funcs))

if __name__ == "__main__":
    main()

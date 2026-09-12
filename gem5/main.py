#!/usr/bin/env python3

import argparse
from pathlib import Path

from driver import Driver


def main() -> None:
    ap = argparse.ArgumentParser(description="Gem5 ISA DSL code generator")
    ap.add_argument("--ir-path", required=True, type=Path, help="Path to lira.yaml")
    args = ap.parse_args()

    Driver(args.ir_path).write_artifacts()


if __name__ == "__main__":
    main()

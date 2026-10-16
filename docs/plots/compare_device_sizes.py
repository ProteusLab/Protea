#!/usr/bin/env python3
"""Measure device source lengths and render the comparison (matplotlib, pygments)."""

import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator
from pygments import lex
from pygments.lexers import CppLexer, RubyLexer
from pygments.token import Comment


DEVICES = [
    ("CLINT", "clint", "riscv/clint"),
    ("UART8250", "uart8250", "serial/uart8250"),
    ("PLIC", "plic", "riscv/plic"),
    ("VirtIO MMIO", "vio_mmio", "riscv/vio_mmio"),
    ("i8042", "i8042", "x86/i8042"),
    ("i82094AA", "i82094aa", "x86/i82094aa"),
    ("i8237", "i8237", "x86/i8237"),
    ("i8254", "i8254", "x86/i8254"),
    ("i8259", "i8259", "x86/i8259"),
]


def measure(path, language, root):
    raw = path.read_bytes()
    source = raw.decode("utf-8")
    lexer = language(stripnl=False, ensurenl=False)
    # Keep preprocessor directives: Pygments classifies them under Comment.
    filtered = "".join(
        "".join("\n" if char == "\n" else " " for char in value)
        if token in Comment and token not in Comment.Preproc
        else value
        for token, value in lex(source, lexer)
    )
    return {
        "path": str(path.relative_to(root)),
        "code_lines": sum(bool(line.strip()) for line in filtered.splitlines()),
        "physical_lines": len(source.splitlines()),
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def render(rows, output):
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 18,
        "text.color": "black", "axes.labelcolor": "black",
        "xtick.color": "black", "ytick.color": "black",
    })
    fig, ax = plt.subplots(figsize=(16, 5.25))
    fig.subplots_adjust(left=0.07, right=0.99, top=0.88, bottom=0.27)
    rows = sorted(rows, key=lambda row: row["gem5_code_lines"], reverse=True)
    positions = list(range(len(rows)))
    width = 0.4
    plod_bars = ax.bar(
        [position - width / 2 for position in positions],
        [row["plod_code_lines"] for row in rows], width,
        color="#66C2A5", label="PLOD",
    )
    gem5_bars = ax.bar(
        [position + width / 2 for position in positions],
        [row["gem5_code_lines"] for row in rows], width,
        color="#FC8D62", label="gem5 (baseline)",
    )
    for bars in (plod_bars, gem5_bars):
        ax.bar_label(bars, padding=4, fontsize=15, color="black")
    for position, row in zip(positions, rows):
        ax.annotate(
            f"{row['plod_change_percent']:+.1f}%",
            (position, max(row["gem5_code_lines"], row["plod_code_lines"])),
            xytext=(0, 32), textcoords="offset points",
            ha="center", va="bottom", fontsize=16, fontweight="bold",
            color="black",
        )
    ax.set_xticks(positions, [row["device"] for row in rows],
                  rotation=40, ha="right", fontsize=16)
    maximum = max(max(row["gem5_code_lines"], row["plod_code_lines"]) for row in rows)
    ax.set_ylim(0, maximum * 1.25)
    ax.yaxis.set_major_locator(MultipleLocator(100 if maximum < 1000 else 200))
    ax.set_ylabel("Lines of code")
    ax.set_title("Device description code size", loc="left", fontsize=22,
                 fontweight="bold", pad=10)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#E6EAED", linewidth=1)
    ax.tick_params(axis="both", colors="black")
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color("#C5CDD3")
    ax.legend(loc="upper right", frameon=False, fontsize=17)
    for extension in ("png", "svg", "pdf"):
        path = output / f"device_code_size.{extension}"
        fig.savefig(path, dpi=128, facecolor="white")
        if extension == "svg":
            path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    repo = Path(__file__).resolve().parents[2]
    parser.add_argument("--gem5-root", type=Path, default=repo.parent / "gem5")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    gem5_root = args.gem5_root.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows, inputs = [], []
    for name, ruby_name, gem5_name in DEVICES:
        ruby = measure(repo / "lib/Devices" / f"{ruby_name}.rb", RubyLexer, repo)
        native = [] if gem5_name is None else [
            measure(gem5_root / "src/dev" / f"{gem5_name}.{ext}", CppLexer, gem5_root)
            for ext in ("cc", "hh")
        ]
        native_lines = sum(item["code_lines"] for item in native) if native else None
        rows.append({
            "device": name,
            "gem5_code_lines": native_lines,
            "plod_code_lines": ruby["code_lines"],
            "plod_change_percent": round(100 * (ruby["code_lines"] / native_lines - 1), 2)
                if native_lines else None,
            "gem5_physical_lines": sum(item["physical_lines"] for item in native) if native else None,
            "plod_physical_lines": ruby["physical_lines"],
            "gem5_bytes": sum(item["bytes"] for item in native) if native else None,
            "plod_bytes": ruby["bytes"],
        })
        inputs.append({"device": name, "gem5": native, "plod": ruby})
    with (output / "device_code_size.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    revision = subprocess.check_output(
        ["git", "-C", str(gem5_root), "rev-parse", "HEAD"], text=True
    ).strip()
    (output / "device_code_size_inputs.json").write_text(json.dumps({
        "gem5_revision": revision,
        "metric": "Physical lines with non-comment, non-whitespace content; preprocessor directives included",
        "inputs": inputs,
    }, indent=2) + "\n")
    render(rows, output)
    for row in rows:
        print(f"{row['device']:12} gem5={str(row['gem5_code_lines']):>4}  "
              f"PLOD={row['plod_code_lines']:>4}  change={row['plod_change_percent']}")


if __name__ == "__main__":
    main()

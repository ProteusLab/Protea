# gen_py/snippets_gen.py — generate ``snippets.h`` from LIRA snippets.

from typing import List

from lira.arch import Snippet

from cpp_gen import Translator
from cpp_gen import OpRegistry


HEADER = """\
#ifndef GENERATED_SNIPPETS_H
#define GENERATED_SNIPPETS_H

#include <stdint.h>
#include "base_ops.h"

"""

FOOTER = "#endif /* GENERATED_SNIPPETS_H */\n"


def _generate_function(name: str, seq) -> str:
    translator = Translator(seq, context="snippet", indent=2)
    body = translator.translate()
    return (
        f"static inline uint32_t {name}(uint32_t raw_insn) {{\n"
        f"{body}\n"
        f"}}"
    )


def generate_snippets(snippets: List[Snippet], ops: dict) -> str:
    OpRegistry.set_ops(ops)
    funcs = [
        _generate_function(s.name, s.seq)
        for s in snippets
    ]
    return HEADER + "\n\n".join(funcs) + "\n\n" + FOOTER

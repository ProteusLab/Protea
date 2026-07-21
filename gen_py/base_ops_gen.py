# gen_py/base_ops_gen.py — generate ``base_ops.h`` from LIRA operations.

from io import StringIO
from typing import List

from lira.arch import Operation

from cpp_ops import to_cpp


HEADER = """\
#ifndef LIRA_STD_OPS_H
#define LIRA_STD_OPS_H

#include <stdint.h>

#ifdef __SIZEOF_INT128__
typedef unsigned __int128 uint128_t;
typedef __int128 int128_t;
#endif

"""

FOOTER = "#endif /* LIRA_STD_OPS_H */\n"


def generate_base_ops(operations: List[Operation]) -> str:
    buf = StringIO()
    buf.write(HEADER)
    for op in sorted(operations, key=lambda o: o.name):
        buf.write(to_cpp(op))
        buf.write("\n\n")
    buf.write(FOOTER)
    return buf.getvalue()

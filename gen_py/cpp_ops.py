# gen_py/cpp_ops.py.

from typing import List

from lira.ir_ops import BaseOp
from lira.arch import Operation


_STANDARD_WIDTHS = [1, 8, 16, 32, 64, 128]


def gen_type(width: int, signed: bool = False) -> str:
    rounded = next(s for s in _STANDARD_WIDTHS if s >= width)
    if rounded == 1:
        return "bool"
    prefix = "" if signed else "u"
    return f"{prefix}int{rounded}_t"


def _signed_cmp(op: Operation, token: str) -> str:
    t = gen_type(op.inputs[0], signed=True)
    return f"return (({t})a {token} ({t})b) ? 1 : 0;"


def _asr_body(op: Operation) -> str:
    t = gen_type(op.inputs[0])
    ts = gen_type(op.inputs[0], signed=True)
    return f"return ({t})(({ts})a >> b);"


def _div_s_body(op: Operation) -> str:
    t = gen_type(op.inputs[0])
    ts = gen_type(op.inputs[0], signed=True)
    return f"return (b == 0) ? c : ({t})(({ts})a / ({ts})b);"


def _extend_sign_body(op: Operation) -> str:
    if op.inputs[0] == 1:
        return "return a;"
    t = gen_type(op.outputs[0])
    iw = op.inputs[0]
    return (
        f"{t} val = a & ((({t})1 << {iw}) - 1);\n"
        f"{t} sign = (val >> ({iw} - 1)) & 1;\n"
        "if (sign)\n"
        f"  return val | (~((({t})1 << {iw}) - 1));\n"
        "else\n"
        "  return val;"
    )


def _extend_zero_body(op: Operation) -> str:
    t = gen_type(op.outputs[0])
    return f"return a & ((({t})1 << {op.inputs[0]}) - 1);"


def _extract_low_body(op: Operation) -> str:
    t = gen_type(op.inputs[0])
    return f"return a & ((({t})1 << {op.outputs[0]}) - 1);"


def _popcnt_body(op: Operation) -> str:
    w = op.inputs[0]
    if w == 8:
        return "unsigned cnt = 0;\nwhile (a) { cnt += a & 1; a >>= 1; }\nreturn cnt;"
    if w == 16:
        return "return popcnt_8(a & 0xFF) + popcnt_8((a >> 8) & 0xFF);"
    if w == 32:
        return "return popcnt_16(a & 0xFFFF) + popcnt_16((a >> 16) & 0xFFFF);"
    if w == 64:
        return "return popcnt_32(a & 0xFFFFFFFF) + popcnt_32((a >> 32) & 0xFFFFFFFF);"
    if w == 128:
        return "return popcnt_64((uint64_t)a) + popcnt_64((uint64_t)(a >> 64));"
    raise ValueError(f"Unsupported popcnt size: {w}")


def _ctz_body(op: Operation) -> str:
    w = op.inputs[0]
    if w == 128:
        return (
            "if (a == 0) return 128;\n"
            "uint64_t lo = (uint64_t)a;\n"
            "if (lo) return ctz_64(lo);\n"
            "else return 64 + ctz_64((uint64_t)(a >> 64));"
        )
    return (
        f"if (a == 0) return {w};\n"
        "unsigned n = 0;\n"
        "while ((a & 1) == 0) { a >>= 1; n++; }\n"
        "return n;"
    )


def _clz_body(op: Operation) -> str:
    w = op.inputs[0]
    if w == 128:
        return (
            "if (a == 0) return 128;\n"
            "uint64_t hi = (uint64_t)(a >> 64);\n"
            "if (hi) return clz_64(hi);\n"
            "else return 64 + clz_64((uint64_t)a);"
        )
    mask = {8: "0x80", 16: "0x8000", 32: "0x80000000",
            64: "0x8000000000000000ULL"}[w]
    return (
        f"if (a == 0) return {w};\n"
        f"unsigned n = 0;\n"
        f"while ((a & {mask}) == 0) {{ a <<= 1; n++; }}\n"
        f"return n;"
    )


_REVERSE_BODIES = {
    8: [
        "a = ((a & 0xF0) >> 4) | ((a & 0x0F) << 4);",
        "a = ((a & 0xCC) >> 2) | ((a & 0x33) << 2);",
        "a = ((a & 0xAA) >> 1) | ((a & 0x55) << 1);",
    ],
    16: [
        "a = ((a & 0xFF00) >> 8) | ((a & 0x00FF) << 8);",
        "a = ((a & 0xF0F0) >> 4) | ((a & 0x0F0F) << 4);",
        "a = ((a & 0xCCCC) >> 2) | ((a & 0x3333) << 2);",
        "a = ((a & 0xAAAA) >> 1) | ((a & 0x5555) << 1);",
    ],
    32: [
        "a = ((a & 0xFFFF0000) >> 16) | ((a & 0x0000FFFF) << 16);",
        "a = ((a & 0xFF00FF00) >> 8) | ((a & 0x00FF00FF) << 8);",
        "a = ((a & 0xF0F0F0F0) >> 4) | ((a & 0x0F0F0F0F) << 4);",
        "a = ((a & 0xCCCCCCCC) >> 2) | ((a & 0x33333333) << 2);",
        "a = ((a & 0xAAAAAAAA) >> 1) | ((a & 0x55555555) << 1);",
    ],
    64: [
        "a = ((a & 0xFFFFFFFF00000000ULL) >> 32) | ((a & 0x00000000FFFFFFFFULL) << 32);",
        "a = ((a & 0xFFFF0000FFFF0000ULL) >> 16) | ((a & 0x0000FFFF0000FFFFULL) << 16);",
        "a = ((a & 0xFF00FF00FF00FF00ULL) >> 8) | ((a & 0x00FF00FF00FF00FFULL) << 8);",
        "a = ((a & 0xF0F0F0F0F0F0F0F0ULL) >> 4) | ((a & 0x0F0F0F0F0F0F0F0FULL) << 4);",
        "a = ((a & 0xCCCCCCCCCCCCCCCCULL) >> 2) | ((a & 0x3333333333333333ULL) << 2);",
        "a = ((a & 0xAAAAAAAAAAAAAAAAULL) >> 1) | ((a & 0x5555555555555555ULL) << 1);",
    ],
}


def _reverse_body(op: Operation) -> str:
    w = op.inputs[0]
    if w == 128:
        return (
            "uint64_t lo = (uint64_t)a;\n"
            "uint64_t hi = (uint64_t)(a >> 64);\n"
            "return ((uint128_t)reverse_64(lo) << 64) | reverse_64(hi);"
        )
    lines = _REVERSE_BODIES[w]
    lines.append("return a;")
    return "\n".join(lines)


def _rem_u_body(_op: Operation) -> str:
    return "if (b == 0) return a;\nreturn a % b;"


def _rem_s_body(op: Operation) -> str:
    t = gen_type(op.inputs[0])
    ts = gen_type(op.inputs[0], signed=True)
    return (
        f"if (b == 0) return a;\n"
        f"{ts} res = ({ts})a % ({ts})b;\n"
        f"return ({t})res;"
    )


def cpp_func_name(op: Operation) -> str:
    return op.name


def cpp_return_type(op: Operation) -> str:
    return gen_type(op.outputs[0])


def cpp_params(op: Operation) -> str:
    params = []
    for i, w in enumerate(op.inputs):
        letter = chr(ord('a') + i)
        params.append(f"{gen_type(w)} {letter}")
    return ", ".join(params)


def cpp_body(op: Operation) -> str:
    sb = op.semantic_base
    if isinstance(sb, str) and sb.startswith(":"):
        sb = sb[1:]

    if sb == BaseOp.NOT:       return "return ~a;"
    if sb == BaseOp.NEG:       return "return -a;"
    if sb == BaseOp.ADD:       return "return a + b;"
    if sb == BaseOp.SUB:       return "return a - b;"
    if sb == BaseOp.MUL:       return "return a * b;"
    if sb == BaseOp.AND:       return "return a & b;"
    if sb == BaseOp.ORR:       return "return a | b;"
    if sb == BaseOp.XOR:       return "return a ^ b;"
    if sb == BaseOp.EQ:        return "return (a == b) ? 1 : 0;"
    if sb == BaseOp.NE:        return "return (a != b) ? 1 : 0;"
    if sb == BaseOp.SLT:       return _signed_cmp(op, '<')
    if sb == BaseOp.SLE:       return _signed_cmp(op, '<=')
    if sb == BaseOp.SGT:       return _signed_cmp(op, '>')
    if sb == BaseOp.SGE:       return _signed_cmp(op, '>=')
    if sb == BaseOp.ULT:       return "return (a < b) ? 1 : 0;"
    if sb == BaseOp.ULE:       return "return (a <= b) ? 1 : 0;"
    if sb == BaseOp.UGT:       return "return (a > b) ? 1 : 0;"
    if sb == BaseOp.UGE:       return "return (a >= b) ? 1 : 0;"
    if sb == BaseOp.LSL:       return "return a << b;"
    if sb == BaseOp.LSR:       return "return a >> b;"
    if sb == BaseOp.ASR:       return _asr_body(op)
    if sb == BaseOp.DIV_U:     return "return (b == 0) ? c : a / b;"
    if sb == BaseOp.DIV_S:     return _div_s_body(op)
    if sb == BaseOp.SELECT:    return "return a ? b : c;"
    if sb == BaseOp.REM_U:     return _rem_u_body(op)
    if sb == BaseOp.REM_S:     return _rem_s_body(op)
    if sb == BaseOp.EXTEND_SIGN:  return _extend_sign_body(op)
    if sb == BaseOp.EXTEND_ZERO:  return _extend_zero_body(op)
    if sb == BaseOp.EXTRACT_LOW:  return _extract_low_body(op)

    raise ValueError(f"No cpp_body defined for operation {sb}")


def to_cpp(op: Operation) -> str:
    body = cpp_body(op)
    lines = body.split('\n')
    indented = '\n'.join(f"  {line}" for line in lines)
    return (
        f"static inline {cpp_return_type(op)} "
        f"{cpp_func_name(op)}({cpp_params(op)}) {{\n"
        f"{indented}\n"
        f"}}"
    )

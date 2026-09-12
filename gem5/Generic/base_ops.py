# gem5/Generic/base_ops.py

from typing import Callable, List

from lira.arch import Operation
from lira.ir_ops import (
    Add,
    And,
    Asr,
    BinaryOp,
    Clz,
    CmpOp,
    Ctz,
    DivS,
    DivU,
    Eq,
    ExtendOp,
    ExtendSign,
    ExtendZero,
    ExtractLow,
    ExtractLowOp,
    Lsl,
    Lsr,
    Mul,
    Ne,
    Neg,
    Not,
    Orr,
    Popcnt,
    RemS,
    RemU,
    Reverse,
    Select,
    Sge,
    Sgt,
    Sle,
    Slt,
    Sub,
    TernaryOp,
    Uge,
    Ugt,
    Ule,
    Ult,
    UnaryOp,
    Xor,
)

from .operand import Variable
from .types import OperandType


class CppOps:
    def cpp_return_type(self) -> str:
        return OperandType.gen(self.outputs[0])

    def cpp_params(self) -> str:
        params = []
        for i, w in enumerate(self.inputs):
            letter = chr(ord("a") + i)
            params.append(f"{OperandType.gen(w)} {letter}")
        return ", ".join(params)

    def cpp_call(self, args: List[str]) -> str:
        if self.semantic_func:
            return f"{self.semantic_func}({', '.join(args)})"
        return f"{self.name}({', '.join(args)})"

    def cpp_body(self) -> str:
        raise ValueError(f"No С++ body defined for operation {self.name}")

    def __call__(self, args: List[Variable]) -> str:
        return self.cpp_call([a.name for a in args])


def _include(cls: type) -> None:
    cls.cpp_return_type = CppOps.cpp_return_type
    cls.cpp_params = CppOps.cpp_params
    cls.cpp_call = CppOps.cpp_call
    cls.cpp_body = CppOps.cpp_body
    cls.__call__ = CppOps.__call__


for _cls in (
    Operation,
    UnaryOp,
    BinaryOp,
    CmpOp,
    TernaryOp,
    ExtendOp,
    ExtractLowOp,
    Select,
):
    _include(_cls)


def _not_body(self) -> str:
    return "return ~a;"


def _neg_body(self) -> str:
    return "return -a;"


def _binary_body(token: str) -> Callable[[Operation], str]:
    def body(self) -> str:
        return f"return a {token} b;"

    return body


def _asr_body(self) -> str:
    t = OperandType.gen(self.inputs[0])
    ts = OperandType.gen(self.inputs[0], signed=True)
    return f"return ({t})(({ts})a >> b);"


def _unsigned_cmp(token: str) -> Callable[[Operation], str]:
    def body(self) -> str:
        return f"return (a {token} b) ? 1 : 0;"

    return body


def _signed_cmp(token: str) -> Callable[[Operation], str]:
    def body(self) -> str:
        t = OperandType.gen(self.inputs[0], signed=True)
        return f"return (({t})a {token} ({t})b) ? 1 : 0;"

    return body


def _div_u_body(self) -> str:
    return "return (b == 0) ? c : a / b;"


def _div_s_body(self) -> str:
    t = OperandType.gen(self.inputs[0])
    ts = OperandType.gen(self.inputs[0], signed=True)
    return f"return (b == 0) ? c : ({t})(({ts})a / ({ts})b);"


def _rem_u_body(self) -> str:
    return f"""if (b == 0) return a;
return a % b;"""


def _rem_s_body(self) -> str:
    t = OperandType.gen(self.inputs[0])
    ts = OperandType.gen(self.inputs[0], signed=True)
    return f"""if (b == 0) return a;
{ts} res = ({ts})a % ({ts})b;
return ({t})res;"""


def _select_body(self) -> str:
    return "return a ? b : c;"


def _select_call(self, args: List[str]) -> str:
    return f"{args[0]} ? {args[1]} : {args[2]}"


def _extend_sign_body(self) -> str:
    if self.inputs[0] == 1:
        return "return a;"
    t = OperandType.gen(self.outputs[0])
    iw = self.inputs[0]
    return f"""{t} val = a & ((({t})1 << {iw}) - 1);
{t} sign = (val >> ({iw} - 1)) & 1;
if (sign)
  return val | (~((({t})1 << {iw}) - 1));
else
  return val;"""


def _extend_zero_body(self) -> str:
    t = OperandType.gen(self.outputs[0])
    return f"return a & ((({t})1 << {self.inputs[0]}) - 1);"


def _extract_low_body(self) -> str:
    t = OperandType.gen(self.inputs[0])
    return f"return a & ((({t})1 << {self.outputs[0]}) - 1);"


def _popcnt_body(self) -> str:
    w = self.inputs[0]
    if w == 8:
        return f"""unsigned cnt = 0;
while (a) {{ cnt += a & 1; a >>= 1; }}
return cnt;"""
    if w == 16:
        return "return popcnt_8(a & 0xFF) + popcnt_8((a >> 8) & 0xFF);"
    if w == 32:
        return "return popcnt_16(a & 0xFFFF) + popcnt_16((a >> 16) & 0xFFFF);"
    if w == 64:
        return "return popcnt_32(a & 0xFFFFFFFF) + popcnt_32((a >> 32) & 0xFFFFFFFF);"
    if w == 128:
        return "return popcnt_64((uint64_t)a) + popcnt_64((uint64_t)(a >> 64));"
    raise ValueError(f"Unsupported popcnt size: {w}")


def _ctz_body(self) -> str:
    w = self.inputs[0]
    if w == 128:
        return f"""if (a == 0) return 128;
uint64_t lo = (uint64_t)a;
if (lo) return ctz_64(lo);
else return 64 + ctz_64((uint64_t)(a >> 64));"""
    return f"""if (a == 0) return {w};
unsigned n = 0;
while ((a & 1) == 0) {{ a >>= 1; n++; }}
return n;"""


def _clz_body(self) -> str:
    w = self.inputs[0]
    if w == 128:
        return f"""if (a == 0) return 128;
uint64_t hi = (uint64_t)(a >> 64);
if (hi) return clz_64(hi);
else return 64 + clz_64((uint64_t)a);"""
    mask = {8: "0x80", 16: "0x8000", 32: "0x80000000", 64: "0x8000000000000000ULL"}[w]
    return f"""if (a == 0) return {w};
unsigned n = 0;
while ((a & {mask}) == 0) {{ a <<= 1; n++; }}
return n;"""


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


def _reverse_body(self) -> str:
    w = self.inputs[0]
    if w == 128:
        return f"""uint64_t lo = (uint64_t)a;
uint64_t hi = (uint64_t)(a >> 64);
return ((uint128_t)reverse_64(lo) << 64) | reverse_64(hi);"""
    lines = _REVERSE_BODIES[w]
    lines.append("return a;")
    return "\n".join(lines)


Not.cpp_body = _not_body
Neg.cpp_body = _neg_body
Add.cpp_body = _binary_body("+")
Sub.cpp_body = _binary_body("-")
Mul.cpp_body = _binary_body("*")
And.cpp_body = _binary_body("&")
Orr.cpp_body = _binary_body("|")
Xor.cpp_body = _binary_body("^")
Lsl.cpp_body = _binary_body("<<")
Lsr.cpp_body = _binary_body(">>")
Asr.cpp_body = _asr_body
Eq.cpp_body = _unsigned_cmp("==")
Ne.cpp_body = _unsigned_cmp("!=")
Slt.cpp_body = _signed_cmp("<")
Sle.cpp_body = _signed_cmp("<=")
Sgt.cpp_body = _signed_cmp(">")
Sge.cpp_body = _signed_cmp(">=")
Ult.cpp_body = _unsigned_cmp("<")
Ule.cpp_body = _unsigned_cmp("<=")
Ugt.cpp_body = _unsigned_cmp(">")
Uge.cpp_body = _unsigned_cmp(">=")
DivU.cpp_body = _div_u_body
DivS.cpp_body = _div_s_body
RemU.cpp_body = _rem_u_body
RemS.cpp_body = _rem_s_body
Select.cpp_body = _select_body
Select.cpp_call = _select_call
ExtendSign.cpp_body = _extend_sign_body
ExtendZero.cpp_body = _extend_zero_body
ExtractLow.cpp_body = _extract_low_body
Popcnt.cpp_body = _popcnt_body
Ctz.cpp_body = _ctz_body
Clz.cpp_body = _clz_body
Reverse.cpp_body = _reverse_body

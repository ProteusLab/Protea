# gen_py/target/rv32i/cpp_ops.py
# RISC-V ISA-specific C++ codegen overrides.
# Shift operations mask the shift amount to log2(XLEN) bits (RISC-V spec §2.4).

import cpp_ops as _base

_STANDARD_WIDTHS = [1, 8, 16, 32, 64, 128]


def _cpp_type_bits(width: int) -> int:
    return next(s for s in _STANDARD_WIDTHS if s >= width)


def _mask(width: int) -> int:
    return _cpp_type_bits(width) - 1


def _lsl_body(op) -> str:
    return f"b &= {_mask(op.inputs[0])}; return a << b;"


def _lsr_body(op) -> str:
    return f"b &= {_mask(op.inputs[0])}; return a >> b;"


def _asr_body(op) -> str:
    t = _base.gen_type(op.inputs[0])
    ts = _base.gen_type(op.inputs[0], signed=True)
    return f"b &= {_mask(op.inputs[0])}; return ({t})(({ts})a >> b);"


def _install():
    """Monkey-patch ``gen_py.cpp_ops`` for RISC-V shift-masking."""
    _original_cpp_body = _base.cpp_body

    def _cpp_body_rv32i(op) -> str:
        sb = op.semantic_base
        if isinstance(sb, str) and sb.startswith(":"):
            sb = sb[1:]
        if sb == "lsl":
            return _lsl_body(op)
        if sb == "lsr":
            return _lsr_body(op)
        if sb == "asr":
            return _asr_body(op)
        return _original_cpp_body(op)

    _base.cpp_body = _cpp_body_rv32i


_install()

# gem5/Generic/isa_emitter.py
# decoder_protea.isa emission: decode block + ProteaInst instantiations.
# No indentation is maintained: it is generated code.

from typing import TYPE_CHECKING, List

if TYPE_CHECKING:
    from .instruction import Instruction

MACH_INST = "machInst"


def _emit_case(inst: "Instruction") -> str:
    return f"""\
{inst.inst_id}: {inst.name}(
op_class = {{{{ IntAluOp }}}},
memb_decls = {{{{
{inst.memb_decls}
}}}},
memb_defs = {{{{
{inst.memb_defs}
}}}},
meth_decls = {{{{
{inst.meth_decls}
}}}},
meth_defs = {{{{
{inst.meth_defs}
}}}});"""


def gen_decoder_isa(insts: List["Instruction"]) -> str:
    code = """\
// -*- mode:c++ -*-

// Protea DSL instruction class declaration template.

decode ProteaDecoderCall default Unknown::unknown() {
format ProteaInst {
"""
    for inst in insts:
        code += _emit_case(inst) + "\n"
    code += """\
}
}
"""
    return code

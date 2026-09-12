# gem5/Generic/instruction.py

from typing import List

from .nodes import render_nodes
from .operand import Register


class Instruction:
    def __init__(
        self,
        inst_id: int,
        name: str,
        constraint_decode: str,
        sem: List[object],
        regs: List[Register],
        num_src: int,
        num_dst: int,
        has_mem: bool,
    ):
        self.inst_id: int = inst_id
        self.name: str = name
        self.constraint_decode: str = constraint_decode
        self.sem: List[object] = sem
        self.regs: List[Register] = regs
        self.num_src: int = num_src
        self.num_dst: int = num_dst
        self.has_mem: bool = has_mem

    @property
    def memb_decls(self) -> str:
        code = ""
        for reg in self.regs:
            code += reg.declaration
        code += f"""
RegId srcRegIdxArr[{self.num_src}];
RegId destRegIdxArr[{self.num_dst}];
"""
        return code

    @property
    def memb_defs(self) -> str:
        code = ""
        for reg in self.regs:
            code += reg.definition
            reg_wiring = reg.emit_reg_wiring
            if reg_wiring:
                code += reg_wiring

        return code

    @property
    def meth_decls(self) -> str:
        code = f"""Fault execute(ExecContext* xc, trace::InstRecord* traceData) const override;\n"""
        if self.has_mem:
            code += f"""\
Fault initiateAcc(ExecContext *, trace::InstRecord *) const override;
Fault completeAcc(PacketPtr, ExecContext *, trace::InstRecord *) const override;
"""
        return code

    @property
    def meth_defs(self) -> str:
        sem = render_nodes(self.sem)
        code = f"""\
Fault {self.name}::execute(ExecContext* xc, trace::InstRecord* traceData) const
{{
{sem}
return NoFault;
}}"""
        if self.has_mem:
            code += f"""

Fault {self.name}::initiateAcc(ExecContext *, trace::InstRecord *) const
{{
return NoFault;
}}

Fault {self.name}::completeAcc(PacketPtr, ExecContext *, trace::InstRecord *) const
{{
return NoFault;
}}
"""
        return code

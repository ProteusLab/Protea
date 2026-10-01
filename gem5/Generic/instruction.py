# gem5/Generic/instruction.py

from typing import List, Optional, Union

from .nodes import ReadMem, WriteMem, node_def, node_uses, render_nodes
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
    def mem_access(self) -> Optional[Union[ReadMem, WriteMem]]:
        for node in self.sem:
            if isinstance(node, (ReadMem, WriteMem)) and node.is_mem:
                return node
        return None

    @property
    def interfaces(self) -> List[object]:
        return [n.interface for n in self.sem if isinstance(n, (ReadMem, WriteMem))]

    @property
    def op_class(self) -> str:
        for interface in self.interfaces:
            if interface.op_class is not None:
                return interface.op_class
        return "IntAluOp"

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

        flags = []
        for interface in self.interfaces:
            flags += [f for f in interface.flags if f not in flags]
        for flag in flags:
            code += f"flags[{flag}] = true;\n"

        return code

    @property
    def meth_decls(self) -> str:
        code = f"""Fault execute(ExecContext* xc, trace::InstRecord* traceData) const override;\n"""
        if self.has_mem:
            code += f"""\
Fault initiateAcc(ExecContext* xc, trace::InstRecord* traceData) const override;
Fault completeAcc(PacketPtr pkt, ExecContext* xc, trace::InstRecord* traceData) const override;
"""
        return code

    def _split_acc(self):
        mem = self.mem_access
        pos = self.sem.index(mem)
        before, after = self.sem[:pos], self.sem[pos + 1:]

        if isinstance(mem, WriteMem):
            initiate = render_nodes(before + [mem.initiate()] + after)
            return f"{initiate}\nreturn NoFault;", "return NoFault;"

        initiate = render_nodes(before + [mem.initiate()])
        live = {id(v) for n in after for v in node_uses(n)}
        recompute = []
        for node in reversed(before):
            var = node_def(node)
            if var is not None and id(var) in live:
                recompute.insert(0, node)
                live.update(id(v) for v in node_uses(node))
        complete = render_nodes(recompute + [mem.complete()] + after)
        return initiate, f"{complete}\nreturn NoFault;"

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
            initiate, complete = self._split_acc()
            code += f"""

Fault {self.name}::initiateAcc(ExecContext* xc, trace::InstRecord* traceData) const
{{
{initiate}
}}

Fault {self.name}::completeAcc(PacketPtr pkt, ExecContext* xc, trace::InstRecord* traceData) const
{{
{complete}
}}
"""
        return code

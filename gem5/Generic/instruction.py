# gem5/Generic/instruction.py

from typing import List, Optional, Union

from .interface import ReadPC
from .nodes import ReadMem, WriteMem, node_def, node_uses, render_nodes
from .operand import Register
from .properties import Control


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
        op_class: str,
        flags: List[str],
        cond_flags: List[str],
        control: Optional[Control],
    ):
        self.inst_id: int = inst_id
        self.name: str = name
        self.constraint_decode: str = constraint_decode
        self.sem: List[object] = sem
        self.regs: List[Register] = regs
        self.num_src: int = num_src
        self.num_dst: int = num_dst
        self.has_mem: bool = has_mem
        self.op_class: str = op_class
        self.flags: List[str] = flags
        # C++ statements setting flags that depend on decoded operands.
        self.cond_flags: List[str] = cond_flags
        self.control: Optional[Control] = control

    @property
    def mem_access(self) -> Optional[Union[ReadMem, WriteMem]]:
        for node in self.sem:
            if isinstance(node, (ReadMem, WriteMem)) and node.is_mem:
                return node
        return None

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

        for flag in self.flags:
            code += f"flags[{flag}] = true;\n"
        for stmt in self.cond_flags:
            code += stmt + "\n"

        return code

    @property
    def meth_decls(self) -> str:
        code = f"""Fault execute(ExecContext* xc, trace::InstRecord* traceData) const override;\n"""
        if self.has_mem:
            code += f"""\
Fault initiateAcc(ExecContext* xc, trace::InstRecord* traceData) const override;
Fault completeAcc(PacketPtr pkt, ExecContext* xc, trace::InstRecord* traceData) const override;
"""
        if self.has_branch_target:
            code += """\
std::unique_ptr<PCStateBase> branchTarget(const PCStateBase &branch_pc) const override;
using StaticInst::branchTarget;
"""
        return code

    @property
    def has_branch_target(self) -> bool:
        # O3 decode calls branchTarget() for IsDirectControl instructions
        return self.control is not None and self.control.direct

    def _branch_target(self) -> str:
        # The taken target computed from the branch PC instead of xc
        body = []
        for node in self.control.taken_slice:
            if isinstance(node, ReadMem) and isinstance(node.interface, ReadPC):
                body.append(f"{node.var.declaration}\n{node.var} = branch_pc.instAddr();\n")
            else:
                body.append(node)
        return f"""{render_nodes(body)}
std::unique_ptr<PCStateBase> target(branch_pc.clone());
target->as<PCState>().set({self.control.taken});
return target;"""

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
        if self.has_branch_target:
            code += f"""

std::unique_ptr<PCStateBase>
{self.name}::branchTarget(const PCStateBase &branch_pc) const
{{
{self._branch_target()}
}}
"""
        return code

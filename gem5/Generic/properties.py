# gem5/Generic/properties.py
# Derivation of gem5 StaticInst flags and op class from instruction semantics.
# The analysis works on generator nodes (not on the input IR), so it does not
# depend on the IR format.

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

from .interface import ReadPC, WritePC
from .nodes import OpAssign, ReadMem, ReadReg, WriteMem, WriteReg, node_def, node_uses
from .operand import Constant, Register, Variable


@dataclass
class Control:
    conditional: bool
    # The target depends only on the PC, constants and decoded fields
    # (no register or memory reads).
    direct: bool
    # Address the PC is set to when the branch is taken (always for
    # unconditional jumps); for a conditional branch it is the select
    # alternative that is not the default pc + instr_size.
    taken: Variable
    # Nodes computing the taken target, in program order (for branchTarget()).
    taken_slice: List[object]
    # Register written with the return address (pc + instruction size).
    link: Optional[Register]
    # The only register the taken target is computed from.
    target_reg: Optional[Register]


@dataclass
class Properties:
    load: bool = False
    store: bool = False
    # Reads or writes registers (of the single, integer register file).
    int_regs: bool = False
    # semantic_base of every operation: "add", "mul", "div_s", ...
    ops: Set[str] = field(default_factory=set)
    # Flags of non-memory env interfaces (sysCall, breakPoint, ...).
    effect_flags: List[str] = field(default_factory=list)
    control: Optional[Control] = None

    def gem5_op_class(self) -> str:
        if self.load:
            return "MemReadOp"
        if self.store:
            return "MemWriteOp"
        if self.ops & {"div_s", "div_u", "rem_s", "rem_u"}:
            return "IntDivOp"
        if "mul" in self.ops:
            return "IntMultOp"
        if self.effect_flags and not self.ops and self.control is None:
            return "No_OpClass"
        return "IntAluOp"

    def gem5_flags(self, link_regs: Set[int]) -> Tuple[List[str], List[str]]:
        """Returns flags set unconditionally and C++ statements setting flags
        that depend on decoded register numbers."""
        flags: List[str] = []
        cond: List[str] = []
        if self.int_regs:
            flags.append("IsInteger")
        if self.load:
            flags.append("IsLoad")
        if self.store:
            flags.append("IsStore")
        flags += [f for f in self.effect_flags if f not in flags]

        ctl = self.control
        if ctl is None:
            return flags, cond
        flags.append("IsControl")
        flags.append("IsCondControl" if ctl.conditional else "IsUncondControl")
        flags.append("IsDirectControl" if ctl.direct else "IsIndirectControl")

        if not link_regs:
            return flags, cond

        # Return address stack hints, RISC-V spec "Unconditional Jumps".
        def is_link(reg: Register) -> str:
            return "(" + " || ".join(f"{reg.name} == {i}" for i in sorted(link_regs)) + ")"

        if ctl.link is not None:
            cond.append(f"if ({is_link(ctl.link)}) flags[IsCall] = true;")
        if not ctl.direct and ctl.target_reg is not None:
            ret = is_link(ctl.target_reg)
            if ctl.link is not None:
                ret += f" && (!{is_link(ctl.link)} || {ctl.target_reg.name} != {ctl.link.name})"
            cond.append(f"if ({ret}) flags[IsReturn] = true;")
        return flags, cond


class _Graph:
    def __init__(self, sem: List[object]):
        self.sem = sem
        self.defs: Dict[int, object] = {}
        for node in sem:
            var = node_def(node)
            if var is not None:
                self.defs[id(var)] = node

    def slice(self, var: Variable) -> List[object]:
        """Computation trace of var, in program order."""
        live = {id(var)}
        nodes = []
        for node in reversed(self.sem):
            var = node_def(node)
            if var is not None and id(var) in live:
                nodes.insert(0, node)
                live.update(id(v) for v in node_uses(node))
        return nodes

    def is_pc(self, var: Variable) -> bool:
        node = self.defs.get(id(var))
        return isinstance(node, ReadMem) and isinstance(node.interface, ReadPC)

    def is_next_pc(self, var: Variable, inst_size: int) -> bool:
        node = self.defs.get(id(var))
        if not isinstance(node, OpAssign) or node.op.semantic_base != "add":
            return False
        a, b = node.args
        for pc, off in ((a, b), (b, a)):
            if self.is_pc(pc) and isinstance(off, Constant) and int(off.value, 0) == inst_size:
                return True
        return False


def _analyze_control(graph: _Graph, inst_size: int) -> Optional[Control]:
    writes = [n for n in graph.sem
              if isinstance(n, WriteMem) and isinstance(n.interface, WritePC)]
    if not writes:
        return None
    target = writes[-1].data

    conditional, taken = False, target
    node = graph.defs.get(id(target))
    if isinstance(node, OpAssign) and node.op.semantic_base == "select":
        _, a, b = node.args
        if graph.is_next_pc(b, inst_size):
            conditional, taken = True, a
        elif graph.is_next_pc(a, inst_size):
            conditional, taken = True, b

    taken_slice = graph.slice(taken)
    read_regs = [n.reg for n in taken_slice if isinstance(n, ReadReg)]
    reads_mem = any(isinstance(n, ReadMem) and n.is_mem for n in taken_slice)
    link = next((n.reg for n in graph.sem
                 if isinstance(n, WriteReg) and graph.is_next_pc(n.value, inst_size)), None)
    return Control(
        conditional=conditional,
        direct=not read_regs and not reads_mem,
        taken=taken,
        taken_slice=taken_slice,
        link=link,
        target_reg=read_regs[0] if len({id(r) for r in read_regs}) == 1 else None,
    )


def analyze(sem: List[object], inst_size: int) -> Properties:
    """inst_size: instruction size in bytes"""
    properties = Properties()
    for node in sem:
        if isinstance(node, OpAssign):
            properties.ops.add(node.op.semantic_base)
        elif isinstance(node, (ReadReg, WriteReg)):
            properties.int_regs = True
        elif isinstance(node, (ReadMem, WriteMem)):
            if node.is_mem:
                properties.load |= isinstance(node, ReadMem)
                properties.store |= isinstance(node, WriteMem)
            else:
                properties.effect_flags += [f for f in node.interface.flags
                                        if f not in properties.effect_flags]
    properties.control = _analyze_control(_Graph(sem), inst_size)
    return properties

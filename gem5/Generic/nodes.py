# gem5/Generic/nodes.py

from typing import List, Optional

from lira.arch import Operation

from .operand import Operand, Register, Variable


def render_nodes(nodes) -> str:
    return "\n".join(str(node) for node in nodes)


class InputAssign:
    def __init__(self, var: Variable, source: str):
        self.var: Variable = var
        self.source: str = source

    def __str__(self) -> str:
        return f"""{self.var.declaration}
{self.var} = {self.source};
"""


class OpAssign:
    def __init__(self, out: Variable, op: Operation, args: List[Variable]):
        self.out: Variable = out
        self.op: Operation = op
        self.args: List[Variable] = args

    def __str__(self) -> str:
        return f"""{self.out.declaration}
{self.out} = {self.op(self.args)};
"""


class ReadReg:
    def __init__(self, reg: Register, var: Variable):
        self.reg: Register = reg
        self.var: Variable = var

    def __str__(self) -> str:
        return f"""{self.var.declaration}
{self.var} = {self.reg.read()};
"""


class WriteReg:
    def __init__(self, reg: Register, value: Variable):
        self.reg: Register = reg
        self.value: Variable = value

    def __str__(self) -> str:
        return self.reg.write(self.value)


def _check_fault(expr: str) -> str:
    return f"""{{
Fault fault = {expr};
if (fault != NoFault) return fault;
}}"""


class ReadMem:
    def __init__(self, var: Variable, addr: Variable, interface):
        self.var: Variable = var
        self.addr: Variable = addr
        self.interface = interface

    @property
    def is_mem(self) -> bool:
        return self.interface.has_mem

    def __str__(self) -> str:
        if not self.is_mem:
            return f"""{self.var.declaration}
{self.interface(self.addr, self.var)}
"""
        return f"""{self.var.declaration}
{_check_fault(self.interface.atomic(self.addr, self.var))}
"""

    def initiate(self) -> str:
        return f"""{self.var.declaration}
return {self.interface.initiate(self.addr, self.var)};
"""

    def complete(self) -> str:
        return f"""{self.var.declaration}
{self.interface.complete(self.var)}
"""


class WriteMem:
    def __init__(self, data: Variable, addr: Variable, interface):
        self.data: Variable = data
        self.addr: Variable = addr
        self.interface = interface

    @property
    def is_mem(self) -> bool:
        return self.interface.has_mem

    def __str__(self) -> str:
        if not self.is_mem:
            return f"{self.interface(self.addr, self.data)};"
        return _check_fault(self.interface.atomic(self.addr, self.data))

    def initiate(self) -> str:
        return _check_fault(self.interface.initiate(self.addr, self.data))


class MemberAssign:
    def __init__(self, operand: Operand, value: Variable):
        self.operand: Operand = operand
        self.value: Variable = value

    def __str__(self) -> str:
        return f"""{self.operand} = {self.value};"""


class Return:
    def __init__(self, value: Variable):
        self.value: Variable = value

    def __str__(self) -> str:
        return f"""return {self.value};"""


def node_uses(node) -> List[Variable]:
    """Variables read by a node."""
    if isinstance(node, OpAssign):
        return list(node.args)
    if isinstance(node, WriteReg):
        return [node.value]
    if isinstance(node, ReadMem):
        return [node.addr] if node.addr is not None else []
    if isinstance(node, WriteMem):
        return [v for v in (node.data, node.addr) if v is not None]
    return []


def node_def(node) -> Optional[Variable]:
    """Variable produced by a node (None for side effects)."""
    if isinstance(node, (InputAssign, ReadReg, ReadMem)):
        return node.var
    if isinstance(node, OpAssign):
        return node.out
    if isinstance(node, Variable):
        return node
    return None

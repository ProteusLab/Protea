# gem5/Generic/nodes.py

from typing import List

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


class ReadMem:
    def __init__(self, var: Variable, addr: Variable, interface):
        self.var: Variable = var
        self.addr: Variable = addr
        self.interface = interface

    def __str__(self) -> str:
        return f"""{self.var.declaration}
{self.interface(self.addr, self.var)}
"""


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

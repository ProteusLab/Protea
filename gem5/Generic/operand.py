# gem5/Generic/operand.py

from typing import Optional

from lira.arch import Snippet
from lira.arch_utils import ArchIndex

from .types import OperandType


class Variable:
    def __init__(self, name: str, width: int):
        self.name: str = name
        self.width: int = width

    def __str__(self) -> str:
        return self.name

    @property
    def type(self) -> str:
        return OperandType.gen(self.width)

    @property
    def declaration(self) -> str:
        return f"{self.type} {self.name}{{0}};"


class Constant(Variable):
    def __init__(self, name: str, width: int, value: str):
        super().__init__(name, width)
        self.value: str = value

    def __str__(self) -> str:
        return self.declaration

    @property
    def declaration(self) -> str:
        return f"{self.type} {self.name} = {self.value};"


class Operand(Variable):
    def __init__(self, name: str, width: int, index: ArchIndex, snippet: Snippet):
        super().__init__(name, width)
        self.index: ArchIndex = index
        self.snippet: Snippet = snippet

    @property
    def definition(self) -> str:
        from .builders import DecodeBuilder
        from .nodes import render_nodes

        nodes = DecodeBuilder(self.index, self).build(self.snippet.seq)
        body = render_nodes(nodes)
        return f"""{{
{body}
}}
"""


class Register(Operand):
    def __init__(
        self,
        name: str,
        width: int,
        index: ArchIndex,
        snippet: Snippet,
        src_pos: Optional[int] = None,
        dst_pos: Optional[int] = None,
    ):
        super().__init__(name, width, index, snippet)
        self.src_pos: Optional[int] = src_pos
        self.dst_pos: Optional[int] = dst_pos

    def read(self) -> str:
        return f"""xc->getRegOperand(this, {self.src_pos})"""

    def write(self, value: Variable) -> str:
        return f"""xc->setRegOperand(this, {self.dst_pos}, {value});
if (traceData) {{ traceData->setData(intRegClass, {value}); }}
"""

    @property
    def set_src(self) -> str:
        if self.src_pos is None:
            return ""
        return f"""setSrcRegIdx({self.src_pos}, intRegClass[{self.name}]);
_numSrcRegs++;
"""

    @property
    def set_dst(self) -> str:
        if self.dst_pos is None:
            return ""
        return f"""setDestRegIdx({self.dst_pos}, intRegClass[{self.name}]);
_numDestRegs++;
"""

    @property
    def emit_reg_wiring(self) -> str:
        return self.set_src + self.set_dst

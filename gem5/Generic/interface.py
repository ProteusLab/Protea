# gem5/Generic/interface.py

from abc import ABC, abstractmethod
from typing import ClassVar, Dict, List, Optional

from lira.arch import Arch


class IInterface(ABC):
    has_mem: ClassVar[bool] = False
    # StaticInst flags implied by the side effect of a non-memory interface;
    # everything else is derived from the semantics (see traits.py).
    flags: ClassVar[List[str]] = []

    @classmethod
    @abstractmethod
    def match(cls, name: str) -> bool:
        pass

    @abstractmethod
    def __call__(self, addr: str, data: str) -> str:
        pass


class IMemInterface(IInterface):
    has_mem: ClassVar[bool] = True

    def __call__(self, addr: str, data: str) -> str:
        return self.atomic(addr, data)

    @abstractmethod
    def atomic(self, addr: str, data: str) -> str:
        pass

    @abstractmethod
    def initiate(self, addr: str, data: str) -> str:
        pass

    @abstractmethod
    def complete(self, data: str) -> str:
        pass


class Load(IMemInterface):
    @classmethod
    def match(cls, name: str) -> bool:
        return name.startswith("readMem")

    def atomic(self, addr: str, data: str) -> str:
        return f"readMemAtomicLE(xc, traceData, {addr}, {data}, 0)"

    def initiate(self, addr: str, data: str) -> str:
        return f"initiateMemRead(xc, traceData, {addr}, {data}, 0)"

    def complete(self, data: str) -> str:
        return f"getMemLE(pkt, {data}, traceData);"


class Store(IMemInterface):
    @classmethod
    def match(cls, name: str) -> bool:
        return name.startswith("writeMem")

    def atomic(self, addr: str, data: str) -> str:
        return f"writeMemAtomicLE(xc, traceData, {data}, {addr}, 0, nullptr)"

    def initiate(self, addr: str, data: str) -> str:
        return f"writeMemTimingLE(xc, traceData, {data}, {addr}, 0, nullptr)"

    def complete(self, data: str) -> str:
        return ""


class ReadPC(IInterface):
    @classmethod
    def match(cls, name: str) -> bool:
        return name == "getPC"

    def __call__(self, addr: str, data: str) -> str:
        return f"{data} = xc->pcState().instAddr();"


class WritePC(IInterface):
    @classmethod
    def match(cls, name: str) -> bool:
        return name == "setPC"

    def __call__(self, addr: str, data: str) -> str:
        return f"""{{
PCState new_pc = xc->pcState().as<PCState>();
new_pc.npc({data});
xc->pcState(new_pc);
}}"""


class SysCall(IInterface):
    flags: ClassVar[List[str]] = ["IsSerializeAfter", "IsNonSpeculative", "IsSyscall"]

    @classmethod
    def match(cls, name: str) -> bool:
        return name == "sysCall"

    def __call__(self, addr: str, data: str) -> str:
        return """MISA misa = xc->readMiscReg(MISCREG_ISA);
bool virtualized = misa.rvh ? virtualizationEnabled(xc) : false;
return std::make_shared<SyscallFault>(
(PrivilegeMode)xc->readMiscReg(MISCREG_PRV), virtualized)"""


class Breakpoint(IInterface):
    flags: ClassVar[List[str]] = ["IsSerializeAfter", "IsNonSpeculative"]

    @classmethod
    def match(cls, name: str) -> bool:
        return name == "breakPoint"

    def __call__(self, addr: str, data: str) -> str:
        return """MISA misa = xc->readMiscReg(MISCREG_ISA);
bool virtualized = misa.rvh ? virtualizationEnabled(xc) : false;
return std::make_shared<BreakpointFault>(xc->pcState(), virtualized)"""


class InterfacesRegistry:
    def __init__(self, interfaces: List[type]):
        self._interfaces: List[type] = interfaces
        self._map: Dict[str, Optional[IInterface]] = {}

    def _match(self, name: str) -> Optional[IInterface]:
        for cls in self._interfaces:
            if cls.match(name):
                return cls()
        return None

    @classmethod
    def from_arch(cls, arch: Arch) -> "InterfacesRegistry":
        reg = cls([Load, Store, ReadPC, WritePC, SysCall, Breakpoint])
        for func in arch.environment_functions:
            reg._map[func.name] = reg._match(func.name)
        return reg

    def __getitem__(self, name: str) -> Optional[IInterface]:
        if name not in self._map:
            self._map[name] = self._match(name)
        return self._map[name]

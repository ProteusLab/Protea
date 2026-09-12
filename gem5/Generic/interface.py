# gem5/Generic/interface.py

from abc import ABC, abstractmethod
from typing import ClassVar, Dict, List, Optional

from lira.arch import Arch


class IInterface(ABC):
    has_mem: ClassVar[bool] = False

    @classmethod
    @abstractmethod
    def match(cls, name: str) -> bool:
        pass

    @abstractmethod
    def __call__(self, addr: str, data: str) -> str:
        pass


class Load(IInterface):
    has_mem: ClassVar[bool] = True

    @classmethod
    def match(cls, name: str) -> bool:
        return name.startswith("readMem")

    def __call__(self, addr: str, data: str) -> str:
        return f"readMemAtomicLE(xc, traceData, {addr}, {data}, 0);"


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
        reg = cls([Load])
        for func in arch.environment_functions:
            reg._map[func.name] = reg._match(func.name)
        return reg

    def __getitem__(self, name: str) -> Optional[IInterface]:
        return self._map.get(name)

# gem5/Generic/config.py

from abc import ABC, abstractmethod
from pathlib import Path
from typing import List, Set, Tuple

from .instruction import Instruction


class IConfig(ABC):
    @property
    @abstractmethod
    def supported_instructions(self) -> Set[str]:
        pass

    @property
    @abstractmethod
    def excluded_instructions(self) -> Set[str]:
        pass

    @property
    @abstractmethod
    def decoder_isa(self) -> Path:
        pass

    @property
    @abstractmethod
    def decoder_hh(self) -> Path:
        pass

    @property
    @abstractmethod
    def decoder_cc(self) -> Path:
        pass

    @property
    @abstractmethod
    def base_ops_hh(self) -> Path:
        pass

    @property
    @abstractmethod
    def base_ops_cc(self) -> Path:
        pass

    @abstractmethod
    def emit_decoder_isa(self, insts: List[Instruction]) -> str:
        pass

    @abstractmethod
    def emit_decoder(self, index, insts: List[Instruction]) -> Tuple[str, str]:
        pass

    @abstractmethod
    def emit_base_ops(self, operations) -> Tuple[str, str]:
        pass

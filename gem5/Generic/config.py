# gem5/Generic/config.py

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, List, Set, Tuple

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
    def implicit_env(self) -> Dict[str, str]:
        """Instruction name -> env function appended to its semantics.
        For instructions whose effect is not expressed in the ADL semantics.
        """
        return {}

    @property
    def link_registers(self) -> Set[int]:
        """Numbers of link registers (return address stack hints for
        IsCall/IsReturn). Not expressed in the semantics."""
        return set()

    @property
    def manual_flags(self) -> Dict[str, List[str]]:
        """Instruction name -> flags added to the derived ones."""
        return {}

    @property
    def manual_op_class(self) -> Dict[str, str]:
        """Instruction name -> op class replacing the derived one."""
        return {}

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

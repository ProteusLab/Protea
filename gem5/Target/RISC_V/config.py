# gem5/Target/RISC_V/config.py
# RISC-V-specific configuration: supported instructions, output paths
# and artifact generation.

from pathlib import Path
from typing import List, Set, Tuple

from Generic.config import IConfig
from Generic.instruction import Instruction
from Generic.isa_emitter import gen_decoder_isa
from Target.RISC_V.base_ops_emitter import gen_protea_base_ops
from Target.RISC_V.decoder_emitter import gen_protea_decoder


class RiscvConfig(IConfig):
    @property
    def supported_instructions(self) -> Set[str]:
        return {"add", "lw"}

    @property
    def excluded_instructions(self) -> Set[str]:
        pass

    @property
    def decoder_isa(self) -> Path:
        return Path("src/arch/riscv/isa/decoder_protea.isa")

    @property
    def decoder_hh(self) -> Path:
        return Path("src/arch/riscv/insts/protea_decoder.hh")

    @property
    def decoder_cc(self) -> Path:
        return Path("src/arch/riscv/insts/protea_decoder.cc")

    @property
    def base_ops_hh(self) -> Path:
        return Path("src/arch/riscv/insts/protea_base_ops.hh")

    @property
    def base_ops_cc(self) -> Path:
        return Path("src/arch/riscv/insts/protea_base_ops.cc")

    def emit_decoder_isa(self, insts: List[Instruction]) -> str:
        return gen_decoder_isa(insts)

    def emit_decoder(self, index, insts: List[Instruction]) -> Tuple[str, str]:
        return gen_protea_decoder(index, insts, index.snippet)

    def emit_base_ops(self, operations) -> Tuple[str, str]:
        return gen_protea_base_ops(operations)

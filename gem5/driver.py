# gem5/Driver.py

from pathlib import Path
from typing import List

from lira.arch_ser_yaml import read_arch
from lira.arch_utils import build_arch_index

from Generic.instruction import Instruction
from Generic.interface import InterfacesRegistry
from Generic.builders import SemanticBuilder
from Target.RISC_V.config import RiscvConfig


class Driver:
    def __init__(self, ir_path: Path):
        self.arch = read_arch(ir_path)
        self.index = build_arch_index(self.arch)
        self.interfaces = InterfacesRegistry.from_arch(self.arch)
        self.config = RiscvConfig()

        self.insts = self.process_instrs(
            [insn for insn in self.arch.instructions
             if insn.name in self.config.supported_instructions],
        )

        # The script is only launched from the gem5 repository root
        # (via scons), so the output files are resolved against the cwd.
        self.repo_root: Path = Path.cwd()

    def process_instrs(self, insns) -> List[Instruction]:
        insts = []
        for i, insn in enumerate(insns):
            sem = SemanticBuilder(self.index, insn, self.interfaces)
            body = sem.build(insn.semantic)
            insts.append(Instruction(
                i,
                insn.name.upper(),
                insn.encoding.constraint_decode,
                body,
                sem.regs,
                len(sem.read_operands),
                len(sem.write_operands),
                sem.has_mem,
            ))
        return insts

    def write_artifacts(self) -> None:
        cfg = self.config
        self._write(cfg.decoder_isa, cfg.emit_decoder_isa(self.insts))

        dec_hh, dec_cc = cfg.emit_decoder(self.index, self.insts)

        self._write(cfg.decoder_hh, dec_hh)
        self._write(cfg.decoder_cc, dec_cc)

        ops_hh, ops_cc = cfg.emit_base_ops(self.arch.operations)

        self._write(cfg.base_ops_hh, ops_hh)
        self._write(cfg.base_ops_cc, ops_cc)

    def _write(self, path: Path, content: str) -> None:
        out_path = self.repo_root / path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w") as out:
            print(content, file=out, end="")

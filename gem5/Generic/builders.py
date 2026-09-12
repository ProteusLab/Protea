# gem5/Generic/builders.py

from abc import ABC, ABCMeta, abstractmethod
from typing import Dict, List, Optional, cast

from lira.arch import Instruction as LiraInstruction
from lira.arch_utils import ArchIndex
from lira.ir import Statement, StatementSeq
from lira.ir_std import (
    StmtConst,
    StmtEnv,
    StmtInput,
    StmtOp,
    StmtOutput,
    StmtRead,
    StmtWrite,
)

from .isa_emitter import MACH_INST
from .nodes import (
    InputAssign,
    MemberAssign,
    OpAssign,
    ReadMem,
    ReadReg,
    Return,
    WriteReg,
)
from .operand import Constant, Operand, Register, Variable


class GenerationError(Exception):
    pass


class IBuilder(ABC):
    @abstractmethod
    def build(self, seq: StatementSeq) -> List[object]:
        pass


class StmtHandler(ABC):
    def __init__(self, builder: IBuilder, stmt: Statement):
        self.builder: IBuilder = builder
        self.stmt: Statement = stmt

    @abstractmethod
    def build(self) -> None:
        pass


def register(kind: str):
    def decorator(handler_cls):
        assert issubclass(handler_cls, StmtHandler)
        handler_cls.handler_kind = kind
        return handler_cls

    return decorator


class BuilderMeta(ABCMeta):
    def __new__(mcls, name, bases, ns):
        cls = super().__new__(mcls, name, bases, ns)
        handlers = {}
        for base in reversed(cls.__mro__):
            handlers.update(getattr(base, "handlers", {}))
        for value in ns.values():
            kind = getattr(value, "handler_kind", None)
            if kind is not None:
                handlers[kind] = value
        cls.handlers = handlers
        return cls


class CodeBuilder(IBuilder, metaclass=BuilderMeta):
    handlers: Dict[str, type]

    def __init__(self, index: ArchIndex):
        self.index: ArchIndex = index
        self.nodes: List[object] = []
        self._vars: Dict[str, Variable] = {}

    def _dispatch(self, stmt: Statement) -> None:
        handler_cls = type(self).handlers.get(stmt.kind)
        if handler_cls is None:
            raise GenerationError(f"Unsupported statement kind '{stmt.kind}'")
        handler_cls(self, stmt).build()

    def build(self, seq: StatementSeq) -> List[object]:
        for stmt in seq.stmts:
            self._dispatch(stmt)
        return self.nodes

    def variable(self, name: str, width: int) -> Variable:
        if name in self._vars:
            return self._vars[name]
        var = Variable(name, width)
        self._vars[name] = var
        return var

    def resolve_var(self, name: str) -> Variable:
        return self._vars[name]

    @register(StmtInput.kind)
    class Input(StmtHandler):
        def build(self) -> None:
            em = self.builder
            out = self.stmt.outputs[0]
            var = em.variable(out, self.stmt.outputs_types[0])
            em.nodes.append(InputAssign(var, MACH_INST))

    @register(StmtConst.kind)
    class Const(StmtHandler):
        def build(self) -> None:
            em = self.builder
            out = self.stmt.outputs[0]
            const = Constant(out, self.stmt.outputs_types[0], self.stmt.specifier)
            em._vars[out] = const
            em.nodes.append(const)

    @register(StmtOp.kind)
    class Op(StmtHandler):
        def build(self) -> None:
            em = self.builder
            out = self.stmt.outputs[0]
            var = em.variable(out, self.stmt.outputs_types[0])
            inputs = [em.resolve_var(a) for a in self.stmt.inputs]
            op = em.index.op[self.stmt.specifier]
            em.nodes.append(OpAssign(var, op, inputs))


class SemanticBuilder(CodeBuilder):
    def __init__(self, index: ArchIndex, insn: LiraInstruction, interfaces):
        super().__init__(index)
        self.insn: LiraInstruction = insn
        self.interfaces = interfaces
        self.read_operands: List[str] = []
        self.write_operands: List[str] = []
        self.has_mem: bool = False
        self.regs: List[Register] = []

    def _scan(self) -> None:
        seq = self.insn.semantic
        for stmt in seq.stmts:
            scan_fn = getattr(self, f"_scan_{stmt.kind}", None)
            if scan_fn is not None:
                scan_fn(stmt)

    def _scan_read(self, stmt: Statement) -> None:
        producer = stmt.input(0, self.insn.semantic)
        idx = int(producer.specifier)
        self.read_operands.append(self.insn.operand_names[idx])

    def _scan_write(self, stmt: Statement) -> None:
        producer = stmt.input(0, self.insn.semantic)
        idx = int(producer.specifier)
        self.write_operands.append(self.insn.operand_names[idx])

    def _scan_env(self, stmt: Statement) -> None:
        interface = self.interfaces[stmt.specifier]
        if interface is not None and interface.has_mem:
            self.has_mem = True

    def _build_regs(self) -> None:
        for idx, (operand, snip_name) in enumerate(
            zip(self.insn.operand_names, self.insn.encoding.decode)
        ):
            src_pos = (
                self.read_operands.index(operand)
                if operand in self.read_operands
                else None
            )
            dst_pos = (
                self.write_operands.index(operand)
                if operand in self.write_operands
                else None
            )
            reg = Register(
                operand,
                self.insn.operand_sizes[idx],
                self.index,
                self.index.snippet[snip_name],
                src_pos,
                dst_pos,
            )
            self.regs.append(reg)

        for stmt in self.insn.semantic.stmts:
            if stmt.kind == StmtInput.kind:
                self._vars[stmt.outputs[0]] = self.regs[int(stmt.specifier)]

    def build(self, seq: StatementSeq) -> List[object]:
        self._scan()
        self._build_regs()
        return super().build(seq)

    @register(StmtInput.kind)
    class Noop(StmtHandler):
        def build(self) -> None:
            pass

    @register(StmtRead.kind)
    class Read(StmtHandler):
        def build(self) -> None:
            em = self.builder
            producer = self.stmt.input(0, em.insn.semantic)
            reg = cast(Register, em.resolve_var(producer.outputs[0]))
            out = self.stmt.outputs[0]
            var = em.variable(out, self.stmt.outputs_types[0])
            em.nodes.append(ReadReg(reg, var))

    @register(StmtWrite.kind)
    class Write(StmtHandler):
        def build(self) -> None:
            em = self.builder
            producer = self.stmt.input(0, em.insn.semantic)
            reg = cast(Register, em.resolve_var(producer.outputs[0]))
            val = em.resolve_var(self.stmt.inputs[1])
            em.nodes.append(WriteReg(reg, val))

    @register(StmtEnv.kind)
    class Env(StmtHandler):
        def build(self) -> None:
            em = self.builder
            func = em.index.env[self.stmt.specifier]
            interface = em.interfaces[self.stmt.specifier]

            if interface is None:
                raise GenerationError(
                    f"{em.insn.name}: env '{func.name}' is not supported yet"
                )

            width = self.stmt.outputs_types[0]
            addr = em.resolve_var(self.stmt.inputs[0])
            out = self.stmt.outputs[0]
            data = em.variable(out, width)
            em.nodes.append(ReadMem(data, addr, interface))


class ConstraintBuilder(CodeBuilder):
    @register(StmtOutput.kind)
    class Output(StmtHandler):
        def build(self) -> None:
            em = self.builder
            val = em.resolve_var(self.stmt.inputs[0])
            em.nodes.append(Return(val))


class DecodeBuilder(CodeBuilder):
    def __init__(self, index: ArchIndex, operand: Operand):
        super().__init__(index)
        self.operand: Operand = operand

    @register(StmtOutput.kind)
    class Output(StmtHandler):
        def build(self) -> None:
            em = self.builder
            val = em.resolve_var(self.stmt.inputs[0])
            em.nodes.append(MemberAssign(em.operand, val))

# gen_py/cpp_gen.py — LIRA IR Statement → C++ translation.

from typing import Dict, List, Optional

from lira.ir import StatementSeq, Statement
from lira.ir_ops import BaseOp
from lira.arch import Operation

from cpp_ops import gen_type


class OpRegistry:
    _ops: Dict[str, Operation] = {}

    @classmethod
    def set_ops(cls, ops: Dict[str, Operation]) -> None:
        cls._ops = ops

    @classmethod
    def lookup(cls, name: str) -> Operation:
        if name not in cls._ops:
            raise KeyError(f"Unknown operation: {name}")
        return cls._ops[name]


class StmtEmitter:
    def __init__(self, translator: "Translator") -> None:
        self._t = translator

    @property
    def stmt(self) -> Statement:
        return self._t.current_stmt

    def emit(self, line: str) -> None:
        self._t.emit(line)

    def indent(self, fn):
        self._t.indent(fn)

    @property
    def context(self):
        return self._t.context

    def resolve_var(self, name: str) -> str:
        return self._t.resolve_var(name, self.stmt)

    def declare(self, name: str, width: int) -> None:
        self._t.declare_var(name, width)

    def var_width(self, name: str) -> Optional[int]:
        return self._t.var_width(name)

    def emit_code(self) -> None:
        raise NotImplementedError


class OpEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        out = s.outputs[0]
        self.declare(out, s.outputs_types[0])
        inputs = [self.resolve_var(i) for i in s.inputs]
        op = OpRegistry.lookup(s.specifier)

        if op.semantic_base == BaseOp.SELECT:
            self.emit(f"{out} = {inputs[0]} ? {inputs[1]} : {inputs[2]};")
        elif op.semantic_func:
            self.emit(f"{out} = {op.semantic_func}({', '.join(inputs)});")
        else:
            self.emit(f"{out} = {op.name}({', '.join(inputs)});")


class ConstEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        out = s.outputs[0]
        width = s.outputs_types[0]
        if self._t.var_declared(out):
            return
        self.emit(f"{gen_type(width)} {out} = {s.specifier};")
        self._t.register_var(out, width)


class DynConstEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        out = s.outputs[0]
        width = s.outputs_types[0]
        if self._t.var_declared(out):
            return
        self.emit(f"{gen_type(width)} {out} = {s.specifier};")
        self._t.register_var(out, width)


class ReadEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        rf = s.specifier
        idx = self.resolve_var(s.inputs[0])
        out = s.outputs[0]
        width = s.outputs_types[0]
        self.declare(out, width)
        if self.context == "execute":
            self.emit(f"{out} = cpu.get{rf}<{gen_type(width)}>({idx});")
        else:
            self.emit(f"{out} = 0;")


class WriteEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        rf = s.specifier
        idx = self.resolve_var(s.inputs[0])
        val = self.resolve_var(s.inputs[1])
        if self.context == "execute":
            self.emit(f"cpu.set{rf}({idx}, {val});")


class EnvEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        func = s.specifier
        inputs = [self.resolve_var(i) for i in s.inputs]
        outputs = s.outputs
        out_types = s.outputs_types

        func = self._resolve_env_func(func, out_types, inputs)

        if self.context != "execute":
            return

        if not outputs:
            self.emit(f"cpu.{func}({', '.join(inputs)});")
        elif len(outputs) == 1:
            out = outputs[0]
            self.declare(out, out_types[0])
            self.emit(f"{out} = cpu.{func}({', '.join(inputs)});")
        else:
            for i, out in enumerate(outputs):
                self.declare(out, out_types[i])
            self.emit(f"std::tie({', '.join(outputs)}) = cpu.{func}({', '.join(inputs)});")

    def _resolve_env_func(self, func: str, out_types: List[int],
                          inputs: List[str]) -> str:
        if func == "readMem" and len(out_types) == 1:
            return f"readMem{out_types[0]}"
        if func == "writeMem" and len(inputs) >= 2:
            width = self.var_width(self.stmt.inputs[1]) or 32
            return f"writeMem{width}"
        return func


class CondEnvEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        cond = self.resolve_var(s.inputs[0])
        num_out = len(s.outputs)
        in_args = [self.resolve_var(i) for i in s.inputs[1:len(s.inputs) - num_out]]
        on_false = [self.resolve_var(i) for i in s.inputs[len(s.inputs) - num_out:]]
        func = s.specifier

        self.emit(f"if ({cond}) {{")
        self.indent(lambda: self._emit_cond_true(s, func, in_args))
        self.emit("} else {")
        self.indent(lambda: self._emit_cond_false(s, on_false))
        self.emit("}")

    def _emit_cond_true(self, st: Statement, func: str,
                        inputs: List[str]) -> None:
        for i, out in enumerate(st.outputs):
            self.declare(out, st.outputs_types[i])
            self.emit(f"{out} = cpu.{func}({', '.join(inputs)});")

    def _emit_cond_false(self, st: Statement,
                         on_false: List[str]) -> None:
        for i, out in enumerate(st.outputs):
            self.emit(f"{out} = {on_false[i]};")


class InputEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        idx = int(s.specifier)
        out = s.outputs[0]
        width = s.outputs_types[0]
        self.declare(out, width)
        if self.context in ("decode", "snippet"):
            self.emit(f"{out} = raw_insn;")
        else:
            self.emit(f"{out} = insn.operand{idx};")


class OutputEmitter(StmtEmitter):
    def emit_code(self) -> None:
        s = self.stmt
        val = self.resolve_var(s.inputs[0])
        idx = int(s.specifier)
        if self.context == "snippet":
            self.emit(f"return {val};")
        else:
            self.emit(f"insn.operand{idx} = {val};")


EMITTER_MAP = {
    "op":   OpEmitter,
    "const":     ConstEmitter,
    "dyn_const": DynConstEmitter,
    "read":      ReadEmitter,
    "write":     WriteEmitter,
    "env":       EnvEmitter,
    "cond_env":  CondEnvEmitter,
    "input":     InputEmitter,
    "output":    OutputEmitter,
}


class Translator:
    def __init__(self, seq: StatementSeq, context: str = "execute",
                 indent: int = 0) -> None:
        self._seq = seq
        self.context = context
        self._indent = indent
        self._output: List[str] = []
        self._var_widths: Dict[str, int] = {}
        self.current_stmt: Optional[Statement] = None

    def translate(self) -> str:
        for stmt in self._seq.stmts:
            self._translate_stmt(stmt)
        return "\n".join(self._output)

    def declare_var(self, name: str, width: int) -> None:
        if self.var_declared(name):
            return
        self.emit(f"{gen_type(width)} {name};")
        self.register_var(name, width)

    def var_declared(self, name: str) -> bool:
        return name in self._var_widths

    def var_width(self, name: str) -> Optional[int]:
        return self._var_widths.get(name)

    def register_var(self, name: str, width: int) -> None:
        self._var_widths[name] = width

    def resolve_var(self, name: str, stmt: Statement) -> str:
        if self.var_declared(name):
            return name

        if name.startswith("_t"):
            width = 32
            if stmt.outputs_types:
                width = stmt.outputs_types[0]
            self.emit(f"{gen_type(width)} {name} = 0;")
            self.register_var(name, width)
            return name
        raise ValueError(f"Unknown variable {name} in {stmt}")

    def emit(self, line: str) -> None:
        self._output.append(" " * self._indent + line)

    def indent(self, fn) -> None:
        self._indent += 2
        fn()
        self._indent -= 2

    def _translate_stmt(self, stmt: Statement) -> None:
        emitter_cls = EMITTER_MAP[stmt.kind]
        if emitter_cls is None:
            raise ValueError(f"Unknown statement kind: {stmt.kind}")
        self.current_stmt = stmt
        emitter_cls(self).emit_code()

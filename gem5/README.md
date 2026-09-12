# gem5 ISA Generator

Gem5 ISA DSL code generator from LIRA IR.

## Usage

The build is driven by scons (from the gem5 repository root):

```bash
scons build/RISCV/gem5.opt --enable-protea -j 16
```

This creates `build/protea-venv` (with the `lira-ir` python package
installed), builds the Protea LIRA IR and regenerates the gem5 ISA DSL
artifacts before compiling them.

The generator can also be run manually from the repository root:

```bash
build/protea-venv/bin/python gem5/main.py \
    --ir-path build/Default-Release/lib/lira.yaml
```

Generates:

| File                                      | Content                                                               |
| ----------------------------------------- | --------------------------------------------------------------------- |
| `<output>/isa/decoder_protea.isa`       | Decode block +`ProteaInst` instantiations (constructor + semantics) |
| `<output>/insts/protea_decoder.hh/.cc`  | `Opcode` enum + `decodeInstr()` dispatch                          |
| `<output>/insts/protea_base_ops.hh/.cc` | Base operation helper functions                                       |

## Layout

| Module                                | Responsibility                                                                                                        |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `main.py`                           | CLI driver                                                                                                            |
| `driver.py`                         | LIRA IR loading                                                                                                       |
| `Generic/config.py`                 | `IConfig`: target configuration interface (supported instructions, output paths)                                      |
| `Generic/builders.py`             | LIRA IR processing: `CodeBuilder` + `DecodeBuilder`/`SemanticBuilder`/`ConstraintBuilder`, statement handlers         |
| `Generic/instruction.py`            | Per-instruction model (container of generated nodes and registers)                                                    |
| `Generic/operand.py`                | `Variable`/`Operand`/`Register` models with C++ rendering                                                             |
| `Generic/nodes.py`                  | Code nodes (`render_nodes`)                                                                                           |
| `Generic/isa_emitter.py`            | `decoder_protea.isa` emission                                                                                         |
| `Target/RISC_V/config.py`           | `RiscvConfig`: RISC-V configuration and artifact generation                                                           |
| `Target/RISC_V/decoder_emitter.py`  | RISC-V C++ decoder module emission                                                                                    |
| `Target/RISC_V/base_ops_emitter.py` | RISC-V C++ base operations module emission                                                                            |

# Plod

**Plod** (Protea Language fOr Devices) is a small language for describing peripheral devices. It combines a declarative register-bank description with an imperative body language, and compiles to C++ headers for the gem5 simulator.

Plod is a Ruby-hosted DSL: device descriptions are ordinary Ruby files evaluated by the `plod` toolchain. No Ruby knowledge beyond the keywords below is required to write a device.

## Toolchain

```
device.rb ──plod check──▶ diagnostics (file:line)
          ──plod ir─────▶ program IR (YAML/JSON)
          ──plod build──▶ C++ header (target-dependent)
```

All commands take one or more device files:

```bash
bundle exec exe/plod check lib/Devices/uart8250.rb
bundle exec exe/plod ir lib/Devices/clint.rb -o clint_ir.yaml
bundle exec exe/plod build lib/Devices/uart8250.rb -d Uart8250 -o Uart8250.hh
bundle exec exe/plod targets            # list target descriptors
```

`check` runs parsing and full type checking; `build` refuses to generate code if checking fails. Exit code is non-zero when errors are found.

## Language

### Files, devices and components

A file is a sequence of top-level declarations:

- `Device(:name) { ... }` — a peripheral device: registers plus fields, constants, enums, methods, lambdas and a constructor.
- `Struct(:name) { ... }` — a concrete struct with fields and methods.
- `AbstractStruct(:name) { ... }` — an environment-provided type: only signatures, no bodies. Calls on abstract members are late-bound (checked as warnings, resolved by the target at link time).
- `AbstractObject(:name, Type())` — a global environment object (e.g. `ns`).
- `AbstractMethod(:name, ...)` — a global environment function (e.g. `curTick`).

Inside a device:

- `Register(:name, size:, offset:, type:, seqn:) { ... }` — a bank register. `size` is in bytes, `offset` in bytes from the bank base, `type` is `:ro`, `:wo` or `:rw` (default), `seqn` declares an arrayed bank (`name.at(i)` / `name.set(i, v)`).
- `Field(:name, Type, *init)` / `AbstractField(:name, Type)` — device state members; abstract fields are provided by the environment.
- `Const(:name, Type, value)`, `Enum(:name) { A(0) ... }`.
- `Method(:name, arg: Type, ..., ret: Type) { ... }` and `AbstractMethod` for environment calls.
- `Constructor(params: Ref(Params())) { Init(:field, expr) ... Body { ... } }`.
- `Lambda(arg: Type, ...) { ... }` — anonymous callbacks, usable as field initializers.

Inside a register:

- `field :name, lsb` or `field :name, lo..hi` — bit fields (also accepted: `[lo, hi]`).
- `enableIf { lcr.dlab == 0 }` — dispatch predicate.
- `Method(:read, ret: B8()) { ... }` / `Method(:write, data: B8()) { ... }` — access semantics. If omitted, a default is generated. The checker enforces: no `write` on `:ro`, no `read` on `:wo`, `read` returns the register width, `write` takes `data` of the register width.

### Types

`B<n>()` bit vectors, `Int()`, `Bool()`, `String()`, `Auto()`, `Array(elem, size)`, `Ptr(t)`, `Ref(t)`, `Lambda`, and any declared `Struct`/`AbstractStruct` by name.

### Bodies

Statements: `Let :x, T, expr`, `Var :x, T`, `x[] = v` (assignment), `If(c) { }.Elseif(c) { }.Else { }`, `For(iter: :i, init: 0, to: n) { }`, `Return [expr]`, `Cast(T, v)`, `GetPtr(v)`.

Expressions: arithmetic and bitwise operators, comparisons, `reg.field` bit access, `recv.method(args)`, `container.at(i)`, `container.set(i, v)`, `enum.KEY`, and calls to device methods and abstract functions.

`this` inside a register method denotes the whole register; bit fields are assignable (`dlab[] = 1`).

## Checking

`plod check` reports errors with file and line:

- unknown names, fields, methods or enum values
- argument count/type mismatches, return type mismatches
- register rule violations (ro/wo, widths, overlapping fields, oversized fields)
- constant overflow, duplicate member names
- warnings for late-bound calls on abstract types and overlapping register ranges

## Targets

Backend boilerplate lives in `targets/*.yaml` (base class, includes, port/init bodies, environment rewrites such as `ns -> sim_clock::as_int::ns`). A target declares which devices it supports; `plod build` picks one automatically or takes `--target`.

## Tests

```bash
bundle exec rake test            # core, frontend, sema, backend, API contract
bundle exec rake golden:update   # refresh golden C++ headers after intentional changes
```

Generated headers are also compiled (`g++ -fsyntax-only`) against the stubs in `tests/support/gem5_stub/`.

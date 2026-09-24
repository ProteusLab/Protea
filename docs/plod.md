# Plod

**Plod** (Protea Language fOr Devices) is a small language for describing peripheral devices. It combines a declarative register-bank description with an imperative body language, and compiles to C++ headers for the gem5 simulator.

Devices are written in the C-like `.pld` language and translated by `plod translate` into a Ruby-hosted DSL (`device.rb`), which is what the rest of the toolchain consumes. Hand-editing the `.rb` files is possible but discouraged for translated devices — edit the `.pld` and re-translate.

## Toolchain

```
device.pld ──plod translate──▶ device.rb ──plod check──▶ diagnostics (file:line)
                                       ──plod ir─────▶ program IR (YAML/JSON)
                                       ──plod build──▶ C++ header (target-dependent)
```

All commands take one or more device files:

```bash
bundle exec exe/plod translate lib/Devices/uart8250.pld   # .pld -> sibling .rb (-o - for stdout)
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

- `Register(:name, Size:, Offset:, Type:, Seqn:) { ... }` — a bank register. `Size` is in bytes, `Offset` in bytes from the bank base, `Type` is `:ro`, `:wo` or `:rw` (default), `Seqn` declares an arrayed bank. The properties can also be declared inside the block as statements: `Size 0x1`, `Offset 0x0`, `Type :ro`, `Seqn 0x100`. Outside the register, `name.at(i)` / `name.set(i, v)` address element `i`, and calling one of its methods (`name.m(i, ...)`) takes the element index as the last argument.
- `Field(:name, Type, *init)` / `AbstractField(:name, Type)` — device state members; abstract fields are provided by the environment.
- `Const(:name, Type, value)`, `Enum(:name) { A(0) ... }`.
- `Method(:name, arg: Type, ..., Ret: Type) { ... }` and `AbstractMethod` for environment calls.
- `Constructor(params: Ref(Params())) { Init(:field, expr) ... Body { ... } }`.
- `Lambda(arg: Type, ...) { ... }` — anonymous callbacks, usable as field initializers.

Inside a register:

- `Field :name, lsb` or `Field :name, [lo, hi]` — bit fields (a `lo..hi` range also works).
- `EnableIf { lcr.dlab == 0 }` — dispatch predicate.
- `Method(:read, Ret: B8()) { ... }` / `Method(:write, data: B8()) { ... }` — access semantics. `Ret:` is reserved (as are `Size:`, `Offset:`, `Type:`, `Seqn:`, `Iter:`, `Init:`, `To:`); user-declared names (`data:` here) start lowercase. A trivial full-element access needs no explicit method: if `read`/`write` is omitted, an implicit implementation is generated — for a banked register `name_read` returns `name[cid]` and `name_write(data)` performs `name[cid] = data`, for a scalar register the same without indexing. Only non-trivial semantics (masking, side effects, field packing) require an explicit `Method`. The checker enforces: no `write` on `:ro`, no `read` on `:wo`, `read` returns the register width, `write` takes `data` of the register width.

Inside a `seqn` register, the bank index is implicit:

- Methods must not declare an index parameter; the generated C++ signature gains a hidden trailing `uint64_t cid`.
- `Self` denotes the addressed element (`Bits` of the register width): read it as a value (`Return Self`) and assign it with `Self[] = v`. It cannot be indexed.
- Bare bit-field names (`msipb[] = 1`) act on the addressed element, and the raw index is available as the read-only binding `cid` (e.g. `system.threads.at(cid)`).
- Calling a sibling method of the same register omits the index — it is forwarded automatically (`update()` inside `write`). `this` still denotes the whole bank and, as such, may not be read, assigned or called as a value inside a banked register's methods.

### Types

`B<n>()` bit vectors, `Int()`, `Bool()`, `String()`, `Auto()`, `Array(elem, size)`, `Ptr(t)`, `Ref(t)`, `Lambda`, and any declared `Struct`/`AbstractStruct` by name.

### Bodies

Statements: `Let :x, T, expr`, `Var :x, T`, `x[] = v` (assignment), `If(c) { }` with sibling `Elseif(c) { }` / `Else { }` blocks, `For(Iter: :i, Init: 0, To: n) { }`, `Return [expr]`, `Cast(T, v)`, `GetPtr(v)`.

Expressions: arithmetic and bitwise operators, comparisons, `reg.field` bit access, `recv.method(args)`, `container.at(i)`, `container.set(i, v)`, `enum.KEY`, and calls to device methods and abstract functions.

`this` inside a register method denotes the whole register; bit fields are assignable (`dlab[] = 1`).

## The .pld language

`.pld` is a C-flavoured surface syntax for the same language. `lib/Devices/uart8250.pld` is the reference example. The translator is forgiving about style: `//` and `#` comments, statements terminated by `;` or a newline, `x*`/`&x` pointer notation.

```c
abstract struct SerialDevice {
    bool dataAvailable();
    b8 readData();
}

device Uart8250 {
    enum InterruptIds { Rx: 2, Tx: 1 }
    const b8 rx_int = 1;

    abstract schedule(Event* event, Tick when);
    abstract int status;

    void dataAvailable() {
        if (ier.rda()) {
            platform.postConsoleInt();
            status |= rx_int;
        }
    }

    register ier: size(0x1), offset(0x1) {
        enableIf { lcr.dlab == 0 }
        field rda(0x0)
        field zero(0x4, 0x7)

        void write(b8 data) {
            self = data;
        }
    }
}
```

Translation rules worth knowing:

- The `.pld` keywords keep their C-like lowercase spelling (`device`, `register`, `field`, `enableIf`, `if`, `else`, `return`); the translator emits the PascalCase Ruby DSL (`Device`, `Register`, `Field`, `EnableIf`, `If`, ...).
- Register props and return types map to capitalized kwargs: `size(0x1)` → `Size: 0x1`, `type(ro)` → `Type: :ro`, `b8 read()` → `Method(:read, Ret: B8())`.
- `self` becomes `this`; compound assignments desugar (`status |= x` → `status[] = status | x`).
- `&x` becomes `GetPtr(x)`; `static_cast<T>(e)` becomes `Cast(T(), e)`; `[]{ ... }` becomes a `Lambda`.
- Enum references lower the enum name's first letter: `InterruptIds.Rx` → `interruptIds.Rx`.
- Hex spellings are preserved (`0x1` stays `0x1`), and blank lines from the source are kept.

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

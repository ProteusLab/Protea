# Plod

**Plod** (Protea Language fOr Devices) is a small language for describing peripheral devices. It combines a declarative register-bank description with an imperative body language, and compiles to C++ headers for the gem5 simulator.

Devices use a Ruby-hosted DSL (`device.rb`), which is consumed directly by the toolchain. The optional C-like `.pld` frontend translates to that DSL. For translated devices such as Uart8250, edit the `.pld` source; the seven RISC-V/x86 ports below are maintained directly in Ruby and include Ruby-only declarations.

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

## RISC-V PLIC and legacy VirtIO MMIO

`lib/Devices/plic.rb` and `lib/Devices/vio_mmio.rb` port gem5's RISC-V
PLIC and legacy (version 1) VirtIO MMIO transport. These Ruby descriptions
are authoritative, and the target descriptors select the C++ backend:

```bash
bundle exec exe/plod check lib/Devices/plic.rb lib/Devices/vio_mmio.rb
bundle exec exe/plod build lib/Devices/plic.rb -d Plic -o Plic.hh
bundle exec exe/plod build lib/Devices/vio_mmio.rb -d MmioVirtIO -o MmioVirtIO.hh
cmake --build build/Default-Debug --target protea_devgen protea_devirgen
```

The generated classes are `gem5::Plic` (including the `PlicBase` interface)
and `gem5::RiscvISA::MmioVirtIO`, using `PlicParams` and
`RiscvMmioVirtIOParams`. PLIC retains parameterized sources and contexts,
hart configuration, delayed output events, atomic/partial register accesses,
and the original checkpoint keys. VirtIO delegates configuration packets to
`VirtIODeviceBase`, and inherits the interrupt-device framework and its
checkpoint behavior. The gem5 Python SimObjects and VirtIO device models are
external environment interfaces; the port does not replace them.

Compatibility follows the frozen local gem5 source fixtures in
`tests/support/gem5_reference`. This includes odd numeric context counts
forming complete M/S pairs, unmasked source-zero state, strict completion
assertions, and the VirtIO guest-feature selector reading the host selector.
PLIC also preserves zero-length padding-register insertion: at full banks,
these can shadow the next register. Diagnostic severity and conditions are
retained; message wording is simplified and gem5 debug tracing is not emitted.

The runtime suite compiles the original and generated devices against the same
controllable packet/event/IRQ/checkpoint environment and the original gem5
`RegisterBankLE`. It compares observable results and checkpoint contents,
including deterministic randomized operations at source-word boundaries.
This validation does not install the headers into an external gem5 checkout
or run a full-system simulation.

### Constructors, collections and loops

A constructor can initialize fields before running its body. `T&` denotes a
reference; method suffix `const` is preserved in generated C++:

```c
constructor(Params& params) : count(params.count) {
    values.resize(count, 0);
}

void serialize(CheckpointOut& cp) const {
    // Calls to declared environment checkpoint functions go here.
}
```

`vector<T>` maps to `std::vector<T>`, and `map<K,V>` to `std::map<K,V>`.
Nested types are supported. Both provide `size()`, `empty()`, `at(index)` and
`clear()`. Vectors additionally provide `resize(count[, initialValue])`,
`push(value)` and `set(index, value)`. Maps provide `put(key, value)` (replace
an existing value), `firstKey()`, `firstValue()` (a copy) and `eraseFirst()`.
The first-entry methods require a nonempty map. These calls are type checked;
references to concrete structures in collections are emitted recursively.
The Ruby DSL spellings are `Vector(T())` and `Map(K(), V())`.

Loops use `for (int i = start; i < end; ++i) { ... }` (or `i++`) and lower to
`For(Iter: :i, Init: start, To: end)`. This syntax supports ascending unit steps.

### Runtime register layouts and packet methods

A `layout` specifies counts and byte strides evaluated during initialization:

```c
register enable: size(4), offset(0x2000), window(0x1fe000) {
    layout {
        repeat(contextConfigs.size(), 0x80);
        repeat(nSrc32, 4);
    }
    void write(b32 data) {
        self = data;
        // cid is the flattened index; the innermost repeat varies fastest.
    }
}
```

In Ruby this is `Layout { Repeat(count, stride); ... }` inside the register.
It cannot be combined with `Seqn`. `self` translates to `Self` in a banked
register and denotes the addressed element. The optional `window(bytes)` /
`Window:` reserves trailing padding to a fixed end address. Repeated groups
are padded to their stride. Counts may be zero; invalid counts, strides,
overlaps and window overflow are rejected during checking or initialization.

Targets select `register_backend: gem5_bank` for a generated `RegisterBankLE`
with register callbacks and reserved gaps. Its generated `initRegisters()`,
`readRegisters(Packet*)` and `writeRegisters(Packet*)` helpers are available to
device-defined lifecycle and packet methods. Register `at`/`set` and `Self`
access the backing value directly; MMIO invokes access callbacks. The target
option `preserve_zero_padding: true` retains zero-size padding entries and
stable insertion order for source compatibility; the default omits them.

`register_backend: word` provides exact-offset `readRegister(offset)` and
`writeRegister(offset, data)` dispatch for scalar 32-bit registers. Devices
supply `readUnknown(offset)` and `writeUnknown(offset, data)` for rejected
accesses, and packet methods for width checks and configuration forwarding.

Concrete device methods named `read`, `write`, `getAddrRanges`, `getPort`,
`init`, `serialize` or `unserialize` replace the corresponding generated defaults. Target metadata
also supports `namespace` (default `gem5`), `params_type`, `inherited_fields`
(which remain available to checking without being redeclared), and
`declarations` for framework interfaces, and `public_declarations` for native
public C++ type aliases or BitUnion definitions required by platform callers. `env` maps types and function calls,
and can map qualified member names such as `Packet.getWord` to
`getLE<uint32_t>`. Existing targets retain the `legacy` register backend.


## X86 i8 devices

The complete `src/dev/x86/i8*` device set from the same gem5 reference is
ported in `lib/Devices`: `i8042.rb`, `i82094aa.rb`, `i8237.rb`,
`i8254.rb` and `i8259.rb`. Edit these Ruby descriptions directly.
Build, device IR and golden-header targets include all five. The existing
`.pld` files for these five devices, PLIC and VirtIO are historical snapshots;
they remain untouched and must not be used to regenerate the Ruby descriptions.

```bash
bundle exec exe/plod check lib/Devices/i8*.rb
bundle exec exe/plod build lib/Devices/i8042.rb -d I8042 -o I8042.hh
bundle exec exe/plod build lib/Devices/i82094aa.rb -d I82094AA -o I82094AA.hh
bundle exec exe/plod build lib/Devices/i8237.rb -d I8237 -o I8237.hh
bundle exec exe/plod build lib/Devices/i8254.rb -d I8254 -o I8254.hh
bundle exec exe/plod build lib/Devices/i8259.rb -d I8259 -o I8259.hh
```

Targets `gem5_i8042`, `gem5_i82094aa`, `gem5_i8237`, `gem5_i8254` and
`gem5_i8259` emit the original `gem5::X86ISA` class names and Params types.
I8042 inherits `PioDevice`; the others inherit `BasicPioDevice`. Public MMIO,
port names, interrupt-pin entry points, PIT forwarding methods and original
checkpoint keys are retained. The public `I82094AA::RedirTableEntry` BitUnion
and `I8237::Register` alias remain available to platform code, including
`Pc::init()`. Generated headers replace the device classes;
do not compile them alongside their original device definitions.

| Device | Preserved behavior |
| --- | --- |
| I8042 | Separate data/status ports, command state, controller replies, keyboard-first prefetch, PS/2 forwarding, mouse/keyboard interrupt pulses and checkpoints. |
| I82094AA | Selector/window MMIO, redirection masks, physical/logical destinations, lowest-priority rotation, edge suppression, atomic/timing ExtInt acknowledgements and checkpoints. |
| I8237 | Native byte register bank, mask/request controls, reset, unimplemented DMA/channel failures and the source's mask-only checkpoint. |
| I8254 | Counter/control MMIO, shared Intel8254Timer engine, counter-zero interrupt pulses, direct counter APIs, startup and timer checkpoints. |
| I8259 | ICW/OCW initialization, masks, priority, EOI, cascade/INTA, pin-edge tracking and checkpoints. |

I8042 declares four one-byte PLOD registers, following the
[IBM technical reference, pages 4-9–4-10](https://www.ardent-tool.com/docs/pdf/ps2_50-60_techref_ch4a_system_board_io_controllers_keyboard.pdf):

| Register | Offset | Access | Conventional port |
| --- | --- | --- | --- |
| `output_buffer` | `0` | Read-only | `0x60` |
| `input_buffer` | `0` | Write-only | `0x60` |
| `status` | `4` | Read-only | `0x64` |
| `command` | `4` | Write-only | `0x64` |

Register methods implement buffer consumption, data forwarding, status readback
and command handling. Packet adapters validate byte accesses and invoke the
register methods using the independently configured `data_port` and
`command_port` addresses, including addresses restored from checkpoints.
The offsets describe the conventional layout; they do not constrain port spacing.

The ports preserve source quirks: I8259 chooses the highest numbered pending
line and skips ICW4 after ICW2 in single mode; masked requests are discarded
at signal time. I8042 disable bits retain their original behavior. I8237
still models only the source's partial DMA functionality. I82094AA retains
the source's inclusive redirection-register bound; accessing selector `0x40`
indexes beyond the 24-entry table and remains undefined behavior. Differential
tests exercise valid selectors and defined error paths, excluding that
undefined access. Debug tracing and exact diagnostic wording are not ported;
warning/fatal/panic/assert conditions and severities are preserved.

The C++ boilerplate binds framework APIs: port lookup/allocation, a callback
bridge to the shared PIT engine and binding a message by value for an
outstanding interrupt acknowledgement. Device state machines, routing,
responses and checkpoint state are described in PLOD. The gem5 checkout and Python
SimObjects are unchanged; full-system gem5 integration is a separate step.

`register_backend: custom` is available for devices whose packet methods
implement address decoding directly or select a generated `packet` policy.
Without a policy, both `read` and `write` must be defined in PLOD.
Registers retain typed storage and generated access methods, and
`getAddrRanges` can describe discontiguous ports or INTA ranges. Framework
checkpoint methods remain inherited unless the device defines its own or
declares a `Checkpoint` block.

### Generated packet adapters

The existing register dispatch and packet emitters also accept a structured
`packet` section in target YAML. All seven ports use this generation path;
they contain no device-level packet `read`/`write` methods. A policy conflicts
with handwritten packet methods.

```yaml
packet:
  latency: latency
  width: 1
  check: assert
  response: atomic
```

`latency` is a nonnegative integer or a numeric state member name. Omit
`width` for native `gem5_bank` partial/spanning access; direct dispatch requires
a width of 1, 2, 4 or 8 bytes matching each register. `check` is `assert`
(default) or `panic`. `response` is `normal` (default, `makeResponse`) or
`atomic` (`makeAtomicResponse`).

`read_response` defaults to `after_payload`; `before_payload` evaluates the
register, creates the response, then assigns the payload. `write_response`
is `after_dispatch` (default) or `before_dispatch`. `match` is `first`
(default) or `all`; `unmapped` is `panic` (default) or `ignore`. Ignored
unmapped reads leave the payload untouched. `denied: warn` warns and returns
zero for write-only reads, or ignores read-only writes; its default is `panic`.
`denied: ignore` leaves forbidden reads unchanged and ignores forbidden writes.
This policy is independent of the unmapped-access policy.
Native banks retain their own register access rules.

`atomic_swap: true` enables the existing read/modify/write packet path.
`after_write: [propagateOutput, updateInt]` invokes declared zero-argument
void device methods after successful writes and before the default response.

A forwarding window runs before width validation, register dispatch and
response creation, leaving the delegated component in charge of the packet:

```yaml
  forward:
    start: 256
    receiver: vio
    read: readConfig
    write: writeConfig
    latency: 0
```

Its methods must be declared as `void (Packet*, b64)`; their offset argument
is relative to `start`. The forwarding latency follows the same rules as
the main latency.

In the Ruby register DSL, `Address { dataPort }` overrides the normal
`pioAddr + Offset` mapping with an absolute bus address evaluated at each
access. For example, I8042's four directional registers use `dataPort` and
`commandPort`, so independently configured or restored addresses work without
rebuilding a bank. Absolute mappings require a packet policy and direct
dispatch; native banks retain relative layouts. `EnableIf` applies to either
mapping. `Address` changes dispatch only; discontiguous mappings also need a
device-defined `getAddrRanges`, as in I8042. Other devices retain existing
range generation.

### Generated checkpoint methods

Ruby-only `Checkpoint` blocks describe saved state once and generate both
gem5 `serialize` and `unserialize`. State selection is explicit; pointers,
callbacks and incidental register-wrapper storage are not automatically saved.

```ruby
Checkpoint {
  Scalar('statusReg', statusReg)
  Array('pinStates', pinStates)
  Repeat(:i, nSrc) {
    Scalar(Literal('priority') + toString(i), priority.at(i))
  }
  AfterRestore(:updateInt)
}
```

`Scalar(key, destination)` accepts numeric, boolean or string storage;
`Array(key, destination)` accepts fixed arrays or vectors of scalar values.
Destinations may be fields, nested struct fields or indexed elements.
Register images use `Repeat` and scalar entries, restoring backing values
directly without calling MMIO methods or triggering access side effects.
`Repeat(index, count)` starts at zero and uses a local index without shadowing.

Ordered maps can retain existing flattened checkpoint keys:

```ruby
OrderedMap(outputQueue, Count: 'n_outputs', CountType: B32(),
           Iter: :i, Key: :tick, Value: :snapshot) {
  Scalar(Literal('output_tick') + toString(i), tick)
  Array(Literal('output_id') + toString(i), snapshot.maxID)
  Array(Literal('output_pri') + toString(i), snapshot.maxPriority)
}
```

Saving visits entries in map order and writes the count after the records.
Restoration reads the count first, builds each record and inserts or replaces
its key without clearing existing map entries. `AfterRestore(*method_names)`
invokes zero-argument void device methods at that point in the restore sequence;
it emits nothing during serialization.

`Delegate(pit, Prefix: 'pit')` delegates to declared
`serialize(prefix, cp) const` / `unserialize(prefix, cp)` component methods.
`Checkpoint { Inherit() }` forwards both methods to the target base class
without adding state; `Inherit()` must be the only entry.

The checker rejects unsupported destinations/types, duplicate static keys,
invalid hooks, procedural statements inside checkpoint blocks, and conflicts
with handwritten checkpoint methods. Existing descriptions without
`Checkpoint` keep their previous checkpoint behavior. These declarations and
`Address` are maintained directly in Ruby; no `.pld` generation is involved.

Device callback fields accept typed parameters:

```cpp
auto callback = [](b32 number) { counterInterrupt(number); };
```

These become `std::function<void(uint32_t)>` members capturing the device.
Arbitrary local captures and return-valued lambdas are not supported. Target
adapters can bind additional callback arguments by value when required by a
framework transport. Pointer equality/inequality with literal zero is checked
as a null test, and abstract `auto` arguments denote a framework-bound value.

`bundle exec rake test` compiles the generated ports and frozen originals in
separate binaries, compares command/register transactions, pulses, interrupt
messages and checkpoint contents, and checks assertion failures. X86 tests
cover all 256 I8042 command bytes, all DMA control bytes, all PIT control
bytes, randomized PIC operations, timer scheduling/restoration and delayed
I/O APIC ExtInt delivery. Both versions use the unmodified native PIT engine;
PS/2 peers, local APICs and interrupt packet transport use controllable stubs.

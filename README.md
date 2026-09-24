Protea: An Architecture Description Language based on Ruby for Learning and Research
====================================================================================

Protea (named after Proteus, the Greek sea god known for his ability to change shape) is an architecture description language (ADL) designed for teaching at ITMO and MIPT. It is built on top of the Ruby programming language, leveraging its flexibility and expressiveness to allow users to easily define and manipulate architectural components.

ProteaIR (Protea Intermediate Representation) doesn't have canonical textual or binary representation. Instead, it is possible to serialize and deserialize it using JSON, YAML, or any other format.

Usage
-----
It is a monorepo managed by [Bundler](https://bundler.io/). To install dependencies, run:

```bash
bundle install
```

So every ruby tool or script can be run using `bundle exec`, for example:

```bash
bundle exec ruby tools/some_tool.rb
```

Device toolchain (Plod)
-----------------------

Devices are described in the C-like `.pld` language and translated into
the Ruby DSL consumed by the `plod` CLI:

```bash
bundle exec exe/plod translate lib/Devices/uart8250.pld # .pld -> .rb (sibling file)
bundle exec exe/plod check lib/Devices/uart8250.rb      # parse + type-check
bundle exec exe/plod ir lib/Devices/clint.rb            # dump IR as YAML/JSON
bundle exec exe/plod build lib/Devices/uart8250.rb \    # generate a gem5-style C++ header
     -d Uart8250 -o Uart8250.hh
bundle exec exe/plod targets                            # list backend targets
```

`lib/Devices/uart8250.rb` is generated from `uart8250.pld`; edit the `.pld`
source and re-run `translate` to change it.

See [docs/plod.md](docs/plod.md) for the language reference.

Tests
-----

```bash
bundle exec rake test            # core, frontend, sema, backend, API contract, header compilation
bundle exec rake golden:update   # refresh golden C++ headers after intentional changes
```


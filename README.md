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

Every ruby tool or script can be run using `bundle exec`.

## SDL
```bash
bundle exec ruby lib/d_ir_gen.rb
```


## ADL
```bash
bundle exec ruby lib/ir_gen.rb
```


Tests
-----

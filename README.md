Protea: An Architecture Description Language based on Ruby for Learning and Research
====================================================================================

Protea (named after Proteus, the Greek sea god known for his ability to change shape) is an architecture description language (ADL) designed for teaching at ITMO and MIPT. It is built on top of the Ruby programming language, leveraging its flexibility and expressiveness to allow users to easily define and manipulate architectural components.

ProteaIR (Protea Intermediate Representation) doesn't have canonical textual or binary representation. Instead, it is possible to serialize and deserialize it using JSON, YAML, or any other format.

Building Protea
-----
```bash
cmake -S . -B build -G <generator> [options]
```

Some common options:
1) -DPROTEA_BUILD_TESTS=BOOL - An option to enable tests. Tests can be run using ctests
2) -DTARGET_NAME_TOOLCHAIN_DIR="..." - A path to target's toolchain dir
3) -DQEMU_PATH="..." - A path to qemu executable

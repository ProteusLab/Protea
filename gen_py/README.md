# gen_py

C++ code generator from LIRA IR (`lira.yaml`).

## Install

```bash
# LIRA Python library (required)
pip install -e /path/to/LIRA/python
```

## Smoke test

```bash
python3 gen_py/main.py --lira lira.yaml --output out/
```

Generates:

| File | Content |
|---|---|
| `out/base_ops.h` | `static inline` C++ functions for base operations |
| `out/snippets.h` | Decode/constraint snippet functions |
| `out/exec_funcs.cc` | Per-instruction execute functions |

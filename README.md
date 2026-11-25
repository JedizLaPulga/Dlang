# Dlang

A workspace and repository dedicated to modern **D programming language** projects, built from the ground up with idiomatic D2 and the official **Phobos** standard library.

---

## Core Engineering Principles

Every project in this repository adheres to the following standards throughout its lifetime:

1. **Official Specification Grounding**
   All language constructs, attributes, templates, ranges, and memory-safety patterns are cross-referenced against the [D Language Specification](https://dlang.org/spec/spec.html) and the [Phobos Library Reference](https://dlang.org/phobos/index.html) at [dlang.org](https://dlang.org).
2. **Full Phobos — Zero Unapproved External Dependencies**
   Every feature is implemented exclusively using the D standard library (`std.*` and `core.*`). **No external DUB packages or third-party modules are permitted** without explicit confirmation beforehand.
3. **Modern Idiomatic D**
   Projects leverage modern D2 features—including `@safe` by default where feasible, UFCS & lazy range pipelines (`std.range`, `std.algorithm`), compile-time reflection/CTFE, `std.sumtype` / `std.typecons`, Design by Contract (`in`/`out`/`invariant`), and built-in `unittest` suites.
4. **Clean DUB Project Lifecycle**
   Each project is initialized with `dub init`, documented with its own `README.md`, and tracked with a dedicated `CHANGELOG.md`.

---

## Projects

| Project | Type | Status | Description |
| :--- | :--- | :--- | :--- |
| **[`Oma`](./Oma/README.md)** | Command-Line Tool (CLI + REPL) | Active (`v0.1.0`) | Modular Linux Control Panel CLI (`system`, `network`, `services`, `power`, `storage`, `env`) written in modern D2 with Full Phobos — see [README](./Oma/README.md) & [CHANGELOG](./Oma/CHANGELOG.md). |

---

## Toolchain & Reference Links

- **D Language Specification:** https://dlang.org/spec/spec.html
- **Phobos Standard Library:** https://dlang.org/phobos/index.html
- **DUB Package & Build Tool:** https://dub.pm/
- **Recommended Compiler:** Modern D2 frontend (e.g., `ldc2` 1.41+ / DMD 2.111+ via `dub build --compiler=ldc2`)

---

## Repository Layout

```text
Dlang/
├── README.md        # Repository overview and Dlang engineering standards
├── .gitignore       # D / DUB build artifacts and editor ignores
└── Oma/             # First CLI project (created via `dub init`, with README.md & CHANGELOG.md)
```

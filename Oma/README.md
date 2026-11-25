# Oma

> **One-stop, modular Linux Control Panel for the command line — crafted in modern D2 with 100% Phobos and zero external dependencies.**

[![Language: D2](https://img.shields.io/badge/Language-D2%20(v2.111)-B03931?style=flat-square)](https://dlang.org/spec/spec.html)
[![Stdlib: Full Phobos](https://img.shields.io/badge/Dependencies-Full%20Phobos%20Only-1F6FEB?style=flat-square)](https://dlang.org/phobos/index.html)
[![Build: DUB](https://img.shields.io/badge/Build-DUB%20(dub.sdl)-2EA043?style=flat-square)](https://dub.pm/)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-FCC624?style=flat-square&logo=linux&logoColor=black)](#)
[![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-6E40C9?style=flat-square)](./CHANGELOG.md)

---

## Why Oma?

Linux system administration is traditionally scattered across dozens of utilities (`hostnamectl`, `timedatectl`, `nmcli`, `ip`, `systemctl`, `powerprofilesctl`, `df`, `/proc`, `/sys`, `/etc`). **Oma** unifies system inspection and configuration into a single, fast, native binary organized into clean, independent **Control Panels**—accessible both via scriptable subcommands and an interactive REPL shell.

### Core Guarantees

- **100% Full Phobos (`std.*` + `core.*`)** — Zero external DUB packages. Every feature uses D's standard library and POSIX bindings unless an external module is explicitly approved.
- **Grounded in `dlang.org`** — Designed and cross-referenced against the [D Language Specification](https://dlang.org/spec/spec.html) and [Phobos Library Reference](https://dlang.org/phobos/index.html).
- **Safe-by-Default Modifications** — Write operations default to `--dry-run` preview mode, showing the exact system command before anything changes. Pass `--apply` (and `sudo` when root privileges are required) to commit changes.
- **Dual Mode (CLI + REPL)** — Use one-liner subcommands in shell scripts (`--json`) or explore interactively via the `oma>` shell (`use <panel>`).

---

## Modular Control Panels

| Panel | Scope | Read Actions | Write Actions (`--dry-run` / `--apply`) |
| :--- | :--- | :--- | :--- |
| **`system`** | OS, kernel, hostname, uptime, memory, load & timezone | `status` | `set-hostname <name>`, `set-timezone <tz>` |
| **`network`** | Interfaces, routes & DNS resolvers | `status`, `interfaces`, `dns` | `set-dns <connection> <dns...>` |
| **`services`** | `systemd` service health & lifecycle | `status [unit]`, `list [limit]` | `start`, `stop`, `restart`, `enable`, `disable` |
| **`power`** | Battery/AC status, CPU governor & power profiles | `status` | `set-profile <power-saver\|balanced\|performance>` |
| **`storage`** | Disk usage & mounted block devices | `status`, `mounts` | *(read-only in v0.1.0)* |
| **`env`** | User/UID, shell, editor, locale, XDG paths & `PATH` | `status`, `path` | *(read-only in v0.1.0)* |

---

## Quick Start

### Prerequisites

- A modern D2 compiler — **`ldc2` 1.41+ (DMD v2.111 frontend)** recommended
- **DUB** package/build manager (`dub`)

### Build & Run Tests

```bash
cd Oma

# Run the built-in Phobos unittest suite
dub test --compiler=ldc2

# Build the native `oma` binary
dub build --compiler=ldc2

# Optional: optimized release build
dub build --compiler=ldc2 --build=release
```

---

## Usage

### 1. Subcommand Mode

```bash
# List all registered control panels
./oma panels

# Unified health snapshot across every panel
./oma status

# Inspect individual panels
./oma system status
./oma network dns
./oma services list 10
./oma power status
./oma storage mounts
./oma env path

# Machine-readable JSON output for scripts & `jq`
./oma --json system status
./oma --json status

# Safe dry-run preview of a system modification (default behavior)
./oma system set-hostname workstation

# Apply a change explicitly
sudo ./oma --apply system set-hostname workstation
sudo ./oma --apply services restart ssh.service
```

### 2. Interactive REPL Mode

Run `./oma` with no arguments (or `./oma repl`) to enter the interactive Control Panel shell:

```text
$ ./oma
oma v0.1.0 — Interactive Linux Control Panel
Mode: dry-run=on · json=off · Type 'help' for commands, 'panels' to browse, 'exit' to quit.

oma [dry]> panels
oma [dry]> use power
Switched active panel to 'power'.
oma [power|dry]> status
oma [power|dry]> set-profile performance
oma [power|dry]> back
oma [dry]> dry-run off
oma [live]> exit
```

### 3. Persistent Local Configuration

Oma persists user defaults in XDG-compliant JSON at `~/.config/oma/config.json` (or `$XDG_CONFIG_HOME/oma/config.json`):

```bash
./oma config show
./oma config path
./oma config set defaultPanel system
./oma config set color true
./oma config set dryRun true
./oma config reset
```

### 4. Global Options

| Flag | Description |
| :--- | :--- |
| `--json` | Emit structured JSON via `std.json` |
| `--no-color` | Disable ANSI terminal colors (also honors the `NO_COLOR` env var & non-TTY piping) |
| `--dry-run` | Preview write operations without modifying Linux state (default) |
| `--apply` | Execute write operations (overrides `dryRun` config) |
| `--config=<path>` | Use a custom JSON config file |
| `-v`, `--verbose` | Enable info-level `std.logger` diagnostics on `stderr` |
| `--debug` | Enable trace-level `std.logger` diagnostics on `stderr` |
| `-q`, `--quiet` | Emit error-level logs only |
| `-V`, `--version` | Display version & spec links |
| `-h`, `--help` | Display usage help |

---

## Architecture

```text
Oma/
├── dub.sdl                         # Package manifest (zero external dependencies)
├── README.md                       # Project documentation
├── CHANGELOG.md                    # Release history
└── source/
    ├── app.d                       # Thin executable entrypoint
    └── oma/
        ├── package.d               # Package metadata & dlang.org references
        ├── cli.d                   # std.getopt flag parsing & subcommand router
        ├── repl.d                  # Interactive shell & quote-aware tokenizer
        ├── config.d                # XDG JSON persistence (std.json, std.file, std.path)
        ├── output.d                # ANSI formatter (isatty/NO_COLOR) + JSON serializer
        ├── logging.d               # std.logger setup routed cleanly to stderr
        ├── sys.d                   # Safe Linux /proc, /sys, /etc readers & applyCommand
        └── panels/
            ├── package.d           # ControlPanel interface & PanelRegistry
            ├── system.d            # OS, hostname, timezone, uptime, memory, load
            ├── network.d           # Interfaces, default route, DNS
            ├── services.d          # systemd inspection & unit control
            ├── power.d             # Battery/AC, CPU governor, power profiles
            ├── storage.d           # Disk usage & /proc/mounts
            └── env.d               # User, shell, editor, locale, XDG, PATH
```

### Adding a New Control Panel

Every Linux settings domain implements the [`ControlPanel`](./source/oma/panels/package.d) interface:

1. Create `source/oma/panels/<domain>.d` implementing `ControlPanel` (`name`, `summary`, `actions`, `execute`).
2. Route all write operations through `oma.sys.applyCommand(argv, ctx.dryRun, requiresRoot)`.
3. Add inline `unittest` blocks covering pure parsers and dry-run paths.
4. Register the panel in `createDefaultRegistry()` inside `source/oma/panels/package.d`.

---

## D Language Specification & Phobos Cross-Reference

Oma uses [dlang.org](https://dlang.org) as its authoritative technical foundation:

| Feature in Oma | D Spec / Phobos Module | Reference |
| :--- | :--- | :--- |
| Modular panel architecture | Interfaces & Package Modules | [dlang.org/spec/interface.html](https://dlang.org/spec/interface.html), [module.html](https://dlang.org/spec/module.html) |
| Safety & precondition checks | `@safe`, `pure`, `nothrow`, `in` contracts | [function.html#function-safety](https://dlang.org/spec/function.html#function-safety), [contracts.html](https://dlang.org/spec/contracts.html) |
| Resource cleanup in tests | `scope (exit)` guards | [statement.html#scope-guard-statement](https://dlang.org/spec/statement.html#scope-guard-statement) |
| Built-in test suite | `unittest` blocks | [unittest.html](https://dlang.org/spec/unittest.html) |
| CLI flag parsing | `std.getopt` (`stopOnFirstNonOption`) | [phobos/std_getopt.html](https://dlang.org/phobos/std_getopt.html) |
| JSON output & config store | `std.json`, `std.file`, `std.path` | [phobos/std_json.html](https://dlang.org/phobos/std_json.html) |
| Structured logging | `std.logger` | [phobos/std_logger.html](https://dlang.org/phobos/std_logger.html) |
| Process & environment access | `std.process`, `core.sys.posix.unistd` | [phobos/std_process.html](https://dlang.org/phobos/std_process.html) |
| Range-based parsing | `std.algorithm`, `std.range`, `std.string` | [phobos/std_algorithm.html](https://dlang.org/phobos/std_algorithm.html) |

---

## License

MIT — see [dub.sdl](./dub.sdl).

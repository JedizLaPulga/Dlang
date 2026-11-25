# Changelog

All notable changes to **Oma** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-25

### Added
- Initialized **Oma** with `dub init Oma -f sdl` targeting modern D2 (`ldc2` / DMD v2.111 frontend) with **100% Full Phobos** and zero external dependencies.
- **Modular Control Panel Architecture** (`oma.panels`) with `ControlPanel` interface and `PanelRegistry`.
- **Six Built-in Linux Control Panels**:
  - `system`: OS/distro (`/etc/os-release`), kernel, hostname, timezone, uptime, load average, memory (`/proc/meminfo`), plus safe `set-hostname` and `set-timezone`.
  - `network`: interfaces (`ip -brief addr`), default route, DNS (`/etc/resolv.conf`), plus safe `set-dns` via `nmcli`.
  - `services`: `systemd` overview, running unit list, single-unit status, plus safe `start`, `stop`, `restart`, `enable`, and `disable`.
  - `power`: `/sys/class/power_supply` battery/AC detection, CPU scaling governor, and `powerprofilesctl` inspection & `set-profile`.
  - `storage`: disk usage (`df`) and block mounts (`/proc/mounts`).
  - `env`: user/UID/EUID, shell, editor, locale, desktop session, XDG paths, and ordered `PATH` inspection.
- **Dual Interaction Modes**:
  - Subcommand CLI (`oma <panel> [action] [args]`, `oma status`, `oma panels`, `oma config`).
  - Interactive REPL shell (`oma` / `oma repl`) with panel context switching (`use <panel>`, `back`), live mode toggles (`dry-run`, `json`, `color`), and quote-aware command tokenization.
- **Safety-First Write Model**: `--dry-run` enabled by default for write commands, explicit `--apply` opt-in, and POSIX `geteuid()` privilege checks.
- **Output & Persistence**:
  - ANSI-styled terminal output with `--no-color`, `NO_COLOR` env var, and TTY auto-detection (`isatty`).
  - Structured `--json` output across all panels and commands via `std.json`.
  - XDG-compliant local JSON config persistence (`~/.config/oma/config.json`) via `std.file`, `std.path`, and `std.json`.
- **Logging & Testing**:
  - `std.logger` diagnostics routed to `stderr` (`--verbose`, `--debug`, `--quiet`).
  - Built-in D `unittest` suite covering config persistence, logging, ANSI/JSON formatting, system file parsers, REPL tokenization, CLI routing, and panel dry-run actions.
- Documentation: `Oma/README.md` cross-referenced with [dlang.org/spec/spec.html](https://dlang.org/spec/spec.html) and Phobos.

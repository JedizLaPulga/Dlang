/**
 * Safe Linux system inspection and command execution helpers using Phobos
 * (`std.process`, `std.file`, `std.string`, `std.algorithm`, `std.conv`, `std.logger`)
 * and `core.sys.posix.unistd`.
 *
 * Design principle:
 * - Read-only inspection reads `/proc`, `/sys`, `/etc` directly when possible,
 *   avoiding unnecessary subprocess overhead.
 * - Mutating operations go through `applyCommand`, which respects `--dry-run`,
 *   logs every command via `std.logger`, and checks privilege requirements cleanly.
 *
 * Spec_Ref: https://dlang.org/spec/function.html#function-safety
 * Spec_Ref: https://dlang.org/spec/contracts.html
 */
module oma.sys;

import core.sys.posix.unistd : geteuid;
import std.algorithm : filter, map, splitter;
import std.array : array, join;
import std.conv : to, ConvException;
import std.file : exists, readText;
import std.format : format;
import std.logger : infof, tracef, warningf;
import std.process : execute, ProcessException;
import std.string : indexOf, lineSplitter, split, startsWith, strip;

/// Result of running a system command.
struct CommandResult
{
    int exitCode = -1;
    string output;
    bool executed = false;
    bool missingBinary = false;
    string renderedCommand;
}

/// Returns `true` if the current process is running with effective UID 0 (`root`).
bool isRoot() @trusted nothrow
{
    return geteuid() == 0;
}

/// Formats an argument vector into a readable shell-like command preview string.
string formatCommand(const string[] argv) @safe pure
{
    string[] quoted;
    quoted.reserve(argv.length);
    foreach (arg; argv)
    {
        if (arg.indexOf(' ') >= 0 || arg.length == 0)
            quoted ~= `"` ~ arg ~ `"`;
        else
            quoted ~= arg;
    }
    return quoted.join(" ");
}

/// Executes a read-only system command safely without invoking a shell (`std.process.execute`).
CommandResult runCommand(const string[] argv)
in (argv.length > 0, "Command argv must contain at least the executable name")
{
    CommandResult res;
    res.renderedCommand = formatCommand(argv);
    tracef("Executing read-only command: %s", res.renderedCommand);

    try
    {
        auto p = execute(argv);
        res.exitCode = p.status;
        res.output = p.output.strip();
        res.executed = true;
    }
    catch (ProcessException e)
    {
        res.exitCode = 127;
        res.output = e.msg;
        res.missingBinary = true;
        warningf("Command unavailable (%s): %s", argv[0], e.msg);
    }
    catch (Exception e)
    {
        res.exitCode = 1;
        res.output = e.msg;
        warningf("Command failed (%s): %s", argv[0], e.msg);
    }
    return res;
}

/// Executes a mutating system command, honoring `dryRun` and optional root-privilege requirements.
CommandResult applyCommand(const string[] argv, bool dryRun, bool requiresRoot = true)
in (argv.length > 0, "Command argv must contain at least the executable name")
{
    CommandResult res;
    res.renderedCommand = formatCommand(argv);

    if (dryRun)
    {
        infof("[dry-run] Would execute: %s", res.renderedCommand);
        res.exitCode = 0;
        res.executed = false;
        res.output = "Dry-run enabled; command not executed.";
        return res;
    }

    if (requiresRoot && !isRoot())
    {
        res.exitCode = 1;
        res.executed = false;
        res.output = "Root privileges required. Re-run with sudo or inspect with --dry-run.";
        return res;
    }

    infof("Applying Linux setting via: %s", res.renderedCommand);
    return runCommand(argv);
}

/// Safely reads a text file if it exists, returning `fallback` on error.
string readFileOr(string path, string fallback = "")
{
    if (!exists(path))
        return fallback;

    try
    {
        return readText(path).strip();
    }
    catch (Exception)
    {
        return fallback;
    }
}

/// Parses key=value entries from `/etc/os-release` content (pure function for easy unit testing).
string[string] parseOsRelease(string content) @safe pure
{
    string[string] fields;
    foreach (rawLine; content.lineSplitter())
    {
        auto line = rawLine.strip();
        if (line.length == 0 || line.startsWith("#"))
            continue;

        auto eq = line.indexOf('=');
        if (eq <= 0)
            continue;

        auto key = line[0 .. eq].strip();
        auto val = line[eq + 1 .. $].strip();
        if (val.length >= 2 && ((val[0] == '"' && val[$ - 1] == '"') || (val[0] == '\'' && val[$ - 1] == '\'')))
            val = val[1 .. $ - 1];

        fields[key] = val;
    }
    return fields;
}

/// Memory summary parsed from `/proc/meminfo` (values in KiB).
struct MemSummary
{
    ulong totalKiB;
    ulong availableKiB;

    ulong usedKiB() const @safe pure nothrow
    {
        return totalKiB >= availableKiB ? (totalKiB - availableKiB) : 0;
    }

    double usedPercent() const @safe pure nothrow
    {
        if (totalKiB == 0)
            return 0.0;
        return (cast(double) usedKiB() / cast(double) totalKiB) * 100.0;
    }
}

/// Parses `MemTotal` and `MemAvailable` from `/proc/meminfo` text.
MemSummary parseMemInfo(string content) @safe pure
{
    MemSummary mem;
    foreach (rawLine; content.lineSplitter())
    {
        auto line = rawLine.strip();
        if (line.startsWith("MemTotal:"))
        {
            auto parts = line.split();
            if (parts.length >= 2)
                mem.totalKiB = parseUlongOr(parts[1], 0);
        }
        else if (line.startsWith("MemAvailable:"))
        {
            auto parts = line.split();
            if (parts.length >= 2)
                mem.availableKiB = parseUlongOr(parts[1], 0);
        }
    }
    return mem;
}

/// Formats uptime seconds from `/proc/uptime` into a concise human-readable duration.
string formatUptime(double totalSeconds) @safe pure
{
    if (totalSeconds < 0)
        return "0m";

    ulong secs = cast(ulong) totalSeconds;
    ulong days = secs / 86_400;
    ulong hours = (secs % 86_400) / 3_600;
    ulong mins = (secs % 3_600) / 60;

    if (days > 0)
        return format("%dd %dh %dm", days, hours, mins);
    if (hours > 0)
        return format("%dh %dm", hours, mins);
    return format("%dm", mins);
}

/// Formats KiB into human-readable GiB/MiB string.
string formatKiB(ulong kib) @safe pure
{
    if (kib >= 1_048_576)
        return format("%.2f GiB", cast(double) kib / 1_048_576.0);
    return format("%.1f MiB", cast(double) kib / 1024.0);
}

/// Extracts `nameserver` entries from `/etc/resolv.conf` content.
string[] parseResolvConf(string content) @safe pure
{
    string[] servers;
    foreach (rawLine; content.lineSplitter())
    {
        auto line = rawLine.strip();
        if (line.length == 0 || line.startsWith("#") || line.startsWith(";"))
            continue;

        auto parts = line.split();
        if (parts.length >= 2 && parts[0] == "nameserver")
            servers ~= parts[1];
    }
    return servers;
}

private ulong parseUlongOr(string raw, ulong fallback) @safe pure nothrow
{
    try
    {
        return raw.to!ulong;
    }
    catch (Exception)
    {
        return fallback;
    }
}

unittest
{
    auto os = parseOsRelease("NAME=\"Ubuntu\"\nPRETTY_NAME=\"Ubuntu 26.04 LTS\"\n# comment\nID=ubuntu\n");
    assert(os["NAME"] == "Ubuntu");
    assert(os["PRETTY_NAME"] == "Ubuntu 26.04 LTS");
    assert(os["ID"] == "ubuntu");

    auto mem = parseMemInfo("MemTotal:       16384000 kB\nMemFree:         2000000 kB\nMemAvailable:    8192000 kB\n");
    assert(mem.totalKiB == 16_384_000);
    assert(mem.availableKiB == 8_192_000);
    assert(mem.usedKiB() == 8_192_000);
    assert(mem.usedPercent() == 50.0);

    assert(formatUptime(90_061) == "1d 1h 1m");
    assert(formatUptime(3_660) == "1h 1m");
    assert(formatUptime(180) == "3m");

    auto dns = parseResolvConf("# Generated\nnameserver 1.1.1.1\nsearch local\nnameserver 9.9.9.9\n");
    assert(dns == ["1.1.1.1", "9.9.9.9"]);

    assert(formatCommand(["hostnamectl", "set-hostname", "my box"]) == `hostnamectl set-hostname "my box"`);
}

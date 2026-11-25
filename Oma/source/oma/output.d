/**
 * Terminal ANSI formatting and structured JSON output rendering.
 *
 * Uses Phobos (`std.stdio`, `std.json`, `std.algorithm`, `std.string`, `std.process`)
 * and POSIX `isatty` (`core.sys.posix.unistd`) to cleanly support:
 * - ANSI colors on interactive TTYs
 * - `--no-color` and the `NO_COLOR` convention (https://no-color.org/)
 * - Machine-readable `--json` output for shell pipelines and scripting
 *
 * Spec_Ref: https://dlang.org/spec/enum.html
 * Spec_Ref: https://dlang.org/spec/struct.html
 */
module oma.output;

import core.sys.posix.unistd : isatty, STDOUT_FILENO;
import std.algorithm : fold, max;
import std.json : JSONValue;
import std.process : environment;
import std.range : repeat;
import std.stdio : File, stdout;
import std.string : leftJustify;

/// Standard ANSI SGR escape sequences.
enum Ansi : string
{
    reset   = "\x1b[0m",
    bold    = "\x1b[1m",
    dim     = "\x1b[2m",
    red     = "\x1b[31m",
    green   = "\x1b[32m",
    yellow  = "\x1b[33m",
    blue    = "\x1b[34m",
    magenta = "\x1b[35m",
    cyan    = "\x1b[36m",
    white   = "\x1b[37m",
}

/// A single key/value entry reported by a control panel.
struct SettingItem
{
    string key;
    string value;
    string note = "";

    JSONValue toJson() const @safe
    {
        JSONValue obj = JSONValue.emptyObject;
        obj["key"] = key;
        obj["value"] = value;
        if (note.length > 0)
            obj["note"] = note;
        return obj;
    }
}

/// Structured result emitted by a panel action or overview query.
struct PanelReport
{
    string panel;
    string action;
    bool ok = true;
    bool dryRun = false;
    string summary;
    SettingItem[] items;
    string[] plannedCommands;
    string[] warnings;
    string errorMessage;

    /// Converts the entire report to a Phobos `JSONValue`.
    JSONValue toJson() const @safe
    {
        JSONValue obj = JSONValue.emptyObject;
        obj["panel"] = panel;
        obj["action"] = action;
        obj["ok"] = ok;
        obj["dryRun"] = dryRun;
        obj["summary"] = summary;

        JSONValue[] itemList;
        foreach (item; items)
            itemList ~= item.toJson();
        obj["items"] = JSONValue(itemList);

        if (plannedCommands.length > 0)
            obj["plannedCommands"] = JSONValue(plannedCommands.dup);

        if (warnings.length > 0)
            obj["warnings"] = JSONValue(warnings.dup);

        if (errorMessage.length > 0)
            obj["error"] = errorMessage;

        return obj;
    }
}

/// Determines whether ANSI color should be enabled for standard output.
bool shouldUseColor(bool configColor, bool noColorFlag) @trusted
{
    if (noColorFlag || !configColor)
        return false;

    // Honor the NO_COLOR standard (any non-empty value disables color).
    if (environment.get("NO_COLOR", "").length > 0)
        return false;

    return isatty(STDOUT_FILENO) != 0;
}

/// Formats output consistently across both human-readable ANSI and `--json` modes.
struct OutputFormatter
{
    bool useColor = true;
    bool jsonMode = false;

    /// Wraps `text` with an ANSI code when `useColor` is active.
    string style(string code, string text) const @safe pure nothrow
    {
        if (!useColor || code.length == 0)
            return text;
        return code ~ text ~ Ansi.reset;
    }

    string bold(string text) const @safe pure nothrow => style(Ansi.bold, text);
    string dim(string text) const @safe pure nothrow => style(Ansi.dim, text);
    string cyan(string text) const @safe pure nothrow => style(Ansi.cyan, text);
    string green(string text) const @safe pure nothrow => style(Ansi.green, text);
    string yellow(string text) const @safe pure nothrow => style(Ansi.yellow, text);
    string red(string text) const @safe pure nothrow => style(Ansi.red, text);
    string blue(string text) const @safe pure nothrow => style(Ansi.blue, text);

    /// Renders a `PanelReport` to `sink` (defaulting to `stdout`).
    void renderReport(const PanelReport report, File sink = stdout) const
    {
        if (jsonMode)
        {
            sink.writeln(report.toJson().toPrettyString());
            return;
        }

        auto badge = report.ok
            ? (report.dryRun ? yellow("[DRY-RUN]") : green("[OK]"))
            : red("[ERROR]");

        sink.writefln("%s %s %s", badge, bold(cyan(report.panel)), dim("· " ~ report.action));

        if (report.summary.length > 0)
            sink.writeln("  " ~ report.summary);

        if (report.items.length > 0)
        {
            size_t keyWidth = 0;
            foreach (item; report.items)
                keyWidth = max(keyWidth, item.key.length);

            sink.writeln();
            foreach (item; report.items)
            {
                auto paddedKey = leftJustify(item.key, keyWidth);
                if (item.note.length > 0)
                    sink.writefln("  %s  %s  %s", dim(paddedKey), item.value, dim("(" ~ item.note ~ ")"));
                else
                    sink.writefln("  %s  %s", dim(paddedKey), item.value);
            }
        }

        if (report.plannedCommands.length > 0)
        {
            sink.writeln();
            sink.writeln("  " ~ bold(yellow("Planned command(s):")));
            foreach (cmd; report.plannedCommands)
                sink.writeln("    $ " ~ cmd);
        }

        if (report.warnings.length > 0)
        {
            sink.writeln();
            foreach (w; report.warnings)
                sink.writeln("  " ~ yellow("Warning: ") ~ w);
        }

        if (report.errorMessage.length > 0)
        {
            sink.writeln();
            sink.writeln("  " ~ red("Error: ") ~ report.errorMessage);
        }
    }

    /// Renders multiple reports (e.g., `oma status` overview across all panels).
    void renderReports(const PanelReport[] reports, File sink = stdout) const
    {
        if (jsonMode)
        {
            JSONValue[] arr;
            foreach (r; reports)
                arr ~= r.toJson();
            JSONValue root = JSONValue.emptyObject;
            root["reports"] = JSONValue(arr);
            sink.writeln(root.toPrettyString());
            return;
        }

        foreach (i, r; reports)
        {
            if (i > 0)
                sink.writeln();
            renderReport(r, sink);
        }
    }

    /// Renders a generic JSON object in `--json` mode or a formatted key/value list in text mode.
    void renderKeyValues(string title, const SettingItem[] items, File sink = stdout) const
    {
        PanelReport r;
        r.panel = title;
        r.action = "show";
        r.ok = true;
        r.items = items.dup;
        renderReport(r, sink);
    }
}

unittest
{
    auto plain = OutputFormatter(false, false);
    assert(plain.green("ok") == "ok");
    assert(plain.bold("title") == "title");

    auto colored = OutputFormatter(true, false);
    assert(colored.green("ok") == "\x1b[32mok\x1b[0m");

    PanelReport report;
    report.panel = "system";
    report.action = "status";
    report.ok = true;
    report.summary = "System healthy";
    report.items = [SettingItem("Hostname", "workstation")];

    auto j = report.toJson();
    assert(j["panel"].str == "system");
    assert(j["ok"].boolean == true);
    assert(j["items"].array.length == 1);
    assert(j["items"][0]["key"].str == "Hostname");
}

/**
 * `system` Control Panel — OS identity, kernel, hostname, uptime, memory, load, and timezone.
 *
 * Read operations read Linux `/etc` and `/proc` directly via Phobos `std.file`.
 * Write operations (`set-hostname`, `set-timezone`) invoke `hostnamectl` / `timedatectl`
 * through `oma.sys.applyCommand`, honoring `--dry-run` by default.
 *
 * Spec_Ref: https://dlang.org/spec/class.html
 */
module oma.panels.system;

import oma.output : PanelReport, SettingItem;
import oma.panels : ControlPanel, ExecContext, PanelActionSpec, panelHelpReport, unknownActionReport;
import oma.sys : applyCommand, formatKiB, formatUptime, isRoot, parseMemInfo, parseOsRelease, readFileOr, runCommand;
import std.conv : to;
import std.format : format;
import std.string : split, strip;

/// Linux system identity, runtime health, and hostname/timezone management panel.
class SystemPanel : ControlPanel
{
    private static immutable PanelActionSpec[] _actions = [
        PanelActionSpec("status",       "status",               "Show OS, kernel, hostname, uptime, memory, load & timezone", false),
        PanelActionSpec("set-hostname", "set-hostname <name>",  "Set the static system hostname via hostnamectl",             true),
        PanelActionSpec("set-timezone", "set-timezone <tz>",    "Set the system timezone via timedatectl (e.g. UTC)",         true),
        PanelActionSpec("help",         "help",                 "List available actions for the system panel",                false),
    ];

    override string name() const @safe pure nothrow => "system";
    override string summary() const @safe pure nothrow => "OS info, hostname, timezone, uptime, memory & load";
    override const(PanelActionSpec)[] actions() const @safe pure nothrow => _actions;

    override PanelReport execute(string action, const string[] args, const ExecContext ctx)
    {
        switch (action)
        {
            case "", "status", "show":
                return inspectStatus();
            case "set-hostname":
                return setHostname(args, ctx);
            case "set-timezone":
                return setTimezone(args, ctx);
            case "help":
                return panelHelpReport(this);
            default:
                return unknownActionReport(this, action);
        }
    }

    private PanelReport inspectStatus()
    {
        PanelReport r;
        r.panel = name;
        r.action = "status";
        r.ok = true;

        auto osFields = parseOsRelease(readFileOr("/etc/os-release"));
        auto prettyOs = osFields.get("PRETTY_NAME", osFields.get("NAME", "Linux"));
        auto hostname = readFileOr("/etc/hostname", "unknown");
        auto kernel = readFileOr("/proc/sys/kernel/osrelease", "unknown");
        auto timezone = readFileOr("/etc/timezone", "");
        if (timezone.length == 0)
        {
            auto tzCmd = runCommand(["timedatectl", "show", "-p", "Timezone", "--value"]);
            timezone = (tzCmd.exitCode == 0 && tzCmd.output.length > 0) ? tzCmd.output : "unknown";
        }

        string uptimeStr = "unknown";
        auto uptimeRaw = readFileOr("/proc/uptime");
        if (uptimeRaw.length > 0)
        {
            auto parts = uptimeRaw.split();
            if (parts.length > 0)
            {
                try
                    uptimeStr = formatUptime(parts[0].to!double);
                catch (Exception)
                    uptimeStr = parts[0] ~ "s";
            }
        }

        auto loadRaw = readFileOr("/proc/loadavg");
        string loadStr = "unknown";
        if (loadRaw.length > 0)
        {
            auto parts = loadRaw.split();
            if (parts.length >= 3)
                loadStr = format("%s, %s, %s (1m/5m/15m)", parts[0], parts[1], parts[2]);
        }

        auto mem = parseMemInfo(readFileOr("/proc/meminfo"));
        string memStr = mem.totalKiB > 0
            ? format("%s / %s (%.1f%% used)", formatKiB(mem.usedKiB()), formatKiB(mem.totalKiB), mem.usedPercent())
            : "unknown";

        r.summary = format("%s on %s", prettyOs, hostname);
        r.items = [
            SettingItem("OS", prettyOs),
            SettingItem("Kernel", kernel),
            SettingItem("Hostname", hostname),
            SettingItem("Timezone", timezone),
            SettingItem("Uptime", uptimeStr),
            SettingItem("Load Average", loadStr),
            SettingItem("Memory", memStr),
            SettingItem("Privilege", isRoot() ? "root (uid=0)" : "standard user", "write actions may need sudo"),
        ];
        return r;
    }

    private PanelReport setHostname(const string[] args, const ExecContext ctx)
    {
        PanelReport r;
        r.panel = name;
        r.action = "set-hostname";
        r.dryRun = ctx.dryRun;

        if (args.length < 1 || args[0].strip().length == 0)
        {
            r.ok = false;
            r.errorMessage = "Missing hostname argument. Usage: oma system set-hostname <name>";
            return r;
        }

        auto newName = args[0].strip();
        auto cmd = ["hostnamectl", "set-hostname", newName];
        auto res = applyCommand(cmd, ctx.dryRun, true);
        r.plannedCommands ~= res.renderedCommand;

        if (ctx.dryRun)
        {
            r.ok = true;
            r.summary = format("Dry-run: would change hostname to '%s'.", newName);
            r.items = [SettingItem("Target Hostname", newName)];
            r.warnings ~= "Pass --apply (or set dryRun=false in config) to apply this change.";
            return r;
        }

        r.ok = (res.exitCode == 0);
        if (r.ok)
            r.summary = format("Hostname updated to '%s'.", newName);
        else
            r.errorMessage = res.output;
        return r;
    }

    private PanelReport setTimezone(const string[] args, const ExecContext ctx)
    {
        PanelReport r;
        r.panel = name;
        r.action = "set-timezone";
        r.dryRun = ctx.dryRun;

        if (args.length < 1 || args[0].strip().length == 0)
        {
            r.ok = false;
            r.errorMessage = "Missing timezone argument. Usage: oma system set-timezone <Region/City|UTC>";
            return r;
        }

        auto tz = args[0].strip();
        auto cmd = ["timedatectl", "set-timezone", tz];
        auto res = applyCommand(cmd, ctx.dryRun, true);
        r.plannedCommands ~= res.renderedCommand;

        if (ctx.dryRun)
        {
            r.ok = true;
            r.summary = format("Dry-run: would set system timezone to '%s'.", tz);
            r.items = [SettingItem("Target Timezone", tz)];
            r.warnings ~= "Pass --apply (or set dryRun=false in config) to apply this change.";
            return r;
        }

        r.ok = (res.exitCode == 0);
        if (r.ok)
            r.summary = format("System timezone updated to '%s'.", tz);
        else
            r.errorMessage = res.output;
        return r;
    }
}

unittest
{
    auto panel = new SystemPanel();
    ExecContext ctx;
    ctx.dryRun = true;

    auto res = panel.execute("set-hostname", ["devbox"], ctx);
    assert(res.ok);
    assert(res.dryRun);
    assert(res.plannedCommands == ["hostnamectl set-hostname devbox"]);

    auto bad = panel.execute("set-hostname", [], ctx);
    assert(!bad.ok);
}

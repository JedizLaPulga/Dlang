/**
 * `power` Control Panel — Battery/AC status, CPU scaling governor, and power profiles.
 *
 * Reads `/sys/class/power_supply` and `/sys/devices/system/cpu/cpu0/cpufreq` directly
 * with Phobos `std.file`, and integrates with `powerprofilesctl` when installed.
 *
 * Spec_Ref: https://dlang.org/spec/class.html
 */
module oma.panels.power;

import oma.output : PanelReport, SettingItem;
import oma.panels : ControlPanel, ExecContext, PanelActionSpec, panelHelpReport, unknownActionReport;
import oma.sys : applyCommand, readFileOr, runCommand;
import std.algorithm : canFind;
import std.file : dirEntries, exists, SpanMode;
import std.format : format;
import std.path : baseName, buildPath;
import std.string : strip;

/// Power supply, CPU scaling governor, and power profile control panel.
class PowerPanel : ControlPanel
{
    private static immutable PanelActionSpec[] _actions = [
        PanelActionSpec("status",      "status",                "Show battery, AC status, CPU governor & active power profile", false),
        PanelActionSpec("set-profile", "set-profile <profile>", "Set power profile (power-saver | balanced | performance)",     true),
        PanelActionSpec("help",        "help",                  "List available actions for the power panel",                   false),
    ];

    private static immutable string[] VALID_PROFILES = ["power-saver", "balanced", "performance"];

    override string name() const @safe pure nothrow => "power";
    override string summary() const @safe pure nothrow => "Battery/AC status, CPU governor & power profiles";
    override const(PanelActionSpec)[] actions() const @safe pure nothrow => _actions;

    override PanelReport execute(string action, const string[] args, const ExecContext ctx)
    {
        switch (action)
        {
            case "", "status", "show":
                return inspectStatus();
            case "set-profile":
                return setProfile(args, ctx);
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

        auto governor = readFileOr("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "unavailable");
        r.items ~= SettingItem("CPU Governor", governor);

        auto profCmd = runCommand(["powerprofilesctl", "get"]);
        if (profCmd.exitCode == 0 && profCmd.output.length > 0)
            r.items ~= SettingItem("Power Profile", profCmd.output, "powerprofilesctl");
        else
            r.items ~= SettingItem("Power Profile", "unavailable", "powerprofilesctl not active");

        enum supplyRoot = "/sys/class/power_supply";
        size_t supplies = 0;
        if (exists(supplyRoot))
        {
            try
            {
                foreach (entry; dirEntries(supplyRoot, SpanMode.shallow))
                {
                    auto devName = baseName(entry.name);
                    auto type = readFileOr(buildPath(entry.name, "type"), "Unknown");
                    if (type == "Battery")
                    {
                        auto cap = readFileOr(buildPath(entry.name, "capacity"), "?");
                        auto stat = readFileOr(buildPath(entry.name, "status"), "Unknown");
                        r.items ~= SettingItem(devName, format("%s%% (%s)", cap, stat), "Battery");
                        supplies++;
                    }
                    else if (type == "Mains")
                    {
                        auto online = readFileOr(buildPath(entry.name, "online"), "0");
                        r.items ~= SettingItem(devName, online == "1" ? "Connected" : "Disconnected", "AC Mains");
                        supplies++;
                    }
                }
            }
            catch (Exception)
            {
                r.warnings ~= "Unable to enumerate /sys/class/power_supply.";
            }
        }

        r.summary = supplies > 0
            ? format("Governor: %s · %d power supply device(s)", governor, supplies)
            : format("Governor: %s (desktop/VM — no battery detected)", governor);
        return r;
    }

    private PanelReport setProfile(const string[] args, const ExecContext ctx)
    {
        PanelReport r;
        r.panel = name;
        r.action = "set-profile";
        r.dryRun = ctx.dryRun;

        if (args.length < 1 || !VALID_PROFILES.canFind(args[0].strip()))
        {
            r.ok = false;
            r.errorMessage = "Invalid or missing profile. Choose one of: power-saver, balanced, performance.";
            return r;
        }

        auto profile = args[0].strip();
        auto cmd = ["powerprofilesctl", "set", profile];
        // `powerprofilesctl` uses polkit/D-Bus and does not strictly require uid 0.
        auto res = applyCommand(cmd, ctx.dryRun, false);
        r.plannedCommands ~= res.renderedCommand;

        if (ctx.dryRun)
        {
            r.ok = true;
            r.summary = format("Dry-run: would switch power profile to '%s'.", profile);
            r.items = [SettingItem("Target Profile", profile)];
            r.warnings ~= "Pass --apply (or set dryRun=false in config) to apply this change.";
            return r;
        }

        r.ok = (res.exitCode == 0);
        if (r.ok)
            r.summary = format("Power profile switched to '%s'.", profile);
        else
            r.errorMessage = res.output;
        return r;
    }
}

unittest
{
    auto panel = new PowerPanel();
    ExecContext ctx;
    ctx.dryRun = true;

    auto okRes = panel.execute("set-profile", ["balanced"], ctx);
    assert(okRes.ok);
    assert(okRes.dryRun);
    assert(okRes.plannedCommands == ["powerprofilesctl set balanced"]);

    auto badRes = panel.execute("set-profile", ["turbo-max"], ctx);
    assert(!badRes.ok);
}

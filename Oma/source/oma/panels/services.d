/**
 * `services` Control Panel — Manage and inspect Linux `systemd` services.
 *
 * Spec_Ref: https://dlang.org/spec/class.html
 */
module oma.panels.services;

import oma.output : PanelReport, SettingItem;
import oma.panels : ControlPanel, ExecContext, PanelActionSpec, panelHelpReport, unknownActionReport;
import oma.sys : applyCommand, runCommand;
import std.format : format;
import std.string : lineSplitter, split, strip;

/// Linux systemd unit inspection and control panel.
class ServicesPanel : ControlPanel
{
    private static immutable PanelActionSpec[] _actions = [
        PanelActionSpec("status",  "status [unit]",  "Show systemd summary or status of a specific unit", false),
        PanelActionSpec("list",    "list [limit]",   "List running systemd services (default limit: 15)", false),
        PanelActionSpec("start",   "start <unit>",   "Start a systemd service",                           true),
        PanelActionSpec("stop",    "stop <unit>",    "Stop a systemd service",                            true),
        PanelActionSpec("restart", "restart <unit>", "Restart a systemd service",                         true),
        PanelActionSpec("enable",  "enable <unit>",  "Enable a systemd service at boot",                  true),
        PanelActionSpec("disable", "disable <unit>", "Disable a systemd service at boot",                 true),
        PanelActionSpec("help",    "help",           "List available actions for the services panel",     false),
    ];

    override string name() const @safe pure nothrow => "services";
    override string summary() const @safe pure nothrow => "Inspect & control systemd services";
    override const(PanelActionSpec)[] actions() const @safe pure nothrow => _actions;

    override PanelReport execute(string action, const string[] args, const ExecContext ctx)
    {
        switch (action)
        {
            case "", "status", "show":
                return args.length > 0 ? unitStatus(args[0]) : overviewStatus();
            case "list":
                return listRunning(args);
            case "start", "stop", "restart", "enable", "disable":
                return controlUnit(action, args, ctx);
            case "help":
                return panelHelpReport(this);
            default:
                return unknownActionReport(this, action);
        }
    }

    private PanelReport overviewStatus()
    {
        PanelReport r;
        r.panel = name;
        r.action = "status";

        auto state = runCommand(["systemctl", "is-system-running"]);
        if (state.missingBinary)
        {
            r.ok = true;
            r.summary = "systemctl is not installed on this host";
            r.warnings ~= "systemd management requires `systemctl`.";
            return r;
        }

        auto failed = runCommand(["systemctl", "--failed", "--no-legend", "--plain"]);
        size_t failedCount = 0;
        if (failed.exitCode == 0 && failed.output.length > 0)
        {
            foreach (line; failed.output.lineSplitter())
                if (line.strip().length > 0)
                    failedCount++;
        }

        auto running = runCommand(["systemctl", "list-units", "--type=service", "--state=running", "--no-legend", "--plain"]);
        size_t runningCount = 0;
        if (running.exitCode == 0 && running.output.length > 0)
        {
            foreach (line; running.output.lineSplitter())
                if (line.strip().length > 0)
                    runningCount++;
        }

        r.ok = true;
        auto sysState = state.output.length > 0 ? state.output : "unknown";
        r.summary = format("systemd state: %s (%d running, %d failed)", sysState, runningCount, failedCount);
        r.items = [
            SettingItem("Systemd State", sysState),
            SettingItem("Running Services", format("%d", runningCount)),
            SettingItem("Failed Units", format("%d", failedCount)),
        ];
        return r;
    }

    private PanelReport unitStatus(string unit)
    {
        PanelReport r;
        r.panel = name;
        r.action = "status";

        auto active = runCommand(["systemctl", "is-active", unit]);
        auto enabled = runCommand(["systemctl", "is-enabled", unit]);

        r.ok = !active.missingBinary;
        if (!r.ok)
        {
            r.errorMessage = "systemctl is not available on this host.";
            return r;
        }

        r.summary = format("Service '%s' is %s", unit, active.output.length > 0 ? active.output : "unknown");
        r.items = [
            SettingItem("Unit", unit),
            SettingItem("Active State", active.output.length > 0 ? active.output : "unknown"),
            SettingItem("Boot Enabled", enabled.output.length > 0 ? enabled.output : "unknown"),
        ];
        return r;
    }

    private PanelReport listRunning(const string[] args)
    {
        import std.conv : to;

        size_t limit = 15;
        if (args.length > 0)
        {
            try
                limit = args[0].to!size_t;
            catch (Exception)
                limit = 15;
        }

        PanelReport r;
        r.panel = name;
        r.action = "list";

        auto cmd = runCommand(["systemctl", "list-units", "--type=service", "--state=running", "--no-legend", "--plain"]);
        if (cmd.exitCode != 0)
        {
            r.ok = false;
            r.errorMessage = "Unable to list services: " ~ cmd.output;
            return r;
        }

        r.ok = true;
        size_t shown = 0;
        foreach (line; cmd.output.lineSplitter())
        {
            if (shown >= limit)
                break;
            auto parts = line.split();
            if (parts.length >= 4)
            {
                auto desc = parts.length > 4 ? line[line.indexOfSafe(parts[4]) .. $].strip() : "";
                r.items ~= SettingItem(parts[0], desc.length > 0 ? desc : parts[3], parts[2] ~ "/" ~ parts[3]);
                shown++;
            }
        }
        r.summary = format("Showing %d running service(s)", shown);
        return r;
    }

    private PanelReport controlUnit(string verb, const string[] args, const ExecContext ctx)
    {
        PanelReport r;
        r.panel = name;
        r.action = verb;
        r.dryRun = ctx.dryRun;

        if (args.length < 1 || args[0].strip().length == 0)
        {
            r.ok = false;
            r.errorMessage = format("Missing unit name. Usage: oma services %s <unit>", verb);
            return r;
        }

        auto unit = args[0].strip();
        auto cmd = ["systemctl", verb, unit];
        auto res = applyCommand(cmd, ctx.dryRun, true);
        r.plannedCommands ~= res.renderedCommand;

        if (ctx.dryRun)
        {
            r.ok = true;
            r.summary = format("Dry-run: would %s service '%s'.", verb, unit);
            r.items = [SettingItem("Unit", unit), SettingItem("Operation", verb)];
            r.warnings ~= "Pass --apply (or set dryRun=false in config) to apply this change.";
            return r;
        }

        r.ok = (res.exitCode == 0);
        if (r.ok)
            r.summary = format("Executed `systemctl %s %s`.", verb, unit);
        else
            r.errorMessage = res.output;
        return r;
    }
}

private size_t indexOfSafe(string haystack, string needle) @safe pure
{
    import std.string : indexOf;
    auto idx = haystack.indexOf(needle);
    return idx >= 0 ? cast(size_t) idx : 0;
}

unittest
{
    auto panel = new ServicesPanel();
    ExecContext ctx;
    ctx.dryRun = true;

    auto res = panel.execute("restart", ["ssh.service"], ctx);
    assert(res.ok);
    assert(res.dryRun);
    assert(res.plannedCommands == ["systemctl restart ssh.service"]);
}

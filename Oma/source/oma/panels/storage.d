/**
 * `storage` Control Panel — Disk usage and mounted filesystems inspection.
 *
 * Spec_Ref: https://dlang.org/spec/class.html
 */
module oma.panels.storage;

import oma.output : PanelReport, SettingItem;
import oma.panels : ControlPanel, ExecContext, PanelActionSpec, panelHelpReport, unknownActionReport;
import oma.sys : readFileOr, runCommand;
import std.algorithm : startsWith;
import std.format : format;
import std.string : lineSplitter, split, strip;

/// Linux storage usage and mount inspection panel.
class StoragePanel : ControlPanel
{
    private static immutable PanelActionSpec[] _actions = [
        PanelActionSpec("status", "status", "Show disk usage for mounted filesystems",    false),
        PanelActionSpec("mounts", "mounts", "List physical block mounts from /proc/mounts", false),
        PanelActionSpec("help",   "help",   "List available actions for the storage panel", false),
    ];

    override string name() const @safe pure nothrow => "storage";
    override string summary() const @safe pure nothrow => "Disk usage & mounted Linux filesystems";
    override const(PanelActionSpec)[] actions() const @safe pure nothrow => _actions;

    override PanelReport execute(string action, const string[] args, const ExecContext ctx)
    {
        switch (action)
        {
            case "", "status", "show":
                return inspectUsage();
            case "mounts":
                return inspectMounts();
            case "help":
                return panelHelpReport(this);
            default:
                return unknownActionReport(this, action);
        }
    }

    private PanelReport inspectUsage()
    {
        PanelReport r;
        r.panel = name;
        r.action = "status";

        auto dfCmd = runCommand(["df", "-h", "-P", "-x", "tmpfs", "-x", "devtmpfs", "-x", "squashfs", "-x", "efivarfs"]);
        if (dfCmd.exitCode != 0)
        {
            r.ok = false;
            r.errorMessage = "Failed to query disk usage via `df`: " ~ dfCmd.output;
            return r;
        }

        r.ok = true;
        bool first = true;
        foreach (line; dfCmd.output.lineSplitter())
        {
            if (first)
            {
                first = false;
                continue;
            }
            auto parts = line.split();
            if (parts.length >= 6)
            {
                auto mountPoint = parts[5];
                auto summaryVal = format("%s / %s used (%s, %s free)", parts[2], parts[1], parts[4], parts[3]);
                r.items ~= SettingItem(mountPoint, summaryVal, parts[0]);
            }
        }
        r.summary = format("%d filesystem(s) reported", r.items.length);
        return r;
    }

    private PanelReport inspectMounts()
    {
        PanelReport r;
        r.panel = name;
        r.action = "mounts";
        r.ok = true;

        auto raw = readFileOr("/proc/mounts");
        foreach (line; raw.lineSplitter())
        {
            auto parts = line.split();
            if (parts.length >= 4 && parts[0].startsWith("/dev/"))
            {
                r.items ~= SettingItem(parts[1], format("%s (%s)", parts[0], parts[2]), parts[3]);
            }
        }
        r.summary = format("%d block device mount(s)", r.items.length);
        return r;
    }
}

unittest
{
    auto panel = new StoragePanel();
    ExecContext ctx;
    auto helpRes = panel.execute("help", [], ctx);
    assert(helpRes.ok);
    assert(helpRes.items.length == 3);
}

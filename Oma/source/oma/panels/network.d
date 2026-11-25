/**
 * `network` Control Panel — Interfaces, IP addresses, default route, and DNS configuration.
 *
 * Spec_Ref: https://dlang.org/spec/class.html
 */
module oma.panels.network;

import oma.output : PanelReport, SettingItem;
import oma.panels : ControlPanel, ExecContext, PanelActionSpec, panelHelpReport, unknownActionReport;
import oma.sys : applyCommand, parseResolvConf, readFileOr, runCommand;
import std.array : join;
import std.format : format;
import std.string : lineSplitter, split, strip;

/// Linux network inspection and DNS settings panel.
class NetworkPanel : ControlPanel
{
    private static immutable PanelActionSpec[] _actions = [
        PanelActionSpec("status",     "status",                        "Show interfaces, default route & DNS servers", false),
        PanelActionSpec("interfaces", "interfaces",                    "List network interfaces and IP addresses",     false),
        PanelActionSpec("dns",        "dns",                           "Inspect configured DNS resolvers",             false),
        PanelActionSpec("set-dns",    "set-dns <connection> <dns...>", "Configure DNS servers via nmcli",              true),
        PanelActionSpec("help",       "help",                          "List available actions for the network panel", false),
    ];

    override string name() const @safe pure nothrow => "network";
    override string summary() const @safe pure nothrow => "Network interfaces, routes & DNS resolvers";
    override const(PanelActionSpec)[] actions() const @safe pure nothrow => _actions;

    override PanelReport execute(string action, const string[] args, const ExecContext ctx)
    {
        switch (action)
        {
            case "", "status", "show":
                return inspectStatus();
            case "interfaces", "ifaces":
                return inspectInterfaces();
            case "dns":
                return inspectDns();
            case "set-dns":
                return setDns(args, ctx);
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

        auto route = runCommand(["ip", "route", "show", "default"]);
        string defaultRoute = (route.exitCode == 0 && route.output.length > 0)
            ? route.output.lineSplitter().front.strip()
            : "none";

        auto dnsServers = parseResolvConf(readFileOr("/etc/resolv.conf"));
        string dnsStr = dnsServers.length > 0 ? dnsServers.join(", ") : "none detected";

        r.items ~= SettingItem("Default Route", defaultRoute);
        r.items ~= SettingItem("DNS Servers", dnsStr, "/etc/resolv.conf");

        auto ipCmd = runCommand(["ip", "-brief", "addr"]);
        if (ipCmd.exitCode == 0 && ipCmd.output.length > 0)
        {
            size_t count = 0;
            foreach (line; ipCmd.output.lineSplitter())
            {
                auto parts = line.split();
                if (parts.length >= 2)
                {
                    auto addr = parts.length >= 3 ? parts[2 .. $].join(", ") : "no address";
                    r.items ~= SettingItem("iface:" ~ parts[0], addr, parts[1]);
                    count++;
                }
            }
            r.summary = format("%d interface(s) detected", count);
        }
        else
        {
            r.summary = "Network summary (ip command unavailable)";
            r.warnings ~= "Could not query `ip -brief addr`.";
        }
        return r;
    }

    private PanelReport inspectInterfaces()
    {
        PanelReport r;
        r.panel = name;
        r.action = "interfaces";
        auto ipCmd = runCommand(["ip", "-brief", "addr"]);

        if (ipCmd.exitCode != 0)
        {
            r.ok = false;
            r.errorMessage = "Failed to inspect interfaces via `ip`: " ~ ipCmd.output;
            return r;
        }

        r.ok = true;
        foreach (line; ipCmd.output.lineSplitter())
        {
            auto parts = line.split();
            if (parts.length >= 2)
            {
                auto addrs = parts.length >= 3 ? parts[2 .. $].join(", ") : "(unassigned)";
                r.items ~= SettingItem(parts[0], addrs, parts[1]);
            }
        }
        r.summary = format("%d network interface(s)", r.items.length);
        return r;
    }

    private PanelReport inspectDns()
    {
        PanelReport r;
        r.panel = name;
        r.action = "dns";
        r.ok = true;

        auto servers = parseResolvConf(readFileOr("/etc/resolv.conf"));
        foreach (i, s; servers)
            r.items ~= SettingItem(format("Nameserver #%d", i + 1), s, "/etc/resolv.conf");

        r.summary = servers.length > 0
            ? format("%d DNS nameserver(s) configured", servers.length)
            : "No nameserver entries found in /etc/resolv.conf";
        return r;
    }

    private PanelReport setDns(const string[] args, const ExecContext ctx)
    {
        PanelReport r;
        r.panel = name;
        r.action = "set-dns";
        r.dryRun = ctx.dryRun;

        if (args.length < 2)
        {
            r.ok = false;
            r.errorMessage = "Usage: oma network set-dns <connection-name> <dns1> [dns2 ...]";
            return r;
        }

        auto conn = args[0];
        auto dnsList = args[1 .. $].join(" ");
        auto cmd = ["nmcli", "connection", "modify", conn, "ipv4.dns", dnsList];
        auto res = applyCommand(cmd, ctx.dryRun, true);
        r.plannedCommands ~= res.renderedCommand;

        if (ctx.dryRun)
        {
            r.ok = true;
            r.summary = format("Dry-run: would set IPv4 DNS for '%s' to '%s'.", conn, dnsList);
            r.items = [
                SettingItem("Connection", conn),
                SettingItem("DNS Servers", dnsList),
            ];
            r.warnings ~= "Pass --apply (or set dryRun=false in config) to apply this change.";
            return r;
        }

        r.ok = (res.exitCode == 0);
        if (r.ok)
            r.summary = format("Updated DNS for '%s' to '%s'.", conn, dnsList);
        else
            r.errorMessage = res.output;
        return r;
    }
}

unittest
{
    auto panel = new NetworkPanel();
    ExecContext ctx;
    ctx.dryRun = true;

    auto res = panel.execute("set-dns", ["Wired", "1.1.1.1", "9.9.9.9"], ctx);
    assert(res.ok);
    assert(res.dryRun);
    assert(res.plannedCommands.length == 1);
}

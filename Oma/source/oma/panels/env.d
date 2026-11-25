/**
 * `env` Control Panel — User identity, shell, editor, locale, XDG directories, and `PATH`.
 *
 * Uses Phobos `std.process.environment`, `std.algorithm`, and POSIX `core.sys.posix.unistd`.
 *
 * Spec_Ref: https://dlang.org/spec/class.html
 */
module oma.panels.env;

import core.sys.posix.unistd : geteuid, getuid;
import oma.output : PanelReport, SettingItem;
import oma.panels : ControlPanel, ExecContext, PanelActionSpec, panelHelpReport, unknownActionReport;
import std.algorithm : filter, splitter;
import std.array : array;
import std.format : format;
import std.process : environment;

/// User environment, shell, locale, and PATH inspection panel.
class EnvPanel : ControlPanel
{
    private static immutable PanelActionSpec[] _actions = [
        PanelActionSpec("status", "status", "Show user, shell, editor, locale & XDG base paths", false),
        PanelActionSpec("path",   "path",   "Inspect ordered PATH directories",                  false),
        PanelActionSpec("help",   "help",   "List available actions for the env panel",          false),
    ];

    override string name() const @safe pure nothrow => "env";
    override string summary() const @safe pure nothrow => "User identity, shell, locale, XDG paths & PATH";
    override const(PanelActionSpec)[] actions() const @safe pure nothrow => _actions;

    override PanelReport execute(string action, const string[] args, const ExecContext ctx)
    {
        switch (action)
        {
            case "", "status", "show":
                return inspectStatus();
            case "path":
                return inspectPath();
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

        auto user = environment.get("USER", "unknown");
        auto shell = environment.get("SHELL", "unknown");
        auto editor = environment.get("VISUAL", environment.get("EDITOR", "(unset)"));
        auto lang = environment.get("LANG", "(unset)");
        auto desktop = environment.get("XDG_CURRENT_DESKTOP", "(headless/unset)");
        auto session = environment.get("XDG_SESSION_TYPE", "(unset)");
        auto configHome = environment.get("XDG_CONFIG_HOME", environment.get("HOME", "~") ~ "/.config");

        r.summary = format("User '%s' (uid=%d, euid=%d)", user, getuid(), geteuid());
        r.items = [
            SettingItem("User", format("%s (uid=%d, euid=%d)", user, getuid(), geteuid())),
            SettingItem("Shell", shell),
            SettingItem("Editor", editor),
            SettingItem("Locale (LANG)", lang),
            SettingItem("Desktop", desktop),
            SettingItem("Session Type", session),
            SettingItem("XDG Config Home", configHome),
        ];
        return r;
    }

    private PanelReport inspectPath()
    {
        PanelReport r;
        r.panel = name;
        r.action = "path";
        r.ok = true;

        auto rawPath = environment.get("PATH", "");
        auto entries = rawPath.splitter(':').filter!(p => p.length > 0).array;
        foreach (i, dir; entries)
            r.items ~= SettingItem(format("#%02d", i + 1), dir);

        r.summary = format("%d PATH entries", entries.length);
        return r;
    }
}

unittest
{
    auto panel = new EnvPanel();
    ExecContext ctx;
    auto res = panel.execute("status", [], ctx);
    assert(res.ok);
    assert(res.items.length >= 6);
}

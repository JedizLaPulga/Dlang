/**
 * Modular Control Panel interface and registry.
 *
 * Every Linux settings domain in Oma implements `ControlPanel` and registers
 * with `PanelRegistry`. This keeps each domain isolated, testable, and easy
 * to extend without modifying core CLI or REPL routing.
 *
 * Spec_Ref: https://dlang.org/spec/interface.html
 * Spec_Ref: https://dlang.org/spec/module.html#package_module
 */
module oma.panels;

import oma.output : PanelReport, SettingItem;
import oma.panels.env : EnvPanel;
import oma.panels.network : NetworkPanel;
import oma.panels.power : PowerPanel;
import oma.panels.services : ServicesPanel;
import oma.panels.storage : StoragePanel;
import oma.panels.system : SystemPanel;
import std.algorithm : sort;

/// Describes a single sub-action exposed by a `ControlPanel`.
struct PanelActionSpec
{
    string name;
    string usage;
    string description;
    bool mutating = false;
}

/// Execution context passed to every panel invocation.
struct ExecContext
{
    /// When `true`, mutating actions preview planned commands without changing system state.
    bool dryRun = true;

    /// When `true`, output is destined for `--json`.
    bool jsonMode = false;

    /// When `true`, verbose diagnostics are enabled.
    bool verbose = false;
}

/// Contract implemented by all modular Oma Linux control panels.
interface ControlPanel
{
    /// Unique lowercase identifier used on the CLI and REPL (e.g., `"system"`, `"network"`).
    string name() const @safe pure nothrow;

    /// Concise summary shown in `oma panels` and help screens.
    string summary() const @safe pure nothrow;

    /// Declares the actions supported by this panel for help discovery.
    const(PanelActionSpec)[] actions() const @safe pure nothrow;

    /// Executes `action` with `args` under `ctx` and returns a structured `PanelReport`.
    PanelReport execute(string action, const string[] args, const ExecContext ctx);
}

/// Central registry holding all available control panels.
class PanelRegistry
{
    private ControlPanel[string] _panels;
    private string[] _order;

    /// Registers a panel instance. Duplicate names replace the previous registration.
    void register(ControlPanel panel)
    in (panel !is null, "Cannot register a null panel")
    in (panel.name.length > 0, "Panel name must not be empty")
    {
        auto key = panel.name;
        if (key !in _panels)
            _order ~= key;
        _panels[key] = panel;
    }

    /// Looks up a panel by name; returns `null` if not registered.
    ControlPanel find(string name)
    {
        if (auto p = name in _panels)
            return *p;
        return null;
    }

    /// Returns all registered panels in registration order.
    ControlPanel[] all()
    {
        ControlPanel[] list;
        list.reserve(_order.length);
        foreach (key; _order)
            list ~= _panels[key];
        return list;
    }

    /// Returns registered panel names.
    string[] names() const @safe pure
    {
        return _order.dup;
    }
}

/// Builds the default `PanelRegistry` populated with Oma's built-in Linux control panels.
PanelRegistry createDefaultRegistry()
{
    auto reg = new PanelRegistry();
    reg.register(new SystemPanel());
    reg.register(new NetworkPanel());
    reg.register(new ServicesPanel());
    reg.register(new PowerPanel());
    reg.register(new StoragePanel());
    reg.register(new EnvPanel());
    return reg;
}

/// Helper for building an error `PanelReport` when a panel receives an unknown action.
PanelReport unknownActionReport(const ControlPanel panel, string action)
{
    PanelReport r;
    r.panel = panel.name;
    r.action = action;
    r.ok = false;
    r.errorMessage = "Unknown action '" ~ action ~ "' for panel '" ~ panel.name ~ "'. Run `oma " ~ panel.name ~ " help` to see available actions.";
    return r;
}

/// Helper for rendering a panel's built-in `help` report.
PanelReport panelHelpReport(const ControlPanel panel)
{
    PanelReport r;
    r.panel = panel.name;
    r.action = "help";
    r.ok = true;
    r.summary = panel.summary;
    foreach (act; panel.actions)
    {
        auto tag = act.mutating ? "write" : "read";
        r.items ~= SettingItem(act.usage, act.description, tag);
    }
    return r;
}

unittest
{
    auto reg = createDefaultRegistry();
    assert(reg.find("system") !is null);
    assert(reg.find("network") !is null);
    assert(reg.find("services") !is null);
    assert(reg.find("power") !is null);
    assert(reg.find("storage") !is null);
    assert(reg.find("env") !is null);
    assert(reg.find("nonexistent") is null);
    assert(reg.all().length == 6);
}

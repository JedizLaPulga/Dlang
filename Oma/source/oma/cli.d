/**
 * Main CLI argument parsing (`std.getopt`) and command router for Oma.
 *
 * Supports both subcommand execution (`oma <panel> <action> [args]`) and
 * interactive REPL mode (`oma` or `oma repl`), with persistent JSON config,
 * `--json`, `--no-color`, `--dry-run` / `--apply`, and `--verbose` / `--debug`.
 *
 * Spec_Ref: https://dlang.org/phobos/std_getopt.html
 */
module oma.cli;

import oma : APP_DESCRIPTION, APP_NAME, APP_VERSION, DLANG_SPEC_URL, PHOBOS_URL;
import oma.config : defaultConfigPath, getConfigKey, loadConfig, OmaConfig, saveConfig, setConfigKey;
import oma.logging : configureLogging;
import oma.output : OutputFormatter, PanelReport, SettingItem, shouldUseColor;
import oma.panels : createDefaultRegistry, ExecContext, PanelRegistry;
import oma.repl : runRepl;
import std.format : format;
import std.getopt : config, getopt, GetOptException;
import std.json : JSONValue;
import std.stdio : stderr, stdout, writefln, writeln;

/// Parses CLI flags, loads local config, and dispatches to the requested command or REPL.
int run(string[] args)
{
    bool flagHelp = false;
    bool flagVersion = false;
    bool flagJson = false;
    bool flagNoColor = false;
    bool flagDryRun = false;
    bool flagApply = false;
    bool flagVerbose = false;
    bool flagDebug = false;
    bool flagQuiet = false;
    string flagConfigPath = "";

    auto parseArgs = args.dup;
    try
    {
        // `stopOnFirstNonOption` preserves subcommand-specific arguments after the subcommand.
        getopt(
            parseArgs,
            config.stopOnFirstNonOption,
            "h|help",     &flagHelp,
            "V|version",  &flagVersion,
            "json",       &flagJson,
            "no-color",   &flagNoColor,
            "dry-run",    &flagDryRun,
            "apply",      &flagApply,
            "v|verbose",  &flagVerbose,
            "debug",      &flagDebug,
            "q|quiet",    &flagQuiet,
            "config",     &flagConfigPath,
        );
    }
    catch (GetOptException e)
    {
        stderr.writefln("Error: %s", e.msg);
        stderr.writeln("Run `oma --help` for usage.");
        return 2;
    }

    // Configure logging early so `loadConfig` respects default warning level unless `-v`/`--debug` is passed.
    configureLogging(flagVerbose, flagDebug, flagQuiet);

    auto cfgPath = flagConfigPath.length > 0 ? flagConfigPath : defaultConfigPath();
    auto cfg = loadConfig(cfgPath);

    bool effectiveVerbose = flagVerbose || cfg.verbose;
    if (effectiveVerbose != flagVerbose)
        configureLogging(effectiveVerbose, flagDebug, flagQuiet);

    bool effectiveJson = flagJson || cfg.jsonOutput;
    bool effectiveColor = shouldUseColor(cfg.color, flagNoColor);
    bool effectiveDryRun = flagApply ? false : (flagDryRun ? true : cfg.dryRun);

    auto fmt = OutputFormatter(effectiveColor, effectiveJson);
    auto ctx = ExecContext(effectiveDryRun, effectiveJson, effectiveVerbose);
    auto registry = createDefaultRegistry();

    auto positional = parseArgs.length > 1 ? parseArgs[1 .. $] : [];

    if (flagVersion)
    {
        printVersion(fmt);
        return 0;
    }

    if (flagHelp)
    {
        printMainHelp(registry, fmt);
        return 0;
    }

    // No subcommand -> launch interactive REPL mode.
    if (positional.length == 0)
        return runRepl(registry, cfg, cfgPath, ctx, fmt);

    auto cmd = positional[0];
    auto rest = positional.length > 1 ? positional[1 .. $] : [];

    switch (cmd)
    {
        case "help":
            if (rest.length > 0)
            {
                if (auto p = registry.find(rest[0]))
                {
                    fmt.renderReport(p.execute("help", [], ctx));
                    return 0;
                }
                stderr.writefln("Unknown panel '%s'.", rest[0]);
                return 1;
            }
            printMainHelp(registry, fmt);
            return 0;

        case "version":
            printVersion(fmt);
            return 0;

        case "panels":
            PanelReport r;
            r.panel = APP_NAME;
            r.action = "panels";
            r.ok = true;
            r.summary = format("%d modular Linux control panel(s)", registry.all().length);
            foreach (p; registry.all())
                r.items ~= SettingItem(p.name, p.summary);
            fmt.renderReport(r);
            return 0;

        case "status":
            PanelReport[] reports;
            foreach (p; registry.all())
                reports ~= p.execute("status", [], ctx);
            fmt.renderReports(reports);
            return 0;

        case "repl", "shell":
            return runRepl(registry, cfg, cfgPath, ctx, fmt);

        case "config":
            return handleConfigCommand(rest, cfg, cfgPath, fmt);

        default:
            break;
    }

    // Panel dispatch: `oma <panel> [action] [args...]`
    if (auto panel = registry.find(cmd))
    {
        auto action = rest.length > 0 ? rest[0] : "status";
        auto actionArgs = rest.length > 1 ? rest[1 .. $] : [];
        auto report = panel.execute(action, actionArgs, ctx);
        fmt.renderReport(report);
        return report.ok ? 0 : 1;
    }

    PanelReport errReport;
    errReport.panel = APP_NAME;
    errReport.action = cmd;
    errReport.ok = false;
    errReport.errorMessage = format("Unknown command or panel '%s'. Run `oma --help` or `oma panels`.", cmd);
    fmt.renderReport(errReport);
    return 2;
}

private int handleConfigCommand(const string[] args, ref OmaConfig cfg, string cfgPath, const OutputFormatter fmt)
{
    auto action = args.length > 0 ? args[0] : "show";

    switch (action)
    {
        case "show":
            fmt.renderKeyValues("config", [
                SettingItem("path", cfgPath),
                SettingItem("color", cfg.color ? "true" : "false"),
                SettingItem("jsonOutput", cfg.jsonOutput ? "true" : "false"),
                SettingItem("dryRun", cfg.dryRun ? "true" : "false"),
                SettingItem("defaultPanel", cfg.defaultPanel.length > 0 ? cfg.defaultPanel : "(none)"),
                SettingItem("verbose", cfg.verbose ? "true" : "false"),
            ]);
            return 0;

        case "path":
            if (fmt.jsonMode)
            {
                JSONValue obj = JSONValue.emptyObject;
                obj["path"] = cfgPath;
                writeln(obj.toPrettyString());
            }
            else
            {
                writeln(cfgPath);
            }
            return 0;

        case "get":
            if (args.length < 2)
            {
                stderr.writeln("Usage: oma config get <key>");
                return 2;
            }
            string val;
            if (!getConfigKey(cfg, args[1], val))
            {
                stderr.writefln("Unknown config key '%s'.", args[1]);
                return 1;
            }
            fmt.renderKeyValues("config", [SettingItem(args[1], val)]);
            return 0;

        case "set":
            if (args.length < 3)
            {
                stderr.writeln("Usage: oma config set <key> <value>");
                return 2;
            }
            string err;
            if (!setConfigKey(cfg, args[1], args[2], err))
            {
                stderr.writeln(err);
                return 1;
            }
            saveConfig(cfg, cfgPath);
            PanelReport r;
            r.panel = "config";
            r.action = "set";
            r.ok = true;
            r.summary = format("Saved '%s' = '%s' to %s", args[1], args[2], cfgPath);
            r.items = [SettingItem(args[1], args[2])];
            fmt.renderReport(r);
            return 0;

        case "reset":
            cfg = OmaConfig.init;
            saveConfig(cfg, cfgPath);
            PanelReport r;
            r.panel = "config";
            r.action = "reset";
            r.ok = true;
            r.summary = format("Reset configuration to defaults at %s", cfgPath);
            fmt.renderReport(r);
            return 0;

        default:
            stderr.writefln("Unknown config action '%s'. Valid: show, path, get, set, reset.", action);
            return 2;
    }
}

private void printVersion(const OutputFormatter fmt)
{
    if (fmt.jsonMode)
    {
        JSONValue obj = JSONValue.emptyObject;
        obj["name"] = APP_NAME;
        obj["version"] = APP_VERSION;
        obj["description"] = APP_DESCRIPTION;
        obj["dlangSpec"] = DLANG_SPEC_URL;
        obj["phobos"] = PHOBOS_URL;
        writeln(obj.toPrettyString());
        return;
    }

    writefln("%s %s — %s", fmt.bold(fmt.cyan(APP_NAME)), APP_VERSION, APP_DESCRIPTION);
}

private void printMainHelp(PanelRegistry registry, const OutputFormatter fmt)
{
    if (fmt.jsonMode)
    {
        PanelReport r;
        r.panel = APP_NAME;
        r.action = "help";
        r.ok = true;
        r.summary = APP_DESCRIPTION;
        foreach (p; registry.all())
            r.items ~= SettingItem(p.name, p.summary);
        fmt.renderReport(r);
        return;
    }

    writeln(fmt.bold(fmt.cyan(format("%s v%s", APP_NAME, APP_VERSION))) ~ " — " ~ APP_DESCRIPTION);
    writeln();
    writeln(fmt.bold("USAGE:"));
    writeln("  oma [global-options]                      Launch interactive REPL");
    writeln("  oma [global-options] <command> [args...]  Run a built-in command");
    writeln("  oma [global-options] <panel> [action]     Inspect or modify a Linux panel");
    writeln();
    writeln(fmt.bold("GLOBAL OPTIONS:"));
    writeln("  --json            Emit machine-readable JSON output (std.json)");
    writeln("  --no-color        Disable ANSI terminal styling (also honors NO_COLOR)");
    writeln("  --dry-run         Preview mutating commands without executing (default)");
    writeln("  --apply           Execute mutating commands (overrides dry-run)");
    writeln("  --config=<path>   Use an alternate JSON config file");
    writeln("  -v, --verbose     Enable informational logs on stderr (std.logger)");
    writeln("  --debug           Enable trace-level logs on stderr");
    writeln("  -q, --quiet       Suppress non-error logs");
    writeln("  -V, --version     Show version information");
    writeln("  -h, --help        Show this help screen");
    writeln();
    writeln(fmt.bold("CORE COMMANDS:"));
    writeln("  panels            List all registered Linux control panels");
    writeln("  status            Show a combined overview across all panels");
    writeln("  repl              Start the interactive control-panel shell");
    writeln("  config            Manage local Oma settings (show|get|set|path|reset)");
    writeln("  help [panel]      Show general help or a panel's actions");
    writeln();
    import std.string : leftJustify;

    writeln(fmt.bold("CONTROL PANELS:"));
    foreach (p; registry.all())
        writefln("  %s  %s", fmt.cyan(leftJustify(p.name, 14)), p.summary);
    writeln();
    writeln(fmt.dim("Examples:"));
    writeln(fmt.dim("  oma system status"));
    writeln(fmt.dim("  oma --json network dns"));
    writeln(fmt.dim("  oma system set-hostname devbox         # safe dry-run preview"));
    writeln(fmt.dim("  sudo oma --apply system set-hostname devbox"));
}

unittest
{
    assert(run(["oma", "--version", "--no-color"]) == 0);
    assert(run(["oma", "--json", "panels"]) == 0);
    assert(run(["oma", "unknown-panel-xyz", "--no-color"]) == 2);
}

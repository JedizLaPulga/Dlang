/**
 * Interactive REPL (Read-Eval-Print Loop) for Oma.
 *
 * Allows navigating Linux control panels conversationally, switching panel contexts
 * with `use <panel>`, toggling `dry-run` / `json` / `color` modes on the fly, and
 * inspecting or modifying settings safely.
 *
 * Spec_Ref: https://dlang.org/spec/statement.html#while-statement
 * Spec_Ref: https://dlang.org/phobos/std_stdio.html
 */
module oma.repl;

import oma : APP_NAME, APP_VERSION;
import oma.config : OmaConfig, parseBool, saveConfig, setConfigKey;
import oma.output : OutputFormatter, PanelReport, SettingItem;
import oma.panels : ControlPanel, ExecContext, panelHelpReport, PanelRegistry;
import std.format : format;
import std.stdio : readln, stdin, stdout, write, writefln, writeln;
import std.string : strip;

/// Tokenizes a single REPL input line, respecting single and double quotes.
string[] tokenizeInput(string line) @safe pure
{
    string[] tokens;
    string current;
    bool inToken = false;
    char quote = '\0';

    foreach (char c; line)
    {
        if (quote != '\0')
        {
            if (c == quote)
                quote = '\0';
            else
                current ~= c;
        }
        else if (c == '"' || c == '\'')
        {
            quote = c;
            inToken = true;
        }
        else if (c == ' ' || c == '\t')
        {
            if (inToken)
            {
                tokens ~= current;
                current = "";
                inToken = false;
            }
        }
        else
        {
            current ~= c;
            inToken = true;
        }
    }

    if (inToken)
        tokens ~= current;

    return tokens;
}

/// Runs the interactive Oma Control Panel shell until `exit`, `quit`, or EOF.
int runRepl(PanelRegistry registry, ref OmaConfig cfg, string configPath, ref ExecContext ctx, ref OutputFormatter fmt)
{
    string activePanel = "";
    if (cfg.defaultPanel.length > 0 && registry.find(cfg.defaultPanel) !is null)
        activePanel = cfg.defaultPanel;

    if (!fmt.jsonMode)
    {
        writeln(fmt.bold(fmt.cyan(format("%s v%s — Interactive Linux Control Panel", APP_NAME, APP_VERSION))));
        writeln(fmt.dim(format("Mode: dry-run=%s · json=%s · Type 'help' for commands, 'panels' to browse, 'exit' to quit.",
            ctx.dryRun ? "on" : "off", fmt.jsonMode ? "on" : "off")));
        writeln();
    }

    while (true)
    {
        if (!fmt.jsonMode)
        {
            auto modeTag = ctx.dryRun ? fmt.yellow("dry") : fmt.red("live");
            if (activePanel.length > 0)
                write(format("%s [%s|%s]> ", fmt.bold(fmt.cyan(APP_NAME)), fmt.green(activePanel), modeTag));
            else
                write(format("%s [%s]> ", fmt.bold(fmt.cyan(APP_NAME)), modeTag));
            stdout.flush();
        }

        string rawLine = readln();
        if (rawLine is null)
        {
            if (!fmt.jsonMode)
                writeln();
            break;
        }

        auto tokens = tokenizeInput(rawLine.strip());
        if (tokens.length == 0)
            continue;

        auto cmd = tokens[0];
        auto rest = tokens.length > 1 ? tokens[1 .. $] : [];

        switch (cmd)
        {
            case "exit", "quit", "q":
                return 0;

            case "help", "?":
                printReplHelp(registry, activePanel, fmt);
                continue;

            case "panels", "ls":
                PanelReport r;
                r.panel = APP_NAME;
                r.action = "panels";
                r.ok = true;
                r.summary = format("%d modular control panel(s) registered", registry.all().length);
                foreach (p; registry.all())
                    r.items ~= SettingItem(p.name, p.summary);
                fmt.renderReport(r);
                continue;

            case "use":
                if (rest.length == 0)
                {
                    activePanel = "";
                    writeln(fmt.dim("Returned to root context."));
                }
                else if (registry.find(rest[0]) !is null)
                {
                    activePanel = rest[0];
                    writeln(fmt.green("Switched active panel to '" ~ activePanel ~ "'."));
                }
                else
                {
                    writeln(fmt.red("Unknown panel: '" ~ rest[0] ~ "'. Run 'panels' to see available panels."));
                }
                continue;

            case "back", "..":
                activePanel = "";
                writeln(fmt.dim("Returned to root context."));
                continue;

            case "dry-run":
                if (rest.length == 0)
                {
                    writeln(format("dry-run is currently %s", ctx.dryRun ? "on" : "off"));
                }
                else
                {
                    bool v;
                    if (parseBool(rest[0], v))
                    {
                        ctx.dryRun = v;
                        writeln(fmt.yellow(format("dry-run set to %s", v ? "on" : "off")));
                    }
                    else
                    {
                        writeln(fmt.red("Usage: dry-run [on|off]"));
                    }
                }
                continue;

            case "json":
                if (rest.length == 0)
                {
                    writeln(format("json output is currently %s", fmt.jsonMode ? "on" : "off"));
                }
                else
                {
                    bool v;
                    if (parseBool(rest[0], v))
                    {
                        fmt.jsonMode = v;
                        ctx.jsonMode = v;
                        if (!v)
                            writeln("json output disabled.");
                    }
                    else
                    {
                        writeln(fmt.red("Usage: json [on|off]"));
                    }
                }
                continue;

            case "color":
                if (rest.length > 0)
                {
                    bool v;
                    if (parseBool(rest[0], v))
                        fmt.useColor = v;
                    else
                        writeln(fmt.red("Usage: color [on|off]"));
                }
                else
                {
                    writeln(format("color is currently %s", fmt.useColor ? "on" : "off"));
                }
                continue;

            case "config":
                handleReplConfig(rest, cfg, configPath, fmt);
                continue;

            default:
                break;
        }

        // Dispatch: either `<panel> [action] [args...]` or, if inside an active panel, `<action> [args...]`.
        if (auto directPanel = registry.find(cmd))
        {
            auto action = rest.length > 0 ? rest[0] : "status";
            auto args = rest.length > 1 ? rest[1 .. $] : [];
            fmt.renderReport(directPanel.execute(action, args, ctx));
            continue;
        }

        if (activePanel.length > 0)
        {
            auto p = registry.find(activePanel);
            if (p !is null)
            {
                fmt.renderReport(p.execute(cmd, rest, ctx));
                continue;
            }
        }

        if (cmd == "status")
        {
            PanelReport[] reports;
            foreach (p; registry.all())
                reports ~= p.execute("status", [], ctx);
            fmt.renderReports(reports);
            continue;
        }

        writeln(fmt.red(format("Unknown command '%s'. Type 'help' or 'panels'.", cmd)));
    }

    return 0;
}

private void handleReplConfig(const string[] args, ref OmaConfig cfg, string configPath, const OutputFormatter fmt)
{
    if (args.length == 0 || args[0] == "show")
    {
        fmt.renderKeyValues("config", [
            SettingItem("path", configPath),
            SettingItem("color", cfg.color ? "true" : "false"),
            SettingItem("jsonOutput", cfg.jsonOutput ? "true" : "false"),
            SettingItem("dryRun", cfg.dryRun ? "true" : "false"),
            SettingItem("defaultPanel", cfg.defaultPanel.length > 0 ? cfg.defaultPanel : "(none)"),
            SettingItem("verbose", cfg.verbose ? "true" : "false"),
        ]);
        return;
    }

    if (args[0] == "set" && args.length >= 3)
    {
        string err;
        if (!setConfigKey(cfg, args[1], args[2], err))
        {
            writeln(fmt.red(err));
            return;
        }
        saveConfig(cfg, configPath);
        writeln(fmt.green(format("Updated '%s' = '%s' and saved to %s", args[1], args[2], configPath)));
        return;
    }

    writeln(fmt.red("Usage: config [show | set <key> <value>]"));
}

private void printReplHelp(PanelRegistry registry, string activePanel, const OutputFormatter fmt)
{
    if (activePanel.length > 0)
    {
        if (auto p = registry.find(activePanel))
        {
            fmt.renderReport(panelHelpReport(p));
            writeln();
            writeln(fmt.dim("REPL controls: back | panels | dry-run [on|off] | json [on|off] | config | exit"));
            return;
        }
    }

    writeln(fmt.bold("Interactive Commands:"));
    writeln("  panels                   List all Linux control panels");
    writeln("  status                   Show overview status across all panels");
    writeln("  use <panel>              Enter a panel context (e.g., `use system`)");
    writeln("  back                     Return to root prompt");
    writeln("  <panel> <action> [args]  Run any panel command directly");
    writeln("  dry-run [on|off]         Toggle safe preview mode for write actions");
    writeln("  json [on|off]            Toggle structured JSON output");
    writeln("  color [on|off]           Toggle ANSI color styling");
    writeln("  config [show|set k v]    Inspect or persist local config");
    writeln("  exit / quit              Exit Oma REPL");
}

unittest
{
    assert(tokenizeInput(`system set-hostname "my dev box"`) == ["system", "set-hostname", "my dev box"]);
    assert(tokenizeInput(`  network   set-dns 'Wired 1' 1.1.1.1  `) == ["network", "set-dns", "Wired 1", "1.1.1.1"]);
    assert(tokenizeInput("").length == 0);
}

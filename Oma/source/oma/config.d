/**
 * Local XDG-compliant JSON configuration persistence using Phobos
 * (`std.json`, `std.file`, `std.path`, `std.process`).
 *
 * Spec_Ref: https://dlang.org/spec/struct.html
 * Spec_Ref: https://dlang.org/spec/contracts.html
 */
module oma.config;

import std.conv : to, ConvException;
import std.file : exists, mkdirRecurse, readText, write;
import std.json : JSONException, JSONType, JSONValue, parseJSON;
import std.logger : infof, warningf;
import std.path : buildPath, dirName, expandTilde;
import std.process : environment;
import std.string : toLower;

/// Persistent user configuration for Oma.
struct OmaConfig
{
    /// Enable ANSI terminal styling by default (can be overridden by `--no-color` or `NO_COLOR`).
    bool color = true;

    /// Emit machine-readable JSON output by default (`--json`).
    bool jsonOutput = false;

    /// Preview write operations without modifying Linux system state (`--dry-run`).
    bool dryRun = true;

    /// Default panel to focus on when launching the interactive REPL (empty = root prompt).
    string defaultPanel = "";

    /// Enable verbose logging by default.
    bool verbose = false;

    /// Serializes this configuration struct to a Phobos `JSONValue`.
    JSONValue toJson() const @safe
    {
        JSONValue obj = JSONValue.emptyObject;
        obj["color"] = color;
        obj["jsonOutput"] = jsonOutput;
        obj["dryRun"] = dryRun;
        obj["defaultPanel"] = defaultPanel;
        obj["verbose"] = verbose;
        return obj;
    }

    /// Populates an `OmaConfig` from a parsed `JSONValue`, falling back to defaults for missing keys.
    static OmaConfig fromJson(const JSONValue root) @safe
    {
        OmaConfig cfg;
        if (root.type != JSONType.object)
            return cfg;

        if (auto p = "color" in root)
            if (p.type == JSONType.true_ || p.type == JSONType.false_)
                cfg.color = p.boolean;

        if (auto p = "jsonOutput" in root)
            if (p.type == JSONType.true_ || p.type == JSONType.false_)
                cfg.jsonOutput = p.boolean;

        if (auto p = "dryRun" in root)
            if (p.type == JSONType.true_ || p.type == JSONType.false_)
                cfg.dryRun = p.boolean;

        if (auto p = "defaultPanel" in root)
            if (p.type == JSONType.string)
                cfg.defaultPanel = p.str;

        if (auto p = "verbose" in root)
            if (p.type == JSONType.true_ || p.type == JSONType.false_)
                cfg.verbose = p.boolean;

        return cfg;
    }
}

/// Resolves the default configuration file path following the XDG Base Directory Specification.
string defaultConfigPath()
{
    auto xdg = environment.get("XDG_CONFIG_HOME", "");
    if (xdg.length > 0)
        return buildPath(xdg, "oma", "config.json");

    auto home = environment.get("HOME", "");
    if (home.length > 0)
        return buildPath(home, ".config", "oma", "config.json");

    return expandTilde("~/.config/oma/config.json");
}

/// Loads `OmaConfig` from `path`. Returns defaults if the file does not exist or cannot be parsed.
OmaConfig loadConfig(string path)
in (path.length > 0, "Configuration path must not be empty")
{
    if (!exists(path))
    {
        infof("Config file '%s' not found; using defaults.", path);
        return OmaConfig.init;
    }

    try
    {
        auto raw = readText(path);
        auto parsed = parseJSON(raw);
        return OmaConfig.fromJson(parsed);
    }
    catch (JSONException e)
    {
        warningf("Invalid JSON in config '%s' (%s); falling back to defaults.", path, e.msg);
        return OmaConfig.init;
    }
    catch (Exception e)
    {
        warningf("Unable to read config '%s' (%s); falling back to defaults.", path, e.msg);
        return OmaConfig.init;
    }
}

/// Persists `cfg` as pretty-printed JSON at `path`, creating parent directories as needed.
void saveConfig(const OmaConfig cfg, string path)
in (path.length > 0, "Configuration path must not be empty")
{
    auto parent = dirName(path);
    if (parent.length > 0 && !exists(parent))
        mkdirRecurse(parent);

    auto payload = cfg.toJson().toPrettyString() ~ "\n";
    write(path, payload);
    infof("Saved Oma configuration to '%s'.", path);
}

/// Parses a boolean string (`true`/`false`, `on`/`off`, `1`/`0`, `yes`/`no`).
bool parseBool(string raw, out bool parsed) @safe pure
{
    switch (raw.toLower())
    {
        case "true", "on", "1", "yes":
            parsed = true;
            return true;
        case "false", "off", "0", "no":
            parsed = false;
            return true;
        default:
            return false;
    }
}

/// Updates a single named key in `cfg`. Returns `true` on success, or sets `errorMsg` on failure.
bool setConfigKey(ref OmaConfig cfg, string key, string value, out string errorMsg) @safe
{
    bool boolVal;
    switch (key)
    {
        case "color":
            if (!parseBool(value, boolVal))
            {
                errorMsg = "Expected boolean value (true/false/on/off) for 'color'.";
                return false;
            }
            cfg.color = boolVal;
            return true;

        case "jsonOutput", "json":
            if (!parseBool(value, boolVal))
            {
                errorMsg = "Expected boolean value (true/false/on/off) for 'jsonOutput'.";
                return false;
            }
            cfg.jsonOutput = boolVal;
            return true;

        case "dryRun", "dry-run":
            if (!parseBool(value, boolVal))
            {
                errorMsg = "Expected boolean value (true/false/on/off) for 'dryRun'.";
                return false;
            }
            cfg.dryRun = boolVal;
            return true;

        case "verbose":
            if (!parseBool(value, boolVal))
            {
                errorMsg = "Expected boolean value (true/false/on/off) for 'verbose'.";
                return false;
            }
            cfg.verbose = boolVal;
            return true;

        case "defaultPanel", "default-panel":
            cfg.defaultPanel = value;
            return true;

        default:
            errorMsg = "Unknown configuration key: '" ~ key ~ "'. Valid keys: color, jsonOutput, dryRun, defaultPanel, verbose.";
            return false;
    }
}

/// Retrieves a string representation of a single key in `cfg`.
bool getConfigKey(const OmaConfig cfg, string key, out string value) @safe
{
    switch (key)
    {
        case "color":
            value = cfg.color ? "true" : "false";
            return true;
        case "jsonOutput", "json":
            value = cfg.jsonOutput ? "true" : "false";
            return true;
        case "dryRun", "dry-run":
            value = cfg.dryRun ? "true" : "false";
            return true;
        case "verbose":
            value = cfg.verbose ? "true" : "false";
            return true;
        case "defaultPanel", "default-panel":
            value = cfg.defaultPanel;
            return true;
        default:
            return false;
    }
}

unittest
{
    import std.file : remove, tempDir;

    OmaConfig cfg;
    assert(cfg.color == true);
    assert(cfg.dryRun == true);
    assert(cfg.jsonOutput == false);

    string err;
    assert(setConfigKey(cfg, "dryRun", "off", err));
    assert(cfg.dryRun == false);
    assert(setConfigKey(cfg, "defaultPanel", "system", err));
    assert(cfg.defaultPanel == "system");
    assert(!setConfigKey(cfg, "color", "maybe", err));
    assert(err.length > 0);

    auto roundTrip = OmaConfig.fromJson(cfg.toJson());
    assert(roundTrip == cfg);

    auto tmpPath = buildPath(tempDir(), "oma_unittest_config.json");
    scope (exit)
    {
        if (exists(tmpPath))
            remove(tmpPath);
    }

    saveConfig(cfg, tmpPath);
    auto loaded = loadConfig(tmpPath);
    assert(loaded == cfg);
}

/**
 * Structured logging configuration powered by Phobos `std.logger`.
 *
 * Spec_Ref: https://dlang.org/phobos/std_logger.html
 */
module oma.logging;

import std.logger : FileLogger, LogLevel, sharedLog;
import std.stdio : stderr;

/// Configures the process-wide Phobos logger to write diagnostic messages to `stderr`.
/// Keeping logs on `stderr` ensures `stdout` remains clean for `--json` and shell pipelines.
LogLevel configureLogging(bool verbose, bool debugMode, bool quiet = false)
{
    LogLevel level = LogLevel.warning;

    if (quiet)
    {
        level = LogLevel.error;
    }
    else if (debugMode)
    {
        level = LogLevel.trace;
    }
    else if (verbose)
    {
        level = LogLevel.info;
    }

    // Cast to shared as required by `std.logger.sharedLog` (DMD v2.101+ / v2.111).
    sharedLog = cast(shared) new FileLogger(stderr, level);
    return level;
}

unittest
{
    assert(configureLogging(false, false, false) == LogLevel.warning);
    assert((cast() sharedLog).logLevel == LogLevel.warning);

    assert(configureLogging(true, false, false) == LogLevel.info);
    assert((cast() sharedLog).logLevel == LogLevel.info);

    assert(configureLogging(false, true, false) == LogLevel.trace);
    assert((cast() sharedLog).logLevel == LogLevel.trace);

    assert(configureLogging(true, true, true) == LogLevel.error);
    assert((cast() sharedLog).logLevel == LogLevel.error);

    // Restore default warning level after test.
    configureLogging(false, false, false);
}

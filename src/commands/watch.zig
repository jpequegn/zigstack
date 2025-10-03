const std = @import("std");
const print = std.debug.print;
const posix = std.posix;

// Core module imports
const config_mod = @import("../core/config.zig");
const file_info_mod = @import("../core/file_info.zig");
const utils = @import("../core/utils.zig");
const organization_mod = @import("../core/organization.zig");
const command_mod = @import("command.zig");

// Import organize command for applying organization
const organize_cmd = @import("organize.zig");
const watch_rules = @import("watch_rules.zig");

// Type exports
pub const Config = config_mod.Config;
pub const FileInfo = file_info_mod.FileInfo;
pub const FileCategory = file_info_mod.FileCategory;
pub const Command = command_mod.Command;

// Utility function shortcuts
const printError = utils.printError;
const printSuccess = utils.printSuccess;
const printInfo = utils.printInfo;
const printWarning = utils.printWarning;
const validateDirectory = utils.validateDirectory;

const watch_help_text =
    \\Usage: zigstack watch [OPTIONS] <directory>
    \\
    \\Monitor a directory for file changes and automatically organize new files.
    \\
    \\Arguments:
    \\  <directory>       Directory path to watch
    \\
    \\Options:
    \\  -h, --help              Display this help message
    \\  --rules <FILE>          JSON rules file for advanced organization
    \\  --validate-rules        Validate rules file and exit
    \\  --interval <SECONDS>    Check interval in seconds (default: 5)
    \\  --log <FILE>            Log file path (default: ~/.local/share/zigstack/watch.log)
    \\  --pid <FILE>            PID file path (default: ~/.local/share/zigstack/watch.pid)
    \\  --daemon                Run as background daemon (not implemented yet)
    \\  -V, --verbose           Enable verbose logging
    \\  --by-date               Organize files by date
    \\  --by-size               Organize large files separately
    \\  --size-threshold N      Size threshold for large files in MB (default: 100)
    \\  --date-format FMT       Date format: year, year-month, year-month-day
    \\
    \\Examples:
    \\  zigstack watch ~/Downloads
    \\  zigstack watch --rules watch-rules.json ~/Downloads
    \\  zigstack watch --validate-rules --rules watch-rules.json
    \\  zigstack watch --interval 10 --verbose ~/Downloads
    \\  zigstack watch --by-date --date-format year-month ~/Documents
    \\
;

/// Watch configuration
pub const WatchConfig = struct {
    interval_seconds: u64 = 5,
    log_file_path: ?[]const u8 = null,
    pid_file_path: ?[]const u8 = null,
    rules_file_path: ?[]const u8 = null,
    validate_rules_only: bool = false,
    daemon: bool = false,
    verbose: bool = false,
};

/// File state for tracking changes
pub const FileState = struct {
    path: []const u8,
    size: u64,
    mtime: i128,
};

/// Watch state for tracking directory contents
pub const WatchState = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap(FileState),
    log_file: ?std.fs.File = null,

    pub fn init(allocator: std.mem.Allocator) WatchState {
        return .{
            .allocator = allocator,
            .files = std.StringHashMap(FileState).init(allocator),
        };
    }

    pub fn deinit(self: *WatchState) void {
        var iter = self.files.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.path);
        }
        self.files.deinit();
        if (self.log_file) |file| {
            file.close();
        }
    }

    /// Open log file for writing
    pub fn openLogFile(self: *WatchState, path: []const u8) !void {
        // Create parent directories if needed
        if (std.fs.path.dirname(path)) |dir| {
            try std.fs.cwd().makePath(dir);
        }

        self.log_file = try std.fs.cwd().createFile(path, .{
            .truncate = false,
            .read = false,
        });
        try self.log_file.?.seekFromEnd(0);
    }

    /// Write to log file and stdout if verbose
    pub fn log(self: *WatchState, comptime format: []const u8, args: anytype, verbose: bool) !void {
        const timestamp = std.time.timestamp();
        const msg = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(msg);

        const log_line = try std.fmt.allocPrint(
            self.allocator,
            "[{d}] {s}\n",
            .{ timestamp, msg },
        );
        defer self.allocator.free(log_line);

        if (self.log_file) |file| {
            _ = try file.writeAll(log_line);
        }

        if (verbose) {
            print("{s}", .{log_line});
        }
    }
};

/// Write PID to file
fn writePidFile(path: []const u8) !void {
    // Create parent directories if needed
    if (std.fs.path.dirname(path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }

    const pid_file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer pid_file.close();

    const pid = std.os.linux.getpid();
    var buffer: [256]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&buffer, "{d}\n", .{pid});
    _ = try pid_file.writeAll(pid_str);
}

/// Remove PID file
fn removePidFile(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch {};
}

/// Signal handler flag for graceful shutdown
var should_exit = std.atomic.Value(bool).init(false);

/// Signal handler for SIGINT and SIGTERM
fn signalHandler(sig: c_int) callconv(.c) void {
    _ = sig;
    should_exit.store(true, .release);
}

/// Scan directory and detect changes
fn scanDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    state: *WatchState,
    config: *const WatchConfig,
) !std.ArrayListUnmanaged([]const u8) {
    var new_files = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (new_files.items) |path| {
            allocator.free(path);
        }
        new_files.deinit(allocator);
    }

    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip directories
        if (entry.kind == .directory) continue;

        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        errdefer allocator.free(full_path);

        // Get file stats
        const file = try dir.openFile(entry.name, .{});
        defer file.close();
        const stat = try file.stat();

        // Check if this is a new or modified file
        if (state.files.get(full_path)) |existing| {
            // File exists, check if modified
            if (stat.mtime != existing.mtime or stat.size != existing.size) {
                try state.log("Modified: {s}", .{entry.name}, config.verbose);

                // Update state
                allocator.free(existing.path);
                try state.files.put(full_path, .{
                    .path = try allocator.dupe(u8, full_path),
                    .size = stat.size,
                    .mtime = stat.mtime,
                });
            }
        } else {
            // New file detected
            try state.log("New file: {s}", .{entry.name}, config.verbose);

            // Add to new files list
            try new_files.append(allocator, try allocator.dupe(u8, full_path));

            // Add to state
            try state.files.put(try allocator.dupe(u8, full_path), .{
                .path = try allocator.dupe(u8, full_path),
                .size = stat.size,
                .mtime = stat.mtime,
            });
        }
    }

    return new_files;
}

/// Check for deleted files
fn checkDeletedFiles(
    allocator: std.mem.Allocator,
    state: *WatchState,
    config: *const WatchConfig,
) !void {
    var to_remove = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (to_remove.items) |path| {
            allocator.free(path);
        }
        to_remove.deinit(allocator);
    }

    var iter = state.files.iterator();
    while (iter.next()) |entry| {
        const path = entry.key_ptr.*;

        // Check if file still exists
        std.fs.cwd().access(path, .{}) catch {
            try state.log("Deleted: {s}", .{path}, config.verbose);
            try to_remove.append(allocator, try allocator.dupe(u8, path));
            continue;
        };
    }

    // Remove deleted files from state
    for (to_remove.items) |path| {
        if (state.files.fetchRemove(path)) |kv| {
            allocator.free(kv.key);
            allocator.free(kv.value.path);
        }
    }
}

/// Execute watch command
fn executeWatch(allocator: std.mem.Allocator, args: []const []const u8, org_config: *Config) !void {
    var watch_config = WatchConfig{};
    var dir_path: ?[]const u8 = null;

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            print("{s}", .{watch_help_text});
            return;
        } else if (std.mem.eql(u8, arg, "--rules")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --rules");
                return error.MissingArgument;
            }
            watch_config.rules_file_path = args[i];
        } else if (std.mem.eql(u8, arg, "--validate-rules")) {
            watch_config.validate_rules_only = true;
        } else if (std.mem.eql(u8, arg, "--interval")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --interval");
                return error.MissingArgument;
            }
            watch_config.interval_seconds = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--log")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --log");
                return error.MissingArgument;
            }
            watch_config.log_file_path = args[i];
        } else if (std.mem.eql(u8, arg, "--pid")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --pid");
                return error.MissingArgument;
            }
            watch_config.pid_file_path = args[i];
        } else if (std.mem.eql(u8, arg, "--daemon")) {
            watch_config.daemon = true;
            printWarning("Daemon mode not fully implemented yet");
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            watch_config.verbose = true;
            org_config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--by-date")) {
            org_config.organize_by_date = true;
        } else if (std.mem.eql(u8, arg, "--by-size")) {
            org_config.organize_by_size = true;
        } else if (std.mem.eql(u8, arg, "--size-threshold")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --size-threshold");
                return error.MissingArgument;
            }
            org_config.size_threshold_mb = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--date-format")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --date-format");
                return error.MissingArgument;
            }
            org_config.date_format = utils.parseDateFormat(args[i]) orelse {
                printError("Invalid date format. Use: year, year-month, or year-month-day");
                return error.InvalidArgument;
            };
        } else if (arg[0] != '-') {
            if (dir_path != null) {
                printError("Multiple directory paths specified");
                return error.TooManyArguments;
            }
            dir_path = arg;
        } else {
            const err_msg = try std.fmt.allocPrint(allocator, "Unknown option: {s}", .{arg});
            defer allocator.free(err_msg);
            printError(err_msg);
            return error.UnknownOption;
        }
    }

    // Validate directory path
    if (dir_path == null) {
        printError("Missing required directory argument");
        print("\n{s}", .{watch_help_text});
        return error.MissingDirectory;
    }

    try validateDirectory(dir_path.?);

    // Load rules if provided
    var rule_engine: ?watch_rules.RuleEngine = null;
    defer if (rule_engine) |*engine| engine.deinit();

    if (watch_config.rules_file_path) |rules_path| {
        rule_engine = watch_rules.loadRulesFromFile(allocator, rules_path) catch |err| {
            const err_msg = try std.fmt.allocPrint(allocator, "Failed to load rules file: {s}", .{@errorName(err)});
            defer allocator.free(err_msg);
            printError(err_msg);
            return err;
        };

        printInfo("Rules loaded successfully");
        print("Loaded {d} rules from: {s}\n", .{ rule_engine.?.rules.items.len, rules_path });

        // Validate rules
        const validation_result = try rule_engine.?.validateRules();
        defer allocator.free(validation_result);

        if (validation_result.len > 0) {
            printWarning("Rule validation issues:");
            print("{s}\n", .{validation_result});

            if (watch_config.validate_rules_only) {
                return error.RuleValidationFailed;
            }
        } else {
            printSuccess("All rules validated successfully");
        }

        // If only validating, exit now
        if (watch_config.validate_rules_only) {
            printSuccess("Rule validation completed");
            return;
        }

        // Display loaded rules
        if (watch_config.verbose) {
            print("\nLoaded rules:\n", .{});
            for (rule_engine.?.rules.items) |*rule| {
                print("  - {s} (priority: {d}, trigger: {s})\n", .{
                    rule.name,
                    rule.priority,
                    rule.trigger.toString(),
                });
            }
            print("\n", .{});
        }
    }

    // Set default paths if not provided
    const home = std.posix.getenv("HOME") orelse ".";
    const default_log_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.local/share/zigstack/watch.log",
        .{home},
    );
    defer allocator.free(default_log_path);

    const default_pid_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.local/share/zigstack/watch.pid",
        .{home},
    );
    defer allocator.free(default_pid_path);

    const log_path = watch_config.log_file_path orelse default_log_path;
    const pid_path = watch_config.pid_file_path orelse default_pid_path;

    // Initialize watch state
    var state = WatchState.init(allocator);
    defer state.deinit();

    // Open log file
    try state.openLogFile(log_path);

    // Write PID file
    try writePidFile(pid_path);
    defer removePidFile(pid_path);

    // Setup signal handlers for graceful shutdown
    const sigact = posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = std.mem.zeroes(posix.sigset_t),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sigact, null);
    posix.sigaction(posix.SIG.TERM, &sigact, null);

    // Initial scan
    printInfo("Starting watch on directory");
    print("Watching: {s}\n", .{dir_path.?});
    print("Log file: {s}\n", .{log_path});
    print("PID file: {s}\n", .{pid_path});
    print("Check interval: {d} seconds\n", .{watch_config.interval_seconds});
    print("Press Ctrl+C to stop\n\n", .{});

    try state.log("Watch started on: {s}", .{dir_path.?}, watch_config.verbose);

    var files_processed: u64 = 0;
    var errors: u64 = 0;

    // Initial scan to populate state
    _ = try scanDirectory(allocator, dir_path.?, &state, &watch_config);

    // Main watch loop
    while (!should_exit.load(.acquire)) {
        // Sleep for interval
        std.Thread.sleep(watch_config.interval_seconds * std.time.ns_per_s);

        // Scan for new files
        var new_files = try scanDirectory(allocator, dir_path.?, &state, &watch_config);
        defer {
            for (new_files.items) |path| {
                allocator.free(path);
            }
            new_files.deinit(allocator);
        }

        // Check for deleted files
        try checkDeletedFiles(allocator, &state, &watch_config);

        // Process new files with organization
        if (new_files.items.len > 0) {
            try state.log("Processing {d} new files", .{new_files.items.len}, watch_config.verbose);

            // If using rules, process through rule engine
            if (rule_engine) |*engine| {
                var action_context = watch_rules.ActionContext.init(allocator);
                defer action_context.deinit();

                for (new_files.items) |file_path| {
                    // Get file info
                    const file_state = state.files.get(file_path) orelse continue;

                    // Process through rule engine
                    const matched = try engine.processFile(
                        file_path,
                        file_state.size,
                        file_state.mtime,
                        .file_created,
                        &action_context,
                    );

                    if (matched > 0) {
                        try state.log("File {s} matched {d} rules", .{ file_path, matched }, watch_config.verbose);
                    }
                }

                // Execute queued actions
                if (action_context.organize_queue.items.len > 0) {
                    try state.log("Organizing {d} files from rules", .{action_context.organize_queue.items.len}, watch_config.verbose);
                    // TODO: Execute organize actions
                }

                files_processed += new_files.items.len;
            } else {
                // Default organization without rules
                org_config.create_directories = true;
                org_config.move_files = true;

                const organize_args = &[_][]const u8{dir_path.?};
                organize_cmd.executeOrganizeCommand(allocator, organize_args, org_config) catch |err| {
                    errors += 1;
                    const err_msg = try std.fmt.allocPrint(
                        allocator,
                        "Error organizing files: {s}",
                        .{@errorName(err)},
                    );
                    defer allocator.free(err_msg);
                    try state.log("{s}", .{err_msg}, watch_config.verbose);
                    continue;
                };

                files_processed += new_files.items.len;
                try state.log("Organized {d} files successfully", .{new_files.items.len}, watch_config.verbose);
            }
        }
    }

    // Shutdown
    printInfo("Shutting down gracefully");
    try state.log("Watch stopped. Processed {d} files, {d} errors", .{ files_processed, errors }, true);
    print("\nTotal files processed: {d}\n", .{files_processed});
    print("Total errors: {d}\n", .{errors});
}

/// Get watch command
pub fn getCommand() Command {
    return .{
        .name = "watch",
        .description = "Monitor directory for changes and auto-organize files",
        .execute_fn = executeWatch,
        .help_fn = printHelp,
    };
}

fn printHelp() void {
    print("{s}", .{watch_help_text});
}

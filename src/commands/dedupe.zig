const std = @import("std");
const print = std.debug.print;

// Core module imports
const config_mod = @import("../core/config.zig");
const utils = @import("../core/utils.zig");
const command_mod = @import("command.zig");

// Type exports
pub const Config = config_mod.Config;
pub const Command = command_mod.Command;

// Utility function shortcuts
const printError = utils.printError;
const printSuccess = utils.printSuccess;
const printInfo = utils.printInfo;
const printWarning = utils.printWarning;
const validateDirectory = utils.validateDirectory;
const calculateFileHash = utils.calculateFileHash;
const getFileStats = utils.getFileStats;

const dedupe_help_text =
    \\Usage: zigstack dedupe [OPTIONS] <directory>
    \\
    \\Find and manage duplicate files with interactive or automatic resolution.
    \\
    \\Arguments:
    \\  <directory>       Directory path to scan for duplicates
    \\
    \\Options:
    \\  -h, --help        Display this help message
    \\  --auto <STRATEGY> Automatic duplicate resolution:
    \\                      keep-oldest:  Keep the oldest file (by modification time)
    \\                      keep-newest:  Keep the newest file (by modification time)
    \\                      keep-largest: Keep the largest file (by size)
    \\  --interactive     Interactive mode with prompts (default)
    \\  --summary         Show summary only, no actions
    \\  --dry-run         Preview actions without making changes (default)
    \\  --delete          Actually delete duplicate files (use with caution!)
    \\  --hardlink        Replace duplicates with hardlinks (saves space, keeps files)
    \\  --recursive       Scan subdirectories recursively (default: true)
    \\  --min-size N      Minimum file size in bytes to consider (default: 0)
    \\  -V, --verbose     Enable verbose logging
    \\
    \\Hardlink Notes:
    \\  - Hardlinks only work on the same filesystem
    \\  - All hardlinked files point to the same data
    \\  - Editing one hardlink affects all copies
    \\  - Cannot hardlink across different filesystems/partitions
    \\
    \\Examples:
    \\  zigstack dedupe /path/to/directory
    \\  zigstack dedupe --auto keep-newest --delete /path
    \\  zigstack dedupe --auto keep-oldest --hardlink /path
    \\  zigstack dedupe --summary /downloads
    \\  zigstack dedupe --min-size 1048576 /media
    \\
;

// ============================================================================
// Data Structures
// ============================================================================

/// Strategy for automatic duplicate resolution
pub const DedupeStrategy = enum {
    keep_oldest,
    keep_newest,
    keep_largest,

    pub fn fromString(s: []const u8) !DedupeStrategy {
        if (std.mem.eql(u8, s, "keep-oldest")) return .keep_oldest;
        if (std.mem.eql(u8, s, "keep-newest")) return .keep_newest;
        if (std.mem.eql(u8, s, "keep-largest")) return .keep_largest;
        return error.InvalidStrategy;
    }

    pub fn toString(self: DedupeStrategy) []const u8 {
        return switch (self) {
            .keep_oldest => "keep-oldest",
            .keep_newest => "keep-newest",
            .keep_largest => "keep-largest",
        };
    }
};

/// Information about a single file instance
pub const FileInstance = struct {
    path: []const u8,
    size: u64,
    modified_time: i64,

    pub fn deinit(self: *FileInstance, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// Group of duplicate files with the same hash
pub const DuplicateGroup = struct {
    allocator: std.mem.Allocator,
    hash: [32]u8,
    files: std.ArrayList(FileInstance),
    total_size: u64,

    pub fn init(allocator: std.mem.Allocator, hash: [32]u8) DuplicateGroup {
        return DuplicateGroup{
            .allocator = allocator,
            .hash = hash,
            .files = std.ArrayList(FileInstance){
                .items = &[_]FileInstance{},
                .capacity = 0,
            },
            .total_size = 0,
        };
    }

    pub fn addFile(self: *DuplicateGroup, path: []const u8, size: u64, modified_time: i64) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.files.append(self.allocator, FileInstance{
            .path = path_copy,
            .size = size,
            .modified_time = modified_time,
        });
        self.total_size = size;
    }

    pub fn getSpaceSavings(self: *DuplicateGroup) u64 {
        if (self.files.items.len <= 1) return 0;
        return self.total_size * (self.files.items.len - 1);
    }

    pub fn deinit(self: *DuplicateGroup) void {
        for (self.files.items) |*file| {
            file.deinit(self.allocator);
        }
        self.files.deinit(self.allocator);
    }
};

/// Overall deduplication results
pub const DedupeResult = struct {
    allocator: std.mem.Allocator,
    duplicate_groups: []DuplicateGroup,
    total_files_scanned: usize,
    total_duplicates: usize,
    total_space_savings: u64,

    pub fn deinit(self: *DedupeResult) void {
        for (self.duplicate_groups) |*group| {
            group.deinit();
        }
        self.allocator.free(self.duplicate_groups);
    }
};

// ============================================================================
// Duplicate Detection
// ============================================================================

const DedupeOptions = struct {
    strategy: ?DedupeStrategy = null,
    interactive: bool = true,
    summary_only: bool = false,
    dry_run: bool = true,
    use_hardlinks: bool = false,
    recursive: bool = true,
    min_size: u64 = 0,
    verbose: bool = false,
};

/// Scan directory for duplicate files
fn scanForDuplicates(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    options: DedupeOptions,
) !DedupeResult {
    var total_files_scanned: usize = 0;
    var total_duplicates: usize = 0;
    var total_space_savings: u64 = 0;

    // HashMap to group files by hash
    var hash_map = std.AutoHashMap([32]u8, std.ArrayList(FileInstance)).init(allocator);
    defer {
        var iter = hash_map.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |*file| {
                file.deinit(allocator);
            }
            entry.value_ptr.deinit(allocator);
        }
        hash_map.deinit();
    }

    // Scan directory
    try scanDirectory(
        allocator,
        dir_path,
        &hash_map,
        &total_files_scanned,
        options,
        0,
    );

    // Convert hash map to duplicate groups
    var groups_list = std.ArrayList(DuplicateGroup){
        .items = &[_]DuplicateGroup{},
        .capacity = 0,
    };
    defer groups_list.deinit(allocator);

    var iter = hash_map.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.items.len > 1) {
            var group = DuplicateGroup.init(allocator, entry.key_ptr.*);
            for (entry.value_ptr.items) |file| {
                const path_copy = try allocator.dupe(u8, file.path);
                try group.files.append(allocator, FileInstance{
                    .path = path_copy,
                    .size = file.size,
                    .modified_time = file.modified_time,
                });
                group.total_size = file.size;
            }

            total_duplicates += entry.value_ptr.items.len - 1;
            total_space_savings += group.getSpaceSavings();
            try groups_list.append(allocator, group);
        }
    }

    const groups_slice = try groups_list.toOwnedSlice(allocator);

    return DedupeResult{
        .allocator = allocator,
        .duplicate_groups = groups_slice,
        .total_files_scanned = total_files_scanned,
        .total_duplicates = total_duplicates,
        .total_space_savings = total_space_savings,
    };
}

fn scanDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    hash_map: *std.AutoHashMap([32]u8, std.ArrayList(FileInstance)),
    total_files: *usize,
    options: DedupeOptions,
    depth: u32,
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (options.verbose) {
            printWarning("Cannot access directory:");
            print(" {s}\n", .{dir_path});
        }
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory and options.recursive) {
            const subdir_path = try std.mem.join(allocator, "/", &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(subdir_path);

            try scanDirectory(allocator, subdir_path, hash_map, total_files, options, depth + 1);
        } else if (entry.kind == .file) {
            const file_path = try std.mem.join(allocator, "/", &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(file_path);

            // Get file stats
            const stats = getFileStats(file_path);

            // Apply size filter
            if (stats.size < options.min_size) continue;

            total_files.* += 1;

            // Calculate hash
            const hash = calculateFileHash(file_path) catch |err| {
                if (options.verbose) {
                    printWarning("Failed to hash file:");
                    print(" {s} ({any})\n", .{ file_path, err });
                }
                continue;
            };

            // Add to hash map
            const gop = try hash_map.getOrPut(hash);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(FileInstance){
                    .items = &[_]FileInstance{},
                    .capacity = 0,
                };
            }

            const path_copy = try allocator.dupe(u8, file_path);
            try gop.value_ptr.append(allocator, FileInstance{
                .path = path_copy,
                .size = stats.size,
                .modified_time = stats.modified_time,
            });
        }
    }
}

// ============================================================================
// Resolution Strategies
// ============================================================================

/// Determine which file to keep based on strategy
fn selectFileToKeep(group: *DuplicateGroup, strategy: DedupeStrategy) usize {
    if (group.files.items.len == 0) return 0;

    var keep_index: usize = 0;

    switch (strategy) {
        .keep_oldest => {
            var oldest_time = group.files.items[0].modified_time;
            for (group.files.items, 0..) |file, i| {
                if (file.modified_time < oldest_time) {
                    oldest_time = file.modified_time;
                    keep_index = i;
                }
            }
        },
        .keep_newest => {
            var newest_time = group.files.items[0].modified_time;
            for (group.files.items, 0..) |file, i| {
                if (file.modified_time > newest_time) {
                    newest_time = file.modified_time;
                    keep_index = i;
                }
            }
        },
        .keep_largest => {
            var largest_size = group.files.items[0].size;
            for (group.files.items, 0..) |file, i| {
                if (file.size > largest_size) {
                    largest_size = file.size;
                    keep_index = i;
                }
            }
        },
    }

    return keep_index;
}

// ============================================================================
// Hardlink Operations
// ============================================================================

/// Create a hardlink from source to target
/// Note: Will fail naturally if files are on different filesystems
fn createHardlink(source: []const u8, target: []const u8) !void {
    // Create temporary path for backup
    var backup_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const backup_path = try std.fmt.bufPrint(&backup_path_buf, "{s}.zigstack_backup", .{target});

    // Rename target to backup (in case we need to rollback)
    try std.fs.cwd().rename(target, backup_path);
    errdefer std.fs.cwd().rename(backup_path, target) catch {};

    // Create hardlink - this will fail if files are on different filesystems
    std.posix.link(source, target) catch |err| {
        // Rollback rename
        std.fs.cwd().rename(backup_path, target) catch {};
        return err;
    };

    // Delete backup
    try std.fs.cwd().deleteFile(backup_path);
}

/// Replace duplicate files with hardlinks
fn applyHardlinks(
    _: std.mem.Allocator,
    result: *DedupeResult,
    options: DedupeOptions,
) !usize {
    if (result.duplicate_groups.len == 0) return 0;
    if (options.strategy == null) {
        printWarning("No strategy specified for hardlink creation");
        return 0;
    }

    var hardlinks_created: usize = 0;
    var errors_encountered: usize = 0;

    for (result.duplicate_groups) |*group| {
        if (group.files.items.len <= 1) continue;

        const keep_idx = selectFileToKeep(group, options.strategy.?);
        const source_path = group.files.items[keep_idx].path;

        if (options.verbose) {
            printInfo("Creating hardlinks for group, keeping:");
            print(" {s}\n", .{source_path});
        }

        for (group.files.items, 0..) |file, idx| {
            if (idx == keep_idx) continue;

            if (options.verbose) {
                printInfo("  Hardlinking:");
                print(" {s} -> {s}\n", .{ file.path, source_path });
            }

            createHardlink(source_path, file.path) catch |err| {
                errors_encountered += 1;
                if (options.verbose) {
                    printWarning("Failed to create hardlink:");
                    print(" {s} ({any})\n", .{ file.path, err });
                }
                continue;
            };

            hardlinks_created += 1;
        }
    }

    if (errors_encountered > 0) {
        printWarning("Encountered errors while creating hardlinks:");
        print(" {d} failed\n", .{errors_encountered});
    }

    return hardlinks_created;
}

// ============================================================================
// Display Functions
// ============================================================================

fn formatSize(size: u64) ![]const u8 {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;

    var buf: [64]u8 = undefined;
    const formatted = if (size >= GB)
        try std.fmt.bufPrint(&buf, "{d:.2} GB", .{@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(GB))})
    else if (size >= MB)
        try std.fmt.bufPrint(&buf, "{d:.2} MB", .{@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(MB))})
    else if (size >= KB)
        try std.fmt.bufPrint(&buf, "{d:.2} KB", .{@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(KB))})
    else
        try std.fmt.bufPrint(&buf, "{d} B", .{size});

    const allocator = std.heap.page_allocator;
    return try allocator.dupe(u8, formatted);
}

fn formatTime(timestamp: i64) ![]const u8 {
    var buf: [64]u8 = undefined;
    // Simple timestamp formatting (would use proper date formatting in production)
    const formatted = try std.fmt.bufPrint(&buf, "{d}", .{timestamp});

    const allocator = std.heap.page_allocator;
    return try allocator.dupe(u8, formatted);
}

fn printDuplicateGroups(result: *DedupeResult, options: DedupeOptions) !void {
    print("\n", .{});
    print("============================================================\n", .{});
    print("DUPLICATE FILE SCAN RESULTS\n", .{});
    print("============================================================\n\n", .{});

    print("Files scanned: {d}\n", .{result.total_files_scanned});
    print("Duplicate files found: {d}\n", .{result.total_duplicates});

    const savings_str = try formatSize(result.total_space_savings);
    defer std.heap.page_allocator.free(savings_str);
    print("Potential space savings: {s}\n\n", .{savings_str});

    if (result.duplicate_groups.len == 0) {
        printSuccess("No duplicate files found!");
        print("\n", .{});
        return;
    }

    print("Duplicate Groups ({d} groups):\n", .{result.duplicate_groups.len});
    print("============================================================\n\n", .{});

    for (result.duplicate_groups, 0..) |*group, group_idx| {
        const size_str = try formatSize(group.total_size);
        defer std.heap.page_allocator.free(size_str);

        const savings_str2 = try formatSize(group.getSpaceSavings());
        defer std.heap.page_allocator.free(savings_str2);

        print("Group {d}: {d} copies, {s} each (save {s})\n", .{
            group_idx + 1,
            group.files.items.len,
            size_str,
            savings_str2,
        });

        for (group.files.items, 0..) |file, idx| {
            const time_str = try formatTime(file.modified_time);
            defer std.heap.page_allocator.free(time_str);

            print("  [{d}] {s} (modified: {s})\n", .{ idx + 1, file.path, time_str });
        }

        // Show which file would be kept with strategy
        if (options.strategy) |strategy| {
            const keep_idx = selectFileToKeep(group, strategy);
            print("  → Strategy '{s}' would keep: {s}\n", .{
                strategy.toString(),
                group.files.items[keep_idx].path,
            });
        }

        print("\n", .{});
    }

    print("============================================================\n", .{});
}

// ============================================================================
// Command Interface Implementation
// ============================================================================

fn dedupeHelp() void {
    print("{s}", .{dedupe_help_text});
}

fn dedupeExecute(allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void {
    if (args.len == 0) {
        printError("Missing required directory argument");
        print("\n", .{});
        dedupeHelp();
        return error.MissingArgument;
    }

    var dir_path: []const u8 = undefined;
    var options = DedupeOptions{};
    options.verbose = config.verbose;

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            dedupeHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--auto")) {
            i += 1;
            if (i >= args.len) {
                printError("--auto requires a strategy (keep-oldest, keep-newest, keep-largest)");
                return error.InvalidArgument;
            }
            options.strategy = try DedupeStrategy.fromString(args[i]);
            options.interactive = false;
        } else if (std.mem.eql(u8, arg, "--interactive")) {
            options.interactive = true;
            options.strategy = null;
        } else if (std.mem.eql(u8, arg, "--summary")) {
            options.summary_only = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--delete")) {
            options.dry_run = false;
        } else if (std.mem.eql(u8, arg, "--hardlink")) {
            options.use_hardlinks = true;
            options.dry_run = false;
        } else if (std.mem.eql(u8, arg, "--recursive")) {
            options.recursive = true;
        } else if (std.mem.eql(u8, arg, "--min-size")) {
            i += 1;
            if (i >= args.len) {
                printError("--min-size requires a value");
                return error.InvalidArgument;
            }
            options.min_size = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (arg[0] != '-') {
            dir_path = arg;
        }
    }

    // Validate directory
    try validateDirectory(dir_path);

    if (!options.summary_only) {
        printInfo("Scanning for duplicate files...");
        print("\n", .{});
    }

    // Scan for duplicates
    var result = try scanForDuplicates(allocator, dir_path, options);
    defer result.deinit();

    // Display results
    try printDuplicateGroups(&result, options);

    // Apply hardlinks if requested
    if (options.use_hardlinks and result.duplicate_groups.len > 0) {
        if (options.strategy == null) {
            printError("--hardlink requires a strategy (--auto keep-oldest/keep-newest/keep-largest)");
            return error.MissingStrategy;
        }

        print("\n", .{});
        printInfo("Creating hardlinks...");
        print("\n", .{});

        const hardlinks_created = try applyHardlinks(allocator, &result, options);

        print("\n", .{});
        printSuccess("Hardlinks created:");
        print(" {d}\n", .{hardlinks_created});

        const space_saved = try formatSize(result.total_space_savings);
        defer std.heap.page_allocator.free(space_saved);
        printSuccess("Space saved:");
        print(" {s}\n", .{space_saved});
        print("\n", .{});
    } else if (!options.dry_run and !options.use_hardlinks and result.duplicate_groups.len > 0) {
        printWarning("File deletion is not yet implemented in this version.");
        print("\n", .{});
    } else if (options.dry_run and result.duplicate_groups.len > 0) {
        printInfo("This is a preview. Use --delete to remove or --hardlink to replace with hardlinks.");
        print("\n", .{});
    }
}

pub fn getCommand() Command {
    return Command{
        .name = "dedupe",
        .description = "Find and manage duplicate files",
        .execute_fn = dedupeExecute,
        .help_fn = dedupeHelp,
    };
}

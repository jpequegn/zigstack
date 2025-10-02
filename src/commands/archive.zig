const std = @import("std");
const print = std.debug.print;

// Core module imports
const config_mod = @import("../core/config.zig");
const file_info_mod = @import("../core/file_info.zig");
const utils = @import("../core/utils.zig");
const command_mod = @import("command.zig");

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
const getFileExtension = utils.getFileExtension;
const getFileStats = utils.getFileStats;

const archive_help_text =
    \\Usage: zigstack archive [OPTIONS] <directory>
    \\
    \\Archive old files based on modification time.
    \\
    \\Arguments:
    \\  <directory>       Directory path to archive from
    \\
    \\Options:
    \\  -h, --help               Display this help message
    \\  --older-than <DURATION>  Age threshold (1d, 7d, 1mo, 6mo, 1y)
    \\  --dest <PATH>            Archive destination directory (required)
    \\  --preserve-structure     Keep original directory structure
    \\  --flatten                Flatten all files into destination (default)
    \\  --move                   Move instead of copy (remove from source)
    \\  --categories <LIST>      Only archive specific categories (comma-separated)
    \\  --min-size <SIZE>        Only archive files above size (in MB)
    \\  -d, --dry-run            Show what would happen without doing it
    \\  -V, --verbose            Enable verbose logging
    \\
    \\Examples:
    \\  zigstack archive --older-than 6mo --dest ~/Archive /path
    \\  zigstack archive --older-than 1y --move --dest ~/Archive /path
    \\  zigstack archive --older-than 30d --preserve-structure --dest ~/Archive /path
    \\
;

/// Duration represents a time duration for filtering files
pub const Duration = struct {
    seconds: i64,

    /// Parse duration string (e.g., "1d", "7d", "1mo", "6mo", "1y")
    pub fn parse(duration_str: []const u8) !Duration {
        if (duration_str.len < 2) {
            return error.InvalidDuration;
        }

        // Extract numeric part and unit
        var num_end: usize = 0;
        while (num_end < duration_str.len and duration_str[num_end] >= '0' and duration_str[num_end] <= '9') {
            num_end += 1;
        }

        if (num_end == 0) {
            return error.InvalidDuration;
        }

        const num_str = duration_str[0..num_end];
        const unit = duration_str[num_end..];

        const value = std.fmt.parseInt(i64, num_str, 10) catch {
            return error.InvalidDuration;
        };

        // Convert to seconds based on unit
        const seconds = if (std.mem.eql(u8, unit, "d"))
            value * 24 * 60 * 60
        else if (std.mem.eql(u8, unit, "mo"))
            value * 30 * 24 * 60 * 60 // Approximate month as 30 days
        else if (std.mem.eql(u8, unit, "y"))
            value * 365 * 24 * 60 * 60 // Approximate year as 365 days
        else
            return error.InvalidDuration;

        return Duration{ .seconds = seconds };
    }

    /// Get threshold timestamp (current time - duration)
    pub fn getThresholdTimestamp(self: Duration) i64 {
        const now = std.time.timestamp();
        return now - self.seconds;
    }
};

/// Archive configuration
pub const ArchiveConfig = struct {
    directory: []const u8,
    dest_path: []const u8,
    older_than: ?Duration,
    preserve_structure: bool,
    move_files: bool,
    categories: ?[]const []const u8,
    min_size_mb: ?u64,
    dry_run: bool,
    verbose: bool,

    pub fn init() ArchiveConfig {
        return ArchiveConfig{
            .directory = "",
            .dest_path = "",
            .older_than = null,
            .preserve_structure = false,
            .move_files = false,
            .categories = null,
            .min_size_mb = null,
            .dry_run = false,
            .verbose = false,
        };
    }
};

/// Archive statistics
pub const ArchiveStats = struct {
    total_files: usize,
    archived_files: usize,
    total_size: u64,
    archived_size: u64,
    categories: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator) ArchiveStats {
        return ArchiveStats{
            .total_files = 0,
            .archived_files = 0,
            .total_size = 0,
            .archived_size = 0,
            .categories = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *ArchiveStats) void {
        var it = self.categories.iterator();
        while (it.next()) |entry| {
            self.categories.allocator.free(entry.key_ptr.*);
        }
        self.categories.deinit();
    }
};

/// Check if file matches archive criteria
fn shouldArchiveFile(file: FileInfo, archive_config: *const ArchiveConfig, threshold_timestamp: i64) bool {
    // Check age
    if (archive_config.older_than != null) {
        if (file.modified_time > threshold_timestamp) {
            return false;
        }
    }

    // Check size
    if (archive_config.min_size_mb) |min_size| {
        const size_mb = file.size / (1024 * 1024);
        if (size_mb < min_size) {
            return false;
        }
    }

    // Check category filter
    if (archive_config.categories) |categories| {
        const category_name = @tagName(file.category);
        var matches = false;
        for (categories) |cat| {
            if (std.mem.eql(u8, cat, category_name)) {
                matches = true;
                break;
            }
        }
        if (!matches) {
            return false;
        }
    }

    return true;
}

/// Discover files in directory
fn discoverFiles(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    _: *const ArchiveConfig,
    files: *std.ArrayList(FileInfo),
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            printError("Directory not found");
            return err;
        },
        error.AccessDenied => {
            printError("Permission denied");
            return err;
        },
        else => return err,
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const name = try allocator.dupe(u8, entry.name);
            const ext_str = getFileExtension(entry.name);
            const extension = try allocator.dupe(u8, ext_str);

            // Create full path for file stats
            const full_file_path = try std.mem.join(allocator, "/", &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(full_file_path);

            const stats = getFileStats(full_file_path);

            // Categorize file
            const file_info = FileInfo{
                .name = name,
                .extension = extension,
                .category = categorizeFileByExtension(extension),
                .size = stats.size,
                .created_time = stats.created_time,
                .modified_time = stats.modified_time,
                .hash = stats.hash,
            };

            try files.append(allocator, file_info);
        }
    }
}

/// Simple categorization based on extension
fn categorizeFileByExtension(extension: []const u8) FileCategory {
    if (extension.len == 0) {
        return .Other;
    }

    // Convert extension to lowercase
    var ext_lower: [256]u8 = undefined;
    const ext_len = @min(extension.len, ext_lower.len);
    for (extension[0..ext_len], 0..) |c, i| {
        ext_lower[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    const ext_lower_slice = ext_lower[0..ext_len];

    // Documents
    if (std.mem.eql(u8, ext_lower_slice, ".txt") or
        std.mem.eql(u8, ext_lower_slice, ".doc") or
        std.mem.eql(u8, ext_lower_slice, ".docx") or
        std.mem.eql(u8, ext_lower_slice, ".pdf") or
        std.mem.eql(u8, ext_lower_slice, ".md"))
    {
        return .Documents;
    }

    // Images
    if (std.mem.eql(u8, ext_lower_slice, ".jpg") or
        std.mem.eql(u8, ext_lower_slice, ".jpeg") or
        std.mem.eql(u8, ext_lower_slice, ".png") or
        std.mem.eql(u8, ext_lower_slice, ".gif") or
        std.mem.eql(u8, ext_lower_slice, ".webp"))
    {
        return .Images;
    }

    // Videos
    if (std.mem.eql(u8, ext_lower_slice, ".mp4") or
        std.mem.eql(u8, ext_lower_slice, ".avi") or
        std.mem.eql(u8, ext_lower_slice, ".mkv") or
        std.mem.eql(u8, ext_lower_slice, ".mov"))
    {
        return .Videos;
    }

    // Audio
    if (std.mem.eql(u8, ext_lower_slice, ".mp3") or
        std.mem.eql(u8, ext_lower_slice, ".wav") or
        std.mem.eql(u8, ext_lower_slice, ".flac"))
    {
        return .Audio;
    }

    // Archives
    if (std.mem.eql(u8, ext_lower_slice, ".zip") or
        std.mem.eql(u8, ext_lower_slice, ".tar") or
        std.mem.eql(u8, ext_lower_slice, ".gz") or
        std.mem.eql(u8, ext_lower_slice, ".rar"))
    {
        return .Archives;
    }

    // Code
    if (std.mem.eql(u8, ext_lower_slice, ".c") or
        std.mem.eql(u8, ext_lower_slice, ".cpp") or
        std.mem.eql(u8, ext_lower_slice, ".py") or
        std.mem.eql(u8, ext_lower_slice, ".js") or
        std.mem.eql(u8, ext_lower_slice, ".zig"))
    {
        return .Code;
    }

    // Data
    if (std.mem.eql(u8, ext_lower_slice, ".json") or
        std.mem.eql(u8, ext_lower_slice, ".xml") or
        std.mem.eql(u8, ext_lower_slice, ".csv"))
    {
        return .Data;
    }

    // Configuration
    if (std.mem.eql(u8, ext_lower_slice, ".ini") or
        std.mem.eql(u8, ext_lower_slice, ".cfg") or
        std.mem.eql(u8, ext_lower_slice, ".yaml") or
        std.mem.eql(u8, ext_lower_slice, ".yml"))
    {
        return .Configuration;
    }

    return .Other;
}

/// Archive files based on configuration
fn archiveFiles(
    allocator: std.mem.Allocator,
    config: *const ArchiveConfig,
    stats: *ArchiveStats,
) !void {
    // Validate destination directory doesn't exist or is empty
    std.fs.cwd().makePath(config.dest_path) catch |err| switch (err) {
        error.PathAlreadyExists => {
            // Directory exists, continue
        },
        else => {
            printError("Failed to create destination directory");
            return err;
        },
    };

    // Discover files
    var files = std.ArrayList(FileInfo).initCapacity(allocator, 100) catch unreachable;
    defer {
        for (files.items) |file| {
            allocator.free(file.name);
            allocator.free(file.extension);
        }
        files.deinit(allocator);
    }

    try discoverFiles(allocator, config.directory, config, &files);

    // Calculate threshold if age filter is enabled
    const threshold_timestamp = if (config.older_than) |duration|
        duration.getThresholdTimestamp()
    else
        std.time.timestamp(); // Use current time if no age filter

    // Filter and archive files
    stats.total_files = files.items.len;

    for (files.items) |file| {
        stats.total_size += file.size;

        if (shouldArchiveFile(file, config, threshold_timestamp)) {
            stats.archived_files += 1;
            stats.archived_size += file.size;

            // Update category statistics
            const category_name = @tagName(file.category);
            if (stats.categories.get(category_name)) |count| {
                try stats.categories.put(category_name, count + 1);
            } else {
                const category_copy = try allocator.dupe(u8, category_name);
                try stats.categories.put(category_copy, 1);
            }

            if (config.dry_run) {
                if (config.verbose) {
                    const size_mb = @as(f64, @floatFromInt(file.size)) / (1024.0 * 1024.0);
                    print("Would archive: {s} ({d:.2} MB, category: {s})\n", .{ file.name, size_mb, category_name });
                }
            } else {
                // Determine destination path
                const dest_file_path = if (config.preserve_structure)
                    try std.mem.join(allocator, "/", &[_][]const u8{ config.dest_path, file.name })
                else
                    try std.mem.join(allocator, "/", &[_][]const u8{ config.dest_path, file.name });
                defer allocator.free(dest_file_path);

                const source_path = try std.mem.join(allocator, "/", &[_][]const u8{ config.directory, file.name });
                defer allocator.free(source_path);

                if (config.move_files) {
                    // Move file
                    std.fs.cwd().rename(source_path, dest_file_path) catch |err| {
                        printError("Failed to move file");
                        print("  Source: {s}\n", .{source_path});
                        print("  Dest: {s}\n", .{dest_file_path});
                        print("  Error: {}\n", .{err});
                        return err;
                    };

                    if (config.verbose) {
                        print("Moved: {s} → {s}\n", .{ source_path, dest_file_path });
                    }
                } else {
                    // Copy file
                    std.fs.cwd().copyFile(source_path, std.fs.cwd(), dest_file_path, .{}) catch |err| {
                        printError("Failed to copy file");
                        print("  Source: {s}\n", .{source_path});
                        print("  Dest: {s}\n", .{dest_file_path});
                        print("  Error: {}\n", .{err});
                        return err;
                    };

                    if (config.verbose) {
                        print("Copied: {s} → {s}\n", .{ source_path, dest_file_path });
                    }
                }
            }
        }
    }
}

/// Display archive statistics
fn displayStats(stats: *const ArchiveStats, config: *const ArchiveConfig) void {
    print("\n{s}\n", .{"============================================================"});
    if (config.dry_run) {
        print("ARCHIVE PREVIEW (DRY RUN)\n", .{});
    } else {
        print("ARCHIVE COMPLETE\n", .{});
    }
    print("{s}\n\n", .{"============================================================"});

    print("Total files found: {}\n", .{stats.total_files});
    print("Files to archive: {}\n", .{stats.archived_files});

    const total_size_mb = @as(f64, @floatFromInt(stats.total_size)) / (1024.0 * 1024.0);
    const archived_size_mb = @as(f64, @floatFromInt(stats.archived_size)) / (1024.0 * 1024.0);
    const archived_size_gb = archived_size_mb / 1024.0;

    print("Total size: {d:.2} MB\n", .{total_size_mb});
    if (archived_size_gb >= 1.0) {
        print("Archived size: {d:.2} GB\n", .{archived_size_gb});
    } else {
        print("Archived size: {d:.2} MB\n", .{archived_size_mb});
    }

    if (stats.archived_files > 0) {
        print("\nArchiving by category:\n", .{});
        print("{s}\n", .{"----------------------------------------"});

        var it = stats.categories.iterator();
        while (it.next()) |entry| {
            const category = entry.key_ptr.*;
            const count = entry.value_ptr.*;
            print("  {s}: {} files\n", .{ category, count });
        }
    }

    print("\n{s}\n", .{"============================================================"});
    if (config.dry_run) {
        print("Note: This is a preview. No files have been archived.\n", .{});
        print("Remove --dry-run to perform the archive operation.\n", .{});
    } else {
        print("Archive destination: {s}\n", .{config.dest_path});
        if (config.move_files) {
            print("Files have been moved (removed from source).\n", .{});
        } else {
            print("Files have been copied (source files remain).\n", .{});
        }
    }
    print("{s}\n", .{"============================================================"});
}

/// Execute the archive command
pub fn executeArchiveCommand(allocator: std.mem.Allocator, args: []const []const u8, _: *Config) !void {
    var archive_config = ArchiveConfig.init();
    defer {
        // Free categories array if allocated
        if (archive_config.categories) |categories| {
            allocator.free(categories);
        }
    }
    var i: usize = 0;
    var has_older_than = false;
    var has_dest = false;

    // Parse arguments
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--older-than")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value after --older-than");
                std.process.exit(1);
            }
            archive_config.older_than = Duration.parse(args[i]) catch {
                printError("Invalid duration format");
                print("Expected format: 1d, 7d, 1mo, 6mo, 1y, got: {s}\n", .{args[i]});
                std.process.exit(1);
            };
            has_older_than = true;
        } else if (std.mem.eql(u8, arg, "--dest")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing path after --dest");
                std.process.exit(1);
            }
            archive_config.dest_path = args[i];
            has_dest = true;
        } else if (std.mem.eql(u8, arg, "--preserve-structure")) {
            archive_config.preserve_structure = true;
        } else if (std.mem.eql(u8, arg, "--flatten")) {
            archive_config.preserve_structure = false;
        } else if (std.mem.eql(u8, arg, "--move")) {
            archive_config.move_files = true;
            archive_config.dry_run = false;
        } else if (std.mem.eql(u8, arg, "--categories")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value after --categories");
                std.process.exit(1);
            }
            // Parse comma-separated categories
            var category_list = std.ArrayList([]const u8).initCapacity(allocator, 5) catch unreachable;
            defer category_list.deinit(allocator);

            var it = std.mem.splitSequence(u8, args[i], ",");
            while (it.next()) |cat| {
                try category_list.append(allocator, cat);
            }

            archive_config.categories = try category_list.toOwnedSlice(allocator);
        } else if (std.mem.eql(u8, arg, "--min-size")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value after --min-size");
                std.process.exit(1);
            }
            archive_config.min_size_mb = std.fmt.parseInt(u64, args[i], 10) catch {
                printError("Invalid min-size value");
                print("Expected a number, got: {s}\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dry-run")) {
            archive_config.dry_run = true;
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            archive_config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            printError("Unknown option");
            print("Unknown option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            // Positional argument (directory path)
            if (archive_config.directory.len > 0) {
                printError("Multiple directory paths provided. Only one is allowed");
                std.process.exit(1);
            }
            archive_config.directory = arg;
        }

        i += 1;
    }

    // Validate required arguments
    if (archive_config.directory.len == 0) {
        printError("Missing required directory argument");
        std.process.exit(1);
    }

    if (!has_dest) {
        printError("Missing required --dest argument");
        print("Specify archive destination with --dest <path>\n", .{});
        std.process.exit(1);
    }

    if (!has_older_than) {
        printWarning("No --older-than specified, will archive all files");
    }

    // Validate source directory exists
    validateDirectory(archive_config.directory) catch {
        std.process.exit(1);
    };

    // Execute archive operation
    print("Analyzing directory: {s}\n", .{archive_config.directory});
    print("Archive destination: {s}\n", .{archive_config.dest_path});

    var stats = ArchiveStats.init(allocator);
    defer stats.deinit();

    try archiveFiles(allocator, &archive_config, &stats);

    // Display statistics
    displayStats(&stats, &archive_config);
}

// ============================================================================
// Command Interface Implementation
// ============================================================================

fn archiveExecute(allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void {
    // Check for help flag
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            archiveHelp();
            return;
        }
    }

    try executeArchiveCommand(allocator, args, config);
}

fn archiveHelp() void {
    print("{s}", .{archive_help_text});
}

pub fn getCommand() Command {
    return Command{
        .name = "archive",
        .description = "Archive old files based on modification time",
        .execute_fn = archiveExecute,
        .help_fn = archiveHelp,
    };
}

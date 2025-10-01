const std = @import("std");
const crypto = std.crypto;
const config_mod = @import("config.zig");

pub const Config = config_mod.Config;
pub const ConfigData = config_mod.ConfigData;
pub const DateFormat = config_mod.DateFormat;
pub const DuplicateAction = config_mod.DuplicateAction;

// ============================================================================
// Output Formatting Functions
// ============================================================================

/// Print error message to stderr
pub fn printError(message: []const u8) void {
    std.debug.print("Error: {s}\n", .{message});
}

/// Print success message (for future use)
pub fn printSuccess(message: []const u8) void {
    std.debug.print("✓ {s}\n", .{message});
}

/// Print info message (for future use)
pub fn printInfo(message: []const u8) void {
    std.debug.print("ℹ {s}\n", .{message});
}

/// Print warning message (for future use)
pub fn printWarning(message: []const u8) void {
    std.debug.print("⚠ {s}\n", .{message});
}

// ============================================================================
// Path Utilities
// ============================================================================

/// Validate that a directory exists and is accessible
pub fn validateDirectory(path: []const u8) !void {
    var file = std.fs.cwd().openDir(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            printError("Directory not found");
            return err;
        },
        error.NotDir => {
            printError("Path exists but is not a directory");
            return err;
        },
        error.AccessDenied => {
            printError("Access denied to directory");
            return err;
        },
        else => {
            printError("Unable to access directory");
            return err;
        },
    };
    file.close();
}

/// Resolve filename conflicts by appending a counter
/// Returns a new path with _1, _2, etc. appended until a non-existent path is found
pub fn resolveFilenameConflict(allocator: std.mem.Allocator, target_path: []const u8) ![]const u8 {
    // Check if the target path exists
    std.fs.cwd().access(target_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // File doesn't exist, use original path
            return try allocator.dupe(u8, target_path);
        },
        else => return err,
    };

    // File exists, need to find alternative name
    const dir_name = std.fs.path.dirname(target_path) orelse ".";
    const base_name = std.fs.path.basename(target_path);

    // Split filename and extension
    const extension = getFileExtension(base_name);
    const name_without_ext = if (extension.len > 0)
        base_name[0 .. base_name.len - extension.len]
    else
        base_name;

    // Try incrementing counter until we find available name
    var counter: u32 = 1;
    while (counter < 1000) : (counter += 1) {
        const new_name = if (extension.len > 0)
            try std.fmt.allocPrint(allocator, "{s}_{}{s}", .{ name_without_ext, counter, extension })
        else
            try std.fmt.allocPrint(allocator, "{s}_{}", .{ name_without_ext, counter });

        const new_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_name, new_name });

        std.fs.cwd().access(new_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Found available name
                allocator.free(new_name);
                return new_path;
            },
            else => {
                allocator.free(new_name);
                allocator.free(new_path);
                return err;
            },
        };

        allocator.free(new_name);
        allocator.free(new_path);
    }

    // If we reach here, couldn't find available name after 1000 tries
    return error.TooManyConflicts;
}

// ============================================================================
// File Utilities
// ============================================================================

/// File statistics structure
pub const FileStats = struct {
    size: u64,
    created_time: i64,
    modified_time: i64,
    hash: [32]u8,
};

/// Extract file extension from filename (includes the dot)
pub fn getFileExtension(filename: []const u8) []const u8 {
    // Handle edge cases
    if (filename.len == 0) {
        return "";
    }

    // Handle files that are only dots
    var all_dots = true;
    for (filename) |char| {
        if (char != '.') {
            all_dots = false;
            break;
        }
    }
    if (all_dots) {
        return "";
    }

    if (std.mem.lastIndexOf(u8, filename, ".")) |dot_index| {
        // Don't count hidden files starting with '.' as having an extension
        if (dot_index == 0) {
            return "";
        }

        // Handle edge case where filename ends with dots
        const extension = filename[dot_index..];
        if (extension.len >= 1) {
            return extension;
        }
        return "";
    }
    return "";
}

/// Get file statistics including size, timestamps, and hash
pub fn getFileStats(file_path: []const u8) FileStats {
    const stat = std.fs.cwd().statFile(file_path) catch {
        return .{
            .size = 0,
            .created_time = 0,
            .modified_time = 0,
            .hash = [_]u8{0} ** 32,
        };
    };

    const hash = calculateFileHash(file_path) catch [_]u8{0} ** 32;

    return .{
        .size = stat.size,
        .created_time = @as(i64, @intCast(@divFloor(stat.ctime, std.time.ns_per_s))),
        .modified_time = @as(i64, @intCast(@divFloor(stat.mtime, std.time.ns_per_s))),
        .hash = hash,
    };
}

/// Calculate SHA-256 hash of a file
pub fn calculateFileHash(file_path: []const u8) ![32]u8 {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => {
            return [_]u8{0} ** 32;
        },
        else => return err,
    };
    defer file.close();

    var hasher = crypto.hash.sha2.Sha256.init(.{});
    var buffer: [4096]u8 = undefined;

    while (true) {
        const bytes_read = try file.readAll(buffer[0..]);
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }

    return hasher.finalResult();
}

// ============================================================================
// Date/Time Utilities
// ============================================================================

/// Format a Unix timestamp into a directory path based on the specified format
pub fn formatDatePath(allocator: std.mem.Allocator, timestamp: i64, date_format: DateFormat) ![]const u8 {
    if (timestamp <= 0) {
        // Return a default path for invalid timestamps
        return try allocator.dupe(u8, "undated");
    }

    // Convert Unix timestamp to seconds since epoch
    const days_since_epoch = @as(u64, @intCast(@divFloor(timestamp, 86400)));

    // Calculate year (rough approximation)
    var year: u32 = 1970;
    var days_remaining = days_since_epoch;

    // Calculate year
    while (days_remaining >= 365) {
        const is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
        const days_in_year: u64 = if (is_leap) 366 else 365;
        if (days_remaining >= days_in_year) {
            days_remaining -= days_in_year;
            year += 1;
        } else {
            break;
        }
    }

    // Calculate month and day (simplified)
    var month: u32 = 1;
    const days_in_months = [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);

    for (days_in_months, 0..) |days_in_month, i| {
        var actual_days = days_in_month;
        if (i == 1 and is_leap) actual_days = 29; // February in leap year

        if (days_remaining >= actual_days) {
            days_remaining -= actual_days;
            month += 1;
        } else {
            break;
        }
    }

    const day = @as(u32, @intCast(days_remaining + 1));

    // Format path based on selected format
    return switch (date_format) {
        .year => try std.fmt.allocPrint(allocator, "{d}", .{year}),
        .year_month => try std.fmt.allocPrint(allocator, "{d}/{d:0>2}", .{ year, month }),
        .year_month_day => try std.fmt.allocPrint(allocator, "{d}/{d:0>2}/{d:0>2}", .{ year, month, day }),
    };
}

// ============================================================================
// Parsing Utilities
// ============================================================================

/// Parse date format string to DateFormat enum
pub fn parseDateFormat(format_str: []const u8) ?DateFormat {
    if (std.mem.eql(u8, format_str, "year")) {
        return .year;
    } else if (std.mem.eql(u8, format_str, "year-month")) {
        return .year_month;
    } else if (std.mem.eql(u8, format_str, "year-month-day")) {
        return .year_month_day;
    }
    return null;
}

/// Parse duplicate action string to DuplicateAction enum
pub fn parseDuplicateAction(action_str: []const u8) ?DuplicateAction {
    if (std.mem.eql(u8, action_str, "skip")) {
        return .skip;
    } else if (std.mem.eql(u8, action_str, "rename")) {
        return .rename;
    } else if (std.mem.eql(u8, action_str, "replace")) {
        return .replace;
    } else if (std.mem.eql(u8, action_str, "keep-both")) {
        return .keep_both;
    }
    return null;
}

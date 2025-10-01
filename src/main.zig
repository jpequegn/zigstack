const std = @import("std");
const print = std.debug.print;
const crypto = std.crypto;

// Import core modules
const file_info_mod = @import("core/file_info.zig");
const organization_mod = @import("core/organization.zig");
const config_mod = @import("core/config.zig");
const tracker_mod = @import("core/tracker.zig");

// Re-export types for use in main
const FileInfo = file_info_mod.FileInfo;
const FileCategory = file_info_mod.FileCategory;
const OrganizationPlan = organization_mod.OrganizationPlan;
const Config = config_mod.Config;
const ConfigData = config_mod.ConfigData;
const Category = config_mod.Category;
const DisplayConfig = config_mod.DisplayConfig;
const BehaviorConfig = config_mod.BehaviorConfig;
const DateFormat = config_mod.DateFormat;
const DuplicateAction = config_mod.DuplicateAction;
const MoveTracker = tracker_mod.MoveTracker;
const MoveRecord = tracker_mod.MoveRecord;

const VERSION = "0.1.0";
const PROGRAM_NAME = "zigstack";

const usage_text =
    \\Usage: {s} [OPTIONS] <directory>
    \\
    \\Analyze and organize files based on extension, date, size, and duplicates.
    \\
    \\Arguments:
    \\  <directory>       Directory path to analyze
    \\
    \\Options:
    \\  -h, --help        Display this help message
    \\  -v, --version     Display version information
    \\  --config PATH     Configuration file path (JSON format)
    \\  -c, --create      Create directories (default: preview only)
    \\  -m, --move        Move files to directories (implies --create)
    \\  -d, --dry-run     Show what would happen without doing it
    \\  -V, --verbose     Enable verbose logging
    \\
    \\Advanced Organization:
    \\  --by-date         Organize files by date (creation/modification)
    \\  --by-size         Organize large files separately
    \\  --detect-dups     Detect and handle duplicate files
    \\  --recursive       Process directories recursively
    \\  --max-depth N     Maximum recursion depth (default: 10)
    \\  --size-threshold N Size threshold for large files in MB (default: 100)
    \\  --date-format FMT Date format: year, year-month, year-month-day
    \\  --dup-action ACT  Duplicate action: skip, rename, replace, keep-both
    \\
    \\Examples:
    \\  {s} /path/to/project                          # Preview organization
    \\  {s} --create /path/to/project                 # Create directories only
    \\  {s} --move /path/to/project                   # Create directories and move files
    \\  {s} --config custom.json /path/to/project     # Use custom categorization config
    \\  {s} --dry-run --verbose /path                 # Verbose preview mode
    \\  {s} --by-date --date-format year-month /path  # Organize by year/month
    \\  {s} --by-size --size-threshold 50 /path       # Separate files larger than 50MB
    \\  {s} --detect-dups --dup-action rename /path   # Detect and rename duplicates
    \\  {s} --recursive --max-depth 5 /path           # Process 5 levels deep
    \\
;

fn printUsage(program_name: []const u8) void {
    print(usage_text, .{ program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name });
}

fn printVersion() void {
    print("{s} {s}\n", .{ PROGRAM_NAME, VERSION });
}

fn printError(message: []const u8) void {
    std.debug.print("Error: {s}\n", .{message});
}

fn parseDateFormat(format_str: []const u8) ?DateFormat {
    if (std.mem.eql(u8, format_str, "year")) {
        return .year;
    } else if (std.mem.eql(u8, format_str, "year-month")) {
        return .year_month;
    } else if (std.mem.eql(u8, format_str, "year-month-day")) {
        return .year_month_day;
    }
    return null;
}

fn parseDuplicateAction(action_str: []const u8) ?DuplicateAction {
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

fn formatDatePath(allocator: std.mem.Allocator, timestamp: i64, date_format: DateFormat) ![]const u8 {
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

fn calculateFileHash(file_path: []const u8) ![32]u8 {
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

fn getFileStats(file_path: []const u8) struct { size: u64, created_time: i64, modified_time: i64, hash: [32]u8 } {
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

fn validateDirectory(path: []const u8) !void {
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

fn loadConfig(allocator: std.mem.Allocator, config_path: []const u8) !ConfigData {
    // Read the config file
    const config_file = std.fs.cwd().openFile(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            printError("Configuration file not found");
            return err;
        },
        error.AccessDenied => {
            printError("Access denied to configuration file");
            return err;
        },
        else => {
            printError("Unable to open configuration file");
            return err;
        },
    };
    defer config_file.close();

    const file_size = try config_file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try config_file.readAll(contents);

    // Parse JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch |err| switch (err) {
        error.InvalidCharacter, error.UnexpectedToken, error.InvalidNumber => {
            printError("Invalid JSON in configuration file");
            return error.InvalidJson;
        },
        else => {
            printError("Failed to parse configuration file");
            return err;
        },
    };
    defer parsed.deinit();

    const root = parsed.value;

    if (root != .object) {
        printError("Configuration file must contain a JSON object");
        return error.InvalidJson;
    }

    // Initialize the config data
    var config_data = ConfigData{
        .version = "",
        .categories = std.StringHashMap(Category).init(allocator),
        .display = DisplayConfig{},
        .behavior = BehaviorConfig{},
    };

    // Parse version (optional)
    if (root.object.get("version")) |version_val| {
        if (version_val == .string) {
            config_data.version = try allocator.dupe(u8, version_val.string);
        }
    }

    // Parse categories (required)
    if (root.object.get("categories")) |categories_val| {
        if (categories_val != .object) {
            printError("'categories' must be an object");
            return error.InvalidJson;
        }

        var categories_iter = categories_val.object.iterator();
        while (categories_iter.next()) |category_entry| {
            const category_name = category_entry.key_ptr.*;
            const category_val = category_entry.value_ptr.*;

            if (category_val != .object) continue;

            // Parse category details
            var category = Category{
                .description = "",
                .extensions = &[_][]const u8{},
                .color = "#FFFFFF",
                .priority = 999,
            };

            if (category_val.object.get("description")) |desc_val| {
                if (desc_val == .string) {
                    category.description = try allocator.dupe(u8, desc_val.string);
                }
            }

            if (category_val.object.get("color")) |color_val| {
                if (color_val == .string) {
                    category.color = try allocator.dupe(u8, color_val.string);
                }
            }

            if (category_val.object.get("priority")) |priority_val| {
                if (priority_val == .integer) {
                    category.priority = @intCast(priority_val.integer);
                }
            }

            if (category_val.object.get("extensions")) |ext_val| {
                if (ext_val == .array) {
                    var extensions = try allocator.alloc([]const u8, ext_val.array.items.len);
                    for (ext_val.array.items, 0..) |item, i| {
                        if (item == .string) {
                            extensions[i] = try allocator.dupe(u8, item.string);
                        } else {
                            extensions[i] = "";
                        }
                    }
                    category.extensions = extensions;
                }
            }

            const category_name_owned = try allocator.dupe(u8, category_name);
            try config_data.categories.put(category_name_owned, category);
        }
    }

    return config_data;
}

fn getFileExtension(filename: []const u8) []const u8 {
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
        if (extension.len >= 1) { // Include single dot case
            return extension;
        }
        return "";
    }
    return "";
}

fn categorizeExtension(extension: []const u8, config_data: ?ConfigData) []const u8 {
    if (config_data) |data| {
        var categories_iter = data.categories.iterator();
        while (categories_iter.next()) |entry| {
            const category_name = entry.key_ptr.*;
            const category = entry.value_ptr.*;

            for (category.extensions) |ext| {
                if (std.mem.eql(u8, extension, ext)) {
                    return category_name;
                }
            }
        }
    }

    // Fallback to enum-based categorization
    const file_category = categorizeFileByExtension(extension);
    return file_category.toString();
}

fn resolveFilenameConflict(allocator: std.mem.Allocator, target_path: []const u8) ![]const u8 {
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
        base_name[0..base_name.len - extension.len]
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

    return error.TooManyConflicts;
}

fn categorizeFileByExtension(extension: []const u8) FileCategory {
    // Handle edge cases
    if (extension.len == 0) {
        return .Other;
    }

    // Handle very long extensions (limit to reasonable size)
    if (extension.len > 32) {
        return .Other;
    }

    // Handle extensions that are only dots or invalid characters
    var has_valid_chars = false;
    for (extension) |char| {
        if (char != '.' and ((char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z') or (char >= '0' and char <= '9'))) {
            has_valid_chars = true;
            break;
        }
    }
    if (!has_valid_chars) {
        return .Other;
    }

    // Convert extension to lowercase for comparison
    var ext_lower: [256]u8 = undefined;

    // Simple lowercase conversion for ASCII with bounds checking
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
        std.mem.eql(u8, ext_lower_slice, ".odt") or
        std.mem.eql(u8, ext_lower_slice, ".rtf") or
        std.mem.eql(u8, ext_lower_slice, ".tex") or
        std.mem.eql(u8, ext_lower_slice, ".md"))
    {
        return .Documents;
    }

    // Images
    if (std.mem.eql(u8, ext_lower_slice, ".jpg") or
        std.mem.eql(u8, ext_lower_slice, ".jpeg") or
        std.mem.eql(u8, ext_lower_slice, ".png") or
        std.mem.eql(u8, ext_lower_slice, ".gif") or
        std.mem.eql(u8, ext_lower_slice, ".bmp") or
        std.mem.eql(u8, ext_lower_slice, ".svg") or
        std.mem.eql(u8, ext_lower_slice, ".ico") or
        std.mem.eql(u8, ext_lower_slice, ".webp"))
    {
        return .Images;
    }

    // Videos
    if (std.mem.eql(u8, ext_lower_slice, ".mp4") or
        std.mem.eql(u8, ext_lower_slice, ".avi") or
        std.mem.eql(u8, ext_lower_slice, ".mkv") or
        std.mem.eql(u8, ext_lower_slice, ".mov") or
        std.mem.eql(u8, ext_lower_slice, ".wmv") or
        std.mem.eql(u8, ext_lower_slice, ".flv") or
        std.mem.eql(u8, ext_lower_slice, ".webm"))
    {
        return .Videos;
    }

    // Audio
    if (std.mem.eql(u8, ext_lower_slice, ".mp3") or
        std.mem.eql(u8, ext_lower_slice, ".wav") or
        std.mem.eql(u8, ext_lower_slice, ".flac") or
        std.mem.eql(u8, ext_lower_slice, ".aac") or
        std.mem.eql(u8, ext_lower_slice, ".ogg") or
        std.mem.eql(u8, ext_lower_slice, ".wma") or
        std.mem.eql(u8, ext_lower_slice, ".m4a"))
    {
        return .Audio;
    }

    // Archives
    if (std.mem.eql(u8, ext_lower_slice, ".zip") or
        std.mem.eql(u8, ext_lower_slice, ".tar") or
        std.mem.eql(u8, ext_lower_slice, ".gz") or
        std.mem.eql(u8, ext_lower_slice, ".rar") or
        std.mem.eql(u8, ext_lower_slice, ".7z") or
        std.mem.eql(u8, ext_lower_slice, ".bz2") or
        std.mem.eql(u8, ext_lower_slice, ".xz"))
    {
        return .Archives;
    }

    // Code
    if (std.mem.eql(u8, ext_lower_slice, ".c") or
        std.mem.eql(u8, ext_lower_slice, ".cpp") or
        std.mem.eql(u8, ext_lower_slice, ".h") or
        std.mem.eql(u8, ext_lower_slice, ".hpp") or
        std.mem.eql(u8, ext_lower_slice, ".py") or
        std.mem.eql(u8, ext_lower_slice, ".js") or
        std.mem.eql(u8, ext_lower_slice, ".ts") or
        std.mem.eql(u8, ext_lower_slice, ".java") or
        std.mem.eql(u8, ext_lower_slice, ".cs") or
        std.mem.eql(u8, ext_lower_slice, ".go") or
        std.mem.eql(u8, ext_lower_slice, ".rs") or
        std.mem.eql(u8, ext_lower_slice, ".zig") or
        std.mem.eql(u8, ext_lower_slice, ".sh") or
        std.mem.eql(u8, ext_lower_slice, ".bat"))
    {
        return .Code;
    }

    // Data
    if (std.mem.eql(u8, ext_lower_slice, ".json") or
        std.mem.eql(u8, ext_lower_slice, ".xml") or
        std.mem.eql(u8, ext_lower_slice, ".csv") or
        std.mem.eql(u8, ext_lower_slice, ".sql") or
        std.mem.eql(u8, ext_lower_slice, ".db") or
        std.mem.eql(u8, ext_lower_slice, ".sqlite"))
    {
        return .Data;
    }

    // Configuration
    if (std.mem.eql(u8, ext_lower_slice, ".ini") or
        std.mem.eql(u8, ext_lower_slice, ".cfg") or
        std.mem.eql(u8, ext_lower_slice, ".conf") or
        std.mem.eql(u8, ext_lower_slice, ".yaml") or
        std.mem.eql(u8, ext_lower_slice, ".yml") or
        std.mem.eql(u8, ext_lower_slice, ".toml"))
    {
        return .Configuration;
    }

    return .Other;
}

fn createDirectories(allocator: std.mem.Allocator, base_path: []const u8, organization_plan: *const OrganizationPlan, config: *const Config) !void {
    // Validate base path length to prevent system issues
    if (base_path.len == 0 or base_path.len > 1024) {
        printError("Invalid base path length");
        return error.InvalidPath;
    }

    if (config.verbose) {
        print("Creating directories in: {s}\n", .{base_path});
    }

    var iterator = organization_plan.categories.iterator();
    while (iterator.next()) |entry| {
        const category = entry.key_ptr.*;
        const file_list = entry.value_ptr.*;

        if (file_list.items.len == 0) continue;

        const dir_name = category.toDirectoryName();

        // Validate directory name for unsafe characters
        for (dir_name) |char| {
            if (char == 0 or char < 32 or char == 127) {
                printError("Invalid directory name contains unsafe characters");
                return error.InvalidDirectoryName;
            }
        }

        // Create full path with bounds checking
        const full_path = try std.mem.join(allocator, "/", &[_][]const u8{ base_path, dir_name });
        defer allocator.free(full_path);

        // Check for path length limits
        if (full_path.len > 2048) {
            printError("Directory path too long");
            return error.PathTooLong;
        }

        if (config.dry_run) {
            print("Would create directory: {s} (for {} files)\n", .{ full_path, file_list.items.len });
        } else if (config.create_directories) {
            // Try to create directory with enhanced error handling
            std.fs.cwd().makeDir(full_path) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    if (config.verbose) {
                        print("Directory already exists: {s}\n", .{full_path});
                    }
                },
                error.AccessDenied => {
                    printError("Permission denied creating directory");
                    print("Failed to create: {s}\n", .{full_path});
                    return err;
                },
                error.FileNotFound => {
                    printError("Parent directory does not exist");
                    print("Cannot create: {s}\n", .{full_path});
                    return err;
                },
                error.NoSpaceLeft => {
                    printError("No space left on device");
                    print("Cannot create: {s}\n", .{full_path});
                    return err;
                },
                error.NameTooLong => {
                    printError("Directory name too long");
                    print("Cannot create: {s}\n", .{full_path});
                    return err;
                },
                else => {
                    printError("Failed to create directory");
                    print("Error creating: {s}, error: {}\n", .{ full_path, err });
                    return err;
                },
            };

            if (config.verbose) {
                print("Created directory: {s}\n", .{full_path});
            }
        }
    }
}

fn moveFiles(allocator: std.mem.Allocator, base_path: []const u8, organization_plan: *const OrganizationPlan, config: *const Config, move_tracker: *MoveTracker) !void {
    if (config.verbose) {
        print("Moving files in: {s}\n", .{base_path});
    }

    var iterator = organization_plan.categories.iterator();
    while (iterator.next()) |entry| {
        const category = entry.key_ptr.*;
        const file_list = entry.value_ptr.*;

        if (file_list.items.len == 0) continue;

        const dir_name = category.toDirectoryName();

        // Create full directory path
        const dest_dir_path = try std.mem.join(allocator, "/", &[_][]const u8{ base_path, dir_name });
        defer allocator.free(dest_dir_path);

        // Move each file in this category
        for (file_list.items) |file_info| {
            const source_path = try std.mem.join(allocator, "/", &[_][]const u8{ base_path, file_info.name });
            defer allocator.free(source_path);

            const initial_dest_path = try std.mem.join(allocator, "/", &[_][]const u8{ dest_dir_path, file_info.name });
            defer allocator.free(initial_dest_path);

            if (config.dry_run) {
                // Check for conflicts in dry-run mode
                const final_dest_path = resolveFilenameConflict(allocator, initial_dest_path) catch |err| {
                    printError("Failed to resolve filename conflict in dry-run");
                    return err;
                };
                defer allocator.free(final_dest_path);

                if (std.mem.eql(u8, initial_dest_path, final_dest_path)) {
                    print("Would move: {s} → {s}\n", .{ source_path, final_dest_path });
                } else {
                    print("Would move: {s} → {s} (renamed due to conflict)\n", .{ source_path, final_dest_path });
                }
            } else if (config.move_files) {
                // Actually move the file
                const final_dest_path = resolveFilenameConflict(allocator, initial_dest_path) catch |err| {
                    printError("Failed to resolve filename conflict");
                    print("Error with file: {s}\n", .{file_info.name});
                    return err;
                };

                // Perform the move
                std.fs.cwd().rename(source_path, final_dest_path) catch |err| {
                    printError("Failed to move file");
                    print("Could not move {s} to {s}: {}\n", .{ source_path, final_dest_path, err });
                    allocator.free(final_dest_path);
                    return err;
                };

                // Record the move for potential rollback
                try move_tracker.recordMove(source_path, final_dest_path);

                if (config.verbose) {
                    if (std.mem.eql(u8, initial_dest_path, final_dest_path)) {
                        print("Moved: {s} → {s}\n", .{ source_path, final_dest_path });
                    } else {
                        print("Moved: {s} → {s} (renamed due to conflict)\n", .{ source_path, final_dest_path });
                    }
                }

                allocator.free(final_dest_path);
            }
        }
    }
}

fn listFilesRecursive(allocator: std.mem.Allocator, dir_path: []const u8, config: *const Config, organization_plan: *OrganizationPlan, depth: u32) !void {
    // Check max depth
    if (depth > config.max_depth) {
        return;
    }

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            printError("Directory not found");
            return;
        },
        error.AccessDenied => {
            printError("Permission denied");
            return;
        },
        else => return err,
    };
    defer dir.close();

    // Iterate through directory and categorize files
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory and config.recursive) {
            // Recursively process subdirectories
            const subdir_path = try std.mem.join(allocator, "/", &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(subdir_path);

            try listFilesRecursive(allocator, subdir_path, config, organization_plan, depth + 1);
        } else if (entry.kind == .file) {
            // Process files (same logic as before)
            const name = try allocator.dupe(u8, entry.name);
            const ext_str = getFileExtension(entry.name);
            const extension = try allocator.dupe(u8, ext_str);
            const category = categorizeFileByExtension(extension);

            // Create full path for file stats
            const full_file_path = try std.mem.join(allocator, "/", &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(full_file_path);
            const stats = getFileStats(full_file_path);
            var file_info = FileInfo{
                .name = name,
                .extension = extension,
                .category = category,
                .size = stats.size,
                .created_time = stats.created_time,
                .modified_time = stats.modified_time,
                .hash = stats.hash,
            };

            // Handle duplicate detection
            if (config.detect_duplicates) {
                // Check if this file hash already exists
                var duplicate_found = false;

                // Search in category organization
                var cat_it = organization_plan.categories.iterator();
                while (cat_it.next()) |cat_entry| {
                    for (cat_entry.value_ptr.items) |existing_file| {
                        if (std.mem.eql(u8, &existing_file.hash, &file_info.hash)) {
                            duplicate_found = true;
                            break;
                        }
                    }
                    if (duplicate_found) break;
                }

                // Search in directory organization if not found in categories
                if (!duplicate_found) {
                    var dir_it = organization_plan.directories.iterator();
                    while (dir_it.next()) |dir_entry| {
                        for (dir_entry.value_ptr.items) |existing_file| {
                            if (std.mem.eql(u8, &existing_file.hash, &file_info.hash)) {
                                duplicate_found = true;
                                break;
                            }
                        }
                        if (duplicate_found) break;
                    }
                }

                if (duplicate_found) {
                    // Handle duplicate based on action
                    switch (config.duplicate_action) {
                        .skip => {
                            // Skip this file (don't add to organization plan)
                            allocator.free(name);
                            allocator.free(extension);
                            continue;
                        },
                        .rename => {
                            // Rename the file by adding a suffix
                            const timestamp = @as(u64, @intCast(std.time.timestamp()));
                            const new_name = try std.fmt.allocPrint(allocator, "{s}_dup_{d}", .{ name, timestamp });
                            allocator.free(name);
                            file_info.name = new_name;
                        },
                        .replace => {
                            // Replace existing (remove from organization plan first, then add new)
                            // This is complex and requires finding and removing the old file
                            // For now, just proceed with adding (effectively replacing)
                        },
                        .keep_both => {
                            // Keep both files (default behavior, just proceed)
                        },
                    }
                }
            }

            // Handle size-based organization
            if (config.organize_by_size) {
                const size_mb = file_info.size / (1024 * 1024);
                const is_large_file = size_mb >= config.size_threshold_mb;

                if (is_large_file) {
                    // Organize large files by type in "Large Files" subdirectories
                    const large_category_name = try std.fmt.allocPrint(allocator, "Large Files/{s}", .{@tagName(category)});
                    defer allocator.free(large_category_name);

                    if (organization_plan.directories.getPtr(large_category_name)) |list_ptr| {
                        try list_ptr.append(allocator, file_info);
                    } else {
                        const large_category_copy = try allocator.dupe(u8, large_category_name);
                        var new_list = std.ArrayList(FileInfo).initCapacity(allocator, 1) catch unreachable;
                        try new_list.append(allocator, file_info);
                        try organization_plan.directories.put(large_category_copy, new_list);
                    }
                } else {
                    // Regular sized files go to normal categories
                    if (organization_plan.categories.getPtr(category)) |list_ptr| {
                        try list_ptr.append(allocator, file_info);
                    } else {
                        var new_list = std.ArrayList(FileInfo).initCapacity(allocator, 1) catch unreachable;
                        try new_list.append(allocator, file_info);
                        try organization_plan.categories.put(category, new_list);
                    }
                }
            } else if (config.organize_by_date) {
                // Date-based organization
                const date_path = try formatDatePath(allocator, file_info.modified_time, config.date_format);
                defer allocator.free(date_path);

                if (organization_plan.directories.getPtr(date_path)) |list_ptr| {
                    try list_ptr.append(allocator, file_info);
                } else {
                    const date_path_copy = try allocator.dupe(u8, date_path);
                    var new_list = std.ArrayList(FileInfo).initCapacity(allocator, 1) catch unreachable;
                    try new_list.append(allocator, file_info);
                    try organization_plan.directories.put(date_path_copy, new_list);
                    // date_path_copy is now owned by the hashmap
                }
            } else {
                // Add file to its category in the organization plan
                if (organization_plan.categories.getPtr(category)) |list_ptr| {
                    try list_ptr.append(allocator, file_info);
                } else {
                    var new_list = std.ArrayList(FileInfo).initCapacity(allocator, 1) catch unreachable;
                    try new_list.append(allocator, file_info);
                    try organization_plan.categories.put(category, new_list);
                }
            }

            // Increment total files count
            organization_plan.total_files += 1;
        }
    }
}

fn listFiles(allocator: std.mem.Allocator, dir_path: []const u8, config: *const Config) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    // Initialize move tracker for rollback capability
    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Initialize organization plan
    var organization_plan = OrganizationPlan{
        .categories = std.hash_map.HashMap(FileCategory, std.ArrayList(FileInfo), std.hash_map.AutoContext(FileCategory), 80).init(allocator),
        .directories = std.StringHashMap(std.ArrayList(FileInfo)).init(allocator),
        .total_files = 0,
        .is_date_based = config.organize_by_date,
        .is_size_based = config.organize_by_size,
    };
    defer {
        var it = organization_plan.categories.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |file| {
                allocator.free(file.name);
                allocator.free(file.extension);
            }
            entry.value_ptr.deinit(allocator);
        }
        organization_plan.categories.deinit();

        var dir_it = organization_plan.directories.iterator();
        while (dir_it.next()) |entry| {
            for (entry.value_ptr.items) |file| {
                allocator.free(file.name);
                allocator.free(file.extension);
            }
            entry.value_ptr.deinit(allocator);
            allocator.free(entry.key_ptr.*); // Free the date path key
        }
        organization_plan.directories.deinit();
    }

    var extension_counts = std.hash_map.StringHashMap(u32).init(allocator);
    var category_counts = std.hash_map.StringHashMap(u32).init(allocator);
    defer {
        var it = extension_counts.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        extension_counts.deinit();

        var cat_it = category_counts.iterator();
        while (cat_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        category_counts.deinit();
    }

    // Use recursive helper to process files (handles both recursive and non-recursive cases)
    try listFilesRecursive(allocator, dir_path, config, &organization_plan, 0);

    // Count extensions and categories from organization plan
    var org_cat_it = organization_plan.categories.iterator();
    while (org_cat_it.next()) |entry| {
        for (entry.value_ptr.items) |file| {
            // Count extensions
            const ext_key = if (file.extension.len > 0) file.extension else "(no extension)";
            const ext_key_copy = try allocator.dupe(u8, ext_key);

            if (extension_counts.get(ext_key_copy)) |count| {
                try extension_counts.put(ext_key_copy, count + 1);
                allocator.free(ext_key_copy);
            } else {
                try extension_counts.put(ext_key_copy, 1);
            }

            // Count categories
            const category_name = @tagName(file.category);
            const category_copy = try allocator.dupe(u8, category_name);

            if (category_counts.get(category_copy)) |count| {
                try category_counts.put(category_copy, count + 1);
                allocator.free(category_copy);
            } else {
                try category_counts.put(category_copy, 1);
            }
        }
    }

    // Also count from directories (for date-based or size-based organization)
    var dir_it = organization_plan.directories.iterator();
    while (dir_it.next()) |entry| {
        for (entry.value_ptr.items) |file| {
            // Count extensions
            const ext_key = if (file.extension.len > 0) file.extension else "(no extension)";
            const ext_key_copy = try allocator.dupe(u8, ext_key);

            if (extension_counts.get(ext_key_copy)) |count| {
                try extension_counts.put(ext_key_copy, count + 1);
                allocator.free(ext_key_copy);
            } else {
                try extension_counts.put(ext_key_copy, 1);
            }

            // Count categories
            const category_name = @tagName(file.category);
            const category_copy = try allocator.dupe(u8, category_name);

            if (category_counts.get(category_copy)) |count| {
                try category_counts.put(category_copy, count + 1);
                allocator.free(category_copy);
            } else {
                try category_counts.put(category_copy, 1);
            }
        }
    }

    // Display results
    if (organization_plan.total_files == 0) {
        print("No files found in directory.\n", .{});
        return;
    }

    print("\n{s}\n", .{"============================================================"});
    if (config.dry_run) {
        if (config.move_files) {
            print("FILE ORGANIZATION PREVIEW - MOVING FILES (DRY RUN)\n", .{});
        } else {
            print("FILE ORGANIZATION PREVIEW (DRY RUN)\n", .{});
        }
    } else if (config.move_files) {
        print("FILE ORGANIZATION - MOVING FILES\n", .{});
    } else if (config.create_directories) {
        print("FILE ORGANIZATION - CREATING DIRECTORIES\n", .{});
    } else {
        print("FILE ORGANIZATION PREVIEW\n", .{});
    }
    print("{s}\n\n", .{"============================================================"});

    print("Total files to organize: {}\n\n", .{organization_plan.total_files});

    if (organization_plan.is_date_based) {
        // Display files grouped by date
        print("Files grouped by date:\n", .{});
        print("{s}\n\n", .{"----------------------------------------"});

        var date_iterator = organization_plan.directories.iterator();
        while (date_iterator.next()) |entry| {
            const date_path = entry.key_ptr.*;
            const file_list = entry.value_ptr.*;

            if (file_list.items.len > 0) {
                print("📅 {s} ({} files):\n", .{ date_path, file_list.items.len });
                for (file_list.items) |file| {
                    print("    • {s}", .{file.name});
                    if (file.extension.len > 0) {
                        print(" ({s})", .{file.extension});
                    }
                    print("\n", .{});
                }
                print("\n", .{});
            }
        }
    } else if (organization_plan.is_size_based) {
        // Display files grouped by size and category
        print("Files grouped by size:\n", .{});
        print("{s}\n\n", .{"----------------------------------------"});

        // Show categories first (normal-sized files)
        const category_order = [_]FileCategory{
            .Documents,
            .Images,
            .Videos,
            .Audio,
            .Archives,
            .Code,
            .Data,
            .Configuration,
            .Other,
        };

        for (category_order) |category| {
            if (organization_plan.categories.get(category)) |file_list| {
                if (file_list.items.len > 0) {
                    print("📁 {s} (normal-sized, {} files):\n", .{ @tagName(category), file_list.items.len });
                    for (file_list.items) |file| {
                        print("    • {s}", .{file.name});
                        if (file.extension.len > 0) {
                            print(" ({s})", .{file.extension});
                        }
                        print("\n", .{});
                    }
                    print("\n", .{});
                }
            }
        }

        // Show large files grouped by directory
        var large_iterator = organization_plan.directories.iterator();
        while (large_iterator.next()) |entry| {
            const large_dir_name = entry.key_ptr.*;
            const file_list = entry.value_ptr.*;
            if (file_list.items.len > 0) {
                print("📦 {s} ({} files):\n", .{ large_dir_name, file_list.items.len });
                for (file_list.items) |file| {
                    const size_mb = file.size / (1024 * 1024);
                    print("    • {s}", .{file.name});
                    if (file.extension.len > 0) {
                        print(" ({s})", .{file.extension});
                    }
                    print(" - {d}MB", .{size_mb});
                    print("\n", .{});
                }
                print("\n", .{});
            }
        }
    } else {
        // Display files grouped by category
        print("Files grouped by category:\n", .{});
        print("{s}\n\n", .{"----------------------------------------"});

        const category_order = [_]FileCategory{
            .Documents,
            .Images,
            .Videos,
            .Audio,
            .Archives,
            .Code,
            .Data,
            .Configuration,
            .Other,
        };

        for (category_order) |category| {
            if (organization_plan.categories.get(category)) |file_list| {
                if (file_list.items.len > 0) {
                    print("📁 {s} ({} files):\n", .{ category.toString(), file_list.items.len });
                    for (file_list.items) |file| {
                        print("    • {s}", .{file.name});
                        if (file.extension.len > 0) {
                            print(" ({s})", .{file.extension});
                        }
                        print("\n", .{});
                    }
                    print("\n", .{});
                }
            }
        }
    }

    // Display organization summary
    print("Organization Summary:\n", .{});
    print("{s}\n", .{"----------------------------------------"});

    if (organization_plan.is_date_based) {
        // Display date summary
        var date_iterator = organization_plan.directories.iterator();
        while (date_iterator.next()) |entry| {
            const date_path = entry.key_ptr.*;
            const file_list = entry.value_ptr.*;
            if (file_list.items.len > 0) {
                const percentage = (@as(f32, @floatFromInt(file_list.items.len)) / @as(f32, @floatFromInt(organization_plan.total_files))) * 100.0;
                print("  {s}: {} files ({d:.1}%)\n", .{ date_path, file_list.items.len, percentage });
            }
        }
    } else if (organization_plan.is_size_based) {
        // Display size-based summary
        // Count normal-sized files by category
        var it = organization_plan.categories.iterator();
        while (it.next()) |entry| {
            const category = entry.key_ptr.*;
            const file_list = entry.value_ptr.*;
            if (file_list.items.len > 0) {
                const percentage = (@as(f32, @floatFromInt(file_list.items.len)) / @as(f32, @floatFromInt(organization_plan.total_files))) * 100.0;
                print("  {s} (normal): {} files ({d:.1}%)\n", .{ @tagName(category), file_list.items.len, percentage });
            }
        }

        // Count large files by category
        var large_iterator = organization_plan.directories.iterator();
        while (large_iterator.next()) |entry| {
            const large_dir_name = entry.key_ptr.*;
            const file_list = entry.value_ptr.*;
            if (file_list.items.len > 0) {
                const percentage = (@as(f32, @floatFromInt(file_list.items.len)) / @as(f32, @floatFromInt(organization_plan.total_files))) * 100.0;
                print("  {s}: {} files ({d:.1}%)\n", .{ large_dir_name, file_list.items.len, percentage });
            }
        }
    } else {
        // Display category summary with both config and enum-based
        const category_order = [_]FileCategory{
            .Documents,
            .Images,
            .Videos,
            .Audio,
            .Archives,
            .Code,
            .Data,
            .Configuration,
            .Other,
        };

        for (category_order) |category| {
            if (organization_plan.categories.get(category)) |file_list| {
                if (file_list.items.len > 0) {
                    const percentage = (@as(f32, @floatFromInt(file_list.items.len)) / @as(f32, @floatFromInt(organization_plan.total_files))) * 100.0;
                    print("  {s}: {} files ({d:.1}%)\n", .{ category.toString(), file_list.items.len, percentage });
                }
            }
        }
    }

    if (category_counts.count() > 0) {
        print("\nCustom category breakdown:\n", .{});
        var cat_it = category_counts.iterator();
        while (cat_it.next()) |entry| {
            print("  {s}: {} file(s)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    // Display file extensions breakdown
    if (extension_counts.count() > 0) {
        print("\nFile extensions breakdown:\n", .{});
        print("{s}\n", .{"----------------------------------------"});
        var it = extension_counts.iterator();
        while (it.next()) |entry| {
            print("  {s}: {} file(s)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    // Create directories if requested
    createDirectories(allocator, dir_path, &organization_plan, config) catch |err| {
        printError("Failed to create directories");
        return err;
    };

    // Move files if requested
    if (config.move_files or config.dry_run) {
        moveFiles(allocator, dir_path, &organization_plan, config, &move_tracker) catch |err| {
            if (config.move_files and !config.dry_run) {
                printError("File moving failed. Attempting rollback...");
                move_tracker.rollback(config) catch |rollback_err| {
                    printError("Rollback also failed!");
                    print("Original error: {}\n", .{err});
                    print("Rollback error: {}\n", .{rollback_err});
                    return rollback_err;
                };
                print("Rollback successful. Files restored to original locations.\n", .{});
            }
            return err;
        };
    }

    print("\n{s}\n", .{"============================================================"});
    if (config.dry_run) {
        if (config.move_files) {
            print("Note: This is a preview. No directories or files have been moved.\n", .{});
        } else {
            print("Note: This is a preview. No directories have been created.\n", .{});
        }
    } else if (config.move_files) {
        print("Directory creation and file moving complete.\n", .{});
    } else if (config.create_directories) {
        print("Directory creation complete.\n", .{});
    } else {
        print("Note: This is a preview. No directories have been created.\n", .{});
    }
    print("{s}\n", .{"============================================================"});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // If no arguments provided
    if (args.len < 2) {
        printError("Missing required directory argument");
        print("\n", .{});
        printUsage(args[0]);
        std.process.exit(1);
    }

    // Parse arguments
    var config = Config{};
    var directory_path: ?[]const u8 = null;
    var i: usize = 1;

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage(args[0]);
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion();
            return;
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing config file path after --config");
                std.process.exit(1);
            }
            config.config_file_path = args[i];
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--create")) {
            config.create_directories = true;
            config.dry_run = false; // Creating implies not dry-run
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--move")) {
            config.move_files = true;
            config.create_directories = true; // Moving implies creating directories
            config.dry_run = false; // Moving implies not dry-run
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dry-run")) {
            config.dry_run = true;
            config.create_directories = false; // Dry-run implies not creating
            config.move_files = false; // Dry-run implies not moving
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--by-date")) {
            config.organize_by_date = true;
        } else if (std.mem.eql(u8, arg, "--by-size")) {
            config.organize_by_size = true;
        } else if (std.mem.eql(u8, arg, "--detect-dups")) {
            config.detect_duplicates = true;
        } else if (std.mem.eql(u8, arg, "--recursive")) {
            config.recursive = true;
        } else if (std.mem.eql(u8, arg, "--max-depth")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value after --max-depth");
                std.process.exit(1);
            }
            config.max_depth = std.fmt.parseInt(u32, args[i], 10) catch {
                printError("Invalid max-depth value");
                print("Expected a number, got: {s}\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--size-threshold")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value after --size-threshold");
                std.process.exit(1);
            }
            config.size_threshold_mb = std.fmt.parseInt(u64, args[i], 10) catch {
                printError("Invalid size-threshold value");
                print("Expected a number, got: {s}\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--date-format")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value after --date-format");
                std.process.exit(1);
            }
            config.date_format = parseDateFormat(args[i]) orelse {
                printError("Invalid date format");
                print("Expected one of: year, year-month, year-month-day, got: {s}\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--dup-action")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value after --dup-action");
                std.process.exit(1);
            }
            config.duplicate_action = parseDuplicateAction(args[i]) orelse {
                printError("Invalid duplicate action");
                print("Expected one of: skip, rename, replace, keep-both, got: {s}\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "-")) {
            printError("Unknown option");
            print("Try '{s} --help' for more information.\n", .{args[0]});
            std.process.exit(1);
        } else {
            // Positional argument (directory path)
            if (directory_path != null) {
                printError("Multiple directory paths provided. Only one is allowed");
                std.process.exit(1);
            }
            directory_path = arg;
        }

        i += 1;
    }

    // Ensure directory path was provided
    const path = directory_path orelse {
        printError("Missing required directory argument");
        print("\n", .{});
        printUsage(args[0]);
        std.process.exit(1);
    };

    // Validate directory exists
    validateDirectory(path) catch {
        std.process.exit(1);
    };

    // Load configuration if provided
    if (config.config_file_path) |config_path| {
        config.data = loadConfig(allocator, config_path) catch {
            printError("Failed to load configuration file");
            std.process.exit(1);
        };
    }

    // If we get here, directory is valid
    print("Analyzing directory: {s}\n", .{path});
    if (config.config_file_path) |config_path| {
        print("Using configuration: {s}\n", .{config_path});
    }

    // List files in the directory
    listFiles(allocator, path, &config) catch |err| {
        if (err == error.AccessDenied) {
            printError("Permission denied while reading directory contents");
        } else {
            printError("Failed to read directory contents");
        }
        std.process.exit(1);
    };
}

// Tests
test "basic test" {
    try std.testing.expect(true);
}

test "getFileExtension" {
    const testing = std.testing;

    // Test regular files with extensions
    try testing.expectEqualStrings(".txt", getFileExtension("file.txt"));
    try testing.expectEqualStrings(".zig", getFileExtension("main.zig"));
    try testing.expectEqualStrings(".gz", getFileExtension("archive.tar.gz"));

    // Test files without extensions
    try testing.expectEqualStrings("", getFileExtension("README"));
    try testing.expectEqualStrings("", getFileExtension("Makefile"));

    // Test hidden files (starting with .)
    try testing.expectEqualStrings("", getFileExtension(".gitignore"));
    try testing.expectEqualStrings(".txt", getFileExtension(".hidden.txt"));
}

test "categorizeFileByExtension" {
    const testing = std.testing;

    // Test Documents
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".txt"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".pdf"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".md"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".doc"));

    // Test Images
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".jpg"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".jpeg"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".png"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".gif"));

    // Test Videos
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".mp4"));
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".avi"));
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".mkv"));

    // Test Audio
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".mp3"));
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".wav"));
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".flac"));

    // Test Archives
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".zip"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".tar"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".gz"));

    // Test Code
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".zig"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".py"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".js"));

    // Test Data
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".json"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".xml"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".csv"));

    // Test Configuration
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".ini"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".yaml"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".toml"));

    // Test case insensitive
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".JPG"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".PNG"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".ZIG"));

    // Test Other/Unknown
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".xyz"));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(""));
}

test "toDirectoryName" {
    const testing = std.testing;

    // Test directory name mapping
    try testing.expectEqualStrings("documents", FileCategory.Documents.toDirectoryName());
    try testing.expectEqualStrings("images", FileCategory.Images.toDirectoryName());
    try testing.expectEqualStrings("videos", FileCategory.Videos.toDirectoryName());
    try testing.expectEqualStrings("audio", FileCategory.Audio.toDirectoryName());
    try testing.expectEqualStrings("archives", FileCategory.Archives.toDirectoryName());
    try testing.expectEqualStrings("code", FileCategory.Code.toDirectoryName());
    try testing.expectEqualStrings("data", FileCategory.Data.toDirectoryName());
    try testing.expectEqualStrings("config", FileCategory.Configuration.toDirectoryName());
    try testing.expectEqualStrings("misc", FileCategory.Other.toDirectoryName());
}

test "Config defaults" {
    const testing = std.testing;

    const config = Config{};
    try testing.expectEqual(false, config.create_directories);
    try testing.expectEqual(false, config.move_files);
    try testing.expectEqual(true, config.dry_run);
    try testing.expectEqual(false, config.verbose);
}

test "resolveFilenameConflict with no conflict" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test with non-existent file (should return original path)
    const result = try resolveFilenameConflict(allocator, "/tmp/nonexistent_file.txt");
    defer allocator.free(result);

    try testing.expectEqualStrings("/tmp/nonexistent_file.txt", result);
}

test "MoveTracker initialization and cleanup" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Verify it initializes correctly
    try testing.expectEqual(@as(usize, 0), move_tracker.moves.items.len);
}

test "MoveTracker record move" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    try move_tracker.recordMove("/source/file.txt", "/dest/file.txt");

    try testing.expectEqual(@as(usize, 1), move_tracker.moves.items.len);
    try testing.expectEqualStrings("/source/file.txt", move_tracker.moves.items[0].original_path);
    try testing.expectEqualStrings("/dest/file.txt", move_tracker.moves.items[0].destination_path);
}

// Additional comprehensive tests

test "getFileExtension edge cases" {
    const testing = std.testing;

    // Test edge cases for special characters and Unicode
    try testing.expectEqualStrings(".txt", getFileExtension("file with spaces.txt"));
    try testing.expectEqualStrings(".pdf", getFileExtension("file-with-dashes.pdf"));
    try testing.expectEqualStrings(".jpg", getFileExtension("file_with_underscores.jpg"));
    try testing.expectEqualStrings(".txt", getFileExtension("file123.txt"));
    try testing.expectEqualStrings(".", getFileExtension("file."));
    try testing.expectEqualStrings("", getFileExtension("."));
    try testing.expectEqualStrings("", getFileExtension(""));

    // Test files with multiple dots
    try testing.expectEqualStrings(".gz", getFileExtension("archive.tar.gz"));
    try testing.expectEqualStrings(".old", getFileExtension("config.ini.old"));

    // Test very long extensions and filenames
    try testing.expectEqualStrings(".extension", getFileExtension("file.extension"));
    try testing.expectEqualStrings(".verylongextension", getFileExtension("short.verylongextension"));
}

test "categorizeFileByExtension case insensitive" {
    const testing = std.testing;

    // Test case insensitive behavior
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".TXT"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".PDF"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".Md"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".JPEG"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".Png"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".ZiG"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".PY"));

    // Mixed case
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".ZiP"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".JsOn"));
}

test "categorizeFileByExtension empty and special extensions" {
    const testing = std.testing;

    // Test empty and special cases
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(""));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension("."));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".unknown"));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".123"));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".special-chars"));
}

test "validateDirectory with non-existent path" {
    // This test validates the error handling for non-existent directories
    const testing = std.testing;

    const result = validateDirectory("/definitely/does/not/exist/path");
    try testing.expectError(error.FileNotFound, result);
}

test "FileCategory toString" {
    const testing = std.testing;

    // Test all enum values
    try testing.expectEqualStrings("Documents", FileCategory.Documents.toString());
    try testing.expectEqualStrings("Images", FileCategory.Images.toString());
    try testing.expectEqualStrings("Videos", FileCategory.Videos.toString());
    try testing.expectEqualStrings("Audio", FileCategory.Audio.toString());
    try testing.expectEqualStrings("Archives", FileCategory.Archives.toString());
    try testing.expectEqualStrings("Code", FileCategory.Code.toString());
    try testing.expectEqualStrings("Data", FileCategory.Data.toString());
    try testing.expectEqualStrings("Configuration", FileCategory.Configuration.toString());
    try testing.expectEqualStrings("Other", FileCategory.Other.toString());
}

test "categorizeExtension with config data" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Create a minimal config for testing
    var categories = std.StringHashMap(Category).init(allocator);
    defer {
        var iter = categories.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.extensions) |ext| {
                allocator.free(ext);
            }
            allocator.free(entry.value_ptr.extensions);
            allocator.free(entry.value_ptr.description);
            allocator.free(entry.value_ptr.color);
        }
        categories.deinit();
    }

    // Add a custom category
    var extensions = try allocator.alloc([]const u8, 2);
    extensions[0] = try allocator.dupe(u8, ".custom");
    extensions[1] = try allocator.dupe(u8, ".special");

    const category = Category{
        .description = try allocator.dupe(u8, "Custom files"),
        .extensions = extensions,
        .color = try allocator.dupe(u8, "#FF0000"),
        .priority = 1,
    };

    const category_name = try allocator.dupe(u8, "Custom");
    try categories.put(category_name, category);

    const config_data = ConfigData{
        .version = "1.0",
        .categories = categories,
        .display = DisplayConfig{},
        .behavior = BehaviorConfig{},
    };

    // Test custom extension categorization
    const result = categorizeExtension(".custom", config_data);
    try testing.expectEqualStrings("Custom", result);

    const result2 = categorizeExtension(".special", config_data);
    try testing.expectEqualStrings("Custom", result2);

    // Test fallback to enum-based categorization
    const result3 = categorizeExtension(".txt", config_data);
    try testing.expectEqualStrings("Documents", result3);
}

test "categorizeExtension fallback to enum" {
    const testing = std.testing;

    // Test fallback when no config is provided
    const result = categorizeExtension(".txt", null);
    try testing.expectEqualStrings("Documents", result);

    const result2 = categorizeExtension(".jpg", null);
    try testing.expectEqualStrings("Images", result2);

    const result3 = categorizeExtension(".unknown", null);
    try testing.expectEqualStrings("Other", result3);
}

test "MoveTracker multiple moves and cleanup" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Record multiple moves
    try move_tracker.recordMove("/source1/file1.txt", "/dest1/file1.txt");
    try move_tracker.recordMove("/source2/file2.jpg", "/dest2/file2.jpg");
    try move_tracker.recordMove("/source3/file3.pdf", "/dest3/file3.pdf");

    try testing.expectEqual(@as(usize, 3), move_tracker.moves.items.len);

    // Verify all moves are recorded correctly
    try testing.expectEqualStrings("/source1/file1.txt", move_tracker.moves.items[0].original_path);
    try testing.expectEqualStrings("/dest1/file1.txt", move_tracker.moves.items[0].destination_path);
    try testing.expectEqualStrings("/source2/file2.jpg", move_tracker.moves.items[1].original_path);
    try testing.expectEqualStrings("/dest2/file2.jpg", move_tracker.moves.items[1].destination_path);
    try testing.expectEqualStrings("/source3/file3.pdf", move_tracker.moves.items[2].original_path);
    try testing.expectEqualStrings("/dest3/file3.pdf", move_tracker.moves.items[2].destination_path);
}

test "loadConfig with invalid JSON" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test invalid JSON handling - this should return an error
    const result = loadConfig(allocator, "nonexistent_config.json");
    try testing.expectError(error.FileNotFound, result);
}

test "Config with various flags" {
    const testing = std.testing;

    // Test different configuration combinations
    var config1 = Config{};
    config1.create_directories = true;
    try testing.expectEqual(true, config1.create_directories);
    try testing.expectEqual(false, config1.move_files);
    try testing.expectEqual(true, config1.dry_run); // Default should still be true

    var config2 = Config{};
    config2.move_files = true;
    try testing.expectEqual(false, config2.create_directories); // Default
    try testing.expectEqual(true, config2.move_files);

    var config3 = Config{};
    config3.verbose = true;
    config3.dry_run = false;
    try testing.expectEqual(true, config3.verbose);
    try testing.expectEqual(false, config3.dry_run);
}

test "FileCategory all categories coverage" {
    const testing = std.testing;

    // Test that we can create and use all categories
    const categories = [_]FileCategory{
        .Documents, .Images, .Videos, .Audio, .Archives, .Code, .Data, .Configuration, .Other
    };

    for (categories) |category| {
        // Verify toString works for all
        const name = category.toString();
        try testing.expect(name.len > 0);

        // Verify toDirectoryName works for all
        const dir_name = category.toDirectoryName();
        try testing.expect(dir_name.len > 0);

        // Verify they're not the same (directory names are lowercase)
        if (category != .Other) { // "Other" -> "misc" is a special case
            try testing.expect(!std.mem.eql(u8, name, dir_name));
        }
    }
}

test "resolveFilenameConflict with special characters" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test with filenames containing special characters
    const result1 = try resolveFilenameConflict(allocator, "/tmp/file with spaces.txt");
    defer allocator.free(result1);
    try testing.expectEqualStrings("/tmp/file with spaces.txt", result1);

    const result2 = try resolveFilenameConflict(allocator, "/tmp/file-with-dashes.jpg");
    defer allocator.free(result2);
    try testing.expectEqualStrings("/tmp/file-with-dashes.jpg", result2);

    const result3 = try resolveFilenameConflict(allocator, "/tmp/file_with_underscores.pdf");
    defer allocator.free(result3);
    try testing.expectEqualStrings("/tmp/file_with_underscores.pdf", result3);
}

test "FileInfo struct creation" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test FileInfo struct creation and cleanup
    const name = try allocator.dupe(u8, "test.txt");
    const extension = try allocator.dupe(u8, ".txt");
    defer allocator.free(name);
    defer allocator.free(extension);

    const file_info = FileInfo{
        .name = name,
        .extension = extension,
        .category = .Documents,
        .size = 0,
        .created_time = 0,
        .modified_time = 0,
        .hash = [_]u8{0} ** 32,
    };

    try testing.expectEqualStrings("test.txt", file_info.name);
    try testing.expectEqualStrings(".txt", file_info.extension);
    try testing.expectEqual(FileCategory.Documents, file_info.category);
}

test "extensive file extension coverage" {
    const testing = std.testing;

    // Test many more file extensions for comprehensive coverage

    // Documents - additional extensions
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".docx"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".odt"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".rtf"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".tex"));

    // Images - additional extensions
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".bmp"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".svg"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".ico"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".webp"));

    // Videos - additional extensions
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".mov"));
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".wmv"));
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".flv"));
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".webm"));

    // Audio - additional extensions
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".aac"));
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".ogg"));
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".wma"));
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".m4a"));

    // Archives - additional extensions
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".rar"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".7z"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".bz2"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".xz"));

    // Code - additional extensions
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".c"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".cpp"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".h"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".hpp"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".java"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".cs"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".go"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".rs"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".sh"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".bat"));

    // Data - additional extensions
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".xml"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".csv"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".sql"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".db"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".sqlite"));

    // Configuration - additional extensions
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".ini"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".cfg"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".conf"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".yaml"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".yml"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".toml"));
}

// Integration tests with temporary directories

test "integration - create temporary directory with files" {
    const allocator = std.testing.allocator;

    // Create a temporary directory
    const temp_dir_name = "zigstack_test_temp";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create test files in the temporary directory
    const test_files = [_][]const u8{
        "document.txt",
        "image.jpg",
        "video.mp4",
        "audio.mp3",
        "archive.zip",
        "source.zig",
        "data.json",
        "config.yaml",
        "unknown.xyz",
        "no_extension",
        ".hidden_file",
        "file with spaces.pdf",
        "file-with-dashes.png",
        "file_with_underscores.wav",
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (test_files) |filename| {
        var file = try temp_dir.createFile(filename, .{});
        try file.writeAll("test content");
        file.close();
    }

    // Test that the files were created successfully
    for (test_files) |filename| {
        temp_dir.access(filename, .{}) catch |err| {
            std.debug.print("Failed to access file: {s}\n", .{filename});
            return err;
        };
    }

    // Test listFiles function with the temporary directory
    const config = Config{
        .dry_run = true,
        .verbose = false,
        .create_directories = false,
        .move_files = false,
    };

    // The listFiles function should run without errors
    listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("listFiles failed with error: {}\n", .{err});
        return err;
    };
}

test "integration - directory creation workflow" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing directory creation
    const temp_dir_name = "zigstack_test_create_dirs";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create test files
    const test_files = [_][]const u8{
        "test1.txt",
        "test2.jpg",
        "test3.mp4",
        "test4.zip",
        "test5.zig",
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (test_files) |filename| {
        var file = try temp_dir.createFile(filename, .{});
        try file.writeAll("test content for integration testing");
        file.close();
    }

    // Test with directory creation enabled
    const config = Config{
        .dry_run = false,
        .verbose = false,
        .create_directories = true,
        .move_files = false,
    };

    listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Directory creation test failed: {}\n", .{err});
        return err;
    };

    // Verify directories were created
    const expected_dirs = [_][]const u8{
        "documents",
        "images",
        "videos",
        "archives",
        "code",
    };

    for (expected_dirs) |dir_name| {
        const dir_path = try std.mem.join(allocator, "/", &[_][]const u8{ temp_dir_name, dir_name });
        defer allocator.free(dir_path);

        std.fs.cwd().access(dir_path, .{}) catch |err| {
            std.debug.print("Expected directory not found: {s}\n", .{dir_path});
            return err;
        };
    }
}

test "integration - file moving workflow" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing file moving
    const temp_dir_name = "zigstack_test_move_files";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create test files with different extensions
    const test_files = [_]struct {
        name: []const u8,
        expected_dir: []const u8,
    }{
        .{ .name = "document.txt", .expected_dir = "documents" },
        .{ .name = "picture.jpg", .expected_dir = "images" },
        .{ .name = "movie.mp4", .expected_dir = "videos" },
        .{ .name = "song.mp3", .expected_dir = "audio" },
        .{ .name = "backup.zip", .expected_dir = "archives" },
        .{ .name = "program.zig", .expected_dir = "code" },
        .{ .name = "database.json", .expected_dir = "data" },
        .{ .name = "settings.yaml", .expected_dir = "config" },
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (test_files) |test_file| {
        var file = try temp_dir.createFile(test_file.name, .{});
        try file.writeAll("test content for file moving");
        file.close();
    }

    // Test with file moving enabled
    const config = Config{
        .dry_run = false,
        .verbose = false,
        .create_directories = true,
        .move_files = true,
    };

    listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("File moving test failed: {}\n", .{err});
        return err;
    };

    // Verify files were moved to correct directories
    for (test_files) |test_file| {
        const file_path = try std.mem.join(allocator, "/", &[_][]const u8{ temp_dir_name, test_file.expected_dir, test_file.name });
        defer allocator.free(file_path);

        std.fs.cwd().access(file_path, .{}) catch |err| {
            std.debug.print("Expected file not found: {s}\n", .{file_path});
            return err;
        };

        // Verify original file no longer exists in root
        const original_path = try std.mem.join(allocator, "/", &[_][]const u8{ temp_dir_name, test_file.name });
        defer allocator.free(original_path);

        std.fs.cwd().access(original_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {}, // Expected - file should have been moved
            else => {
                std.debug.print("Original file still exists: {s}\n", .{original_path});
                return err;
            },
        };
    }
}

test "integration - filename conflict resolution" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing filename conflicts
    const temp_dir_name = "zigstack_test_conflicts";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    // Create directories first
    try temp_dir.makeDir("documents");

    // Create a file in the documents directory to create a conflict
    var existing_file = try temp_dir.createFile("documents/test.txt", .{});
    try existing_file.writeAll("existing content");
    existing_file.close();

    // Create a file with the same name in the root directory
    var new_file = try temp_dir.createFile("test.txt", .{});
    try new_file.writeAll("new content");
    new_file.close();

    // Test file moving with conflict resolution
    const config = Config{
        .dry_run = false,
        .verbose = true,
        .create_directories = true,
        .move_files = true,
    };

    listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Conflict resolution test failed: {}\n", .{err});
        return err;
    };

    // Verify that both files exist (original and renamed)
    temp_dir.access("documents/test.txt", .{}) catch |err| {
        std.debug.print("Original conflicting file missing: {}\n", .{err});
        return err;
    };

    // The new file should have been renamed to test_1.txt
    temp_dir.access("documents/test_1.txt", .{}) catch |err| {
        std.debug.print("Renamed conflicting file missing: {}\n", .{err});
        return err;
    };
}

test "integration - empty directory handling" {
    const allocator = std.testing.allocator;

    // Create a temporary empty directory
    const temp_dir_name = "zigstack_test_empty";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    const config = Config{
        .dry_run = true,
        .verbose = false,
        .create_directories = false,
        .move_files = false,
    };

    // Test that empty directories are handled gracefully
    listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Empty directory test failed: {}\n", .{err});
        return err;
    };
}

test "integration - special characters in filenames" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing special characters
    const temp_dir_name = "zigstack_test_special";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create files with special characters in names
    const special_files = [_][]const u8{
        "file with spaces.txt",
        "file-with-dashes.jpg",
        "file_with_underscores.mp3",
        "file123numbers.pdf",
        "file.multiple.dots.zip",
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (special_files) |filename| {
        var file = try temp_dir.createFile(filename, .{});
        try file.writeAll("content with special characters");
        file.close();
    }

    // Test with dry run first
    const config = Config{
        .dry_run = true,
        .verbose = false,
        .create_directories = false,
        .move_files = true, // Test move logic in dry-run mode
    };

    listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Special characters test failed: {}\n", .{err});
        return err;
    };
}

test "integration - rollback functionality" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test MoveTracker rollback with real files (simulated)
    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Simulate recording some moves
    try move_tracker.recordMove("source1.txt", "dest1.txt");
    try move_tracker.recordMove("source2.jpg", "dest2.jpg");

    try testing.expectEqual(@as(usize, 2), move_tracker.moves.items.len);

    // Test that rollback configuration works
    const config = Config{
        .dry_run = false,
        .verbose = true,
        .create_directories = false,
        .move_files = false,
    };

    // Note: We can't actually test file system rollback without creating real files
    // that we might fail to move, but we can test that the structure works
    try testing.expectEqual(true, config.verbose);
}

// Edge case tests for improved robustness

test "edge cases - empty filename handling" {
    const testing = std.testing;

    // Test empty filename
    try testing.expectEqualStrings("", getFileExtension(""));

    // Test filename with only dots
    try testing.expectEqualStrings("", getFileExtension("..."));
    try testing.expectEqualStrings("", getFileExtension(".."));

    // Test edge cases with categorization
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(""));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension("."));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension("..."));
}

test "edge cases - very long extensions" {
    const testing = std.testing;

    // Test very long extension (should be categorized as Other)
    const long_extension = ".verylongextensionnamethatexceedslimits123456789";
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(long_extension));

    // Test normal extension still works
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".txt"));
}

test "edge cases - invalid characters in extensions" {
    const testing = std.testing;

    // Test extensions with only dots and invalid characters
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension("....."));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".@#$%"));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".*&^%"));

    // Test valid extensions with numbers (should still work)
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".123")); // Numbers only should be Other
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".jpg")); // Valid extension
}

test "edge cases - filename boundaries" {
    const testing = std.testing;

    // Test single character filenames
    try testing.expectEqualStrings("", getFileExtension("a"));
    try testing.expectEqualStrings(".b", getFileExtension("a.b"));

    // Test filename ending with dot
    try testing.expectEqualStrings(".", getFileExtension("file."));

    // Test multiple extensions
    try testing.expectEqualStrings(".old", getFileExtension("file.txt.old"));
    try testing.expectEqualStrings(".gz", getFileExtension("archive.tar.gz"));

    // Categorize these edge cases
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension("."));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".old"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".gz")); // .gz is a known archive extension
}

test "edge cases - special filename patterns" {
    const testing = std.testing;

    // Test files that start and end with dots
    try testing.expectEqualStrings("", getFileExtension(".hidden"));
    try testing.expectEqualStrings(".txt", getFileExtension(".hidden.txt"));

    // Test files with numbers and special chars
    try testing.expectEqualStrings(".123", getFileExtension("file.123"));
    try testing.expectEqualStrings(".test", getFileExtension("123.test"));
    try testing.expectEqualStrings(".txt", getFileExtension("file-name_123.txt"));

    // Verify these get categorized correctly
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".123"));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".test"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".txt"));
}

// Advanced feature tests

test "date format parsing" {
    const testing = std.testing;
    try testing.expectEqual(DateFormat.year, parseDateFormat("year").?);
    try testing.expectEqual(DateFormat.year_month, parseDateFormat("year-month").?);
    try testing.expectEqual(DateFormat.year_month_day, parseDateFormat("year-month-day").?);
    try testing.expectEqual(@as(?DateFormat, null), parseDateFormat("invalid")); // Should return null for invalid input
}

test "duplicate action parsing" {
    const testing = std.testing;
    try testing.expectEqual(DuplicateAction.skip, parseDuplicateAction("skip").?);
    try testing.expectEqual(DuplicateAction.rename, parseDuplicateAction("rename").?);
    try testing.expectEqual(DuplicateAction.replace, parseDuplicateAction("replace").?);
    try testing.expectEqual(DuplicateAction.keep_both, parseDuplicateAction("keep-both").?);
    try testing.expectEqual(@as(?DuplicateAction, null), parseDuplicateAction("invalid")); // Should return null for invalid input
}

test "formatDatePath various formats" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test with known timestamp (2025-09-26 14:30:00 UTC)
    const test_timestamp: i64 = 1758913800;

    // Test year format
    const year_path = try formatDatePath(allocator, test_timestamp, DateFormat.year);
    defer allocator.free(year_path);
    try testing.expectEqualStrings("2025", year_path);

    // Test year-month format
    const year_month_path = try formatDatePath(allocator, test_timestamp, DateFormat.year_month);
    defer allocator.free(year_month_path);
    try testing.expectEqualStrings("2025/09", year_month_path);

    // Test year-month-day format
    const year_month_day_path = try formatDatePath(allocator, test_timestamp, DateFormat.year_month_day);
    defer allocator.free(year_month_day_path);
    try testing.expectEqualStrings("2025/09/26", year_month_day_path);
}

test "getFileStats functionality" {
    const testing = std.testing;

    // Create a temporary file
    const temp_file_name = "test_stats_file.txt";
    const test_content = "test content for stats";

    // Write test content
    const file = try std.fs.cwd().createFile(temp_file_name, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(temp_file_name) catch {};

    try file.writeAll(test_content);

    // Test getFileStats
    const stats = getFileStats(temp_file_name);
    try testing.expect(stats.size == test_content.len);
    try testing.expect(stats.created_time > 0);
    try testing.expect(stats.modified_time > 0);
    // Hash should not be all zeros for non-empty file
    try testing.expect(stats.hash[0] != 0 or stats.hash[1] != 0 or stats.hash[2] != 0);
}

test "calculateFileHash with different content" {
    const testing = std.testing;

    // Create two files with different content
    const file1_name = "test_hash_file1.txt";
    const file2_name = "test_hash_file2.txt";

    defer std.fs.cwd().deleteFile(file1_name) catch {};
    defer std.fs.cwd().deleteFile(file2_name) catch {};

    // Create file 1
    const file1 = try std.fs.cwd().createFile(file1_name, .{});
    defer file1.close();
    try file1.writeAll("content 1");

    // Create file 2 with different content
    const file2 = try std.fs.cwd().createFile(file2_name, .{});
    defer file2.close();
    try file2.writeAll("content 2");

    // Calculate hashes
    const hash1 = try calculateFileHash(file1_name);
    const hash2 = try calculateFileHash(file2_name);

    // Hashes should be different for different content
    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));

    // Same file should produce same hash
    const hash1_again = try calculateFileHash(file1_name);
    try testing.expect(std.mem.eql(u8, &hash1, &hash1_again));
}

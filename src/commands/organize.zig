const std = @import("std");
const print = std.debug.print;

// Core module imports
const config_mod = @import("../core/config.zig");
const file_info_mod = @import("../core/file_info.zig");
const organization_mod = @import("../core/organization.zig");
const tracker_mod = @import("../core/tracker.zig");
const utils = @import("../core/utils.zig");
const command_mod = @import("command.zig");

// Type exports
pub const Config = config_mod.Config;
pub const ConfigData = config_mod.ConfigData;
pub const Category = config_mod.Category;
pub const DisplayConfig = config_mod.DisplayConfig;
pub const BehaviorConfig = config_mod.BehaviorConfig;
pub const DateFormat = config_mod.DateFormat;
pub const DuplicateAction = config_mod.DuplicateAction;
pub const FileInfo = file_info_mod.FileInfo;
pub const FileCategory = file_info_mod.FileCategory;
pub const OrganizationPlan = organization_mod.OrganizationPlan;
pub const MoveTracker = tracker_mod.MoveTracker;
pub const Command = command_mod.Command;

// Utility function shortcuts
const printError = utils.printError;
const printSuccess = utils.printSuccess;
const printInfo = utils.printInfo;
const printWarning = utils.printWarning;
const validateDirectory = utils.validateDirectory;
const resolveFilenameConflict = utils.resolveFilenameConflict;
const getFileExtension = utils.getFileExtension;
const getFileStats = utils.getFileStats;
const calculateFileHash = utils.calculateFileHash;
const formatDatePath = utils.formatDatePath;
const parseDateFormat = utils.parseDateFormat;
const parseDuplicateAction = utils.parseDuplicateAction;

const organize_help_text =
    \\Usage: zigstack organize [OPTIONS] <directory>
    \\
    \\Organize files based on extension, date, size, and duplicates.
    \\
    \\Arguments:
    \\  <directory>       Directory path to organize
    \\
    \\Options:
    \\  -h, --help        Display this help message
    \\  --config PATH     Configuration file path (JSON format)
    \\  -c, --create      Create directories (default: preview only)
    \\  -m, --move        Move files to directories (implies --create)
    \\  -d, --dry-run     Show what would happen without doing it
    \\  -V, --verbose     Enable verbose logging
    \\
    \\Advanced Organization:
    \\  --by-date         Organize files by date (creation/modification)
    \\  --date-format FMT Date format: year, year-month, year-month-day
    \\  --by-size         Organize large files separately
    \\  --size-threshold N Size threshold for large files in MB (default: 100)
    \\  --detect-dups     Detect and handle duplicate files
    \\  --dup-action ACT  Duplicate action: skip, rename, replace, keep-both
    \\  --recursive       Process directories recursively
    \\  --max-depth N     Maximum recursion depth (default: 10)
    \\
    \\Examples:
    \\  zigstack organize /path/to/directory
    \\  zigstack organize --move --by-date /path
    \\  zigstack organize --recursive --max-depth 5 /path
    \\
;

// ============================================================================
// Configuration Loading
// ============================================================================

pub fn loadConfig(allocator: std.mem.Allocator, config_path: []const u8) !ConfigData {
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

// ============================================================================
// File Categorization
// ============================================================================

pub fn categorizeExtension(extension: []const u8, config_data: ?ConfigData) []const u8 {
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

pub fn categorizeFileByExtension(extension: []const u8) FileCategory {
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

// ============================================================================
// Directory Operations
// ============================================================================

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

// ============================================================================
// File Movement Operations
// ============================================================================

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

// ============================================================================
// File Discovery and Organization
// ============================================================================

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

pub fn listFiles(allocator: std.mem.Allocator, dir_path: []const u8, config: *const Config) !void {
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

// ============================================================================
// Command Entry Point
// ============================================================================

/// Execute the organize command with given arguments
pub fn executeOrganizeCommand(allocator: std.mem.Allocator, args: []const []const u8, base_config: *Config) !void {
    var config = base_config.*;
    var directory_path: ?[]const u8 = null;
    var i: usize = 0;

    // Parse arguments
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing config file path after --config");
                std.process.exit(1);
            }
            config.config_file_path = args[i];
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--create")) {
            config.create_directories = true;
            config.dry_run = false;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--move")) {
            config.move_files = true;
            config.create_directories = true;
            config.dry_run = false;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dry-run")) {
            config.dry_run = true;
            config.create_directories = false;
            config.move_files = false;
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

// ============================================================================
// Command Interface Implementation
// ============================================================================

fn organizeExecute(allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void {
    // Check for help flag
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            organizeHelp();
            return;
        }
    }

    try executeOrganizeCommand(allocator, args, config);
}

fn organizeHelp() void {
    print("{s}", .{organize_help_text});
}

pub fn getCommand() Command {
    return Command{
        .name = "organize",
        .description = "Organize files by extension, date, size, or duplicates",
        .execute_fn = organizeExecute,
        .help_fn = organizeHelp,
    };
}

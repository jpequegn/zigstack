const std = @import("std");
const print = std.debug.print;

const VERSION = "0.1.0";
const PROGRAM_NAME = "zigstack";

const FileInfo = struct {
    name: []const u8,
    extension: []const u8,
};

const Category = struct {
    description: []const u8,
    extensions: []const []const u8,
    color: []const u8,
    priority: u32,
};

const DisplayConfig = struct {
    show_categories: bool = true,
    show_colors: bool = false,
    group_by_category: bool = true,
    sort_categories_by_priority: bool = true,
    show_category_summaries: bool = true,
    show_uncategorized: bool = true,
    uncategorized_label: []const u8 = "Other",
};

const BehaviorConfig = struct {
    case_sensitive_extensions: bool = false,
    include_hidden_files: bool = false,
    include_directories: bool = false,
    max_depth: u32 = 1,
};

const ConfigData = struct {
    version: []const u8,
    categories: std.StringHashMap(Category),
    display: DisplayConfig,
    behavior: BehaviorConfig,

    pub fn deinit(self: *ConfigData) void {
        self.categories.deinit();
    }
};

const Config = struct {
    config_file_path: ?[]const u8 = null,
    data: ?ConfigData = null,
};

const usage_text =
    \\Usage: {s} [OPTIONS] <directory>
    \\
    \\Analyze and manage Zig project stack structure.
    \\
    \\Arguments:
    \\  <directory>       Directory path to analyze
    \\
    \\Options:
    \\  -h, --help        Display this help message
    \\  -v, --version     Display version information
    \\  -c, --config PATH Configuration file path (JSON format)
    \\
    \\Examples:
    \\  {s} /path/to/project
    \\  {s} --config custom.json /path/to/project
    \\  {s} --help
    \\  {s} --version
    \\
;

fn printUsage(program_name: []const u8) void {
    print(usage_text, .{ program_name, program_name, program_name, program_name, program_name });
}

fn printVersion() void {
    print("{s} {s}\n", .{ PROGRAM_NAME, VERSION });
}

fn printError(message: []const u8) void {
    std.debug.print("Error: {s}\n", .{message});
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
    if (std.mem.lastIndexOf(u8, filename, ".")) |dot_index| {
        // Don't count hidden files starting with '.' as having an extension
        if (dot_index == 0) {
            return "";
        }
        return filename[dot_index..];
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

    // Default categorization if no config or extension not found
    if (std.mem.eql(u8, extension, ".zig") or std.mem.eql(u8, extension, ".c") or std.mem.eql(u8, extension, ".cpp")) {
        return "Code";
    } else if (std.mem.eql(u8, extension, ".md") or std.mem.eql(u8, extension, ".txt")) {
        return "Documents";
    } else if (std.mem.eql(u8, extension, ".jpg") or std.mem.eql(u8, extension, ".png")) {
        return "Images";
    }

    return "Other";
}

fn listFiles(allocator: std.mem.Allocator, dir_path: []const u8, config: *const Config) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var files = std.ArrayList(FileInfo).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (files.items) |file| {
            allocator.free(file.name);
            allocator.free(file.extension);
        }
        files.deinit(allocator);
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

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip directories, only process files
        if (entry.kind == .file) {
            const name = try allocator.dupe(u8, entry.name);
            const ext_str = getFileExtension(entry.name);
            const extension = try allocator.dupe(u8, ext_str);

            try files.append(allocator, FileInfo{
                .name = name,
                .extension = extension,
            });

            // Count extensions
            const ext_key = if (extension.len > 0) extension else "(no extension)";
            const ext_key_copy = try allocator.dupe(u8, ext_key);

            if (extension_counts.get(ext_key_copy)) |count| {
                try extension_counts.put(ext_key_copy, count + 1);
                allocator.free(ext_key_copy);
            } else {
                try extension_counts.put(ext_key_copy, 1);
            }

            // Count categories
            const category = categorizeExtension(extension, config.data);
            const category_copy = try allocator.dupe(u8, category);

            if (category_counts.get(category_copy)) |count| {
                try category_counts.put(category_copy, count + 1);
                allocator.free(category_copy);
            } else {
                try category_counts.put(category_copy, 1);
            }
        }
    }

    // Display results
    if (files.items.len == 0) {
        print("No files found in directory.\n", .{});
        return;
    }

    print("\nDiscovered files:\n", .{});
    print("-----------------\n", .{});

    for (files.items) |file| {
        print("  {s}\n", .{file.name});
    }

    print("\nSummary:\n", .{});
    print("--------\n", .{});
    print("Total files: {}\n", .{files.items.len});

    if (category_counts.count() > 0) {
        print("\nFile categories breakdown:\n", .{});
        var cat_it = category_counts.iterator();
        while (cat_it.next()) |entry| {
            print("  {s}: {} file(s)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    if (extension_counts.count() > 0) {
        print("\nFile extensions breakdown:\n", .{});
        var it = extension_counts.iterator();
        while (it.next()) |entry| {
            print("  {s}: {} file(s)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
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
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            printVersion();
            return;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing config file path after --config");
                std.process.exit(1);
            }
            config.config_file_path = args[i];
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

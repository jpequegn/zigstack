const std = @import("std");
const print = std.debug.print;

const VERSION = "0.1.0";
const PROGRAM_NAME = "zigstack";

const FileInfo = struct {
    name: []const u8,
    extension: []const u8,
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
    \\
    \\Examples:
    \\  {s} /path/to/project
    \\  {s} --help
    \\  {s} --version
    \\
;

fn printUsage(program_name: []const u8) void {
    print(usage_text, .{ program_name, program_name, program_name, program_name });
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

fn listFiles(allocator: std.mem.Allocator, dir_path: []const u8) !void {
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
    defer {
        var it = extension_counts.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        extension_counts.deinit();
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

    // If we get here, directory is valid
    print("Analyzing directory: {s}\n", .{path});

    // List files in the directory
    listFiles(allocator, path) catch |err| {
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

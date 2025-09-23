const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const VERSION = "0.1.0";
const PROGRAM_NAME = "zigstack";

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
    print("Directory exists and is accessible.\n", .{});
}

// Tests
test "basic test" {
    try std.testing.expect(true);
}
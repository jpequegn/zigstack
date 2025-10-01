const std = @import("std");
const config_mod = @import("../core/config.zig");
const command_mod = @import("command.zig");

pub const Config = config_mod.Config;
pub const Command = command_mod.Command;

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

fn organizeExecute(allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void {
    // Check for help flag
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            organizeHelp();
            return;
        }
    }

    // Import the main module to access executeOrganizeCommand
    const main = @import("../main.zig");
    try main.executeOrganizeCommand(allocator, args, config);
}

fn organizeHelp() void {
    std.debug.print("{s}", .{organize_help_text});
}

pub fn getCommand() Command {
    return Command{
        .name = "organize",
        .description = "Organize files by extension, date, size, or duplicates",
        .execute_fn = organizeExecute,
        .help_fn = organizeHelp,
    };
}

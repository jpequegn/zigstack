const std = @import("std");
const config_mod = @import("../core/config.zig");

pub const Config = config_mod.Config;

/// Command interface that all commands must implement
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    execute_fn: *const fn (allocator: std.mem.Allocator, args: []const []const u8, config: *Config) anyerror!void,
    help_fn: *const fn () void,

    pub fn execute(self: Command, allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void {
        try self.execute_fn(allocator, args, config);
    }

    pub fn printHelp(self: Command) void {
        self.help_fn();
    }
};

/// CommandRegistry manages available commands
pub const CommandRegistry = struct {
    commands: std.StringHashMap(Command),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandRegistry {
        return CommandRegistry{
            .commands = std.StringHashMap(Command).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CommandRegistry) void {
        self.commands.deinit();
    }

    pub fn register(self: *CommandRegistry, command: Command) !void {
        try self.commands.put(command.name, command);
    }

    pub fn get(self: *CommandRegistry, name: []const u8) ?Command {
        return self.commands.get(name);
    }

    pub fn has(self: *CommandRegistry, name: []const u8) bool {
        return self.commands.contains(name);
    }

    pub fn listCommands(self: *CommandRegistry) ![]const []const u8 {
        var list = std.ArrayList([]const u8).init(self.allocator);
        defer list.deinit();

        var iterator = self.commands.iterator();
        while (iterator.next()) |entry| {
            try list.append(entry.key_ptr.*);
        }

        return try list.toOwnedSlice();
    }

    pub fn printAllHelp(self: *CommandRegistry) void {
        std.debug.print("\nAvailable commands:\n\n", .{});

        var iterator = self.commands.iterator();
        while (iterator.next()) |entry| {
            const cmd = entry.value_ptr.*;
            std.debug.print("  {s:<12} - {s}\n", .{ cmd.name, cmd.description });
        }

        std.debug.print("\nUse 'zigstack <command> --help' for more information about a command.\n", .{});
    }
};

/// Parse command line arguments to extract command and its arguments
pub const CommandParser = struct {
    pub const ParseResult = struct {
        command_name: ?[]const u8,
        command_args: []const []const u8,
        is_path: bool, // true if first arg looks like a path (for backward compatibility)
    };

    pub fn parse(_: std.mem.Allocator, args: []const []const u8) !ParseResult {
        if (args.len == 0) {
            return ParseResult{
                .command_name = null,
                .command_args = &[_][]const u8{},
                .is_path = false,
            };
        }

        const first_arg = args[0];

        // Check if first argument is a flag (starts with -)
        if (first_arg.len > 0 and first_arg[0] == '-') {
            // It's a flag, no command specified (backward compatibility)
            return ParseResult{
                .command_name = null,
                .command_args = args,
                .is_path = false,
            };
        }

        // Check if first argument looks like a path (contains /, ., or is a known directory)
        const is_path = std.mem.indexOf(u8, first_arg, "/") != null or
            std.mem.indexOf(u8, first_arg, ".") != null or
            std.mem.eql(u8, first_arg, "~");

        if (is_path) {
            // It's a path, no command specified (backward compatibility)
            return ParseResult{
                .command_name = null,
                .command_args = args,
                .is_path = true,
            };
        }

        // First argument could be a command
        // Return it as the command name with remaining args
        return ParseResult{
            .command_name = first_arg,
            .command_args = if (args.len > 1) args[1..] else &[_][]const u8{},
            .is_path = false,
        };
    }
};

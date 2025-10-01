const std = @import("std");
const testing = std.testing;
const CommandParser = @import("command.zig").CommandParser;
const CommandRegistry = @import("command.zig").CommandRegistry;
const Command = @import("command.zig").Command;
const Config = @import("../core/config.zig").Config;

// Mock command for testing
fn mockExecute(_: std.mem.Allocator, _: []const []const u8, _: *Config) !void {
    // No-op for testing
}

fn mockHelp() void {
    // No-op for testing
}

test "CommandParser detects explicit command" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "organize", "/path/to/dir" };

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name != null);
    try testing.expectEqualStrings("organize", result.command_name.?);
    try testing.expectEqual(@as(usize, 1), result.command_args.len);
    try testing.expectEqualStrings("/path/to/dir", result.command_args[0]);
    try testing.expect(!result.is_path);
}

test "CommandParser detects path as non-command (forward slash)" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "/path/to/dir", "--create" };

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
    try testing.expect(result.is_path);
}

test "CommandParser detects path as non-command (dot)" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "./relative/path", "--move" };

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
    try testing.expect(result.is_path);
}

test "CommandParser detects flag as non-command" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--help" };

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 1), result.command_args.len);
    try testing.expect(!result.is_path);
}

test "CommandParser handles empty args" {
    const allocator = testing.allocator;
    const args = [_][]const u8{};

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 0), result.command_args.len);
    try testing.expect(!result.is_path);
}

test "CommandParser detects command with flags" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "organize", "--create", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name != null);
    try testing.expectEqualStrings("organize", result.command_name.?);
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
}

test "CommandRegistry register and get command" {
    const allocator = testing.allocator;
    var registry = CommandRegistry.init(allocator);
    defer registry.deinit();

    const cmd = Command{
        .name = "test",
        .description = "Test command",
        .execute_fn = mockExecute,
        .help_fn = mockHelp,
    };

    try registry.register(cmd);

    const retrieved = registry.get("test");
    try testing.expect(retrieved != null);
    try testing.expectEqualStrings("test", retrieved.?.name);
    try testing.expectEqualStrings("Test command", retrieved.?.description);
}

test "CommandRegistry returns null for unknown command" {
    const allocator = testing.allocator;
    var registry = CommandRegistry.init(allocator);
    defer registry.deinit();

    const cmd = registry.get("nonexistent");
    try testing.expect(cmd == null);
}

test "CommandRegistry has() checks for command existence" {
    const allocator = testing.allocator;
    var registry = CommandRegistry.init(allocator);
    defer registry.deinit();

    const cmd = Command{
        .name = "test",
        .description = "Test command",
        .execute_fn = mockExecute,
        .help_fn = mockHelp,
    };

    try registry.register(cmd);

    try testing.expect(registry.has("test"));
    try testing.expect(!registry.has("nonexistent"));
}

test "Command execute calls execute_fn" {
    const allocator = testing.allocator;
    var config = Config{};
    const args = [_][]const u8{};

    const cmd = Command{
        .name = "test",
        .description = "Test command",
        .execute_fn = mockExecute,
        .help_fn = mockHelp,
    };

    // Should not error
    try cmd.execute(allocator, &args, &config);
}

test "CommandParser detects current directory" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ ".", "--verbose" };

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
    try testing.expect(result.is_path);
}

test "CommandParser detects tilde home directory" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "~", "--move" };

    const result = try CommandParser.parse(allocator, &args);

    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
    try testing.expect(result.is_path);
}

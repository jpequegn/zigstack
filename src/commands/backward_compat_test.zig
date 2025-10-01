const std = @import("std");
const testing = std.testing;
const CommandParser = @import("command.zig").CommandParser;

// Comprehensive backward compatibility tests for v0.2.0 CLI patterns
// These tests ensure all existing usage patterns continue to work

test "backward compat: zigstack /path/to/dir" {
    const allocator = testing.allocator;
    const args = [_][]const u8{"/path/to/dir"};

    const result = try CommandParser.parse(allocator, &args);

    // Should be treated as path, not command
    try testing.expect(result.command_name == null);
    try testing.expect(result.is_path);
    try testing.expectEqual(@as(usize, 1), result.command_args.len);
    try testing.expectEqualStrings("/path/to/dir", result.command_args[0]);
}

test "backward compat: zigstack --move /path/to/dir" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--move", "/path/to/dir" };

    const result = try CommandParser.parse(allocator, &args);

    // Should detect flag first, treat as no command
    try testing.expect(result.command_name == null);
    try testing.expect(!result.is_path); // First arg is flag, not path
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
    try testing.expectEqualStrings("--move", result.command_args[0]);
    try testing.expectEqualStrings("/path/to/dir", result.command_args[1]);
}

test "backward compat: zigstack --by-date --move /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--by-date", "--move", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Multiple flags before path - should work
    try testing.expect(result.command_name == null);
    try testing.expect(!result.is_path); // First arg is flag
    try testing.expectEqual(@as(usize, 3), result.command_args.len);
}

test "backward compat: zigstack --verbose --dry-run /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--verbose", "--dry-run", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Multiple flags with path
    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 3), result.command_args.len);
    try testing.expectEqualStrings("--verbose", result.command_args[0]);
}

test "backward compat: zigstack ./relative/path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{"./relative/path"};

    const result = try CommandParser.parse(allocator, &args);

    // Relative path starting with ./
    try testing.expect(result.command_name == null);
    try testing.expect(result.is_path);
    try testing.expectEqual(@as(usize, 1), result.command_args.len);
}

test "backward compat: zigstack ../parent/path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{"../parent/path"};

    const result = try CommandParser.parse(allocator, &args);

    // Relative path with ..
    try testing.expect(result.command_name == null);
    try testing.expect(result.is_path);
    try testing.expectEqual(@as(usize, 1), result.command_args.len);
}

test "backward compat: zigstack . --create" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ ".", "--create" };

    const result = try CommandParser.parse(allocator, &args);

    // Current directory with flag
    try testing.expect(result.command_name == null);
    try testing.expect(result.is_path);
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
}

test "backward compat: zigstack ~ " {
    const allocator = testing.allocator;
    const args = [_][]const u8{"~"};

    const result = try CommandParser.parse(allocator, &args);

    // Home directory
    try testing.expect(result.command_name == null);
    try testing.expect(result.is_path);
    try testing.expectEqual(@as(usize, 1), result.command_args.len);
}

test "backward compat: zigstack -c /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "-c", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Short flag before path
    try testing.expect(result.command_name == null);
    try testing.expect(!result.is_path); // Flag is first
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
}

test "backward compat: zigstack -m -V /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "-m", "-V", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Multiple short flags
    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 3), result.command_args.len);
}

test "backward compat: zigstack --config custom.json /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--config", "custom.json", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Flag with value before path
    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 3), result.command_args.len);
}

test "backward compat: zigstack --by-date --date-format year-month /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--by-date", "--date-format", "year-month", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Advanced options
    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 4), result.command_args.len);
}

test "backward compat: zigstack --recursive --max-depth 5 /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--recursive", "--max-depth", "5", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Recursive with depth limit
    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 4), result.command_args.len);
}

test "backward compat: zigstack --by-size --size-threshold 100 /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--by-size", "--size-threshold", "100", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Size-based organization
    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 4), result.command_args.len);
}

test "backward compat: zigstack --detect-dups --dup-action rename /path" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "--detect-dups", "--dup-action", "rename", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Duplicate detection
    try testing.expect(result.command_name == null);
    try testing.expectEqual(@as(usize, 4), result.command_args.len);
}

// Edge case tests for command vs path disambiguation

test "disambiguation: path with dots in filename" {
    const allocator = testing.allocator;
    const args = [_][]const u8{"file.with.dots.txt"};

    const result = try CommandParser.parse(allocator, &args);

    // Should be treated as path due to dots
    try testing.expect(result.command_name == null);
    try testing.expect(result.is_path);
}

test "disambiguation: simple directory name without special chars" {
    const allocator = testing.allocator;
    const args = [_][]const u8{"myproject"};

    const result = try CommandParser.parse(allocator, &args);

    // Could be command or simple directory name
    // Current implementation treats as command (no /, ., or ~)
    try testing.expect(result.command_name != null);
    try testing.expectEqualStrings("myproject", result.command_name.?);
    try testing.expect(!result.is_path);
}

test "disambiguation: organize command explicitly" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "organize", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Explicit command usage
    try testing.expect(result.command_name != null);
    try testing.expectEqualStrings("organize", result.command_name.?);
    try testing.expect(!result.is_path);
    try testing.expectEqual(@as(usize, 1), result.command_args.len);
}

test "disambiguation: organize command with flags" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "organize", "--create", "/path" };

    const result = try CommandParser.parse(allocator, &args);

    // Explicit command with flags
    try testing.expect(result.command_name != null);
    try testing.expectEqualStrings("organize", result.command_name.?);
    try testing.expectEqual(@as(usize, 2), result.command_args.len);
}

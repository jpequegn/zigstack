const std = @import("std");
const testing = std.testing;
const utils = @import("utils.zig");
const config_mod = @import("config.zig");

// ============================================================================
// File Extension Tests
// ============================================================================

test "getFileExtension: regular files with extensions" {
    try testing.expectEqualStrings(".txt", utils.getFileExtension("file.txt"));
    try testing.expectEqualStrings(".zig", utils.getFileExtension("main.zig"));
    try testing.expectEqualStrings(".gz", utils.getFileExtension("archive.tar.gz"));
    try testing.expectEqualStrings(".json", utils.getFileExtension("config.json"));
}

test "getFileExtension: files without extensions" {
    try testing.expectEqualStrings("", utils.getFileExtension("README"));
    try testing.expectEqualStrings("", utils.getFileExtension("Makefile"));
    try testing.expectEqualStrings("", utils.getFileExtension("LICENSE"));
}

test "getFileExtension: hidden files" {
    try testing.expectEqualStrings("", utils.getFileExtension(".gitignore"));
    try testing.expectEqualStrings(".txt", utils.getFileExtension(".hidden.txt"));
    try testing.expectEqualStrings(".json", utils.getFileExtension(".vscode.json"));
}

test "getFileExtension: edge cases" {
    try testing.expectEqualStrings("", utils.getFileExtension(""));
    try testing.expectEqualStrings("", utils.getFileExtension("."));
    try testing.expectEqualStrings("", utils.getFileExtension(".."));
    try testing.expectEqualStrings("", utils.getFileExtension("..."));
}

test "getFileExtension: special cases" {
    try testing.expectEqualStrings(".txt", utils.getFileExtension("file.with.dots.txt"));
    try testing.expectEqualStrings(".tar", utils.getFileExtension("archive.tar"));
}

// ============================================================================
// Path Validation Tests
// ============================================================================

test "validateDirectory: current directory exists" {
    // Current directory should always be accessible
    try utils.validateDirectory(".");
}

test "validateDirectory: non-existent directory fails" {
    const result = utils.validateDirectory("/tmp/this_dir_definitely_does_not_exist_zigstack_test_12345");
    try testing.expectError(error.FileNotFound, result);
}

// ============================================================================
// Filename Conflict Resolution Tests
// ============================================================================

test "resolveFilenameConflict: non-existent file returns original path" {
    const allocator = testing.allocator;
    const path = "/tmp/nonexistent_file_zigstack_test_12345.txt";

    const resolved = try utils.resolveFilenameConflict(allocator, path);
    defer allocator.free(resolved);

    try testing.expectEqualStrings(path, resolved);
}

test "resolveFilenameConflict: existing file gets incremented name" {
    const allocator = testing.allocator;

    // Create a temporary file
    const test_path = "/tmp/zigstack_test_conflict.txt";
    const file = try std.fs.cwd().createFile(test_path, .{});
    file.close();
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const resolved = try utils.resolveFilenameConflict(allocator, test_path);
    defer allocator.free(resolved);

    // Should get _1 appended
    try testing.expect(std.mem.indexOf(u8, resolved, "_1.txt") != null);
}

// ============================================================================
// File Stats Tests
// ============================================================================

test "getFileStats: valid file returns stats" {
    // Create a temporary test file
    const test_file = "/tmp/zigstack_stats_test.txt";
    const file = try std.fs.cwd().createFile(test_file, .{});
    try file.writeAll("test content");
    file.close();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const stats = utils.getFileStats(test_file);

    // File should have non-zero size
    try testing.expect(stats.size > 0);
    // Timestamps should be reasonable (not zero, not too far in the past/future)
    try testing.expect(stats.modified_time > 0);
}

test "getFileStats: non-existent file returns zeros" {
    const stats = utils.getFileStats("/tmp/nonexistent_zigstack_file_12345.txt");

    try testing.expectEqual(@as(u64, 0), stats.size);
    try testing.expectEqual(@as(i64, 0), stats.created_time);
    try testing.expectEqual(@as(i64, 0), stats.modified_time);
}

// ============================================================================
// File Hash Tests
// ============================================================================

test "calculateFileHash: same content produces same hash" {
    const allocator = testing.allocator;
    _ = allocator;

    // Create two files with same content
    const file1 = "/tmp/zigstack_hash_test1.txt";
    const file2 = "/tmp/zigstack_hash_test2.txt";

    const f1 = try std.fs.cwd().createFile(file1, .{});
    try f1.writeAll("identical content");
    f1.close();
    defer std.fs.cwd().deleteFile(file1) catch {};

    const f2 = try std.fs.cwd().createFile(file2, .{});
    try f2.writeAll("identical content");
    f2.close();
    defer std.fs.cwd().deleteFile(file2) catch {};

    const hash1 = try utils.calculateFileHash(file1);
    const hash2 = try utils.calculateFileHash(file2);

    try testing.expect(std.mem.eql(u8, &hash1, &hash2));
}

test "calculateFileHash: different content produces different hash" {
    const allocator = testing.allocator;
    _ = allocator;

    // Create two files with different content
    const file1 = "/tmp/zigstack_hash_diff1.txt";
    const file2 = "/tmp/zigstack_hash_diff2.txt";

    const f1 = try std.fs.cwd().createFile(file1, .{});
    try f1.writeAll("content 1");
    f1.close();
    defer std.fs.cwd().deleteFile(file1) catch {};

    const f2 = try std.fs.cwd().createFile(file2, .{});
    try f2.writeAll("content 2");
    f2.close();
    defer std.fs.cwd().deleteFile(file2) catch {};

    const hash1 = try utils.calculateFileHash(file1);
    const hash2 = try utils.calculateFileHash(file2);

    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "calculateFileHash: non-existent file returns zero hash" {
    const hash = try utils.calculateFileHash("/tmp/nonexistent_zigstack_hash_12345.txt");
    const zero_hash = [_]u8{0} ** 32;

    try testing.expect(std.mem.eql(u8, &hash, &zero_hash));
}

// ============================================================================
// Date Path Formatting Tests
// ============================================================================

test "formatDatePath: year format" {
    const allocator = testing.allocator;

    // Test a specific timestamp: 2024-09-15 (approx)
    const timestamp: i64 = 1726358400; // 2024-09-15 00:00:00 UTC
    const path = try utils.formatDatePath(allocator, timestamp, .year);
    defer allocator.free(path);

    try testing.expectEqualStrings("2024", path);
}

test "formatDatePath: year-month format" {
    const allocator = testing.allocator;

    const timestamp: i64 = 1726358400; // 2024-09-15 00:00:00 UTC
    const path = try utils.formatDatePath(allocator, timestamp, .year_month);
    defer allocator.free(path);

    try testing.expectEqualStrings("2024/09", path);
}

test "formatDatePath: year-month-day format" {
    const allocator = testing.allocator;

    const timestamp: i64 = 1726358400; // 2024-09-15 00:00:00 UTC
    const path = try utils.formatDatePath(allocator, timestamp, .year_month_day);
    defer allocator.free(path);

    // Should be in format YYYY/MM/DD
    try testing.expect(std.mem.indexOf(u8, path, "2024/09/") != null);
}

test "formatDatePath: invalid timestamp returns 'undated'" {
    const allocator = testing.allocator;

    const path = try utils.formatDatePath(allocator, -1, .year);
    defer allocator.free(path);

    try testing.expectEqualStrings("undated", path);
}

test "formatDatePath: zero timestamp returns 'undated'" {
    const allocator = testing.allocator;

    const path = try utils.formatDatePath(allocator, 0, .year);
    defer allocator.free(path);

    try testing.expectEqualStrings("undated", path);
}

// ============================================================================
// Parsing Tests
// ============================================================================

test "parseDateFormat: valid formats" {
    try testing.expectEqual(config_mod.DateFormat.year, utils.parseDateFormat("year"));
    try testing.expectEqual(config_mod.DateFormat.year_month, utils.parseDateFormat("year-month"));
    try testing.expectEqual(config_mod.DateFormat.year_month_day, utils.parseDateFormat("year-month-day"));
}

test "parseDateFormat: invalid format returns null" {
    try testing.expect(utils.parseDateFormat("invalid") == null);
    try testing.expect(utils.parseDateFormat("") == null);
    try testing.expect(utils.parseDateFormat("year-month-day-hour") == null);
}

test "parseDuplicateAction: valid actions" {
    try testing.expectEqual(config_mod.DuplicateAction.skip, utils.parseDuplicateAction("skip"));
    try testing.expectEqual(config_mod.DuplicateAction.rename, utils.parseDuplicateAction("rename"));
    try testing.expectEqual(config_mod.DuplicateAction.replace, utils.parseDuplicateAction("replace"));
    try testing.expectEqual(config_mod.DuplicateAction.keep_both, utils.parseDuplicateAction("keep-both"));
}

test "parseDuplicateAction: invalid action returns null" {
    try testing.expect(utils.parseDuplicateAction("invalid") == null);
    try testing.expect(utils.parseDuplicateAction("") == null);
    try testing.expect(utils.parseDuplicateAction("delete") == null);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration: file extension and conflict resolution" {
    const allocator = testing.allocator;

    const filename = "test.with.dots.txt";
    const ext = utils.getFileExtension(filename);
    try testing.expectEqualStrings(".txt", ext);

    // Create a file to test conflict resolution
    const test_path = "/tmp/zigstack_integration_test.txt";
    const file = try std.fs.cwd().createFile(test_path, .{});
    file.close();
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const resolved = try utils.resolveFilenameConflict(allocator, test_path);
    defer allocator.free(resolved);

    // Should have _1 in the name
    try testing.expect(std.mem.indexOf(u8, resolved, "_1") != null);
}

test "integration: file stats and hash consistency" {
    // Create a file with known content
    const test_file = "/tmp/zigstack_consistency_test.txt";
    const content = "test content for consistency";

    const f = try std.fs.cwd().createFile(test_file, .{});
    try f.writeAll(content);
    f.close();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Get stats
    const stats = utils.getFileStats(test_file);

    // Size should match content length
    try testing.expectEqual(@as(u64, content.len), stats.size);

    // Hash should be consistent across calls
    const hash1 = try utils.calculateFileHash(test_file);
    const hash2 = try utils.calculateFileHash(test_file);
    try testing.expect(std.mem.eql(u8, &hash1, &hash2));
    try testing.expect(std.mem.eql(u8, &stats.hash, &hash1));
}

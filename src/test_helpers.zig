// Test Helper Utilities
// Common test scenarios, fixtures, and utilities for ZigStack testing

const std = @import("std");
const testing = std.testing;
const fs = std.fs;

/// Creates a temporary test directory with a unique name
/// Returns the directory path which must be freed by the caller
pub fn createTempTestDir(allocator: std.mem.Allocator) ![]const u8 {
    const tmp_dir = try std.fs.cwd().openDir("/tmp", .{});
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    const dir_name = try std.fmt.allocPrint(
        allocator,
        "zigstack_test_{x}",
        .{std.fmt.fmtSliceHexLower(&random_bytes)},
    );
    defer allocator.free(dir_name);

    try tmp_dir.makeDir(dir_name);
    return try std.fmt.allocPrint(allocator, "/tmp/{s}", .{dir_name});
}

/// Removes a test directory and all its contents
pub fn removeTempTestDir(path: []const u8) !void {
    try std.fs.cwd().deleteTree(path);
}

/// Creates a test file with specified content in the given directory
pub fn createTestFile(
    dir_path: []const u8,
    filename: []const u8,
    content: []const u8,
) !void {
    const dir = try std.fs.cwd().openDir(dir_path, .{});
    const file = try dir.createFile(filename, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Creates multiple test files with specified extensions
/// extensions is an array of file extensions (e.g., .txt, .jpg)
pub fn createTestFilesWithExtensions(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    extensions: []const []const u8,
) !void {
    for (extensions, 0..) |ext, i| {
        const filename = try std.fmt.allocPrint(
            allocator,
            "test_file_{d}{s}",
            .{ i, ext },
        );
        defer allocator.free(filename);
        try createTestFile(dir_path, filename, "test content");
    }
}

/// Creates a test directory structure with subdirectories
pub fn createTestDirStructure(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    subdirs: []const []const u8,
) !void {
    const dir = try std.fs.cwd().openDir(base_path, .{});
    for (subdirs) |subdir| {
        const full_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ base_path, subdir },
        );
        defer allocator.free(full_path);
        try dir.makeDir(subdir);
    }
}

/// Counts files in a directory with optional extension filter
pub fn countFilesInDir(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    extension: ?[]const u8,
) !usize {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var count: usize = 0;
    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        if (extension) |ext| {
            if (std.mem.endsWith(u8, entry.name, ext)) {
                count += 1;
            }
        } else {
            count += 1;
        }
    }

    _ = allocator; // For API consistency
    return count;
}

/// Checks if a directory exists
pub fn dirExists(dir_path: []const u8) bool {
    const dir = std.fs.cwd().openDir(dir_path, .{}) catch return false;
    dir.close();
    return true;
}

/// Checks if a file exists in a directory
pub fn fileExistsInDir(dir_path: []const u8, filename: []const u8) bool {
    const dir = std.fs.cwd().openDir(dir_path, .{}) catch return false;
    defer dir.close();

    const file = dir.openFile(filename, .{}) catch return false;
    file.close();
    return true;
}

/// Creates test files with specific sizes for size-based testing
pub fn createTestFileWithSize(
    dir_path: []const u8,
    filename: []const u8,
    size_bytes: usize,
) !void {
    const dir = try std.fs.cwd().openDir(dir_path, .{});
    const file = try dir.createFile(filename, .{});
    defer file.close();

    // Write dummy data to reach the specified size
    var buffer: [4096]u8 = undefined;
    @memset(&buffer, 'X');

    var written: usize = 0;
    while (written < size_bytes) {
        const to_write = @min(buffer.len, size_bytes - written);
        try file.writeAll(buffer[0..to_write]);
        written += to_write;
    }
}

/// Test helper to verify file was moved correctly
pub fn verifyFileMoved(
    src_dir: []const u8,
    src_file: []const u8,
    dst_dir: []const u8,
    dst_file: []const u8,
) !void {
    // Source file should not exist
    try testing.expect(!fileExistsInDir(src_dir, src_file));

    // Destination file should exist
    try testing.expect(fileExistsInDir(dst_dir, dst_file));
}

// Test scenario builder for common test patterns
pub const TestScenario = struct {
    allocator: std.mem.Allocator,
    temp_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !TestScenario {
        const temp_dir = try createTempTestDir(allocator);
        return TestScenario{
            .allocator = allocator,
            .temp_dir = temp_dir,
        };
    }

    pub fn deinit(self: *TestScenario) void {
        removeTempTestDir(self.temp_dir) catch {};
        self.allocator.free(self.temp_dir);
    }

    pub fn createFile(self: *TestScenario, filename: []const u8, content: []const u8) !void {
        try createTestFile(self.temp_dir, filename, content);
    }

    pub fn createFiles(self: *TestScenario, extensions: []const []const u8) !void {
        try createTestFilesWithExtensions(self.allocator, self.temp_dir, extensions);
    }

    pub fn createSubdir(self: *TestScenario, subdir: []const u8) !void {
        const subdirs = [_][]const u8{subdir};
        try createTestDirStructure(self.allocator, self.temp_dir, &subdirs);
    }

    pub fn getPath(self: *TestScenario) []const u8 {
        return self.temp_dir;
    }
};

// Basic smoke tests for the helper utilities
test "createTempTestDir creates unique directory" {
    const allocator = testing.allocator;
    const dir1 = try createTempTestDir(allocator);
    defer allocator.free(dir1);
    defer removeTempTestDir(dir1) catch {};

    const dir2 = try createTempTestDir(allocator);
    defer allocator.free(dir2);
    defer removeTempTestDir(dir2) catch {};

    // Directories should be different
    try testing.expect(!std.mem.eql(u8, dir1, dir2));

    // Both should exist
    try testing.expect(dirExists(dir1));
    try testing.expect(dirExists(dir2));
}

test "createTestFile creates file with content" {
    const allocator = testing.allocator;
    const dir = try createTempTestDir(allocator);
    defer allocator.free(dir);
    defer removeTempTestDir(dir) catch {};

    try createTestFile(dir, "test.txt", "hello world");

    try testing.expect(fileExistsInDir(dir, "test.txt"));
}

test "TestScenario helper workflow" {
    const allocator = testing.allocator;
    var scenario = try TestScenario.init(allocator);
    defer scenario.deinit();

    try scenario.createFile("test.txt", "content");
    try testing.expect(fileExistsInDir(scenario.getPath(), "test.txt"));

    const extensions = [_][]const u8{ ".jpg", ".png", ".txt" };
    try scenario.createFiles(&extensions);

    const count = try countFilesInDir(allocator, scenario.getPath(), null);
    try testing.expectEqual(@as(usize, 4), count); // 1 + 3 files
}

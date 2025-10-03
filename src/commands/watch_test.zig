const std = @import("std");
const testing = std.testing;
const watch_cmd = @import("watch.zig");
const config_mod = @import("../core/config.zig");

const Config = config_mod.Config;

test "watch command - basic structure" {
    const cmd = watch_cmd.getCommand();
    try testing.expectEqualStrings("watch", cmd.name);
    try testing.expect(cmd.description.len > 0);
}

test "watch command - help text" {
    // Test that help can be called without errors
    const cmd = watch_cmd.getCommand();
    cmd.printHelp();
}

test "watch state - init and deinit" {
    const allocator = testing.allocator;

    var state = watch_cmd.WatchState.init(allocator);
    defer state.deinit();

    try testing.expect(state.files.count() == 0);
}

test "watch config - default values" {
    const config = watch_cmd.WatchConfig{};

    try testing.expectEqual(@as(u64, 5), config.interval_seconds);
    try testing.expectEqual(@as(?[]const u8, null), config.log_file_path);
    try testing.expectEqual(@as(?[]const u8, null), config.pid_file_path);
    try testing.expectEqual(false, config.daemon);
    try testing.expectEqual(false, config.verbose);
}

test "watch state - log file operations" {
    const allocator = testing.allocator;

    var state = watch_cmd.WatchState.init(allocator);
    defer state.deinit();

    // Create a temporary log file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const log_path = try tmp_dir.dir.realpath(".", &path_buf);
    const log_file = try std.fmt.allocPrint(allocator, "{s}/test.log", .{log_path});
    defer allocator.free(log_file);

    try state.openLogFile(log_file);

    // Test logging
    try state.log("Test message: {s}", .{"hello"}, false);

    // Verify log file was created
    const file = try std.fs.cwd().openFile(log_file, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(contents);

    try testing.expect(std.mem.indexOf(u8, contents, "Test message: hello") != null);
}

test "watch state - file tracking" {
    const allocator = testing.allocator;

    var state = watch_cmd.WatchState.init(allocator);
    defer state.deinit();

    // Add a file to state
    const path = try allocator.dupe(u8, "/tmp/test.txt");
    const file_state = watch_cmd.FileState{
        .path = try allocator.dupe(u8, "/tmp/test.txt"),
        .size = 1024,
        .mtime = 12345,
    };

    try state.files.put(path, file_state);

    try testing.expectEqual(@as(usize, 1), state.files.count());

    const retrieved = state.files.get("/tmp/test.txt").?;
    try testing.expectEqual(@as(u64, 1024), retrieved.size);
    try testing.expectEqual(@as(i64, 12345), retrieved.mtime);
}

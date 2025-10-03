const std = @import("std");
const testing = std.testing;
const workspace = @import("workspace.zig");

const ProjectType = workspace.ProjectType;
const ProjectInfo = workspace.ProjectInfo;
const WorkspaceStats = workspace.WorkspaceStats;

test "ProjectType - toString" {
    try testing.expectEqualStrings("Node.js", ProjectType.nodejs.toString());
    try testing.expectEqualStrings("Python", ProjectType.python.toString());
    try testing.expectEqualStrings("Rust", ProjectType.rust.toString());
    try testing.expectEqualStrings("Zig", ProjectType.zig.toString());
    try testing.expectEqualStrings("Go", ProjectType.go_lang.toString());
    try testing.expectEqualStrings("Java", ProjectType.java.toString());
    try testing.expectEqualStrings("Unknown", ProjectType.unknown.toString());
}

test "WorkspaceStats - init and deinit" {
    const allocator = testing.allocator;

    var stats = WorkspaceStats.init(allocator);
    defer stats.deinit();

    try testing.expectEqual(@as(usize, 0), stats.total_projects);
    try testing.expectEqual(@as(u64, 0), stats.total_size);
}

test "workspace command - basic structure" {
    const cmd = workspace.getCommand();
    try testing.expectEqualStrings("workspace", cmd.name);
    try testing.expect(cmd.description.len > 0);
}

test "workspace command - help text" {
    const cmd = workspace.getCommand();
    cmd.printHelp();
}

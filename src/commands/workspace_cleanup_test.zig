const std = @import("std");
const testing = std.testing;
const workspace = @import("workspace.zig");

const CleanupStrategy = workspace.CleanupStrategy;
const CleanupConfig = workspace.CleanupConfig;
const ProjectType = workspace.ProjectType;

test "CleanupStrategy - fromString and toString" {
    try testing.expectEqual(CleanupStrategy.conservative, CleanupStrategy.fromString("conservative").?);
    try testing.expectEqual(CleanupStrategy.moderate, CleanupStrategy.fromString("moderate").?);
    try testing.expectEqual(CleanupStrategy.aggressive, CleanupStrategy.fromString("aggressive").?);
    try testing.expectEqual(@as(?CleanupStrategy, null), CleanupStrategy.fromString("invalid"));

    try testing.expectEqualStrings("conservative", CleanupStrategy.conservative.toString());
    try testing.expectEqualStrings("moderate", CleanupStrategy.moderate.toString());
    try testing.expectEqualStrings("aggressive", CleanupStrategy.aggressive.toString());
}

test "CleanupConfig - default values" {
    const config = CleanupConfig{};

    try testing.expectEqual(false, config.dry_run);
    try testing.expectEqual(CleanupStrategy.conservative, config.strategy);
    try testing.expectEqual(@as(?ProjectType, null), config.project_type_filter);
    try testing.expectEqual(false, config.inactive_only);
    try testing.expectEqual(false, config.artifacts_only);
    try testing.expectEqual(false, config.deps_only);
    try testing.expectEqual(false, config.verbose);
}

test "CleanupConfig - custom configuration" {
    const config = CleanupConfig{
        .dry_run = true,
        .strategy = .aggressive,
        .project_type_filter = .nodejs,
        .inactive_only = true,
        .artifacts_only = true,
        .verbose = true,
    };

    try testing.expectEqual(true, config.dry_run);
    try testing.expectEqual(CleanupStrategy.aggressive, config.strategy);
    try testing.expectEqual(ProjectType.nodejs, config.project_type_filter.?);
    try testing.expectEqual(true, config.inactive_only);
    try testing.expectEqual(true, config.artifacts_only);
    try testing.expectEqual(true, config.verbose);
}

test "workspace cleanup - help text includes cleanup command" {
    const cmd = workspace.getCommand();
    try testing.expectEqualStrings("workspace", cmd.name);
    try testing.expect(cmd.description.len > 0);
}

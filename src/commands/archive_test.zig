const std = @import("std");
const testing = std.testing;
const archive = @import("archive.zig");

test "CompressionFormat fromString - none" {
    const format = archive.CompressionFormat.fromString("none");
    try testing.expectEqual(archive.CompressionFormat.none, format.?);
}

test "CompressionFormat fromString - tar.gz" {
    const format = archive.CompressionFormat.fromString("tar.gz");
    try testing.expectEqual(archive.CompressionFormat.targz, format.?);
}

test "CompressionFormat fromString - targz" {
    const format = archive.CompressionFormat.fromString("targz");
    try testing.expectEqual(archive.CompressionFormat.targz, format.?);
}

test "CompressionFormat fromString - invalid" {
    const format = archive.CompressionFormat.fromString("invalid");
    try testing.expectEqual(@as(?archive.CompressionFormat, null), format);
}

test "CompressionFormat toString" {
    try testing.expectEqualStrings("none", archive.CompressionFormat.none.toString());
    try testing.expectEqualStrings("tar.gz", archive.CompressionFormat.targz.toString());
}

test "CompressionFormat extension" {
    try testing.expectEqualStrings("", archive.CompressionFormat.none.extension());
    try testing.expectEqualStrings(".tar.gz", archive.CompressionFormat.targz.extension());
}

test "Duration parsing - days" {
    const duration = try archive.Duration.parse("7d");
    try testing.expectEqual(@as(i64, 7 * 24 * 60 * 60), duration.seconds);
}

test "Duration parsing - months" {
    const duration = try archive.Duration.parse("6mo");
    try testing.expectEqual(@as(i64, 6 * 30 * 24 * 60 * 60), duration.seconds);
}

test "Duration parsing - years" {
    const duration = try archive.Duration.parse("1y");
    try testing.expectEqual(@as(i64, 365 * 24 * 60 * 60), duration.seconds);
}

test "Duration parsing - single day" {
    const duration = try archive.Duration.parse("1d");
    try testing.expectEqual(@as(i64, 24 * 60 * 60), duration.seconds);
}

test "Duration parsing - large numbers" {
    const duration = try archive.Duration.parse("30d");
    try testing.expectEqual(@as(i64, 30 * 24 * 60 * 60), duration.seconds);
}

test "Duration parsing - invalid format" {
    const result = archive.Duration.parse("invalid");
    try testing.expectError(error.InvalidDuration, result);
}

test "Duration parsing - empty string" {
    const result = archive.Duration.parse("");
    try testing.expectError(error.InvalidDuration, result);
}

test "Duration parsing - no number" {
    const result = archive.Duration.parse("d");
    try testing.expectError(error.InvalidDuration, result);
}

test "Duration parsing - invalid unit" {
    const result = archive.Duration.parse("7w");
    try testing.expectError(error.InvalidDuration, result);
}

test "Duration getThresholdTimestamp" {
    const duration = try archive.Duration.parse("1d");
    const now = std.time.timestamp();
    const threshold = duration.getThresholdTimestamp();

    // Threshold should be approximately 1 day ago
    const expected_threshold = now - (24 * 60 * 60);
    const diff = if (threshold > expected_threshold)
        threshold - expected_threshold
    else
        expected_threshold - threshold;

    // Allow for 1 second of test execution time
    try testing.expect(diff <= 1);
}

test "ArchiveConfig initialization" {
    const config = archive.ArchiveConfig.init();

    try testing.expectEqualStrings("", config.directory);
    try testing.expectEqualStrings("", config.dest_path);
    try testing.expectEqual(@as(?archive.Duration, null), config.older_than);
    try testing.expectEqual(false, config.preserve_structure);
    try testing.expectEqual(false, config.move_files);
    try testing.expectEqual(@as(?[]const []const u8, null), config.categories);
    try testing.expectEqual(@as(?u64, null), config.min_size_mb);
    try testing.expectEqual(true, config.dry_run);
    try testing.expectEqual(false, config.verbose);
}

test "ArchiveStats initialization and cleanup" {
    const allocator = testing.allocator;
    var stats = archive.ArchiveStats.init(allocator);
    defer stats.deinit();

    try testing.expectEqual(@as(usize, 0), stats.total_files);
    try testing.expectEqual(@as(usize, 0), stats.archived_files);
    try testing.expectEqual(@as(u64, 0), stats.total_size);
    try testing.expectEqual(@as(u64, 0), stats.archived_size);
    try testing.expectEqual(@as(usize, 0), stats.categories.count());
}

test "categorizeFileByExtension - documents" {
    try testing.expectEqual(archive.FileCategory.Documents, archive.categorizeFileByExtension(".txt"));
    try testing.expectEqual(archive.FileCategory.Documents, archive.categorizeFileByExtension(".pdf"));
    try testing.expectEqual(archive.FileCategory.Documents, archive.categorizeFileByExtension(".md"));
    try testing.expectEqual(archive.FileCategory.Documents, archive.categorizeFileByExtension(".doc"));
    try testing.expectEqual(archive.FileCategory.Documents, archive.categorizeFileByExtension(".docx"));
}

test "categorizeFileByExtension - images" {
    try testing.expectEqual(archive.FileCategory.Images, archive.categorizeFileByExtension(".jpg"));
    try testing.expectEqual(archive.FileCategory.Images, archive.categorizeFileByExtension(".jpeg"));
    try testing.expectEqual(archive.FileCategory.Images, archive.categorizeFileByExtension(".png"));
    try testing.expectEqual(archive.FileCategory.Images, archive.categorizeFileByExtension(".gif"));
    try testing.expectEqual(archive.FileCategory.Images, archive.categorizeFileByExtension(".webp"));
}

test "categorizeFileByExtension - videos" {
    try testing.expectEqual(archive.FileCategory.Videos, archive.categorizeFileByExtension(".mp4"));
    try testing.expectEqual(archive.FileCategory.Videos, archive.categorizeFileByExtension(".avi"));
    try testing.expectEqual(archive.FileCategory.Videos, archive.categorizeFileByExtension(".mkv"));
    try testing.expectEqual(archive.FileCategory.Videos, archive.categorizeFileByExtension(".mov"));
}

test "categorizeFileByExtension - audio" {
    try testing.expectEqual(archive.FileCategory.Audio, archive.categorizeFileByExtension(".mp3"));
    try testing.expectEqual(archive.FileCategory.Audio, archive.categorizeFileByExtension(".wav"));
    try testing.expectEqual(archive.FileCategory.Audio, archive.categorizeFileByExtension(".flac"));
}

test "categorizeFileByExtension - archives" {
    try testing.expectEqual(archive.FileCategory.Archives, archive.categorizeFileByExtension(".zip"));
    try testing.expectEqual(archive.FileCategory.Archives, archive.categorizeFileByExtension(".tar"));
    try testing.expectEqual(archive.FileCategory.Archives, archive.categorizeFileByExtension(".gz"));
    try testing.expectEqual(archive.FileCategory.Archives, archive.categorizeFileByExtension(".rar"));
}

test "categorizeFileByExtension - code" {
    try testing.expectEqual(archive.FileCategory.Code, archive.categorizeFileByExtension(".c"));
    try testing.expectEqual(archive.FileCategory.Code, archive.categorizeFileByExtension(".cpp"));
    try testing.expectEqual(archive.FileCategory.Code, archive.categorizeFileByExtension(".py"));
    try testing.expectEqual(archive.FileCategory.Code, archive.categorizeFileByExtension(".js"));
    try testing.expectEqual(archive.FileCategory.Code, archive.categorizeFileByExtension(".zig"));
}

test "categorizeFileByExtension - data" {
    try testing.expectEqual(archive.FileCategory.Data, archive.categorizeFileByExtension(".json"));
    try testing.expectEqual(archive.FileCategory.Data, archive.categorizeFileByExtension(".xml"));
    try testing.expectEqual(archive.FileCategory.Data, archive.categorizeFileByExtension(".csv"));
}

test "categorizeFileByExtension - configuration" {
    try testing.expectEqual(archive.FileCategory.Configuration, archive.categorizeFileByExtension(".ini"));
    try testing.expectEqual(archive.FileCategory.Configuration, archive.categorizeFileByExtension(".cfg"));
    try testing.expectEqual(archive.FileCategory.Configuration, archive.categorizeFileByExtension(".yaml"));
    try testing.expectEqual(archive.FileCategory.Configuration, archive.categorizeFileByExtension(".yml"));
}

test "categorizeFileByExtension - case insensitive" {
    try testing.expectEqual(archive.FileCategory.Documents, archive.categorizeFileByExtension(".TXT"));
    try testing.expectEqual(archive.FileCategory.Documents, archive.categorizeFileByExtension(".PDF"));
    try testing.expectEqual(archive.FileCategory.Images, archive.categorizeFileByExtension(".JPG"));
    try testing.expectEqual(archive.FileCategory.Code, archive.categorizeFileByExtension(".ZIG"));
}

test "categorizeFileByExtension - other" {
    try testing.expectEqual(archive.FileCategory.Other, archive.categorizeFileByExtension(".unknown"));
    try testing.expectEqual(archive.FileCategory.Other, archive.categorizeFileByExtension(""));
    try testing.expectEqual(archive.FileCategory.Other, archive.categorizeFileByExtension(".123"));
}

test "integration - duration parsing with various units" {
    // Test different valid durations
    const durations = [_]struct {
        input: []const u8,
        expected_seconds: i64,
    }{
        .{ .input = "1d", .expected_seconds = 86400 },
        .{ .input = "7d", .expected_seconds = 604800 },
        .{ .input = "30d", .expected_seconds = 2592000 },
        .{ .input = "1mo", .expected_seconds = 2592000 },
        .{ .input = "6mo", .expected_seconds = 15552000 },
        .{ .input = "12mo", .expected_seconds = 31104000 },
        .{ .input = "1y", .expected_seconds = 31536000 },
    };

    for (durations) |d| {
        const parsed = try archive.Duration.parse(d.input);
        try testing.expectEqual(d.expected_seconds, parsed.seconds);
    }
}

test "integration - archive config defaults" {
    const config = archive.ArchiveConfig.init();

    // Verify default values match expected behavior
    try testing.expect(config.directory.len == 0);
    try testing.expect(config.dest_path.len == 0);
    try testing.expect(config.older_than == null);
    try testing.expect(!config.preserve_structure);
    try testing.expect(!config.move_files);
    try testing.expect(config.categories == null);
    try testing.expect(config.min_size_mb == null);
    try testing.expect(!config.dry_run);
    try testing.expect(!config.verbose);
    try testing.expectEqual(archive.CompressionFormat.none, config.compress);
    try testing.expectEqual(@as(u8, 6), config.compression_level);
    try testing.expectEqual(@as(?[]const u8, null), config.archive_name);
}

test "ArchiveStats compression ratio" {
    const allocator = testing.allocator;
    var stats = archive.ArchiveStats.init(allocator);
    defer stats.deinit();

    stats.archived_size = 1000;
    stats.compressed_size = 600;

    const ratio = stats.compressionRatio();
    try testing.expectEqual(@as(f64, 0.6), ratio);
}

test "ArchiveStats compression savings" {
    const allocator = testing.allocator;
    var stats = archive.ArchiveStats.init(allocator);
    defer stats.deinit();

    stats.archived_size = 1000;
    stats.compressed_size = 600;

    const savings = stats.compressionSavings();
    try testing.expectEqual(@as(f64, 40.0), savings);
}

test "ArchiveStats compression ratio - zero size" {
    const allocator = testing.allocator;
    var stats = archive.ArchiveStats.init(allocator);
    defer stats.deinit();

    stats.archived_size = 0;
    stats.compressed_size = 0;

    const ratio = stats.compressionRatio();
    try testing.expectEqual(@as(f64, 0.0), ratio);
}

test "ArchiveStats compression savings - zero size" {
    const allocator = testing.allocator;
    var stats = archive.ArchiveStats.init(allocator);
    defer stats.deinit();

    stats.archived_size = 0;
    stats.compressed_size = 0;

    const savings = stats.compressionSavings();
    try testing.expectEqual(@as(f64, 0.0), savings);
}

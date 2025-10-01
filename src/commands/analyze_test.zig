const std = @import("std");
const testing = std.testing;
const analyze = @import("analyze.zig");

test "analyze: categorizeFile" {
    const categorizeFile = @import("analyze.zig").categorizeFile;

    try testing.expectEqual(.Documents, categorizeFile("pdf"));
    try testing.expectEqual(.Documents, categorizeFile("PDF"));
    try testing.expectEqual(.Images, categorizeFile("jpg"));
    try testing.expectEqual(.Images, categorizeFile("PNG"));
    try testing.expectEqual(.Videos, categorizeFile("mp4"));
    try testing.expectEqual(.Audio, categorizeFile("mp3"));
    try testing.expectEqual(.Archives, categorizeFile("zip"));
    try testing.expectEqual(.Code, categorizeFile("zig"));
    try testing.expectEqual(.Code, categorizeFile("py"));
    try testing.expectEqual(.Data, categorizeFile("json"));
    try testing.expectEqual(.Configuration, categorizeFile("yml"));
    try testing.expectEqual(.Other, categorizeFile("xyz"));
    try testing.expectEqual(.Other, categorizeFile(""));
}

test "analyze: formatSize" {
    const allocator = testing.allocator;

    {
        const size = try analyze.formatSize(0);
        defer allocator.free(size);
        try testing.expectEqualStrings("0 B", size);
    }

    {
        const size = try analyze.formatSize(500);
        defer allocator.free(size);
        try testing.expectEqualStrings("500 B", size);
    }

    {
        const size = try analyze.formatSize(1024);
        defer allocator.free(size);
        try testing.expectEqualStrings("1.00 KB", size);
    }

    {
        const size = try analyze.formatSize(1536);
        defer allocator.free(size);
        try testing.expectEqualStrings("1.50 KB", size);
    }

    {
        const size = try analyze.formatSize(1024 * 1024);
        defer allocator.free(size);
        try testing.expectEqualStrings("1.00 MB", size);
    }

    {
        const size = try analyze.formatSize(1024 * 1024 * 1024);
        defer allocator.free(size);
        try testing.expectEqualStrings("1.00 GB", size);
    }
}

test "analyze: command registration" {
    const cmd = analyze.getCommand();

    try testing.expectEqualStrings("analyze", cmd.name);
    try testing.expect(cmd.description.len > 0);
    try testing.expect(cmd.execute_fn != null);
    try testing.expect(cmd.help_fn != null);
}

test "analyze: analyzeDirectory with test data" {
    const allocator = testing.allocator;

    // Create a temporary test directory
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create some test files
    try tmp_dir.dir.writeFile(.{ .sub_path = "test1.txt", .data = "Hello World" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test2.md", .data = "# Markdown" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test3.json", .data = "{}" });

    // Create a subdirectory with more files
    try tmp_dir.dir.makeDir("subdir");
    try tmp_dir.dir.writeFile(.{ .sub_path = "subdir/code.zig", .data = "const x = 42;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "subdir/image.png", .data = "fake png data" });

    // Get the absolute path to the temporary directory
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    // Analyze the directory
    const options = analyze.AnalysisOptions{
        .min_size_mb = 0,
        .max_depth = null,
        .top_n = 10,
        .json_output = false,
        .verbose = false,
    };

    var result = try analyze.analyzeDirectory(allocator, tmp_path, options);
    defer result.deinit();

    // Verify results
    try testing.expect(result.total_files == 5);
    try testing.expect(result.total_size > 0);
    try testing.expect(result.category_stats.len > 0);
    try testing.expect(result.largest_files.len <= 10);
}

test "analyze: max_depth option" {
    const allocator = testing.allocator;

    // Create a temporary test directory with nested structure
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "file1.txt", .data = "root" });
    try tmp_dir.dir.makeDir("level1");
    try tmp_dir.dir.writeFile(.{ .sub_path = "level1/file2.txt", .data = "level1" });
    try tmp_dir.dir.makeDir("level1/level2");
    try tmp_dir.dir.writeFile(.{ .sub_path = "level1/level2/file3.txt", .data = "level2" });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    // Test with max_depth = 1 (should only see root files)
    {
        const options = analyze.AnalysisOptions{
            .min_size_mb = 0,
            .max_depth = 1,
            .top_n = 10,
            .json_output = false,
            .verbose = false,
        };

        var result = try analyze.analyzeDirectory(allocator, tmp_path, options);
        defer result.deinit();

        try testing.expect(result.total_files == 1); // Only root file
    }

    // Test with max_depth = 2 (should see root + level1)
    {
        const options = analyze.AnalysisOptions{
            .min_size_mb = 0,
            .max_depth = 2,
            .top_n = 10,
            .json_output = false,
            .verbose = false,
        };

        var result = try analyze.analyzeDirectory(allocator, tmp_path, options);
        defer result.deinit();

        try testing.expect(result.total_files == 2); // Root + level1
    }
}

test "analyze: min_size option" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create files of different sizes
    const small_data = "x" ** 100; // 100 bytes
    const large_data = "y" ** (2 * 1024 * 1024); // 2MB

    try tmp_dir.dir.writeFile(.{ .sub_path = "small.txt", .data = small_data });
    try tmp_dir.dir.writeFile(.{ .sub_path = "large.txt", .data = large_data });

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    // Test with min_size = 1 MB (should only see large file)
    const options = analyze.AnalysisOptions{
        .min_size_mb = 1,
        .max_depth = null,
        .top_n = 10,
        .json_output = false,
        .verbose = false,
    };

    var result = try analyze.analyzeDirectory(allocator, tmp_path, options);
    defer result.deinit();

    try testing.expect(result.total_files == 1); // Only large file
    try testing.expect(result.total_size >= 2 * 1024 * 1024);
}

test "analyze: top_n option" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create 10 files
    for (0..10) |i| {
        const filename = try std.fmt.allocPrint(allocator, "file{d}.txt", .{i});
        defer allocator.free(filename);

        const data = try std.fmt.allocPrint(allocator, "Content {d}", .{i});
        defer allocator.free(data);

        try tmp_dir.dir.writeFile(.{ .sub_path = filename, .data = data });
    }

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    // Test with top_n = 3
    const options = analyze.AnalysisOptions{
        .min_size_mb = 0,
        .max_depth = null,
        .top_n = 3,
        .json_output = false,
        .verbose = false,
    };

    var result = try analyze.analyzeDirectory(allocator, tmp_path, options);
    defer result.deinit();

    try testing.expect(result.total_files == 10);
    try testing.expect(result.largest_files.len == 3);
}

test "analyze: compareCategories sorting" {
    const compareCategories = @import("analyze.zig").compareCategories;

    const cat1 = analyze.CategoryStats{
        .category = .Documents,
        .total_size = 1000,
        .file_count = 5,
    };

    const cat2 = analyze.CategoryStats{
        .category = .Code,
        .total_size = 2000,
        .file_count = 3,
    };

    // Should sort by size descending (cat2 > cat1)
    try testing.expect(compareCategories({}, cat1, cat2) == false);
    try testing.expect(compareCategories({}, cat2, cat1) == true);
}

test "analyze: compareFiles sorting" {
    const compareFiles = @import("analyze.zig").compareFiles;

    const file1 = analyze.FileSize{
        .path = "file1.txt",
        .size = 1000,
        .category = .Documents,
    };

    const file2 = analyze.FileSize{
        .path = "file2.txt",
        .size = 2000,
        .category = .Documents,
    };

    // Should sort by size descending (file2 > file1)
    try testing.expect(compareFiles({}, file1, file2) == false);
    try testing.expect(compareFiles({}, file2, file1) == true);
}

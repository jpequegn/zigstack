const std = @import("std");
const organize_cmd = @import("commands/organize.zig");
const analyze_cmd = @import("commands/analyze.zig");
const dedupe_cmd = @import("commands/dedupe.zig");
const utils = @import("core/utils.zig");
const file_info_mod = @import("core/file_info.zig");

const FileInfo = file_info_mod.FileInfo;
const FileCategory = file_info_mod.FileCategory;

/// Performance targets (files per second)
const ORGANIZE_TARGET: f64 = 1000.0;
const ANALYZE_TARGET: f64 = 1000.0;
const ANALYZE_CONTENT_TARGET: f64 = 500.0;
const DEDUPE_TARGET: f64 = 500.0;

/// Benchmark timer for measuring performance
const BenchmarkTimer = struct {
    start_time: i128,

    pub fn start() BenchmarkTimer {
        return .{ .start_time = std.time.nanoTimestamp() };
    }

    pub fn elapsed(self: BenchmarkTimer) u64 {
        const end_time = std.time.nanoTimestamp();
        return @intCast(end_time - self.start_time);
    }

    pub fn elapsedMs(self: BenchmarkTimer) f64 {
        return @as(f64, @floatFromInt(self.elapsed())) / 1_000_000.0;
    }

    pub fn elapsedSec(self: BenchmarkTimer) f64 {
        return @as(f64, @floatFromInt(self.elapsed())) / 1_000_000_000.0;
    }
};

/// Benchmark result tracking
const BenchmarkResult = struct {
    name: []const u8,
    file_count: usize,
    duration_ms: f64,
    files_per_sec: f64,
    target: f64,
    passed: bool,

    pub fn print(self: BenchmarkResult) void {
        const status = if (self.passed) "✓ PASS" else "✗ FAIL";
        const color = if (self.passed) "\x1b[32m" else "\x1b[31m";
        const reset = "\x1b[0m";

        std.debug.print("{s}{s}{s}: {s}\n", .{ color, status, reset, self.name });
        std.debug.print("  Files:      {d}\n", .{self.file_count});
        std.debug.print("  Duration:   {d:.2} ms\n", .{self.duration_ms});
        std.debug.print("  Throughput: {d:.1} files/sec\n", .{self.files_per_sec});
        std.debug.print("  Target:     {d:.1} files/sec\n", .{self.target});
        std.debug.print("  Difference: {s}{d:.1}%{s}\n\n", .{
            if (self.passed) "\x1b[32m" else "\x1b[31m",
            (self.files_per_sec / self.target - 1.0) * 100.0,
            reset,
        });
    }
};

/// Create test files for benchmarking
fn createTestFiles(allocator: std.mem.Allocator, dir_path: []const u8, count: usize) !void {
    var dir = try std.fs.cwd().makeOpenPath(dir_path, .{});
    defer dir.close();

    const extensions = [_][]const u8{ ".txt", ".jpg", ".png", ".pdf", ".mp4", ".zip", ".json", ".py", ".js", ".md" };

    for (0..count) |i| {
        const ext = extensions[i % extensions.len];
        const filename = try std.fmt.allocPrint(allocator, "test_file_{d}{s}", .{ i, ext });
        defer allocator.free(filename);

        const file = try dir.createFile(filename, .{});
        defer file.close();

        // Write some content to make files realistic
        const content = try std.fmt.allocPrint(allocator, "Test content for file {d}\n", .{i});
        defer allocator.free(content);
        try file.writeAll(content);
    }
}

/// Benchmark: File extension extraction
fn benchmarkExtensionExtraction(allocator: std.mem.Allocator) !BenchmarkResult {
    const iterations: usize = 100_000;
    const test_files = [_][]const u8{
        "document.pdf",
        "image.jpg",
        "archive.tar.gz",
        "script.py",
        "data.json",
        "video.mp4",
        "presentation.pptx",
        "spreadsheet.xlsx",
        "code.zig",
        "readme.md",
    };

    const timer = BenchmarkTimer.start();

    for (0..iterations) |_| {
        for (test_files) |filename| {
            const ext = utils.getFileExtension(filename);
            std.mem.doNotOptimizeAway(ext);
        }
    }

    const duration_ms = timer.elapsedMs();
    const total_ops = iterations * test_files.len;
    const ops_per_sec = @as(f64, @floatFromInt(total_ops)) / (duration_ms / 1000.0);

    _ = allocator;

    return BenchmarkResult{
        .name = "Extension Extraction",
        .file_count = total_ops,
        .duration_ms = duration_ms,
        .files_per_sec = ops_per_sec,
        .target = 100_000.0, // Should be very fast
        .passed = ops_per_sec >= 100_000.0,
    };
}

/// Benchmark: File categorization
fn benchmarkCategorization(allocator: std.mem.Allocator) !BenchmarkResult {
    const iterations: usize = 50_000;
    const test_extensions = [_][]const u8{
        ".pdf",
        ".jpg",
        ".tar.gz",
        ".py",
        ".json",
        ".mp4",
        ".pptx",
        ".xlsx",
        ".zig",
        ".md",
    };

    const timer = BenchmarkTimer.start();

    for (0..iterations) |_| {
        for (test_extensions) |ext| {
            const category = organize_cmd.categorizeFileByExtension(ext);
            std.mem.doNotOptimizeAway(category);
        }
    }

    const duration_ms = timer.elapsedMs();
    const total_ops = iterations * test_extensions.len;
    const ops_per_sec = @as(f64, @floatFromInt(total_ops)) / (duration_ms / 1000.0);

    _ = allocator;

    return BenchmarkResult{
        .name = "File Categorization",
        .file_count = total_ops,
        .duration_ms = duration_ms,
        .files_per_sec = ops_per_sec,
        .target = 50_000.0, // Should be very fast
        .passed = ops_per_sec >= 50_000.0,
    };
}

/// Benchmark: File scanning and categorization
fn benchmarkOrganize(allocator: std.mem.Allocator) !BenchmarkResult {
    const test_dir = "/tmp/zigstack_bench_organize";
    const file_count: usize = 1000;

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test directory and files
    try std.fs.cwd().makePath(test_dir);
    try createTestFiles(allocator, test_dir, file_count);

    const timer = BenchmarkTimer.start();

    // Scan directory and categorize files
    var dir = try std.fs.cwd().openDir(test_dir, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    var scanned_count: usize = 0;

    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        const ext = utils.getFileExtension(entry.name);
        const category = organize_cmd.categorizeFileByExtension(ext);
        std.mem.doNotOptimizeAway(category);
        scanned_count += 1;
    }

    const duration_ms = timer.elapsedMs();
    const files_per_sec = @as(f64, @floatFromInt(scanned_count)) / (duration_ms / 1000.0);

    // Clean up
    std.fs.cwd().deleteTree(test_dir) catch {};

    return BenchmarkResult{
        .name = "File Scanning & Categorization",
        .file_count = scanned_count,
        .duration_ms = duration_ms,
        .files_per_sec = files_per_sec,
        .target = ORGANIZE_TARGET,
        .passed = files_per_sec >= ORGANIZE_TARGET,
    };
}

/// Benchmark: File stat retrieval (disk usage analysis)
fn benchmarkAnalyze(allocator: std.mem.Allocator) !BenchmarkResult {
    const test_dir = "/tmp/zigstack_bench_analyze";
    const file_count: usize = 1000;

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test directory and files
    try std.fs.cwd().makePath(test_dir);
    try createTestFiles(allocator, test_dir, file_count);

    const timer = BenchmarkTimer.start();

    // Scan directory and get file stats
    var dir = try std.fs.cwd().openDir(test_dir, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    var scanned_count: usize = 0;
    var total_size: u64 = 0;

    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        const stats = try dir.statFile(entry.name);
        total_size += stats.size;
        scanned_count += 1;
    }

    std.mem.doNotOptimizeAway(total_size);

    const duration_ms = timer.elapsedMs();
    const files_per_sec = @as(f64, @floatFromInt(scanned_count)) / (duration_ms / 1000.0);

    // Clean up
    std.fs.cwd().deleteTree(test_dir) catch {};

    return BenchmarkResult{
        .name = "File Stats Retrieval",
        .file_count = scanned_count,
        .duration_ms = duration_ms,
        .files_per_sec = files_per_sec,
        .target = ANALYZE_TARGET,
        .passed = files_per_sec >= ANALYZE_TARGET,
    };
}

/// Benchmark: Hash calculation for duplicate detection
fn benchmarkHashCalculation(allocator: std.mem.Allocator) !BenchmarkResult {
    const test_dir = "/tmp/zigstack_bench_dedupe";
    const file_count: usize = 500;

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test directory and files
    try std.fs.cwd().makePath(test_dir);
    try createTestFiles(allocator, test_dir, file_count);

    const timer = BenchmarkTimer.start();

    // Calculate hashes for all files
    var dir = try std.fs.cwd().openDir(test_dir, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    var hash_count: usize = 0;

    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ test_dir, entry.name });
        defer allocator.free(path);

        _ = try utils.calculateFileHash(path);
        hash_count += 1;
    }

    const duration_ms = timer.elapsedMs();
    const files_per_sec = @as(f64, @floatFromInt(hash_count)) / (duration_ms / 1000.0);

    // Clean up
    std.fs.cwd().deleteTree(test_dir) catch {};

    return BenchmarkResult{
        .name = "Hash Calculation (Dedupe)",
        .file_count = hash_count,
        .duration_ms = duration_ms,
        .files_per_sec = files_per_sec,
        .target = DEDUPE_TARGET,
        .passed = files_per_sec >= DEDUPE_TARGET,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("ZigStack Performance Benchmarks\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    var results = try std.ArrayList(BenchmarkResult).initCapacity(allocator, 10);
    defer results.deinit(allocator);

    // Run all benchmarks
    std.debug.print("Running benchmarks...\n\n", .{});

    try results.append(allocator, try benchmarkExtensionExtraction(allocator));
    try results.append(allocator, try benchmarkCategorization(allocator));
    try results.append(allocator, try benchmarkOrganize(allocator));
    try results.append(allocator, try benchmarkAnalyze(allocator));
    try results.append(allocator, try benchmarkHashCalculation(allocator));

    // Print results
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("BENCHMARK RESULTS\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    for (results.items) |result| {
        result.print();
        if (result.passed) {
            passed += 1;
        } else {
            failed += 1;
        }
    }

    // Summary
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("SUMMARY\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("Total benchmarks: {d}\n", .{results.items.len});
    std.debug.print("Passed: {d}\n", .{passed});
    std.debug.print("Failed: {d}\n", .{failed});

    if (failed > 0) {
        std.debug.print("\n❌ Some benchmarks did not meet performance targets\n", .{});
        std.process.exit(1);
    } else {
        std.debug.print("\n✅ All benchmarks passed!\n", .{});
    }
}

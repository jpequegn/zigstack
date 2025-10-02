const std = @import("std");
const print = std.debug.print;

// Core module imports
const config_mod = @import("../core/config.zig");
const file_info_mod = @import("../core/file_info.zig");
const utils = @import("../core/utils.zig");
const command_mod = @import("command.zig");
const content_metadata = @import("../core/content_metadata.zig");

// Type exports
pub const Config = config_mod.Config;
pub const FileCategory = file_info_mod.FileCategory;
pub const Command = command_mod.Command;
pub const ContentMetadata = content_metadata.ContentMetadata;

// Utility function shortcuts
const printError = utils.printError;
const printSuccess = utils.printSuccess;
const printInfo = utils.printInfo;
const printWarning = utils.printWarning;
const validateDirectory = utils.validateDirectory;
const getFileExtension = utils.getFileExtension;

const analyze_help_text =
    \\Usage: zigstack analyze [OPTIONS] <directory>
    \\
    \\Analyze disk usage with detailed breakdown by category and visualization.
    \\
    \\Arguments:
    \\  <directory>       Directory path to analyze
    \\
    \\Options:
    \\  -h, --help        Display this help message
    \\  --min-size N      Minimum file size in MB to include (default: 0)
    \\  --max-depth N     Maximum directory depth (default: unlimited)
    \\  --top N           Show top N largest files/directories (default: 10)
    \\  --json            Output results in JSON format
    \\  --content         Enable detailed content analysis (metadata for images, docs, code)
    \\  --recursive       Process directories recursively (default: true)
    \\  -V, --verbose     Enable verbose logging
    \\
    \\Examples:
    \\  zigstack analyze /path/to/directory
    \\  zigstack analyze --top 20 /path
    \\  zigstack analyze --min-size 10 --json /path
    \\  zigstack analyze --max-depth 3 /path
    \\  zigstack analyze --content /path/to/media
    \\
;

// ============================================================================
// Data Structures
// ============================================================================

/// File size information
pub const FileSize = struct {
    path: []const u8,
    size: u64,
    category: FileCategory,
    content_metadata: ?ContentMetadata = null,

    pub fn deinit(self: *FileSize, allocator: std.mem.Allocator) void {
        if (self.content_metadata) |*metadata| {
            metadata.deinit(allocator);
        }
    }
};

/// Category size statistics
pub const CategoryStats = struct {
    category: FileCategory,
    total_size: u64,
    file_count: usize,
};

/// Analysis results
pub const AnalysisResult = struct {
    allocator: std.mem.Allocator,
    total_size: u64,
    total_files: usize,
    category_stats: []CategoryStats,
    largest_files: []FileSize,

    pub fn deinit(self: *AnalysisResult) void {
        // Free category stats
        self.allocator.free(self.category_stats);

        // Free largest files
        for (self.largest_files) |*file| {
            self.allocator.free(file.path);
            if (file.content_metadata) |*metadata| {
                metadata.deinit(self.allocator);
            }
        }
        self.allocator.free(self.largest_files);
    }
};

// ============================================================================
// Size Calculation and Analysis
// ============================================================================

pub fn categorizeFile(extension: []const u8) FileCategory {
    if (extension.len == 0) {
        return .Other;
    }

    // Convert to lowercase for comparison
    var lower_buf: [256]u8 = undefined;
    if (extension.len >= lower_buf.len) {
        return .Other;
    }

    const lower = std.ascii.lowerString(&lower_buf, extension);

    // Documents
    if (std.mem.eql(u8, lower, ".txt") or
        std.mem.eql(u8, lower, ".pdf") or
        std.mem.eql(u8, lower, ".doc") or
        std.mem.eql(u8, lower, ".docx") or
        std.mem.eql(u8, lower, ".md") or
        std.mem.eql(u8, lower, ".odt") or
        std.mem.eql(u8, lower, ".rtf") or
        std.mem.eql(u8, lower, ".tex"))
    {
        return .Documents;
    }

    // Images
    if (std.mem.eql(u8, lower, ".jpg") or
        std.mem.eql(u8, lower, ".jpeg") or
        std.mem.eql(u8, lower, ".png") or
        std.mem.eql(u8, lower, ".gif") or
        std.mem.eql(u8, lower, ".bmp") or
        std.mem.eql(u8, lower, ".svg") or
        std.mem.eql(u8, lower, ".ico") or
        std.mem.eql(u8, lower, ".webp"))
    {
        return .Images;
    }

    // Videos
    if (std.mem.eql(u8, lower, ".mp4") or
        std.mem.eql(u8, lower, ".avi") or
        std.mem.eql(u8, lower, ".mkv") or
        std.mem.eql(u8, lower, ".mov") or
        std.mem.eql(u8, lower, ".wmv") or
        std.mem.eql(u8, lower, ".flv") or
        std.mem.eql(u8, lower, ".webm"))
    {
        return .Videos;
    }

    // Audio
    if (std.mem.eql(u8, lower, ".mp3") or
        std.mem.eql(u8, lower, ".wav") or
        std.mem.eql(u8, lower, ".flac") or
        std.mem.eql(u8, lower, ".aac") or
        std.mem.eql(u8, lower, ".ogg") or
        std.mem.eql(u8, lower, ".wma") or
        std.mem.eql(u8, lower, ".m4a"))
    {
        return .Audio;
    }

    // Archives
    if (std.mem.eql(u8, lower, ".zip") or
        std.mem.eql(u8, lower, ".tar") or
        std.mem.eql(u8, lower, ".gz") or
        std.mem.eql(u8, lower, ".rar") or
        std.mem.eql(u8, lower, ".7z") or
        std.mem.eql(u8, lower, ".bz2") or
        std.mem.eql(u8, lower, ".xz"))
    {
        return .Archives;
    }

    // Code
    if (std.mem.eql(u8, lower, ".zig") or
        std.mem.eql(u8, lower, ".py") or
        std.mem.eql(u8, lower, ".js") or
        std.mem.eql(u8, lower, ".ts") or
        std.mem.eql(u8, lower, ".c") or
        std.mem.eql(u8, lower, ".cpp") or
        std.mem.eql(u8, lower, ".h") or
        std.mem.eql(u8, lower, ".hpp") or
        std.mem.eql(u8, lower, ".java") or
        std.mem.eql(u8, lower, ".cs") or
        std.mem.eql(u8, lower, ".go") or
        std.mem.eql(u8, lower, ".rs") or
        std.mem.eql(u8, lower, ".sh") or
        std.mem.eql(u8, lower, ".bat"))
    {
        return .Code;
    }

    // Data
    if (std.mem.eql(u8, lower, ".json") or
        std.mem.eql(u8, lower, ".xml") or
        std.mem.eql(u8, lower, ".csv") or
        std.mem.eql(u8, lower, ".sql") or
        std.mem.eql(u8, lower, ".db") or
        std.mem.eql(u8, lower, ".sqlite"))
    {
        return .Data;
    }

    // Configuration
    if (std.mem.eql(u8, lower, ".ini") or
        std.mem.eql(u8, lower, ".yaml") or
        std.mem.eql(u8, lower, ".yml") or
        std.mem.eql(u8, lower, ".toml") or
        std.mem.eql(u8, lower, ".cfg") or
        std.mem.eql(u8, lower, ".conf"))
    {
        return .Configuration;
    }

    return .Other;
}

/// Format file size in human-readable format
pub fn formatSize(size: u64) ![]const u8 {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    const TB: u64 = GB * 1024;

    var buf: [64]u8 = undefined;
    const formatted = if (size >= TB)
        try std.fmt.bufPrint(&buf, "{d:.2} TB", .{@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(TB))})
    else if (size >= GB)
        try std.fmt.bufPrint(&buf, "{d:.2} GB", .{@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(GB))})
    else if (size >= MB)
        try std.fmt.bufPrint(&buf, "{d:.2} MB", .{@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(MB))})
    else if (size >= KB)
        try std.fmt.bufPrint(&buf, "{d:.2} KB", .{@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(KB))})
    else
        try std.fmt.bufPrint(&buf, "{d} B", .{size});

    // Return a copy that will be valid
    const allocator = std.heap.page_allocator;
    return try allocator.dupe(u8, formatted);
}

// ============================================================================
// Directory Traversal and Analysis
// ============================================================================

const AnalysisOptions = struct {
    min_size_mb: u64 = 0,
    max_depth: ?u32 = null,
    top_n: usize = 10,
    json_output: bool = false,
    content_analysis: bool = false,
    verbose: bool = false,
};

fn analyzeDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    options: AnalysisOptions,
) !AnalysisResult {
    var category_map = std.AutoHashMap(FileCategory, CategoryStats).init(allocator);
    defer category_map.deinit();

    var all_files = try std.ArrayList(FileSize).initCapacity(allocator, 100);
    defer all_files.deinit(allocator);

    var total_size: u64 = 0;
    var total_files: usize = 0;

    // Initialize category stats
    const all_categories = [_]FileCategory{
        .Documents, .Images,   .Videos,  .Audio,    .Archives,
        .Code,      .Data,     .Configuration, .Other,
    };
    for (all_categories) |cat| {
        try category_map.put(cat, CategoryStats{
            .category = cat,
            .total_size = 0,
            .file_count = 0,
        });
    }

    // Traverse directory
    try traverseDirectory(
        allocator,
        dir_path,
        &category_map,
        &all_files,
        &total_size,
        &total_files,
        options,
        0, // current depth
    );

    // Convert category map to array
    var category_stats = try std.ArrayList(CategoryStats).initCapacity(allocator, 9);
    defer category_stats.deinit(allocator);

    var cat_iter = category_map.iterator();
    while (cat_iter.next()) |entry| {
        if (entry.value_ptr.file_count > 0) {
            try category_stats.append(allocator, entry.value_ptr.*);
        }
    }

    // Sort categories by size (descending)
    const cat_slice = try category_stats.toOwnedSlice(allocator);
    std.sort.pdq(CategoryStats, cat_slice, {}, compareCategories);

    // Sort files by size and take top N
    const all_files_slice = try all_files.toOwnedSlice(allocator);
    std.sort.pdq(FileSize, all_files_slice, {}, compareFiles);

    const top_n = @min(options.top_n, all_files_slice.len);
    var largest_files = try allocator.alloc(FileSize, top_n);

    // Transfer ownership of top N files (no duplication needed)
    for (0..top_n) |i| {
        largest_files[i] = all_files_slice[i];
    }

    // Free paths for files not in top N
    for (top_n..all_files_slice.len) |i| {
        allocator.free(all_files_slice[i].path);
    }
    allocator.free(all_files_slice);

    return AnalysisResult{
        .allocator = allocator,
        .total_size = total_size,
        .total_files = total_files,
        .category_stats = cat_slice,
        .largest_files = largest_files,
    };
}

fn traverseDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    category_map: *std.AutoHashMap(FileCategory, CategoryStats),
    all_files: *std.ArrayList(FileSize),
    total_size: *u64,
    total_files: *usize,
    options: AnalysisOptions,
    depth: u32,
) !void {
    // Check max depth
    if (options.max_depth) |max_depth| {
        if (depth >= max_depth) return;
    }

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (options.verbose) {
            printWarning("Cannot access directory:");
            print(" {s}\n", .{dir_path});
        }
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            // Recurse into subdirectories
            const subdir_path = try std.mem.join(allocator, "/", &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(subdir_path);

            try traverseDirectory(
                allocator,
                subdir_path,
                category_map,
                all_files,
                total_size,
                total_files,
                options,
                depth + 1,
            );
        } else if (entry.kind == .file) {
            const file_path = try std.mem.join(allocator, "/", &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(file_path);

            // Get file size
            const file = dir.openFile(entry.name, .{}) catch continue;
            defer file.close();

            const stat = file.stat() catch continue;
            const size = stat.size;

            // Apply size filter
            const size_mb = size / (1024 * 1024);
            if (size_mb < options.min_size_mb) continue;

            total_size.* += size;
            total_files.* += 1;

            // Categorize file
            const extension = getFileExtension(entry.name);
            const category = categorizeFile(extension);

            // Update category stats
            if (category_map.getPtr(category)) |stats| {
                stats.total_size += size;
                stats.file_count += 1;
            }

            // Read content metadata if enabled
            var metadata: ?ContentMetadata = null;
            if (options.content_analysis) {
                metadata = content_metadata.readContentMetadata(
                    allocator,
                    file_path,
                    extension,
                    category,
                ) catch blk: {
                    if (options.verbose) {
                        printWarning("Failed to read metadata for:");
                        print(" {s}\n", .{file_path});
                    }
                    break :blk null;
                };
            }

            // Add to all files list
            const file_path_owned = try allocator.dupe(u8, file_path);
            try all_files.append(allocator, FileSize{
                .path = file_path_owned,
                .size = size,
                .category = category,
                .content_metadata = metadata,
            });
        }
    }
}

pub fn compareCategories(_: void, a: CategoryStats, b: CategoryStats) bool {
    return a.total_size > b.total_size;
}

pub fn compareFiles(_: void, a: FileSize, b: FileSize) bool {
    return a.size > b.size;
}

// ============================================================================
// Visualization
// ============================================================================

fn printBarChart(label: []const u8, size: u64, max_size: u64, bar_width: usize) void {
    const percentage = if (max_size > 0)
        @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(max_size))
    else
        0.0;

    const filled = @as(usize, @intFromFloat(percentage * @as(f64, @floatFromInt(bar_width))));

    print("  {s:<15} [", .{label});
    var i: usize = 0;
    while (i < bar_width) : (i += 1) {
        if (i < filled) {
            print("█", .{});
        } else {
            print("░", .{});
        }
    }
    print("] {d:>6.1}%\n", .{percentage * 100.0});
}

fn printContentMetadata(metadata: ContentMetadata) void {
    switch (metadata) {
        .image => |img| {
            print("    📸 {d}x{d} {s} ({d}-bit)\n", .{ img.width, img.height, img.format, img.color_depth });
        },
        .video => |vid| {
            print("    🎬 {d}x{d} {s}/{s} ({d:.1}s)\n", .{ vid.width, vid.height, vid.format, vid.codec, vid.duration_seconds });
        },
        .audio => |aud| {
            print("    🎵 {s} {d}kbps @ {d}Hz ({d:.1}s)\n", .{ aud.format, aud.bitrate / 1000, aud.sample_rate, aud.duration_seconds });
        },
        .document => |doc| {
            if (doc.page_count) |pages| {
                print("    📄 {d} words, {d} lines, {d} pages\n", .{ doc.word_count, doc.line_count, pages });
            } else {
                print("    📄 {d} words, {d} lines\n", .{ doc.word_count, doc.line_count });
            }
        },
        .code => |code| {
            print("    💻 {s}: {d} lines ({d} code, {d} comments, {d} blank)\n", .{
                code.language,
                code.line_count,
                code.code_lines,
                code.comment_lines,
                code.blank_lines,
            });
        },
        .none => {},
    }
}

fn printResults(result: AnalysisResult) !void {
    print("\n", .{});
    print("============================================================\n", .{});
    print("DISK USAGE ANALYSIS\n", .{});
    print("============================================================\n\n", .{});

    // Total summary
    const total_size_str = try formatSize(result.total_size);
    defer std.heap.page_allocator.free(total_size_str);

    print("Total Size: {s}\n", .{total_size_str});
    print("Total Files: {d}\n\n", .{result.total_files});

    // Category breakdown
    print("Size by Category:\n", .{});
    print("----------------------------------------\n", .{});

    const max_category_size = if (result.category_stats.len > 0)
        result.category_stats[0].total_size
    else
        0;

    for (result.category_stats) |stats| {
        const cat_size_str = try formatSize(stats.total_size);
        defer std.heap.page_allocator.free(cat_size_str);

        const cat_name = stats.category.toString();
        print("\n📁 {s} ({d} files, {s})\n", .{ cat_name, stats.file_count, cat_size_str });
        printBarChart(cat_name, stats.total_size, max_category_size, 40);
    }

    // Largest files
    if (result.largest_files.len > 0) {
        print("\n", .{});
        print("Largest Files:\n", .{});
        print("----------------------------------------\n", .{});

        for (result.largest_files, 0..) |file, i| {
            const file_size_str = try formatSize(file.size);
            defer std.heap.page_allocator.free(file_size_str);

            print("{d:>3}. {s:<10} {s}\n", .{ i + 1, file_size_str, file.path });

            // Print content metadata if available
            if (file.content_metadata) |metadata| {
                printContentMetadata(metadata);
            }
        }
    }

    print("\n", .{});
    print("============================================================\n", .{});
}

fn printResultsJson(result: AnalysisResult) !void {
    print("{{", .{});
    print("\"total_size\":{d},", .{result.total_size});
    print("\"total_files\":{d},", .{result.total_files});

    print("\"categories\":[", .{});
    for (result.category_stats, 0..) |stats, i| {
        if (i > 0) print(",", .{});
        print("{{", .{});
        print("\"name\":\"{s}\",", .{stats.category.toString()});
        print("\"size\":{d},", .{stats.total_size});
        print("\"count\":{d}", .{stats.file_count});
        print("}}", .{});
    }
    print("],", .{});

    print("\"largest_files\":[", .{});
    for (result.largest_files, 0..) |file, i| {
        if (i > 0) print(",", .{});
        print("{{", .{});
        print("\"path\":\"{s}\",", .{file.path});
        print("\"size\":{d}", .{file.size});
        print("}}", .{});
    }
    print("]", .{});
    print("}}\n", .{});
}

// ============================================================================
// Command Interface Implementation
// ============================================================================

fn analyzeHelp() void {
    print("{s}", .{analyze_help_text});
}

fn analyzeExecute(allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void {
    if (args.len == 0) {
        printError("Missing required directory argument");
        print("\n", .{});
        analyzeHelp();
        return error.MissingArgument;
    }

    var dir_path: []const u8 = undefined;
    var options = AnalysisOptions{};
    options.verbose = config.verbose;

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            analyzeHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--min-size")) {
            i += 1;
            if (i >= args.len) {
                printError("--min-size requires a value");
                return error.InvalidArgument;
            }
            options.min_size_mb = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--max-depth")) {
            i += 1;
            if (i >= args.len) {
                printError("--max-depth requires a value");
                return error.InvalidArgument;
            }
            options.max_depth = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--top")) {
            i += 1;
            if (i >= args.len) {
                printError("--top requires a value");
                return error.InvalidArgument;
            }
            options.top_n = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--json")) {
            options.json_output = true;
        } else if (std.mem.eql(u8, arg, "--content")) {
            options.content_analysis = true;
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (arg[0] != '-') {
            dir_path = arg;
        }
    }

    // Validate directory exists
    try validateDirectory(dir_path);

    if (!options.json_output) {
        printInfo("Analyzing directory...");
        print("\n", .{});
    }

    // Perform analysis
    var result = try analyzeDirectory(allocator, dir_path, options);
    defer result.deinit();

    // Print results
    if (options.json_output) {
        try printResultsJson(result);
    } else {
        try printResults(result);
    }
}

pub fn getCommand() Command {
    return Command{
        .name = "analyze",
        .description = "Analyze disk usage with detailed breakdown",
        .execute_fn = analyzeExecute,
        .help_fn = analyzeHelp,
    };
}

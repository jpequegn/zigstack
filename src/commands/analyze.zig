const std = @import("std");
const print = std.debug.print;

// Core module imports
const config_mod = @import("../core/config.zig");
const file_info_mod = @import("../core/file_info.zig");
const utils = @import("../core/utils.zig");
const command_mod = @import("command.zig");

// Type exports
pub const Config = config_mod.Config;
pub const FileCategory = file_info_mod.FileCategory;
pub const Command = command_mod.Command;

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
    \\  --recursive       Process directories recursively (default: true)
    \\  -V, --verbose     Enable verbose logging
    \\
    \\Examples:
    \\  zigstack analyze /path/to/directory
    \\  zigstack analyze --top 20 /path
    \\  zigstack analyze --min-size 10 --json /path
    \\  zigstack analyze --max-depth 3 /path
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
        for (self.largest_files) |file| {
            self.allocator.free(file.path);
        }
        self.allocator.free(self.largest_files);
    }
};

// ============================================================================
// Size Calculation and Analysis
// ============================================================================

fn categorizeFile(extension: []const u8) FileCategory {
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
fn formatSize(size: u64) ![]const u8 {
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
// Command Interface Implementation
// ============================================================================

fn analyzeHelp() void {
    print("{s}", .{analyze_help_text});
}

fn analyzeExecute(allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void {
    _ = config; // Will use later for options

    if (args.len == 0) {
        printError("Missing required directory argument");
        print("\n", .{});
        analyzeHelp();
        return error.MissingArgument;
    }

    const dir_path = args[0];

    // Validate directory exists
    try validateDirectory(dir_path);

    printInfo("Analyzing directory...");
    print("\n", .{});

    // TODO: Implement full analysis logic
    _ = allocator;

    printSuccess("Analysis complete!");
}

pub fn getCommand() Command {
    return Command{
        .name = "analyze",
        .description = "Analyze disk usage with detailed breakdown",
        .execute_fn = analyzeExecute,
        .help_fn = analyzeHelp,
    };
}

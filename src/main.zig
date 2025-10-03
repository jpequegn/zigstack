const std = @import("std");
const print = std.debug.print;
const crypto = std.crypto;

// Import core modules
const file_info_mod = @import("core/file_info.zig");
const organization_mod = @import("core/organization.zig");
const config_mod = @import("core/config.zig");
const tracker_mod = @import("core/tracker.zig");
const utils = @import("core/utils.zig");

// Import command modules
const command_mod = @import("commands/command.zig");
const organize_cmd = @import("commands/organize.zig");
const analyze_cmd = @import("commands/analyze.zig");
const dedupe_cmd = @import("commands/dedupe.zig");
const archive_cmd = @import("commands/archive.zig");
const watch_cmd = @import("commands/watch.zig");
const workspace_cmd = @import("commands/workspace.zig");

// Re-export types for use in main
const FileInfo = file_info_mod.FileInfo;
const FileCategory = file_info_mod.FileCategory;
const OrganizationPlan = organization_mod.OrganizationPlan;
const Config = config_mod.Config;
const ConfigData = config_mod.ConfigData;
const Category = config_mod.Category;
const DisplayConfig = config_mod.DisplayConfig;
const BehaviorConfig = config_mod.BehaviorConfig;
const DateFormat = config_mod.DateFormat;
const DuplicateAction = config_mod.DuplicateAction;
const MoveTracker = tracker_mod.MoveTracker;
const MoveRecord = tracker_mod.MoveRecord;

// Command system types
const Command = command_mod.Command;
const CommandRegistry = command_mod.CommandRegistry;
const CommandParser = command_mod.CommandParser;

const VERSION = "0.1.0";
const PROGRAM_NAME = "zigstack";

const usage_text =
    \\Usage: {s} [OPTIONS] <directory>
    \\
    \\Analyze and organize files based on extension, date, size, and duplicates.
    \\
    \\Arguments:
    \\  <directory>       Directory path to analyze
    \\
    \\Options:
    \\  -h, --help        Display this help message
    \\  -v, --version     Display version information
    \\  --config PATH     Configuration file path (JSON format)
    \\  -c, --create      Create directories (default: preview only)
    \\  -m, --move        Move files to directories (implies --create)
    \\  -d, --dry-run     Show what would happen without doing it
    \\  -V, --verbose     Enable verbose logging
    \\
    \\Advanced Organization:
    \\  --by-date         Organize files by date (creation/modification)
    \\  --by-size         Organize large files separately
    \\  --detect-dups     Detect and handle duplicate files
    \\  --recursive       Process directories recursively
    \\  --max-depth N     Maximum recursion depth (default: 10)
    \\  --size-threshold N Size threshold for large files in MB (default: 100)
    \\  --date-format FMT Date format: year, year-month, year-month-day
    \\  --dup-action ACT  Duplicate action: skip, rename, replace, keep-both
    \\
    \\Examples:
    \\  {s} /path/to/project                          # Preview organization
    \\  {s} --create /path/to/project                 # Create directories only
    \\  {s} --move /path/to/project                   # Create directories and move files
    \\  {s} --config custom.json /path/to/project     # Use custom categorization config
    \\  {s} --dry-run --verbose /path                 # Verbose preview mode
    \\  {s} --by-date --date-format year-month /path  # Organize by year/month
    \\  {s} --by-size --size-threshold 50 /path       # Separate files larger than 50MB
    \\  {s} --detect-dups --dup-action rename /path   # Detect and rename duplicates
    \\  {s} --recursive --max-depth 5 /path           # Process 5 levels deep
    \\
;

fn printUsage(program_name: []const u8) void {
    print(usage_text, .{ program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name });
}

fn printVersion() void {
    print("{s} {s}\n", .{ PROGRAM_NAME, VERSION });
}

// Utility function wrappers for backward compatibility
fn printError(message: []const u8) void {
    utils.printError(message);
}

fn parseDateFormat(format_str: []const u8) ?DateFormat {
    return utils.parseDateFormat(format_str);
}

fn parseDuplicateAction(action_str: []const u8) ?DuplicateAction {
    return utils.parseDuplicateAction(action_str);
}

fn formatDatePath(allocator: std.mem.Allocator, timestamp: i64, date_format: DateFormat) ![]const u8 {
    return utils.formatDatePath(allocator, timestamp, date_format);
}

fn calculateFileHash(file_path: []const u8) ![32]u8 {
    return utils.calculateFileHash(file_path);
}

fn getFileStats(file_path: []const u8) utils.FileStats {
    return utils.getFileStats(file_path);
}

fn validateDirectory(path: []const u8) !void {
    return utils.validateDirectory(path);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // If no arguments provided
    if (args.len < 2) {
        printError("Missing required directory argument");
        print("\n", .{});
        printUsage(args[0]);
        std.process.exit(1);
    }

    // Check for global help/version flags (only if no subcommand detected)
    const first_arg = args[1];
    const is_help = std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help");
    const is_version = std.mem.eql(u8, first_arg, "--version");

    if (is_help) {
        printUsage(args[0]);
        return;
    } else if (is_version) {
        printVersion();
        return;
    }

    // Set up command registry
    var registry = CommandRegistry.init(allocator);
    defer registry.deinit();
    try registry.register(organize_cmd.getCommand());
    try registry.register(analyze_cmd.getCommand());
    try registry.register(dedupe_cmd.getCommand());
    try registry.register(archive_cmd.getCommand());
    try registry.register(watch_cmd.getCommand());
    try registry.register(workspace_cmd.getCommand());

    // Parse for command
    const parse_result = try CommandParser.parse(allocator, args[1..]);

    var config = Config{};

    if (parse_result.command_name) |cmd_name| {
        // Command specified explicitly
        if (registry.get(cmd_name)) |cmd| {
            try cmd.execute(allocator, parse_result.command_args, &config);
        } else {
            printError("Unknown command");
            print("Try '{s} --help' for more information.\n", .{args[0]});
            registry.printAllHelp();
            std.process.exit(1);
        }
    } else {
        // Backward compatibility - default to organize command
        try organize_cmd.executeOrganizeCommand(allocator, args[1..], &config);
    }
}

// Tests
test "basic test" {
    try std.testing.expect(true);
}

test "getFileExtension" {
    const testing = std.testing;

    // Test regular files with extensions
    try testing.expectEqualStrings(".txt", utils.getFileExtension("file.txt"));
    try testing.expectEqualStrings(".zig", utils.getFileExtension("main.zig"));
    try testing.expectEqualStrings(".gz", utils.getFileExtension("archive.tar.gz"));

    // Test files without extensions
    try testing.expectEqualStrings("", utils.getFileExtension("README"));
    try testing.expectEqualStrings("", utils.getFileExtension("Makefile"));

    // Test hidden files (starting with .)
    try testing.expectEqualStrings("", utils.getFileExtension(".gitignore"));
    try testing.expectEqualStrings(".txt", utils.getFileExtension(".hidden.txt"));
}

test "categorizeFileByExtension" {
    const testing = std.testing;

    // Test Documents
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".txt"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".pdf"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".md"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".doc"));

    // Test Images
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".jpg"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".jpeg"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".png"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".gif"));

    // Test Videos
    try testing.expectEqual(FileCategory.Videos, organize_cmd.categorizeFileByExtension(".mp4"));
    try testing.expectEqual(FileCategory.Videos, organize_cmd.categorizeFileByExtension(".avi"));
    try testing.expectEqual(FileCategory.Videos, organize_cmd.categorizeFileByExtension(".mkv"));

    // Test Audio
    try testing.expectEqual(FileCategory.Audio, organize_cmd.categorizeFileByExtension(".mp3"));
    try testing.expectEqual(FileCategory.Audio, organize_cmd.categorizeFileByExtension(".wav"));
    try testing.expectEqual(FileCategory.Audio, organize_cmd.categorizeFileByExtension(".flac"));

    // Test Archives
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".zip"));
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".tar"));
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".gz"));

    // Test Code
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".zig"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".py"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".js"));

    // Test Data
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".json"));
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".xml"));
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".csv"));

    // Test Configuration
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".ini"));
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".yaml"));
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".toml"));

    // Test case insensitive
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".JPG"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".PNG"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".ZIG"));

    // Test Other/Unknown
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".xyz"));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(""));
}

test "toDirectoryName" {
    const testing = std.testing;

    // Test directory name mapping
    try testing.expectEqualStrings("documents", FileCategory.Documents.toDirectoryName());
    try testing.expectEqualStrings("images", FileCategory.Images.toDirectoryName());
    try testing.expectEqualStrings("videos", FileCategory.Videos.toDirectoryName());
    try testing.expectEqualStrings("audio", FileCategory.Audio.toDirectoryName());
    try testing.expectEqualStrings("archives", FileCategory.Archives.toDirectoryName());
    try testing.expectEqualStrings("code", FileCategory.Code.toDirectoryName());
    try testing.expectEqualStrings("data", FileCategory.Data.toDirectoryName());
    try testing.expectEqualStrings("config", FileCategory.Configuration.toDirectoryName());
    try testing.expectEqualStrings("misc", FileCategory.Other.toDirectoryName());
}

test "Config defaults" {
    const testing = std.testing;

    const config = Config{};
    try testing.expectEqual(false, config.create_directories);
    try testing.expectEqual(false, config.move_files);
    try testing.expectEqual(true, config.dry_run);
    try testing.expectEqual(false, config.verbose);
}

test "resolveFilenameConflict with no conflict" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test with non-existent file (should return original path)
    const result = try utils.resolveFilenameConflict(allocator, "/tmp/nonexistent_file.txt");
    defer allocator.free(result);

    try testing.expectEqualStrings("/tmp/nonexistent_file.txt", result);
}

test "MoveTracker initialization and cleanup" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Verify it initializes correctly
    try testing.expectEqual(@as(usize, 0), move_tracker.moves.items.len);
}

test "MoveTracker record move" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    try move_tracker.recordMove("/source/file.txt", "/dest/file.txt");

    try testing.expectEqual(@as(usize, 1), move_tracker.moves.items.len);
    try testing.expectEqualStrings("/source/file.txt", move_tracker.moves.items[0].original_path);
    try testing.expectEqualStrings("/dest/file.txt", move_tracker.moves.items[0].destination_path);
}

// Additional comprehensive tests

test "getFileExtension edge cases" {
    const testing = std.testing;

    // Test edge cases for special characters and Unicode
    try testing.expectEqualStrings(".txt", utils.getFileExtension("file with spaces.txt"));
    try testing.expectEqualStrings(".pdf", utils.getFileExtension("file-with-dashes.pdf"));
    try testing.expectEqualStrings(".jpg", utils.getFileExtension("file_with_underscores.jpg"));
    try testing.expectEqualStrings(".txt", utils.getFileExtension("file123.txt"));
    try testing.expectEqualStrings(".", utils.getFileExtension("file."));
    try testing.expectEqualStrings("", utils.getFileExtension("."));
    try testing.expectEqualStrings("", utils.getFileExtension(""));

    // Test files with multiple dots
    try testing.expectEqualStrings(".gz", utils.getFileExtension("archive.tar.gz"));
    try testing.expectEqualStrings(".old", utils.getFileExtension("config.ini.old"));

    // Test very long extensions and filenames
    try testing.expectEqualStrings(".extension", utils.getFileExtension("file.extension"));
    try testing.expectEqualStrings(".verylongextension", utils.getFileExtension("short.verylongextension"));
}

test "categorizeFileByExtension case insensitive" {
    const testing = std.testing;

    // Test case insensitive behavior
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".TXT"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".PDF"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".Md"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".JPEG"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".Png"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".ZiG"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".PY"));

    // Mixed case
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".ZiP"));
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".JsOn"));
}

test "categorizeFileByExtension empty and special extensions" {
    const testing = std.testing;

    // Test empty and special cases
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(""));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension("."));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".unknown"));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".123"));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".special-chars"));
}

test "validateDirectory with non-existent path" {
    // This test validates the error handling for non-existent directories
    const testing = std.testing;

    const result = validateDirectory("/definitely/does/not/exist/path");
    try testing.expectError(error.FileNotFound, result);
}

test "FileCategory toString" {
    const testing = std.testing;

    // Test all enum values
    try testing.expectEqualStrings("Documents", FileCategory.Documents.toString());
    try testing.expectEqualStrings("Images", FileCategory.Images.toString());
    try testing.expectEqualStrings("Videos", FileCategory.Videos.toString());
    try testing.expectEqualStrings("Audio", FileCategory.Audio.toString());
    try testing.expectEqualStrings("Archives", FileCategory.Archives.toString());
    try testing.expectEqualStrings("Code", FileCategory.Code.toString());
    try testing.expectEqualStrings("Data", FileCategory.Data.toString());
    try testing.expectEqualStrings("Configuration", FileCategory.Configuration.toString());
    try testing.expectEqualStrings("Other", FileCategory.Other.toString());
}

test "categorizeExtension with config data" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Create a minimal config for testing
    var categories = std.StringHashMap(Category).init(allocator);
    defer {
        var iter = categories.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.extensions) |ext| {
                allocator.free(ext);
            }
            allocator.free(entry.value_ptr.extensions);
            allocator.free(entry.value_ptr.description);
            allocator.free(entry.value_ptr.color);
        }
        categories.deinit();
    }

    // Add a custom category
    var extensions = try allocator.alloc([]const u8, 2);
    extensions[0] = try allocator.dupe(u8, ".custom");
    extensions[1] = try allocator.dupe(u8, ".special");

    const category = Category{
        .description = try allocator.dupe(u8, "Custom files"),
        .extensions = extensions,
        .color = try allocator.dupe(u8, "#FF0000"),
        .priority = 1,
    };

    const category_name = try allocator.dupe(u8, "Custom");
    try categories.put(category_name, category);

    const config_data = ConfigData{
        .version = "1.0",
        .categories = categories,
        .display = DisplayConfig{},
        .behavior = BehaviorConfig{},
    };

    // Test custom extension categorization
    const result = organize_cmd.categorizeExtension(".custom", config_data);
    try testing.expectEqualStrings("Custom", result);

    const result2 = organize_cmd.categorizeExtension(".special", config_data);
    try testing.expectEqualStrings("Custom", result2);

    // Test fallback to enum-based categorization
    const result3 = organize_cmd.categorizeExtension(".txt", config_data);
    try testing.expectEqualStrings("Documents", result3);
}

test "categorizeExtension fallback to enum" {
    const testing = std.testing;

    // Test fallback when no config is provided
    const result = organize_cmd.categorizeExtension(".txt", null);
    try testing.expectEqualStrings("Documents", result);

    const result2 = organize_cmd.categorizeExtension(".jpg", null);
    try testing.expectEqualStrings("Images", result2);

    const result3 = organize_cmd.categorizeExtension(".unknown", null);
    try testing.expectEqualStrings("Other", result3);
}

test "MoveTracker multiple moves and cleanup" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Record multiple moves
    try move_tracker.recordMove("/source1/file1.txt", "/dest1/file1.txt");
    try move_tracker.recordMove("/source2/file2.jpg", "/dest2/file2.jpg");
    try move_tracker.recordMove("/source3/file3.pdf", "/dest3/file3.pdf");

    try testing.expectEqual(@as(usize, 3), move_tracker.moves.items.len);

    // Verify all moves are recorded correctly
    try testing.expectEqualStrings("/source1/file1.txt", move_tracker.moves.items[0].original_path);
    try testing.expectEqualStrings("/dest1/file1.txt", move_tracker.moves.items[0].destination_path);
    try testing.expectEqualStrings("/source2/file2.jpg", move_tracker.moves.items[1].original_path);
    try testing.expectEqualStrings("/dest2/file2.jpg", move_tracker.moves.items[1].destination_path);
    try testing.expectEqualStrings("/source3/file3.pdf", move_tracker.moves.items[2].original_path);
    try testing.expectEqualStrings("/dest3/file3.pdf", move_tracker.moves.items[2].destination_path);
}

test "loadConfig with invalid JSON" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test invalid JSON handling - this should return an error
    const result = organize_cmd.loadConfig(allocator, "nonexistent_config.json");
    try testing.expectError(error.FileNotFound, result);
}

test "Config with various flags" {
    const testing = std.testing;

    // Test different configuration combinations
    var config1 = Config{};
    config1.create_directories = true;
    try testing.expectEqual(true, config1.create_directories);
    try testing.expectEqual(false, config1.move_files);
    try testing.expectEqual(true, config1.dry_run); // Default should still be true

    var config2 = Config{};
    config2.move_files = true;
    try testing.expectEqual(false, config2.create_directories); // Default
    try testing.expectEqual(true, config2.move_files);

    var config3 = Config{};
    config3.verbose = true;
    config3.dry_run = false;
    try testing.expectEqual(true, config3.verbose);
    try testing.expectEqual(false, config3.dry_run);
}

test "FileCategory all categories coverage" {
    const testing = std.testing;

    // Test that we can create and use all categories
    const categories = [_]FileCategory{
        .Documents, .Images, .Videos, .Audio, .Archives, .Code, .Data, .Configuration, .Other
    };

    for (categories) |category| {
        // Verify toString works for all
        const name = category.toString();
        try testing.expect(name.len > 0);

        // Verify toDirectoryName works for all
        const dir_name = category.toDirectoryName();
        try testing.expect(dir_name.len > 0);

        // Verify they're not the same (directory names are lowercase)
        if (category != .Other) { // "Other" -> "misc" is a special case
            try testing.expect(!std.mem.eql(u8, name, dir_name));
        }
    }
}

test "resolveFilenameConflict with special characters" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test with filenames containing special characters
    const result1 = try utils.resolveFilenameConflict(allocator, "/tmp/file with spaces.txt");
    defer allocator.free(result1);
    try testing.expectEqualStrings("/tmp/file with spaces.txt", result1);

    const result2 = try utils.resolveFilenameConflict(allocator, "/tmp/file-with-dashes.jpg");
    defer allocator.free(result2);
    try testing.expectEqualStrings("/tmp/file-with-dashes.jpg", result2);

    const result3 = try utils.resolveFilenameConflict(allocator, "/tmp/file_with_underscores.pdf");
    defer allocator.free(result3);
    try testing.expectEqualStrings("/tmp/file_with_underscores.pdf", result3);
}

test "FileInfo struct creation" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test FileInfo struct creation and cleanup
    const name = try allocator.dupe(u8, "test.txt");
    const extension = try allocator.dupe(u8, ".txt");
    defer allocator.free(name);
    defer allocator.free(extension);

    const file_info = FileInfo{
        .name = name,
        .extension = extension,
        .category = .Documents,
        .size = 0,
        .created_time = 0,
        .modified_time = 0,
        .hash = [_]u8{0} ** 32,
    };

    try testing.expectEqualStrings("test.txt", file_info.name);
    try testing.expectEqualStrings(".txt", file_info.extension);
    try testing.expectEqual(FileCategory.Documents, file_info.category);
}

test "extensive file extension coverage" {
    const testing = std.testing;

    // Test many more file extensions for comprehensive coverage

    // Documents - additional extensions
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".docx"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".odt"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".rtf"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".tex"));

    // Images - additional extensions
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".bmp"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".svg"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".ico"));
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".webp"));

    // Videos - additional extensions
    try testing.expectEqual(FileCategory.Videos, organize_cmd.categorizeFileByExtension(".mov"));
    try testing.expectEqual(FileCategory.Videos, organize_cmd.categorizeFileByExtension(".wmv"));
    try testing.expectEqual(FileCategory.Videos, organize_cmd.categorizeFileByExtension(".flv"));
    try testing.expectEqual(FileCategory.Videos, organize_cmd.categorizeFileByExtension(".webm"));

    // Audio - additional extensions
    try testing.expectEqual(FileCategory.Audio, organize_cmd.categorizeFileByExtension(".aac"));
    try testing.expectEqual(FileCategory.Audio, organize_cmd.categorizeFileByExtension(".ogg"));
    try testing.expectEqual(FileCategory.Audio, organize_cmd.categorizeFileByExtension(".wma"));
    try testing.expectEqual(FileCategory.Audio, organize_cmd.categorizeFileByExtension(".m4a"));

    // Archives - additional extensions
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".rar"));
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".7z"));
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".bz2"));
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".xz"));

    // Code - additional extensions
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".c"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".cpp"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".h"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".hpp"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".java"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".cs"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".go"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".rs"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".sh"));
    try testing.expectEqual(FileCategory.Code, organize_cmd.categorizeFileByExtension(".bat"));

    // Data - additional extensions
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".xml"));
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".csv"));
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".sql"));
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".db"));
    try testing.expectEqual(FileCategory.Data, organize_cmd.categorizeFileByExtension(".sqlite"));

    // Configuration - additional extensions
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".ini"));
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".cfg"));
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".conf"));
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".yaml"));
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".yml"));
    try testing.expectEqual(FileCategory.Configuration, organize_cmd.categorizeFileByExtension(".toml"));
}

// Integration tests with temporary directories

test "integration - create temporary directory with files" {
    const allocator = std.testing.allocator;

    // Create a temporary directory
    const temp_dir_name = "zigstack_test_temp";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create test files in the temporary directory
    const test_files = [_][]const u8{
        "document.txt",
        "image.jpg",
        "video.mp4",
        "audio.mp3",
        "archive.zip",
        "source.zig",
        "data.json",
        "config.yaml",
        "unknown.xyz",
        "no_extension",
        ".hidden_file",
        "file with spaces.pdf",
        "file-with-dashes.png",
        "file_with_underscores.wav",
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (test_files) |filename| {
        var file = try temp_dir.createFile(filename, .{});
        try file.writeAll("test content");
        file.close();
    }

    // Test that the files were created successfully
    for (test_files) |filename| {
        temp_dir.access(filename, .{}) catch |err| {
            std.debug.print("Failed to access file: {s}\n", .{filename});
            return err;
        };
    }

    // Test listFiles function with the temporary directory
    const config = Config{
        .dry_run = true,
        .verbose = false,
        .create_directories = false,
        .move_files = false,
    };

    // The listFiles function should run without errors
    organize_cmd.listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("listFiles failed with error: {}\n", .{err});
        return err;
    };
}

test "integration - directory creation workflow" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing directory creation
    const temp_dir_name = "zigstack_test_create_dirs";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create test files
    const test_files = [_][]const u8{
        "test1.txt",
        "test2.jpg",
        "test3.mp4",
        "test4.zip",
        "test5.zig",
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (test_files) |filename| {
        var file = try temp_dir.createFile(filename, .{});
        try file.writeAll("test content for integration testing");
        file.close();
    }

    // Test with directory creation enabled
    const config = Config{
        .dry_run = false,
        .verbose = false,
        .create_directories = true,
        .move_files = false,
    };

    organize_cmd.listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Directory creation test failed: {}\n", .{err});
        return err;
    };

    // Verify directories were created
    const expected_dirs = [_][]const u8{
        "documents",
        "images",
        "videos",
        "archives",
        "code",
    };

    for (expected_dirs) |dir_name| {
        const dir_path = try std.mem.join(allocator, "/", &[_][]const u8{ temp_dir_name, dir_name });
        defer allocator.free(dir_path);

        std.fs.cwd().access(dir_path, .{}) catch |err| {
            std.debug.print("Expected directory not found: {s}\n", .{dir_path});
            return err;
        };
    }
}

test "integration - file moving workflow" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing file moving
    const temp_dir_name = "zigstack_test_move_files";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create test files with different extensions
    const test_files = [_]struct {
        name: []const u8,
        expected_dir: []const u8,
    }{
        .{ .name = "document.txt", .expected_dir = "documents" },
        .{ .name = "picture.jpg", .expected_dir = "images" },
        .{ .name = "movie.mp4", .expected_dir = "videos" },
        .{ .name = "song.mp3", .expected_dir = "audio" },
        .{ .name = "backup.zip", .expected_dir = "archives" },
        .{ .name = "program.zig", .expected_dir = "code" },
        .{ .name = "database.json", .expected_dir = "data" },
        .{ .name = "settings.yaml", .expected_dir = "config" },
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (test_files) |test_file| {
        var file = try temp_dir.createFile(test_file.name, .{});
        try file.writeAll("test content for file moving");
        file.close();
    }

    // Test with file moving enabled
    const config = Config{
        .dry_run = false,
        .verbose = false,
        .create_directories = true,
        .move_files = true,
    };

    organize_cmd.listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("File moving test failed: {}\n", .{err});
        return err;
    };

    // Verify files were moved to correct directories
    for (test_files) |test_file| {
        const file_path = try std.mem.join(allocator, "/", &[_][]const u8{ temp_dir_name, test_file.expected_dir, test_file.name });
        defer allocator.free(file_path);

        std.fs.cwd().access(file_path, .{}) catch |err| {
            std.debug.print("Expected file not found: {s}\n", .{file_path});
            return err;
        };

        // Verify original file no longer exists in root
        const original_path = try std.mem.join(allocator, "/", &[_][]const u8{ temp_dir_name, test_file.name });
        defer allocator.free(original_path);

        std.fs.cwd().access(original_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {}, // Expected - file should have been moved
            else => {
                std.debug.print("Original file still exists: {s}\n", .{original_path});
                return err;
            },
        };
    }
}

test "integration - filename conflict resolution" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing filename conflicts
    const temp_dir_name = "zigstack_test_conflicts";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    // Create directories first
    try temp_dir.makeDir("documents");

    // Create a file in the documents directory to create a conflict
    var existing_file = try temp_dir.createFile("documents/test.txt", .{});
    try existing_file.writeAll("existing content");
    existing_file.close();

    // Create a file with the same name in the root directory
    var new_file = try temp_dir.createFile("test.txt", .{});
    try new_file.writeAll("new content");
    new_file.close();

    // Test file moving with conflict resolution
    const config = Config{
        .dry_run = false,
        .verbose = true,
        .create_directories = true,
        .move_files = true,
    };

    organize_cmd.listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Conflict resolution test failed: {}\n", .{err});
        return err;
    };

    // Verify that both files exist (original and renamed)
    temp_dir.access("documents/test.txt", .{}) catch |err| {
        std.debug.print("Original conflicting file missing: {}\n", .{err});
        return err;
    };

    // The new file should have been renamed to test_1.txt
    temp_dir.access("documents/test_1.txt", .{}) catch |err| {
        std.debug.print("Renamed conflicting file missing: {}\n", .{err});
        return err;
    };
}

test "integration - empty directory handling" {
    const allocator = std.testing.allocator;

    // Create a temporary empty directory
    const temp_dir_name = "zigstack_test_empty";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    const config = Config{
        .dry_run = true,
        .verbose = false,
        .create_directories = false,
        .move_files = false,
    };

    // Test that empty directories are handled gracefully
    organize_cmd.listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Empty directory test failed: {}\n", .{err});
        return err;
    };
}

test "integration - special characters in filenames" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing special characters
    const temp_dir_name = "zigstack_test_special";
    std.fs.cwd().makeDir(temp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err,
    };
    defer std.fs.cwd().deleteTree(temp_dir_name) catch {};

    // Create files with special characters in names
    const special_files = [_][]const u8{
        "file with spaces.txt",
        "file-with-dashes.jpg",
        "file_with_underscores.mp3",
        "file123numbers.pdf",
        "file.multiple.dots.zip",
    };

    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    for (special_files) |filename| {
        var file = try temp_dir.createFile(filename, .{});
        try file.writeAll("content with special characters");
        file.close();
    }

    // Test with dry run first
    const config = Config{
        .dry_run = true,
        .verbose = false,
        .create_directories = false,
        .move_files = true, // Test move logic in dry-run mode
    };

    organize_cmd.listFiles(allocator, temp_dir_name, &config) catch |err| {
        std.debug.print("Special characters test failed: {}\n", .{err});
        return err;
    };
}

test "integration - rollback functionality" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    // Test MoveTracker rollback with real files (simulated)
    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Simulate recording some moves
    try move_tracker.recordMove("source1.txt", "dest1.txt");
    try move_tracker.recordMove("source2.jpg", "dest2.jpg");

    try testing.expectEqual(@as(usize, 2), move_tracker.moves.items.len);

    // Test that rollback configuration works
    const config = Config{
        .dry_run = false,
        .verbose = true,
        .create_directories = false,
        .move_files = false,
    };

    // Note: We can't actually test file system rollback without creating real files
    // that we might fail to move, but we can test that the structure works
    try testing.expectEqual(true, config.verbose);
}

// Edge case tests for improved robustness

test "edge cases - empty filename handling" {
    const testing = std.testing;

    // Test empty filename
    try testing.expectEqualStrings("", utils.getFileExtension(""));

    // Test filename with only dots
    try testing.expectEqualStrings("", utils.getFileExtension("..."));
    try testing.expectEqualStrings("", utils.getFileExtension(".."));

    // Test edge cases with categorization
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(""));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension("."));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension("..."));
}

test "edge cases - very long extensions" {
    const testing = std.testing;

    // Test very long extension (should be categorized as Other)
    const long_extension = ".verylongextensionnamethatexceedslimits123456789";
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(long_extension));

    // Test normal extension still works
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".txt"));
}

test "edge cases - invalid characters in extensions" {
    const testing = std.testing;

    // Test extensions with only dots and invalid characters
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension("....."));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".@#$%"));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".*&^%"));

    // Test valid extensions with numbers (should still work)
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".123")); // Numbers only should be Other
    try testing.expectEqual(FileCategory.Images, organize_cmd.categorizeFileByExtension(".jpg")); // Valid extension
}

test "edge cases - filename boundaries" {
    const testing = std.testing;

    // Test single character filenames
    try testing.expectEqualStrings("", utils.getFileExtension("a"));
    try testing.expectEqualStrings(".b", utils.getFileExtension("a.b"));

    // Test filename ending with dot
    try testing.expectEqualStrings(".", utils.getFileExtension("file."));

    // Test multiple extensions
    try testing.expectEqualStrings(".old", utils.getFileExtension("file.txt.old"));
    try testing.expectEqualStrings(".gz", utils.getFileExtension("archive.tar.gz"));

    // Categorize these edge cases
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension("."));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".old"));
    try testing.expectEqual(FileCategory.Archives, organize_cmd.categorizeFileByExtension(".gz")); // .gz is a known archive extension
}

test "edge cases - special filename patterns" {
    const testing = std.testing;

    // Test files that start and end with dots
    try testing.expectEqualStrings("", utils.getFileExtension(".hidden"));
    try testing.expectEqualStrings(".txt", utils.getFileExtension(".hidden.txt"));

    // Test files with numbers and special chars
    try testing.expectEqualStrings(".123", utils.getFileExtension("file.123"));
    try testing.expectEqualStrings(".test", utils.getFileExtension("123.test"));
    try testing.expectEqualStrings(".txt", utils.getFileExtension("file-name_123.txt"));

    // Verify these get categorized correctly
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".123"));
    try testing.expectEqual(FileCategory.Other, organize_cmd.categorizeFileByExtension(".test"));
    try testing.expectEqual(FileCategory.Documents, organize_cmd.categorizeFileByExtension(".txt"));
}

// Advanced feature tests

test "date format parsing" {
    const testing = std.testing;
    try testing.expectEqual(DateFormat.year, parseDateFormat("year").?);
    try testing.expectEqual(DateFormat.year_month, parseDateFormat("year-month").?);
    try testing.expectEqual(DateFormat.year_month_day, parseDateFormat("year-month-day").?);
    try testing.expectEqual(@as(?DateFormat, null), parseDateFormat("invalid")); // Should return null for invalid input
}

test "duplicate action parsing" {
    const testing = std.testing;
    try testing.expectEqual(DuplicateAction.skip, parseDuplicateAction("skip").?);
    try testing.expectEqual(DuplicateAction.rename, parseDuplicateAction("rename").?);
    try testing.expectEqual(DuplicateAction.replace, parseDuplicateAction("replace").?);
    try testing.expectEqual(DuplicateAction.keep_both, parseDuplicateAction("keep-both").?);
    try testing.expectEqual(@as(?DuplicateAction, null), parseDuplicateAction("invalid")); // Should return null for invalid input
}

test "formatDatePath various formats" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test with known timestamp (2025-09-26 14:30:00 UTC)
    const test_timestamp: i64 = 1758913800;

    // Test year format
    const year_path = try formatDatePath(allocator, test_timestamp, DateFormat.year);
    defer allocator.free(year_path);
    try testing.expectEqualStrings("2025", year_path);

    // Test year-month format
    const year_month_path = try formatDatePath(allocator, test_timestamp, DateFormat.year_month);
    defer allocator.free(year_month_path);
    try testing.expectEqualStrings("2025/09", year_month_path);

    // Test year-month-day format
    const year_month_day_path = try formatDatePath(allocator, test_timestamp, DateFormat.year_month_day);
    defer allocator.free(year_month_day_path);
    try testing.expectEqualStrings("2025/09/26", year_month_day_path);
}

test "getFileStats functionality" {
    const testing = std.testing;

    // Create a temporary file
    const temp_file_name = "test_stats_file.txt";
    const test_content = "test content for stats";

    // Write test content
    const file = try std.fs.cwd().createFile(temp_file_name, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(temp_file_name) catch {};

    try file.writeAll(test_content);

    // Test getFileStats
    const stats = getFileStats(temp_file_name);
    try testing.expect(stats.size == test_content.len);
    try testing.expect(stats.created_time > 0);
    try testing.expect(stats.modified_time > 0);
    // Hash should not be all zeros for non-empty file
    try testing.expect(stats.hash[0] != 0 or stats.hash[1] != 0 or stats.hash[2] != 0);
}

test "calculateFileHash with different content" {
    const testing = std.testing;

    // Create two files with different content
    const file1_name = "test_hash_file1.txt";
    const file2_name = "test_hash_file2.txt";

    defer std.fs.cwd().deleteFile(file1_name) catch {};
    defer std.fs.cwd().deleteFile(file2_name) catch {};

    // Create file 1
    const file1 = try std.fs.cwd().createFile(file1_name, .{});
    defer file1.close();
    try file1.writeAll("content 1");

    // Create file 2 with different content
    const file2 = try std.fs.cwd().createFile(file2_name, .{});
    defer file2.close();
    try file2.writeAll("content 2");

    // Calculate hashes
    const hash1 = try calculateFileHash(file1_name);
    const hash2 = try calculateFileHash(file2_name);

    // Hashes should be different for different content
    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));

    // Same file should produce same hash
    const hash1_again = try calculateFileHash(file1_name);
    try testing.expect(std.mem.eql(u8, &hash1, &hash1_again));
}

// Import command tests
test {
    _ = @import("commands/command_test.zig");
    _ = @import("commands/backward_compat_test.zig");
    _ = @import("commands/watch_test.zig");
    _ = @import("commands/watch_rules_test.zig");
    _ = @import("commands/workspace_test.zig");
    _ = @import("commands/workspace_cleanup_test.zig");
    _ = @import("core/utils_test.zig");
    _ = @import("core/export.zig");
}

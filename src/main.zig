const std = @import("std");
const print = std.debug.print;

const VERSION = "0.1.0";
const PROGRAM_NAME = "zigstack";

const FileInfo = struct {
    name: []const u8,
    extension: []const u8,
    category: FileCategory,
};

const FileCategory = enum {
    Documents,
    Images,
    Videos,
    Audio,
    Archives,
    Code,
    Data,
    Configuration,
    Other,

    pub fn toString(self: FileCategory) []const u8 {
        return switch (self) {
            .Documents => "Documents",
            .Images => "Images",
            .Videos => "Videos",
            .Audio => "Audio",
            .Archives => "Archives",
            .Code => "Code",
            .Data => "Data",
            .Configuration => "Configuration",
            .Other => "Other",
        };
    }

    pub fn toDirectoryName(self: FileCategory) []const u8 {
        return switch (self) {
            .Documents => "documents",
            .Images => "images",
            .Videos => "videos",
            .Audio => "audio",
            .Archives => "archives",
            .Code => "code",
            .Data => "data",
            .Configuration => "config",
            .Other => "misc",
        };
    }
};

const OrganizationPlan = struct {
    categories: std.hash_map.HashMap(FileCategory, std.ArrayList(FileInfo), std.hash_map.AutoContext(FileCategory), 80),
    total_files: usize,
};

const Config = struct {
    create_directories: bool = false,
    move_files: bool = false,
    dry_run: bool = true,
    verbose: bool = false,
};

const MoveRecord = struct {
    original_path: []const u8,
    destination_path: []const u8,
};

const MoveTracker = struct {
    moves: std.ArrayList(MoveRecord),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) MoveTracker {
        return MoveTracker{
            .moves = std.ArrayList(MoveRecord){},
            .allocator = allocator,
        };
    }

    fn deinit(self: *MoveTracker) void {
        for (self.moves.items) |move_record| {
            self.allocator.free(move_record.original_path);
            self.allocator.free(move_record.destination_path);
        }
        self.moves.deinit(self.allocator);
    }

    fn recordMove(self: *MoveTracker, original_path: []const u8, destination_path: []const u8) !void {
        const original_copy = try self.allocator.dupe(u8, original_path);
        const destination_copy = try self.allocator.dupe(u8, destination_path);

        try self.moves.append(self.allocator, MoveRecord{
            .original_path = original_copy,
            .destination_path = destination_copy,
        });
    }

    fn rollback(self: *MoveTracker, config: *const Config) !void {
        if (config.verbose) {
            print("Rolling back {} file moves...\n", .{self.moves.items.len});
        }

        // Rollback in reverse order
        var i = self.moves.items.len;
        while (i > 0) {
            i -= 1;
            const move_record = self.moves.items[i];

            if (config.verbose) {
                print("Moving {s} back to {s}\n", .{ move_record.destination_path, move_record.original_path });
            }

            std.fs.cwd().rename(move_record.destination_path, move_record.original_path) catch |err| {
                printError("Failed to rollback file move");
                print("Could not move {s} back to {s}: {}\n", .{ move_record.destination_path, move_record.original_path, err });
                return err;
            };
        }

        if (config.verbose) {
            print("Rollback complete.\n", .{});
        }
    }
};

const usage_text =
    \\Usage: {s} [OPTIONS] <directory>
    \\
    \\Analyze and manage Zig project stack structure.
    \\
    \\Arguments:
    \\  <directory>       Directory path to analyze
    \\
    \\Options:
    \\  -h, --help        Display this help message
    \\  --version         Display version information
    \\  -c, --create      Create directories (default: preview only)
    \\  -m, --move        Move files to directories (implies --create)
    \\  -d, --dry-run     Show what would happen without doing it
    \\  -V, --verbose     Enable verbose logging
    \\
    \\Examples:
    \\  {s} /path/to/project              # Preview organization
    \\  {s} --create /path/to/project     # Create directories only
    \\  {s} --move /path/to/project       # Create directories and move files
    \\  {s} --dry-run --verbose /path     # Verbose preview mode
    \\
;

fn printUsage(program_name: []const u8) void {
    print(usage_text, .{ program_name, program_name, program_name, program_name, program_name });
}

fn printVersion() void {
    print("{s} {s}\n", .{ PROGRAM_NAME, VERSION });
}

fn printError(message: []const u8) void {
    std.debug.print("Error: {s}\n", .{message});
}

fn validateDirectory(path: []const u8) !void {
    var file = std.fs.cwd().openDir(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            printError("Directory not found");
            return err;
        },
        error.NotDir => {
            printError("Path exists but is not a directory");
            return err;
        },
        error.AccessDenied => {
            printError("Access denied to directory");
            return err;
        },
        else => {
            printError("Unable to access directory");
            return err;
        },
    };
    file.close();
}

fn getFileExtension(filename: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, filename, ".")) |dot_index| {
        // Don't count hidden files starting with '.' as having an extension
        if (dot_index == 0) {
            return "";
        }
        return filename[dot_index..];
    }
    return "";
}

fn resolveFilenameConflict(allocator: std.mem.Allocator, target_path: []const u8) ![]const u8 {
    // Check if the target path exists
    std.fs.cwd().access(target_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // File doesn't exist, use original path
            return try allocator.dupe(u8, target_path);
        },
        else => return err,
    };

    // File exists, need to find alternative name
    const dir_name = std.fs.path.dirname(target_path) orelse ".";
    const base_name = std.fs.path.basename(target_path);

    // Split filename and extension
    const extension = getFileExtension(base_name);
    const name_without_ext = if (extension.len > 0)
        base_name[0..base_name.len - extension.len]
    else
        base_name;

    // Try incrementing counter until we find available name
    var counter: u32 = 1;
    while (counter < 1000) : (counter += 1) {
        const new_name = if (extension.len > 0)
            try std.fmt.allocPrint(allocator, "{s}_{}{s}", .{ name_without_ext, counter, extension })
        else
            try std.fmt.allocPrint(allocator, "{s}_{}", .{ name_without_ext, counter });

        const new_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_name, new_name });

        std.fs.cwd().access(new_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Found available name
                allocator.free(new_name);
                return new_path;
            },
            else => {
                allocator.free(new_name);
                allocator.free(new_path);
                return err;
            },
        };

        allocator.free(new_name);
        allocator.free(new_path);
    }

    return error.TooManyConflicts;
}

fn categorizeFileByExtension(extension: []const u8) FileCategory {
    // Convert extension to lowercase for comparison
    var ext_lower: [256]u8 = undefined;
    if (extension.len == 0) {
        return .Other;
    }

    // Simple lowercase conversion for ASCII
    const ext_len = @min(extension.len, ext_lower.len);
    for (extension[0..ext_len], 0..) |c, i| {
        ext_lower[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    const ext_lower_slice = ext_lower[0..ext_len];

    // Documents
    if (std.mem.eql(u8, ext_lower_slice, ".txt") or
        std.mem.eql(u8, ext_lower_slice, ".doc") or
        std.mem.eql(u8, ext_lower_slice, ".docx") or
        std.mem.eql(u8, ext_lower_slice, ".pdf") or
        std.mem.eql(u8, ext_lower_slice, ".odt") or
        std.mem.eql(u8, ext_lower_slice, ".rtf") or
        std.mem.eql(u8, ext_lower_slice, ".tex") or
        std.mem.eql(u8, ext_lower_slice, ".md"))
    {
        return .Documents;
    }

    // Images
    if (std.mem.eql(u8, ext_lower_slice, ".jpg") or
        std.mem.eql(u8, ext_lower_slice, ".jpeg") or
        std.mem.eql(u8, ext_lower_slice, ".png") or
        std.mem.eql(u8, ext_lower_slice, ".gif") or
        std.mem.eql(u8, ext_lower_slice, ".bmp") or
        std.mem.eql(u8, ext_lower_slice, ".svg") or
        std.mem.eql(u8, ext_lower_slice, ".ico") or
        std.mem.eql(u8, ext_lower_slice, ".webp"))
    {
        return .Images;
    }

    // Videos
    if (std.mem.eql(u8, ext_lower_slice, ".mp4") or
        std.mem.eql(u8, ext_lower_slice, ".avi") or
        std.mem.eql(u8, ext_lower_slice, ".mkv") or
        std.mem.eql(u8, ext_lower_slice, ".mov") or
        std.mem.eql(u8, ext_lower_slice, ".wmv") or
        std.mem.eql(u8, ext_lower_slice, ".flv") or
        std.mem.eql(u8, ext_lower_slice, ".webm"))
    {
        return .Videos;
    }

    // Audio
    if (std.mem.eql(u8, ext_lower_slice, ".mp3") or
        std.mem.eql(u8, ext_lower_slice, ".wav") or
        std.mem.eql(u8, ext_lower_slice, ".flac") or
        std.mem.eql(u8, ext_lower_slice, ".aac") or
        std.mem.eql(u8, ext_lower_slice, ".ogg") or
        std.mem.eql(u8, ext_lower_slice, ".wma") or
        std.mem.eql(u8, ext_lower_slice, ".m4a"))
    {
        return .Audio;
    }

    // Archives
    if (std.mem.eql(u8, ext_lower_slice, ".zip") or
        std.mem.eql(u8, ext_lower_slice, ".tar") or
        std.mem.eql(u8, ext_lower_slice, ".gz") or
        std.mem.eql(u8, ext_lower_slice, ".rar") or
        std.mem.eql(u8, ext_lower_slice, ".7z") or
        std.mem.eql(u8, ext_lower_slice, ".bz2") or
        std.mem.eql(u8, ext_lower_slice, ".xz"))
    {
        return .Archives;
    }

    // Code
    if (std.mem.eql(u8, ext_lower_slice, ".c") or
        std.mem.eql(u8, ext_lower_slice, ".cpp") or
        std.mem.eql(u8, ext_lower_slice, ".h") or
        std.mem.eql(u8, ext_lower_slice, ".hpp") or
        std.mem.eql(u8, ext_lower_slice, ".py") or
        std.mem.eql(u8, ext_lower_slice, ".js") or
        std.mem.eql(u8, ext_lower_slice, ".ts") or
        std.mem.eql(u8, ext_lower_slice, ".java") or
        std.mem.eql(u8, ext_lower_slice, ".cs") or
        std.mem.eql(u8, ext_lower_slice, ".go") or
        std.mem.eql(u8, ext_lower_slice, ".rs") or
        std.mem.eql(u8, ext_lower_slice, ".zig") or
        std.mem.eql(u8, ext_lower_slice, ".sh") or
        std.mem.eql(u8, ext_lower_slice, ".bat"))
    {
        return .Code;
    }

    // Data
    if (std.mem.eql(u8, ext_lower_slice, ".json") or
        std.mem.eql(u8, ext_lower_slice, ".xml") or
        std.mem.eql(u8, ext_lower_slice, ".csv") or
        std.mem.eql(u8, ext_lower_slice, ".sql") or
        std.mem.eql(u8, ext_lower_slice, ".db") or
        std.mem.eql(u8, ext_lower_slice, ".sqlite"))
    {
        return .Data;
    }

    // Configuration
    if (std.mem.eql(u8, ext_lower_slice, ".ini") or
        std.mem.eql(u8, ext_lower_slice, ".cfg") or
        std.mem.eql(u8, ext_lower_slice, ".conf") or
        std.mem.eql(u8, ext_lower_slice, ".yaml") or
        std.mem.eql(u8, ext_lower_slice, ".yml") or
        std.mem.eql(u8, ext_lower_slice, ".toml"))
    {
        return .Configuration;
    }

    return .Other;
}

fn createDirectories(allocator: std.mem.Allocator, base_path: []const u8, organization_plan: *const OrganizationPlan, config: *const Config) !void {
    if (config.verbose) {
        print("Creating directories in: {s}\n", .{base_path});
    }

    var iterator = organization_plan.categories.iterator();
    while (iterator.next()) |entry| {
        const category = entry.key_ptr.*;
        const file_list = entry.value_ptr.*;

        if (file_list.items.len == 0) continue;

        const dir_name = category.toDirectoryName();

        // Create full path
        const full_path = try std.mem.join(allocator, "/", &[_][]const u8{ base_path, dir_name });
        defer allocator.free(full_path);

        if (config.dry_run) {
            print("Would create directory: {s} (for {} files)\n", .{ full_path, file_list.items.len });
        } else if (config.create_directories) {
            // Try to create directory
            std.fs.cwd().makeDir(full_path) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    if (config.verbose) {
                        print("Directory already exists: {s}\n", .{full_path});
                    }
                },
                error.AccessDenied => {
                    printError("Permission denied creating directory");
                    print("Failed to create: {s}\n", .{full_path});
                    return err;
                },
                else => {
                    printError("Failed to create directory");
                    print("Error creating: {s}\n", .{full_path});
                    return err;
                },
            };

            if (config.verbose) {
                print("Created directory: {s}\n", .{full_path});
            }
        }
    }
}

fn moveFiles(allocator: std.mem.Allocator, base_path: []const u8, organization_plan: *const OrganizationPlan, config: *const Config, move_tracker: *MoveTracker) !void {
    if (config.verbose) {
        print("Moving files in: {s}\n", .{base_path});
    }

    var iterator = organization_plan.categories.iterator();
    while (iterator.next()) |entry| {
        const category = entry.key_ptr.*;
        const file_list = entry.value_ptr.*;

        if (file_list.items.len == 0) continue;

        const dir_name = category.toDirectoryName();

        // Create full directory path
        const dest_dir_path = try std.mem.join(allocator, "/", &[_][]const u8{ base_path, dir_name });
        defer allocator.free(dest_dir_path);

        // Move each file in this category
        for (file_list.items) |file_info| {
            const source_path = try std.mem.join(allocator, "/", &[_][]const u8{ base_path, file_info.name });
            defer allocator.free(source_path);

            const initial_dest_path = try std.mem.join(allocator, "/", &[_][]const u8{ dest_dir_path, file_info.name });
            defer allocator.free(initial_dest_path);

            if (config.dry_run) {
                // Check for conflicts in dry-run mode
                const final_dest_path = resolveFilenameConflict(allocator, initial_dest_path) catch |err| {
                    printError("Failed to resolve filename conflict in dry-run");
                    return err;
                };
                defer allocator.free(final_dest_path);

                if (std.mem.eql(u8, initial_dest_path, final_dest_path)) {
                    print("Would move: {s} → {s}\n", .{ source_path, final_dest_path });
                } else {
                    print("Would move: {s} → {s} (renamed due to conflict)\n", .{ source_path, final_dest_path });
                }
            } else if (config.move_files) {
                // Actually move the file
                const final_dest_path = resolveFilenameConflict(allocator, initial_dest_path) catch |err| {
                    printError("Failed to resolve filename conflict");
                    print("Error with file: {s}\n", .{file_info.name});
                    return err;
                };

                // Perform the move
                std.fs.cwd().rename(source_path, final_dest_path) catch |err| {
                    printError("Failed to move file");
                    print("Could not move {s} to {s}: {}\n", .{ source_path, final_dest_path, err });
                    allocator.free(final_dest_path);
                    return err;
                };

                // Record the move for potential rollback
                try move_tracker.recordMove(source_path, final_dest_path);

                if (config.verbose) {
                    if (std.mem.eql(u8, initial_dest_path, final_dest_path)) {
                        print("Moved: {s} → {s}\n", .{ source_path, final_dest_path });
                    } else {
                        print("Moved: {s} → {s} (renamed due to conflict)\n", .{ source_path, final_dest_path });
                    }
                }

                allocator.free(final_dest_path);
            }
        }
    }
}

fn listFiles(allocator: std.mem.Allocator, dir_path: []const u8, config: *const Config) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    // Initialize move tracker for rollback capability
    var move_tracker = MoveTracker.init(allocator);
    defer move_tracker.deinit();

    // Initialize organization plan
    var organization_plan = OrganizationPlan{
        .categories = std.hash_map.HashMap(FileCategory, std.ArrayList(FileInfo), std.hash_map.AutoContext(FileCategory), 80).init(allocator),
        .total_files = 0,
    };
    defer {
        var it = organization_plan.categories.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |file| {
                allocator.free(file.name);
                allocator.free(file.extension);
            }
            entry.value_ptr.deinit(allocator);
        }
        organization_plan.categories.deinit();
    }

    var extension_counts = std.hash_map.StringHashMap(u32).init(allocator);
    defer {
        var it = extension_counts.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        extension_counts.deinit();
    }

    // Iterate through directory and categorize files
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip directories, only process files
        if (entry.kind == .file) {
            const name = try allocator.dupe(u8, entry.name);
            const ext_str = getFileExtension(entry.name);
            const extension = try allocator.dupe(u8, ext_str);
            const category = categorizeFileByExtension(extension);

            const file_info = FileInfo{
                .name = name,
                .extension = extension,
                .category = category,
            };

            // Add file to its category in the organization plan
            if (organization_plan.categories.getPtr(category)) |list_ptr| {
                try list_ptr.append(allocator, file_info);
            } else {
                var new_list = std.ArrayList(FileInfo).initCapacity(allocator, 1) catch unreachable;
                try new_list.append(allocator, file_info);
                try organization_plan.categories.put(category, new_list);
            }

            organization_plan.total_files += 1;

            // Count extensions
            const ext_key = if (extension.len > 0) extension else "(no extension)";
            const ext_key_copy = try allocator.dupe(u8, ext_key);

            if (extension_counts.get(ext_key_copy)) |count| {
                try extension_counts.put(ext_key_copy, count + 1);
                allocator.free(ext_key_copy);
            } else {
                try extension_counts.put(ext_key_copy, 1);
            }
        }
    }

    // Display results
    if (organization_plan.total_files == 0) {
        print("No files found in directory.\n", .{});
        return;
    }

    print("\n{s}\n", .{"============================================================"});
    if (config.dry_run) {
        if (config.move_files) {
            print("FILE ORGANIZATION PREVIEW - MOVING FILES (DRY RUN)\n", .{});
        } else {
            print("FILE ORGANIZATION PREVIEW (DRY RUN)\n", .{});
        }
    } else if (config.move_files) {
        print("FILE ORGANIZATION - MOVING FILES\n", .{});
    } else if (config.create_directories) {
        print("FILE ORGANIZATION - CREATING DIRECTORIES\n", .{});
    } else {
        print("FILE ORGANIZATION PREVIEW\n", .{});
    }
    print("{s}\n\n", .{"============================================================"});

    print("Total files to organize: {}\n\n", .{organization_plan.total_files});

    // Display files grouped by category
    print("Files grouped by category:\n", .{});
    print("{s}\n\n", .{"----------------------------------------"});

    const category_order = [_]FileCategory{
        .Documents,
        .Images,
        .Videos,
        .Audio,
        .Archives,
        .Code,
        .Data,
        .Configuration,
        .Other,
    };

    for (category_order) |category| {
        if (organization_plan.categories.get(category)) |file_list| {
            if (file_list.items.len > 0) {
                print("📁 {s} ({} files):\n", .{ category.toString(), file_list.items.len });
                for (file_list.items) |file| {
                    print("    • {s}", .{file.name});
                    if (file.extension.len > 0) {
                        print(" ({s})", .{file.extension});
                    }
                    print("\n", .{});
                }
                print("\n", .{});
            }
        }
    }

    // Display organization summary
    print("Organization Summary:\n", .{});
    print("{s}\n", .{"----------------------------------------"});

    for (category_order) |category| {
        if (organization_plan.categories.get(category)) |file_list| {
            if (file_list.items.len > 0) {
                const percentage = (@as(f32, @floatFromInt(file_list.items.len)) / @as(f32, @floatFromInt(organization_plan.total_files))) * 100.0;
                print("  {s}: {} files ({d:.1}%)\n", .{ category.toString(), file_list.items.len, percentage });
            }
        }
    }

    // Display file extensions breakdown
    if (extension_counts.count() > 0) {
        print("\nFile extensions breakdown:\n", .{});
        print("{s}\n", .{"----------------------------------------"});
        var it = extension_counts.iterator();
        while (it.next()) |entry| {
            print("  {s}: {} file(s)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    // Create directories if requested
    createDirectories(allocator, dir_path, &organization_plan, config) catch |err| {
        printError("Failed to create directories");
        return err;
    };

    // Move files if requested
    if (config.move_files or config.dry_run) {
        moveFiles(allocator, dir_path, &organization_plan, config, &move_tracker) catch |err| {
            if (config.move_files and !config.dry_run) {
                printError("File moving failed. Attempting rollback...");
                move_tracker.rollback(config) catch |rollback_err| {
                    printError("Rollback also failed!");
                    print("Original error: {}\n", .{err});
                    print("Rollback error: {}\n", .{rollback_err});
                    return rollback_err;
                };
                print("Rollback successful. Files restored to original locations.\n", .{});
            }
            return err;
        };
    }

    print("\n{s}\n", .{"============================================================"});
    if (config.dry_run) {
        if (config.move_files) {
            print("Note: This is a preview. No directories or files have been moved.\n", .{});
        } else {
            print("Note: This is a preview. No directories have been created.\n", .{});
        }
    } else if (config.move_files) {
        print("Directory creation and file moving complete.\n", .{});
    } else if (config.create_directories) {
        print("Directory creation complete.\n", .{});
    } else {
        print("Note: This is a preview. No directories have been created.\n", .{});
    }
    print("{s}\n", .{"============================================================"});
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

    // Parse arguments
    var directory_path: ?[]const u8 = null;
    var config = Config{};
    var i: usize = 1;

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage(args[0]);
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion();
            return;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--create")) {
            config.create_directories = true;
            config.dry_run = false; // Creating implies not dry-run
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--move")) {
            config.move_files = true;
            config.create_directories = true; // Moving implies creating directories
            config.dry_run = false; // Moving implies not dry-run
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dry-run")) {
            config.dry_run = true;
            config.create_directories = false; // Dry-run implies not creating
            config.move_files = false; // Dry-run implies not moving
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            printError("Unknown option");
            print("Try '{s} --help' for more information.\n", .{args[0]});
            std.process.exit(1);
        } else {
            // Positional argument (directory path)
            if (directory_path != null) {
                printError("Multiple directory paths provided. Only one is allowed");
                std.process.exit(1);
            }
            directory_path = arg;
        }

        i += 1;
    }

    // Ensure directory path was provided
    const path = directory_path orelse {
        printError("Missing required directory argument");
        print("\n", .{});
        printUsage(args[0]);
        std.process.exit(1);
    };

    // Validate directory exists
    validateDirectory(path) catch {
        std.process.exit(1);
    };

    // If we get here, directory is valid
    print("Analyzing directory: {s}\n", .{path});

    // List files in the directory
    listFiles(allocator, path, &config) catch |err| {
        if (err == error.AccessDenied) {
            printError("Permission denied while reading directory contents");
        } else {
            printError("Failed to read directory contents");
        }
        std.process.exit(1);
    };
}

// Tests
test "basic test" {
    try std.testing.expect(true);
}

test "getFileExtension" {
    const testing = std.testing;

    // Test regular files with extensions
    try testing.expectEqualStrings(".txt", getFileExtension("file.txt"));
    try testing.expectEqualStrings(".zig", getFileExtension("main.zig"));
    try testing.expectEqualStrings(".gz", getFileExtension("archive.tar.gz"));

    // Test files without extensions
    try testing.expectEqualStrings("", getFileExtension("README"));
    try testing.expectEqualStrings("", getFileExtension("Makefile"));

    // Test hidden files (starting with .)
    try testing.expectEqualStrings("", getFileExtension(".gitignore"));
    try testing.expectEqualStrings(".txt", getFileExtension(".hidden.txt"));
}

test "categorizeFileByExtension" {
    const testing = std.testing;

    // Test Documents
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".txt"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".pdf"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".md"));
    try testing.expectEqual(FileCategory.Documents, categorizeFileByExtension(".doc"));

    // Test Images
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".jpg"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".jpeg"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".png"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".gif"));

    // Test Videos
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".mp4"));
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".avi"));
    try testing.expectEqual(FileCategory.Videos, categorizeFileByExtension(".mkv"));

    // Test Audio
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".mp3"));
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".wav"));
    try testing.expectEqual(FileCategory.Audio, categorizeFileByExtension(".flac"));

    // Test Archives
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".zip"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".tar"));
    try testing.expectEqual(FileCategory.Archives, categorizeFileByExtension(".gz"));

    // Test Code
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".zig"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".py"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".js"));

    // Test Data
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".json"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".xml"));
    try testing.expectEqual(FileCategory.Data, categorizeFileByExtension(".csv"));

    // Test Configuration
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".ini"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".yaml"));
    try testing.expectEqual(FileCategory.Configuration, categorizeFileByExtension(".toml"));

    // Test case insensitive
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".JPG"));
    try testing.expectEqual(FileCategory.Images, categorizeFileByExtension(".PNG"));
    try testing.expectEqual(FileCategory.Code, categorizeFileByExtension(".ZIG"));

    // Test Other/Unknown
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(".xyz"));
    try testing.expectEqual(FileCategory.Other, categorizeFileByExtension(""));
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
    const result = try resolveFilenameConflict(allocator, "/tmp/nonexistent_file.txt");
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

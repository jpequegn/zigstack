const std = @import("std");
const print = std.debug.print;

const utils = @import("../core/utils.zig");
const command_mod = @import("command.zig");

pub const Command = command_mod.Command;

const printError = utils.printError;
const printSuccess = utils.printSuccess;
const printInfo = utils.printInfo;
const printWarning = utils.printWarning;
const validateDirectory = utils.validateDirectory;

const workspace_help_text =
    \\Usage: zigstack workspace [COMMAND] [OPTIONS] <directory>
    \\
    \\Analyze and manage developer workspace projects.
    \\
    \\Commands:
    \\  scan        Scan directory for projects and generate report
    \\  cleanup     Clean up build artifacts and dependencies from projects
    \\
    \\Arguments:
    \\  <directory>       Directory path to scan (usually ~/Code or ~/Projects)
    \\
    \\Options:
    \\  -h, --help              Display this help message
    \\  --inactive-days N       Days threshold for inactive projects (default: 180)
    \\  -V, --verbose           Enable verbose logging
    \\  --json                  Output results as JSON
    \\
    \\Cleanup Options:
    \\  -d, --dry-run           Show what would be cleaned without deleting
    \\  --strategy LEVEL        Cleanup strategy: conservative, moderate, aggressive (default: conservative)
    \\  --project-type TYPE     Only clean projects of specific type (nodejs, python, rust, zig, go, java)
    \\  --inactive-only         Only clean inactive projects
    \\  --artifacts-only        Only remove build artifacts (preserve dependencies)
    \\  --deps-only             Only remove dependencies (preserve build artifacts)
    \\
    \\Examples:
    \\  zigstack workspace scan ~/Code
    \\  zigstack workspace scan --inactive-days 90 ~/Projects
    \\  zigstack workspace cleanup --dry-run ~/Code
    \\  zigstack workspace cleanup --strategy moderate --inactive-only ~/Code
    \\  zigstack workspace cleanup --project-type nodejs --artifacts-only ~/Code
    \\
;

/// Project type enumeration
pub const ProjectType = enum {
    nodejs,
    python,
    rust,
    zig,
    go_lang,
    java,
    unknown,

    pub fn toString(self: ProjectType) []const u8 {
        return switch (self) {
            .nodejs => "Node.js",
            .python => "Python",
            .rust => "Rust",
            .zig => "Zig",
            .go_lang => "Go",
            .java => "Java",
            .unknown => "Unknown",
        };
    }
};

/// Project information
pub const ProjectInfo = struct {
    name: []const u8,
    path: []const u8,
    project_type: ProjectType,
    source_size: u64 = 0,
    dependencies_size: u64 = 0,
    build_artifacts_size: u64 = 0,
    git_size: u64 = 0,
    total_size: u64 = 0,
    last_modified: i128 = 0,
    is_inactive: bool = false,
};

/// Workspace statistics
pub const WorkspaceStats = struct {
    total_projects: usize = 0,
    projects_by_type: std.AutoHashMap(ProjectType, usize),
    size_by_type: std.AutoHashMap(ProjectType, u64),
    inactive_by_type: std.AutoHashMap(ProjectType, usize),
    total_source_size: u64 = 0,
    total_dependencies_size: u64 = 0,
    total_build_artifacts_size: u64 = 0,
    total_git_size: u64 = 0,
    total_size: u64 = 0,
    total_inactive: usize = 0,

    pub fn init(allocator: std.mem.Allocator) WorkspaceStats {
        return .{
            .projects_by_type = std.AutoHashMap(ProjectType, usize).init(allocator),
            .size_by_type = std.AutoHashMap(ProjectType, u64).init(allocator),
            .inactive_by_type = std.AutoHashMap(ProjectType, usize).init(allocator),
        };
    }

    pub fn deinit(self: *WorkspaceStats) void {
        self.projects_by_type.deinit();
        self.size_by_type.deinit();
        self.inactive_by_type.deinit();
    }
};

/// Cleanup strategy levels
pub const CleanupStrategy = enum {
    conservative, // Only build artifacts in inactive projects
    moderate, // Build artifacts + dependencies in inactive projects
    aggressive, // Build artifacts + dependencies in all projects

    pub fn fromString(str: []const u8) ?CleanupStrategy {
        if (std.mem.eql(u8, str, "conservative")) return .conservative;
        if (std.mem.eql(u8, str, "moderate")) return .moderate;
        if (std.mem.eql(u8, str, "aggressive")) return .aggressive;
        return null;
    }

    pub fn toString(self: CleanupStrategy) []const u8 {
        return switch (self) {
            .conservative => "conservative",
            .moderate => "moderate",
            .aggressive => "aggressive",
        };
    }
};

/// Cleanup configuration
pub const CleanupConfig = struct {
    dry_run: bool = false,
    strategy: CleanupStrategy = .conservative,
    project_type_filter: ?ProjectType = null,
    inactive_only: bool = false,
    artifacts_only: bool = false,
    deps_only: bool = false,
    verbose: bool = false,
};

/// Cleanup result for a single project
pub const CleanupResult = struct {
    project_name: []const u8,
    project_type: ProjectType,
    artifacts_removed: u64 = 0,
    deps_removed: u64 = 0,
    total_removed: u64 = 0,
    error_message: ?[]const u8 = null,
};

/// Aggregate cleanup statistics
pub const CleanupStats = struct {
    projects_cleaned: usize = 0,
    projects_skipped: usize = 0,
    projects_failed: usize = 0,
    total_artifacts_removed: u64 = 0,
    total_deps_removed: u64 = 0,
    total_space_freed: u64 = 0,
};

/// Detect project type based on files in directory
fn detectProjectType(dir_path: []const u8) !ProjectType {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = false });
    defer dir.close();

    // Check for Node.js
    if (dir.access("package.json", .{})) |_| {
        return .nodejs;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for Python
    if (dir.access("requirements.txt", .{})) |_| {
        return .python;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    if (dir.access("setup.py", .{})) |_| {
        return .python;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    if (dir.access("pyproject.toml", .{})) |_| {
        return .python;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for Rust
    if (dir.access("Cargo.toml", .{})) |_| {
        return .rust;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for Zig
    if (dir.access("build.zig", .{})) |_| {
        return .zig;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for Go
    if (dir.access("go.mod", .{})) |_| {
        return .go_lang;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for Java
    if (dir.access("pom.xml", .{})) |_| {
        return .java;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    if (dir.access("build.gradle", .{})) |_| {
        return .java;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    return .unknown;
}

/// Calculate directory size recursively
fn calculateDirSize(allocator: std.mem.Allocator, dir_path: []const u8) !u64 {
    var total_size: u64 = 0;
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        return if (err == error.FileNotFound or err == error.AccessDenied) 0 else err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const subdir_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(subdir_path);
            total_size += try calculateDirSize(allocator, subdir_path);
        } else if (entry.kind == .file) {
            const file_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(file_path);

            const file = dir.openFile(entry.name, .{}) catch continue;
            defer file.close();

            const stat = file.stat() catch continue;
            total_size += stat.size;
        }
    }

    return total_size;
}

/// Get last modified time of directory
fn getLastModifiedTime(dir_path: []const u8) !i128 {
    var dir = try std.fs.cwd().openDir(dir_path, .{});
    defer dir.close();

    const stat = try dir.stat();
    return stat.mtime;
}

/// Analyze a single project
fn analyzeProject(
    allocator: std.mem.Allocator,
    project_path: []const u8,
    project_name: []const u8,
    project_type: ProjectType,
    inactive_threshold_secs: i64,
) !ProjectInfo {
    var info = ProjectInfo{
        .name = try allocator.dupe(u8, project_name),
        .path = try allocator.dupe(u8, project_path),
        .project_type = project_type,
    };

    // Calculate sizes for different artifact types
    const deps_paths: []const []const u8 = switch (project_type) {
        .nodejs => &[_][]const u8{"node_modules"},
        .python => &[_][]const u8{ "venv", ".venv", "__pycache__" },
        .rust => &[_][]const u8{"target"},
        .zig => &[_][]const u8{ "zig-cache", "zig-out" },
        .go_lang => &[_][]const u8{"vendor"},
        .java => &[_][]const u8{ "target", "build", ".gradle" },
        .unknown => &[_][]const u8{},
    };

    const build_paths: []const []const u8 = switch (project_type) {
        .nodejs => &[_][]const u8{ "dist", "build", ".next", ".nuxt" },
        .python => &[_][]const u8{"dist"},
        .rust => &[_][]const u8{},
        .zig => &[_][]const u8{},
        .go_lang => &[_][]const u8{},
        .java => &[_][]const u8{},
        .unknown => &[_][]const u8{},
    };

    // Calculate dependencies size
    for (deps_paths) |dep_path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ project_path, dep_path });
        defer allocator.free(full_path);
        info.dependencies_size += try calculateDirSize(allocator, full_path);
    }

    // Calculate build artifacts size
    for (build_paths) |build_path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ project_path, build_path });
        defer allocator.free(full_path);
        info.build_artifacts_size += try calculateDirSize(allocator, full_path);
    }

    // Calculate git repository size
    const git_path = try std.fs.path.join(allocator, &[_][]const u8{ project_path, ".git" });
    defer allocator.free(git_path);
    info.git_size = try calculateDirSize(allocator, git_path);

    // Calculate total project size
    const total_project_size = try calculateDirSize(allocator, project_path);
    info.total_size = total_project_size;
    info.source_size = total_project_size -| info.dependencies_size -| info.build_artifacts_size -| info.git_size;

    // Check if project is inactive
    info.last_modified = getLastModifiedTime(project_path) catch 0;
    const now = std.time.nanoTimestamp();
    const age_secs = @divFloor(now - info.last_modified, std.time.ns_per_s);
    info.is_inactive = age_secs > inactive_threshold_secs;

    return info;
}

/// Scan workspace for projects
fn scanWorkspace(
    allocator: std.mem.Allocator,
    workspace_path: []const u8,
    inactive_days: u32,
) !std.ArrayListUnmanaged(ProjectInfo) {
    var projects = std.ArrayListUnmanaged(ProjectInfo){};
    errdefer {
        for (projects.items) |*proj| {
            allocator.free(proj.name);
            allocator.free(proj.path);
        }
        projects.deinit(allocator);
    }

    var dir = try std.fs.cwd().openDir(workspace_path, .{ .iterate = true });
    defer dir.close();

    const inactive_threshold_secs = @as(i64, inactive_days) * 86400;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (std.mem.startsWith(u8, entry.name, ".")) continue; // Skip hidden dirs

        const project_path = try std.fs.path.join(allocator, &[_][]const u8{ workspace_path, entry.name });
        defer allocator.free(project_path);

        const project_type = detectProjectType(project_path) catch .unknown;
        if (project_type == .unknown) continue;

        const project_info = try analyzeProject(
            allocator,
            project_path,
            entry.name,
            project_type,
            inactive_threshold_secs,
        );

        try projects.append(allocator, project_info);
    }

    return projects;
}

/// Generate workspace statistics
fn generateStats(allocator: std.mem.Allocator, projects: []const ProjectInfo) !WorkspaceStats {
    var stats = WorkspaceStats.init(allocator);
    errdefer stats.deinit();

    stats.total_projects = projects.len;

    for (projects) |*project| {
        // Count by type
        const type_count = stats.projects_by_type.get(project.project_type) orelse 0;
        try stats.projects_by_type.put(project.project_type, type_count + 1);

        // Size by type
        const type_size = stats.size_by_type.get(project.project_type) orelse 0;
        try stats.size_by_type.put(project.project_type, type_size + project.total_size);

        // Inactive by type
        if (project.is_inactive) {
            const inactive_count = stats.inactive_by_type.get(project.project_type) orelse 0;
            try stats.inactive_by_type.put(project.project_type, inactive_count + 1);
            stats.total_inactive += 1;
        }

        // Aggregate sizes
        stats.total_source_size += project.source_size;
        stats.total_dependencies_size += project.dependencies_size;
        stats.total_build_artifacts_size += project.build_artifacts_size;
        stats.total_git_size += project.git_size;
        stats.total_size += project.total_size;
    }

    return stats;
}

/// Format size in human-readable format
fn formatSize(size: u64, buf: []u8) ![]const u8 {
    if (size < 1024) {
        return try std.fmt.bufPrint(buf, "{d} B", .{size});
    } else if (size < 1024 * 1024) {
        return try std.fmt.bufPrint(buf, "{d:.1} KB", .{@as(f64, @floatFromInt(size)) / 1024.0});
    } else if (size < 1024 * 1024 * 1024) {
        return try std.fmt.bufPrint(buf, "{d:.1} MB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0)});
    } else {
        return try std.fmt.bufPrint(buf, "{d:.1} GB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0)});
    }
}

/// Print workspace report
fn printReport(stats: *const WorkspaceStats, projects: []const ProjectInfo, workspace_path: []const u8) !void {
    var buf: [64]u8 = undefined;

    print("\n", .{});
    print("============================================================\n", .{});
    print("WORKSPACE ANALYSIS: {s}\n", .{workspace_path});
    print("============================================================\n\n", .{});

    print("Projects Found: {d}\n\n", .{stats.total_projects});

    // Projects by type
    if (stats.projects_by_type.count() > 0) {
        print("By Type:\n", .{});
        print("----------------------------------------\n", .{});

        var type_iter = stats.projects_by_type.iterator();
        while (type_iter.next()) |entry| {
            const project_type = entry.key_ptr.*;
            const count = entry.value_ptr.*;
            const size = stats.size_by_type.get(project_type) orelse 0;
            const inactive = stats.inactive_by_type.get(project_type) orelse 0;

            const size_str = try formatSize(size, &buf);
            print("  {s:<10} {d} projects ({s}, {d} inactive)\n", .{
                project_type.toString(),
                count,
                size_str,
                inactive,
            });
        }
        print("\n", .{});
    }

    // Disk usage breakdown
    print("Disk Usage:\n", .{});
    print("----------------------------------------\n", .{});
    print("  Source code:        {s}\n", .{try formatSize(stats.total_source_size, &buf)});
    print("  Dependencies:       {s}\n", .{try formatSize(stats.total_dependencies_size, &buf)});
    print("  Build artifacts:    {s}\n", .{try formatSize(stats.total_build_artifacts_size, &buf)});
    print("  Git repositories:   {s}\n", .{try formatSize(stats.total_git_size, &buf)});
    print("  Total:              {s}\n\n", .{try formatSize(stats.total_size, &buf)});

    // Cleanup potential
    if (stats.total_inactive > 0) {
        var cleanup_potential: u64 = 0;
        for (projects) |*project| {
            if (project.is_inactive) {
                cleanup_potential += project.dependencies_size + project.build_artifacts_size;
            }
        }
        print("Cleanup Potential: {s} from {d} inactive projects\n", .{
            try formatSize(cleanup_potential, &buf),
            stats.total_inactive,
        });
    }

    print("\n============================================================\n", .{});
}

/// Delete directory recursively
fn deleteDirectory(dir_path: []const u8) !void {
    std.fs.cwd().deleteTree(dir_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
}

/// Get paths to clean based on project type and config
fn getCleanupPaths(
    allocator: std.mem.Allocator,
    project_type: ProjectType,
    config: *const CleanupConfig,
) !struct { deps: []const []const u8, artifacts: []const []const u8 } {
    const deps_paths: []const []const u8 = if (!config.artifacts_only) switch (project_type) {
        .nodejs => &[_][]const u8{"node_modules"},
        .python => &[_][]const u8{ "venv", ".venv", "__pycache__" },
        .rust => &[_][]const u8{"target"},
        .zig => &[_][]const u8{ "zig-cache", "zig-out" },
        .go_lang => &[_][]const u8{"vendor"},
        .java => &[_][]const u8{ "target", "build", ".gradle" },
        .unknown => &[_][]const u8{},
    } else &[_][]const u8{};

    const build_paths: []const []const u8 = if (!config.deps_only) switch (project_type) {
        .nodejs => &[_][]const u8{ "dist", "build", ".next", ".nuxt" },
        .python => &[_][]const u8{"dist"},
        .rust => &[_][]const u8{},
        .zig => &[_][]const u8{},
        .go_lang => &[_][]const u8{},
        .java => &[_][]const u8{},
        .unknown => &[_][]const u8{},
    } else &[_][]const u8{};

    _ = allocator;
    return .{ .deps = deps_paths, .artifacts = build_paths };
}

/// Clean up a single project
fn cleanupProject(
    allocator: std.mem.Allocator,
    project: *const ProjectInfo,
    config: *const CleanupConfig,
) !CleanupResult {
    var result = CleanupResult{
        .project_name = project.name,
        .project_type = project.project_type,
    };

    const paths = try getCleanupPaths(allocator, project.project_type, config);

    // Calculate sizes before deletion
    var artifacts_size: u64 = 0;
    var deps_size: u64 = 0;

    for (paths.artifacts) |artifact_path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ project.path, artifact_path });
        defer allocator.free(full_path);

        const size = try calculateDirSize(allocator, full_path);
        artifacts_size += size;

        if (!config.dry_run) {
            deleteDirectory(full_path) catch |err| {
                const msg = try std.fmt.allocPrint(allocator, "Failed to delete {s}: {}", .{ artifact_path, err });
                result.error_message = msg;
                return result;
            };
        }
    }

    for (paths.deps) |dep_path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ project.path, dep_path });
        defer allocator.free(full_path);

        const size = try calculateDirSize(allocator, full_path);
        deps_size += size;

        if (!config.dry_run) {
            deleteDirectory(full_path) catch |err| {
                const msg = try std.fmt.allocPrint(allocator, "Failed to delete {s}: {}", .{ dep_path, err });
                result.error_message = msg;
                return result;
            };
        }
    }

    result.artifacts_removed = artifacts_size;
    result.deps_removed = deps_size;
    result.total_removed = artifacts_size + deps_size;

    return result;
}

/// Check if project should be cleaned based on config
fn shouldCleanProject(project: *const ProjectInfo, config: *const CleanupConfig) bool {
    // Filter by project type
    if (config.project_type_filter) |filter_type| {
        if (project.project_type != filter_type) return false;
    }

    // Filter by inactive status based on strategy
    switch (config.strategy) {
        .conservative => {
            if (!project.is_inactive) return false;
        },
        .moderate => {
            if (!project.is_inactive) return false;
        },
        .aggressive => {
            // Clean all projects
        },
    }

    // Additional inactive-only filter
    if (config.inactive_only and !project.is_inactive) {
        return false;
    }

    return true;
}

/// Execute cleanup on workspace
fn performCleanup(
    allocator: std.mem.Allocator,
    projects: []const ProjectInfo,
    config: *const CleanupConfig,
) !struct { results: std.ArrayListUnmanaged(CleanupResult), stats: CleanupStats } {
    var results = std.ArrayListUnmanaged(CleanupResult){};
    errdefer {
        for (results.items) |*r| {
            if (r.error_message) |msg| allocator.free(msg);
        }
        results.deinit(allocator);
    }

    var stats = CleanupStats{};

    for (projects) |*project| {
        if (!shouldCleanProject(project, config)) {
            stats.projects_skipped += 1;
            continue;
        }

        const result = cleanupProject(allocator, project, config) catch |err| {
            stats.projects_failed += 1;
            const msg = try std.fmt.allocPrint(allocator, "Cleanup error: {}", .{err});
            try results.append(allocator, .{
                .project_name = project.name,
                .project_type = project.project_type,
                .error_message = msg,
            });
            continue;
        };

        if (result.error_message != null) {
            stats.projects_failed += 1;
        } else {
            stats.projects_cleaned += 1;
            stats.total_artifacts_removed += result.artifacts_removed;
            stats.total_deps_removed += result.deps_removed;
            stats.total_space_freed += result.total_removed;
        }

        try results.append(allocator, result);
    }

    return .{ .results = results, .stats = stats };
}

/// Print cleanup report
fn printCleanupReport(
    config: *const CleanupConfig,
    stats: *const CleanupStats,
    results: []const CleanupResult,
) !void {
    var buf: [64]u8 = undefined;

    print("\n", .{});
    print("============================================================\n", .{});
    if (config.dry_run) {
        print("CLEANUP PREVIEW (DRY RUN)\n", .{});
    } else {
        print("CLEANUP COMPLETE\n", .{});
    }
    print("============================================================\n\n", .{});

    print("Strategy: {s}\n", .{config.strategy.toString()});
    if (config.project_type_filter) |ptype| {
        print("Filter: {s} projects only\n", .{ptype.toString()});
    }
    if (config.inactive_only) {
        print("Mode: Inactive projects only\n", .{});
    }
    if (config.artifacts_only) {
        print("Scope: Build artifacts only\n", .{});
    } else if (config.deps_only) {
        print("Scope: Dependencies only\n", .{});
    }
    print("\n", .{});

    print("Summary:\n", .{});
    print("----------------------------------------\n", .{});
    print("  Projects cleaned:   {d}\n", .{stats.projects_cleaned});
    print("  Projects skipped:   {d}\n", .{stats.projects_skipped});
    print("  Projects failed:    {d}\n\n", .{stats.projects_failed});

    print("Space Freed:\n", .{});
    print("----------------------------------------\n", .{});
    print("  Build artifacts:    {s}\n", .{try formatSize(stats.total_artifacts_removed, &buf)});
    print("  Dependencies:       {s}\n", .{try formatSize(stats.total_deps_removed, &buf)});
    print("  Total:              {s}\n\n", .{try formatSize(stats.total_space_freed, &buf)});

    // Show detailed results if verbose or if there were failures
    if (config.verbose or stats.projects_failed > 0) {
        print("Detailed Results:\n", .{});
        print("----------------------------------------\n", .{});
        for (results) |*result| {
            if (result.error_message) |msg| {
                print("  ❌ {s} ({s}): {s}\n", .{
                    result.project_name,
                    result.project_type.toString(),
                    msg,
                });
            } else if (config.verbose and result.total_removed > 0) {
                const size_str = try formatSize(result.total_removed, &buf);
                print("  ✓ {s} ({s}): {s}\n", .{
                    result.project_name,
                    result.project_type.toString(),
                    size_str,
                });
            }
        }
        print("\n", .{});
    }

    print("============================================================\n", .{});

    if (config.dry_run and stats.total_space_freed > 0) {
        print("\nTo perform actual cleanup, run without --dry-run flag\n", .{});
    }
}

/// Execute cleanup command
fn executeCleanup(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var config = CleanupConfig{};
    var inactive_days: u32 = 180;
    var workspace_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            print("{s}", .{workspace_help_text});
            return;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dry-run")) {
            config.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--strategy")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --strategy");
                return error.MissingArgument;
            }
            config.strategy = CleanupStrategy.fromString(args[i]) orelse {
                printError("Invalid strategy. Use: conservative, moderate, or aggressive");
                return error.InvalidStrategy;
            };
        } else if (std.mem.eql(u8, arg, "--project-type")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --project-type");
                return error.MissingArgument;
            }
            const type_str = args[i];
            if (std.mem.eql(u8, type_str, "nodejs")) {
                config.project_type_filter = .nodejs;
            } else if (std.mem.eql(u8, type_str, "python")) {
                config.project_type_filter = .python;
            } else if (std.mem.eql(u8, type_str, "rust")) {
                config.project_type_filter = .rust;
            } else if (std.mem.eql(u8, type_str, "zig")) {
                config.project_type_filter = .zig;
            } else if (std.mem.eql(u8, type_str, "go")) {
                config.project_type_filter = .go_lang;
            } else if (std.mem.eql(u8, type_str, "java")) {
                config.project_type_filter = .java;
            } else {
                printError("Invalid project type. Use: nodejs, python, rust, zig, go, or java");
                return error.InvalidProjectType;
            }
        } else if (std.mem.eql(u8, arg, "--inactive-only")) {
            config.inactive_only = true;
        } else if (std.mem.eql(u8, arg, "--artifacts-only")) {
            config.artifacts_only = true;
        } else if (std.mem.eql(u8, arg, "--deps-only")) {
            config.deps_only = true;
        } else if (std.mem.eql(u8, arg, "--inactive-days")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --inactive-days");
                return error.MissingArgument;
            }
            inactive_days = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (arg[0] != '-') {
            if (workspace_path != null) {
                printError("Multiple workspace paths specified");
                return error.TooManyArguments;
            }
            workspace_path = arg;
        }
    }

    if (config.artifacts_only and config.deps_only) {
        printError("Cannot specify both --artifacts-only and --deps-only");
        return error.ConflictingOptions;
    }

    if (workspace_path == null) {
        printError("Missing required workspace path argument");
        print("\n{s}", .{workspace_help_text});
        return error.MissingWorkspacePath;
    }

    try validateDirectory(workspace_path.?);

    if (config.verbose) {
        printInfo("Scanning workspace for cleanup...");
        print("Path: {s}\n", .{workspace_path.?});
        print("Strategy: {s}\n", .{config.strategy.toString()});
        if (config.dry_run) {
            print("Mode: DRY RUN (no actual deletion)\n", .{});
        }
        print("\n", .{});
    }

    // Scan workspace to get project list
    var projects = try scanWorkspace(allocator, workspace_path.?, inactive_days);
    defer {
        for (projects.items) |*proj| {
            allocator.free(proj.name);
            allocator.free(proj.path);
        }
        projects.deinit(allocator);
    }

    // Perform cleanup
    var cleanup_data = try performCleanup(allocator, projects.items, &config);
    defer {
        for (cleanup_data.results.items) |*r| {
            if (r.error_message) |msg| allocator.free(msg);
        }
        cleanup_data.results.deinit(allocator);
    }

    // Print report
    try printCleanupReport(&config, &cleanup_data.stats, cleanup_data.results.items);
}

/// Execute workspace scan command
fn executeScan(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var inactive_days: u32 = 180;
    var verbose = false;
    var workspace_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            print("{s}", .{workspace_help_text});
            return;
        } else if (std.mem.eql(u8, arg, "--inactive-days")) {
            i += 1;
            if (i >= args.len) {
                printError("Missing value for --inactive-days");
                return error.MissingArgument;
            }
            inactive_days = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (arg[0] != '-') {
            if (workspace_path != null) {
                printError("Multiple workspace paths specified");
                return error.TooManyArguments;
            }
            workspace_path = arg;
        }
    }

    if (workspace_path == null) {
        printError("Missing required workspace path argument");
        print("\n{s}", .{workspace_help_text});
        return error.MissingWorkspacePath;
    }

    try validateDirectory(workspace_path.?);

    if (verbose) {
        printInfo("Scanning workspace...");
        print("Path: {s}\n", .{workspace_path.?});
        print("Inactive threshold: {d} days\n\n", .{inactive_days});
    }

    var projects = try scanWorkspace(allocator, workspace_path.?, inactive_days);
    defer {
        for (projects.items) |*proj| {
            allocator.free(proj.name);
            allocator.free(proj.path);
        }
        projects.deinit(allocator);
    }

    var stats = try generateStats(allocator, projects.items);
    defer stats.deinit();

    try printReport(&stats, projects.items, workspace_path.?);

    if (verbose) {
        print("\nScanned {d} directories, found {d} projects\n", .{
            projects.items.len,
            stats.total_projects,
        });
    }
}

/// Execute workspace command
fn executeWorkspace(allocator: std.mem.Allocator, args: []const []const u8, _: *anyopaque) !void {
    if (args.len == 0) {
        print("{s}", .{workspace_help_text});
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "scan")) {
        try executeScan(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "cleanup")) {
        try executeCleanup(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "-h") or std.mem.eql(u8, subcommand, "--help")) {
        print("{s}", .{workspace_help_text});
    } else {
        const err_msg = try std.fmt.allocPrint(allocator, "Unknown subcommand: {s}", .{subcommand});
        defer allocator.free(err_msg);
        printError(err_msg);
        print("\n{s}", .{workspace_help_text});
        return error.UnknownSubcommand;
    }
}

/// Get workspace command
pub fn getCommand() Command {
    return .{
        .name = "workspace",
        .description = "Analyze and manage developer workspace projects",
        .execute_fn = @ptrCast(&executeWorkspace),
        .help_fn = printHelp,
    };
}

fn printHelp() void {
    print("{s}", .{workspace_help_text});
}

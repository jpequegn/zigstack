const std = @import("std");

pub const DateFormat = enum {
    year, // Organize by year only (2023/)
    year_month, // Organize by year and month (2023/01/)
    year_month_day, // Organize by year, month, and day (2023/01/15/)
};

pub const DuplicateAction = enum {
    skip, // Skip duplicate files
    rename, // Rename duplicate files
    replace, // Replace existing files with duplicates
    keep_both, // Keep both files with different names
};

pub const Category = struct {
    description: []const u8,
    extensions: []const []const u8,
    color: []const u8,
    priority: u32,
};

pub const DisplayConfig = struct {
    show_categories: bool = true,
    show_colors: bool = false,
    group_by_category: bool = true,
    sort_categories_by_priority: bool = true,
    show_category_summaries: bool = true,
    show_uncategorized: bool = true,
    uncategorized_label: []const u8 = "Other",
};

pub const BehaviorConfig = struct {
    case_sensitive_extensions: bool = false,
    include_hidden_files: bool = false,
    include_directories: bool = false,
    max_depth: u32 = 1,
};

pub const ConfigData = struct {
    version: []const u8,
    categories: std.StringHashMap(Category),
    display: DisplayConfig,
    behavior: BehaviorConfig,

    pub fn deinit(self: *ConfigData) void {
        self.categories.deinit();
    }
};

pub const Config = struct {
    // File management flags
    create_directories: bool = false,
    move_files: bool = false,
    dry_run: bool = true,
    verbose: bool = false,

    // Configuration file support
    config_file_path: ?[]const u8 = null,
    data: ?ConfigData = null,

    // Advanced organization options
    organize_by_date: bool = false, // Enable date-based organization
    organize_by_size: bool = false, // Enable size-based organization
    detect_duplicates: bool = false, // Enable duplicate file detection
    recursive: bool = false, // Enable recursive directory processing
    max_depth: u32 = 10, // Maximum recursion depth
    size_threshold_mb: u64 = 100, // Size threshold for large files (MB)
    date_format: DateFormat = .year_month, // Date organization format
    duplicate_action: DuplicateAction = .skip, // Action for duplicate files
};
